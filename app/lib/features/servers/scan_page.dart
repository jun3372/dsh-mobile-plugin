import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'pairing_controller.dart';

/// 扫码绑定页：mobile_scanner 取流 + 手动输入降级表单。
/// （ohos 平台实现由 dependency_overrides 指向 CPF-Flutter 移植提供。）
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _controller = MobileScannerController();
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pairingControllerProvider, (previous, next) {
      if (next.status == PairingStatus.success) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    return Scaffold(
      // 相机页恒黑白字，不随主题（SPEC §1.2）。
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text('扫码绑定'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _CameraUnavailable(onManual: _openManualInput),
          ),
          _ScanFrameOverlay(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '对准 dsh 宿主插件面板上的配对二维码',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: DshSpace.x6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleButton(
                      icon: Icons.flashlight_on_outlined,
                      tooltip: '手电筒',
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      onTap: _toggleTorch,
                    ),
                    const SizedBox(width: DshSpace.x6),
                    CircleButton(
                      icon: Icons.keyboard_alt_outlined,
                      tooltip: '手动输入',
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      onTap: _openManualInput,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildStatusBanner(),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final state = ref.watch(pairingControllerProvider);
    if (state.status == PairingStatus.idle ||
        state.status == PairingStatus.success) {
      return const SizedBox.shrink();
    }
    final text = switch (state.status) {
      PairingStatus.checking => '正在连接服务端…',
      PairingStatus.loggingIn => '已连接，正在验证访问密码…',
      PairingStatus.failed => state.message,
      _ => '',
    };
    return Positioned(
      left: 24,
      right: 24,
      bottom: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: state.status == PairingStatus.failed
              ? context.dsh.dangerRed.withValues(alpha: 0.92)
              : Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(DshRadius.codeBlock),
        ),
        child: Row(
          children: [
            if (state.status != PairingStatus.failed)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            if (state.status != PairingStatus.failed) const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white),
              onPressed: () {
                // 中途取消配对：恢复扫码，允许重新识别或改用手动输入。
                setState(() => _handling = false);
                ref.read(pairingControllerProvider.notifier).reset();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _handling = true;
      // 识别成功：触觉 + 提示，随后进入连接流程。
      unawaited(HapticFeedback.mediumImpact());
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showDshSnack(context, '二维码识别成功，正在连接服务端…');
      }
      await ref.read(pairingControllerProvider.notifier).bind(raw);
      return;
    }
  }

  Future<void> _toggleTorch() => _controller.toggleTorch();

  void _openManualInput() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _ManualInputSheet(
        onSubmit: (raw) {
          _handling = true;
          ref.read(pairingControllerProvider.notifier).bind(raw);
        },
      ),
    );
  }
}

/// 手动输入表单放独立 StatefulWidget：随键盘实时调整留白，并在关闭时释放控制器。
class _ManualInputSheet extends StatefulWidget {
  final ValueChanged<String> onSubmit;

  const _ManualInputSheet({required this.onSubmit});

  @override
  State<_ManualInputSheet> createState() => _ManualInputSheetState();
}

class _ManualInputSheetState extends State<_ManualInputSheet> {
  final _originController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _originController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    var originText = _originController.text.trim();
    if (originText.isEmpty) {
      setState(() => _error = '请填写网关地址');
      return;
    }
    if (!originText.contains('://')) originText = 'http://$originText';
    final password = _passwordController.text.trim();
    final String raw;
    if (password.isEmpty) {
      raw = originText;
    } else {
      final uri = Uri.tryParse(originText);
      if (uri == null || uri.host.isEmpty) {
        setState(() => _error = '网关地址格式不正确');
        return;
      }
      final origin = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      );
      raw = origin.replace(queryParameters: {'token': password}).toString();
    }
    Navigator.of(context).pop();
    widget.onSubmit(raw);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DshSpace.x5,
        DshSpace.x5,
        DshSpace.x5,
        DshSpace.x5 + keyboardInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('手动输入绑定', style: context.dshText.titleLarge),
            const SizedBox(height: 6),
            Text(
              '填写宿主网关地址与访问密码，如 http://192.168.1.50:39081',
              style: context.dshText.bodySmall?.copyWith(
                fontSize: 13,
                color: p.secondaryText,
              ),
            ),
            const SizedBox(height: DshSpace.x4),
            TextField(
              controller: _originController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '网关地址'),
            ),
            const SizedBox(height: DshSpace.x3),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '访问密码'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: context.dshText.bodySmall?.copyWith(color: p.dangerRed),
              ),
            ],
            const SizedBox(height: DshSpace.x4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _submit, child: const Text('绑定')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFrameOverlay extends StatelessWidget {
  final Widget child;

  const _ScanFrameOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(DshRadius.scanFrame),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  final VoidCallback onManual;

  const _CameraUnavailable({required this.onManual});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: Colors.white70,
            ),
            const SizedBox(height: 12),
            const Text(
              '相机不可用（模拟器或未授权）',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              onPressed: onManual,
              child: const Text('改用手动输入绑定'),
            ),
          ],
        ),
      ),
    );
  }
}
