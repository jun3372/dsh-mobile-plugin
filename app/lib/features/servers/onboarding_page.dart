import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'pairing_controller.dart';
import 'scan_page.dart';

/// 未绑定任何服务端时的引导页。
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(pairingControllerProvider, (previous, next) {
      if (next.status == PairingStatus.failed) {
        showDshError(context, next.message);
      }
    });
    final p = context.dsh;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.x8),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.foreground,
                  borderRadius: BorderRadius.circular(DshRadius.bubble),
                ),
                alignment: Alignment.center,
                child: Text(
                  'D',
                  style: TextStyle(
                    color: p.onForeground,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: DshSpace.x6),
              Text(
                '探索未至之境',
                style: context.dshText.titleLarge?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: DshSpace.x3),
              Text(
                '扫码绑定 DSH 宿主的手机连接网关，\n远程查看任务与会话进展。',
                textAlign: TextAlign.center,
                style: context.dshText.bodyMedium?.copyWith(height: 1.5),
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
