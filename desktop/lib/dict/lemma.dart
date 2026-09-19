// 本地词形还原 —— 纯函数 + 只读查询，无网络、无 AI、零成本。
//
// 为什么需要它：词库 3 万词是按 frq 裁剪的，大量高频**变形词**不在其中。
// 实测 `dict.exchange` 可反向建索引：24522 词有 exchange，可提取 52036 对
// （变形 -> 原形）；去重后 37521 个变形词形里，有 31597 个（84.2%）自身不在
// 词库 —— `went` / `children` / `bought` / `took` / `mice` / `ran` 全属此类。
//
// 它排在 AI 之前（见 openspec/changes/add-ai-word-enrichment design D3）：
// 用户查 `went` 时，正确答案是「这是 go 的过去式」，而不是让 AI 从零编一张
// `went` 的卡。而且它不依赖 settings.ai.enabled —— 零成本纯收益的能力，
// 绑在 AI 开关后面等于白扔。
//
// 边界：只覆盖屈折变化，不覆盖派生（`serendipitously` 还原不到
// `serendipitous`，因为 ECDICT 的 exchange 里没有它）。派生词仍走 AI。
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 一次词形还原的结果。
class LemmaHit {
  /// 原形（词库中的词）。
  final String lemma;

  /// 命中的词形变化键：d=过去分词 p=过去式 i=现在分词 3=三单 s=复数
  /// r=比较级 t=最高级。同一变形可能同时出现在多个键下（如 `s` 与 `3`
  /// 都是 `abandons`），此时取首个命中的键。
  final String exchangeKey;

  const LemmaHit({required this.lemma, required this.exchangeKey});

  /// 该键的中文说明（与 widgets/word_bits.dart 的 exchangeLabels 同源语义）。
  String get label => exchangeLabels[exchangeKey] ?? exchangeKey;

  /// 键 -> 中文标签。与 widgets/word_bits.dart 的映射保持一致。
  ///
  /// 注意：`d` / `p` 的映射与 ECDICT 的实际约定相反（实测 `go` 的 exchange 为
  /// `p:went/d:gone`，即 p=过去式、d=过去分词）。这是**既有缺陷**，已在本次
  /// 变更的 proposal「顺延」里记为独立 change，此处不顺手改，以免混淆两件事。
  static const Map<String, String> exchangeLabels = {
    'd': '过去式',
    'p': '过去分词',
    'i': '现在分词',
    '3': '三单',
    's': '复数',
    'r': '比较级',
    't': '最高级',
  };
}

/// 解析 `exchange` 字段为 (词形 -> 键) 映射。
///
/// 格式：`d:abandoned/p:abandoned/i:abandoning/3:abandons/s:abandons`，
/// 即 `/` 分段、`:` 分键值，**每段一个值**。
///
/// 全量实测（3 万词）：52051 个段全部为单值，**零逗号、零第二冒号**。
/// 因此这里不实现「值里逗号分隔多词形」——真实数据里不存在的格式不该被
/// 发明出语义（真要出现，应在 tasks 3.6 的全量回归里作为数据不变量被断言到，
/// 而不是在这里靠臆测解析）。
Map<String, String> parseExchange(String exchange) {
  final out = <String, String>{};
  if (exchange.trim().isEmpty) return out;
  for (final seg in exchange.split('/')) {
    final idx = seg.indexOf(':');
    if (idx <= 0) continue;
    final key = seg.substring(0, idx).trim();
    final form = seg.substring(idx + 1).trim().toLowerCase();
    if (key.isEmpty || form.isEmpty) continue;
    out.putIfAbsent(form, () => key); // 首个键优先
  }
  return out;
}

/// 从词库构建逆向词形索引：变形词形（小写） -> 原形。
///
/// 一次全表扫描 + Dart 内建表。3 万词 / 8MB 库，毫秒级。
/// 冲突时保留词频更高（`frq` 更小）的原形 —— `better` 同时是 `good` 与
/// `well` 的比较级，应还原到更常用的那个。
Future<Map<String, String>> buildLemmaIndex(Database db) async {
  final rows = await db.rawQuery(
      "SELECT word, exchange, frq FROM dict WHERE exchange != ''");
  final index = <String, String>{};
  final bestFrq = <String, int>{};
  for (final r in rows) {
    final lemma = ((r['word'] as String?) ?? '').trim();
    if (lemma.isEmpty) continue;
    final frq = (r['frq'] as int?) ?? 0;
    final forms = parseExchange((r['exchange'] as String?) ?? '');
    for (final form in forms.keys) {
      if (form == lemma.toLowerCase()) continue; // 自身不算还原
      final prev = bestFrq[form];
      if (prev == null || _better(frq, prev)) {
        index[form] = lemma;
        bestFrq[form] = frq;
      }
    }
  }
  return index;
}

/// frq 越小越高频；0 表示无频率数据（视为最差，让有数据的胜出）。
bool _better(int a, int b) {
  if (a == 0) return false;
  if (b == 0) return true;
  return a < b;
}

/// 查词形还原。**精确命中优先**：词本身在词库里时返回 null，让调用方走精确查词。
///
/// [db] 是只读词库连接；[word] 是用户输入。返回 null 表示「还原不了」。
Future<LemmaHit?> lookupLemma(Database db, String word,
    {Map<String, String>? index}) async {
  final w = word.trim();
  if (w.isEmpty) return null;

  // 精确命中优先（spec：`better` 直接展示自身词条，不报为 good 的比较级）
  final exact = await db.rawQuery(
      'SELECT word FROM dict WHERE word = ? COLLATE NOCASE LIMIT 1', [w]);
  if (exact.isNotEmpty) return null;

  final idx = index ?? await buildLemmaIndex(db);
  final lemma = idx[w.toLowerCase()];
  if (lemma == null) return null;

  // 取该原形的 exchange 以回报命中的键
  final rows = await db.rawQuery(
      'SELECT exchange FROM dict WHERE word = ? COLLATE NOCASE LIMIT 1', [lemma]);
  final key = rows.isEmpty
      ? ''
      : (parseExchange((rows.first['exchange'] as String?) ?? '')[w.toLowerCase()] ??
          '');
  return LemmaHit(lemma: lemma, exchangeKey: key);
}
