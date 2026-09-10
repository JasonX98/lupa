// 复习重置的纯函数边界测试（openspec change reset-review-history）。
// 只测纯逻辑（时间窗 / 命中判定），不碰数据库。
//
// 注意：r_id 的低 16 位被 XOR 随机化，所以「窗口之外」的期望值必须相对
// `ridTimeWindowMillis` 算出的真实边界来构造，不能靠猜测时间戳低位（否则用例会飘）。
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/notebook/repo.dart';

/// 模拟 `_genAnkiId`：毫秒时间戳 XOR 16 位随机数。
int ridOf(int ms) => ms ^ 0x1234;

void main() {
  // 固定基准：2026-09-05 12:15:23（本地时间）
  final base = DateTime(2026, 9, 5, 12, 15, 23);
  final baseMs = base.millisecondsSinceEpoch;
  final baseSec = baseMs ~/ 1000;

  final rid = ridOf(baseMs);
  final (winLo, winHi) = ridTimeWindowMillis(rid);
  final winLoSec = winLo ~/ 1000;
  final winHiSec = winHi ~/ 1000;

  test('3.1 r_id 时间窗：宽度 65536ms，且包住真实时刻', () {
    expect(winHi - winLo, 0x10000, reason: '低 16 位被随机化 → 只能还原 65.536 秒宽的窗');
    expect(winLo <= baseMs && baseMs < winHi, isTrue, reason: '真实时刻必落在窗口内');
  });

  test('3.1 只有 1 条历史时用 cards.mod 精确判定', () {
    expect(
      hitsResetWindow(
        historyCount: 1,
        cardModSec: baseSec,
        revlogRIds: [rid],
        sinceSec: baseSec - 5,
        untilSec: baseSec + 5,
      ),
      isTrue,
    );
    // 目标窗完全落在 r_id 窗之后（+2 分钟）→ 不命中
    expect(
      hitsResetWindow(
        historyCount: 1,
        cardModSec: baseSec,
        revlogRIds: [rid],
        sinceSec: winHiSec + 120,
        untilSec: winHiSec + 180,
      ),
      isFalse,
      reason: '窗口在评分之后 → 不命中',
    );
  });

  test('3.1 历史 >1 条时 cards.mod 不得作为精确依据（只有窗口相交才算）', () {
    // mod 落在窗口内，但两条历史的 r_id 窗口都远在窗口之外
    final farA = ridOf(baseMs - 3600 * 1000);
    final farB = ridOf(baseMs - 7200 * 1000);
    expect(
      hitsResetWindow(
        historyCount: 2,
        cardModSec: baseSec,
        revlogRIds: [farA, farB],
        sinceSec: baseSec - 5,
        untilSec: baseSec + 5,
      ),
      isFalse,
      reason: 'mod 只在「该卡仅 1 条历史」时才等于该次评分时间',
    );
    // 其中一条历史的窗口与目标窗口相交 → 命中（mod 完全不参与）
    expect(
      hitsResetWindow(
        historyCount: 2,
        cardModSec: baseSec - 99999,
        revlogRIds: [farA, rid],
        sinceSec: baseSec - 5,
        untilSec: baseSec + 5,
      ),
      isTrue,
    );
  });

  test('3.1 收窄窗口（--until）可把边缘命中排除在外', () {
    // 上界早于 r_id 窗的下界 → 无交集
    expect(
      hitsResetWindow(
        historyCount: 1,
        cardModSec: baseSec,
        revlogRIds: [rid],
        sinceSec: winLoSec - 600,
        untilSec: winLoSec - 10,
      ),
      isFalse,
      reason: 'r_id 窗与目标窗无交集 → 不命中',
    );
    // 目标窗覆盖整个 r_id 窗 → 相交
    expect(
      hitsResetWindow(
        historyCount: 1,
        cardModSec: baseSec,
        revlogRIds: [rid],
        sinceSec: winLoSec - 10,
        untilSec: winHiSec + 10,
      ),
      isTrue,
    );
  });

  test('3.1 无历史的卡（新词）在限定窗口下不命中，不限窗口则命中', () {
    expect(
      hitsResetWindow(
        historyCount: 0,
        cardModSec: baseSec,
        revlogRIds: const [],
        sinceSec: baseSec - 60,
        untilSec: baseSec + 60,
      ),
      isFalse,
    );
    expect(
      hitsResetWindow(
        historyCount: 0,
        cardModSec: baseSec,
        revlogRIds: const [],
      ),
      isTrue,
      reason: '不设窗口 = 全命中（--all 语义）',
    );
  });

  test('3.1 命中依据文案区分 mod / r_id / 两者', () {
    // mod 与 r_id 都命中：目标窗跨度盖住评分时刻与整个 r_id 窗
    expect(
      resetHitBasis(
        historyCount: 1,
        cardModSec: baseSec,
        revlogRIds: [rid],
        sinceSec: winLoSec - 120,
        untilSec: winHiSec + 120,
      ),
      'mod+r_id',
    );
    // 只有 r_id 命中：mod 被「历史 >1 条」排除
    expect(
      resetHitBasis(
        historyCount: 2,
        cardModSec: baseSec - 99999,
        revlogRIds: [rid],
        sinceSec: baseSec - 5,
        untilSec: baseSec + 5,
      ),
      'r_id',
    );
    // 只有 mod 命中：该卡仅 1 条历史，且那条历史的 r_id 窗远在目标窗之外
    final farRid = ridOf(baseMs - 3600 * 1000);
    expect(
      resetHitBasis(
        historyCount: 1,
        cardModSec: baseSec,
        revlogRIds: [farRid],
        sinceSec: baseSec - 1,
        untilSec: baseSec + 1,
      ),
      'mod',
    );
  });
}
