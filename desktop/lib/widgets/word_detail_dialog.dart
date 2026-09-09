// 单词详情弹窗 — 生词本点词条目弹出，展示完整词条 + 调度状态 + 朗读。
// 词条内容优先取词典库（DictEntry，含柯林斯/牛津/词频/标签），
// 查不到时回退生词本五段字段（NotebookEntry）。视觉与查词页结果卡同构。
import 'package:flutter/material.dart';

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
                    if (_dict != null) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (label, kind) in _badges(_dict!))
                            TagChip(label: label, kind: kind),
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
