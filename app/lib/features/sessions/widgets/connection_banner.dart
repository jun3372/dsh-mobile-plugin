import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/mux/dsh_mux_client.dart';

/// 断线/重连横幅；连接正常时完全隐藏。
class ConnectionBanner extends StatelessWidget {
  final MuxConnectionState state;
  final bool waitingSnapshot;
  final String? error;
  final VoidCallback onRetry;

  const ConnectionBanner({
    super.key,
    required this.state,
    required this.waitingSnapshot,
    required this.onRetry,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final offline =
        state == MuxConnectionState.waiting ||
        state == MuxConnectionState.closed;
    final connecting = state == MuxConnectionState.connecting;
    if (!offline && !connecting && error == null) {
      return const SizedBox.shrink();
    }
    final message =
        error ??
        (offline
            ? (waitingSnapshot ? '连接已断开，正在恢复会话…' : '连接已断开，正在重连…')
            : '正在连接会话…');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: error != null ? p.dangerRed.withValues(alpha: 0.08) : p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.leading),
      ),
      child: Row(
        children: [
          if (connecting)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              error != null ? Icons.error_outline : Icons.cloud_off_outlined,
              size: 16,
              color: error != null ? p.dangerRed : p.secondaryText,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.dshText.bodySmall?.copyWith(
                color: error != null ? p.dangerRed : p.secondaryText,
              ),
            ),
          ),
          if (offline || error != null)
            GestureDetector(
              onTap: onRetry,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '重试',
                  style: context.dshText.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.accentBlue,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
