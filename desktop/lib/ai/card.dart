// AI 词卡模型与校验 —— 纯函数，无 IO / 无 UI / 无网络。
//
// 职责边界：本文件只负责「把模型返回的 JSON 解析成结构」与「判定这份结构是否
// 可用」。不负责请求、不负责缓存、不负责提示词（分别见 client.dart / repo.dart /
// prompt.dart），也不负责「校验失败之后怎么办」（见 enrich.dart）。
//
// 校验分五类，各自生效的模式不同（见 design D4）：
//   L1 结构     所有模式：字段齐全、类型正确、至少有一条例句
//   L2 覆盖     full 模式：返回的词性组 ⊇ 本地解析出的词性集合
//   L3 自洽     define 模式：模型自报的词性 ⊆ 它自己的例句分组
//   L4 自证     define 模式：独立函数 selfProofOf（对应 spec 的「拒绝非英语词」
//               与「提示标准拼写」两个用户可见结果，**不触发修复重试**）
//   L5 例句含词  所有模式：每条例句必须含该词或其已知词形
import 'dart:convert';

/// AI 产物的种类。缓存键的 feature 段与提示词的选择都由它决定。
enum AiFeature {
  /// 词库命中且解析出词性 -> 按词性分组补齐
  enrich('enrich'),

  /// 词库命中但解析不出词性、且是内容词 -> 降级为不分组的通用例句
  enrichPlain('enrich-plain'),

  /// 词库未命中 -> 生成整卡
  define('define');

  const AiFeature(this.cacheFeature);
  final String cacheFeature;

  /// 是否要求按词性分组（只有 full 补齐与整卡要求分组）。
  bool get requiresPosGroups => this != AiFeature.enrichPlain;
}

/// 一条例句。
class AiExample {
  final String en;
  final String zh;
  const AiExample({required this.en, required this.zh});

  @override
  String toString() => 'AiExample($en / $zh)';
}

/// 一组内容：词性组（`n.` / `vt.`）或搭配组（`record a video`）。
///
/// 对应数据库的 `word_ai_groups` + `word_ai_examples`（见 design D1）。
class AiGroup {
  /// `sense`（词性组）或 `collocation`（搭配组）。
  final String kind;

  /// 词性组取 `n.` / `vt.`；搭配组取搭配本身（`record a video`）。
  final String label;

  /// 词性组取该词性的中文释义；搭配组取搭配的中文释义。
  final String gloss;

  final List<AiExample> examples;

  const AiGroup({
    required this.kind,
    required this.label,
    required this.gloss,
    required this.examples,
  });

  bool get isSense => kind == kindSense;
  bool get isCollocation => kind == kindCollocation;

  static const String kindSense = 'sense';
  static const String kindCollocation = 'collocation';
}

/// 一张 AI 词卡。
class AiCard {
  final String word;

  /// 模型认为的标准拼写。与 [word] 不一致时提示用户（见 [selfProofOf]）。
  final String canonical;

  /// 模型是否认为这是一个合法英语单词。
  final bool isKnownWord;

  /// 词库未命中时由模型给出的音标与释义（词库命中时留空，界面用词库的）。
  final String phonetic;
  final String translation;
  final String definition;

  /// 模型自报的词性列表（仅 define 用，用于 L3 自洽校验）。
  final List<String> pos;

  /// 不分组的通用例句（仅降级补齐用）。
  final List<AiExample> examples;

  /// 按词性分组的例句（full 与 define）。
  final List<AiGroup> senses;

  /// 搭配及其例句。
  final List<AiGroup> collocations;

  const AiCard({
    required this.word,
    this.canonical = '',
    this.isKnownWord = true,
    this.phonetic = '',
    this.translation = '',
    this.definition = '',
    this.pos = const [],
    this.examples = const [],
    this.senses = const [],
    this.collocations = const [],
  });

  /// 全部例句（用于 L5 与「至少一条」判定）。
  Iterable<AiExample> get allExamples sync* {
    yield* examples;
    for (final g in senses) {
      yield* g.examples;
    }
    for (final g in collocations) {
      yield* g.examples;
    }
  }

  /// 按词性分组的组标签集合（L2 / L3 用）。
  Set<String> get senseLabels =>
      senses.map((g) => g.label.trim()).where((l) => l.isNotEmpty).toSet();
}

/// 解析结果：成功时 [card] 非空，失败时 [error] 说明原因。
class AiParseOutcome {
  final AiCard? card;
  final String? error;
  const AiParseOutcome.ok(this.card) : error = null;
  const AiParseOutcome.fail(this.error) : card = null;
  bool get ok => card != null;
}

/// 解析模型返回的 JSON 文本。**任何输入都不抛异常**，失败以 [AiParseOutcome.fail] 返回。
AiParseOutcome parseAiCard(String raw) {
  final Object? decoded;
  try {
    decoded = json.decode(raw);
  } catch (e) {
    return AiParseOutcome.fail('不是合法 JSON: $e');
  }
  if (decoded is! Map) return const AiParseOutcome.fail('顶层不是对象');
  final map = decoded.cast<String, Object?>();

  final word = _str(map['word']);
  if (word.isEmpty) return const AiParseOutcome.fail('缺少 word');

  return AiParseOutcome.ok(AiCard(
    word: word,
    canonical: _str(map['canonical']),
    isKnownWord: _bool(map['is_known_word'], fallback: true),
    phonetic: _str(map['phonetic']),
    translation: _str(map['translation']),
    definition: _str(map['definition']),
    pos: _strList(map['pos']),
    examples: _examples(map['examples']),
    senses: _groups(map['senses'], AiGroup.kindSense),
    collocations: _groups(map['collocations'], AiGroup.kindCollocation),
  ));
}

String _str(Object? v) => v is String ? v.trim() : (v == null ? '' : '$v'.trim());

bool _bool(Object? v, {required bool fallback}) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
  }
  return fallback;
}

List<String> _strList(Object? v) {
  if (v is! List) return const [];
  return v.map(_str).where((s) => s.isNotEmpty).toList();
}

List<AiExample> _examples(Object? v) {
  if (v is! List) return const [];
  final out = <AiExample>[];
  for (final e in v) {
    if (e is Map) {
      final en = _str(e['en']);
      if (en.isEmpty) continue; // 空例句无意义，丢弃而非整体失败
      out.add(AiExample(en: en, zh: _str(e['zh'])));
    } else if (e is String && e.trim().isNotEmpty) {
      // 容忍模型把例句写成纯字符串数组
      out.add(AiExample(en: e.trim(), zh: ''));
    }
  }
  return out;
}

List<AiGroup> _groups(Object? v, String kind) {
  if (v is! List) return const [];
  final out = <AiGroup>[];
  for (final g in v) {
    if (g is! Map) continue;
    final m = g.cast<String, Object?>();
    // 标签字段名按 kind 容错：词性组用 pos/label，搭配组用 phrase/label
    final label = kind == AiGroup.kindCollocation
        ? (_str(m['phrase']).isNotEmpty ? _str(m['phrase']) : _str(m['label']))
        : (_str(m['pos']).isNotEmpty ? _str(m['pos']) : _str(m['label']));
    if (label.isEmpty) continue;
    out.add(AiGroup(
      kind: kind,
      label: label,
      gloss: _str(m['gloss']).isNotEmpty ? _str(m['gloss']) : _str(m['meaning']),
      examples: _examples(m['examples']),
    ));
  }
  return out;
}

// ---- 校验 ----

/// 校验失败的类别。
enum AiViolationKind {
  structure, // L1
  coverage, // L2
  selfConsistency, // L3
  exampleMissingWord, // L5
}

class AiViolation {
  final AiViolationKind kind;
  final String message;
  const AiViolation(this.kind, this.message);
  @override
  String toString() => '${kind.name}: $message';
}

class AiValidation {
  final List<AiViolation> violations;
  const AiValidation(this.violations);
  bool get ok => violations.isEmpty;

  /// 是否值得重发一次请求去修复。
  ///
  /// 所有违规都值得修复 —— 自证（L4）不走这里，它由 [selfProofOf] 单独判定，
  /// 因为「这个词拼错了」不是模型写坏了，而是用户输入错了（见 design D3）。
  bool get repairable => violations.isNotEmpty;

  /// 回灌给模型的缺项说明（修复重试用）。
  String get repairHint =>
      violations.map((v) => '- ${v.message}').join('\n');
}

/// 对解析结果执行 L1 / L2 / L3 / L5 校验。
///
/// [feature] 决定哪些层生效；[expectedPos] 是本地解析出的词性集合（L2 用）；
/// [knownForms] 是该词及其已知词形（L5 用，含原形与 exchange 里的各变形）。
AiValidation validateAiCard(
  AiCard card, {
  required AiFeature feature,
  List<String> expectedPos = const [],
  List<String> knownForms = const [],
}) {
  final v = <AiViolation>[];

  // ---- L1 结构 ----
  if (card.word.trim().isEmpty) {
    v.add(const AiViolation(AiViolationKind.structure, '缺少 word'));
  }
  if (feature == AiFeature.define) {
    if (card.translation.isEmpty && card.definition.isEmpty) {
      v.add(const AiViolation(
          AiViolationKind.structure, '整卡缺少释义（translation 与 definition 都为空）'));
    }
    if (card.senses.isEmpty) {
      v.add(const AiViolation(AiViolationKind.structure, '整卡缺少按词性分组的例句'));
    }
  }
  if (feature == AiFeature.enrichPlain) {
    if (card.examples.isEmpty) {
      v.add(const AiViolation(
          AiViolationKind.structure, '降级补齐缺少通用例句（examples 为空）'));
    }
  }
  if (!card.allExamples.any((e) => e.en.trim().isNotEmpty)) {
    v.add(const AiViolation(AiViolationKind.structure, '没有任何例句'));
  }
  for (final g in [...card.senses, ...card.collocations]) {
    if (g.examples.isEmpty) {
      v.add(AiViolation(
          AiViolationKind.structure, '「${g.label}」这一组没有例句'));
    }
  }

  // ---- L2 覆盖（仅 full：本地词性集合是硬约束）----
  if (feature == AiFeature.enrich && expectedPos.isNotEmpty) {
    final got = card.senseLabels;
    final missing = expectedPos.where((p) => !got.contains(p)).toList();
    if (missing.isNotEmpty) {
      v.add(AiViolation(AiViolationKind.coverage,
          '缺少这些词性的例句组：${missing.join('、')}（必须覆盖 ${expectedPos.join('、')}）'));
    }
  }

  // ---- L3 自洽（仅 define：没有本地参照，要求模型自报的词性 ⊆ 它自己的分组）----
  if (feature == AiFeature.define && card.pos.isNotEmpty) {
    final got = card.senseLabels;
    final extra = card.pos.where((p) => !got.contains(p)).toList();
    if (extra.isNotEmpty) {
      v.add(AiViolation(AiViolationKind.selfConsistency,
          '自报词性 ${extra.join('、')} 没有对应的例句组'));
    }
  }

  // ---- L5 例句必须含该词或其已知词形 ----
  final forms = <String>{
    card.word.trim(),
    card.canonical.trim(),
    ...knownForms.map((f) => f.trim()),
  }.where((f) => f.isNotEmpty).toList();
  if (forms.isNotEmpty) {
    final bad = <String>[];
    for (final e in card.allExamples) {
      if (e.en.trim().isEmpty) continue;
      if (!_containsAnyForm(e.en, forms)) bad.add(e.en);
    }
    if (bad.isNotEmpty) {
      v.add(AiViolation(AiViolationKind.exampleMissingWord,
          '这些例句不含「${card.word}」或其词形：${bad.take(2).join(' / ')}'));
    }
  }

  return AiValidation(v);
}

/// 例句是否含该词的任一已知词形。
///
/// 用词边界匹配而非裸 `contains`：短词（`a` / `an`）用裸包含会命中一切。
/// 屈折变形靠 [knownForms] 传入（词库的 `exchange` 值），而不是靠宽松匹配 ——
/// 这正好让「例句里只有 abandoned、没有 abandon」被判为合格（abandoned 是已知词形）。
bool _containsAnyForm(String sentence, List<String> forms) {
  for (final f in forms) {
    final re = RegExp(r'\b' + RegExp.escape(f) + r'\b', caseSensitive: false);
    if (re.hasMatch(sentence)) return true;
  }
  return false;
}

// ---- L4 自证（define 专用，独立于修复重试）----

/// 模型对「这个输入是不是一个词」的自报结果。
enum SelfProof {
  /// 是合法英语词，且拼写一致 -> 正常展示
  known,

  /// 是词但拼写不同 -> 提示「你是不是想查 X」
  misspelled,

  /// 看起来不是英语词 -> 不展示词卡
  notAWord,
}

/// L4 自证判定（仅 define 用）。
///
/// 单独于 [validateAiCard]：这两条对应 spec 里两个**用户可见的结果**，不是
/// 「让模型重写一遍」就能解决的（用户打错字，重发请求只会再编一次）。
SelfProof selfProofOf(AiCard card, String input) {
  if (!card.isKnownWord) return SelfProof.notAWord;
  final canon = card.canonical.trim();
  if (canon.isNotEmpty &&
      canon.toLowerCase() != input.trim().toLowerCase()) {
    return SelfProof.misspelled;
  }
  return SelfProof.known;
}

/// 每组最多保留的例句数（design D4：上限 2 防模型刷量）。
const int maxExamplesPerGroup = 2;

/// 把超出上限的例句截断。**多给不是错误**，只是浪费 token，所以截断而非判失败。
AiCard truncateExamples(AiCard card, {int max = maxExamplesPerGroup}) {
  List<AiExample> cut(List<AiExample> xs) =>
      xs.length <= max ? xs : xs.sublist(0, max);
  List<AiGroup> cutGroups(List<AiGroup> gs) => gs
      .map((g) => AiGroup(
            kind: g.kind,
            label: g.label,
            gloss: g.gloss,
            examples: cut(g.examples),
          ))
      .toList();
  return AiCard(
    word: card.word,
    canonical: card.canonical,
    isKnownWord: card.isKnownWord,
    phonetic: card.phonetic,
    translation: card.translation,
    definition: card.definition,
    pos: card.pos,
    examples: cut(card.examples),
    senses: cutGroups(card.senses),
    collocations: cutGroups(card.collocations),
  );
}
