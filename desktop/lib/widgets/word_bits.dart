// 词条内容展示的小工具：词形变化标签、柯林斯星级、到期文案、音标展示。
// 与 export/apkg.dart 的 _fmt_exchange 标签保持一致。
import 'package:flutter/material.dart';

import 'package:lupa/ai/card.dart';
import 'package:lupa/ai/enrich.dart';
import 'package:lupa/media/phonetic.dart';

/// 展示音标：在线结果优先（英 / 美 同时展示，英前美后），否则回退词库自带音标。
String displayPhonetic({PhoneticResult? online, String fallback = ''}) {
  final uk = online?.uk ?? '';
  final us = online?.us ?? '';
  if (uk.isNotEmpty && us.isNotEmpty) return '英 $uk · 美 $us';
  if (uk.isNotEmpty) return '英 $uk';
  if (us.isNotEmpty) return '美 $us';
  return fallback.trim();
}
/// 词形变化键 -> 中文标签（d=过去式 p=过去分词 i=现在分词 3=三单 s=复数 r=比较级 t=最高级）。
const Map<String, String> exchangeLabels = {
  'd': '过去式',
  'p': '过去分词',
  'i': '现在分词',
  '3': '三单',
  's': '复数',
  'r': '比较级',
  't': '最高级',
};

/// 解析 exchange 字段为「标签 + 词形」行列表。
List<(String, String)> exchangeLines(String exchange) {
  final result = <(String, String)>[];
  if (exchange.isEmpty) return result;
  for (final seg in exchange.split('/')) {
    final idx = seg.indexOf(':');
    if (idx <= 0) continue;
    final key = seg.substring(0, idx);
    final value = seg.substring(idx + 1);
    if (value.isEmpty) continue;
    result.add((exchangeLabels[key] ?? key, value));
  }
  return result;
}

/// 柯林斯星级：0 -> ''，n -> '★' * n
String collinsStars(int n) => n <= 0 ? '' : '★' * n;

/// ECDICT tag 串 -> 展示标签（zk gk cet4 cet6 ky toefl ...）。
List<String> tagList(String tag) =>
    tag.trim().isEmpty ? [] : tag.trim().split(RegExp(r'\s+'));

/// 生词本的 due 展示文案：新词 / 今天 / MM-dd。
String dueLabel(int cardType, int dueUnixSeconds, {DateTime? now}) {
  if (cardType == 0) return '新词';
  final n = now ?? DateTime.now();
  final d = DateTime.fromMillisecondsSinceEpoch(dueUnixSeconds * 1000);
  if (d.isBefore(n)) return '今天';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.month)}-${two(d.day)}';
}

// ---- AI 内容区块 ----
//
// 四种状态（见 specs/desktop-app 的「AI 内容区块的呈现」）：
//   idle    -> 未触发（AI 未开或未就绪）
//   loading -> 请求中
//   ok      -> 按词性分组渲染（降级内容走「通用例句」标题）
//   failed  -> 提示 + 重试
// 任何状态都**不阻塞、不遮挡**词库内容。

/// AI 例句与搭配区块。
class AiSection extends StatelessWidget {
  final AiOutcome? outcome;
  final bool loading;

  /// AI 未就绪时的原因（用于 idle 态文案）。
  final String? unavailableReason;
  final VoidCallback? onRequest;
  final VoidCallback? onRegenerate;
  final VoidCallback? onGoSettings;
  final int defFontSize;

  const AiSection({
    super.key,
    required this.outcome,
    this.loading = false,
    this.unavailableReason,
    this.onRequest,
    this.onRegenerate,
    this.onGoSettings,
    this.defFontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Row(children: [
          const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('正在补齐例句与搭配…', style: text.bodySmall),
        ]),
      );
    }

    final o = outcome;
    if (o == null) {
      // idle：AI 未就绪、或尚未触发。
      //
      // idle 态的动作语义就是「补齐」（此时没有内容可覆盖），所以 onRequest
      // 与 onRegenerate 在这里是同一件事 —— 取第一个非空的。这样调用方传哪个
      // 都不会得到「只有文案、没有按钮」的死状态（实测踩过：详情弹窗传了
      // onRegenerate，而本分支当时只读 onRequest，于是显示了「可点下方补齐」
      // 却下方无物）。
      final request = onRequest ?? onRegenerate;
      // 既没有可执行动作、也没有设置入口时不渲染：
      // 宁可什么都不显示，也不要给一句无路可走的提示。
      if (request == null && onGoSettings == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Row(children: [
          if (request != null)
            OutlinedButton.icon(
              onPressed: request,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('AI 补齐', style: TextStyle(fontSize: 13)),
            ),
          if (unavailableReason != null) ...[
            if (request != null) const SizedBox(width: 10),
            Expanded(
              child: Text(unavailableReason!, style: text.bodySmall),
            ),
          ],
          // 不可用时必须给一条出路（spec：说明不可用原因）——
          // 只说「未启用」而不给入口，用户就卡在这里了。
          if (onGoSettings != null)
            TextButton(onPressed: onGoSettings, child: const Text('去设置')),
        ]),
      );
    }

    final card = o.card;
    if (card == null) {
      // failed
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(o.reason.isEmpty ? 'AI 补齐失败' : o.reason,
                style: text.bodySmall),
          ),
          if (onRegenerate != null)
            TextButton(onPressed: onRegenerate, child: const Text('重试')),
          if (onGoSettings != null)
            TextButton(onPressed: onGoSettings, child: const Text('去设置')),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('AI 补充',
                style: text.labelLarge!.copyWith(color: scheme.primary)),
            const SizedBox(width: 8),
            if (o.partial)
              Expanded(
                child: Text('部分词性缺例句',
                    style: text.bodySmall!.copyWith(color: scheme.error)),
              )
            else if (o.fromCache)
              Text('来自缓存', style: text.bodySmall),
            const Spacer(),
            if (onRegenerate != null)
              TextButton(
                onPressed: onRegenerate,
                child: const Text('重新生成', style: TextStyle(fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 6),
          // 降级补齐没有词性分组，统一走「通用例句」标题
          if (card.senses.isEmpty && card.examples.isNotEmpty)
            _exampleBlock(context, '通用例句', card.examples),
          for (final g in card.senses)
            _groupBlock(context, g.label, g.gloss, g.examples),
          if (card.collocations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('常用搭配',
                style: text.labelMedium!.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final g in card.collocations)
              _groupBlock(context, g.label, g.gloss, g.examples,
                  isCollocation: true),
          ],
        ],
      ),
    );
  }

  Widget _groupBlock(BuildContext context, String label, String gloss,
      List<AiExample> examples,
      {bool isCollocation = false}) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
            ),
            if (gloss.trim().isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(gloss.trim(),
                    style: text.bodySmall!
                        .copyWith(fontSize: (defFontSize - 2).clamp(11.0, 16.0).toDouble())),
              ),
            ],
          ]),
          ...examples.map((e) => Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.en,
                        style: text.bodyMedium!
                            .copyWith(fontSize: (defFontSize - 1).clamp(11.0, 17.0).toDouble())),
                    if (e.zh.trim().isNotEmpty)
                      Text(e.zh,
                          // 不要用 scheme.outline —— 它被映射到 border（边框色
                          // 0xFFE4E2DD），当文字色对比度极低（实测看不清）。
                          // bodySmall 本身已是 tx3（WCAG AA 4.8:1），直接用。
                          style: text.bodySmall!.copyWith(
                              fontSize:
                                  (defFontSize - 3).clamp(10.0, 15.0).toDouble())),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _exampleBlock(
      BuildContext context, String title, List<AiExample> examples) {
    return _groupBlock(context, title, '', examples);
  }
}
