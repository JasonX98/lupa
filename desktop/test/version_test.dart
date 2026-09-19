// 版本号一致性：`pubspec.yaml` 是唯一事实源，`lib/version.dart` 是它的副本。
//
// 为什么需要这条测试：版本号以前散落四处（pubspec / README / version.dart /
// schema.sql 的 lupa_version），实测漂移了三个补丁 —— README 停在 v0.2.1、
// version.dart 停在 0.2.2，而设置页脚显示的正是 version.dart 的值。
// 手抄常量必然漂移，所以把「唯一事实源」从口头约定变成可执行断言。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/version.dart';

void main() {
  test('lupaVersion 与 pubspec.yaml 的 version 一致', () {
    final f = File('pubspec.yaml');
    expect(f.existsSync(), isTrue, reason: '测试需在 desktop/ 下运行');
    final line = f
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
    expect(line, isNotEmpty, reason: 'pubspec.yaml 缺 version 行');

    // pubspec 允许 `x.y.z+build`，本项目的约定是纯 x.y.z（见 AGENTS.md 约束 6）
    final raw = line.substring('version:'.length).trim();
    expect(raw, isNot(contains('+')),
        reason: '版本号应统一为 x.y.z，不带 build 后缀');

    expect(lupaVersion, raw,
        reason: 'lib/version.dart 的 lupaVersion 与 pubspec.yaml 不一致：'
            '改版本号时两处必须同步');
  });

  test('版本号形如 x.y.z', () {
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(lupaVersion), isTrue,
        reason: '实际值: $lupaVersion');
  });
}
