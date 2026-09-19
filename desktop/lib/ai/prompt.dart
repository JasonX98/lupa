// AI 提示词 —— 纯常量 + 纯函数，无 IO。
//
// 两条硬约束（见 openspec/changes/add-ai-word-enrichment design D10）：
//
// 1) 前缀缓存对齐：DeepSeek 的磁盘缓存按「完整前缀单元」精确匹配、默认开启。
//    因此 messages 里**固定不变的生成规范放 system 且放最前面**，每个词不同的
//    信息放 user。system 段越长，被所有词请求复用的收益越大。所以下面每个
//    system 段都必须**逐字稳定**（有单测守住这一点）。
//
// 2) 一个 feature 对应一个 system 段 = 一个缓存前缀单元。三套提示词各自独立，
//    互不共享前缀；这是 D2 明确接受的代价（换来 prompt_version 生命周期独立）。
//
// 提示词里的输出契约与 lib/ai/card.dart 的解析器是一对：改这里必须同时改解析器，
// 并把 promptVersion 加一（旧缓存靠它失效）。
import 'card.dart';

/// 提示词版本 + 输出结构版本。
///
/// 两者同生共死：改提示词措辞或改输出结构，都必须加一。它写进 ai_cache 的
/// prompt_version 列，用于让旧缓存失效（见 design D2）。
const int promptVersion = 1;

/// 输出契约（三套提示词共用同一段文字，但分别嵌进各自的 system 段）。
///
/// 描述的是 card.dart 实际能解析的字段名，不是理想 schema —— 保持两者一致
/// 比「写一份更漂亮的 schema」重要。
const String _outputContract = '''
你必须只输出一个 JSON 对象，不要输出任何解释、markdown 代码块或多余文字。

字段契约：
- "word": 字符串，词本身（原样返回用户给的词）
- "is_known_word": 布尔，你是否认为这是一个合法的英语单词
- "canonical": 字符串，你认为该词的标准拼写（与输入一致时填同样的值）
- "senses": 数组，每项为 {"pos": 词性缩写, "gloss": 该词性的中文释义, "examples": [{"en": 英文例句, "zh": 中文翻译}]}
- "collocations": 数组，每项为 {"phrase": 英文搭配, "gloss": 搭配的中文释义, "examples": [{"en": 英文例句, "zh": 中文翻译}]}
- "examples": 数组，每项为 {"en": 英文例句, "zh": 中文翻译}（仅在要求不分组时使用）

例句要求：
- 每条例句都必须真的含有该词（或其词形变化），不允许出现不含该词的泛泛句子
- 例句要能体现该词的实际用法，长度 8-18 个词
- 中文翻译要自然，不要逐字直译
''';

/// 词性分组补齐（feature = enrich）的 system 段。
const String enrichSystem = '''
你是一位英语词典编纂者，为中文母语的英语学习者编写词条例句。

任务：为一个已知词性的英语单词，按词性分别给出例句，并给出常用搭配及其例句。

$_outputContract

分组要求：
- 用户会告诉你该词需要覆盖的词性清单。你必须为清单中的**每一个**词性都给出一个 senses 条目
- 每个词性给 1 到 2 条例句；若该词性下有差异较大的义项，给 2 条，否则给 1 条
- 不要给出清单之外的词性
- 每个搭配也要给 1 到 2 条例句
''';

/// 降级补齐（feature = enrich-plain）的 system 段：不分组。
const String enrichPlainSystem = '''
你是一位英语词典编纂者，为中文母语的英语学习者编写词条例句。

任务：为一个英语单词给出通用例句与常用搭配及其例句。

$_outputContract

本次要求：
- 不要按词性分组，senses 留空数组，改用 "examples" 给出 1 到 2 条通用例句
- 这些例句要覆盖该词最常见的用法
- 每个搭配也要给 1 到 2 条例句
''';

/// 整卡生成（feature = define）的 system 段。
const String defineSystem = '''
你是一位英语词典编纂者，为中文母语的英语学习者编写词条。

任务：为一个用户查不到的词生成完整词条。

$_outputContract

本次要求：
- 必须给出 "phonetic"（国际音标，不含斜杠）、"translation"（中文释义，每行以词性缩写开头，如 "n. 记录"）、"definition"（英文释义）
- 必须给出 "pos"：该词所有词性的缩写清单，且 senses 必须覆盖 pos 里的每一个词性
- 每个词性给 1 到 2 条例句，每个搭配也要给 1 到 2 条例句
- 如果这不是一个合法的英语单词（拼写错误、非英语、或纯符号），把 "is_known_word" 设为 false，其余字段可留空
- 如果它是合法单词但拼写与输入不同（用户打错了），把 "canonical" 填成正确的拼写
''';

/// 取某个 feature 的 system 段。
String systemPromptFor(AiFeature feature) => switch (feature) {
      AiFeature.enrich => enrichSystem,
      AiFeature.enrichPlain => enrichPlainSystem,
      AiFeature.define => defineSystem,
    };

/// 取某个 feature 的 user 段。
///
/// [word] 用户输入；[pos] 本地解析出的词性集合（仅 full 补齐会用到）；
/// [knownForms] 已知词形（让模型知道哪些变形算「含该词」）；[existing] 词库里
/// 已有的释义（帮模型对齐义项，也让它知道该覆盖什么）。
String userPromptFor(
  AiFeature feature,
  String word, {
  List<String> pos = const [],
  List<String> knownForms = const [],
  String existingTranslation = '',
}) {
  final b = StringBuffer('单词：$word\n');
  if (knownForms.isNotEmpty) {
    b.writeln('已知词形变化：${knownForms.join('、')}');
  }
  if (existingTranslation.trim().isNotEmpty) {
    b.writeln('词库已有释义（请对齐这些义项，不要另立无关义项）：');
    b.writeln(existingTranslation.trim());
  }
  if (feature == AiFeature.enrich && pos.isNotEmpty) {
    b.writeln('必须覆盖的词性：${pos.join('、')}');
  }
  return b.toString();
}
