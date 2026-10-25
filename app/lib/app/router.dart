import 'package:flutter/material.dart';

/// 全局 navigator：供通知点击等无 context 场景做路由跳转。
final GlobalKey<NavigatorState> dshNavigatorKey = GlobalKey<NavigatorState>();

/// Navigator 1.0 路由辅助：平台自适应转场。
Route<T> dshRoute<T>(Widget page) {
  return MaterialPageRoute<T>(builder: (_) => page);
}

/// 二级页面统一从右侧滑入（工作区文件、文件预览等）。
Route<T> dshSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
