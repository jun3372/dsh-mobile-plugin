import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/dsh_logo.dart';
import 'scan_page.dart';

/// 未绑定任何服务端时的引导页。
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.x8),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // 与首页头部一致：SVG 鲸鱼标志，随深浅色主题自动换色。
              const DshLogo(width: 72, height: 72),
              const SizedBox(height: DshSpace.x6),
              Text(
                '探索未至之境',
                style: context.dshText.titleLarge?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: DshSpace.x3),
              Text(
                '扫码绑定 DSH 宿主的手机连接网关，\n远程查看任务与会话进展。',
                textAlign: TextAlign.center,
                style: context.dshText.bodyMedium?.copyWith(
                  height: 1.5,
                  color: context.dsh.secondaryText,
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('扫码绑定 DSH 服务端'),
                  onPressed: () => Navigator.of(context).push(dshScanRoute()),
                ),
              ),
              const SizedBox(height: DshSpace.x6),
            ],
          ),
        ),
      ),
    );
  }
}

Route<void> dshScanRoute() {
  return MaterialPageRoute<void>(builder: (_) => const ScanPage());
}
