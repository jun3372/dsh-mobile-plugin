import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../pairing_controller.dart';

/// 扫码绑定进度弹窗：居中展示当前阶段（连接 / 校验 / 成功 / 失败），
/// 成功后短暂停留再自动关闭，失败可原地重试。
class PairingProgressDialog extends ConsumerStatefulWidget {
  /// 二维码或手动输入解析出的原始绑定串。
  final String raw;

  const PairingProgressDialog({super.key, required this.raw});

  /// 弹出弹窗并等待结果；返回 true 表示绑定成功。
  static Future<bool> show(BuildContext context, String raw) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useSafeArea: true,
      builder: (_) => PairingProgressDialog(raw: raw),
    );
    return result ?? false;
  }

  @override
  ConsumerState<PairingProgressDialog> createState() =>
      _PairingProgressDialogState();
}

class _PairingProgressDialogState extends ConsumerState<PairingProgressDialog> {
  bool _running = false;

  /// 弹窗内自成一份阶段快照，避免在 overlay 中 watch 全局 provider：
  /// 路由切换时 Riverpod 的订阅恢复与构建同帧会触发 setState-during-build。
  PairingState _state = const PairingState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    final ok = await ref
        .read(pairingControllerProvider.notifier)
        .bind(
          widget.raw,
          onStage: (next) {
            if (mounted) setState(() => _state = next);
          },
        );
    if (!mounted) return;
    setState(() => _running = false);
    if (!ok) {
      unawaited(_failureFeedback());
      return; // 失败态由阶段快照驱动，等待用户重试或关闭。
    }
    unawaited(_successFeedback());
    // 成功状态短暂停留，避免弹窗一闪而过。
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) Navigator.of(context).pop(true);
  }

  /// 成功：两段轻震 + 系统点击音。
  Future<void> _successFeedback() async {
    unawaited(HapticFeedback.mediumImpact());
    _playSystemSound(SystemSoundType.click);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    unawaited(HapticFeedback.lightImpact());
  }

  /// 失败：两次重震 + 系统告警音，与成功形成明显区分。
  Future<void> _failureFeedback() async {
    unawaited(HapticFeedback.heavyImpact());
    _playSystemSound(SystemSoundType.alert);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    unawaited(HapticFeedback.heavyImpact());
  }

  /// 部分平台（如鸿蒙）可能未实现系统音效，失败时静默降级为震动。
  void _playSystemSound(SystemSoundType type) {
    unawaited(SystemSound.play(type).catchError((_) {}));
  }

  void _retry() {
    ref.read(pairingControllerProvider.notifier).reset();
    setState(() => _state = const PairingState());
    _run();
  }

  void _close() {
    ref.read(pairingControllerProvider.notifier).reset();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final status = _state;
    final failed = status.status == PairingStatus.failed;
    final success = status.status == PairingStatus.success;
    final busy = !failed && !success;

    final title = switch (status.status) {
      PairingStatus.checking => '正在连接服务端…',
      PairingStatus.loggingIn => '已连接，正在验证访问密码…',
      PairingStatus.success => '绑定成功',
      PairingStatus.failed => '绑定失败',
      PairingStatus.idle => '正在准备…',
    };

    return PopScope(
      // 流程进行中禁止返回关闭，避免用户误触后状态悬挂。
      canPop: false,
      child: Dialog(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DshRadius.card),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.x6,
              DshSpace.x6,
              DshSpace.x6,
              DshSpace.x4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: DshMotion.fast,
                      child: _StatusIcon(
                        key: ValueKey(status.status),
                        failed: failed,
                        success: success,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DshSpace.x4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: context.dshText.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.foreground,
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: DshSpace.x2),
                  Text(
                    status.message,
                    textAlign: TextAlign.center,
                    style: context.dshText.bodySmall?.copyWith(
                      color: p.dangerRed,
                      height: 1.4,
                    ),
                  ),
                ],
                if (_serverLabel(status.origin) case final server?) ...[
                  const SizedBox(height: DshSpace.x2),
                  Text(
                    server,
                    textAlign: TextAlign.center,
                    style: context.dshText.bodySmall?.copyWith(
                      color: p.secondaryText,
                    ),
                  ),
                ],
                const SizedBox(height: DshSpace.x5),
                if (busy)
                  TextButton(
                    onPressed: _close,
                    style: TextButton.styleFrom(
                      foregroundColor: p.secondaryText,
                      minimumSize: const Size.fromHeight(DshTouch.minTarget),
                    ),
                    child: const Text('取消'),
                  )
                else if (failed) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _retry,
                      child: const Text('重试'),
                    ),
                  ),
                  TextButton(
                    onPressed: _close,
                    style: TextButton.styleFrom(
                      foregroundColor: p.secondaryText,
                      minimumSize: const Size.fromHeight(DshTouch.minTarget),
                    ),
                    child: const Text('关闭'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 只展示非默认端口的 host:port，保持弹窗信息简洁。
  String? _serverLabel(Uri? origin) {
    if (origin == null) return null;
    final defaultPort = origin.scheme == 'https' ? 443 : 80;
    return origin.hasPort && origin.port != defaultPort
        ? '${origin.host}:${origin.port}'
        : origin.host;
  }
}

class _StatusIcon extends StatelessWidget {
  final bool failed;
  final bool success;

  const _StatusIcon({super.key, required this.failed, required this.success});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    if (success) {
      return Icon(Icons.check_circle_rounded, size: 44, color: p.planGreen);
    }
    if (failed) {
      return Icon(Icons.error_rounded, size: 44, color: p.dangerRed);
    }
    return SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(strokeWidth: 3, color: p.foreground),
    );
  }
}
