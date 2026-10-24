import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// 浮层中清晰行副本的 key（对齐校验与调试入口）。
const sessionRowPreviewKey = Key('session-row-preview');

/// 会话长按上下文菜单的一条动作。
///
/// [onTap] 在浮层关闭之后执行，动作内部的异步与错误提示由调用方负责。
class SessionMenuAction {
  final String label;
  final IconData icon;

  /// 文字与图标色（如 dangerRed），默认走主文本色。
  final Color? color;
  final VoidCallback? onTap;

  const SessionMenuAction({
    required this.label,
    required this.icon,
    this.color,
    this.onTap,
  });
}

/// 上下文菜单浮层的关闭句柄（列表滚动、页面销毁等场景需要主动收起）。
abstract final class SessionContextMenu {
  static BuildContext? _current;

  /// 当前是否有浮层打开。
  static bool get isOpen => _current != null;

  /// 关闭当前浮层；未打开时为空操作。
  static void dismissIfOpen() {
    final context = _current;
    _current = null;
    if (context == null || !context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }
}

/// 在 [anchorRect]（屏幕坐标，即被长按会话行的矩形）处弹出全屏高斯模糊的
/// 上下文菜单：整页（含头部与 FAB）被模糊，只有该行以 [preview] 重绘保持清晰，
/// 菜单卡贴其下方，空间不足时翻到上方。
Future<void> showSessionContextMenu(
  BuildContext anchorContext, {
  required Rect anchorRect,
  required Widget preview,
  required List<SessionMenuAction> actions,
}) {
  return showGeneralDialog<void>(
    context: anchorContext,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: '会话操作菜单',
    // 遮罩由浮层自绘，才能与模糊同步淡入。
    barrierColor: Colors.transparent,
    transitionDuration: DshMotion.normal,
    // 路由默认 FadeTransition 会把副本行一起淡入，这里关掉、由浮层自行编排。
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
    pageBuilder: (context, _, _) => _SessionContextMenuLayer(
      anchorRect: anchorRect,
      preview: preview,
      actions: actions,
    ),
  );
}

class _SessionContextMenuLayer extends StatefulWidget {
  final Rect anchorRect;
  final Widget preview;
  final List<SessionMenuAction> actions;

  const _SessionContextMenuLayer({
    required this.anchorRect,
    required this.preview,
    required this.actions,
  });

  @override
  State<_SessionContextMenuLayer> createState() =>
      _SessionContextMenuLayerState();
}

class _SessionContextMenuLayerState extends State<_SessionContextMenuLayer> {
  /// 高斯模糊稳态 sigma（再大在低端机上掉帧，参考稿观感 ≈10 已足够）。
  static const _blurSigma = 10.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SessionContextMenu._current = context;
  }

  @override
  void dispose() {
    if (SessionContextMenu._current == context) {
      SessionContextMenu._current = null;
    }
    super.dispose();
  }

  /// 菜单卡度量：宽 224（窄屏收缩）、行高 52（与参考稿一致，项间不加分割线）。
  double _menuWidth(double screenW) =>
      screenW < 224 + DshSpace.x6 ? screenW - DshSpace.x6 : 224;

  double _menuHeight() => widget.actions.length * 52.0;

  /// 默认贴行下方，越界则翻到行上方（与参考稿一致）。
  double _menuTop(Rect viewport) {
    final height = _menuHeight();
    final below = widget.anchorRect.bottom + DshSpace.x2;
    if (below + height <= viewport.bottom - DshSpace.x3) return below;
    return (widget.anchorRect.top - DshSpace.x2 - height).clamp(
      viewport.top + DshSpace.x3,
      viewport.bottom,
    );
  }

  double _menuLeft(double screenW) {
    final width = _menuWidth(screenW);
    return widget.anchorRect.left.clamp(
      DshSpace.x5,
      (screenW - width - DshSpace.x5).clamp(DshSpace.x5, screenW),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)!.animation!;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = DshMotion.curve.transform(animation.value.clamp(0, 1));
        // 减少动效时不做模糊，只保留纯遮罩淡入。
        final reduceMotion =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        final media = MediaQuery.of(context);
        // 可视区：扣掉状态栏与键盘，决定菜单卡朝下还是朝上。
        final viewport = Rect.fromLTRB(
          0,
          media.padding.top,
          media.size.width,
          media.size.height - media.viewInsets.bottom,
        );
        final dark = media.platformBrightness == Brightness.dark;
        final scrimAlpha = (dark ? 0.28 : 0.12) * t;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (!reduceMotion)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: _blurSigma * t,
                    sigmaY: _blurSigma * t,
                    tileMode: ui.TileMode.clamp,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned.fill(
              // ColoredBox 自身参与命中，需让指针穿透才能「点空白处关闭」。
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: scrimAlpha),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: widget.anchorRect,
              child: IgnorePointer(
                key: sessionRowPreviewKey,
                child: widget.preview,
              ),
            ),
            Positioned(
              left: _menuLeft(media.size.width),
              top: _menuTop(viewport),
              width: _menuWidth(media.size.width),
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * DshSpace.x1),
                  child: _MenuCard(actions: widget.actions),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<SessionMenuAction> actions;

  const _MenuCard({required this.actions});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Semantics(
      container: true,
      label: '会话操作菜单',
      child: Material(
        color: p.surface,
        elevation: 6,
        shadowColor: p.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DshRadius.menu),
          side: BorderSide(color: p.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final action in actions) _ActionTile(action: action)],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final SessionMenuAction action;

  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final color = action.color ?? p.foreground;
    return InkWell(
      onTap: () {
        SessionContextMenu.dismissIfOpen();
        action.onTap?.call();
      },
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.x4),
          child: Row(
            children: [
              Icon(action.icon, size: DshIcon.action, color: color),
              const SizedBox(width: DshSpace.x3),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.bodyLarge?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
