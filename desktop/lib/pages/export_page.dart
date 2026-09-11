// Lupa 导出页：顶部分段「生词本 | 短语集」，各自提供 apkg / csv 两个入口。
// 短语集分组另有标签筛选（默认「全部」）。导出是「归你所有」的落点，P0 功能。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/phrase_bits.dart';

/// 分组值：顶部分段控件用。
const String _gWords = 'words';
const String _gPhrases = 'phrases';

/// 标签筛选的「全部」档位（与短语集页同名值）。
const String _tagAll = 'all';

/// 一个导出目标（分组 × 格式）。四张卡的差异全收在这份描述里：
/// 新增一种格式只加一条，不再抄一遍 busy/result/error 三件套（见 design D7）。
class _TaskDef {
  final String id; // 状态 map 的 key，如 words.apkg
  final String group; // _gWords / _gPhrases
  final String ext; // apkg / csv
  final IconData icon;
  final String title;
  final String desc;
  final String buttonLabel;
  final bool filled; // apkg 主按钮、csv 次按钮（与原型一致）
  final String? countUnit; // null = 卡片标题不带计数（与单词 CSV 卡现状一致）

  const _TaskDef({
    required this.id,
    required this.group,
    required this.ext,
    required this.icon,
    required this.title,
    required this.desc,
    required this.buttonLabel,
    required this.filled,
    this.countUnit,
  });
}

const List<_TaskDef> _taskDefs = [
  _TaskDef(
    id: 'words.apkg',
    group: _gWords,
    ext: 'apkg',
    icon: Icons.style_outlined,
    title: 'Anki 牌组（.apkg）',
    desc: 'Anki 2.1+ 直接导入。同词稳定 guid：重复导出在 Anki 端更新卡片而非重复建卡。',
    buttonLabel: '导出 .apkg',
    filled: true,
    countUnit: '张卡',
  ),
  _TaskDef(
    id: 'words.csv',
    group: _gWords,
    ext: 'csv',
    icon: Icons.table_chart_outlined,
    title: 'CSV 表格（.csv）',
    desc: 'UTF-8 带 BOM，Excel / WPS 双击打开不乱码。7 列：单词、音标、释义、英解、词形、标签、收藏时间。',
    buttonLabel: '导出 .csv',
    filled: false,
  ),
  _TaskDef(
    id: 'phrases.apkg',
    group: _gPhrases,
    ext: 'apkg',
    icon: Icons.style_outlined,
    title: 'Anki 牌组（.apkg）',
    desc: '独立牌组 Lupa::短语集，与生词本牌组互不干扰。短语文本稳定 guid：重复导出在 Anki 端更新卡片而非重复建卡。',
    buttonLabel: '导出 .apkg',
    filled: true,
    countUnit: '条短语',
  ),
  _TaskDef(
    id: 'phrases.csv',
    group: _gPhrases,
    ext: 'csv',
    icon: Icons.table_chart_outlined,
    title: 'CSV 表格（.csv）',
    desc: 'UTF-8 带 BOM，Excel / WPS 双击打开不乱码。9 列：短语、直译、释义、典故、场景、场景标签、标签、收藏时间、例句。',
    buttonLabel: '导出 .csv',
    filled: false,
    countUnit: '条短语',
  ),
];

/// 一次成功导出的结果（条数 / 路径 / 非「全部」时的标签名）。
class _Done {
  final int count;
  final String path;
  final String? scope;
  const _Done(this.count, this.path, {this.scope});
}

class ExportPage extends StatefulWidget {
  final AppState state;
  const ExportPage({super.key, required this.state});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  /// 顶部分组与短语标签筛选都是导出页自持状态（design D2：
  /// 不提升短语集页的筛选，避免"导出的是上次筛过的子集"这种隐藏耦合）。
  String _group = _gWords;
  String _phraseTag = _tagAll;

  final _busy = <String, bool>{};
  final _done = <String, _Done>{};
  final _error = <String, String>{};

  int get _wordTotal => widget.state.stats['total'] ?? 0;

  int get _phraseTotal => widget.state.phraseStats['total'] ?? 0;

  /// 当前导出范围内的条数——守卫与卡片计数共用同一口径（design D5/D8）。
  int _scopeCount(_TaskDef t) {
    if (t.group == _gWords) return _wordTotal;
    if (_phraseTag == _tagAll) return _phraseTotal;
    return widget.state.phraseEntries
        .where((e) => e.tags.contains(_phraseTag))
        .length;
  }

  /// 空范围的提示：分「生词本为空 / 短语集为空 / 该标签下无短语」三种。
  String _emptyHint(_TaskDef t) {
    if (t.group == _gWords) return '生词本是空的，先收藏几个词再导出';
    if (_phraseTag == _tagAll) return '短语集还是空的，先记几条短语再导出';
    return '「$_phraseTag」下暂无短语，换个标签或选全部再导出';
  }

  Future<void> _doExport(_TaskDef t) async {
    if (_scopeCount(t) == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_emptyHint(t))));
      return;
    }
    setState(() {
      _busy[t.id] = true;
      _done.remove(t.id);
      _error.remove(t.id);
    });
    final dir = widget.state.exportDir();
    // 生词本与短语集两条命名线分开，同一分钟内先后导出不会互相覆盖（design D4）
    final name = t.group == _gWords
        ? widget.state.exportFileName(t.ext)
        : widget.state.phraseExportFileName(t.ext);
    final path = p.join(dir, name);
    try {
      final count = await _run(t, path);
      if (!mounted) return;
      setState(() {
        _busy[t.id] = false;
        _done[t.id] = _Done(
          count,
          path,
          scope: t.group == _gPhrases && _phraseTag != _tagAll
              ? _phraseTag
              : null,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy[t.id] = false;
        _error[t.id] = '$e';
      });
    }
  }

  /// 真实导出，返回写入条数。每个目标一行，不写 if/else 分支矩阵。
  Future<int> _run(_TaskDef t, String path) async {
    final tag =
        t.group == _gPhrases && _phraseTag != _tagAll ? _phraseTag : null;
    switch (t.id) {
      case 'words.apkg':
        return (await widget.state.exportApkgTo(path)).count;
      case 'words.csv':
        return (await widget.state.exportCsvTo(path)).count;
      case 'phrases.apkg':
        return (await widget.state.exportPhraseApkgTo(path, tag: tag)).count;
      case 'phrases.csv':
        return (await widget.state.exportPhraseCsvTo(path, tag: tag)).count;
      default:
        throw StateError('未知导出目标: ${t.id}');
    }
  }

  Future<void> _openFolder(String filePath) async {
    try {
      await Process.run('explorer.exe', ['/select,', p.absolute(filePath)]);
    } catch (_) {/* 打不开就算了，路径已展示 */}
  }

  String _subtitle() => _group == _gWords
      ? '数据在你手里 — $_wordTotal 个词随时带走'
      : '数据在你手里 — $_phraseTotal 条短语随时带走';

  /// 分组控件与短语标签筛选同行：分组靠左，标签靠右且右边界与卡片右边界对齐。
  /// 标签多到放不下时只让标签这一侧横向滚动，分组控件位置不动。
  ///
  /// 靠右靠的是 `Align(centerRight)` + 横向 `SingleChildScrollView` 的收缩行为
  /// （滚动视图的尺寸 = constrain(子尺寸)，所以比可用宽度窄时会贴右）。
  Widget _bars(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Row(children: [
            _groupBar(),
            const SizedBox(width: 12),
            if (_group == _gPhrases)
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _tagBar(context),
                  ),
                ),
              ),
          ]),
        ),
      );

  Widget _groupBar() => PhraseFilterBar(
        selected: _group,
        onSelect: (v) => setState(() => _group = v),
        segments: [
          PhraseFilterSegment(
              value: _gWords, label: '生词本', count: _wordTotal),
          PhraseFilterSegment(
              value: _gPhrases, label: '短语集', count: _phraseTotal),
        ],
      );

  Widget _tagBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = widget.state.phraseEntries;
    final tags = widget.state.phraseTags;
    int countOf(String t) => entries.where((e) => e.tags.contains(t)).length;
    return PhraseFilterBar(
      selected: _phraseTag,
      onSelect: (v) => setState(() => _phraseTag = v),
      segments: [
        PhraseFilterSegment(value: _tagAll, label: '全部', count: _phraseTotal),
        for (var i = 0; i < tags.length; i++)
          PhraseFilterSegment(
            value: tags[i],
            label: tags[i],
            count: countOf(tags[i]),
            dot: phraseDotColor(i, isDark),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tasks = _taskDefs.where((t) => t.group == _group).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('导出', style: text.titleLarge!.copyWith(fontSize: 20)),
            const SizedBox(height: 6),
            Text(_subtitle(), style: text.bodySmall),
            const SizedBox(height: 16),
            _bars(context),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(children: [
                      for (var i = 0; i < tasks.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        _ExportCard(
                          task: tasks[i],
                          countLabel: tasks[i].countUnit == null
                              ? null
                              : '${_scopeCount(tasks[i])} ${tasks[i].countUnit}',
                          busy: _busy[tasks[i].id] ?? false,
                          done: _done[tasks[i].id],
                          error: _error[tasks[i].id],
                          onExport: () => _doExport(tasks[i]),
                          onOpenFolder: _openFolder,
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一张导出卡（标题 / 计数 / 说明 / 主按钮 / 结果行）。
class _ExportCard extends StatelessWidget {
  final _TaskDef task;
  final String? countLabel;
  final bool busy;
  final _Done? done;
  final String? error;
  final VoidCallback onExport;
  final void Function(String path) onOpenFolder;

  const _ExportCard({
    required this.task,
    required this.countLabel,
    required this.busy,
    required this.done,
    required this.error,
    required this.onExport,
    required this.onOpenFolder,
  });

  Widget _button(BuildContext context) {
    final icon = busy
        ? const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.download_rounded, size: 18);
    final label = Text(task.buttonLabel);
    return task.filled
        ? FilledButton.icon(
            onPressed: busy ? null : onExport, icon: icon, label: label)
        : OutlinedButton.icon(
            onPressed: busy ? null : onExport, icon: icon, label: label);
  }

  Widget _result(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('导出失败: $error',
            style: text.bodySmall!.copyWith(color: scheme.error)),
      );
    }
    final d = done;
    if (d == null) return const SizedBox.shrink();
    final scope = d.scope == null ? '' : ' · 标签「${d.scope}」';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Icon(Icons.check_circle_outline, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Text('已导出 ${d.count} 条$scope', style: text.bodySmall),
        const SizedBox(width: 10),
        Expanded(
          child: Text(d.path,
              style: text.bodySmall!.copyWith(fontFamily: 'Consolas'),
              overflow: TextOverflow.ellipsis),
        ),
        TextButton(
          onPressed: () => onOpenFolder(d.path),
          child: const Text('打开所在文件夹', style: TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(task.icon, size: 22, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(task.title, style: text.titleMedium)),
            if (countLabel != null) Text(countLabel!, style: text.bodySmall),
          ]),
          const SizedBox(height: 8),
          Text(task.desc, style: text.bodySmall),
          const SizedBox(height: 14),
          _button(context),
          _result(context),
        ],
      ),
    );
  }
}
