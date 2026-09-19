## Why

主题把 `scheme.outline` 映射到**边框色**（`#E4E2DD`）。这个颜色作为 1px 描边是合适的，但被误用为**文字与图标的前景色**时，实测对比度只有 **1.20~1.29:1**（WCAG AA 对正文要求 4.5:1、对图标等非文字 UI 组件要求 3:1）——等于看不清、看不见。

这不是个别笔误，而是**主题缺少「弱化前景色」这个语义 token**导致的系统性误用：开发者需要「次要灰」时，手边唯一看起来像灰的就是 `outline`。上一轮变更（`add-ai-word-enrichment`）在实现 AI 段落时同样踩了进去，已随该变更修掉自己引入的 2 处；**其余 7 处是既有问题**，其中 3 处是主要交互入口（侧栏导航图标、侧栏「设置」图标、收藏星标），图标看不见等于功能不可发现。

另有一处**可触达性**缺陷（与对比度无关，但同属「界面在边界条件下不可用」）：侧栏是固定 `Column` 且**没有滚动**，实测窗口高度低于约 373px 时溢出（340px → 溢出 33px，300px → 溢出 73px）；而 Windows runner **未设置最小窗口尺寸**，用户可以把窗口拖到那个高度，此时侧栏底部的「设置」入口被裁掉且无法触达。这与既有的「复习界面在窗口尺寸变化下不裁剪内容」是同一类问题，只是发生在侧栏。

## What Changes

- **主题补上「弱化前景色」语义 token**：显式映射 `onSurfaceVariant`（并用注释说明它才是弱化前景色，而 `outline` 是边框色、不得当前景）。这是根因修复，避免后来者继续拿 `outline` 当灰色用。
- 修掉 **7 处** `scheme.outline` 当文字/图标色的用法，全部改为 `scheme.onSurfaceVariant`（实测约 9.3:1，浅深主题都通过）。
- 侧栏加滚动能力（空间够时保持原布局，不够时可滚动），使底部的「设置」入口在任意窗口高度下都可触达。
- 新增两个可机械验证的界面质量要求：**前景色对比度下限**与**侧栏内容可触达**。
- **无 schema 变更、无数据迁移、无依赖变更**。纯界面层修复 + 主题 token。

## Non-goals

- 不重做配色方案：主题的正文/次正文/辅助文字色（`tx1` / `tx2` / `tx3`）实测全部达标（17.2 / 7.8 / 4.8:1），不动。
- 不改任何布局比例、间距、字号。
- 不顺手修「短语集筛选圆点色 `#8B908A` 在 `surfaceContainerHighest` 上 2.80:1」——它是装饰性圆点而非文字/控件，且只差 0.2，不在本次范围。
- 不为本次修复引入任何新的界面控件或交互。
- 不改 `desktop/lib/ai/**` 与 `add-ai-word-enrichment` 已修的两处（它们已随该变更交付）。

## Capabilities

### New Capabilities

<!-- 无新增能力 -->

### Modified Capabilities

- `desktop-app`: 新增「界面前景色对比度」要求（正文 ≥ 4.5:1、图标等非文字 UI 组件 ≥ 3:1，浅深主题均适用）；新增「侧栏在窗口尺寸变化下不裁剪内容」要求（任意窗口高度下侧栏各项可达，含底部「设置」入口）。

## Impact

**修改文件**

- `desktop/lib/theme/lupa_theme.dart`：显式映射 `onSurfaceVariant`，并加注释说明 `outline` = 边框色、不得当前景（防复发）。
- `desktop/lib/widgets/app_shell.dart`：3 处前景色（侧栏导航图标 192、快捷键提示文字 204、「设置」图标 261）改用 `onSurfaceVariant`；侧栏 `SizedBox > Column` 改为可滚动。
- `desktop/lib/pages/search_page.dart`：2 处（空状态大图标 423、收藏星标 835）改用 `onSurfaceVariant`。
- `desktop/lib/pages/notebook_page.dart`：1 处（空状态图标 135）。
- `desktop/lib/pages/phrase_page.dart`：1 处（空状态图标 273）。
- `desktop/test/`：新增界面质量测试（对比度按 WCAG 公式计算，覆盖浅深主题与文字/图标两类；侧栏在矮窗口下不溢出且「设置」可点）。

**零改动**

- `desktop/lib/ai/**`、`desktop/lib/data/**`（含 `schema.sql`）、`desktop/lib/export/**`、`desktop/pubspec.yaml`、所有 `desktop/tool/verify_*.dart`。

**风险**

- 侧栏加滚动后，若实现不当可能让「设置」入口从「贴底」变成「跟着内容走」（视觉回退）。需保证空间充足时布局与现在逐像素一致。
- `onSurfaceVariant` 当前取自 `ColorScheme.fromSeed` 的生成值（实测浅 9.3:1 / 深 8.2:1，均达标）。显式映射时应固定为已验收的值，避免将来 Flutter 调整 `fromSeed` 算法导致色值漂移。

## 顺延（不在本 change 范围）

- **短语集筛选圆点色**（`phrase_bits.dart` 的 `#8B908A`）：装饰性圆点，白底 3.25:1 达标、`surfaceContainerHighest` 上 2.80:1 略低于 3:1。等真正影响可读性时再处理。
- **`Windows` runner 的最小窗口尺寸**：本次选择「让界面适应任意尺寸」而不是「限制窗口不能太小」。若将来想设置最小尺寸，是独立决策（会改变用户可拖拽的范围）。
- **`tx3` 在页面底色（非卡片底色）上为 4.48:1**，比正文阈值低 0.02。主题是按卡片底色（surface）校准的，且实测量级无感；若将来要严格对齐可单独调色。
