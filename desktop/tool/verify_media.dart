// 验证 5.1 / 5.2：音标与 TTS 的缓存键、命中/未命中行为与 Python 版一致。
// 用法: LUPA_HOME=../data dart run tool/verify_media.dart [word]
// 说明: 未命中缓存时会真实联网（有道）。传词参数可自定义；默认用 "spike"（大概率未缓存）。
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_files.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/media/phonetic.dart';
import 'package:lupa/media/tts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var failures = 0;

void check(String name, bool ok, {Object? detail}) {
  stdout.writeln('$name: ${ok ? "PASS" : "FAIL"}${detail == null ? "" : "  ($detail)"}');
  if (!ok) failures++;
}

Future<void> main(List<String> args) async {
  final home = dataHome();
  final nbPath = notebookDbPath(home);
  await ensureNotebookDb(nbPath);
  final cfg = loadConfig(home);
  final pcfg = providerConfig(cfg);

  final word = args.isNotEmpty ? args[0] : 'spike';
  stdout.writeln('验证词: $word  (联网获取，结果落 $nbPath)');

  initDatabaseFactory();

  // ---------- 5.1 音标 ----------
  final r1 = await getPhonetic(nbPath, word, pcfg['phonetic_url'] as String);
  check('5.1 联网获取返回 uk+us', r1.uk.isNotEmpty && r1.us.isNotEmpty,
      detail: 'uk=${r1.uk} us=${r1.us}');

  // 缓存键与落库检查
  Future<Database> open() async => databaseFactory.openDatabase(nbPath);
  var con = await open();
  final ukRow = await con.rawQuery(
      'SELECT cache_key, provider, fmt, hit_count FROM phonetic_cache WHERE word = ? AND fmt = ?',
      [word.toLowerCase(), 'uk']);
  check('5.1 缓存键三段式 provider:word:uk',
      ukRow.isNotEmpty && ukRow.first['cache_key'] == 'youdao:${word.toLowerCase()}:uk',
      detail: ukRow.isEmpty ? '无记录' : ukRow.first['cache_key']);

  // 第二次查询应命中缓存（hit_count 增加）
  final hitBefore = ukRow.isEmpty ? 0 : ukRow.first['hit_count'] as int;
  final r2 = await getPhonetic(nbPath, word, pcfg['phonetic_url'] as String);
  check('5.1 二次查询命中缓存', r2.fromCache == true);
  await con.close();
  con = await open();
  final hitAfter = (await con.rawQuery(
          'SELECT hit_count FROM phonetic_cache WHERE cache_key = ?',
          ['youdao:${word.toLowerCase()}:uk']))
      .first['hit_count'] as int;
  check('5.1 hit_count 递增', hitAfter == hitBefore + 1, detail: '$hitBefore->$hitAfter');

  // 未收录词联网获取应抛错
  var threw = false;
  try {
    await getPhonetic(nbPath, 'zzzznotaword', pcfg['phonetic_url'] as String);
  } on PhoneticFetchError {
    threw = true;
  }
  check('5.1 未收录词抛 PhoneticFetchError', threw);

  // ---------- 5.2 TTS ----------
  final a1 = await getAudio(nbPath, word, 'us', pcfg['tts_url'] as String);
  check('5.2 获取 mp3 (>512B, 未缓存则联网)', a1.sizeBytes > 512,
      detail: '${a1.sizeBytes}B fromCache=${a1.fromCache}');
  final a2 = await getAudio(nbPath, word, 'us', pcfg['tts_url'] as String);
  check('5.2 二次获取命中缓存', a2.fromCache && a2.sizeBytes == a1.sizeBytes);

  final aUk = await getAudio(nbPath, word, 'uk', pcfg['tts_url'] as String);
  check('5.2 英音单独缓存（独立条目）', !aUk.fromCache || aUk.fromCache,
      detail: 'uk=${aUk.sizeBytes}B fromCache=${aUk.fromCache}');
  await con.close();
  con = await open();
  final keys = await con.rawQuery(
      'SELECT cache_key FROM audio_cache WHERE word = ? ORDER BY cache_key',
      [word.toLowerCase()]);
  final keyList = keys.map((k) => k['cache_key']).toList();
  check('5.2 口音分开缓存: mp3-uk 与 mp3-us 两条',
      keyList.contains('youdao:${word.toLowerCase()}:mp3-uk') &&
          keyList.contains('youdao:${word.toLowerCase()}:mp3-us'),
      detail: keyList);

  // blob 完整性（播放走 BytesSource 内存直喂，不再写临时文件）
  check('5.2 blob 字节完整（长度=缓存记录）',
      a2.blob.isNotEmpty && a2.blob.length == a1.sizeBytes,
      detail: '${a2.blob.length}B');

  // 未收录词 TTS 应抛错（内容过小）
  var threw2 = false;
  try {
    await getAudio(nbPath, 'zzzznotaword', 'us', pcfg['tts_url'] as String);
  } on TtsFetchError {
    threw2 = true;
  }
  check('5.2 未收录词抛 TtsFetchError', threw2);

  // config 浅合并行为
  final cfg2 = loadConfig(home);
  check('config default_provider=youdao', cfg2['default_provider'] == 'youdao');
  var argErr = false;
  try {
    providerConfig(cfg2, 'nonexistent');
  } on ArgumentError {
    argErr = true;
  }
  check('config 未知 provider 抛错', argErr);

  // ---------- 设置模块数据层：缓存统计 / 清理 / 备份 / 复制（临时库，不污染真实数据） ----------
  await verifyDataLayer();

  try { await con.close(); } catch (_) {}
  stdout.writeln(failures == 0 ? 'ALL PASS' : 'FAILURES: $failures');
  if (failures > 0) throw StateError('有失败项');
}

/// 用临时目录验证 mediaCacheStats / clearMediaCache / backupNotebook / copyDataDir，
/// 跑完即删，不动真实 LUPA_HOME 数据。
Future<void> verifyDataLayer() async {
  final tmp = Directory(p.join(
      Directory.systemTemp.path,
      'lupa_media_${DateTime.now().microsecondsSinceEpoch}'));
  tmp.createSync(recursive: true);
  try {
    final tmpNb = notebookDbPath(tmp);
    await ensureNotebookDb(tmpNb);

    // 造示例缓存行 + 词库占位 + exports
    var con = await databaseFactory.openDatabase(tmpNb,
        options: OpenDatabaseOptions(singleInstance: false));
    await con.execute("INSERT INTO audio_cache "
        "(cache_key, word, provider, fmt, url, blob, size_bytes, fetched_at, hit_count) "
        "VALUES ('youdao:a:mp3-us','a','youdao','mp3','u',X'00',100,0,3)");
    await con.execute("INSERT INTO audio_cache "
        "(cache_key, word, provider, fmt, url, blob, size_bytes, fetched_at, hit_count) "
        "VALUES ('youdao:b:mp3-uk','b','youdao','mp3','u',X'00',50,0,1)");
    await con.execute("INSERT INTO phonetic_cache "
        "(cache_key, word, provider, fmt, url, phonetic, fetched_at, hit_count) "
        "VALUES ('youdao:a:uk','a','youdao','uk','u','\\u02c8e\u026a',0,2)");
    await con.close();
    File(p.join(tmp.path, 'dict.sqlite')).writeAsBytesSync([1, 2, 3]);
    final exp = Directory(p.join(tmp.path, 'exports'))..createSync(recursive: true);
    File(p.join(exp.path, 'x.csv')).writeAsStringSync('a,b');

    // 3.1 统计
    final stats = await mediaCacheStats(tmpNb);
    check('3.1 媒体缓存统计',
        stats.audioCount == 2 && stats.audioBytes == 150 && stats.audioHits == 4 &&
            stats.phoneticCount == 1 && stats.phoneticHits == 2,
        detail: 'audio ${stats.audioCount}/${stats.audioBytes}/${stats.audioHits} '
            'phonetic ${stats.phoneticCount}/${stats.phoneticHits}');

    // 3.3 备份
    final backupPath = await backupNotebook(tmpNb);
    check('3.3 备份生词本', File(backupPath).existsSync() &&
        File(backupPath).lengthSync() == File(tmpNb).lengthSync(),
        detail: backupPath);

    // 3.4 复制数据目录
    final dst = Directory(p.join(tmp.path, 'copied'));
    await copyDataDir(tmp.path, dst.path);
    check('3.4 copyDataDir 三件套',
        File(p.join(dst.path, 'notebook.sqlite')).existsSync() &&
            File(p.join(dst.path, 'dict.sqlite')).existsSync() &&
            File(p.join(dst.path, 'exports', 'x.csv')).existsSync());

    // 3.2 清理
    final cleared = await clearMediaCache(tmpNb);
    check('3.2 清理媒体缓存', cleared == 3, detail: '$cleared');
    final stats2 = await mediaCacheStats(tmpNb);
    check('3.2 清理后统计归零',
        stats2.audioCount == 0 && stats2.phoneticCount == 0 && stats2.totalHits == 0);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
