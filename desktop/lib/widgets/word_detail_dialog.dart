// 单词详情弹窗 — 生词本点词条目弹出，展示完整词条 + 调度状态 + 朗读。
// 词条内容优先取词典库（DictEntry，含柯林斯/牛津/词频/标签），
// 查不到时回退生词本五段字段（NotebookEntry）。视觉与查词页结果卡同构。
import 'package:flutter/material.dart';

import 'package:lupa/ai/card.dart' show AiCard, AiExample, AiFeature, AiGroup;
import 'package:lupa/ai/enrich.dart' show AiOutcome;
import 'package:lupa/ai/pos.dart';
import 'package:lupa/ai/prompt.dart' show promptVersion;
import 'package:lupa/dict/lemma.dart' show parseExchange;
import 'package:lupa/dict/query.dart';
import 'package:lupa/media/phonetic.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/tag_chip.dart';
import 'package:lupa/widgets/word_bits.dart';

/// 弹出单词详情卡片。
Future<void> showWordDetailDialog(
  BuildContext context,
  AppState state,
  NotebookEntry nb,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => WordDetailDialog(state: state, entry: nb),
  );
}

class WordDetailDialog extends StatefulWidget {
  final AppState state;
  final NotebookEntry entry;

  const WordDetailDialog({super.key, required this.state, required this.entry});

  @override
  State<WordDetailDialog> createState() => _WordDetailDialogState();
}

class _WordDetailDialogState extends State<WordDetailDialog> {
  DictEntry? _dict;
  PhoneticResult? _phonetic;
  bool _loading = true;
  String? _speakingAccent;
  bool _regenerating = false;

  /// 刚刚补齐/重新生成得到的 AI 内容。
  ///
  /// 为什么需要它：[widget.entry] 是**打开弹窗时的不可变快照**。补齐成功后
  /// `replaceAiGroups` 写的是库、`state.refresh()` 刷的是 AppState 的列表，
  /// 两者都不会改变手上这个 `NotebookEntry` 对象 —— 于是弹窗里的
  /// `nb.aiGroups` 仍是空的，用户必须关掉再打开才能看到（实测踩过）。
  /// 这里直接把刚生成的结果拿来渲染，既即时又不必回查。
  AiOutcome? _freshAi;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 词条：词库全量字段；音标：联网增强（离线静默回退生词本自带）。
    try {
      final d = await queryWord(widget.entry.word);
      if (mounted) setState(() => _dict = d);
    } catch (_) {/* 词库查询失败不影响生词本字段展示 */}
    try {
      final p = await widget.state.phonetic(widget.entry.word);
      if (mounted) setState(() => _phonetic = p);
    } catch (_) {/* 离线静默 */}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _speak(String accent) async {
    if (_speakingAccent != null) return;
    setState(() => _speakingAccent = accent);
    try {
      await widget.state.speak(widget.entry.word, accent);
    } catch (_) {
      // 朗读失败（需联网）静默：详情卡是浏览场景，不打断
    } finally {
      if (mounted) setState(() => _speakingAccent = null);
    }
  }

  /// 重新生成 AI 内容（已有内容时才走，先二次确认）。
  Future<void> _regenerate() async {
    final word = widget.entry.word;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成'),
        content: Text('将重新生成「$word」的例句与搭配，并覆盖当前内容。继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重新生成')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runEnrich(word: word, forceRegenerate: true, verb: '重新生成');
  }

  /// 首次补齐 AI 内容（该词尚无例句时）。无需二次确认 —— 没有内容可覆盖。
  Future<void> _enrich() =>
      _runEnrich(word: widget.entry.word, forceRegenerate: false, verb: '补齐');

  /// 补齐与重新生成的共同实现（区别只在是否先删缓存、以及提示文案）。
  ///
  /// 两条路径都会把结果写进**旁表**（不只是缓存）—— 否则生词本里看不到，
  /// 直到下次重新打开详情弹窗。
  Future<void> _runEnrich({
    required String word,
    required bool forceRegenerate,
    required String verb,
  }) async {
    setState(() => _regenerating = true);
    try {
      final e = widget.entry;
      final mode = enrichMode(e.word, e.translation);
      final outcome = await widget.state.enrichWord(
        word: word,
        feature: mode == EnrichMode.full
            ? AiFeature.enrich
            : (mode == EnrichMode.degraded
                ? AiFeature.enrichPlain
                : AiFeature.define),
        expectedPos: parsePos(e.translation),
        knownForms: parseExchange(e.exchange).keys.toList(),
        existingTranslation: e.translation,
        forceRegenerate: forceRegenerate,
      );
      final card = outcome.card;
      if (card != null) {
        // 两侧都写回：缓存已由 enrich 写入，这里更新已保存的旁表
        await replaceAiGroups(widget.state.nbPath, e.noteId, card,
            provider: widget.state.aiProviderName,
            promptVersion: promptVersion);
        await widget.state.refresh();
        // 旁表写成功后才更新本地渲染状态（否则会显示未落库的内容）
        if (mounted) setState(() => _freshAi = outcome);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(card == null
                ? '$verb失败：${outcome.reason}'
                : '已$verb「$word」的例句与搭配')));
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final nb = widget.entry;

    // 词条字段：词典库优先，回退生词本。
    final phoneticText = _displayPhonetic();
    final translation =
        (_dict?.translation.trim().isNotEmpty == true) ? _dict!.translation.trim() : nb.translation.trim();
    final definition = (_dict?.definition.trim().isNotEmpty == true)
        ? _dict!.definition.trim()
        : nb.definition.trim();
    final exchange = _dict?.exchange ?? nb.exchange;
    final tag = _dict?.tag ?? nb.tags;

    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- 标题行：单词 + 音标 + 生词本标记 ----
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nb.word,
                                  style: TextStyle(
                                      fontFamily: wordFontFamily, fontSize: 32,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface)),
                              if (phoneticText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('/$phoneticText/', style: text.bodyMedium),
                              ],
                            ],
                          ),
                        ),
                        Tooltip(
                          message: '已在生词本',
                          child: IconButton(
                            onPressed: null,
                            icon: Icon(Icons.star_rounded,
                                size: 26, color: scheme.primary),
                          ),
                        ),
                      ],
                    ),
                    // ---- 口音朗读 ----
                    Row(children: [
                      for (final (label, accent) in [('英音', 'uk'), ('美音', 'us')])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: OutlinedButton.icon(
                            // 只有正在朗读的按钮禁用+转圈，另一个保持常态外观
                            onPressed: _speakingAccent == accent
                                ? null
                                : () => _speak(accent),
                            icon: _speakingAccent == accent
                                ? const SizedBox(
                                    width: 13, height: 13,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.volume_up, size: 16),
                            label: Text(label, style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    // ---- 标签行：柯林斯 / 牛津 / 词频 / 考试 ----
                    if (_dict != null || nb.source == NoteSource.ai) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (_dict != null)
                            for (final (label, kind) in _badges(_dict!))
                              TagChip(label: label, kind: kind),
                          if (nb.source == NoteSource.ai)
                            const TagChip(
                                label: 'AI 生成', kind: TagKind.plain),
                          for (final t in tagList(tag))
                            TagChip(label: t, kind: TagKind.exam),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    // ---- 释义 ----
                    if (translation.isNotEmpty)
                      Text(translation, style: text.bodyLarge),
                    if (definition.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(definition,
                          style: text.bodySmall!
                              .copyWith(fontStyle: FontStyle.italic)),
                    ],
                    // ---- 词形变化 ----
                    ...exchangeLines(exchange).map((line) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${line.$1}  ${line.$2}',
                              style: text.bodyMedium),
                        )),
                    // ---- AI 例句与搭配（已保存的快照，不重新请求）----
                    // 刚补齐的结果优先于打开时的快照（见 _freshAi 的注释）
                    () {
                      final hasAi = detailHasAi(fresh: _freshAi, entry: nb);
                      if (!hasAi && !widget.state.aiReady) {
                        return const SizedBox.shrink();
                      }
                      return AiSection(
                        outcome: resolveDetailAi(fresh: _freshAi, entry: nb),
                        loading: _regenerating,
                        // 文案不再承诺「点下方」——按钮渲染与否由 AiSection 决定，
                        // 承诺与能力必须绑在一起（曾出现「可点下方补齐」但下方无物）。
                        unavailableReason: hasAi
                            ? null
                            : (widget.state.aiReady
                                ? '该词尚无 AI 例句'
                                : 'AI 未启用'),
                        // 尚无内容 -> 补齐（无需确认）；已有内容 -> 重新生成（先确认）
                        onRequest:
                            (widget.state.aiReady && !hasAi) ? _enrich : null,
                        onRegenerate:
                            (widget.state.aiReady && hasAi) ? _regenerate : null,
                        onGoSettings: widget.state.aiReady
                            ? null
                            : () => widget.state.requestOpenSettings(),
                        defFontSize: widget.state.defFontSize,
                      );
                    }(),
                    const SizedBox(height: 18),
                    // ---- 调度状态 ----
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 4,
                        children: [
                          _SchedItem('到期', dueLabel(nb.cardType, nb.due)),
                          _SchedItem('间隔', '${nb.ivl} 天'),
                          _SchedItem('已复习', '${nb.reps} 次'),
                          _SchedItem('遗忘', '${nb.lapses} 次'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  String _displayPhonetic() {
    // 与查词页/列表同源：在线缓存优先，英美相同时只显示一个，ECDICT 兜底
    return displayPhonetic(
        online: _phonetic,
        fallback: widget.entry.phonetic.trim().isNotEmpty
            ? widget.entry.phonetic
            : (_dict?.phonetic ?? ''));
  }

  List<(String, TagKind)> _badges(DictEntry e) {
    final badges = <(String, TagKind)>[];
    final stars = collinsStars(e.collins);
    if (stars.isNotEmpty) badges.add(('柯林斯 $stars', TagKind.collins));
    if (e.oxford == 1) badges.add(('牛津 3000', TagKind.oxford));
    if (e.frq > 0) badges.add(('词频 #${e.frq}', TagKind.freq));
    return badges;
  }
}

class _SchedItem extends StatelessWidget {
  final String label;
  final String value;
  const _SchedItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: text.bodySmall),
      Text(value,
          style: text.bodySmall!
              .copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

/// 把已保存的旁表快照包成 [AiOutcome]，让详情弹窗与查词页共用同一渲染组件。
///
/// 详情弹窗展示的是**存进库里的那一份**（design D5-1 的「存了什么就看到什么」），
/// 不重新请求 —— 背单词时内容随 API 波动对记忆是负面的。
AiOutcome? aiOutcomeFromNotebook(NotebookEntry nb) {
    if (!nb.hasAi) return null;
    final card = AiCard(
      word: nb.word,
      isKnownWord: true,
      phonetic: nb.phonetic,
      translation: nb.translation,
      definition: nb.definition,
      senses: [
        for (final g in nb.aiSenses)
          AiGroup(
            kind: AiGroup.kindSense,
            label: g.label,
            gloss: g.gloss,
            examples: [
              for (final e in g.examples) AiExample(en: e.en, zh: e.zh)
            ],
          ),
      ],
      collocations: [
        for (final g in nb.aiCollocations)
          AiGroup(
            kind: AiGroup.kindCollocation,
            label: g.label,
            gloss: g.gloss,
            examples: [
              for (final e in g.examples) AiExample(en: e.en, zh: e.zh)
            ],
          ),
      ],
    );
    // 降级内容：label 为空的 sense 组（见 repo 的 _insertAiGroups）
    final plain = card.senses.where((g) => g.label.trim().isEmpty).toList();
    if (plain.isNotEmpty && card.senses.length == plain.length) {
      return AiOutcome(
        card: AiCard(
          word: nb.word,
          isKnownWord: true,
          examples: [
            for (final g in plain) ...g.examples,
          ],
          collocations: card.collocations,
        ),
      );
    }
    return AiOutcome(card: card);
}

/// 详情弹窗该渲染哪一份 AI 内容。
///
/// **刚补齐/重新生成的结果优先于打开弹窗时的快照。**
///
/// 为什么需要这个函数（回归点）：[NotebookEntry] 是不可变的，弹窗打开时拿到
/// 的就是那一刻的快照。补齐成功后 `replaceAiGroups` 写的是库、`state.refresh()`
/// 刷的是 AppState 的列表，两者都不会改变手上的那个对象 —— 于是界面仍是空的，
/// 用户必须关掉弹窗再打开才能看到（实测踩过）。
/// 把它抽成纯函数是为了让这个决策能被快速测到（毫秒级、无网络、无 widget）。
AiOutcome? resolveDetailAi({AiOutcome? fresh, required NotebookEntry entry}) =>
    fresh ?? aiOutcomeFromNotebook(entry);

/// 该词是否已有 AI 内容（含刚补齐但尚未从库里读回的那一次）。
bool detailHasAi({AiOutcome? fresh, required NotebookEntry entry}) =>
    fresh != null || entry.hasAi;
