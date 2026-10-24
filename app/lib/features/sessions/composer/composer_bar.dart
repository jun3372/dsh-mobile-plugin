/// 会话页输入条：顶行选择器 + 附件栏 + 输入行 + 底部工具行。
///
/// 布局对齐 Qoder 桌面端 composer：卡片上方一行「工作区 / 会话模式」选择器；
/// 卡片内输入内容上方独立一行显示计划 chip 与附件卡片；输入框独占一行；
/// 底行左侧为「+」圆钮（指令与附件统一入口）与盾牌权限钮，右侧为模型选择
/// 与 34px 停止/发送圆钮。
/// - 会话模式在「标准模式 / 计划模式」间切换，计划模式经 /plan 落笔生效；
/// - 运行中且输入为空时，主按钮变成「发出全部排队消息」；
/// - 未聚焦且无内容（文字+附件）且未运行时收起为单行胶囊（对齐 Qoder 移动端
///   参考样式），聚焦或出现内容后展开为完整输入卡。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/models/dsh_session.dart';
import '../../../widgets/common.dart';
import '../session_providers.dart';
import 'attachment_rail.dart';
import 'attachment_sources.dart';
import 'composer_controller.dart';
import 'trigger_menu_view.dart';
import 'trigger_sources.dart';

/// 输入条需要的会话级动作，由页面注入（避免 composer 反向依赖 riverpod）。
class ComposerActions {
  final VoidCallback showModelPicker;
  final VoidCallback showPermissionPicker;
  final VoidCallback togglePlan;
  final VoidCallback showGoalEditor;
  final VoidCallback cancelTurn;
  final Future<List<TriggerItem>> Function() hostCommands;

  const ComposerActions({
    required this.showModelPicker,
    required this.showPermissionPicker,
    required this.togglePlan,
    required this.showGoalEditor,
    required this.cancelTurn,
    required this.hostCommands,
  });
}

class ComposerBar extends StatefulWidget {
  final ComposerController controller;
  final SessionViewState view;
  final AttachmentSources sources;
  final ComposerActions actions;
  final ValueChanged<String> onError;

  const ComposerBar({
    super.key,
    required this.controller,
    required this.view,
    required this.sources,
    required this.actions,
    required this.onError,
  });

  @override
  State<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<ComposerBar> {
  final _focus = FocusNode();

  ComposerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    _syncEnvironment(widget.view);
  }

  @override
  void didUpdateWidget(ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.attachments.updateLimits(widget.view.imageLimits);
    if (widget.view != oldWidget.view) _syncEnvironment(widget.view);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _syncEnvironment(SessionViewState view) {
    _controller.attachments.updateLimits(view.imageLimits);
    _controller.syncEnvironment(
      ComposerEnvironment(
        ready: view.hasSnapshot && !view.waitingSnapshot,
        running: view.running,
        offline: view.isOffline,
        planMode: view.plan?.active ?? false,
        workspaceName: view.cwd,
        hasQueued: view.queue.isNotEmpty,
      ),
    );
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _controller.closeMenu();
    // 聚焦/失焦驱动重建，切换收起态与展开态。
    if (mounted) setState(() {});
  }

  /// 收起态：键盘未激活、无任何内容（文字+附件）且会话未运行时，输入条
  /// 退化为单行胶囊（左「+」+ 占位文字 + 右侧聚焦圆钮），对齐参考样式。
  ///
  /// 用键盘可见性而非 FocusNode.hasFocus 判定：移动端键盘收起后 Flutter
  /// 仍保留焦点，按 hasFocus 会一直保持展开，不符合「键盘未激活即收起」。
  bool get _collapsed =>
      MediaQuery.viewInsetsOf(context).bottom <= 0 &&
      !_controller.hasContent &&
      !_controller.environment.running;

  /// 硬件键盘：Esc 关闭菜单，↑/↓ 在菜单内移动高亮。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_controller.menuOpen) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _controller.closeMenu();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _controller.menu.moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _controller.menu.moveHighlight(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TriggerMenuView(controller: _controller.menu),
            if (_controller.notice case final notice?)
              _NoticeBar(message: notice, onDismiss: _controller.dismissNotice),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_collapsed) ...[
                    _buildTopRow(),
                    const SizedBox(height: DshSpace.x2),
                  ],
                  AnimatedContainer(
                    duration: DshMotion.fast,
                    curve: DshMotion.curve,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
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
                    child: AnimatedSwitcher(
                      duration: DshMotion.fast,
                      switchInCurve: DshMotion.curve,
                      switchOutCurve: DshMotion.curve,
                      child: _collapsed
                          ? _buildCollapsedRow(key: const ValueKey('collapsed'))
                          : _buildExpandedCard(key: const ValueKey('expanded')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 卡片上方选择器行：工作区与会话模式均靠左排列（对齐 Qoder 顶行）。
  Widget _buildTopRow() {
    final view = widget.view;
    final planActive = view.plan?.active ?? false;
    return Row(
      children: [
        _MetaChip(
          icon: Icons.folder_outlined,
          label: folderNameOf(view.cwd) ?? '默认工作区',
          chevron: true,
          onTap: _showWorkspaceSheet,
        ),
        const SizedBox(width: DshSpace.x2),
        _MetaChip(
          icon: Icons.adjust,
          label: planActive ? '计划模式' : '标准模式',
          chevron: true,
          onTap: view.hasSnapshot ? _showModeSheet : null,
        ),
      ],
    );
  }

  /// 收起态单行胶囊：左「+」+ 占位文字 + 右侧黑色聚焦圆钮（对齐参考图）。
  Widget _buildCollapsedRow({required Key key}) {
    final p = context.dsh;
    final view = widget.view;
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 参考图无灰色圆底，用裸「+」图标钮，功能同展开态底行「+」。
        InkWell(
          borderRadius: BorderRadius.circular(DshRadius.pill),
          onTap: view.hasSnapshot ? _showCommandSheet : null,
          child: Tooltip(
            message: '指令与附件',
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.add, size: 24, color: p.midText),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildField(),
          ),
        ),
        PrimaryRoundButton(
          icon: Icons.arrow_upward_rounded,
          size: DshButton.composer,
          semanticLabel: '输入',
          // 无语音能力：点击聚焦输入框，弹起键盘并展开为完整输入卡。
          onTap: _expandAndFocus,
        ),
      ],
    );
  }

  /// 展开态完整输入卡：附件/计划栏 + 输入行 + 底行工具按钮。
  Widget _buildExpandedCard({required Key key}) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_controller.environment.planMode ||
            !_controller.attachments.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: DshSpace.x2),
            child: AttachmentRail(
              store: _controller.attachments,
              leading: _controller.environment.planMode
                  ? _PlanChip(onRemove: widget.actions.togglePlan)
                  : null,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
          child: _buildField(),
        ),
        _buildBottomRow(),
      ],
    );
  }

  /// 圆钮点击：聚焦输入框并唤起键盘。键盘收起后焦点可能仍被保留，
  /// 单纯 requestFocus 是空操作，需再显式 TextInput.show 弹回键盘。
  void _expandAndFocus() {
    _focus.requestFocus();
    if (_focus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }
  }

  Widget _buildField() {
    final p = context.dsh;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKey,
      child: TextField(
        controller: _controller.text,
        focusNode: _focus,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.send,
        style: context.dshText.bodyMedium,
        decoration: InputDecoration.collapsed(
          hintText: _controller.placeholderText,
          hintStyle: context.dshText.bodyMedium?.copyWith(
            color: p.secondaryText,
          ),
        ),
        onSubmitted: (_) => _controller.submit(),
      ),
    );
  }

  /// 底行：「+」与盾牌权限钮在左，模型选择靠右紧挨停止/发送钮（对齐 Qoder）。
  Widget _buildBottomRow() {
    final view = widget.view;
    const gap = SizedBox(width: DshSpace.x2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _RoundToolButton(
          icon: Icons.add,
          tooltip: '指令与附件',
          onPressed: view.hasSnapshot ? _showCommandSheet : null,
        ),
        gap,
        _PermissionButton(
          tooltip: '权限',
          onPressed: view.hasSnapshot
              ? widget.actions.showPermissionPicker
              : null,
        ),
        const Spacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: InkWell(
            borderRadius: BorderRadius.circular(DshRadius.pill),
            onTap: widget.actions.showModelPicker,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      view.selectedModel ?? '未选择模型',
                      overflow: TextOverflow.ellipsis,
                      style: context.dshText.bodySmall?.copyWith(
                        color: context.dsh.midText,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: context.dsh.secondaryText,
                  ),
                ],
              ),
            ),
          ),
        ),
        gap,
        ..._buildActions(),
      ],
    );
  }

  /// 运行中：停止 + 主按钮；空输入时主按钮改为发出全部排队消息。
  List<Widget> _buildActions() {
    final running = _controller.environment.running;
    final hasContent = _controller.hasContent;
    final stop = running
        ? Material(
            color: context.dsh.accentBlue,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.actions.cancelTurn,
              child: SizedBox(
                width: DshButton.composer,
                height: DshButton.composer,
                child: Icon(
                  Icons.stop_rounded,
                  size: 17,
                  // 深色 accentBlue 较亮时用黑标保证对比。
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          )
        : null;
    final Widget primary;
    if (running && !hasContent) {
      primary = PrimaryRoundButton(
        icon: Icons.queue_music_rounded,
        size: DshButton.composer,
        color: context.dsh.foreground,
        semanticLabel: '发出全部排队消息',
        onTap: _controller.environment.hasQueued ? _controller.steerAll : null,
      );
    } else {
      primary = PrimaryRoundButton(
        icon: Icons.arrow_upward_rounded,
        size: DshButton.composer,
        semanticLabel: '发送',
        onTap: _controller.canSend ? _controller.submit : null,
      );
    }
    if (stop == null) return [primary];
    return [stop, const SizedBox(width: DshSpace.x2), primary];
  }

  // ------------------------------------------------------------------ 弹层入口

  /// 「添加」菜单：目标 / 附件 / 宿主命令表（对齐 Qoder 底行「+」）。
  void _showCommandSheet() {
    final actions = widget.actions;
    final controller = _controller;
    showDshSheet<void>(
      context,
      heightFactor: 0.75,
      // 整页滚动：标题、附件入口与命令表一起滚动，不再只滚命令列表。
      builder: (sheetContext) {
        void closeAndRun(void Function() body) {
          Navigator.of(sheetContext).pop();
          body();
        }

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DshSheetTitle(title: '添加'),
              _LauncherTile(
                icon: Icons.flag_outlined,
                label: '设定目标',
                onTap: () => closeAndRun(actions.showGoalEditor),
              ),
              const _LauncherSectionTitle(label: '附件'),
              _LauncherTile(
                icon: Icons.photo_library_outlined,
                label: '相册图片',
                onTap: () => closeAndRun(() => _pickImages(camera: false)),
              ),
              _LauncherTile(
                icon: Icons.photo_camera_outlined,
                label: '拍照',
                onTap: () => closeAndRun(() => _pickImages(camera: true)),
              ),
              _LauncherTile(
                icon: Icons.description_outlined,
                label: '文件',
                onTap: () => closeAndRun(_pickFiles),
              ),
              const _LauncherSectionTitle(label: '宿主命令'),
              FutureBuilder<List<TriggerItem>>(
                future: actions.hostCommands(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(DshSpace.x5),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final items = snapshot.data ?? const <TriggerItem>[];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in items)
                        _LauncherTile(
                          icon: Icons.terminal_outlined,
                          label: item.title,
                          caption: item.subtitle,
                          onTap: () {
                            final pick = item.onPick;
                            closeAndRun(() {
                              if (pick != null) {
                                pick();
                              } else {
                                controller.runCommand(item.title);
                              }
                            });
                          },
                        ),
                      const SizedBox(height: DshSpace.x2),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 工作区菜单：展示末段名与完整路径。
  void _showWorkspaceSheet() {
    final cwd = widget.view.cwd ?? '';
    showDshSheet<void>(
      context,
      builder: (sheetContext) {
        void close() => Navigator.of(sheetContext).pop();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DshSheetTitle(title: '工作区'),
            if (cwd.isEmpty)
              _LauncherTile(
                icon: Icons.folder_off_outlined,
                label: '未指定工作区目录',
                onTap: close,
              )
            else
              _LauncherTile(
                icon: Icons.folder_outlined,
                label: folderNameOf(cwd) ?? cwd,
                caption: cwd,
                onTap: close,
              ),
            const SizedBox(height: DshSpace.x2),
          ],
        );
      },
    );
  }

  /// 会话模式菜单：标准模式 / 计划模式（togglePlan 为开关语义）。
  void _showModeSheet() {
    final planActive = widget.view.plan?.active ?? false;
    showDshSheet<void>(
      context,
      builder: (sheetContext) {
        void close() => Navigator.of(sheetContext).pop();
        void closeAndToggle() {
          Navigator.of(sheetContext).pop();
          widget.actions.togglePlan();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DshSheetTitle(title: '会话模式'),
            _LauncherTile(
              icon: Icons.adjust,
              label: '标准模式',
              trailing: planActive
                  ? null
                  : const Icon(Icons.check_rounded, size: 18),
              onTap: planActive ? closeAndToggle : close,
            ),
            _LauncherTile(
              icon: Icons.assignment_outlined,
              label: '计划模式',
              trailing: planActive
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
              onTap: planActive ? close : closeAndToggle,
            ),
            const SizedBox(height: DshSpace.x2),
          ],
        );
      },
    );
  }

  Future<void> _pickImages({required bool camera}) async {
    final store = _controller.attachments;
    final remaining = store.limits.maxImagesPerMessage - store.imageCount;
    final pick = camera
        ? await widget.sources.capturePhoto()
        : await widget.sources.pickImages(limit: remaining);
    if (!mounted) return;
    if (pick.error case final error?) {
      widget.onError(error);
      return;
    }
    if (pick.paths.isEmpty) return;
    final rejection = await store.addImages(pick.paths);
    if (rejection != null && mounted) widget.onError(rejection.message);
  }

  Future<void> _pickFiles() async {
    final pick = await widget.sources.pickFiles();
    if (!mounted) return;
    if (pick.error case final error?) {
      widget.onError(error);
      return;
    }
    if (pick.paths.isNotEmpty) {
      await _controller.attachments.addFiles(pick.paths);
    }
  }
}

/// 底行圆形工具钮（28，对齐 dsh 底行「+」「📎」同位小圆钮）。
class _RoundToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _RoundToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.chipGray,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: DshButton.tool,
            height: DshButton.tool,
            child: Icon(icon, size: DshIcon.tool, color: p.midText),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool chevron;
  final VoidCallback? onTap;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Material(
      color: p.chipGray,
      borderRadius: BorderRadius.circular(DshRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(DshRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: p.secondaryText),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.labelSmall?.copyWith(color: p.midText),
                ),
              ),
              if (chevron)
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 15,
                  color: p.secondaryText,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 计划模式 chip：绿色图标+文字，点击退出计划模式（显示在输入内容上方）。
class _PlanChip extends StatelessWidget {
  final VoidCallback onRemove;

  const _PlanChip({required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Material(
      color: p.chipGray,
      borderRadius: BorderRadius.circular(DshRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(DshRadius.pill),
        onTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_outlined, size: 16, color: p.planGreen),
              const SizedBox(width: 6),
              Text(
                '计划',
                style: context.dshText.bodySmall?.copyWith(
                  color: p.planGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.close_rounded, size: 15, color: p.planGreen),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底行盾牌权限钮：裸图标 + 下拉箭头，不带文字（对齐 Qoder 盾牌入口）。
class _PermissionButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;

  const _PermissionButton({required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(DshRadius.pill),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 17, color: p.midText),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 14,
                color: p.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _NoticeBar({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: p.chipGray,
          borderRadius: BorderRadius.circular(DshRadius.input),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: context.dshText.bodySmall?.copyWith(color: p.midText),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _LauncherSectionTitle extends StatelessWidget {
  final String label;

  const _LauncherSectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.x5,
        DshSpace.x3,
        DshSpace.x5,
        DshSpace.x1,
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _LauncherTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? caption;
  final Widget? trailing;
  final VoidCallback onTap;

  const _LauncherTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: context.dsh.midText),
      title: Text(label),
      subtitle: switch (caption) {
        null => null,
        final text => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      },
      trailing: trailing,
      onTap: onTap,
    );
  }
}
