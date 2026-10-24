import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(currentServerProvider);
    return server == null ? const OnboardingPage() : const TasksPage();
  }
}
