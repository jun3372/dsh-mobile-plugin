import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/background_alert_controller.dart';
import '../features/servers/onboarding_page.dart';
import '../features/servers/servers_providers.dart';
import '../features/tasks/tasks_page.dart';
import 'theme.dart';

/// 根组件：未绑定服务端 → 引导页；已绑定 → 任务列表。
/// 深浅色跟随系统（SPEC §1.2 深色映射）。
class DshApp extends StatelessWidget {
  const DshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '探索未至之境',
      debugShowCheckedModeBanner: false,
      theme: buildDshTheme(Brightness.light),
      darkTheme: buildDshTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      themeAnimationDuration: DshMotion.normal,
      themeAnimationCurve: DshMotion.curve,
      builder: (context, child) {
        final palette = context.dsh;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: palette.background,
            systemNavigationBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const RootGate(),
    );
  }
}

class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  @override
  void initState() {
    super.initState();
    // 首帧后再挂载等待输入通知控制器：其依赖链（mux 等）的首次构建
    // 若落在 widget build 阶段会触发 markNeedsBuild 断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(backgroundAlertControllerProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(currentServerProvider);
    return server == null ? const OnboardingPage() : const TasksPage();
  }
}
