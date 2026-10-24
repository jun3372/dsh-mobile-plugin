import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/approval_request.dart';
import '../../../core/session/session_replica.dart' show PlanReview;
import 'plan_detail_page.dart';

/// 是否为计划模式退出审批：宿主真实工具名是 snake_case 的 exit_plan_mode，
/// 归一化（去下划线/空格/连字符 + 小写）后与 exitplanmode 比较。
bool isExitPlanToolName(String toolName) =>
    toolName.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '') == 'exitplanmode';

/// `approval/request` waterfall 的工具审批卡。
/// 计划模式 exit_plan_mode 审批按 Qoder 截图渲染为专属「计划」确认卡：
/// 表头「计划 ›」（点击整行/预览区进入 PlanDetailPage 全文页）、
/// markdown 计划限高预览 + 底部渐隐，底部两态按钮——
/// 收起态「建议修改 / 允许一次」，展开态反馈输入框 +「允许一次 / 提交反馈」。
class ApprovalCard extends StatefulWidget {
  final ApprovalRequest approval;
  final Future<void> Function(bool allowed) onAnswer;

  /// 计划卡「提交反馈」：先拒绝审批（让 Agent 留在计划模式），再以用户消息发送反馈。
  final Future<void> Function(String feedback)? onFeedback;

  /// 计划正文 markdown（来自 exit_plan_mode 的 tool/call arguments.plan）。
  /// 缺省时计划卡退回纯文本摘要版式。
  final String? planText;

  const ApprovalCard({
    super.key,
    required this.approval,
    required this.onAnswer,
    this.onFeedback,
    this.planText,
  });

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  bool _submitting = false;
  bool _feedbackOpen = false;
  final _feedback = TextEditingController();

  /// 计划模式退出审批：走「计划」专属版式。
  bool get _isPlanApproval => isExitPlanToolName(widget.approval.toolName);

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _answer(bool allowed) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onAnswer(allowed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitFeedback() async {
    final text = _feedback.text.trim();
    if (_submitting || text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onFeedback?.call(text);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPlanApproval) return _buildPlanCard(context);
    return _buildGenericCard(context);
  }

  /// 计划正文预览：有 markdown 正文时限高渲染、超长内容底部渐隐；
  /// 无正文（宿主未带计划全文）退回纯文本摘要。
  Widget get _planPreviewText {
    final plan = widget.planText?.trim();
    if (plan == null || plan.isEmpty) {
      return Text(
        widget.approval.detail,
        style: context.dshText.bodyMedium?.copyWith(height: 1.5),
      );
    }
    return PlanMarkdownPreview(markdown: plan, onTap: _openPlanDetail);
  }

  /// 进入计划详情全文页。
  void _openPlanDetail() {
    final plan = widget.planText?.trim();
    final markdown = (plan == null || plan.isEmpty)
        ? widget.approval.detail
        : plan;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailPage(markdown: markdown),
      ),
    );
  }

  /// 计划确认卡：复刻 Qoder 截图布局。
  Widget _buildPlanCard(BuildContext context) {
    final p = context.dsh;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(DshRadius.card),
        border: Border.all(color: p.divider),
        // 计划卡底部阴影减淡到约 1/3，只留一点浮起感
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: p.shadow.a * 0.35),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _openPlanDetail,
            borderRadius: BorderRadius.circular(DshRadius.card),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 20,
                    color: p.foreground,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '计划',
                    style: context.dshText.titleMedium?.copyWith(
                      color: p.foreground,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: p.tertiaryText,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: p.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _planPreviewText,
                if (_feedbackOpen) ...[
                  const SizedBox(height: 12),
                  _FeedbackField(
                    controller: _feedback,
                    onChanged: () {
                      if (mounted) setState(() {});
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _PlanButton(
                        label: _feedbackOpen ? '允许一次' : '建议修改',
                        primary: false,
                        onTap: _submitting
                            ? null
                            : () {
                                if (_feedbackOpen) {
                                  _answer(true);
                                } else {
                                  setState(() => _feedbackOpen = true);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _feedbackOpen
                          ? _PlanButton(
                              label: '提交反馈',
                              primary: true,
                              disabled: _feedback.text.trim().isEmpty,
                              loading: _submitting,
                              onTap: _submitFeedback,
                            )
                          : _PlanButton(
                              label: '允许一次',
                              primary: true,
                              loading: _submitting,
                              onTap: () => _answer(true),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 通用工具审批卡：保持原样式。
  Widget _buildGenericCard(BuildContext context) {
    final p = context.dsh;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(DshRadius.card),
        border: Border.all(color: p.runningYellow.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: p.runningYellow,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '需要你的确认',
                  style: context.dshText.bodySmall?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.foreground,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  widget.approval.toolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.approval.detail,
            style: context.dshText.bodySmall?.copyWith(
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting ? null : () => _answer(false),
                child: Text('拒绝', style: TextStyle(color: p.dangerRed)),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _submitting ? null : () => _answer(true),
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('允许一次'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 宿主 exit_plan_mode 计划评审（userQuestions intent=plan-review）拆两处渲染：
/// - 本内容卡进对话流：表头「计划 ›」+ 计划 markdown 限高预览，点击进全文页；
/// - 应答按钮在底部输入区位，见 [PlanReviewActionBar]。
class PlanReviewContentCard extends StatelessWidget {
  final PlanReview review;

  const PlanReviewContentCard({super.key, required this.review});

  void _openPlanDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailPage(markdown: review.plan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(DshRadius.card),
        border: Border.all(color: p.divider),
        // 计划卡底部阴影减淡到约 1/3，只留一点浮起感
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: p.shadow.a * 0.35),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openPlanDetail(context),
            borderRadius: BorderRadius.circular(DshRadius.card),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 20,
                    color: p.foreground,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '计划',
                    style: context.dshText.titleMedium?.copyWith(
                      color: p.foreground,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: p.tertiaryText,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: p.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: PlanMarkdownPreview(
              markdown: review.plan,
              onTap: () => _openPlanDetail(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 计划评审动作条：占据底部输入区位，只渲染应答按钮（计划正文在对话流的
/// [PlanReviewContentCard]）。应答按宿主契约回填：「允许一次」= 选中 approve
/// 标签；「建议修改→提交反馈」= 选中 decline 标签 + custom 反馈文本。
class PlanReviewActionBar extends StatefulWidget {
  final PlanReview review;
  final Future<void> Function() onApprove;
  final Future<void> Function(String feedback) onFeedback;

  const PlanReviewActionBar({
    super.key,
    required this.review,
    required this.onApprove,
    required this.onFeedback,
  });

  @override
  State<PlanReviewActionBar> createState() => _PlanReviewActionBarState();
}

class _PlanReviewActionBarState extends State<PlanReviewActionBar> {
  bool _submitting = false;
  bool _feedbackOpen = false;
  final _feedback = TextEditingController();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onApprove();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitFeedback() async {
    final text = _feedback.text.trim();
    if (_submitting || text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onFeedback(text);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final decline = widget.review.decline;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(DshRadius.card),
        border: Border.all(color: p.divider),
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_outlined, size: 18, color: p.foreground),
              const SizedBox(width: 8),
              Text(
                '计划',
                style: context.dshText.bodyMedium?.copyWith(
                  color: p.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '已写好计划，可以开始执行。',
            style: context.dshText.bodyMedium?.copyWith(
              height: 1.4,
              color: p.foreground,
            ),
          ),
          if (_feedbackOpen) ...[
            const SizedBox(height: 10),
            _FeedbackField(
              controller: _feedback,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
          ],
          const SizedBox(height: 12),
          if (decline == null)
            _PlanButton(
              label: '允许一次',
              primary: true,
              loading: _submitting,
              onTap: _approve,
            )
          else
            Row(
              children: [
                Expanded(
                  child: _PlanButton(
                    label: _feedbackOpen ? '允许一次' : '建议修改',
                    primary: false,
                    onTap: _submitting
                        ? null
                        : () {
                            if (_feedbackOpen) {
                              _approve();
                            } else {
                              setState(() => _feedbackOpen = true);
                            }
                          },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _feedbackOpen
                      ? _PlanButton(
                          label: '提交反馈',
                          primary: true,
                          disabled: _feedback.text.trim().isEmpty,
                          loading: _submitting,
                          onTap: _submitFeedback,
                        )
                      : _PlanButton(
                          label: '允许一次',
                          primary: true,
                          loading: _submitting,
                          onTap: _approve,
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 计划卡反馈输入框：浅灰圆角容器 + 无边框多行输入。
class _FeedbackField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _FeedbackField({required this.controller, required this.onChanged});

  @override
  State<_FeedbackField> createState() => _FeedbackFieldState();
}

class _FeedbackFieldState extends State<_FeedbackField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(widget.onChanged);
  }

  @override
  void didUpdateWidget(_FeedbackField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(widget.onChanged);
      widget.controller.addListener(widget.onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(widget.onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Container(
      decoration: BoxDecoration(
        color: p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.codeBlock),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: TextField(
        controller: widget.controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        style: context.dshText.bodyMedium?.copyWith(height: 1.5),
        decoration: InputDecoration(
          isCollapsed: true,
          hintText: '计划中有哪些需要调整？',
          hintStyle: context.dshText.bodyMedium?.copyWith(
            color: p.secondaryText,
          ),
        ),
      ),
    );
  }
}

/// 计划卡底部按钮：圆角矩形，primary=黑底白字，否则浅灰底黑字。
class _PlanButton extends StatelessWidget {
  final String label;
  final bool primary;
  final bool disabled;
  final bool loading;
  final VoidCallback? onTap;

  const _PlanButton({
    required this.label,
    required this.primary,
    this.disabled = false,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final enabled = onTap != null && !disabled && !loading;
    final background = !enabled
        ? p.chipGray
        : primary
        ? p.foreground
        : p.chipGray;
    final foreground = !enabled
        ? p.tertiaryText
        : primary
        ? p.onForeground
        : p.foreground;
    return SizedBox(
      height: 48,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primary ? p.onForeground : p.foreground,
                    ),
                  )
                : Text(
                    label,
                    style: context.dshText.labelLarge?.copyWith(
                      fontSize: 15,
                      color: foreground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
