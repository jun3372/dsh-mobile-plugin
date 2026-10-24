import 'dart:math';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/errors.dart';

/// 白色圆形图标按钮（返回钮等，SPEC §3：44×44、图标 20、1px 细边 + 轻阴影）。
class CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// 扫码页等特殊场景的白底黑图标恒定样式。
  final Color? backgroundColor;
  final Color? foregroundColor;

  const CircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final background = backgroundColor ?? p.surface;
    final foreground = onTap == null
        ? p.tertiaryText
        : (foregroundColor ?? p.foreground);
    final button = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: Border.all(color: p.divider),
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: foreground),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 任务状态点（SPEC §3 实测：进行中 16dp 虚线黄圈，其余 7dp 灰点）。
class StatusDot extends StatelessWidget {
  final bool running;
  final double size;

  const StatusDot({super.key, required this.running, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    if (running) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _DashedCirclePainter(color: p.runningYellow),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: p.dotGray, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;

  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2 - 1;
    final center = Offset(size.width / 2, size.height / 2);
    final arc = 2 * pi / 10;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * arc,
        arc * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 空态视图（SPEC §3：图标 44、文案 14）。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DshSpace.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: p.dotGray),
            const SizedBox(height: DshSpace.x3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.dshText.bodyMedium?.copyWith(
                color: p.secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错误视图（含重试）。
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final message = switch (error) {
      AppException e => e.userMessage,
      _ => '加载失败，请稍后重试',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DshSpace.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: p.dotGray),
            const SizedBox(height: DshSpace.x3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.dshText.bodyMedium?.copyWith(
                color: p.secondaryText,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: DshSpace.x4),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

/// 黑色圆形发送/语音主按钮（SPEC §3：44，深色下反转为白底黑标）。
class PrimaryRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final String? semanticLabel;

  const PrimaryRoundButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final background = onTap == null ? p.chipGray : (color ?? p.foreground);
    final foreground = onTap == null ? p.tertiaryText : p.onForeground;
    final button = Material(
      color: background,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.5, color: foreground),
        ),
      ),
    );
    if (semanticLabel == null) return button;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: button,
    );
  }
}

/// 底部弹层标题（18/w700，配合全局拖拽把手）。
class DshSheetTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const DshSheetTitle({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.x5,
        DshSpace.x1,
        DshSpace.x5,
        DshSpace.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.dshText.titleLarge),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: DshSpace.x1),
              child: Text(
                subtitle!,
                style: context.dshText.bodySmall?.copyWith(
                  color: p.secondaryText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部弹层分组小标题（12/w500）。
class DshSheetCaption extends StatelessWidget {
  final String text;

  const DshSheetCaption({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.x5,
        DshSpace.x4,
        DshSpace.x5,
        DshSpace.x1,
      ),
      child: Text(
        text,
        style: context.dshText.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: p.secondaryText,
        ),
      ),
    );
  }
}

/// 输入区选项菜单：统一从底部弹出，先收起键盘；内容超高时内部滚动。
/// [useRootNavigator] 默认 true；页面内自动弹出场景可传 false，避免盖住其他路由。
Future<T?> showDshSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double heightFactor = 0.7,
  bool useRootNavigator = true,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * heightFactor,
      ),
      child: builder(sheetContext),
    ),
  );
}

/// 统一 SnackBar（SPEC §1：错误红底白字，常规反色底）。
void showDshSnack(BuildContext context, String message) {
  final p = context.dsh;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: context.dshText.bodyMedium?.copyWith(color: p.onForeground),
      ),
      backgroundColor: p.foreground,
    ),
  );
}

void showDshError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: context.dshText.bodyMedium?.copyWith(color: Colors.white),
      ),
      backgroundColor: context.dsh.dangerRed,
    ),
  );
}

/// 右上 popover 菜单选项。
class DshPopoverOption {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const DshPopoverOption({
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });
}

/// popover 分组：可选小标题 + 若干选项。
class DshPopoverSection {
  final String? caption;
  final List<DshPopoverOption> options;

  const DshPopoverSection({this.caption, required this.options});
}

/// 右上浮层菜单（SPEC §4 实测：宽 224、圆角 24、选项行 52、选中标记在标签左侧、
/// 分组之间通栏细分割线）。
/// [anchorContext] 为触发按钮的 BuildContext，菜单贴其右下角弹出。
Future<void> showDshPopoverMenu(
  BuildContext anchorContext, {
  required List<DshPopoverSection> sections,
}) async {
  final box = anchorContext.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject()! as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );
  final p = DshPalette.of(anchorContext);
  await showMenu<void>(
    context: anchorContext,
    position: position,
    color: p.surface,
    elevation: 6,
    shadowColor: p.shadow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DshRadius.menu),
      side: BorderSide(color: p.divider),
    ),
    constraints: const BoxConstraints.tightFor(width: 224),
    items: [
      for (final (index, section) in sections.indexed) ...[
        if (index > 0) const _PopoverDividerEntry(),
        if (section.caption != null)
          _PopoverCaptionEntry(label: section.caption!),
        for (final option in section.options) _PopoverOptionEntry(option),
      ],
    ],
  );
}

/// 分组之间的通栏 1px 分割线。
class _PopoverDividerEntry extends PopupMenuEntry<void> {
  const _PopoverDividerEntry();

  @override
  double get height => 1;

  @override
  bool represents(void value) => false;

  @override
  State<_PopoverDividerEntry> createState() => _PopoverDividerEntryState();
}

class _PopoverDividerEntryState extends State<_PopoverDividerEntry> {
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 1, child: ColoredBox(color: context.dsh.divider));
}

class _PopoverCaptionEntry extends PopupMenuEntry<void> {
  final String label;

  const _PopoverCaptionEntry({required this.label});

  @override
  double get height => 36;

  @override
  bool represents(void value) => false;

  @override
  State<_PopoverCaptionEntry> createState() => _PopoverCaptionEntryState();
}

class _PopoverCaptionEntryState extends State<_PopoverCaptionEntry> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.x4,
        DshSpace.x3,
        DshSpace.x4,
        DshSpace.x1,
      ),
      child: Text(
        widget.label,
        style: context.dshText.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: context.dsh.secondaryText,
        ),
      ),
    );
  }
}

class _PopoverOptionEntry extends PopupMenuEntry<void> {
  final DshPopoverOption option;

  const _PopoverOptionEntry(this.option);

  @override
  double get height => 52;

  @override
  bool represents(void value) => false;

  @override
  State<_PopoverOptionEntry> createState() => _PopoverOptionEntryState();
}

class _PopoverOptionEntryState extends State<_PopoverOptionEntry> {
  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final option = widget.option;
    return InkWell(
      onTap: option.onTap == null
          ? null
          : () {
              Navigator.of(context).pop();
              option.onTap!();
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.only(left: DshSpace.x2, right: DshSpace.x4),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: option.icon == null
                    ? (option.selected
                          ? Icon(Icons.check, size: 20, color: p.foreground)
                          : null)
                    : Icon(option.icon, size: 20, color: p.foreground),
              ),
              Expanded(
                child: Text(option.label, style: context.dshText.bodyMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
