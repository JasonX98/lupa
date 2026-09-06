// Lupa 词库查询 — 与 Python 版 src/lupa/dict/query.py 行为对齐（纯查询，无 IO 副作用）。
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/data/notebook_db.dart';

/// 一条词条（与 dict.sqlite 的 dict 表一一对应）。
class DictEntry {
  final String word;
  final String sw;
  final String phonetic;
  final String definition; // 英文释义
  final String translation; // 中文释义
  final String pos; // 词性，如 'n:1/v:1'
  final int collins; // 柯林斯星级 0-5
  final int oxford; // 牛津 3000: 0/1
  final String tag; // 标签，如 'zk gk cet4 cet6 ky toefl'
  final int bnc; // BNC 词频排名
  final int frq; // 当代语料库词频排名（越小越高频）
  final String exchange; // 词形变化 'd:xx/p:xx/i:xx/3:xx/s:xx/r:xx/t:xx'
  final String audio;

  const DictEntry({
    required this.word,
    required this.sw,
    required this.phonetic,
    required this.definition,
    required this.translation,
    required this.pos,
    required this.collins,
    required this.oxford,
    required this.tag,
    required this.bnc,
    required this.frq,
    required this.exchange,
    required this.audio,
  });

  factory DictEntry.fromRow(Map<String, Object?> row) => DictEntry(
        word: row['word'] as String,
        sw: row['sw'] as String,
        phonetic: row['phonetic'] as String,
        definition: row['definition'] as String,
        translation: row['translation'] as String,
        pos: row['pos'] as String,
        collins: row['collins'] as int,
        oxford: row['oxford'] as int,
        tag: row['tag'] as String,
        bnc: row['bnc'] as int,
        frq: row['frq'] as int,
        exchange: row['exchange'] as String,
        audio: row['audio'] as String,
      );

  /// 词形变化解析：{'d': 'abandoned', 'p': ..., 'i': ..., '3': ...}
  /// 键含义：d=过去式 p=过去分词 i=现在分词 3=三单 s=复数 r=比较级 t=最高级。
  Map<String, String> get exchanges {
    final result = <String, String>{};
    if (exchange.isEmpty) return result;
    for (final part in exchange.split('/')) {
      final idx = part.indexOf(':');
      if (idx > 0) {
        result[part.substring(0, idx)] = part.substring(idx + 1);
      }
    }
    return result;
  }
}

/// 词库统计：总词数、含音标数、含英解数。
class DictStats {
  final int total;
  final int withPhonetic;
  final int withDefinition;
  const DictStats({required this.total, required this.withPhonetic, required this.withDefinition});

  @override
  String toString() =>
      'DictStats(total: $total, withPhonetic: $withPhonetic, withDefinition: $withDefinition)';
}

/// 打开只读词库连接（调用方负责 close）。
Future<Database> openDict([Directory? home]) async {
  initDatabaseFactory();
  final path = dictDbPath(home);
  if (!File(path).existsSync()) {
    throw FileSystemException('词库不存在，先构建词库', path);
  }
  return databaseFactory.openDatabase(path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
}

/// 按单词精确查询（大小写不敏感）。查不到返回 null。
Future<DictEntry?> queryWord(String word, [Directory? home]) async {
  final db = await openDict(home);
  try {
    final rows = await db.rawQuery(
      'SELECT * FROM dict WHERE word = ? COLLATE NOCASE',
      [word.trim()],
    );
    return rows.isEmpty ? null : DictEntry.fromRow(rows.first);
  } finally {
    await db.close();
  }
}

/// 前缀联想，返回单词列表（frq 升序 = 高频优先）。
Future<List<String>> suggestPrefix(String prefix, {int limit = 10, Directory? home}) async {
  final db = await openDict(home);
  try {
    final rows = await db.rawQuery(
      "SELECT word FROM dict WHERE word LIKE ? || '%' ORDER BY frq ASC LIMIT ?",
      [prefix.trim(), limit],
    );
    return rows.map((r) => r['word'] as String).toList();
  } finally {
    await db.close();
  }
}

/// 词库统计。
Future<DictStats> dictStats([Directory? home]) async {
  final db = await openDict(home);
  try {
    final total = sqfliteFirstInt(
        await db.rawQuery('SELECT COUNT(*) AS c FROM dict'));
    final withPhonetic = sqfliteFirstInt(await db
        .rawQuery("SELECT COUNT(*) AS c FROM dict WHERE phonetic != ''"));
    final withDefinition = sqfliteFirstInt(await db
        .rawQuery("SELECT COUNT(*) AS c FROM dict WHERE definition != ''"));
    return DictStats(
        total: total, withPhonetic: withPhonetic, withDefinition: withDefinition);
  } finally {
    await db.close();
  }
}

int sqfliteFirstInt(List<Map<String, Object?>> rows) => rows.first['c'] as int;
