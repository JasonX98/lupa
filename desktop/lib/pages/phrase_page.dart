// Lupa 短语集页：统计 + 标签筛选 + 列表 + 详情 + 记录/编辑表单。
// 与单词生词本完全隔离（独立三表、独立复习队列）。
import 'package:flutter/material.dart';

import 'package:lupa/phrase/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/phrase_bits.dart';
import 'package:lupa/widgets/tag_chip.dart';

class PhrasePage extends StatefulWidget {
  final AppState state;
  final bool isActive;
  final VoidCallback onGotoReview;

  const PhrasePage({
    super.key,
    required this.state,
    required this.isActive,
    required this.onGotoReview,
  });

  @override
  State<PhrasePage> createState() => _PhrasePageState();
}

class _PhrasePageState extends State<PhrasePage> {
  String _filter = 'all';

  /// 工具栏按钮（对齐原型 .btn：内边距 0 14、圆角 8、字号 14）。
  /// tapTargetSize.shrinkWrap：去掉 FilledButton 默认的 48px 点击热区；
  /// 高度统一 40px，记录短语 / 开始复习两个按钮齐平。
  static final ButtonStyle _toolbarBtn = FilledButton.styleFrom(
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );

  @override
  void didUpdateWidget(covariant PhrasePage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      widget.state.refresh();
    }
  }

  Future<void> _openForm({PhraseEntry? editing}) async {
    final input = await showDialog<PhraseInput>(
      context: context,
      builder: (_) => _PhraseFormDialog(editing: editing),
    );
    if (input == null || !mounted) return;
    try {
      if (editing == null) {
        await widget.state.addPhraseEntry(input);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已收录「${input.phrase}」')));
        }
      } else {
        await widget.state.updatePhraseEntry(editing.id, input);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已更新「${input.phrase}」')));
        }
      }
    } on PhraseExistsError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('「${input.phrase}」已存在')));
      }
    } on PhraseValidationError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _remove(PhraseEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除短语'),
        content: Text('把「${e.phrase}」从短语集删除？例句与复习历史一并删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.state.removePhraseEntry(e.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已删除「${e.phrase}」')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- 头部 ----
          Row(children: [
            Expanded(
              child: Text('短语集',
                  style: text.titleLarge!.copyWith(fontSize: 20)),
            ),
            ListenableBuilder(
              listenable: widget.state,
              builder: (context, _) {
                final dueCount = widget.state.phraseStats['due'] ?? 0;
                return FilledButton.icon(
                  onPressed:
                      dueCount == 0 ? null : widget.onGotoReview,
                  style: _toolbarBtn,
                  icon: const Icon(Icons.play_arrow_rounded, size: 15),
                  label: Text(dueCount == 0 ? '暂无到期' : '开始复习（$dueCount）'),
                );
              },
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _openForm(),
              style: _toolbarBtn,
              icon: const Icon(Icons.add, size: 15),
              label: const Text('记录短语'),
            ),
          ]),
          const SizedBox(height: 12),
          // ---- 统计 ----
          ListenableBuilder(
            listenable: widget.state,
            builder: (context, _) {
              final s = widget.state.phraseStats;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                _StatChip('总短语', '${s['total'] ?? 0}'),
                _StatChip('新短语', '${s['new'] ?? 0}'),
                _StatChip('复习中', '${s['review'] ?? 0}'),
                _StatChip('今日到期', '${s['due'] ?? 0}', emphasize: true),
                _StatChip('累计遗忘', '${s['lapses'] ?? 0}'),
              ]);
            },
          ),
          const SizedBox(height: 12),
          // ---- 筛选分段控件（对齐原型 .chips）----
          ListenableBuilder(
            listenable: widget.state,
            builder: (context, _) {
              final entries = widget.state.phraseEntries;
              final tags = <String>{};
              for (final e in entries) {
                tags.addAll(e.tags);
              }
              final sortedTags = tags.toList()..sort();
              int countOf(String t) =>
                  entries.where((e) => e.tags.contains(t)).length;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: PhraseFilterBar(
                  selected: _filter,
                  onSelect: (v) => setState(() => _filter = v),
                  segments: [
                    PhraseFilterSegment(
                      value: 'all',
                      label: '全部',
                      count: entries.length,
                    ),
                    for (var i = 0; i < sortedTags.length; i++)
                      PhraseFilterSegment(
                        value: sortedTags[i],
                        label: sortedTags[i],
                        count: countOf(sortedTags[i]),
                        dot: phraseDotColor(i, isDark),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // ---- 列表 ----
          Expanded(
            child: ListenableBuilder(
              listenable: widget.state,
              builder: (context, _) {
                final all = widget.state.phraseEntries;
                final shown = _filter == 'all'
                    ? all
                    : all.where((e) => e.tags.contains(_filter)).toList();
                if (shown.isEmpty) {
                  return _EmptyState(filtered: all.isNotEmpty);
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _PhraseRow(
                    entry: shown[i],
                    onTap: () => showPhraseDetailDialog(
                        context, widget.state, shown[i],
                        onEdit: (e) => _openForm(editing: e),
                        onDelete: (e) => _remove(e)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const _StatChip(this.label, this.value, {this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: emphasize
            ? (isDark ? const Color(0xFF1E3A34) : const Color(0xFFE7F2EF))
            : scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: Theme.of(context).textTheme.bodySmall),
        Text(value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: emphasize ? scheme.primary : scheme.onSurface,
            )),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool filtered;
  const _EmptyState({required this.filtered});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 14),
          Text(filtered ? '该标签下暂无短语' : '短语集还是空的', style: text.titleLarge),
          const SizedBox(height: 6),
          Text(
            filtered ? '换个标签看看' : '点右上「记录短语」，把词组/惯用语收进来',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PhraseRow extends StatelessWidget {
  final PhraseEntry entry;
  final VoidCallback onTap;
  const _PhraseRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label = phraseDueLabel(entry.state, entry.due);
    final isDueToday = label == '今天' || label == '新短语';

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(entry.phrase,
                          style: TextStyle(
                              fontFamily: wordFontFamily,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                    ),
                    if (entry.lit.trim().isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(entry.lit.trim(),
                            style: text.bodySmall,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ]),
                  if (entry.meaning.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(entry.meaning.trim(),
                          style: text.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (entry.exampleCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text('例句 ${entry.exampleCount}', style: text.labelSmall),
              ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDueToday
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDueToday
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF0F2C26)
                            : Colors.white)
                        : text.bodySmall!.color,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text('间隔 ${entry.ivl}天 · 复习${entry.reps}次',
                  style: text.labelSmall),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// 短语详情弹窗（对齐原型 .idm-card：释义高亮块 / 起源引用条 / 场景 pill / 例句虚分隔线）。
Future<void> showPhraseDetailDialog(
  BuildContext context,
  AppState state,
  PhraseEntry entry, {
  required void Function(PhraseEntry) onEdit,
  required void Function(PhraseEntry) onDelete,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;
      final tx1 = isDark ? LupaColors.tx1Dark : LupaColors.tx1Light;
      final tx2 = isDark ? LupaColors.tx2Dark : LupaColors.tx2Light;
      final tx3 = isDark ? LupaColors.tx3Dark : LupaColors.tx3Light;
      final accent = isDark ? LupaColors.jadeDark : LupaColors.jade;
      final acSoft =
          isDark ? LupaColors.jadeSoftDark : LupaColors.jadeSoftLight;
      final danger = isDark ? LupaColors.dangerDark : LupaColors.dangerLight;
      final border = theme.dividerColor;

      Widget section(String title, Widget child) => Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                        color: tx3)),
                const SizedBox(height: 8),
                child,
              ],
            ),
          );

      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- 头部：标题 + 字面直译 + Esc + 标签 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 22, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.phrase,
                                  style: TextStyle(
                                      fontFamily: wordFontFamily,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                      color: tx1)),
                              if (entry.lit.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('字面直译：${entry.lit.trim()}',
                                      style:
                                          TextStyle(fontSize: 13, color: tx3)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tx3,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            minimumSize: const Size(0, 34),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            side: BorderSide(color: border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Esc 关闭',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in entry.tags)
                          TagChip(label: t, kind: TagKind.exam),
                        TagChip(
                            label: '收录于 ${formatAddedDate(entry.addedAt)}',
                            kind: TagKind.plain),
                      ],
                    ),
                  ],
                ),
              ),
              // ---- 正文（可滚动）----
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.meaning.trim().isNotEmpty)
                        section(
                          '核心释义',
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                                color: acSoft,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(entry.meaning.trim(),
                                style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.6,
                                    color: tx1)),
                          ),
                        ),
                      if (entry.origin.trim().isNotEmpty)
                        section(
                          '起源与词源',
                          Container(
                            padding: const EdgeInsets.only(
                                left: 16, top: 2, bottom: 2),
                            decoration: BoxDecoration(
                                border: Border(
                                    left:
                                        BorderSide(color: accent, width: 3))),
                            child: Text(entry.origin.trim(),
                                style: TextStyle(
                                    fontFamily: wordFontFamily,
                                    fontSize: 14,
                                    height: 1.8,
                                    color: tx2)),
                          ),
                        ),
                      if (entry.scene.trim().isNotEmpty ||
                          entry.sceneTag.trim().isNotEmpty)
                        section(
                          '使用场景',
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TagChip(
                                  label: entry.sceneTag.trim().isEmpty
                                      ? '通用'
                                      : entry.sceneTag.trim(),
                                  kind: TagKind.exam),
                              if (entry.scene.trim().isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(entry.scene.trim(),
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          height: 1.7,
                                          color: tx2)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (entry.examples.isNotEmpty)
                        section(
                          '例句',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0;
                                  i < entry.examples.length;
                                  i++) ...[
                                if (i > 0) const PhraseDashedDivider(),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(entry.examples[i].en,
                                          style: TextStyle(
                                              fontSize: 14.5,
                                              height: 1.5,
                                              color: tx1)),
                                      if (entry
                                          .examples[i].zh.trim().isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                              entry.examples[i].zh.trim(),
                                              style: TextStyle(
                                                  fontSize: 13, color: tx2)),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // ---- 底栏 ----
              Container(
                padding: const EdgeInsets.fromLTRB(28, 14, 20, 16),
                decoration:
                    BoxDecoration(border: Border(top: BorderSide(color: border))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '复习：${phraseDueLabel(entry.state, entry.due)} · 固定间隔 1/3/7/15/30 天',
                        style: TextStyle(fontSize: 12, color: tx3),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onDelete(entry);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: danger,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 11),
                        side: BorderSide(color: border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                      ),
                      child: const Text('删除'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onEdit(entry);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: acSoft,
                        foregroundColor: accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 11),
                      ),
                      child: const Text('编辑'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 记录 / 编辑短语表单（返回 PhraseInput 或 null）。
class _PhraseFormDialog extends StatefulWidget {
  final PhraseEntry? editing;
  const _PhraseFormDialog({this.editing});

  @override
  State<_PhraseFormDialog> createState() => _PhraseFormDialogState();
}

class _PhraseFormDialogState extends State<_PhraseFormDialog> {
  late final TextEditingController _phrase;
  late final TextEditingController _meaning;
  late final TextEditingController _lit;
  late final TextEditingController _origin;
  late final TextEditingController _scene;
  late final TextEditingController _tags;
  late String _sceneTag;
  final List<ExampleEditRowController> _examples = [];

  static const _sceneTagPresets = ['通用', '口语', '书面', '正式'];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _phrase = TextEditingController(text: e?.phrase ?? '');
    _meaning = TextEditingController(text: e?.meaning ?? '');
    _lit = TextEditingController(text: e?.lit ?? '');
    _origin = TextEditingController(text: e?.origin ?? '');
    _scene = TextEditingController(text: e?.scene ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _sceneTag = (e?.sceneTag.trim().isNotEmpty ?? false) ? e!.sceneTag : '通用';
    for (final ex in e?.examples ?? const <PhraseExample>[]) {
      _examples.add(ExampleEditRowController(enText: ex.en, zhText: ex.zh));
    }
  }

  @override
  void dispose() {
    _phrase.dispose();
    _meaning.dispose();
    _lit.dispose();
    _origin.dispose();
    _scene.dispose();
    _tags.dispose();
    for (final c in _examples) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final phrase = _phrase.text.trim();
    final meaning = _meaning.text.trim();
    if (phrase.isEmpty || meaning.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('短语和核心释义必填')));
      return;
    }
    final examples = <PhraseExample>[];
    for (final c in _examples) {
      final en = c.en.text.trim();
      if (en.isEmpty) continue;
      examples.add(PhraseExample(en: en, zh: c.zh.text.trim()));
    }
    Navigator.pop(
      context,
      PhraseInput(
        phrase: phrase,
        meaning: meaning,
        lit: _lit.text,
        origin: _origin.text,
        scene: _scene.text,
        sceneTag: _sceneTag,
        tags: _tags.text,
        examples: examples,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sceneTagOptions = <String>{
      ..._sceneTagPresets,
      if (_sceneTag.trim().isNotEmpty) _sceneTag,
    }.toList();

    return AlertDialog(
      title: Text(widget.editing == null ? '记录短语' : '编辑短语'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _phrase,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '短语 *',
                  hintText: '如 bite the bullet',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _meaning,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '核心释义 *',
                  hintText: '如 咬紧牙关硬着头皮去做',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lit,
                decoration: const InputDecoration(
                  labelText: '字面直译',
                  hintText: '如 咬子弹',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _origin,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '典故 / 来源',
                  hintText: '它是怎么来的？一个故事胜过一打解释。',
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _sceneTag,
                    decoration: const InputDecoration(labelText: '场景标签'),
                    items: [
                      for (final t in sceneTagOptions)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setState(() => _sceneTag = v ?? '通用'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _scene,
                    decoration: const InputDecoration(
                      labelText: '使用场景',
                      hintText: '如 面对困难任务时的自我鼓励',
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('例句',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              const SizedBox(height: 6),
              for (final c in _examples)
                ExampleEditRow(
                  controller: c,
                  onRemove: () => setState(() {
                    _examples.remove(c);
                    c.dispose();
                  }),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                      () => _examples.add(ExampleEditRowController())),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('加一条例句'),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '逗号分隔，如 口语, 通用',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
