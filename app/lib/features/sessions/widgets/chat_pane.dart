import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/errors.dart';
import '../../../core/models/approval_request.dart';
import '../../../core/models/composer_models.dart';
import '../../../core/models/goal_info.dart';
import '../../../core/models/transcript_node.dart';
import '../../../core/session/session_replica.dart';
import '../../../widgets/common.dart';
import 'approval_card.dart';
import 'connection_banner.dart';
import 'load_older_row.dart';
import 'message_action_row.dart';
import 'message_images.dart';
import 'question_sheet.dart';
import 'tool_card.dart';
import 'turn_error_card.dart';
import '../session_providers.dart';

/// 对话面板：连接横幅 + 消息流 + 回到底部，随底部 TabBarView 保持存活。
class ChatPane extends ConsumerStatefulWidget {
  final SessionKey sessionKey;

  const ChatPane({super.key, required this.sessionKey});

  @override
  ConsumerState<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends ConsumerState<ChatPane>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  bool _didInitialScroll = false;
  int _lastNodeCount = 0;
  String? _lastNodeId;

  /// 已自动弹过应答 sheet 的 prompt key（被关闭后不再自动弹，靠入口卡重开）。
  final _autoOpenedKeys = <String>{};
  final _sheetOpenKeys = <String>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final show =
        position.maxScrollExtent > 0 &&
        position.maxScrollExtent - position.pixels > 200;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  bool get _nearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 160;
  }

  SessionKey get _key => widget.sessionKey;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(sessionProvider(_key));
    ref.listen(sessionProvider(_key), (previous, next) {
      final view = next.value;
      if (view == null) return;
      _syncQuestionSheet(view);
      final wasNearBottom = _nearBottom;
      final count = view.nodes.length;
      final lastId = view.nodes.isEmpty ? null : view.nodes.last.id;
      final live = view.nodes.isNotEmpty && view.nodes.last.live;
      final grewAtEnd =
          (count > _lastNodeCount && lastId != _lastNodeId) || live;
      _lastNodeCount = count;
      _lastNodeId = lastId;
      if (!grewAtEnd) return;
      if (!_didInitialScroll) {
        _didInitialScroll = true;
        _jumpToBottom(animate: false);
      } else if (wasNearBottom) {
        _jumpToBottom(animate: live);
      }
    });

    final view = state.value;
    return Column(
      children: [
        if (view != null)
          ConnectionBanner(
            state: view.connection,
            waitingSnapshot: view.waitingSnapshot,
            error: view.connectionError,
            onRetry: () => ref.read(sessionProvider(_key).notifier).reconnect(),
          ),
        Expanded(
          child: state.when(
            skipLoadingOnReload: true,
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (error, _) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(sessionProvider(_key)),
            ),
            data: (view) => _buildMessages(view),
          ),
        ),
      ],
    );
  }

  Widget _buildMessages(SessionViewState view) {
    if (view.nodes.isEmpty &&
        !view.hasPendingInteractions &&
        view.queue.isEmpty &&
        !_hasGoalPlan(view) &&
        !view.hasMore) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        message: '发送第一条消息开始任务',
      );
    }
    if (!_didInitialScroll &&
        (view.nodes.isNotEmpty || view.hasPendingInteractions)) {
      _didInitialScroll = true;
      _jumpToBottom(animate: false);
    }
    final widgets = <Widget>[
      if (view.hasMore || view.loadingOlder)
        LoadOlderRow(loading: view.loadingOlder, onTap: _loadOlder),
      if (_hasGoalPlan(view))
        _GoalPlanCard(view: view, onGoalTap: _showGoalActions),
      for (final node in view.nodes) _buildNode(node),
      for (final approval in view.approvals)
        ApprovalCard(
          key: ValueKey('approval-${approval.eventId}'),
          approval: approval,
          planText: _planTextFor(view, approval),
          onAnswer: (allowed) => _answerApproval(approval.eventId, allowed),
          onFeedback: (text) => _rejectWithFeedback(approval.eventId, text),
        ),
      for (final prompt in view.questions)
        // 计划评审拆两处：正文卡在对话流，应答按钮在底部输入区（见 SessionPage）。
        if (prompt.planReview case final review?)
          PlanReviewContentCard(
            key: ValueKey('plan-review-${prompt.key}'),
            review: review,
          )
        else if (prompt.questions.isNotEmpty)
          QuestionEntryCard(
            key: ValueKey('question-${prompt.key}'),
            prompt: prompt,
            remainingMs: view.questionRemainingMs[prompt.key],
            onOpen: () => _openQuestionSheet(prompt),
          ),
    ];
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          // body 未被键盘压缩（页面 resizeToAvoidBottomInset:false），列表底部
          // 补一段键盘高度，保证最后一条消息能滚到键盘上方可见。
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          itemCount: widgets.length,
          itemBuilder: (context, index) => widgets[index],
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 16,
            bottom: 16,
            child: CircleButton(
              icon: Icons.keyboard_arrow_down_rounded,
              onTap: _jumpToBottom,
            ),
          ),
      ],
    );
  }

  Widget _buildNode(TranscriptNode node) {
    switch (node.kind) {
      case TranscriptKind.user:
        return _buildUserNode(node);
      case TranscriptKind.assistant:
        return _buildAssistantNode(node);
      case TranscriptKind.tool:
        return ToolCard(key: ValueKey(node.id), node: node);
      case TranscriptKind.error:
      case TranscriptKind.notice:
      case TranscriptKind.compaction:
        return TurnNoticeCard(key: ValueKey(node.id), node: node);
    }
  }

  bool _hasGoalPlan(SessionViewState view) =>
      view.goal != null ||
      view.plan?.active == true ||
      view.plan?.pending == true ||
      view.todos.isNotEmpty;

  /// 计划审批正文：exit_plan_mode 的 tool/call arguments 是 {"plan": markdown}，
  /// 按 approval.callId 在转写工具节点里对号取出，供计划卡预览与详情页渲染。
  String? _planTextFor(SessionViewState view, ApprovalRequest approval) {
    if (!isExitPlanToolName(approval.toolName)) return null;
    final callId = approval.callId;
    for (final node in view.nodes.reversed) {
      if (node.kind != TranscriptKind.tool) continue;
      final matched = callId != null
          ? node.toolCallId == callId
          : isExitPlanToolName(node.toolName ?? '');
      if (!matched) continue;
      final raw = node.toolArguments;
      if (raw == null) return null;
      try {
        final args = jsonDecode(raw);
        if (args is Map && args['plan'] is String) {
          final plan = (args['plan'] as String).trim();
          return plan.isEmpty ? null : plan;
        }
      } on FormatException {
        return null;
      }
      return null;
    }
    return null;
  }

  Future<void> _loadOlder() async {
    final before = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final offset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    try {
      await ref.read(sessionProvider(_key).notifier).loadOlder();
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
      return;
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final delta = _scrollController.position.maxScrollExtent - before;
      if (delta > 0) {
        _scrollController.jumpTo(offset + delta);
      }
    });
  }

  Future<void> _answerApproval(String eventId, bool allowed) async {
    try {
      await ref
          .read(sessionProvider(_key).notifier)
          .answerApproval(eventId, allowed: allowed);
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  /// 计划卡「提交反馈」：先拒绝审批让 Agent 留在计划模式，再以用户消息送出反馈。
  Future<void> _rejectWithFeedback(String eventId, String text) async {
    try {
      await ref
          .read(sessionProvider(_key).notifier)
          .answerApproval(eventId, allowed: false);
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
      return;
    }
    if (!mounted) return;
    try {
      await ref.read(sessionProvider(_key).notifier).send(text);
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  /// 新提问到达且本页可见时自动弹一次应答 sheet；其余场景靠入口卡进入。
  void _syncQuestionSheet(SessionViewState view) {
    final live = {
      for (final prompt in view.questions)
        if (prompt.questions.isNotEmpty && prompt.planReview == null)
          prompt.key: prompt,
    };
    _autoOpenedKeys.removeWhere((key) => !live.containsKey(key));
    for (final prompt in live.values) {
      if (_autoOpenedKeys.contains(prompt.key)) continue;
      _autoOpenedKeys.add(prompt.key);
      // 已有 sheet 挂着时不叠加，剩余交给入口卡。
      if (_sheetOpenKeys.isNotEmpty) continue;
      // ChatPane 被 TabBarView keepAlive：后台页不得给用户当前页面盖弹窗。
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) continue;
      _openQuestionSheet(prompt);
    }
  }

  Future<void> _openQuestionSheet(SessionQuestionPrompt prompt) async {
    if (_sheetOpenKeys.contains(prompt.key)) return;
    _sheetOpenKeys.add(prompt.key);
    final notifier = ref.read(sessionProvider(_key).notifier);
    await showQuestionSheet(
      context,
      prompt: prompt,
      remainingMs: ref
          .read(sessionProvider(_key))
          .value
          ?.questionRemainingMs[prompt.key],
      // 失败抛给 sheet：保留已选内容并统一提示。
      onAnswer: (answers) => notifier.answerQuestion(prompt, answers),
      onSkip: prompt.viaWaterfall ? () => notifier.skipQuestion(prompt) : null,
      useRootNavigator: false,
    );
    _sheetOpenKeys.remove(prompt.key);
  }

  Widget _buildUserNode(TranscriptNode node) {
    final p = context.dsh;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          // SPEC §4 实测：画布 #F6F6F6 上气泡为 #E3E3E3（dotGray），四角等半径 12。
          color: node.failed ? p.dangerRed.withValues(alpha: 0.08) : p.dotGray,
          borderRadius: BorderRadius.circular(DshRadius.chatBubble),
        ),
        child: GestureDetector(
          onTap: node.failed ? () => _resend(node.id) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (node.text.isNotEmpty)
                      Text(node.text, style: context.dshText.bodyLarge),
                    if (node.images.isNotEmpty) ...[
                      if (node.text.isNotEmpty) const SizedBox(height: 6),
                      MessageImages(
                        sessionId: _key.sessionId,
                        images: node.images,
                      ),
                    ],
                    if (node.failed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '发送失败，点击重试',
                          style: context.dshText.labelSmall?.copyWith(
                            color: p.dangerRed,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (node.optimistic && !node.failed) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ] else if (node.failed) ...[
                const SizedBox(width: 8),
                Icon(Icons.error_outline, size: 16, color: p.dangerRed),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantNode(TranscriptNode node) {
    final p = context.dsh;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (node.reasoning != null) _ReasoningSection(text: node.reasoning!),
          if (node.text.isNotEmpty)
            MarkdownBody(
              data: node.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: context.dshText.bodyLarge?.copyWith(height: 1.6),
                h1: context.dshText.titleLarge?.copyWith(fontSize: 22),
                h2: context.dshText.titleLarge?.copyWith(fontSize: 20),
                h3: context.dshText.titleLarge,
                codeblockDecoration: BoxDecoration(
                  color: p.chipGray,
                  borderRadius: BorderRadius.circular(DshRadius.codeBlock),
                  border: Border.all(color: p.divider),
                ),
                codeblockPadding: const EdgeInsets.all(DshSpace.x3),
                code: TextStyle(
                  fontSize: 13.5,
                  color: p.foreground,
                  backgroundColor: p.chipGray,
                  fontFamilyFallback: const ['Menlo', 'monospace'],
                ),
                listBullet: context.dshText.bodyLarge,
                blockSpacing: 10,
                a: TextStyle(color: p.accentBlue),
              ),
            ),
          if (node.live)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '正在输出…',
                    style: context.dshText.labelSmall?.copyWith(
                      color: p.tertiaryText,
                    ),
                  ),
                ],
              ),
            ),
          if (node.images.isNotEmpty) ...[
            if (node.text.isNotEmpty) const SizedBox(height: 6),
            MessageImages(sessionId: _key.sessionId, images: node.images),
          ],
          if (!node.live && node.text.isNotEmpty) MessageActionRow(node: node),
        ],
      ),
    );
  }

  Future<void> _resend(String nodeId) async {
    try {
      await ref.read(sessionProvider(_key).notifier).resend(nodeId);
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  /// 把列表拉到底：控制器可能在首帧构建期尚未 attach（进页时的初始滚动），
  /// ListView.builder 的估计高度也会在落底后继续增长——两种情况都逐帧重试，
  /// 直到真正贴底或用完重试预算。
  void _jumpToBottom({bool animate = true}) {
    var remaining = 12;
    void step() {
      if (!mounted || remaining <= 0) return;
      remaining--;
      if (!_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) => step());
        return;
      }
      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      }
      _scrollController.jumpTo(target);
      _handleScroll();
      // 下一帧重估后高度可能继续增长：还没贴底就再追一次。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final pos = _scrollController.position;
        if (pos.pixels < pos.maxScrollExtent - 0.5) step();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => step());
  }

  /// 目标编辑：无目标时新建，有目标时按 CAS 引用改正文。
  void _showGoalEditor() {
    final goal = ref.read(sessionProvider(_key)).value?.goal;
    final controller = TextEditingController(text: goal?.objective ?? '');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(goal == null ? '设定目标' : '编辑目标'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '目标描述'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final objective = controller.text.trim();
              if (objective.isEmpty) return;
              Navigator.of(dialogContext).pop();
              final notifier = ref.read(sessionProvider(_key).notifier);
              try {
                if (goal == null) {
                  await notifier.createGoal(objective);
                } else {
                  await notifier.editGoal(
                    GoalRef(id: goal.id, revision: goal.revision),
                    objective: objective,
                  );
                }
              } on AppException catch (e) {
                if (mounted) _showError(e.userMessage);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 目标卡上的状态操作：暂停 / 恢复 / 完成 / 清除。
  void _showGoalActions(GoalInfo goal) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DshSheetTitle(title: '目标'),
            for (final entry in <(String, String, bool)>[
              if (goal.isActive) ('pause', '暂停目标', false),
              if (!goal.isActive && goal.phase != 'complete')
                ('resume', '恢复目标', false),
              if (goal.phase != 'complete') ('complete', '标记完成', false),
              ('clear', '清除目标', true),
            ])
              ListTile(
                leading: Icon(
                  entry.$3
                      ? Icons.delete_outline
                      : switch (entry.$1) {
                          'pause' => Icons.pause_outlined,
                          'resume' => Icons.play_arrow_outlined,
                          _ => Icons.check_circle_outline,
                        },
                  size: 22,
                  color: entry.$3 ? context.dsh.dangerRed : null,
                ),
                title: Text(entry.$2),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _goalTransition(entry.$1, goal);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 22),
              title: const Text('编辑目标'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showGoalEditor();
              },
            ),
            const SizedBox(height: DshSpace.x2),
          ],
        ),
      ),
    );
  }

  Future<void> _goalTransition(String action, GoalInfo goal) async {
    try {
      await ref
          .read(sessionProvider(_key).notifier)
          .goalTransition(
            action,
            GoalRef(id: goal.id, revision: goal.revision),
          );
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  void _showError(String message) => showDshError(context, message);
}

/// 目标 / 计划 / 待办只读卡片（来自 projections）。
class _GoalPlanCard extends StatelessWidget {
  final SessionViewState view;

  /// 目标行可点：打开状态操作菜单（暂停/恢复/完成/清除/编辑）。
  final void Function(GoalInfo goal)? onGoalTap;

  const _GoalPlanCard({required this.view, this.onGoalTap});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final goal = view.goal;
    final plan = view.plan;
    final todos = view.todos;
    final planVisible = plan != null && (plan.active || plan.pending);
    if (goal == null && !planVisible && todos.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.codeBlock),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (goal != null) ...[
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 15, color: p.secondaryText),
                const SizedBox(width: 6),
                Text(
                  '目标 · ${goal.phaseLabel}',
                  style: context.dshText.bodySmall,
                ),
                const Spacer(),
                if (onGoalTap != null)
                  InkWell(
                    onTap: () => onGoalTap!(goal),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: p.secondaryText,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              goal.objective,
              style: context.dshText.bodyMedium?.copyWith(height: 1.4),
            ),
            if (goal.blockedMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  goal.blockedMessage!,
                  style: context.dshText.bodySmall?.copyWith(
                    color: p.dangerRed,
                  ),
                ),
              ),
          ],
          if (planVisible) ...[
            if (goal != null) const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.assignment_outlined, size: 15, color: p.accentBlue),
                const SizedBox(width: 6),
                Text(
                  plan.active ? '计划模式进行中' : '计划模式切换中…',
                  style: context.dshText.bodySmall?.copyWith(
                    color: p.accentBlue,
                  ),
                ),
              ],
            ),
          ],
          if (todos.isNotEmpty) ...[
            if (goal != null || planVisible) const SizedBox(height: 8),
            for (final todo in todos.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      todo.status == 'completed'
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: todo.status == 'completed'
                          ? p.secondaryText
                          : p.dotGray,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        todo.content,
                        style: context.dshText.bodySmall?.copyWith(
                          fontSize: 13,
                          height: 1.35,
                          color: todo.status == 'completed'
                              ? p.tertiaryText
                              : p.foreground,
                          decoration: todo.status == 'completed'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (todos.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '还有 ${todos.length - 6} 项…',
                  style: context.dshText.labelSmall?.copyWith(
                    color: p.tertiaryText,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 「深度思考」折叠区：assistant reasoning 内容。
class _ReasoningSection extends StatefulWidget {
  final String text;

  const _ReasoningSection({required this.text});

  @override
  State<_ReasoningSection> createState() => _ReasoningSectionState();
}

class _ReasoningSectionState extends State<_ReasoningSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: _expanded,
        onExpansionChanged: (value) => setState(() => _expanded = value),
        leading: Icon(Icons.settings_outlined, size: 18, color: p.midText),
        title: Text(
          '深度思考',
          style: context.dshText.bodySmall?.copyWith(
            fontSize: 14,
            color: p.midText,
          ),
        ),
        trailing: Icon(
          _expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_right_rounded,
          size: 18,
          color: p.secondaryText,
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.chipGray,
              borderRadius: BorderRadius.circular(DshRadius.codeBlock),
            ),
            child: Text(
              widget.text,
              style: context.dshText.bodySmall?.copyWith(
                fontSize: 13,
                color: p.secondaryText,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
