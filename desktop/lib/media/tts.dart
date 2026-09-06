// Lupa TTS 服务 — 有道 dictvoice 音频下载，blob 落 audio_cache。
// 与 Python 版 src/lupa/media/tts.py 行为对齐：
// 缓存键 {provider}:{word}:mp3-{accent}（口音并入 fmt 段，同词英美音分开缓存）。
import 'dart:typed_data';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/notebook_db.dart';

const String _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

/// TTS 获取失败。
class TtsFetchError implements Exception {
  final String message;
  const TtsFetchError(this.message);
  @override
  String toString() => 'TtsFetchError: $message';
}

/// 一次 TTS 查询的结果。
class AudioResult {
  final String word;
  final String accent; // uk / us
  final int sizeBytes;
  final bool fromCache;
  final List<int> blob;
  const AudioResult(this.word, this.accent, this.sizeBytes, this.fromCache, this.blob);
}

/// 口音 -> 有道 dictvoice 的 type 参数。1=英音 2=美音。
String _accentParam(String accent) =>
    switch (accent.toLowerCase()) { 'uk' => '1', 'us' => '2', _ => throw ArgumentError('口音须为 uk/us: $accent') };

Future<List<int>?> _cacheGet(Database con, String key) async {
  final rows = await con.rawQuery(
    'SELECT blob FROM audio_cache WHERE cache_key = ?',
    [key],
  );
  if (rows.isEmpty) return null;
  await con.rawUpdate(
    'UPDATE audio_cache SET hit_count = hit_count + 1 WHERE cache_key = ?',
    [key],
  );
  return rows.first['blob'] as List<int>;
}

Future<void> _cachePut(Database con, String key, String word, String provider,
    String url, List<int> blob) async {
  await con.execute(
    "INSERT INTO audio_cache (cache_key, word, provider, fmt, url, blob, size_bytes, fetched_at, hit_count) "
    "VALUES (?, ?, ?, 'mp3', ?, ?, ?, ?, 0) "
    'ON CONFLICT(cache_key) DO UPDATE SET '
    'blob = excluded.blob, url = excluded.url, size_bytes = excluded.size_bytes, '
    'fetched_at = excluded.fetched_at',
    [
      key,
      word,
      provider,
      url,
      Uint8List.fromList(blob),
      blob.length,
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ],
  );
}

/// 联网取发音 mp3。失败抛 TtsFetchError。
Future<List<int>> fetchOnline(String word, String accent, String ttsUrl,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final url = ttsUrl
      .replaceAll('{word}', Uri.encodeQueryComponent(word))
      .replaceAll('{accent}', _accentParam(accent));
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url))
      ..headers.set('User-Agent', _userAgent);
    final HttpClientResponse resp;
    try {
      resp = await req.close().timeout(timeout);
    } catch (e) {
      throw TtsFetchError('TTS 请求失败: $e');
    }
    final blob = await resp.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    // dictvoice 对未收录词可能返回极小空响应
    if (blob.length < 512) {
      throw TtsFetchError('TTS 返回内容异常（${blob.length} 字节）: $word');
    }
    return blob;
  } finally {
    client.close();
  }
}

/// 取发音：缓存优先，未命中联网并落库。accent = uk / us。
Future<AudioResult> getAudio(
  String nbPath,
  String word,
  String accent,
  String ttsUrl, {
  String provider = 'youdao',
  bool useCache = true,
}) async {
  word = word.trim();
  accent = accent.toLowerCase();
  // 同词英美音分开缓存：口音并入 fmt 段（如 youdao:abandon:mp3-us）
  final key = '$provider:${word.toLowerCase()}:mp3-$accent';

  initDatabaseFactory();
  final con = await databaseFactory.openDatabase(p.absolute(nbPath));
  try {
    if (useCache) {
      final blob = await _cacheGet(con, key);
      if (blob != null && blob.isNotEmpty) {
        return AudioResult(word, accent, blob.length, true, blob);
      }
    }
    final blob = await fetchOnline(word, accent, ttsUrl);
    final url = ttsUrl
        .replaceAll('{word}', word)
        .replaceAll('{accent}', _accentParam(accent));
    await _cachePut(con, key, word, provider, url, blob);
    return AudioResult(word, accent, blob.length, false, blob);
  } finally {
    await con.close();
  }
}
