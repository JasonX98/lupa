// Lupa 查词页（openspec task 7.1）。
// 前缀联想 + 精确查询 + 音标/释义/词形/标签 + 收藏 + 美英朗读。
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lupa/dict/query.dart';
import 'package:lupa/media/phonetic.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/tag_chip.dart';
import 'package:lupa/widgets/word_bits.dart';

class SearchPage extends StatefulWidget {
  final AppState state;
  final bool isActive; // 由 AppShell 传入：切回本页时把焦点还给搜索框

  const SearchPage({super.key, required this.state, this.isActive = true});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  List<String> _suggestions = const [];
  DictEntry? _entry;
  PhoneticResult? _phonetic;
  bool _loading = false;
  String? _speakingAccent; // 正在朗读的口音（us/uk），null = 空闲
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void didUpdateWidget(covariant SearchPage old) {
    super.didUpdateWidget(old);
    // 从别的页切回来：焦点还给搜索框（否则焦点留在隐藏页，打字无响应）。
    // requestFocus 延后到帧末——didUpdateWidget 处于 build 阶段，
    // build 期发焦点变更会触发 FocusManager 断言
    if (widget.isActive && !old.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      final v = value.trim();
      if (v.isEmpty) {
        if (mounted) setState(() => _suggestions = const []);
        return;
      }
      try {
        final s = await suggestPrefix(v, limit: 8);
        if (mounted && _ctrl.text.trim() == v) setState(() => _suggestions = s);
      } catch (_) {/* 联想失败静默，不打断输入 */}
    });
  }

  Future<void> _submit([String? word]) async {
    final w = (word ?? _ctrl.text).trim();
    if (w.isEmpty) return;
    _ctrl.text = w;
    _ctrl.selection = TextSelection.collapsed(offset: w.length);
    setState(() {
      _loading = true;
      _error = null;
      _suggestions = const [];
      _entry = null;
      _phonetic = null;
    });
    try {
      final e = await queryWord(w);
      if (!mounted) return;
      if (e == null) {
        setState(() {
          _loading = false;
          _error = '词库中没有「$w」— 试试别的拼写，或检查数据目录 lupa_data/dict.sqlite';
        });
        return;
      }
      setState(() => _loading = false);
      _ctrl.text = e.word; // 回写词库标准拼写
      _ctrl.selection = TextSelection.collapsed(offset: e.word.length);
      _entry = e;
      _focus.requestFocus();
      _loadPhonetic(e.word);
    } catch (err) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '查询失败: $err';
        });
      }
    }
  }

  Future<void> _loadPhonetic(String word) async {
    try {
      final p = await widget.state.phonetic(word);
      if (mounted) setState(() => _phonetic = p);
    } catch (_) {
      // 离线时静默：结果卡片仍展示词库自带 phonetic
    }
  }

  Future<void> _speak(String accent) async {
    if (_entry == null || _speakingAccent != null) return;
    setState(() => _speakingAccent = accent);
    try {
      await widget.state.speak(_entry!.word, accent);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('朗读失败（需联网）: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _speakingAccent = null);
    }
  }

  Future<void> _toggleStar() async {
    final word = _entry!.word;
    if (widget.state.isInNotebook(word)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('移出生词本'),
          content: Text('把「$word」从生词本移出？其复习进度将一并删除。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('移出')),
          ],
        ),
      );
      if (ok != true) return;
      await widget.state.remove(word);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已移出「$word」')));
      }
    } else {
      try {
        await widget.state.add(word);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('已加入生词本「$word」')));
        }
      } on WordNotInDictError {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('该词不在词库中')));
        }
      } on DuplicateWordError {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('「$word」已在生词本')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- 搜索框 ----
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: _onChanged,
                onSubmitted: (_) => _submit(),
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 16, color: scheme.onSurface),
                decoration: const InputDecoration(
                  hintText: '输入单词，回车查询（Ctrl+F 回到这里）',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _loading ? null : () => _submit(),
              child: _loading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('查询'),
            ),
          ]),
          // ---- 联想 ----
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _suggestions)
                    ActionChip(
                      label: Text(s),
                      onPressed: () => _submit(s),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          // ---- 结果区 ----
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _error != null
                    ? _ErrorCard(message: _error!)
                    : _entry == null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 96),
                            child: Column(children: [
                              Icon(Icons.travel_explore, size: 44, color: scheme.outline),
                              const SizedBox(height: 14),
                              Text('查一个词，看清它', style: text.titleLarge),
                              const SizedBox(height: 6),
                              Text('词库 3 万高频词 · 点星收藏 · 星标词可导出 Anki',
                                  style: text.bodySmall),
                            ]),
                          )
                        : ListenableBuilder(
                            listenable: widget.state,
                            builder: (context, _) =>
                                _ResultCard(entry: _entry!, phonetic: _phonetic,
                                  starred: widget.state.isInNotebook(_entry!.word),
                                  speakingAccent: _speakingAccent,
                                  onSpeak: _speak, onToggleStar: _toggleStar,
                                  defFontSize: widget.state.defFontSize,
                                  showEnglish: widget.state.showEnglish),
                          ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: text.bodyMedium)),
      ]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final DictEntry entry;
  final PhoneticResult? phonetic;
  final bool starred;
  final String? speakingAccent; // 正在朗读的口音，只让对应按钮出状态
  final void Function(String accent) onSpeak;
  final VoidCallback onToggleStar;
  final int defFontSize;
  final bool showEnglish;

  const _ResultCard({
    required this.entry,
    required this.phonetic,
    required this.starred,
    required this.speakingAccent,
    required this.onSpeak,
    required this.onToggleStar,
    this.defFontSize = 14,
    this.showEnglish = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final phoneticText = _displayPhonetic();

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- 标题行：单词 + 音标 + 操作 ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.word,
                        style: TextStyle(
                            fontFamily: wordFontFamily, fontSize: 34,
                            fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    if (phoneticText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('/$phoneticText/', style: text.bodyMedium),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: starred ? '移出生词本' : '加入生词本',
                onPressed: onToggleStar,
                icon: Icon(starred ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 28,
                    color: starred ? scheme.primary : scheme.outline),
              ),
            ],
          ),
          // ---- 口音朗读（统一英音在前、美音在后，与生词本详情弹窗一致）----
          Row(children: [
            for (final (label, accent) in const [('英音', 'uk'), ('美音', 'us')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  // 只有正在朗读的按钮禁用+转圈，另一个保持常态外观
                  onPressed: speakingAccent == accent ? null : () => onSpeak(accent),
                  icon: speakingAccent == accent
                      ? const SizedBox(width: 13, height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.volume_up, size: 16),
                  label: Text(label, style: const TextStyle(fontSize: 13)),
                ),
              ),
          ]),
          const SizedBox(height: 18),
          // ---- 标签行：柯林斯 / 牛津 / 考试 ----
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, kind) in _badges())
                TagChip(label: label, kind: kind),
              for (final t in tagList(entry.tag))
                TagChip(label: t, kind: TagKind.exam),
            ],
          ),
          const SizedBox(height: 18),
          // ---- 释义 ----
          Text(entry.translation.trim(),
              style: text.bodyLarge!.copyWith(fontSize: defFontSize.toDouble())),
          if (showEnglish && entry.definition.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(entry.definition.trim(),
                style: text.bodySmall!.copyWith(
                    fontStyle: FontStyle.italic,
                    fontSize: (defFontSize - 1.5).clamp(11.0, 16.0).toDouble())),
          ],
          // ---- 词形变化 ----
          ...exchangeLines(entry.exchange).map((line) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${line.$1}  ${line.$2}', style: text.bodyMedium),
              )),
        ],
      ),
    );
  }

  String _displayPhonetic() {
    // 全站同源：在线优先，英美相同时只显示一个，ECDICT 兜底
    return displayPhonetic(online: phonetic, fallback: entry.phonetic);
  }

  List<(String, TagKind)> _badges() {
    final badges = <(String, TagKind)>[];
    final stars = collinsStars(entry.collins);
    if (stars.isNotEmpty) badges.add(('柯林斯 $stars', TagKind.collins));
    if (entry.oxford == 1) badges.add(('牛津 3000', TagKind.oxford));
    if (entry.frq > 0) badges.add(('词频 #${entry.frq}', TagKind.freq));
    return badges;
  }
}


