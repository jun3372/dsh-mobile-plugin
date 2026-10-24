import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/common.dart';

/// 新建会话页输入白卡：文本框 + 「+/权限/计划/模型/发送」工具行。
/// 会话创建前的静态选择（权限/模型/计划）在发送时延迟生效。
class NewTaskInputCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPickAdd;
  final VoidCallback onPickPermission;
  final VoidCallback onPickModel;
  final VoidCallback onTogglePlan;
  final bool planActive;
  final String permissionLabel;
  final String modelLabel;

  const NewTaskInputCard({
    super.key,
    required this.controller,
    required this.focus,
    required this.sending,
    required this.onSend,
    required this.onPickAdd,
    required this.onPickPermission,
    required this.onPickModel,
    required this.onTogglePlan,
    required this.planActive,
    required this.permissionLabel,
    required this.modelLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.x4,
        DshSpace.x4,
        DshSpace.x4,
        DshSpace.x3,
      ),
      child: AnimatedContainer(
        duration: DshMotion.fast,
        curve: DshMotion.curve,
        // SPEC §4：白卡浮起于灰画布，聚焦描边。
        padding: const EdgeInsets.fromLTRB(
          DshSpace.x4,
          DshSpace.x3,
          DshSpace.x3,
          DshSpace.x2,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(DshRadius.inputCard),
          boxShadow: [
            BoxShadow(
              color: p.shadow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 5,
              autofocus: true,
              style: context.dshText.bodyLarge,
              decoration: InputDecoration.collapsed(
                hintText: '描述你想要构建的内容，/ 调用指令，@ 文件或对话',
                hintStyle: context.dshText.bodyLarge?.copyWith(
                  color: p.secondaryText,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
            const SizedBox(height: DshSpace.x2),
            Row(
              children: [
                _RoundTool(icon: Icons.add, tooltip: '添加', onTap: onPickAdd),
                const SizedBox(width: DshSpace.x1),
                _CardChip(
                  icon: Icons.shield_outlined,
                  label: permissionLabel,
                  onTap: onPickPermission,
                ),
                const SizedBox(width: DshSpace.x1),
                _CardChip(
                  icon: Icons.event_note_outlined,
                  label: '计划',
                  active: planActive,
                  onTap: onTogglePlan,
                ),
                const SizedBox(width: DshSpace.x1),
                Flexible(
                  child: _CardChip(
                    icon: null,
                    label: modelLabel,
                    onTap: onPickModel,
                  ),
                ),
                const Spacer(),
                sending
                    ? const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : PrimaryRoundButton(
                        icon: Icons.arrow_upward_rounded,
                        semanticLabel: '发送',
                        onTap: controller.text.trim().isEmpty ? null : onSend,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆形工具钮（「+」）。
class _RoundTool extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundTool({
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
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: p.foreground),
        ),
      ),
    );
  }
}

/// 卡内小胶囊：图标 + 文本 + 下拉箭头，激活态反色。
class _CardChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CardChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final color = active ? p.foreground : p.secondaryText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DshRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DshSpace.x2,
          vertical: DshSpace.x1 + 1,
        ),
        decoration: BoxDecoration(
          color: active ? p.accentBlue.withValues(alpha: 0.12) : p.chipGray,
          borderRadius: BorderRadius.circular(DshRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.dshText.bodySmall?.copyWith(
                  fontSize: 13,
                  color: active ? p.foreground : p.midText,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: color),
          ],
        ),
      ),
    );
  }
}
