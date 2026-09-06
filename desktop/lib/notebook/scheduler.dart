// Lupa 复习调度 — v1 固定间隔（与 Python 版 src/lupa/notebook/scheduler.py 对齐）。
//
// 间隔档位：1/3/7/15/30 天。答对（ease >= 2）推进下一档；答错（ease < 2）回第一档。
// 纯函数，无 IO。
library;

/// 固定间隔档位（天）
const List<int> intervals = [1, 3, 7, 15, 30];

/// ease 取值（与 Anki 一致）：1=Again 忘了 / 2=Hard / 3=Good / 4=Easy
const int easeAgain = 1;
const int easeHard = 2;
const int easeGood = 3;
const int easeEasy = 4;

/// 根据当前间隔与评分，计算下一次间隔（天）。
///
/// - 答错（ease=1）：回第一档（1 天）。
/// - 答对：推进到比 currentIvl 更大的下一档；已在最高档则保持 30。
/// - 新词（currentIvl=0）：答对进第一档。
int nextInterval(int currentIvl, int ease) {
  if (ease < easeHard) return intervals[0];
  for (final interval in intervals) {
    if (interval > currentIvl) return interval;
  }
  return intervals.last;
}

/// 返回 (nextIvl, dueUnixSeconds)。
///
/// Anki 约定：review 卡的 due = 当天零点 + ivl 天；v1 简化：now + ivl*86400（与 Python 版一致）。
(int, int) dueTimestamp(int currentIvl, int ease, {int? now}) {
  final ts = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final nextIvl = nextInterval(currentIvl, ease);
  return (nextIvl, ts + nextIvl * 86400);
}
