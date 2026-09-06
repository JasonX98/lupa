// Lupa 生词本页（openspec task 7.2）。
// 统计头 + 列表（加入时间倒序）+ 移除 + 复习入口。
import 'package:flutter/material.dart';

import 'package:lupa/notebook/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/word_bits.dart';

class NotebookPage extends StatelessWidget {
  final AppState state;
  final VoidCallback onGotoReview;

  const NotebookPage({
    super.key,
    required this.state,
    required this.onGotoReview,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- 头部：标题 + 复习 CTA ----
          Row(children: [
            Expanded(
              child: Text('生词本',
                  style: text.titleLarge!.copyWith(fontSize: 20)),
            ),
            ListenableBuilder(
              listenable: state,
              builder: (context, _) {
                final dueCount = state.stats['due'] ?? 0;
                return FilledButton.icon(
                  onPressed: dueCount == 0 ? null : onGotoReview,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(dueCount == 0 ? '暂无到期' : '开始复习（$dueCount）'),
                );
              },
            ),
          ]),
          const SizedBox(height: 12),
          // ---- 统计条 ----
          ListenableBuilder(
            listenable: state,
            builder: (context, _) {
              final s = state.stats;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip('总词数', '${s['total'] ?? 0}'),
                  _StatChip('新词', '${s['new'] ?? 0}'),
                  _StatChip('复习中', '${s['review'] ?? 0}'),
                  _StatChip('今日到期', '${s['due'] ?? 0}', emphasize: true),
                  _StatChip('累计遗忘', '${s['lapses'] ?? 0}'),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // ---- 列表 ----
          Expanded(
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) {
                if (state.entries.isEmpty) {
                  return _EmptyState();
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: state.entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) =>
                      _EntryRow(entry: state.entries[i], state: state),
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
        Text('$label ',
            style: Theme.of(context).textTheme.bodySmall),
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
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_border_rounded,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 14),
          Text('生词本还是空的', style: text.titleLarge),
          const SizedBox(height: 6),
          Text('去查个词（Ctrl+F），点星收藏进来', style: text.bodySmall),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final NotebookEntry entry;
  final AppState state;

  const _EntryRow({required this.entry, required this.state});

  Future<void> _remove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移出生词本'),
        content: Text('把「${entry.word}」从生词本移出？其复习进度将一并删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('移出')),
        ],
      ),
    );
    if (ok == true) {
      await state.remove(entry.word);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已移出「${entry.word}」')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label = dueLabel(entry.cardType, entry.due);
    final isDueToday = label == '今天' || label == '新词';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(entry.word,
                    style: TextStyle(
                        fontFamily: wordFontFamily, fontSize: 16.5,
                        fontWeight: FontWeight.w600, color: scheme.onSurface)),
                if (entry.phonetic.trim().isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text('/${entry.phonetic.trim()}/',
                        style: text.bodySmall, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ]),
              if (entry.translation.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(entry.translation.trim(),
                      style: text.bodyMedium, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // ---- 调度状态 ----
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDueToday
                    ? scheme.primary // 玉青底
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
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
          ],
        ),
        IconButton(
          tooltip: '移出',
          onPressed: () => _remove(context),
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ]),
    );
  }
}
