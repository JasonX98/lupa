// Lupa 音标服务 — 联网取美/英音标，结果落 phonetic_cache。
// 缓存键三段式 {provider}:{word}:{fmt}；缓存命中 hit_count+1；联网异常抛错不吞。
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/notebook_db.dart';

const String _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

/// 音标获取失败。
class PhoneticFetchError implements Exception {
  final String message;
  const PhoneticFetchError(this.message);
  @override
  String toString() => 'PhoneticFetchError: $message';
}

/// 一次音标查询的结果。
class PhoneticResult {
  final String word;
  final String uk;
  final String us;
  final bool fromCache;
  const PhoneticResult({required this.word, required this.uk, required this.us, required this.fromCache});
}

Future<Map<String, Object?>> _httpGetJson(String url, {Duration timeout = const Duration(seconds: 10)}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url))
      ..headers.set('User-Agent', _userAgent);
    final resp = await req.close().timeout(timeout);
    final body = await resp.transform(utf8.decoder).join();
    return json.decode(body) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

Future<String?> _cacheGet(Database con, String key) async {
  final rows = await con.rawQuery(
    'SELECT phonetic FROM phonetic_cache WHERE cache_key = ?',
    [key],
  );
  if (rows.isEmpty) return null;
  await con.rawUpdate(
    'UPDATE phonetic_cache SET hit_count = hit_count + 1 WHERE cache_key = ?',
    [key],
  );
  return rows.first['phonetic'] as String;
}

Future<void> _cachePut(
  Database con,
  String key,
  String word,
  String provider,
  String fmt,
  String url,
  String phonetic,
) async {
  await con.execute(
    'INSERT INTO phonetic_cache (cache_key, word, provider, fmt, url, phonetic, fetched_at, hit_count) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, 0) '
    'ON CONFLICT(cache_key) DO UPDATE SET '
    'phonetic = excluded.phonetic, url = excluded.url, fetched_at = excluded.fetched_at',
    [key, word, provider, fmt, url, phonetic, DateTime.now().millisecondsSinceEpoch ~/ 1000],
  );
}

/// 联网查音标。返回 {"uk": ..., "us": ...}。失败抛 PhoneticFetchError。
Future<Map<String, String>> fetchOnline(String word, String phoneticUrl) async {
  final Map<String, Object?> data;
  try {
    final url = phoneticUrl.replaceAll('{word}', Uri.encodeQueryComponent(word));
    data = await _httpGetJson(url);
  } catch (e) {
    throw PhoneticFetchError('音标请求失败: $e');
  }

  dynamic entry = (data['simple'] as Map<String, Object?>?)?['word']
      ?? (data['ec'] as Map<String, Object?>?)?['word']
      ?? const [];
  if (entry is List && entry.isNotEmpty) {
    entry = entry.first;
  } else {
    entry = <String, Object?>{};
  }
  final map = (entry as Map).cast<String, Object?>();
  final uk = ((map['ukphone'] as String?) ?? '').trim();
  final us = ((map['usphone'] as String?) ?? '').trim();
  if (uk.isEmpty && us.isEmpty) {
    throw PhoneticFetchError('接口未返回音标: $word');
  }
  return {'uk': uk, 'us': us};
}

/// 查音标：缓存优先，未命中联网并落库。
Future<PhoneticResult> getPhonetic(
  String nbPath,
  String word,
  String phoneticUrl, {
  String provider = 'youdao',
  bool useCache = true,
}) async {
  word = word.trim();
  final ukKey = '$provider:${word.toLowerCase()}:uk';
  final usKey = '$provider:${word.toLowerCase()}:us';

  initDatabaseFactory();
  final con = await databaseFactory.openDatabase(p.absolute(nbPath),
      options: OpenDatabaseOptions(singleInstance: false));
  try {
    String? uk;
    String? us;
    if (useCache) {
      uk = await _cacheGet(con, ukKey);
      us = await _cacheGet(con, usKey);
    }
    if (uk != null && uk.isNotEmpty && us != null && us.isNotEmpty) {
      return PhoneticResult(word: word, uk: uk, us: us, fromCache: true);
    }

    final online = await fetchOnline(word, phoneticUrl);
    uk = (uk != null && uk.isNotEmpty) ? uk : online['uk']!;
    us = (us != null && us.isNotEmpty) ? us : online['us']!;
    await _cachePut(con, ukKey, word, provider, 'uk', phoneticUrl, uk);
    await _cachePut(con, usKey, word, provider, 'us', phoneticUrl, us);
    return PhoneticResult(word: word, uk: uk, us: us, fromCache: false);
  } finally {
    await con.close();
  }
}
