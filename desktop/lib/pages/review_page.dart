// Lupa 复习页（openspec task 7.3）。
// 逐卡答题评分：空格翻面，1234 评分，评分后调度推进（scheduler 固定间隔）。
// 专注模式：居中单列，无其他干扰元素。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lupa/notebook/repo.dart';
import 'package:lupa/notebook/scheduler.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/flip_card.dart';
import 'package:lupa/widgets/word_bits.dart';

class ReviewPage extends StatefulWidget {
  final AppState state;
  final bool isActive; // 由 AppShell 传入：切到本页时触发重载到期队列

  const ReviewPage({super.key, required this.state, required this.isActive});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  bool _loading = true;
  List<NotebookEntry> _queue = const [];
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
  void didUpdateWidget(covariant ReviewPage old) {
    super.didUpdateWidget(old);
    // 从别的页切过来：重拉到期队列，并把焦点要回来
    //（IndexedStack 下页面常驻，搜索框可能一直持有焦点，空格会打进隐藏输入框）
    // requestFocus 必须延后到帧末——didUpdateWidget 处于 build 阶段，
    // build 期发焦点变更会触发 FocusManager 断言
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
      _queue = widget.state.due;
      _index = 0;
      _revealed = false;
      _goodCount = 0;
      _againCount = 0;
      _lastFeedback = null;
      _loading = false;
    });
    // 音标预热：与查词页同源（在线缓存优先），卡背面渐进增强
    widget.state
        .preloadPhonetics(_queue.take(20).map((e) => e.word));
  }

  NotebookEntry? get _current =>
      (_index < _queue.length) ? _queue[_index] : null;

  void _reveal() {
    final card = _current;
    if (card == null || _revealed) return;
    setState(() => _revealed = true);
    // 复习时自动朗读：翻面按默认口音播发音（settings 复习组开关）
    if (widget.state.reviewAutoRead) {
      widget.state.speak(card.word, widget.state.defaultAccent);
    }
  }

  Future<void> _rate(int ease) async {
    final card = _current;
    if (card == null || _submitting || !_revealed) return;
    setState(() => _submitting = true);
    try {
      final (nextIvl, _) = await widget.state.answer(card.cardId, ease);
      if (!mounted) return;
      setState(() {
        if (ease >= 2) {
          _goodCount++;
        } else {
          _againCount++;
        }
        _lastFeedback = '「${card.word}」${
            ease == 1 ? '重新来过' : '下次 $nextIvl 天后见'}';
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

  // ---- 答题界面 ----
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
              // ---- 进度 ----
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
              // ---- 卡片（3D 翻面，空格/点击翻面）----
              FlipCard(
                showBack: _revealed,
                onTap: _revealed ? null : _reveal,
                front: _cardSurface(context, _buildFront(context, card)),
                back: _cardSurface(context, _buildBack(context, card), back: true),
              ),
              const SizedBox(height: 20),
              // ---- 操作区 ----
              _revealed ? _buildRating(context, card) : _buildRevealButton(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// 卡面外观（surface + 1px 描边 + 14px 圆角）。正面居中，背面顶部对齐且可滚动。
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

  Widget _buildFront(BuildContext context, NotebookEntry card) {
    final text = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(card.word,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: wordFontFamily, fontSize: 44,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 18),
      Text('还记得它的意思吗？空格键 显示答案', style: text.bodySmall),
    ]);
  }

  Widget _buildBack(BuildContext context, NotebookEntry card) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(card.word,
              style: TextStyle(
                  fontFamily: wordFontFamily, fontSize: 34,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface)),
        ),
        if (card.phonetic.trim().isNotEmpty ||
            widget.state.phoneticOf(card.word) != null)
          Center(
            // 音标与查词页同源：在线缓存优先，ECDICT 兜底
            child: ListenableBuilder(
              listenable: widget.state,
              builder: (context, _) {
                final ph = displayPhonetic(
                    online: widget.state.phoneticOf(card.word),
                    fallback: card.phonetic);
                return ph.isEmpty
                    ? const SizedBox.shrink()
                    : Text('/$ph/', style: text.bodyMedium);
              },
            ),
          ),
        const SizedBox(height: 16),
        if (card.translation.trim().isNotEmpty)
          Text(card.translation.trim(),
              style: text.bodyLarge!.copyWith(fontSize: 16)),
        if (card.definition.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(card.definition.trim(),
              style: text.bodySmall!.copyWith(fontStyle: FontStyle.italic)),
        ],
        ...exchangeLines(card.exchange).map((line) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${line.$1}  ${line.$2}', style: text.bodyMedium),
            )),
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

  Widget _buildRating(BuildContext context, NotebookEntry card) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(ease == 1 ? '重来' : '+$next 天',
                style: TextStyle(fontSize: 11,
                    color: color ?? Theme.of(context).textTheme.bodySmall!.color)),
          ]),
        ),
      );
    }

    final row = Row(children: [
      ratingButton('忘了', 1, danger: true),
      const SizedBox(width: 8),
      ratingButton('模糊', 2),
      const SizedBox(width: 8),
      ratingButton('记得', 3),
      const SizedBox(width: 8),
      ratingButton('简单', 4),
    ]);
    // 深色下玉青浅底按钮无需特殊处理，此处仅保留结构
    if (isDark) return row;
    return row;
  }

  // ---- 收尾界面 ----
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
          Text(total == 0 ? '没有到期的卡片' : '本轮完成', style: text.titleLarge),
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
          Text('新加入的词随时出现在这里', style: text.bodySmall),
        ],
      ),
    );
  }
}
