import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../widgets/common.dart';

/// 会话详情弹层数据：由会话页头部标题点击触发。
class SessionDetails {
  final String? title;

  /// 项目名（cwd 末段）。
  final String? projectName;

  /// 任务 ID（sessionId），支持点击复制。
  final String sessionId;

  /// 模型展示名。
  final String? model;

  /// 运行环境（服务端主机名）。
  final String? environment;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SessionDetails({
    required this.sessionId,
    this.title,
    this.projectName,
    this.model,
    this.environment,
    this.createdAt,
    this.updatedAt,
  });
}

/// 从底部弹出当前会话的详情：标题 + 任务 ID（可复制）+ 元数据列表。
Future<void> showSessionDetailsSheet(
  BuildContext context, {
  required SessionDetails details,
}) {
  return showDshSheet<void>(
    context,
    heightFactor: 0.85,
    builder: (sheetContext) => _SessionDetailsSheet(details: details),
  );
}

class _SessionDetailsSheet extends StatelessWidget {
  final SessionDetails details;

  const _SessionDetailsSheet({required this.details});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final text = context.dshText;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：居中标题「详情」+ 右侧关闭圆钮。
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.x5,
                0,
                DshSpace.x5,
                DshSpace.x2,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text('详情', style: text.titleLarge),
                  Align(
                    alignment: Alignment.centerRight,
                    child: CircleButton(
                      icon: Icons.close_rounded,
                      tooltip: '关闭',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.x5,
                DshSpace.x4,
                DshSpace.x5,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    details.title ?? '新任务',
                    style: text.bodyLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (details.projectName case final project?) ...[
                    const SizedBox(height: DshSpace.x2),
                    Text(
                      project,
                      style: text.bodyMedium?.copyWith(color: p.secondaryText),
                    ),
                  ],
                  const SizedBox(height: DshSpace.x4),
                  _TaskIdCard(sessionId: details.sessionId),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DshSpace.x5),
              child: const _FullBleedDivider(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.x5,
                0,
                DshSpace.x5,
                DshSpace.x2,
              ),
              child: Text(
                '元数据',
                style: text.bodyMedium?.copyWith(color: p.secondaryText),
              ),
            ),
            _MetaRow(label: '模型', value: details.model ?? '未选择'),
            _MetaRow(label: '运行环境', value: details.environment ?? '—'),
            if (details.createdAt case final time?)
              _MetaRow(label: '创建时间', value: _formatDshTime(time)),
            if (details.updatedAt case final time?)
              _MetaRow(label: '最后更新时间', value: _formatDshTime(time)),
            const SizedBox(height: DshSpace.x4),
          ],
        ),
      ),
    );
  }
}

/// 任务 ID 灰底卡：标签 + 等宽 ID + 右侧复制钮。
/// 复制成功反馈用图标切换（勾 1.5s 后复原）：弹层盖在页面 Scaffold 之上，
/// SnackBar 会被遮挡，不能用作此处反馈。
class _TaskIdCard extends StatefulWidget {
  final String sessionId;

  const _TaskIdCard({required this.sessionId});

  @override
  State<_TaskIdCard> createState() => _TaskIdCardState();
}

class _TaskIdCardState extends State<_TaskIdCard> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.sessionId));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: BorderRadius.circular(DshRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DshSpace.x4,
          DshSpace.x3,
          DshSpace.x2,
          DshSpace.x3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '任务 ID',
                    style: context.dshText.bodySmall?.copyWith(
                      fontSize: 13,
                      color: p.secondaryText,
                    ),
                  ),
                  const SizedBox(height: DshSpace.x2),
                  SelectableText(
                    widget.sessionId,
                    style: context.dshText.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _copied ? '已复制' : '复制任务 ID',
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 20,
                color: _copied ? p.planGreen : null,
              ),
              onPressed: _copy,
            ),
          ],
        ),
      ),
    );
  }
}

/// 元数据行：左侧标签、右侧取值，整行横向留白。
class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.x5,
        vertical: DshSpace.x3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.dshText.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: DshSpace.x4),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: context.dshText.bodyMedium?.copyWith(
                color: p.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullBleedDivider extends StatelessWidget {
  const _FullBleedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 1, child: ColoredBox(color: context.dsh.divider));
  }
}

/// 详情弹层时间格式：2026年10月24日 02:36（本地时区）。
String _formatDshTime(DateTime time) {
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}年${two(local.month)}月${two(local.day)}日 '
      '${two(local.hour)}:${two(local.minute)}';
}
