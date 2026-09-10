// Lupa 短语复习页：独立入口 + 独立到期队列（不与单词卡混排）。
// 逐卡答题：空格翻面，1234 评分，评分后复用 scheduler 固定间隔推进。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lupa/notebook/scheduler.dart';
import 'package:lupa/phrase/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/flip_card.dart';
import 'package:lupa/widgets/phrase_bits.dart';

class PhraseReviewPage extends StatefulWidget {
  final AppState state;
  final bool isActive;

  const PhraseReviewPage({
    super.key,
    required this.state,
    required this.isActive,
  });

  @override
  State<PhraseReviewPage> createState() => _PhraseReviewPageState();
}

class _PhraseReviewPageState extends State<PhraseReviewPage> {
  bool _loading = true;
  List<PhraseEntry> _queue = const [];
  int _index = 0;
  bool _revealed = false;
  int _goodCount = 0;
  int _againCount = 0;
  String? _lastFeedback;
  bool _submitting = false;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PhraseReviewPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _reload();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await widget.state.refresh();
    if (!mounted) return;
    setState(() {
      _queue = widget.state.phraseDue;
      _index = 0;
      _revealed = false;
      _goodCount = 0;
      _againCount = 0;
      _lastFeedback = null;
      _loading = false;
    });
  }

  PhraseEntry? get _current => (_index < _queue.length) ? _queue[_index] : null;

  void _reveal() {
    if (_current == null || _revealed) return;
    setState(() => _revealed = true);
  }

  Future<void> _rate(int ease) async {
    final card = _current;
    if (card == null || _submitting || !_revealed) return;
    setState(() => _submitting = true);
    try {
      final (nextIvl, _) = await widget.state.answerPhraseCard(card.id, ease);
      if (!mounted) return;
      setState(() {
        if (ease >= 2) {
          _goodCount++;
        } else {
          _againCount++;
        }
        _lastFeedback = '「${card.phrase}」${ease == 1 ? '重新来过' : '下次 $nextIvl 天后见'}';
        _index++;
        _revealed = false;
        _submitting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('评分失败: $e')));
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_current == null) return KeyEventResult.ignored;
    if (!_revealed) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _reveal();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final easeMap = {
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.numpad4: 4,
    };
    final ease = easeMap[event.logicalKey];
    if (ease != null) {
      _rate(ease);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      autofocus: true,
      child: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : _current == null
              ? _buildDone(context)
              : _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final card = _current!;
    final progress = '${_index + 1} / ${_queue.length}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Text(progress, style: text.bodySmall),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _queue.isEmpty ? 0 : _index / _queue.length,
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (_lastFeedback != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_lastFeedback!, style: text.bodySmall),
                ),
              const SizedBox(height: 32),
              FlipCard(
                showBack: _revealed,
                onTap: _revealed ? null : _reveal,
                // 短语背面字段多（字面/释义/典故/场景/例句），比单词卡高
                height: 460,
                front: _cardSurface(context, _buildFront(context, card)),
                back: _cardSurface(context, _buildBack(context, card), back: true),
              ),
              const SizedBox(height: 20),
              _revealed
                  ? _buildRating(context, card)
                  : _buildRevealButton(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardSurface(BuildContext context, Widget child, {bool back = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(back ? 24 : 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: back
          ? SingleChildScrollView(child: child)
          : Center(child: child),
    );
  }

  Widget _buildFront(BuildContext context, PhraseEntry card) {
    final text = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(card.phrase,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: wordFontFamily,
              fontSize: 40,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface)),
      if (card.lit.trim().isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(card.lit.trim(), style: text.bodySmall),
      ],
      const SizedBox(height: 18),
      Text('还记得它的意思吗？空格键 显示答案', style: text.bodySmall),
    ]);
  }

  Widget _buildBack(BuildContext context, PhraseEntry card) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget section(String title, String body) {
      if (body.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: text.labelSmall!.copyWith(color: scheme.primary)),
          const SizedBox(height: 3),
          Text(body.trim(), style: text.bodyMedium),
        ]),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(card.phrase,
              style: TextStyle(
                  fontFamily: wordFontFamily,
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
        ),
        section('字面', card.lit),
        section('释义', card.meaning),
        section('典故', card.origin),
        section('场景', card.scene),
        if (card.examples.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('例句',
                    style: text.labelSmall!.copyWith(color: scheme.primary)),
                const SizedBox(height: 6),
                for (final ex in card.examples)
                  PhraseExampleView(en: ex.en, zh: ex.zh),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRevealButton(BuildContext context) {
    return SizedBox(
      width: 220,
      child: FilledButton(
        onPressed: _reveal,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('显示答案（空格）', style: TextStyle(fontSize: 15)),
        ),
      ),
    );
  }

  Widget _buildRating(BuildContext context, PhraseEntry card) {
    Widget ratingButton(String label, int ease, {bool danger = false}) {
      final next = nextInterval(card.ivl, ease);
      final color = danger ? Theme.of(context).colorScheme.error : null;
      return Expanded(
        child: OutlinedButton(
          onPressed: _submitting ? null : () => _rate(ease),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ).copyWith(
            side: WidgetStatePropertyAll(BorderSide(
              color: color ?? Theme.of(context).dividerColor,
            )),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$label（$ease）',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(ease == 1 ? '重来' : '+$next 天',
                style: TextStyle(
                    fontSize: 11,
                    color: color ??
                        Theme.of(context).textTheme.bodySmall!.color)),
          ]),
        ),
      );
    }

    return Row(children: [
      ratingButton('忘了', 1, danger: true),
      const SizedBox(width: 8),
      ratingButton('模糊', 2),
      const SizedBox(width: 8),
      ratingButton('记得', 3),
      const SizedBox(width: 8),
      ratingButton('简单', 4),
    ]);
  }

  Widget _buildDone(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = _goodCount + _againCount;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(total == 0 ? Icons.task_alt : Icons.celebration_outlined,
              size: 48, color: scheme.primary),
          const SizedBox(height: 14),
          Text(total == 0 ? '没有到期的短语' : '本轮完成', style: text.titleLarge),
          const SizedBox(height: 8),
          if (total > 0)
            Text('共 $total 张 · 记得 $_goodCount · 忘了 $_againCount',
                style: text.bodyMedium),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('刷新队列'),
          ),
          const SizedBox(height: 6),
          Text('新收录的短语随时出现在这里', style: text.bodySmall),
        ],
      ),
    );
  }
}
