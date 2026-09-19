## 1. 根因：主题补上「弱化前景色」token

- [ ] 1.1 在 `desktop/lib/theme/lupa_theme.dart` 的 `_buildLupaTheme` 里显式映射 `onSurfaceVariant`，取当前实测达标的值（浅色 ≈ `#3F4946`、深色 ≈ `#BEC9C5`；实施时以现值为准，不要另挑），并在该行上方加注释说明「它才是弱化前景色；`outline` 是边框色（1.2:1）只能描边」；验证：`flutter test test/ai_text_contrast_test.dart` 仍全过（该文件已断言 AI 区域文字 ≥4.5:1），且 `flutter analyze` 无新增告警
- [ ] 1.2 确认显式映射前后 `onSurfaceVariant` 的实际对比度未退化：临时打印浅/深两套主题下它与 `surface` 的对比度，应分别 ≥4.5:1；验证：打印值写入本任务勾选说明（浅/深各一个数）

## 2. 收敛 7 处 `outline` 当 foreground

- [ ] 2.1 `desktop/lib/widgets/app_shell.dart`：侧栏导航图标（约 192）与「设置」图标（约 261）的三元表达式 else 分支由 `scheme.outline` 改为 `scheme.onSurfaceVariant`（选中态保持 `primary`）；验证：`grep -n "scheme.outline" lib/widgets/app_shell.dart` 只剩描边用途
- [ ] 2.2 `desktop/lib/widgets/app_shell.dart`：快捷键提示文字（约 204）的 else 分支同样改为 `scheme.onSurfaceVariant`（这是 7 处里唯一的文字误用，10.5px）；验证：同 2.1
- [ ] 2.3 `desktop/lib/pages/search_page.dart`：空状态大图标（约 423）与收藏星标 else 分支（约 835）改为 `scheme.onSurfaceVariant`；验证：`grep -n "scheme.outline" lib/pages/search_page.dart` 只剩描边用途
- [ ] 2.4 `desktop/lib/pages/notebook_page.dart`（约 135）与 `desktop/lib/pages/phrase_page.dart`（约 273）的空状态图标改为 `scheme.onSurfaceVariant`；验证：这两个文件里 `grep -n "outline"` 只剩描边用途
- [ ] 2.5 全仓复查：`grep -rn "scheme.outline\|colorScheme.outline" lib/` 的结果里 MUST NOT 再出现被当作 `Icon(color:)` 或 `TextStyle(color:)` 的用法；验证：逐条人工分类确认，结果贴在勾选说明里

## 3. 侧栏在矮窗口下可触达

- [ ] 3.1 把 `desktop/lib/widgets/app_shell.dart` 的侧栏 `SizedBox > Column` 改为「空间足够时保持原布局（「设置」贴底、不出现滚动条），空间不足时可滚动」；实现手法见 design D3（注意 `Spacer`/`Expanded` 在 `SingleChildScrollView` 的无界高度下会抛异常，需先约束高度）；验证：`flutter analyze` 无新增告警
- [ ] 3.2 补回归测试：在 720 / 600 / 460 / 400 / 340 / 300px 六个窗口高度下渲染 `AppShell`，断言均不产生布局溢出异常；验证：该测试全过（实施前 340px 应溢出 33px、300px 溢出 73px —— 先跑一遍确认测试能红，再实现）
- [ ] 3.3 补「矮窗口下设置仍可达」的断言：窗口高度不足以容纳侧栏内容时，滚动后能点到「设置」入口并切到设置页；验证：测试全过
- [ ] 3.4 补「空间充足时布局不退化」的断言：窗口足够高（如 720px）时，各导航项与「设置」入口的相对位置与改动前一致、且「设置」入口贴侧栏底部；验证：测试全过（用 `getRect` 断言而非像素魔数）

## 4. 用「算对比度」的测试守住这一类

- [ ] 4.1 新增 `desktop/test/ui_contrast_test.dart`：按 WCAG 2.x 公式计算对比度（**注意是 2.4 次幂**，写成平方会算出偏小值而误报），断言所有文字前景色相对背景 ≥4.5:1、所有图标前景色 ≥3:1，浅深两套主题都跑；覆盖侧栏、查词空状态、生词本空状态、短语集空状态、收藏星标；验证：测试全过
- [ ] 4.2 反向验证（**这条是本任务的价值所在**）：临时把至少 3 处（必须含侧栏图标、快捷键提示文字、收藏星标）改回 `scheme.outline`，确认测试**转红并打印出具体对比度数值**（约 1.2~1.3:1）；然后恢复；验证：两种状态各跑一次，把红/绿结果写在勾选说明里
- [ ] 4.3 若 4.1 的断言依赖硬编码背景色，改为从主题取值（避免色值漂移导致测试与实现脱节）；验证：`grep -c "Color(0x" test/ui_contrast_test.dart` 为 0（只允许引用 `LupaColors.*`）

## 5. 集成验证

- [ ] 5.1 依次运行 `flutter analyze`、`flutter test`；验证：前者无新增 error/warning，后者全过（当前基线 292 个用例）
- [ ] 5.2 运行八组 `verify_*.dart`（`verify_notebook_db` / `verify_dict_query` / `verify_notebook_repo` / `verify_media` / `verify_export` / `verify_e2e` / `verify_phrase_repo` / `verify_ai`）；验证：全部 0 失败 —— 证明纯界面改动没有触碰数据层
- [ ] 5.3 手动看一眼实机观感：浅色与深色主题下侧栏（选中/未选中态）、三个空状态页、查词页未收藏星标；确认可读性提升且无「过重」的观感问题；验证：若装饰性空状态图标过重，按 design 的 Open Question 单独取值（仍 ≥3:1），并在勾选说明里记录最终选择
