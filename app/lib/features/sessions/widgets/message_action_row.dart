import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/models/transcript_node.dart';

/// assistant 消息底部操作行：复制 / 赞 / 踩 / 分享 + 时间戳。
/// 赞/踩/分享为本地态占位（宿主暂无对应接口）。
class MessageActionRow extends StatefulWidget {
  final TranscriptNode node;

  const MessageActionRow({super.key, required this.node});

  @override
  State<MessageActionRow> createState() => _MessageActionRowState();
}

class _MessageActionRowState extends State<MessageActionRow> {
  int? _vote; // 1 赞 / -1 踩 / null 未选

  String? get _timeLabel {
    final ms = widget.node.timeMs;
    if (ms == null || ms <= 0) return null;
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return sameDay ? '$hh:$mm' : '${t.month}月${t.day}日 $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          _ActionIcon(
            icon: Icons.copy_outlined,
            tooltip: '复制',
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: widget.node.text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          _ActionIcon(
            icon: _vote == 1 ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
            tooltip: '赞',
            color: _vote == 1 ? p.accentBlue : null,
            onTap: () => setState(() => _vote = _vote == 1 ? null : 1),
          ),
          _ActionIcon(
            icon: _vote == -1
                ? Icons.thumb_down_alt
                : Icons.thumb_down_alt_outlined,
            tooltip: '踩',
            color: _vote == -1 ? p.dangerRed : null,
            onTap: () => setState(() => _vote = _vote == -1 ? null : -1),
          ),
          _ActionIcon(
            icon: Icons.ios_share_outlined,
            tooltip: '分享',
            onTap: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('分享能力开发中'))),
          ),
          const Spacer(),
          if (_timeLabel != null)
            Text(
              _timeLabel!,
              style: context.dshText.labelSmall?.copyWith(
                color: p.tertiaryText,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 28,
          child: Icon(icon, size: 16, color: color ?? p.secondaryText),
        ),
      ),
    );
  }
}
