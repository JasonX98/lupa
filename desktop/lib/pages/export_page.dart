// Lupa 导出页（openspec task 7.4 的导出部分）。
// apkg（Anki）/ csv（Excel）两个入口。导出是「归你所有」的落点，P0 功能。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/state/app_state.dart';

class ExportPage extends StatefulWidget {
  final AppState state;
  const ExportPage({super.key, required this.state});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  bool _busyApkg = false;
  bool _busyCsv = false;
  String? _resultApkg;
  String? _resultCsv;
  String? _errorApkg;
  String? _errorCsv;

  String _stampBase() => widget.state.exportFileName('apkg').replaceAll('.apkg', '');

  Future<void> _doExport({required bool apkg}) async {
    final total = widget.state.stats['total'] ?? 0;
    if (total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生词本是空的，先收藏几个词再导出')));
      return;
    }
    setState(() {
      if (apkg) {
        _busyApkg = true;
        _resultApkg = null;
        _errorApkg = null;
      } else {
        _busyCsv = true;
        _resultCsv = null;
        _errorCsv = null;
      }
    });
    final dir = widget.state.exportDir();
    final base = _stampBase();
    try {
      if (apkg) {
        final path = p.join(dir, '$base.apkg');
        final report = await widget.state.exportApkgTo(path);
        setState(() { _busyApkg = false; _resultApkg = report.path; });
      } else {
        final path = p.join(dir, '$base.csv');
        final report = await widget.state.exportCsvTo(path);
        setState(() { _busyCsv = false; _resultCsv = report.path; });
      }
    } catch (e) {
      setState(() {
        if (apkg) {
          _busyApkg = false;
          _errorApkg = '$e';
        } else {
          _busyCsv = false;
          _errorCsv = '$e';
        }
      });
    }
  }

  Future<void> _openFolder(String filePath) async {
    try {
      await Process.run('explorer.exe', ['/select,', p.absolute(filePath)]);
    } catch (_) {/* 打不开就算了，路径已展示 */}
  }

  Widget _resultRow(BuildContext context, String? path, String? error) {
    final text = Theme.of(context).textTheme;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text('导出失败: $error',
            style: text.bodySmall!.copyWith(
                color: Theme.of(context).colorScheme.error)),
      );
    }
    if (path == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Icon(Icons.check_circle_outline,
            size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(path,
              style: text.bodySmall!.copyWith(fontFamily: 'Consolas')),
        ),
        TextButton(
          onPressed: () => _openFolder(path),
          child: const Text('打开所在文件夹', style: TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = widget.state.stats['total'] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('导出', style: text.titleLarge!.copyWith(fontSize: 20)),
          const SizedBox(height: 6),
          Text('数据在你手里 — $total 个词随时带走', style: text.bodySmall),
          const SizedBox(height: 24),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(children: [
                // ---- apkg ----
                Container(
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
                        Icon(Icons.style_outlined, size: 22, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text('Anki 牌组（.apkg）', style: text.titleMedium),
                        const Spacer(),
                        ListenableBuilder(
                          listenable: widget.state,
                          builder: (context, _) => Text('$total 张卡',
                              style: text.bodySmall),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text('Anki 2.1+ 直接导入。同词稳定 guid：重复导出在 Anki 端更新卡片而非重复建卡。',
                          style: text.bodySmall),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _busyApkg ? null : () => _doExport(apkg: true),
                        icon: _busyApkg
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_rounded, size: 18),
                        label: const Text('导出 .apkg'),
                      ),
                      _resultRow(context, _resultApkg, _errorApkg),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ---- csv ----
                Container(
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
                        Icon(Icons.table_chart_outlined,
                            size: 22, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text('CSV 表格（.csv）', style: text.titleMedium),
                      ]),
                      const SizedBox(height: 8),
                      Text('UTF-8 带 BOM，Excel / WPS 双击打开不乱码。7 列：单词、音标、释义、英解、词形、标签、收藏时间。',
                          style: text.bodySmall),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _busyCsv ? null : () => _doExport(apkg: false),
                        icon: _busyCsv
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_rounded, size: 18),
                        label: const Text('导出 .csv'),
                      ),
                      _resultRow(context, _resultCsv, _errorCsv),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
