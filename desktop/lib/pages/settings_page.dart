// Lupa 设置页 —— 外观 / 发音 / 复习 / 数据四组，全部写回 config.json。
// 对应《Lupa 桌面版 UI 设计方案》P1 设置页与 specs/settings/spec.md。
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/version.dart';
import 'package:lupa/widgets/seg_control.dart';
import 'package:lupa/widgets/switch_lupa.dart';

class SettingsPage extends StatefulWidget {
  final AppState state;
  const SettingsPage({super.key, required this.state});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _ttsUrl;
  late final TextEditingController _phoneticUrl;
  MediaCacheStats? _cacheStats;
  bool _busy = false; // 数据目录切换 / 备份 / 清理进行中

  @override
  void initState() {
    super.initState();
    _ttsUrl = TextEditingController(text: widget.state.providerUrl('tts_url'));
    _phoneticUrl =
        TextEditingController(text: widget.state.providerUrl('phonetic_url'));
    _loadCacheStats();
  }

  @override
  void dispose() {
    _ttsUrl.dispose();
    _phoneticUrl.dispose();
    super.dispose();
  }

  Future<void> _loadCacheStats() async {
    final s = await mediaCacheStats(widget.state.nbPath);
    if (mounted) setState(() => _cacheStats = s);
  }

  Future<void> _clearCache() async {
    final removed = await clearMediaCache(widget.state.nbPath);
    if (mounted) {
      setState(() => _cacheStats = MediaCacheStats(
            audioCount: 0,
            audioBytes: 0,
            audioHits: 0,
            phoneticCount: 0,
            phoneticHits: 0,
          ));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已清理 $removed 条缓存')));
    }
  }

  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await widget.state.backupNote();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已备份到 $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('备份失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFolder(String path) async {
    try {
      await Process.run('explorer', [p.normalize(path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开失败: $e')));
      }
    }
  }

  /// 数据目录「更改」：选目录 → 校验 → 复制或新开。返回选中的目录。
  Future<void> _changeDataDir() async {
    if (_busy) return;
    final dir = await getDirectoryPath(
      initialDirectory: dataHome().path,
      confirmButtonText: '选择此目录',
    );
    if (dir == null || dir.isEmpty) return; // 用户取消
    final dst = p.absolute(dir);
    final hasNotebook = File(p.join(dst, 'notebook.sqlite')).existsSync();

    setState(() => _busy = true);
    try {
      if (hasNotebook) {
        await widget.state.switchDataDir(dst, copyExisting: false);
      } else {
        // 空目录：让用户选「复制现有数据」或「新开空白」
        final choice = await _askCopyOrFresh();
        if (choice == null) return; // 取消：不改
        await widget.state.switchDataDir(dst,
            copyExisting: choice == 'copy');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已切换到数据目录：$dst')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('切换失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askCopyOrFresh() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新目录为空'),
        content: const Text('把现有生词本与词库复制到新目录，还是新开一份空白生词本？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'fresh'),
            child: const Text('新开空白'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'copy'),
            child: const Text('复制现有数据'),
          ),
        ],
      ),
    );
  }

  void _saveProvider(String key, TextEditingController c) {
    widget.state.setProviderUrl(key, c.text);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _pageHead(context),
        _sectionTitle('外观'),
        _card(_appearanceGroup(context)),
        _sectionTitle('发音'),
        _card(_pronunciationGroup(context)),
        _sectionTitle('复习'),
        _card(_reviewGroup(context)),
        _sectionTitle('数据'),
        _card(_dataGroup(context)),
        const SizedBox(height: 16),
        _versionFooter(context),
      ],
    );
  }

  Widget _pageHead(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: text.titleLarge),
          const SizedBox(height: 4),
          Text('所有配置写入 config.json，可直接文本编辑', style: text.bodySmall),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Text(title,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface)),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(children: children),
    );
  }

  Widget _row({
    required String label,
    String? sub,
    required Widget control,
  }) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub, style: text.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }

  // ---- 外观 ----
  List<Widget> _appearanceGroup(BuildContext context) {
    final state = widget.state;
    final themeSel = switch (state.themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    return [
      _row(
        label: '主题',
        sub: '跟随系统 / 浅色 / 深色',
        control: SegControl<String>(
          selected: themeSel,
          onChanged: (v) => state.setTheme(v),
          options: const [
            SegOption('跟随系统', 'system'),
            SegOption('浅色', 'light'),
            SegOption('深色', 'dark'),
          ],
        ),
      ),
      _divider(),
      _row(
        label: '释义字号',
        sub: '默认 14px，可调 12–18px',
        control: SegControl<int>(
          selected: state.defFontSize,
          onChanged: (v) => state.setDefFontSize(v),
          options: const [
            SegOption('12', 12),
            SegOption('14', 14),
            SegOption('15', 15),
            SegOption('16', 16),
            SegOption('18', 18),
          ],
        ),
      ),
      _divider(),
      _row(
        label: '显示英文释义',
        sub: '关闭后查词页只显示中文，界面更紧凑',
        control: LupaSwitch(
          value: state.showEnglish,
          onChanged: (v) => state.setShowEnglish(v),
        ),
      ),
    ];
  }

  // ---- 发音 ----
  List<Widget> _pronunciationGroup(BuildContext context) {
    final state = widget.state;
    return [
      _row(
        label: '默认口音',
        sub: '影响发音按钮与复习自动朗读',
        control: SegControl<String>(
          selected: state.defaultAccent,
          onChanged: (v) => state.setDefaultAccent(v),
          options: const [
            SegOption('美音 US', 'us'),
            SegOption('英音 UK', 'uk'),
          ],
        ),
      ),
      _divider(),
      _urlRow('TTS 服务商地址', '可替换为任意自有服务，不硬编码', _ttsUrl,
          () => _saveProvider('tts_url', _ttsUrl)),
      _divider(),
      _urlRow('音标服务商地址', '可替换为任意自有服务，不硬编码', _phoneticUrl,
          () => _saveProvider('phonetic_url', _phoneticUrl)),
      _divider(),
      _row(
        label: '媒体缓存',
        sub: _cacheStats == null
            ? '加载中…'
            : '已缓存 ${_cacheStats!.audioCount} 条音频 / '
                '${_fmtBytes(_cacheStats!.audioBytes)} · 命中 ${_cacheStats!.totalHits} 次',
        control: OutlinedButton(
          onPressed: _cacheStats == null ? null : _clearCache,
          child: const Text('清理缓存'),
        ),
      ),
    ];
  }

  Widget _urlRow(String label, String sub, TextEditingController c, VoidCallback onSave) {
    final text = Theme.of(context).textTheme;
    Widget urlField() => SizedBox(
          width: 320,
          child: TextField(
            controller: c,
            style: text.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: const OutlineInputBorder(),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 3),
          Text(sub, style: text.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: urlField()),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onSave,
              icon: const Icon(Icons.check, size: 18),
              tooltip: '保存',
            ),
          ]),
        ],
      ),
    );
  }

  // ---- 复习 ----
  List<Widget> _reviewGroup(BuildContext context) {
    final state = widget.state;
    return [
      _row(
        label: '调度算法',
        sub: '固定间隔 1 / 3 / 7 / 15 / 30 天',
        control: SegControl<String>(
          selected: 'fixed',
          onChanged: (_) {},
          options: const [
            SegOption('固定间隔', 'fixed'),
            SegOption('FSRS', 'fsrs', enabled: false, caption: 'v2'),
          ],
        ),
      ),
      _divider(),
      _row(
        label: '复习时自动朗读',
        sub: '翻面时播放发音，训练听力',
        control: LupaSwitch(
          value: state.reviewAutoRead,
          onChanged: (v) => state.setReviewAutoRead(v),
        ),
      ),
    ];
  }

  // ---- 数据 ----
  List<Widget> _dataGroup(BuildContext context) {
    final state = widget.state;
    final text = Theme.of(context).textTheme;
    final dirPath = dataHome().path;
    final dictPath = state.dictDb;
    final dictReady = File(dictPath).existsSync();
    return [
      _row(
        label: '数据目录',
        sub: 'notebook.sqlite · dict.sqlite · exports/ 在此目录',
        control: Row(children: [
          OutlinedButton(
            onPressed: _busy ? null : _changeDataDir,
            child: const Text('更改'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _openFolder(dirPath),
            child: const Text('打开'),
          ),
        ]),
      ),
      if (state.dataDirDiverges)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '提示：LUPA_HOME 已设置，且与上方数据目录不同。CLI（若用）仍指向 LUPA_HOME。',
            style: text.bodySmall!.copyWith(
                color: Theme.of(context).colorScheme.error),
          ),
        ),
      _divider(),
      _row(
        label: '数据目录路径',
        sub: dirPath,
        control: const SizedBox.shrink(),
      ),
      _divider(),
      _row(
        label: '词库',
        sub: dictReady
            ? 'ECDICT 裁剪版 · 30,000 词（只读）'
            : '未找到 dict.sqlite · 查词不可用，请放入数据目录或设 LUPA_HOME',
        control: Row(mainAxisSize: MainAxisSize.min, children: [
          _statusBadge(context, dictReady ? '已就绪' : '未找到', ok: dictReady),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _openFolder(p.dirname(dictPath)),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text('查看',
                  style: text.bodySmall!
                      .copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
          ),
        ]),
      ),
      _divider(),
      _row(
        label: '备份生词本',
        sub: '导出一份完整 SQLite 副本，可用于换机迁移',
        control: OutlinedButton(
          onPressed: _busy ? null : _backup,
          child: const Text('立即备份'),
        ),
      ),
    ];
  }

  Widget _versionFooter(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Lupa 璐帕 v$lupaVersion · MIT License · 词库来源 ECDICT（MIT）· 全程离线，无账号，无埋点。',
        style: text.bodySmall!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1);

  Widget _statusBadge(BuildContext context, String label, {required bool ok}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = ok
        ? (isDark ? LupaColors.successDark : LupaColors.successLight)
        : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  String _fmtBytes(int b) {
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }
}
