import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// 列表头部的「加载更早」入口。
class LoadOlderRow extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const LoadOlderRow({super.key, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: loading ? null : onTap,
        icon: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.history_rounded, size: 16),
        label: Text(
          loading ? '正在加载…' : '加载更早的消息',
          style: context.dshText.bodySmall?.copyWith(
            fontSize: 13,
            color: context.dsh.secondaryText,
          ),
        ),
      ),
    );
  }
}
