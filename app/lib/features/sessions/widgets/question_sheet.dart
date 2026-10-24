import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/errors.dart';
import '../../../core/models/dsh_models.dart';
import '../../../core/services/dsh_api.dart' show QuestionAnswer;
import '../../../core/session/session_replica.dart';
import '../../../widgets/common.dart';

/// 剥掉选项 label 尾部的「(推荐)/(Recommended)」后缀，返回净化 label 与推荐标记。
/// 服务端契约（QuestionOption）无 recommended 字段，官方以 label 后缀表达。
({String label, bool recommended}) splitRecommended(String raw) {
  final pattern = RegExp(
    r'\s*[（(](?:推荐|recommended)[）)]\s*$',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(raw);
  if (match == null) return (label: raw, recommended: false);
  return (label: raw.substring(0, match.start).trimRight(), recommended: true);
}

/// 弹窗主按钮的紧凑样式：全局 filledButtonTheme 高 52，sheet 内压到 38。
ButtonStyle _compactFillButton(BuildContext context) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 38),
    padding: const EdgeInsets.symmetric(horizontal: DshSpace.x4),
    textStyle: context.dshText.labelLarge?.copyWith(fontSize: 13),
  );
}

/// 弹出提问应答 sheet（复刻 Qoder 截图布局）。一次只承载一个 prompt。
/// [onAnswer]/[onSkip] 失败需抛出 AppException，由 sheet 统一提示并保留选择。
Future<void> showQuestionSheet(
  BuildContext context, {
  required SessionQuestionPrompt prompt,
  int? remainingMs,
  required Future<void> Function(List<QuestionAnswer> answers) onAnswer,
  Future<void> Function()? onSkip,
  bool useRootNavigator = true,
}) {
  return showDshSheet<void>(
    context,
    heightFactor: 0.75,
    useRootNavigator: useRootNavigator,
    builder: (sheetContext) => _QuestionSheetBody(
      prompt: prompt,
      initialRemainingMs: remainingMs,
      onAnswer: onAnswer,
      onSkip: onSkip,
    ),
  );
}

class _QuestionSheetBody extends StatefulWidget {
  final SessionQuestionPrompt prompt;
  final int? initialRemainingMs;
  final Future<void> Function(List<QuestionAnswer> answers) onAnswer;
  final Future<void> Function()? onSkip;

  const _QuestionSheetBody({
    required this.prompt,
    required this.onAnswer,
    this.initialRemainingMs,
    this.onSkip,
  });

  @override
  State<_QuestionSheetBody> createState() => _QuestionSheetBodyState();
}

class _QuestionSheetBodyState extends State<_QuestionSheetBody> {
  final _selected = <String, Set<String>>{};
  final _custom = <String, TextEditingController>{};
  bool _submitting = false;

  /// 倒计时展示用本地 tick；超时拒绝由 SessionNotifier 权威驱动，不在此处。
  int? _remainingMs;
  Timer? _ticker;

  List<UserQuestion> get _questions => widget.prompt.questions;

  /// 单题 + 单选 + 有选项：点选项即提交（instantPick）；否则统一「提交回答」。
  bool get _instantPick {
    if (_questions.length != 1) return false;
    final question = _questions.first;
    return !question.multiSelect && question.options.isNotEmpty;
  }

  /// 多题（非 instantPick）按页展示：一屏一题，上一个/下一个导航。
  bool get _paginated => !_instantPick && _questions.length > 1;

  int _page = 0;

  bool get _isLastPage => _page >= _questions.length - 1;

  void _goPage(int page) {
    if (page < 0 || page >= _questions.length || page == _page) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _page = page);
  }

  bool get _canSkip =>
      widget.prompt.viaWaterfall && widget.onSkip != null && !_submitting;

  @override
  void initState() {
    super.initState();
    _remainingMs = widget.initialRemainingMs;
    if (_remainingMs != null && _remainingMs! > 0) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        final next = (_remainingMs ?? 0) - 1000;
        if (!mounted) return;
        setState(() => _remainingMs = next <= 0 ? 0 : next);
        if (next <= 0) timer.cancel();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final controller in _custom.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Set<String> _selectionOf(String questionId) =>
      _selected.putIfAbsent(questionId, () => <String>{});

  TextEditingController _customOf(String questionId) =>
      _custom.putIfAbsent(questionId, () => TextEditingController());

  String? _customText(String questionId) {
    final text = _custom[questionId]?.text.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  bool get _allAnswered => _questions.every(
    (question) =>
        _selectionOf(question.id).isNotEmpty ||
        _customText(question.id) != null,
  );

  Future<void> _run(Future<void> Function() action) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on AppException catch (e) {
      if (mounted) showDshError(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toggleOption(UserQuestion question, String label) {
    final selection = _selectionOf(question.id);
    if (question.multiSelect) {
      setState(() {
        selection.contains(label)
            ? selection.remove(label)
            : selection.add(label);
      });
    } else {
      setState(() {
        selection
          ..clear()
          ..add(label);
      });
      _maybeAutoAdvance(question);
    }
  }

  /// 分页模式下单选点完选项：短暂停留露出勾选后自动切到下一题。
  /// 下一题已有答案（用户回页改选）则不抢焦点，留在当前页手动翻页。
  void _maybeAutoAdvance(UserQuestion question) {
    if (!_paginated || question.multiSelect || question.options.isEmpty) return;
    if (_page + 1 >= _questions.length) return;
    final next = _questions[_page + 1];
    final nextAnswered =
        _selected[next.id]?.isNotEmpty == true || _customText(next.id) != null;
    if (nextAnswered) return;
    final target = _page + 1;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted && _page == target - 1) _goPage(target);
    });
  }

  /// confirm 模式统一提交：每题携带 selected + custom。
  Future<void> _submitAll() {
    return _run(
      () => widget.onAnswer([
        for (final question in _questions)
          QuestionAnswer(
            questionId: question.id,
            selected: _selectionOf(question.id).toList(),
            custom: _customText(question.id),
          ),
      ]),
    );
  }

  /// instantPick：点选项 / 提交自定义答案，直接单题回填。
  Future<void> _submitSingle(UserQuestion question, {String? label}) {
    final custom = label == null ? _customText(question.id) : null;
    if (label == null && custom == null) return Future.value();
    return _run(
      () => widget.onAnswer([
        QuestionAnswer(
          questionId: question.id,
          selected: [?label],
          custom: custom,
        ),
      ]),
    );
  }

  Future<void> _skip() {
    return _run(() => widget.onSkip!());
  }

  String _countdownLabel(int ms) {
    final total = ms ~/ 1000;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 单题块（instantPick/confirm/分页共用）；分页时仅渲染当前题。
  Widget _blockFor(UserQuestion question) {
    return _QuestionBlock(
      question: question,
      selected: _selectionOf(question.id),
      checkable: !_instantPick,
      submitting: _submitting,
      onToggle: (label) {
        if (_instantPick) {
          _submitSingle(question, label: label);
        } else {
          _toggleOption(question, label);
        }
      },
      // confirm 模式每题尾部内联自定义框；instantPick 归入底部公共输入行。
      inlineCustom: !_instantPick,
      customController: _customOf(question.id),
      onCustomChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final singleQuestion = _instantPick ? _questions.first : null;
    return Padding(
      // 键盘避让：底栏贴键盘上沿，中部滚动区被压缩。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.x5,
              DshSpace.x1,
              DshSpace.x5,
              DshSpace.x2,
            ),
            child: Row(
              children: [
                Icon(Icons.help_outline_rounded, size: 16, color: p.foreground),
                const SizedBox(width: DshSpace.x2),
                Expanded(
                  child: Text(
                    '请回答以下问题',
                    style: context.dshText.titleMedium?.copyWith(fontSize: 15),
                  ),
                ),
                if (_paginated) ...[
                  _PagePill(label: '${_page + 1}/${_questions.length}'),
                  const SizedBox(width: DshSpace.x2),
                ],
                if (_remainingMs != null)
                  Text(
                    _remainingMs! <= 0
                        ? '等待已超时…'
                        : '剩余 ${_countdownLabel(_remainingMs!)}',
                    style: context.dshText.labelSmall?.copyWith(
                      fontSize: 11,
                      color: _remainingMs! <= 30000
                          ? p.dangerRed
                          : p.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.prompt.state == 'continued')
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.x5,
                0,
                DshSpace.x5,
                DshSpace.x2,
              ),
              child: Text(
                '该提问已离开实时窗口，提交后将直接回填',
                style: context.dshText.labelSmall?.copyWith(
                  color: p.tertiaryText,
                ),
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              // 切页时重置滚动位置。
              key: ValueKey(_paginated ? 'page-$_page' : 'all'),
              padding: const EdgeInsets.only(bottom: DshSpace.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_paginated)
                    _blockFor(_questions[_page.clamp(0, _questions.length - 1)])
                  else
                    for (final question in _questions) _blockFor(question),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: p.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.x5,
              DshSpace.x2,
              DshSpace.x5,
              DshSpace.x2 + 2,
            ),
            child: Row(
              children: [
                if (_instantPick && singleQuestion != null) ...[
                  Icon(Icons.edit_outlined, size: 16, color: p.tertiaryText),
                  const SizedBox(width: DshSpace.x2),
                  Expanded(
                    child: TextField(
                      controller: _customOf(singleQuestion.id),
                      onChanged: (_) {
                        setState(() {});
                      },
                      onSubmitted: (_) => _submitSingle(singleQuestion),
                      style: context.dshText.bodySmall?.copyWith(fontSize: 13),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        hintText: '或输入自定义答案',
                        hintStyle: context.dshText.bodySmall?.copyWith(
                          fontSize: 12,
                          color: p.tertiaryText,
                        ),
                      ),
                    ),
                  ),
                ] else if (_paginated) ...[
                  if (_page > 0) ...[
                    _NavPill(
                      icon: Icons.chevron_left_rounded,
                      onTap: _submitting ? null : () => _goPage(_page - 1),
                    ),
                    const SizedBox(width: DshSpace.x2),
                  ],
                  Expanded(
                    child: FilledButton(
                      // 末页才提交；未答完保持禁用，可回上一页补选。
                      onPressed: _isLastPage
                          ? (_submitting || !_allAnswered ? null : _submitAll)
                          : (_submitting ? null : () => _goPage(_page + 1)),
                      style: _compactFillButton(context),
                      child: Text(_isLastPage ? '提交回答' : '下一个问题'),
                    ),
                  ),
                  const SizedBox(width: DshSpace.x3),
                ] else ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: (_submitting || !_allAnswered)
                          ? null
                          : _submitAll,
                      style: _compactFillButton(context),
                      child: const Text('提交回答'),
                    ),
                  ),
                  const SizedBox(width: DshSpace.x3),
                ],
                if (_canSkip)
                  _SkipPill(
                    onTap: _submitting ? null : _skip,
                    padding: _instantPick
                        ? const EdgeInsets.only(left: DshSpace.x3)
                        : EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个问题块：灰色 header → 加粗问题 → detail → 垂直选项行。
class _QuestionBlock extends StatelessWidget {
  final UserQuestion question;
  final Set<String> selected;
  final bool checkable;
  final bool submitting;
  final void Function(String label) onToggle;
  final bool inlineCustom;
  final TextEditingController customController;
  final VoidCallback onCustomChanged;

  const _QuestionBlock({
    required this.question,
    required this.selected,
    required this.checkable,
    required this.submitting,
    required this.onToggle,
    required this.inlineCustom,
    required this.customController,
    required this.onCustomChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.x5,
        DshSpace.x1,
        DshSpace.x5,
        DshSpace.x2 + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.header != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                question.header!,
                style: context.dshText.bodySmall?.copyWith(
                  fontSize: 11,
                  color: p.secondaryText,
                ),
              ),
            ),
          Text(
            question.question,
            style: context.dshText.bodySmall?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (question.detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                question.detail!,
                style: context.dshText.bodySmall?.copyWith(
                  fontSize: 11,
                  color: p.tertiaryText,
                ),
              ),
            ),
          const SizedBox(height: DshSpace.x2),
          for (final option in question.options)
            _OptionTile(
              label: option.label,
              description: option.description,
              selected: selected.contains(option.label),
              checkable: checkable,
              onTap: submitting ? null : () => onToggle(option.label),
            ),
          if (question.options.isEmpty || inlineCustom)
            Padding(
              padding: const EdgeInsets.only(top: DshSpace.x2),
              child: Container(
                decoration: BoxDecoration(
                  color: p.chipGray,
                  borderRadius: BorderRadius.circular(DshRadius.codeBlock),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: DshSpace.x2 + 2,
                  vertical: DshSpace.x2,
                ),
                child: TextField(
                  controller: customController,
                  onChanged: (_) => onCustomChanged(),
                  minLines: 1,
                  maxLines: 3,
                  style: context.dshText.bodySmall?.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    hintText: '或输入自定义答案',
                    hintStyle: context.dshText.bodySmall?.copyWith(
                      fontSize: 12,
                      color: p.tertiaryText,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 选项行：label（+推荐徽标）在上、描述在下，垂直堆叠；选中浅灰底 + 右侧勾。
class _OptionTile extends StatelessWidget {
  final String label;
  final String? description;
  final bool selected;
  final bool checkable;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.label,
    required this.description,
    required this.selected,
    required this.checkable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final split = splitRecommended(label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DshSpace.x1),
      child: Material(
        color: selected ? p.chipGray : Colors.transparent,
        borderRadius: BorderRadius.circular(DshRadius.leading),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(
              horizontal: DshSpace.x2 + 2,
              vertical: DshSpace.x2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              split.label,
                              style: context.dshText.bodySmall?.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: p.foreground,
                              ),
                            ),
                          ),
                          if (split.recommended) ...[
                            const SizedBox(width: DshSpace.x2),
                            const _RecBadge(),
                          ],
                        ],
                      ),
                      if (description != null && description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            description!,
                            style: context.dshText.bodySmall?.copyWith(
                              fontSize: 11,
                              color: p.secondaryText,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (checkable && selected) ...[
                  const SizedBox(width: DshSpace.x2),
                  Icon(Icons.check, size: 16, color: p.foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「推荐」小徽标：chipGray 底、pill 圆角、11px 灰字。
class _RecBadge extends StatelessWidget {
  const _RecBadge();

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DshSpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.pill),
      ),
      child: Text(
        '推荐',
        style: context.dshText.labelSmall?.copyWith(
          fontSize: 11,
          color: p.secondaryText,
        ),
      ),
    );
  }
}

/// 标题行右侧的「1/2」页码胶囊（分页模式）。
class _PagePill extends StatelessWidget {
  final String label;

  const _PagePill({required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DshSpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.pill),
      ),
      child: Text(
        label,
        style: context.dshText.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: p.secondaryText,
        ),
      ),
    );
  }
}

/// 分页导航的圆形小胶囊（上一页）。
class _NavPill extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NavPill({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Material(
      color: p.chipGray,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: p.foreground),
        ),
      ),
    );
  }
}

/// 「跳过」灰色胶囊按钮。
class _SkipPill extends StatelessWidget {
  final VoidCallback? onTap;
  final EdgeInsets padding;

  const _SkipPill({required this.onTap, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: padding,
      child: Material(
        color: p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DshSpace.x3),
              child: Center(
                child: Text(
                  '跳过',
                  style: context.dshText.bodySmall?.copyWith(
                    fontSize: 12,
                    color: p.foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 聊天流内的紧凑「待回答」入口卡：sheet 被关闭后的重入口 + 倒计时/continued 状态。
class QuestionEntryCard extends StatelessWidget {
  final SessionQuestionPrompt prompt;
  final int? remainingMs;
  final VoidCallback onOpen;

  const QuestionEntryCard({
    super.key,
    required this.prompt,
    required this.remainingMs,
    required this.onOpen,
  });

  static String _countdown(int ms) {
    final total = ms ~/ 1000;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final first = prompt.questions.isEmpty ? null : prompt.questions.first;
    final title = first == null ? '提问' : (first.header ?? first.question);
    final timed = remainingMs != null;
    final timedOut = timed && remainingMs! <= 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.codeBlock),
      ),
      child: Row(
        children: [
          Icon(Icons.help_outline_rounded, size: 16, color: p.accentBlue),
          const SizedBox(width: DshSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '待回答：$title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timed
                      ? (timedOut
                            ? '等待已超时，宿主处理中…'
                            : '限时回答，剩余 ${_countdown(remainingMs!)}')
                      : prompt.state == 'continued'
                      ? '已离开实时窗口，提交后直接回填'
                      : 'Agent 等待你的回答',
                  style: context.dshText.labelSmall?.copyWith(
                    color: timed && !timedOut && remainingMs! <= 30000
                        ? p.dangerRed
                        : p.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DshSpace.x2),
          // chipGray 卡上用白底细边小胶囊，避免黑坨坨（对齐 CircleButton 的轻量风格）。
          Material(
            color: p.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DshRadius.pill),
              side: BorderSide(color: p.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: const SizedBox(
                height: 32,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: DshSpace.x4),
                  child: Center(
                    child: Text(
                      '回答',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
