// Lupa 词性解析 —— 纯函数，无 IO / 无 UI / 无 AI。
//
// 词性集合的来源是 dict.translation 的逐行前缀，而**不是** dict.pos 字段：
//   - translation 前缀是 ECDICT 缩写体系（vt./n./a./...），与用户看到的释义行
//     同源，因此「用户看到 4 行释义」与「返回 4 组例句」天然对齐
//   - pos 字段是 WordNet 单字母体系（n/j/v/r/...），两套体系互不对应：
//       serene   pos='j:100'                translation='a. 宁静的...'
//       present  pos='n:15/r:4/j:31/v:50'   translation 有 'a.' 但没有 'j.'
//     拿 pos 去校验必然错配（见 openspec/changes/add-ai-word-enrichment design D4）。
//
// 白名单由 3 万词库全量统计得出 —— 注意最长的 token 是 6 个字母（interj.），
// 按「1..4 字母」的正则会漏掉它。
//
// 已知数据瑕疵（刻意不收）：floodwaters 的 translation 以 'na.' 开头，疑似 'n.'
// 的录入错误，全库计数 1。未在词库中出现过的 token 不配被当成词性。

/// translation 行前缀的词性缩写白名单（全量统计共 18 种）。
const Set<String> posWhitelist = <String>{
  'n.', 'a.', 'vt.', 'vi.', 'adv.', 'v.', 'prep.', 'pron.', 'interj.',
  'num.', 'conj.', 'abbr.', 'int.', 'pl.', 'aux.', 'vbl.', 'art.', 'pref.',
};

/// 行首「字母 + 句点」token。上限 6 个字母（interj. 是最长的合法 token）。
final RegExp _leadingToken = RegExp(r'^([A-Za-z]{1,6})\.');

/// 从词库释义解析词性集合：逐行取前缀、命中白名单才收、保序去重。
///
/// 空白行与「无词性前缀」的行（如 `[计] 因特网`、`先生`）直接跳过 —— 后者正是
/// 「0 组」的来源。大小写不折叠：词库数据全为小写，严格匹配使白名单契约可审计。
List<String> parsePos(String translation) {
  final out = <String>[];
  for (final raw in translation.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = _leadingToken.firstMatch(line);
    if (m == null) continue;
    final token = '${m.group(1)!}.';
    if (!posWhitelist.contains(token)) continue;
    if (!out.contains(token)) out.add(token);
  }
  return out;
}

/// 该词该如何补齐 AI 内容。
///
/// - [full]：释义解析出 ≥1 个词性 -> 按词性分组补齐，词性集合作为硬约束下发
/// - [degraded]：解析不出词性、但词形全为小写 -> 视为内容词，降级为不分组的通用
///   例句与搭配（如 `online` 的释义只有 `[计] 联机`，而它恰恰最需要例句）
/// - [none]：解析不出词性、且词形含大写 -> 视为缩写或专名，不补齐、**不发起请求**
///   （如 `Mr` / `TV` / `DNA`，模型不该给它们编一个词性）
///
/// 实测构成：3 万词中 full 28492、degraded 1417、none 91。
///
/// 调用方契约（重要）：
///   词库命中 -> 用 [enrichMode] 选 AiFeature.enrich / enrichPlain，`none` 则不请求
///   词库未命中 -> 直接用 AiFeature.define，**不要**调本函数
enum EnrichMode { full, degraded, none }

/// 判定补齐模式。纯函数，可单测。
///
/// **前提：该词已命中词库。** 词库未命中时没有 `translation` 可解析，此时应走
/// [AiFeature.define]（整卡生成）而不是本函数 —— 否则一个拼错的词会被当成
/// 「小写内容词」走降级补齐，而正确行为是让 define 的自证机制把拼写错误指出来。
EnrichMode enrichMode(String word, String translation) {
  if (parsePos(translation).isNotEmpty) return EnrichMode.full;
  // 含任意大写字母 = 缩写 / 专名。词库里的普通词条全为小写。
  return word.contains(RegExp(r'[A-Z]'))
      ? EnrichMode.none
      : EnrichMode.degraded;
}
