import '../models/composer_models.dart';
import '../models/dsh_models.dart';
import '../models/goal_info.dart';
import '../models/pending_submission.dart';
import '../models/plan_state.dart';
import '../models/queued_message.dart';
import '../models/session_event.dart';
import '../models/todo_item.dart';
import '../models/transcript_node.dart';
import '../models/turn_outline.dart';
import '../mux/mux_error.dart';
import '../services/dsh_api.dart';
import 'assistant_stream_folder.dart';
import 'pending_submission_store.dart';
import 'session_follow_client.dart';
import 'transcript_builder.dart';

/// 会话内一条待应答提问（waterfall 或投影中的 continued）。
class SessionQuestionPrompt {
  final String? eventId;
  final String? callId;
  final String agentId;
  final List<UserQuestion> questions;
  final String state;

  /// 宿主侧限时等待（waterfall 请求携带 `wait.timed`）。
  final bool timedWait;

  const SessionQuestionPrompt({
    required this.agentId,
    required this.questions,
    this.eventId,
    this.callId,
    this.state = 'open',
    this.timedWait = false,
  });

  bool get viaWaterfall => eventId != null;

  String get key =>
      callId ?? eventId ?? (questions.isEmpty ? '' : questions.first.id);

  /// exit_plan_mode 计划评审收窄（对齐 Web planReviewOf）：单题、
  /// intent.kind=plan-review、detail 携带计划 markdown、非多选、选项 ≤2
  /// 且含 approve 标签。命中时须用专属计划卡渲染，不走问答弹窗。
  PlanReview? get planReview {
    if (questions.length != 1) return null;
    final question = questions.first;
    if (question.intentKind != 'plan-review') return null;
    final plan = question.detail;
    if (plan == null || plan.trim().isEmpty) return null;
    if (question.multiSelect) return null;
    if (question.options.isEmpty || question.options.length > 2) return null;
    final approve = question.options
        .where((option) => option.label == question.intentApprove)
        .firstOrNull;
    if (approve == null) return null;
    final decline = question.options
        .where((option) => option.label != question.intentApprove)
        .firstOrNull;
    return PlanReview(
      question: question,
      plan: plan,
      approve: approve,
      decline: decline,
    );
  }
}

/// [SessionQuestionPrompt.planReview] 的收窄结果。
class PlanReview {
  final UserQuestion question;

  /// 计划 markdown 正文（问题 detail）。
  final String plan;

  /// 批准选项（intent.approve 命中的 label）。
  final QuestionOption approve;

  /// 继续规划选项（另一项，可能缺省）。
  final QuestionOption? decline;

  const PlanReview({
    required this.question,
    required this.plan,
    required this.approve,
    this.decline,
  });
}

/// 一个会话的只读真值副本：follow 窗口 + 投影 + assistant 流 + 本地待回显。
///
/// 所有增量都先校验再落地；任何 assistant 折叠违约交由上层重开 follow。
class SessionReplica {
  SessionReplica(this.sessionId);

  static const _optimisticBaseSeq = 1 << 51;

  final String sessionId;
  final TranscriptBuilder transcript = TranscriptBuilder();
  final AssistantStreamFolder assistant = AssistantStreamFolder();
  final PendingSubmissionStore pending = PendingSubmissionStore();

  Map<String, Object?> _projections = const {};
  int _projectionSeq = 0;
  Map<String, Object?> _header = const {};
  int _cursor = -1;
  bool _hasMore = false;
  bool _hasSnapshot = false;
  bool _waitingForSnapshot = true;
  MuxError? _lastError;
  bool _running = false;
  int _lastTurn = 0;
  List<SessionQuestionPrompt> _waterfallQuestions = const [];

  String? get title => _projections['title'] as String?;

  String? get cwd =>
      _header['cwd'] as String? ?? _projections['cwd'] as String?;

  /// 最近一次 turn/start 的轮次号（用于会话页状态栏）。
  int get turns => _lastTurn;

  int get cursor => _cursor;

  bool get hasMore => _hasMore;

  bool get hasSnapshot => _hasSnapshot;

  bool get waitingForSnapshot => _waitingForSnapshot;

  MuxError? get lastError => _lastError;

  bool get running => _running;

  int get baseSeq => transcript.baseSeq;

  int get projectionAsOfSeq => _projectionSeq;

  GoalInfo? get goal => GoalInfo.fromValue(_projections['goal']);

  PlanState? get plan => PlanState.fromValue(_projections['plan']);

  List<TodoItem> get todos => TodoItem.listFromValue(_projections['todos']);

  List<TurnOutlineEntry> get turnOutline =>
      TurnOutlineEntry.listFromValue(_projections['turnOutline']);

  ImageLimits get imageLimits {
    final limits = _projections['imageLimits'];
    return limits is Map
        ? ImageLimits.fromJson(_mapOf(limits))
        : const ImageLimits();
  }

  String? get selectedProvider => _selected?['provider'] as String?;

  String? get selectedModel => _selected?['model'] as String?;

  String? get selectedReasoningEffort =>
      _selected?['reasoningEffort'] as String?;

  /// 上下文占用环数据源；宿主未挂相关投影时为 null。
  ContextPressure? get contextPressure =>
      ContextPressure.fromValue(_projections['contextPressure']);

  /// 权限预设只读投影（`{currentValue}`）；变更走 `/permission <value>` 命令。
  String? get permissionPreset {
    final permissions = _projections['permissions'];
    if (permissions is! Map) return null;
    return permissions['currentValue'] as String?;
  }

  Map? get _selected {
    final selection = _projections['modelSelection'];
    if (selection is! Map) return null;
    final next = selection['next'];
    if (next is Map) return next;
    final last = selection['lastUsed'];
    return last is Map ? last : null;
  }

  bool get hasQuestions => questionPrompts.isNotEmpty;

  /// 投影中的 open/continued 提问；若 waterfall 中有同一 callId，以 waterfall 为准。
  List<SessionQuestionPrompt> get questionPrompts {
    final merged = <String, SessionQuestionPrompt>{};
    final questions = _projections['userQuestions'];
    if (questions is Map) {
      final active = questions['active'];
      if (active is List) {
        for (final raw in active.whereType<Map>()) {
          final call = QuestionCall.fromJson(_mapOf(raw));
          if (call.questions.isEmpty) continue;
          final prompt = SessionQuestionPrompt(
            agentId: sessionId,
            callId: call.callId,
            questions: call.questions,
            state: call.state,
          );
          merged[prompt.key] = prompt;
        }
      }
    }
    for (final prompt in _waterfallQuestions) {
      merged[prompt.key] = prompt;
    }
    return List.unmodifiable(merged.values);
  }

  /// 宿主 inbox 投影队列 + 尚未被收据确认的本地排队消息。
  List<QueuedMessage> get queue {
    final projected = QueuedMessage.fromProjection(_projections['inbox']);
    final projectedRpcIds = {
      for (final item in projected)
        if (item.rpcId != null) item.rpcId!,
    };
    return List.unmodifiable([
      ...projected,
      for (final item in pending.items)
        if (item.queued &&
            item.status != PendingSubmissionStatus.failed &&
            !projectedRpcIds.contains(item.requestId))
          QueuedMessage(
            itemId: 'local-${item.requestId}',
            text: item.text,
            imageCount: item.imageCount,
            target: 'next-turn',
            rpcId: item.requestId,
          ),
    ]);
  }

  /// 会话页转写：持久节点 + 本地待回显 + 正在流式输出的节点。
  List<TranscriptNode> get nodes {
    final result = [...transcript.nodes];
    var index = 0;
    for (final item in pending.items) {
      final failed = item.status == PendingSubmissionStatus.failed;
      if (item.queued && !failed) continue;
      result.add(
        TranscriptNode(
          id: 'local-${item.requestId}',
          kind: TranscriptKind.user,
          seq: _optimisticBaseSeq + index,
          text: item.text,
          imageCount: item.imageCount,
          images: [
            for (final attachment in item.attachments)
              if (attachment is PromptImage)
                TranscriptImage(
                  inlineBase64: attachment.base64Data,
                  mediaType: attachment.mediaType,
                  name: attachment.name,
                ),
          ],
          optimistic: true,
          failed: failed,
        ),
      );
      index += 1;
    }
    final live = assistant.liveNode;
    if (live != null) result.add(live);
    return List.unmodifiable(result);
  }

  bool get hasOptimistic => pending.items.isNotEmpty;

  /// 是否有仍在进行、尚未回显的提交（用于运行态与断线提示）。
  bool get awaitingEcho => pending.items.any(
    (item) => item.status != PendingSubmissionStatus.failed,
  );

  void installSnapshot(FollowSnapshot snapshot) {
    _header = snapshot.header;
    _cursor = snapshot.cursor;
    _hasMore = snapshot.hasMore;
    _hasSnapshot = true;
    _waitingForSnapshot = false;
    _lastError = null;
    final controlValues = _projections;
    final controlSeq = _projectionSeq;
    _projections = Map.unmodifiable(snapshot.projections);
    _projectionSeq = snapshot.projectionsAsOfSeq;
    if (controlSeq > _projectionSeq) {
      _projections = Map.unmodifiable({..._projections, ...controlValues});
      _projectionSeq = controlSeq;
    }
    transcript.replace(snapshot.records);
    assistant.resetWithBaseline(snapshot.assistantStream);
    assistant.seedPublished(snapshot.records);
    _lastTurn = _foldTurns(snapshot.records);
    _running =
        snapshot.assistantStream is Map &&
            (snapshot.assistantStream as Map)['activeAttempt'] != null
        ? true
        : _turnOpen(snapshot.records) || awaitingEcho;
    _reconcilePending();
  }

  /// 返回 false 表示 seq 断裂，需要重开 follow 重新取基线。
  bool appendEvent(SessionWireEvent event) {
    if (event.seq <= _cursor) return true;
    if (_cursor >= 0 && event.seq > _cursor + 1) {
      _waitingForSnapshot = true;
      return false;
    }
    _cursor = event.seq;
    final disposition = assistant.acceptDurable(event);
    if (disposition == AssistantDurableResult.publish) {
      transcript.append(event);
    }
    for (final settlement in assistant.drainReleased()) {
      transcript.append(settlement);
    }
    switch (event.type) {
      case 'turn/start':
        _lastTurn =
            (event.data is Map ? (event.data as Map)['turn'] as num? : null)
                ?.toInt() ??
            _lastTurn;
        _running = true;
      case 'turn/end':
        _running = false;
      case 'assistant/attempt':
        _running = true;
      case 'agent/inbox/spliced':
        final outcome = event.data is Map
            ? (event.data as Map)['outcome']
            : null;
        if (outcome == 'canceled') _running = false;
      default:
        break;
    }
    _reconcilePending();
    return true;
  }

  /// 返回 false 表示 assistant 折叠违约，需要重开 follow。
  bool acceptAssistantFrame(Map<String, Object?> frame) {
    final result = assistant.acceptFrame(frame);
    if (result == AssistantFrameResult.rebaseline) {
      waitingForSnapshotNow();
      return false;
    }
    if (result == AssistantFrameResult.updated) {
      for (final settlement in assistant.drainReleased()) {
        transcript.append(settlement);
      }
      _running = true;
    }
    return true;
  }

  void setRunning(bool running) {
    _running = running;
  }

  void waitingForSnapshotNow() {
    _waitingForSnapshot = true;
  }

  void setLastError(MuxError? error) {
    _lastError = error;
  }

  void setWaterfallQuestions(List<SessionQuestionPrompt> questions) {
    _waterfallQuestions = List.unmodifiable(questions);
  }

  /// 合并 `session/control` 的投影值（按整体 seq 水位，低水位忽略）。
  bool applyControlValues(Map<String, Object?> values, int asOfSeq) {
    if (asOfSeq > 0 && asOfSeq < _projectionSeq) return false;
    if (asOfSeq > _projectionSeq) _projectionSeq = asOfSeq;
    if (values.isEmpty) return false;
    _projections = Map.unmodifiable({..._projections, ...values});
    _reconcilePending();
    return true;
  }

  /// 向上翻页结果拼接到窗口头部；返回是否产生了变化。
  bool prependOlder(SessionHistoryPage page) {
    if (page.events.isEmpty) {
      _hasMore = false;
      return false;
    }
    transcript.prepend(page.events);
    _hasMore = page.hasMore;
    return true;
  }

  void setHasMore(bool hasMore) {
    _hasMore = hasMore;
  }

  void setPendingAccepted(String requestId) {
    pending.markAccepted(requestId);
    _running = true;
  }

  void setPendingFailed(String requestId, String error) {
    pending.markFailed(requestId, error);
    _reconcilePending();
  }

  void addPending(PendingSubmission submission) {
    pending.add(submission);
    _running = true;
  }

  void removePending(String requestId) {
    pending.remove(requestId);
    _reconcilePending();
  }

  void _reconcilePending() {
    final inbox = _projections['inbox'];
    final inboxRpcIds = <String>{
      for (final item in QueuedMessage.fromProjection(inbox))
        if (item.rpcId != null) item.rpcId!,
    };
    pending.reconcile(
      echoedRpcIds: transcript.seenRpcIds,
      inboxRpcIds: inboxRpcIds,
    );
  }

  int _foldTurns(List<SessionWireEvent> events) {
    var turn = _lastTurn;
    for (final event in events) {
      if (event.type == 'turn/start' && event.data is Map) {
        turn = ((event.data as Map)['turn'] as num?)?.toInt() ?? turn;
      }
    }
    return turn;
  }

  bool _turnOpen(List<SessionWireEvent> events) {
    var open = false;
    for (final event in events) {
      switch (event.type) {
        case 'turn/start':
          open = true;
        case 'turn/end':
          open = false;
        default:
          break;
      }
    }
    return open;
  }

  Map<String, dynamic> _mapOf(Map value) => Map<String, dynamic>.from(value);
}
