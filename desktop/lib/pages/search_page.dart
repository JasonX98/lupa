// Lupa 查词页（openspec task 7.1）。
// 前缀联想 + 精确查询 + 音标/释义/词形/标签 + 收藏 + 美英朗读。
//
// 未收录时走三段式（见 specs/desktop-app 的「查词界面」）：
//   1. 本地词形还原（went -> go）—— 零成本、零网络，不依赖 AI 开关
//   2. 生词本回退（词卡存在本地，只是词库没有）
//   3. AI 生成入口（显式，不自动花钱）
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lupa/ai/card.dart' as ai_card;
import 'package:lupa/ai/card.dart' show SelfProof;
import 'package:lupa/ai/enrich.dart' as ai_enrich;
import 'package:lupa/ai/pos.dart';
import 'package:lupa/dict/lemma.dart';
import 'package:lupa/dict/query.dart';
import 'package:lupa/media/phonetic.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/tag_chip.dart';
import 'package:lupa/widgets/word_bits.dart';

/// 未收录时的处理结果（三段式的前两段）。
enum MissKind { lemma, notebook, aiOnly }

class _Miss {
  final MissKind kind;
  final LemmaHit? lemma;
  final NotebookEntry? entry;
  const _Miss(this.kind, {this.lemma, this.entry});
}

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
  // ---- 未收录时的三段式结果 ----
  _Miss? _miss;
  // ---- AI 段落状态 ----
  ai_enrich.AiOutcome? _ai;
  bool _aiLoading = false;
  bool _ai401Notified = false; // 401/403 本次会话只弹一次（spec 要求）

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
        // 合并生词本中匹配前缀的词（词库候选在前 —— 它们经过词库校验）
        final lib = <String>[...s];
        final seen = lib.map((e) => e.toLowerCase()).toSet();
        final extra = <String>[];
        for (final e in widget.state.entries) {
          final w = e.word;
          if (w.toLowerCase().startsWith(v.toLowerCase()) &&
              !seen.contains(w.toLowerCase())) {
            extra.add(w);
          }
        }
        final merged = [...lib, ...extra];
        if (mounted && _ctrl.text.trim() == v) {
          setState(() => _suggestions = merged);
        }
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
      _miss = null;
      _ai = null;
      _aiLoading = false;
    });
    try {
      final e = await queryWord(w);
      if (!mounted) return;
      if (e == null) {
        // 未收录：先试本地词形还原，再试生词本，最后才给 AI 入口
        final miss = await _resolveMiss(w);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _miss = miss;
        });
        return;
      }
      setState(() => _loading = false);
      _ctrl.text = e.word; // 回写词库标准拼写
      _ctrl.selection = TextSelection.collapsed(offset: e.word.length);
      _entry = e;
      _focus.requestFocus();
      _loadPhonetic(e.word);
      _maybeAutoEnrich(e);
    } catch (err) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '查询失败: $err';
        });
      }
    }
  }

  /// 未收录时依次尝试：本地词形还原 -> 生词本回退 -> 只给 AI 入口。
  Future<_Miss> _resolveMiss(String word) async {
    // 1. 本地词形还原（零成本、零网络）
    try {
      final db = await openDict();
      try {
        final hit = await lookupLemma(db, word);
        if (hit != null) return _Miss(MissKind.lemma, lemma: hit);
      } finally {
        await db.close();
      }
    } catch (_) {/* 词库不可用时跳过这一层 */}

    // 2. 生词本回退（AI 生成过的词可能就在这里）
    final key = word.toLowerCase();
    for (final e in widget.state.entries) {
      if (e.word.toLowerCase() == key) {
        return _Miss(MissKind.notebook, entry: e);
      }
    }

    // 3. 都没有：给 AI 入口
    return const _Miss(MissKind.aiOnly);
  }

  /// 词库命中时按需自动补齐（**只在 _submit 后触发**，不在联想防抖里）。
  Future<void> _maybeAutoEnrich(DictEntry e) async {
    final mode = enrichMode(e.word, e.translation);
    if (mode == EnrichMode.none) return; // 缩写/专名：不请求（早退分支，不花钱）
    if (!widget.state.aiReady) return;
    if (!widget.state.aiAutoEnrich) return;
    await _runAi(e, mode);
  }

  /// 手动触发补齐（自动补齐关闭时用）。
  Future<void> _manualEnrich() async {
    final e = _entry;
    if (e == null) return;
    await _runAi(e, enrichMode(e.word, e.translation), forceRegenerate: true);
  }

  Future<void> _runAi(DictEntry e, EnrichMode mode,
      {bool forceRegenerate = false}) async {
    final word = e.word;
    final feature = mode == EnrichMode.full
        ? ai_card.AiFeature.enrich
        : ai_card.AiFeature.enrichPlain;
    setState(() => _aiLoading = true);
    final outcome = await widget.state.loadAiFor(
      word,
      feature: feature,
      expectedPos: parsePos(e.translation),
      knownForms: e.exchanges.values.toList(),
      existingTranslation: e.translation,
      forceRegenerate: forceRegenerate,
    );
    if (!mounted) return;
    // 结果按词校验：用户已改查别的词时丢弃（不渲染）
    if (_ctrl.text.trim().toLowerCase() != word.toLowerCase()) {
      setState(() => _aiLoading = false);
      return;
    }
    setState(() {
      _aiLoading = false;
      if (outcome != null) _ai = outcome;
    });
    _notifyAuthOnce(outcome);
  }

  /// 401/403 本次会话首次出现时额外弹一次，引导去设置（spec 要求）。
  void _notifyAuthOnce(ai_enrich.AiOutcome? outcome) {
    final reason = outcome?.reason ?? '';
    if (!reason.contains('API Key') && !reason.contains('鉴权')) return;
    if (_ai401Notified) return;
    _ai401Notified = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('AI 密钥无效，请到设置 → AI 检查配置'),
      action: SnackBarAction(
        label: '去设置',
        onPressed: () => widget.state.requestOpenSettings(),
      ),
    ));
  }

  /// 未收录词的 AI 生成（define）。
  Future<void> _generateForMiss(String word) async {
    setState(() => _aiLoading = true);
    final outcome = await widget.state.loadAiFor(
      word,
      feature: ai_card.AiFeature.define,
      forceRegenerate: true,
    );
    if (!mounted) return;
    setState(() {
      _aiLoading = false;
      _ai = outcome;
    });
    _notifyAuthOnce(outcome);
  }

  /// 采纳「你是不是想查 X」：改查标准拼写。
  void _acceptCanonical(String canonical) {
    _submit(canonical);
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
          //
          // 必须可滚动：AI 段落是渐进增强的，它让结果卡的内容高度变得不确定
          // （一个 4 词性词的例句+搭配可以很长），固定高度下会 RenderFlex
          // overflow（实测 hoax 溢出 547px）。用 SingleChildScrollView 而
          // 不是 CenteredScrollView —— 结果卡要**顶部对齐**，不要居中。
          Expanded(
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _error != null
                      ? _ErrorCard(message: _error!)
                      : _entry == null
                          ? (_miss != null
                              ? _MissCard(
                                  miss: _miss!,
                                  ai: _ai,
                                  aiLoading: _aiLoading,
                                  aiReady: widget.state.aiReady,
                                  aiEnabled: widget.state.aiEnabled,
                                  hasApiKey: widget.state.aiApiKey.isNotEmpty,
                                  onOpenLemma: _submit,
                                  onOpenNotebookWord: _submit,
                                  onGenerate: _generateForMiss,
                                  onAcceptCanonical: _acceptCanonical,
                                  onGoSettings: () =>
                                      widget.state.requestOpenSettings(),
                                  queryWord: _ctrl.text.trim(),
                                  defFontSize: widget.state.defFontSize,
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(top: 96),
                                  child: Column(children: [
                                    Icon(Icons.travel_explore,
                                        size: 44, color: scheme.outline),
                                    const SizedBox(height: 14),
                                    Text('查一个词，看清它',
                                        style: text.titleLarge),
                                    const SizedBox(height: 6),
                                    Text('词库 3 万高频词 · 点星收藏 · 星标词可导出',
                                        style: text.bodySmall),
                                  ]),
                                ))
                          : ListenableBuilder(
                              listenable: widget.state,
                              builder: (context, _) => _ResultCard(
                                entry: _entry!,
                                phonetic: _phonetic,
                                starred:
                                    widget.state.isInNotebook(_entry!.word),
                                speakingAccent: _speakingAccent,
                                onSpeak: _speak,
                                onToggleStar: _toggleStar,
                                defFontSize: widget.state.defFontSize,
                                showEnglish: widget.state.showEnglish,
                                ai: _ai,
                                aiLoading: _aiLoading,
                                aiReady: widget.state.aiReady,
                                aiAutoEnrich: widget.state.aiAutoEnrich,
                                enrichDisabled: enrichMode(
                                        _entry!.word, _entry!.translation) ==
                                    EnrichMode.none,
                                onEnrich: _manualEnrich,
                                onRegenerate: _manualEnrich,
                                onGoSettings: () =>
                                    widget.state.requestOpenSettings(),
                              ),
                            ),
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

/// 未收录时的卡片：三段式（本地还原 / 生词本回退 / AI 入口）。
class _MissCard extends StatelessWidget {
  final _Miss miss;
  final ai_enrich.AiOutcome? ai;
  final bool aiLoading;
  final bool aiReady;
  final bool aiEnabled;
  final bool hasApiKey;
  final void Function(String word) onOpenLemma;
  final void Function(String word) onOpenNotebookWord;
  final Future<void> Function(String word) onGenerate;
  final void Function(String canonical) onAcceptCanonical;
  final VoidCallback onGoSettings;
  final int defFontSize;

  /// 当前查询框里的词（未收录时就是用户输入的那个）。
  final String queryWord;

  const _MissCard({
    required this.miss,
    required this.ai,
    required this.aiLoading,
    required this.aiReady,
    required this.aiEnabled,
    required this.hasApiKey,
    required this.onOpenLemma,
    required this.onOpenNotebookWord,
    required this.onGenerate,
    required this.onAcceptCanonical,
    required this.onGoSettings,
    required this.queryWord,
    this.defFontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget wrap(List<Widget> children) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );

    // ---- 1. 本地词形还原 ----
    if (miss.kind == MissKind.lemma) {
      final hit = miss.lemma!;
      return wrap([
        Row(children: [
          Icon(Icons.auto_stories_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text('词形变化',
              style: text.labelLarge!.copyWith(color: scheme.primary)),
        ]),
        const SizedBox(height: 12),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: hit.lemma,
              style: TextStyle(
                  fontFamily: wordFontFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
          TextSpan(
              text: '  ${hit.label}',
              style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant)),
        ])),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => onOpenLemma(hit.lemma),
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: Text('查看 ${hit.lemma}'),
        ),
      ]);
    }

    // ---- 2. 生词本回退 ----
    if (miss.kind == MissKind.notebook) {
      final e = miss.entry!;
      return wrap([
        Row(children: [
          Icon(Icons.bookmark_outline, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text('已在生词本（词库未收录）',
              style: text.labelLarge!.copyWith(color: scheme.primary)),
        ]),
        const SizedBox(height: 12),
        Text(e.word,
            style: TextStyle(
                fontFamily: wordFontFamily,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        if (e.phonetic.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('/${e.phonetic}/', style: text.bodyMedium),
        ],
        const SizedBox(height: 12),
        if (e.translation.trim().isNotEmpty)
          Text(e.translation.trim(),
              style: text.bodyLarge!
                  .copyWith(fontSize: defFontSize.toDouble())),
        if (e.definition.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(e.definition.trim(),
              style: text.bodySmall!.copyWith(fontStyle: FontStyle.italic)),
        ],
        ...exchangeLines(e.exchange).map((l) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${l.$1}  ${l.$2}', style: text.bodyMedium),
            )),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => onOpenNotebookWord(e.word),
          icon: const Icon(Icons.search, size: 16),
          label: const Text('重新查询'),
        ),
      ]);
    }

    // ---- 3. 都没有：AI 入口 ----
    final o = ai;
    final card = o?.card;

    // AI 生成了卡片，但自证不通过（拼写错 / 不是词）
    if (o != null && card == null && o.selfProof != null) {
      final isMisspelled = o.selfProof == SelfProof.misspelled;
      final canonical = isMisspelled ? _extractCanonical(o.reason) : '';
      return wrap([
        Row(children: [
          Icon(isMisspelled ? Icons.spellcheck : Icons.help_outline,
              size: 20, color: scheme.error),
          const SizedBox(width: 8),
          Text(isMisspelled ? '拼写可能不对' : '看起来不是英语单词',
              style: text.labelLarge!.copyWith(color: scheme.error)),
        ]),
        const SizedBox(height: 12),
        Text(o.reason, style: text.bodyMedium),
        if (canonical.isNotEmpty) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => onAcceptCanonical(canonical),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text('查询 $canonical'),
          ),
        ],
      ]);
    }

    // AI 已生成整卡（o 此处必非空：card 来自 o）
    if (card != null && o != null) {
      return wrap([
        Row(children: [
          Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text('AI 生成（词库未收录）',
              style: text.labelLarge!.copyWith(color: scheme.primary)),
          const Spacer(),
          if (o.partial)
            Text('部分内容缺失',
                style: text.bodySmall!.copyWith(color: scheme.error)),
        ]),
        const SizedBox(height: 12),
        Text(card.word,
            style: TextStyle(
                fontFamily: wordFontFamily,
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        if (card.phonetic.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('/${card.phonetic}/', style: text.bodyMedium),
        ],
        const SizedBox(height: 14),
        if (card.translation.trim().isNotEmpty)
          Text(card.translation.trim(),
              style: text.bodyLarge!
                  .copyWith(fontSize: defFontSize.toDouble())),
        if (card.definition.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(card.definition.trim(),
              style: text.bodySmall!.copyWith(fontStyle: FontStyle.italic)),
        ],
        AiSection(
          outcome: o,
          loading: aiLoading,
          onRegenerate: () => onGenerate(card.word),
          defFontSize: defFontSize,
        ),
      ]);
    }

    // 还没生成：给入口 + 不可用原因
    final String? why;
    if (!aiEnabled) {
      why = 'AI 未启用，可在设置中开启并填入密钥';
    } else if (!hasApiKey) {
      why = 'AI 已启用但未填密钥，请到设置 → AI 配置';
    } else {
      why = null;
    }

    return wrap([
      Row(children: [
        // 不要用 scheme.outline 当前景色 —— 它是边框色（1.29:1，等于不可见）。
        // 主题的 onSurfaceVariant 才是「弱化前景色」（约 9:1）。
        Icon(Icons.search_off, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('词库未收录',
            style: text.labelLarge!.copyWith(color: scheme.onSurfaceVariant)),
      ]),
      const SizedBox(height: 12),
      if (aiLoading)
        Row(children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('正在用 AI 查询…', style: text.bodySmall),
        ])
      else if (o != null && card == null)
        Row(children: [
          Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(o.reason.isEmpty ? 'AI 查询失败' : o.reason,
                style: text.bodySmall),
          ),
        ])
      else if (why == null)
        FilledButton.icon(
          onPressed: () => onGenerate(queryWord),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('用 AI 查询'),
        )
      else ...[
        Text(why, style: text.bodySmall),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onGoSettings,
          child: const Text('去设置'),
        ),
      ],
    ]);
  }

  /// 从自证原因里取出 canonical（格式见 enrich.dart：'拼写可能应为 X'）。
  static String _extractCanonical(String reason) {
    final i = reason.lastIndexOf(' ');
    return i >= 0 ? reason.substring(i + 1).trim() : '';
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
  // ---- AI 段落 ----
  final ai_enrich.AiOutcome? ai;
  final bool aiLoading;
  final bool aiReady;
  final bool aiAutoEnrich;

  /// 该词属于「不补齐」（缩写/专名）时不为 true，不显示 AI 入口。
  final bool enrichDisabled;
  final VoidCallback? onEnrich;
  final VoidCallback? onRegenerate;
  final VoidCallback? onGoSettings;

  const _ResultCard({
    required this.entry,
    required this.phonetic,
    required this.starred,
    required this.speakingAccent,
    required this.onSpeak,
    required this.onToggleStar,
    this.defFontSize = 14,
    this.showEnglish = true,
    this.ai,
    this.aiLoading = false,
    this.aiReady = false,
    this.aiAutoEnrich = true,
    this.enrichDisabled = false,
    this.onEnrich,
    this.onRegenerate,
    this.onGoSettings,
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
          // ---- AI 例句与搭配（不阻塞上面的词库内容）----
          if (!enrichDisabled)
            AiSection(
              outcome: ai,
              loading: aiLoading,
              unavailableReason: aiReady
                  ? (aiAutoEnrich ? null : null)
                  : 'AI 未启用，可在设置中开启并填入密钥',
              // 未就绪时不提供按钮（避免点了没反应）
              onRequest: (!aiReady || ai != null) ? null : onEnrich,
              onRegenerate: ai != null ? onRegenerate : null,
              onGoSettings: aiReady ? null : onGoSettings,
              defFontSize: defFontSize,
            ),
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


