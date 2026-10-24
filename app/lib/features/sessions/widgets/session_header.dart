import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/common.dart';

/// 会话页头部：返回圆钮 + 标题/主机副标题 + 右侧「文件夹 / ⋯」胶囊。
class SessionHeader extends StatelessWidget {
  final String? title;

  /// 副标题展示的服务端名称（缺省回退主机名）。
  final String? serverName;
  final VoidCallback onBack;

  /// 打开工作区信息 sheet。
  final VoidCallback onFolder;
  final VoidCallback onMore;

  const SessionHeader({
    super.key,
    required this.title,
    required this.serverName,
    required this.onBack,
    required this.onFolder,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.x4,
        DshSpace.x2,
        DshSpace.x3,
        DshSpace.x2,
      ),
      child: Row(
        children: [
          CircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            onTap: onBack,
          ),
          const SizedBox(width: DshSpace.x4),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title ?? '新任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.titleLarge,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.computer_outlined,
                      size: 13,
                      color: p.secondaryText,
                    ),
                    const SizedBox(width: DshSpace.x1),
                    Flexible(
                      child: Text(
                        serverName ?? '本地服务端',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.dshText.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: DshSpace.x2),
          _HeaderActionsPill(onFolder: onFolder, onMore: onMore),
        ],
      ),
    );
  }
}

/// 右侧浮起胶囊：文件夹 / 更多两个触控区。
class _HeaderActionsPill extends StatelessWidget {
  final VoidCallback onFolder;
  final VoidCallback onMore;

  const _HeaderActionsPill({required this.onFolder, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(DshRadius.pill),
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(DshRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PillIconButton(
              icon: Icons.folder_outlined,
              tooltip: '工作区',
              onTap: onFolder,
            ),
            _PillIconButton(
              icon: Icons.more_horiz,
              tooltip: '更多',
              onTap: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _PillIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _PillIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: Icon(icon, size: 20, color: p.foreground)),
        ),
      ),
    );
  }
}
