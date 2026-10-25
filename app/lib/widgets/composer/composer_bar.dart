/// 会话页输入条：附件栏 + 输入行 + 底部工具行。
///
/// 布局对齐 Qoder 桌面端 composer：卡片内输入内容上方独立一行显示计划
/// chip 与附件卡片；输入框独占一行；底行左侧为「+」圆钮（指令与附件
/// 统一入口）与盾牌权限钮，右侧为模型选择与 34px 停止/发送圆钮。会话
/// 模式只在新建任务页选择（会话开始后宿主固定预设）。
/// - 计划模式在「+」菜单中开关，经 /plan 落笔生效；
/// - 主按钮按会话状态切换：有内容→发送；运行中且无内容→停止（收起态胶囊
///   同样生效）；空闲且无内容→禁用态发送；
/// - 未聚焦且无内容（文字+附件）且未进入计划模式时收起为单行胶囊（对齐
///   Qoder 移动端参考样式），聚焦或出现内容后展开为完整输入卡。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
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
  final ComposerViewData view;
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

  void _syncEnvironment(ComposerViewData view) {
    _controller.attachments.updateLimits(view.imageLimits);
    _controller.syncEnvironment(
      ComposerEnvironment(
        ready: view.ready,
        running: view.running,
        offline: view.offline,
        planMode: view.planActive,
        workspaceName: view.cwd,
      ),
    );
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      _controller.closeMenu();
      // 失焦时清除一次性展开请求，允许回到收起态。
      if (_expandRequested && mounted) setState(() => _expandRequested = false);
    }
    // 聚焦/失焦驱动重建，切换收起态与展开态。
    if (mounted) setState(() {});
  }

  /// 点击展开请求（一次性）：收起态点击后先据此展开挂载输入框，键盘
  /// 真正弹起（viewInsets>0）或出现内容后即由常规条件接管；键盘没起来
  /// 且无内容时在 build 中复位，避免卡在展开态。
  bool _expandRequested = false;

  /// 收起态：键盘未激活、无任何内容（文字+附件）且未进入计划模式时，输入条
  /// 退化为单行胶囊（左「+」+ 占位文字 + 右侧发送/停止圆钮），对齐参考样式。
  ///
  /// 会话运行中同样收起，此时右侧圆钮显示停止，不展开也能中止回合。
  ///
  /// 用键盘可见性而非 FocusNode.hasFocus 判定：移动端键盘收起后 Flutter
  /// 仍保留焦点，按 hasFocus 会一直保持展开，不符合「键盘未激活即收起」。
  bool get _collapsed =>
      !_expandRequested &&
      MediaQuery.viewInsetsOf(context).bottom <= 0 &&
      !_controller.hasContent &&
      // 计划模式激活期保持展开：计划 chip 只在展开卡顶部渲染，塌回收起态
      // 会丢失状态展示（也发生在空内容下切计划模式弹层收起键盘的场景）。
      !_controller.environment.planMode;

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
    // 键盘真正弹起后交给 viewInsets 常规条件接管，清除一次性展开请求。
    if (_expandRequested && MediaQuery.viewInsetsOf(context).bottom > 0) {
      _expandRequested = false;
    }
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

  /// 收起态单行胶囊：左「+」+ 占位文字 + 右侧发送/停止圆钮（对齐参考图）。
  ///
  /// 中间不是真实 TextField——两个 TextField 抢焦点会导致激活事件冲突，
  /// 这里只放一个占位文本，点击胶囊任意处换出展开态的真实输入框。
  Widget _buildCollapsedRow({required Key key}) {
    final p = context.dsh;
    final ready = widget.view.ready;
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 参考图无灰色圆底，用裸「+」图标钮，功能同展开态底行「+」。
        InkWell(
          borderRadius: BorderRadius.circular(DshRadius.pill),
          onTap: ready ? _showCommandSheet : null,
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
          child: InkWell(
            borderRadius: BorderRadius.circular(DshRadius.pill),
            onTap: _expandAndFocus,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Text(
                _controller.placeholderText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.dshText.bodyMedium?.copyWith(
                  color: p.secondaryText,
                ),
              ),
            ),
          ),
        ),
        // 右侧主钮随会话状态切换：运行中→停止；空闲→发送箭头（点击展开并聚焦）。
        if (widget.view.running)
          PrimaryRoundButton(
            icon: Icons.stop_rounded,
            size: DshButton.composer,
            // color: p.accentBlue,
            semanticLabel: '停止',
            onTap: widget.actions.cancelTurn,
          )
        else
          PrimaryRoundButton(
            icon: Icons.arrow_upward_rounded,
            size: DshButton.composer,
            semanticLabel: '发送',
            // 无语音能力：空闲时点击聚焦输入框，弹起键盘并展开为完整输入卡。
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

  /// 圆钮/占位文字点击：先强制展开让真实输入框挂载，下一帧再聚焦并唤起
  /// 键盘。收起态下输入框尚未挂载，直接 requestFocus 落在未附加的
  /// FocusNode 上是空操作；键盘收起后焦点也可能被保留，故再显式
  /// TextInput.show 保证键盘弹回。
  void _expandAndFocus() {
    setState(() => _expandRequested = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  Widget _buildField() {
    final p = context.dsh;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKey,
      child: TextField(
        controller: _controller.text,
        focusNode: _focus,
        minLines: 2,
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
    final ready = widget.view.ready;
    const gap = SizedBox(width: DshSpace.x2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _RoundToolButton(
          icon: Icons.add,
          tooltip: '指令与附件',
          onPressed: ready ? _showCommandSheet : null,
        ),
        gap,
        _PermissionButton(
          tooltip: '权限',
          onPressed: ready ? widget.actions.showPermissionPicker : null,
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
                      widget.view.selectedModel ?? '未选择模型',
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

  /// 底行右侧合并后的唯一主按钮：有内容→发送；运行中且无内容→停止；
  /// 空闲且无内容→禁用态发送（图标占位，不可点）。
  /// 「发出全部排队消息」一键插队已移除，排队消息经队列条目逐条处理。
  List<Widget> _buildActions() {
    if (_controller.hasContent) {
      return [
        PrimaryRoundButton(
          icon: Icons.arrow_upward_rounded,
          size: DshButton.composer,
          semanticLabel: '发送',
          onTap: _controller.canSend ? _controller.submit : null,
        ),
      ];
    }
    if (_controller.environment.running) {
      return [
        PrimaryRoundButton(
          icon: Icons.stop_rounded,
          size: DshButton.composer,
          // color: context.dsh.accentBlue,
          semanticLabel: '停止',
          onTap: widget.actions.cancelTurn,
        ),
      ];
    }
    return [
      PrimaryRoundButton(
        icon: Icons.arrow_upward_rounded,
        size: DshButton.composer,
        semanticLabel: '发送',
        onTap: null,
      ),
    ];
  }

  // ------------------------------------------------------------------ 弹层入口

  /// 「添加」菜单：目标 / 计划模式 / 附件 / 宿主命令表（对齐 Qoder 底行「+」）。
  void _showCommandSheet() {
    final actions = widget.actions;
    final controller = _controller;
    // Future 必须在 builder 外取一次：sheet 拖拽/键盘动画期间 builder 逐帧
    // 重跑，内联创建 Future 会让 FutureBuilder 每帧重置回 loading，列表塌陷闪烁。
    final commands = actions.hostCommands();
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
              _LauncherTile(
                icon: Icons.assignment_outlined,
                label: '计划模式',
                trailing: widget.view.planActive
                    ? const Icon(Icons.check_rounded, size: 18)
                    : null,
                onTap: () => closeAndRun(actions.togglePlan),
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
                future: commands,
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
