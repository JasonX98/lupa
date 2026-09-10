// 复习调度纯函数：按评分分级的固定间隔推进（方案 A）。
// 覆盖 specs/notebook/spec.md「固定间隔复习调度」与 specs/phrases/spec.md 同名条目。
//
// 规则（档位 1/3/7/15/30）：
//   忘了(1) → 回第 1 档；模糊(2) → 保持当前档；记得(3) → 前进 1 档；简单(4) → 前进 2 档。
//   新词（ivl < 1）按"即将进入第 1 档"计。
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/notebook/scheduler.dart';

void main() {
  group('intervals 档位表', () {
    test('档位为 1/3/7/15/30', () {
      expect(intervals, [1, 3, 7, 15, 30]);
    });
  });

  group('rungIndex（新词按第 1 档计）', () {
    test('新词与第一档都落在下标 0', () {
      expect(rungIndex(0), 0);
      expect(rungIndex(1), 0);
    });

    test('各档位下标', () {
      expect(rungIndex(3), 1);
      expect(rungIndex(7), 2);
      expect(rungIndex(15), 3);
      expect(rungIndex(30), 4);
    });

    test('超出最高档仍取下标 4', () {
      expect(rungIndex(100), 4);
    });
  });

  group('nextInterval 评分 × 当前间隔 矩阵', () {
    // 行 = 当前 ivl，列 = ease 1/2/3/4
    const matrix = <int, List<int>>{
      0: [1, 1, 3, 7],
      1: [1, 1, 3, 7],
      3: [1, 3, 7, 15],
      7: [1, 7, 15, 30],
      15: [1, 15, 30, 30],
      30: [1, 30, 30, 30],
    };

    matrix.forEach((ivl, expected) {
      test('ivl=$ivl → 忘了/模糊/记得/简单 = $expected', () {
        expect(nextInterval(ivl, easeAgain), expected[0]);
        expect(nextInterval(ivl, easeHard), expected[1]);
        expect(nextInterval(ivl, easeGood), expected[2]);
        expect(nextInterval(ivl, easeEasy), expected[3]);
      });
    });

    test('模糊不推进：保持当前档位', () {
      expect(nextInterval(7, easeHard), 7);
      expect(nextInterval(15, easeHard), 15);
      expect(nextInterval(30, easeHard), 30);
    });

    test('新词模糊进第一档（不跳过）', () {
      expect(nextInterval(0, easeHard), intervals.first);
    });

    test('简单比记得走得远，记得比模糊走得远（单调）', () {
      for (final ivl in matrix.keys) {
        final again = nextInterval(ivl, easeAgain);
        final hard = nextInterval(ivl, easeHard);
        final good = nextInterval(ivl, easeGood);
        final easy = nextInterval(ivl, easeEasy);
        expect(again <= hard, isTrue, reason: 'ivl=$ivl: 忘了应不高于模糊');
        expect(hard <= good, isTrue, reason: 'ivl=$ivl: 模糊应不高于记得');
        expect(good <= easy, isTrue, reason: 'ivl=$ivl: 记得应不高于简单');
      }
    });

    test('任何评分都不会掉出档位表', () {
      for (final ivl in [0, 1, 3, 7, 15, 30, 999]) {
        for (final ease in [easeAgain, easeHard, easeGood, easeEasy]) {
          expect(intervals, contains(nextInterval(ivl, ease)),
              reason: 'ivl=$ivl ease=$ease');
        }
      }
    });

    test('未知评分按最高档推进（兜底不炸）', () {
      expect(intervals, contains(nextInterval(7, 9)));
    });
  });

  group('dueTimestamp', () {
    test('记得：间隔 1 天 → 下次 3 天，due = now + 3*86400', () {
      final (ivl, due) = dueTimestamp(1, easeGood, now: 1000000);
      expect(ivl, 3);
      expect(due, 1000000 + 3 * 86400);
    });

    test('忘了：间隔 7 天 → 回第一档，due = now + 1*86400', () {
      final (ivl, due) = dueTimestamp(7, easeAgain, now: 1000000);
      expect(ivl, intervals.first);
      expect(due, 1000000 + 1 * 86400);
    });

    test('简单：新词 → 7 天，due = now + 7*86400', () {
      final (ivl, due) = dueTimestamp(0, easeEasy, now: 1000000);
      expect(ivl, 7);
      expect(due, 1000000 + 7 * 86400);
    });
  });
}
