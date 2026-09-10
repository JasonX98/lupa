// Lupa 复习调度 — v1 固定间隔。
//
// 注意：本实现已与 Python 参考版 src/lupa/notebook/scheduler.py 分叉
//（Python 版仍是「ease>=2 一律推进一档」，不区分模糊/记得/简单），按 AGENTS.md
// 的约定不再回同步。
//
// 间隔档位：1/3/7/15/30 天。按评分分级推进：
//   忘了(1) → 回第一档；模糊(2) → 保持当前档；记得(3) → 前进一档；简单(4) → 前进两档。
//   新词（ivl < 1）按"即将进入第一档"计，故与间隔 1 天的卡同档。
// 纯函数，无 IO。
library;

/// 固定间隔档位（天）
const List<int> intervals = [1, 3, 7, 15, 30];

/// ease 取值（与 Anki 一致）：1=Again 忘了 / 2=Hard 模糊 / 3=Good 记得 / 4=Easy 简单
const int easeAgain = 1;
const int easeHard = 2;
const int easeGood = 3;
const int easeEasy = 4;

/// 当前间隔所处的档位下标（0..4）。
///
/// 新词（ivl < 1，含 0）按"即将进入第一档"计，返回 0；
/// 落在两档之间的值取下界档位（如 5 → 3 天，下标 1）；超过最高档返回末位下标。
int rungIndex(int ivl) {
  var idx = 0;
  for (var i = 0; i < intervals.length; i++) {
    if (intervals[i] <= ivl) idx = i;
  }
  return idx;
}

/// 根据当前间隔与评分，计算下一次间隔（天）。
///
/// - 忘了（ease=1）：回第一档（1 天）。
/// - 模糊（ease=2）：保持当前档位，下限第一档。
/// - 记得（ease=3）：前进一档。
/// - 简单（ease=4）：前进两档。
/// - 结果一律夹在档位表内。新词按「即将进入第一档」计，故与间隔 1 天的卡同档：
///   记得 → 3 天（前进一档），模糊 → 1 天（停在第一档）。
int nextInterval(int currentIvl, int ease) {
  final idx = rungIndex(currentIvl);
  final target = switch (ease) {
    easeAgain => 0,
    easeHard => idx,
    easeGood => idx + 1,
    _ => idx + 2,
  };
  return intervals[target.clamp(0, intervals.length - 1)];
}

/// 返回 (nextIvl, dueUnixSeconds)。
///
/// Anki 约定：review 卡的 due = 当天零点 + ivl 天；v1 简化：now + ivl*86400（与 Python 版一致）。
(int, int) dueTimestamp(int currentIvl, int ease, {int? now}) {
  final ts = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final nextIvl = nextInterval(currentIvl, ease);
  return (nextIvl, ts + nextIvl * 86400);
}
