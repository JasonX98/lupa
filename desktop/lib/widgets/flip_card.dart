// Lupa 翻卡 —— 复习卡 3D 翻面。
// 与《Lupa 桌面版 UI 设计方案》对齐：flip 480ms cubic-bezier(.32,.72,.3,1)，
// 透视 1600px，卡高 340px，背面可滚动（释义过长时）。
// 遵循 prefers-reduced-motion：关闭动效时退化为 120ms 交叉淡入。
import 'dart:math' as math;

import 'package:flutter/material.dart';

class FlipCard extends StatefulWidget {
  /// true = 显示背面（已翻面）；false = 显示正面。
  final bool showBack;
  final Widget front;
  final Widget back;
  final double height;
  final VoidCallback? onTap;

  const FlipCard({
    super.key,
    required this.showBack,
    required this.front,
    required this.back,
    this.height = 340,
    this.onTap,
  });

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  static const Duration _flipDuration = Duration(milliseconds: 480);
  static const Cubic _flipCurve = Cubic(0.32, 0.72, 0.3, 1);

  late final AnimationController _controller;
  late final CurvedAnimation _flip;

  @override
  void initState() {
    super.initState();
    // 在 initState 建 ticker（元素已挂载）；避免延迟到 dispose 才初始化。
    _controller = AnimationController(
      vsync: this,
      duration: _flipDuration,
      value: widget.showBack ? 1 : 0,
    );
    _flip = CurvedAnimation(parent: _controller, curve: _flipCurve);
  }

  @override
  void didUpdateWidget(covariant FlipCard old) {
    super.didUpdateWidget(old);
    if (widget.showBack != old.showBack) {
      if (widget.showBack) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: widget.height,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: reduceMotion ? _buildCrossFade() : _buildFlip(),
      ),
    );
  }

  /// prefers-reduced-motion：120ms 交叉淡入，不做 3D 旋转。
  Widget _buildCrossFade() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      child: widget.showBack
          ? KeyedSubtree(key: const ValueKey('back'), child: widget.back)
          : KeyedSubtree(key: const ValueKey('front'), child: widget.front),
    );
  }

  Widget _buildFlip() {
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final angle = _flip.value * math.pi;
        // 90° 处正好侧对屏幕（视觉宽度为 0），此帧切换正/背面不可见。
        final showFront = angle < math.pi / 2;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (showFront)
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 1 / 1600) // 透视 ≈ CSS perspective:1600px
                  ..rotateY(angle),
                child: widget.front,
              )
            else
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 1 / 1600)
                  ..rotateY(angle + math.pi), // 背面预翻 180°，翻到正面时正读
                child: widget.back,
              ),
          ],
        );
      },
    );
  }
}
