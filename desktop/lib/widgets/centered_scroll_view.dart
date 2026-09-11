// 复习页共用舞台：空间够就垂直居中，不够就允许滚动。
//
// 为什么需要（openspec: 复习界面在窗口尺寸变化下不裁剪内容）：
// 复习卡是**固定设计高度**（短语 460 / 单词 340），外层 Column 还有进度条、
// 反馈行、评分区等固定元素。默认窗口 1280x720 放得下，但窗口被拖矮后
// （短语页客户区低于约 660px 时）这些元素总和超过视口 → Column 溢出 →
// 评分按钮被裁掉且无法触达，用户没法完成评分。
//
// 这里不引入"卡高随窗口收缩"（要么维护一个 chrome 高度常量、要么给 FlipCard
// 加弹性高度，都更脆），而是让页面自己有滚动能力：任意窗口尺寸都不裁剪。
import 'package:flutter/material.dart';

class CenteredScrollView extends StatelessWidget {
  final Widget child;

  const CenteredScrollView({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 内容比视口矮时用它撑满，Center 才能垂直居中；比视口高时由
        // SingleChildScrollView 接管滚动。
        final minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}
