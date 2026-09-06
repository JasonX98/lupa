// 词条内容展示的小工具：词形变化标签、柯林斯星级、到期文案、音标展示。
// 与 export/apkg.dart 的 _fmt_exchange 标签保持一致。
import 'package:lupa/media/phonetic.dart';

/// 展示音标：在线结果优先（英美相同时只显示一个），否则回退词库自带音标。
String displayPhonetic({PhoneticResult? online, String fallback = ''}) {
  final uk = online?.uk ?? '';
  final us = online?.us ?? '';
  if (uk.isNotEmpty && us.isNotEmpty) {
    return uk == us ? uk : '英 $uk · 美 $us';
  }
  if (uk.isNotEmpty) return uk;
  if (us.isNotEmpty) return us;
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
