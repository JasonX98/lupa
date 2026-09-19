// 本地词形还原测试：纯函数部分走单测，索引部分用内存库（不依赖真实词库）。
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/dict/lemma.dart';

/// 造一个只含 word/exchange/frq 的内存词库（形状与 dict.sqlite 一致）。
Future<Database> _memDict(List<(String, String, int)> rows) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('''
    CREATE TABLE dict (
      word TEXT PRIMARY KEY, sw TEXT NOT NULL DEFAULT '',
      phonetic TEXT NOT NULL DEFAULT '', definition TEXT NOT NULL DEFAULT '',
      translation TEXT NOT NULL DEFAULT '', pos TEXT NOT NULL DEFAULT '',
      collins INTEGER NOT NULL DEFAULT 0, oxford INTEGER NOT NULL DEFAULT 0,
      tag TEXT NOT NULL DEFAULT '', bnc INTEGER NOT NULL DEFAULT 0,
      frq INTEGER NOT NULL DEFAULT 0, exchange TEXT NOT NULL DEFAULT '',
      audio TEXT NOT NULL DEFAULT '')
  ''');
  for (final (w, ex, frq) in rows) {
    await db.rawInsert(
        'INSERT INTO dict (word, exchange, frq) VALUES (?, ?, ?)', [w, ex, frq]);
  }
  return db;
}

void main() {
  group('parseExchange', () {
    test('解析 go 的 exchange', () {
      expect(parseExchange('i:going/p:went/d:gone/3:goes/s:goes'),
          {'going': 'i', 'went': 'p', 'gone': 'd', 'goes': '3'});
    });

    test('每段一个值（实测 52051 段全部单值，无逗号分隔）', () {
      // 真实数据里的「同词形多键」长这样：3 与 s 共用 abandons
      expect(parseExchange('3:abandons/s:abandons'), {'abandons': '3'});
      // 逗号不是分隔符（真实数据零逗号）；值里带逗号时整段作为一词形
      expect(parseExchange('d:abandoned,p:abandoned'),
          {'abandoned,p:abandoned': 'd'});
    });

    test('同一词形出现在多个键下时取首个', () {
      expect(parseExchange('3:abandons/s:abandons'), {'abandons': '3'});
    });

    test('空串与畸形段被忽略', () {
      expect(parseExchange(''), isEmpty);
      expect(parseExchange('   '), isEmpty);
      expect(parseExchange('nocolon/alsobad'), isEmpty);
      expect(parseExchange('d:/p:x'), {'x': 'p'});
      expect(parseExchange(':x'), isEmpty); // 空键
    });

    test('统一小写', () {
      expect(parseExchange('d:Abandoned'), {'abandoned': 'd'});
    });
  });

  group('buildLemmaIndex', () {
    test('建成 变形 -> 原形 映射', () async {
      final db = await _memDict([
        ('go', 'i:going/p:went/d:gone/3:goes/s:goes', 100),
        ('child', 's:children', 200),
        ('buy', 'p:bought/d:bought/i:buying/3:buys/s:buys', 300),
      ]);
      final idx = await buildLemmaIndex(db);
      expect(idx['went'], 'go');
      expect(idx['gone'], 'go');
      expect(idx['children'], 'child');
      expect(idx['bought'], 'buy');
      await db.close();
    });

    test('原形自身不出现在索引里（避免自我还原）', () async {
      final db = await _memDict([
        ('go', 'i:going/p:went/d:gone/3:goes/s:goes', 100),
      ]);
      final idx = await buildLemmaIndex(db);
      expect(idx.containsKey('go'), isFalse);
      await db.close();
    });

    test('冲突时保留更高频（frq 更小）的原形', () async {
      final db = await _memDict([
        ('well', 'r:better/t:best', 9000),
        ('good', 'r:better/t:best', 50),
      ]);
      final idx = await buildLemmaIndex(db);
      expect(idx['better'], 'good');
      await db.close();
    });

    test('frq 为 0 的一方败给有频率数据的一方', () async {
      final db = await _memDict([
        ('good', 'r:better', 0),
        ('well', 'r:better', 9000),
      ]);
      final idx = await buildLemmaIndex(db);
      expect(idx['better'], 'well');
      await db.close();
    });

    test('无 exchange 的词不参与', () async {
      final db = await _memDict([('serene', '', 1000)]);
      expect(await buildLemmaIndex(db), isEmpty);
      await db.close();
    });
  });

  group('lookupLemma', () {
    test('went -> go，并回报命中的键', () async {
      final db = await _memDict([
        ('go', 'i:going/p:went/d:gone/3:goes/s:goes', 100),
      ]);
      final hit = await lookupLemma(db, 'went');
      expect(hit, isNotNull);
      expect(hit!.lemma, 'go');
      expect(hit.exchangeKey, 'p');
      await db.close();
    });

    test('children -> child', () async {
      final db = await _memDict([('child', 's:children', 200)]);
      expect((await lookupLemma(db, 'children'))!.lemma, 'child');
      await db.close();
    });

    test('bought -> buy', () async {
      final db = await _memDict([
        ('buy', 'p:bought/d:bought/i:buying/3:buys/s:buys', 300),
      ]);
      expect((await lookupLemma(db, 'bought'))!.lemma, 'buy');
      await db.close();
    });

    test('精确命中优先：better 在词库中时不报还原', () async {
      final db = await _memDict([
        ('better', 'r:best', 500),
        ('good', 'r:better/t:best', 50),
      ]);
      expect(await lookupLemma(db, 'better'), isNull);
      await db.close();
    });

    test('大小写不敏感', () async {
      final db = await _memDict([
        ('go', 'i:going/p:went/d:gone/3:goes/s:goes', 100),
      ]);
      expect((await lookupLemma(db, 'WENT'))!.lemma, 'go');
      await db.close();
    });

    test('还原不了时返回 null（派生词不在覆盖范围）', () async {
      final db = await _memDict([
        ('serendipitous', 'r:more serendipitous', 5000),
      ]);
      expect(await lookupLemma(db, 'serendipitously'), isNull);
      await db.close();
    });

    test('空输入返回 null', () async {
      final db = await _memDict([('go', 'p:went', 100)]);
      expect(await lookupLemma(db, ''), isNull);
      expect(await lookupLemma(db, '   '), isNull);
      await db.close();
    });

    test('传入已建索引时结果一致（免去重复建索引）', () async {
      final db = await _memDict([
        ('go', 'i:going/p:went/d:gone/3:goes/s:goes', 100),
      ]);
      final idx = await buildLemmaIndex(db);
      expect((await lookupLemma(db, 'went', index: idx))!.lemma, 'go');
      await db.close();
    });
  });

  group('LemmaHit.label', () {
    test('键映射到中文标签', () {
      expect(const LemmaHit(lemma: 'go', exchangeKey: 'p').label, '过去分词');
      expect(const LemmaHit(lemma: 'child', exchangeKey: 's').label, '复数');
      expect(const LemmaHit(lemma: 'good', exchangeKey: 'r').label, '比较级');
    });

    test('未知键回退为键本身', () {
      expect(const LemmaHit(lemma: 'x', exchangeKey: 'zz').label, 'zz');
    });
  });
}
