import 'package:flutter/material.dart';

/// 全局页面转场：淡入 + 微上浮（0 → 1 opacity, y: 4% → 0）
///
/// 通过 ThemeData.pageTransitionsTheme 全局注入，所有 MaterialPageRoute 自动生效，
/// 无需改动任何 push 调用点。曲线 easeOutCubic 减速感自然，回退 easeInCubic 稍快。
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        // y 轴偏移 4%，约 15-25px（视 DPI 而定），足够微妙又不突兀
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
