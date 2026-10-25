import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/models/approval_request.dart';
import '../../core/models/composer_models.dart';
import '../../core/models/dsh_models.dart';
import '../../core/models/goal_info.dart';
import '../../core/models/pending_submission.dart';
import '../../core/models/plan_state.dart';
import '../../core/models/queued_message.dart';
import '../../core/models/todo_item.dart';
import '../../core/models/transcript_node.dart';
import '../../core/models/turn_outline.dart';
import '../../core/mux/dsh_mux_client.dart';
import '../../core/mux/mux_hub.dart';
import '../../core/mux/remote_events.dart';
import '../../core/services/api_client.dart';
import '../../core/services/dsh_api.dart';
import '../../core/session/session_follow_client.dart';
import '../../core/session/session_page_loader.dart';
import '../../core/session/session_replica.dart';
import '../servers/servers_providers.dart';
import '../tasks/tasks_providers.dart';

/// family 参数：会话 id + 进入页时从列表带来的快照信息。
typedef SessionKey = ({
  String sessionId,
  String? serverId,
  bool initialRunning,
  bool initialBlank,
  String? initialTitle,
});

/// 会话页视图状态：转写节点 + 队列 + 待处理审批/提问 + 投影派生信息。
class SessionViewState {
  final List<TranscriptNode> nodes;
  final List<QueuedMessage> queue;
  final List<ApprovalRequest> approvals;
  final List<SessionQuestionPrompt> questions;
  final bool running;
  final String? title;
  final String? cwd;
  final GoalInfo? goal;
  final PlanState? plan;
  final List<TodoItem> todos;
  final List<TurnOutlineEntry> turnOutline;
  final ImageLimits imageLimits;
  final ContextPressure? contextPressure;
  final String? permissionValue;
  final String? selectedProvider;
  final String? selectedModel;
  final String? selectedReasoningEffort;
  final bool hasMore;
  final bool loadingOlder;
  final bool hasSnapshot;
  final bool waitingSnapshot;
  final MuxConnectionState connection;
  final String? connectionError;
  final int cursor;

  /// 限时提问剩余等待毫秒（key = prompt.key）。倒计时由 notifier 驱动，
  /// 弹窗关闭不影响超时链路。
  final Map<String, int> questionRemainingMs;

  /// 最近一次 turn/start 的轮次号。
  final int turns;

  const SessionViewState({
    this.nodes = const [],
    this.queue = const [],
    this.approvals = const [],
    this.questions = const [],
    this.running = false,
    this.title,
    this.cwd,
    this.goal,
    this.plan,
    this.todos = const [],
    this.turnOutline = const [],
    this.imageLimits = const ImageLimits(),
    this.contextPressure,
    this.permissionValue,
    this.selectedProvider,
    this.selectedModel,
    this.selectedReasoningEffort,
    this.hasMore = false,
    this.loadingOlder = false,
    this.hasSnapshot = false,
    this.waitingSnapshot = false,
    this.connection = MuxConnectionState.idle,
    this.connectionError,
    this.cursor = -1,
    this.turns = 0,
    this.questionRemainingMs = const {},
  });

  bool get hasQuestions => questions.any((q) => q.questions.isNotEmpty);

  /// 待确认的计划评审（未开始的计划）：首个收窄命中的 plan-review 问题。
  /// 宿主 Agent 停在 exit_plan_mode 等待应答期间计划尚未开始，
  /// 底部输入区以此卡替代输入框（对齐 Web composer 位让位给计划评审面板）。
  ({SessionQuestionPrompt prompt, PlanReview review})? get pendingPlanReview {
    for (final prompt in questions) {
      final review = prompt.planReview;
      if (review != null) return (prompt: prompt, review: review);
    }
    return null;
  }

  bool get hasPendingInteractions => approvals.isNotEmpty || hasQuestions;

  bool get isOffline =>
      connection == MuxConnectionState.waiting ||
      connection == MuxConnectionState.closed;

  SessionViewState copyWith({
    bool? running,
    String? title,
    bool? hasMore,
    bool? loadingOlder,
    bool? waitingSnapshot,
  }) {
    return SessionViewState(
      nodes: nodes,
      queue: queue,
      approvals: approvals,
      questions: questions,
      running: running ?? this.running,
      title: title ?? this.title,
      cwd: cwd,
      goal: goal,
      plan: plan,
      todos: todos,
      turnOutline: turnOutline,
      imageLimits: imageLimits,
      contextPressure: contextPressure,
      permissionValue: permissionValue,
      selectedProvider: selectedProvider,
      selectedModel: selectedModel,
      selectedReasoningEffort: selectedReasoningEffort,
      hasMore: hasMore ?? this.hasMore,
      loadingOlder: loadingOlder ?? this.loadingOlder,
      hasSnapshot: hasSnapshot,
      waitingSnapshot: waitingSnapshot ?? this.waitingSnapshot,
      connection: connection,
      connectionError: connectionError,
      cursor: cursor,
      turns: turns,
      questionRemainingMs: questionRemainingMs,
    );
  }
}

final sessionProvider =
    AsyncNotifierProvider.family<SessionNotifier, SessionViewState, SessionKey>(
      SessionNotifier.new,
      isAutoDispose: true,
    );

class SessionNotifier extends AsyncNotifier<SessionViewState> {
  SessionNotifier(this.arg);

  final SessionKey arg;

  SessionReplica? _replica;
  SessionFollowClient? _follow;
  SessionPageLoader? _loader;
  MuxHub? _hub;
  DshApi? _api;

  /// 每次 build 重建（Riverpod 复用同一 Notifier 实例，invalidate 后再次进入 build）。
  Completer<void> _ready = Completer<void>();
  final Set<String> _answeredQuestionKeys = {};
  List<ApprovalRequest> _approvals = const [];
  List<RemoteQuestionRequest> _waterfallQuestions = const [];
  MuxConnectionState _connection = MuxConnectionState.idle;
  String? _runtimeError;
  bool _loadingOlder = false;
  bool _built = false;
  bool _disposed = false;
  Timer? _publishTimer;
  Timer? _readyTimeout;

  /// 限时提问倒计时：attachWait 订阅 + 本地秒级 tick，随弹窗开合无关地存活。
  final _waitSubs = <String, StreamSubscription<Object?>>{};
  final _waitTickers = <String, Timer>{};
  final _questionRemaining = <String, int>{};

  StreamSubscription<MuxConnectionState>? _connectionSub;
  StreamSubscription<String>? _controlSub;
  StreamSubscription<List<ApprovalRequest>>? _approvalSub;
  StreamSubscription<List<RemoteQuestionRequest>>? _questionSub;
  StreamSubscription<RemoteSessionSignal>? _signalSub;

  @override
  Future<SessionViewState> build() async {
    // Riverpod 重建时复用同一 Notifier 实例：上一轮 build 的 onDispose 已执行，
    // 但实例字段仍残留 `_disposed=true` 与已 complete 的 `_ready`，不复位会导致
    // invalidate（如「重试」）后流式帧与发布被永久丢弃。
    _disposed = false;
    _built = false;
    _ready = Completer<void>();
    _answeredQuestionKeys.clear();
    _approvals = const [];
    _waterfallQuestions = const [];
    _connection = MuxConnectionState.idle;
    _runtimeError = null;
    _loadingOlder = false;
    ref.onDispose(_dispose);
    final hub = ref.watch(muxHubProvider);
    final api = ref.watch(dshApiProvider);
    _hub = hub;
    _api = api;
    final serverId = ref.read(currentServerIdProvider);
    if (hub == null ||
        api == null ||
        (arg.serverId != null && arg.serverId != serverId)) {
      _built = true;
      return SessionViewState(
        title: arg.initialTitle,
        running: arg.initialRunning,
      );
    }

    final replica = SessionReplica(arg.sessionId);
    _replica = replica;
    _connection = hub.connection;
    _follow = SessionFollowClient(
      client: hub.client,
      sessionId: arg.sessionId,
      onFrame: _onFrame,
    );
    _loader = SessionPageLoader(api, arg.sessionId);
    _bindHub(hub);
    _follow!.start();

    _readyTimeout = Timer(const Duration(seconds: 12), _completeReady);
    await _ready.future;
    _readyTimeout?.cancel();
    _readyTimeout = null;
    _built = true;
    return _view();
  }

  void _bindHub(MuxHub hub) {
    _controlSub = hub.control.changes.listen((sessionId) {
      if (sessionId.isNotEmpty && sessionId != arg.sessionId) return;
      _syncControl(hub);
    });
    _syncControl(hub);
    _approvalSub = hub.events.approvals.listen((items) {
      _approvals = [
        for (final item in items)
          if (item.agentId == arg.sessionId) item,
      ];
      _schedulePublish();
    });
    _questionSub = hub.events.questions.listen((items) {
      _waterfallQuestions = [
        for (final item in items)
          if (item.agentId == arg.sessionId) item,
      ];
      _syncWaterfallQuestions();
      _schedulePublish();
    });
    _signalSub = hub.events.sessionSignals.listen(_onSessionSignal);
    _connectionSub = hub.connectionStates.listen((connection) {
      _connection = connection;
      if (connection == MuxConnectionState.waiting) {
        _replica?.waitingForSnapshotNow();
      }
      _schedulePublish();
    });
    _approvals = [
      for (final item in hub.events.pendingApprovals)
        if (item.agentId == arg.sessionId) item,
    ];
    _waterfallQuestions = [
      for (final item in hub.events.pendingQuestions)
        if (item.agentId == arg.sessionId) item,
    ];
    _syncWaterfallQuestions();
  }

  void _syncControl(MuxHub hub) {
    final replica = _replica;
    if (replica == null) return;
    final state = hub.control.store.stateOf(arg.sessionId);
    if (state == null) return;
    if (replica.applyControlValues(state.values, state.asOfSeq)) {
      _schedulePublish();
    }
  }

  void _onSessionSignal(RemoteSessionSignal signal) {
    final replica = _replica;
    if (replica == null) return;
    switch (signal) {
      case RemoteSessionStatus(:final sessionId, :final running):
        if (sessionId != arg.sessionId) return;
        replica.setRunning(running);
        _schedulePublish();
      case RemoteSessionError(:final sessionId, :final message):
        if (sessionId != arg.sessionId) return;
        _runtimeError = message.isEmpty ? '会话运行出错' : message;
        _schedulePublish();
      case RemoteSessionRemoved(:final sessionId):
        if (sessionId != arg.sessionId) return;
        _runtimeError = '会话已被删除';
        _schedulePublish();
      case RemoteSessionAdded():
      case RemoteSessionActivity():
        return;
    }
  }

  void _onFrame(FollowFrame frame) {
    final replica = _replica;
    if (replica == null || _disposed) return;
    switch (frame) {
      case FollowSnapshot():
        replica.installSnapshot(frame);
        _runtimeError = null;
        _syncWaterfallQuestions();
        _completeReady();
        _schedulePublish();
      case FollowEvent():
        final ok = replica.appendEvent(frame.event);
        if (!ok) {
          _follow?.restart();
        }
        _schedulePublish();
      case FollowAssistantFrame():
        final ok = replica.acceptAssistantFrame(frame.frame);
        if (!ok) {
          _follow?.restart();
        }
        _schedulePublish();
      case FollowWaiting():
        replica.waitingForSnapshotNow();
        _schedulePublish();
      case FollowOpened(:final restarted):
        if (restarted) {
          replica.waitingForSnapshotNow();
          _schedulePublish();
        }
      case FollowFailure(:final error):
        replica.setLastError(error);
        _completeReady();
        _schedulePublish();
    }
  }

  void _syncWaterfallQuestions() {
    final replica = _replica;
    if (replica == null) return;
    replica.setWaterfallQuestions([
      for (final item in _waterfallQuestions)
        SessionQuestionPrompt(
          eventId: item.eventId,
          callId: item.callId,
          agentId: item.agentId,
          questions: item.questions,
          state: 'open',
          timedWait: item.timedWait,
        ),
    ]);
    _syncWaits();
  }

  /// 按当前存活提问集合对齐倒计时订阅：新增挂上、消失回收。
  void _syncWaits() {
    final replica = _replica;
    if (replica == null) return;
    final live = <String>{};
    for (final prompt in replica.questionPrompts) {
      if (!prompt.viaWaterfall || !prompt.timedWait) continue;
      final key = prompt.key;
      if (key.isEmpty) continue;
      live.add(key);
      if (_waitSubs.containsKey(key)) continue;
      final stream = attachWait(prompt);
      if (stream == null) continue;
      _waitSubs[key] = stream.listen(
        (value) {
          final ms = _remainingMsOf(value);
          if (ms == null || _disposed) return;
          _questionRemaining[key] = ms;
          if (ms > 0) _startWaitTicker(prompt, key, ms);
          _schedulePublish();
        },
        onDone: () {
          _waitSubs.remove(key)?.cancel();
          _waitTickers.remove(key)?.cancel();
        },
        onError: (Object _) {
          // attachWait 流失败（如服务端报错）视同结束，交由 pending 重放恢复。
          _waitSubs.remove(key)?.cancel();
          _waitTickers.remove(key)?.cancel();
        },
      );
    }
    for (final key in _waitSubs.keys.toList()) {
      if (live.contains(key)) continue;
      _waitSubs.remove(key)?.cancel();
      _waitTickers.remove(key)?.cancel();
      _questionRemaining.remove(key);
    }
    for (final key in _questionRemaining.keys.toList()) {
      if (!live.contains(key)) _questionRemaining.remove(key);
    }
  }

  /// attachWait 帧：毫秒数，或带 remainingMs / ms / remaining 字段的对象。
  int? _remainingMsOf(Object? value) {
    if (value is num) return value.toInt();
    if (value is Map) {
      for (final field in const ['remainingMs', 'ms', 'remaining']) {
        final item = value[field];
        if (item is num) return item.toInt();
      }
    }
    return null;
  }

  /// 本地秒级递减；归零走 questionTimedOut（宿主转 pending）。
  void _startWaitTicker(SessionQuestionPrompt prompt, String key, int ms) {
    _waitTickers.remove(key)?.cancel();
    _waitTickers[key] = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = (_questionRemaining[key] ?? 0) - 1000;
      if (next <= 0) {
        timer.cancel();
        _waitTickers.remove(key);
        _questionRemaining.remove(key);
        if (_disposed) return;
        questionTimedOut(prompt);
      } else {
        _questionRemaining[key] = next;
        _schedulePublish();
      }
    });
  }

  SessionViewState _view() {
    final replica = _replica;
    if (replica == null) {
      return SessionViewState(
        title: arg.initialTitle,
        running: arg.initialRunning,
        connection: _connection,
      );
    }
    return SessionViewState(
      nodes: replica.nodes,
      queue: replica.queue,
      approvals: _approvals,
      questions: [
        for (final prompt in replica.questionPrompts)
          if (!_answeredQuestionKeys.contains(prompt.key)) prompt,
      ],
      running: replica.running,
      title: replica.title ?? arg.initialTitle,
      cwd: replica.cwd,
      goal: replica.goal,
      plan: replica.plan,
      todos: replica.todos,
      turnOutline: replica.turnOutline,
      imageLimits: replica.imageLimits,
      contextPressure: replica.contextPressure,
      permissionValue: replica.permissionPreset,
      selectedProvider: replica.selectedProvider,
      selectedModel: replica.selectedModel,
      selectedReasoningEffort: replica.selectedReasoningEffort,
      hasMore: replica.hasMore,
      loadingOlder: _loadingOlder,
      hasSnapshot: replica.hasSnapshot,
      waitingSnapshot: replica.waitingForSnapshot,
      connection: _connection,
      connectionError:
          _runtimeError ?? replica.lastError?.toException().userMessage,
      cursor: replica.cursor,
      turns: replica.turns,
      questionRemainingMs: Map.unmodifiable(_questionRemaining),
    );
  }

  void _completeReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  void _schedulePublish() {
    if (!_built || _disposed) return;
    if (_publishTimer != null) return;
    _publishTimer = Timer(const Duration(milliseconds: 40), () {
      _publishTimer = null;
      _publish();
    });
  }

  void _publish() {
    if (!_built || _disposed || !ref.mounted) return;
    state = AsyncData(_view());
  }

  /// 发送用户消息（requestId 对账；运行中默认进入宿主队列）。
  Future<void> send(
    String text, {
    List<PromptAttachment> attachments = const [],
    String mode = 'queue',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    final api = _api;
    final replica = _replica;
    if (api == null || replica == null) return;
    final current = state.value;
    final running = current?.running ?? replica.running;
    final requestId = newRpcId();
    replica.addPending(
      PendingSubmission(
        requestId: requestId,
        text: trimmed,
        attachments: attachments,
        queued: running && mode == 'queue',
        mode: mode,
      ),
    );
    _publish();
    try {
      await api.prompt(
        sessionId: arg.sessionId,
        requestId: requestId,
        text: trimmed,
        attachments: attachments,
        mode: mode,
      );
      replica.setPendingAccepted(requestId);
      _publish();
      ref.invalidate(tasksProvider);
    } on AppException catch (e) {
      replica.setPendingFailed(requestId, e.userMessage);
      _publish();
      rethrow;
    }
  }

  /// 重试失败消息：换新的 requestId（宿主无去重）。
  Future<void> resend(String nodeId) async {
    final replica = _replica;
    if (replica == null || !nodeId.startsWith('local-')) return;
    final requestId = nodeId.substring('local-'.length);
    final pending = replica.pending.byId(requestId);
    if (pending == null || pending.status != PendingSubmissionStatus.failed) {
      return;
    }
    replica.removePending(requestId);
    _publish();
    await send(
      pending.text,
      attachments: pending.attachments,
      mode: pending.mode,
    );
  }

  /// 执行一条宿主命令（`/permission x`、`/plan`、`/compact` 等）。
  /// Web 侧同样用该入口落权限预设与计划模式，而不是另调投影写接口。
  Future<CommandExecution> executeCommand(
    String line, [
    List<PromptAttachment> attachments = const [],
  ]) async {
    final api = _api;
    if (api == null) return const CommandExecution.none();
    final result = await api.executeCommand(
      sessionId: arg.sessionId,
      line: line,
      attachments: attachments,
    );
    await _refreshProjections();
    return result;
  }

  /// 停止当前回合。
  Future<void> cancelTurn() async {
    final api = _api;
    final replica = _replica;
    if (api == null || replica == null) return;
    try {
      await api.cancel(arg.sessionId);
    } finally {
      replica.setRunning(false);
      _publish();
      ref.invalidate(tasksProvider);
    }
  }

  /// 撤回一条排队消息。
  Future<void> removeQueueItem(String itemId) =>
      _updateQueueItem(itemId, {'kind': 'remove'});

  /// 打断当前回合并立即发送该队列消息（⚡ 立即发送）。
  ///
  /// 宿主的 `steer` 只是把消息注入进行中的回合、不打断当前工作；这里先取消
  /// 当前回合（宿主 cancel 保留 inbox），再把消息移出队列并作为新 prompt
  /// 立即发出。附件从本地 pending 记录按 rpcId 恢复（队列投影只有摘要）。
  Future<void> steerImmediately(QueuedMessage item) async {
    if (item.isLocal) return;
    await cancelTurn();
    final replica = _replica;
    final pending = (replica == null || item.rpcId == null)
        ? null
        : replica.pending.byId(item.rpcId!);
    final attachments = pending?.attachments ?? const [];
    await _updateQueueItem(item.itemId, {'kind': 'remove'});
    if (item.text.trim().isNotEmpty || attachments.isNotEmpty) {
      await send(item.text, attachments: attachments);
    }
  }

  Future<void> _updateQueueItem(
    String itemId,
    Map<String, Object?> action,
  ) async {
    final api = _api;
    final replica = _replica;
    if (api == null || replica == null) return;
    if (itemId.startsWith('local-')) {
      // 尚未获宿主回显的本地排队消息：直接撤回本地占位。
      if (action['kind'] == 'remove') {
        replica.removePending(itemId.substring('local-'.length));
        _publish();
      }
      return;
    }
    await api.updateQueueItem(
      sessionId: arg.sessionId,
      itemId: itemId,
      action: action,
    );
    // 排队改动由 control 流推送；这里主动刷新一次兜底。
    await _refreshProjections();
  }

  /// 向上加载更早的一页历史。
  Future<void> loadOlder() async {
    final replica = _replica;
    final loader = _loader;
    final current = state.value;
    if (replica == null ||
        loader == null ||
        current == null ||
        _loadingOlder ||
        !current.hasMore ||
        !replica.hasSnapshot) {
      return;
    }
    if (replica.cursor < 0 || replica.baseSeq < 0) {
      replica.setHasMore(false);
      _publish();
      return;
    }
    _loadingOlder = true;
    _publish();
    try {
      final page = await loader.loadOlder(
        throughSeq: replica.cursor,
        beforeSeq: replica.baseSeq,
        maxMessages: 80,
        turnWindow: const {'minMessages': 50, 'minTurns': 2},
      );
      replica.prependOlder(page);
    } finally {
      _loadingOlder = false;
      _publish();
    }
  }

  /// 重命名会话并同步标题。
  Future<void> rename(String title) async {
    final api = _api;
    final replica = _replica;
    if (api == null || replica == null) return;
    final newTitle = await api.rename(arg.sessionId, title);
    replica.applyControlValues({'title': newTitle}, 0);
    _publish();
    ref.invalidate(tasksProvider);
  }

  /// 新建目标（Web 侧「设定目标」入口）。
  Future<void> createGoal(String objective, {int? maxGoalRounds}) async {
    final api = _api;
    if (api == null) return;
    await api.createGoal(
      sessionId: arg.sessionId,
      objective: objective,
      maxGoalRounds: maxGoalRounds,
    );
    await _refreshProjections();
  }

  /// 改目标正文/轮数上限，走 CAS 引用。
  Future<void> editGoal(
    GoalRef ref, {
    String? objective,
    int? maxGoalRounds,
  }) async {
    final api = _api;
    if (api == null) return;
    await api.editGoal(
      sessionId: arg.sessionId,
      ref: ref,
      objective: objective,
      maxGoalRounds: maxGoalRounds,
    );
    await _refreshProjections();
  }

  /// 目标状态迁移：pause / resume / complete / clear。
  Future<void> goalTransition(String action, GoalRef ref) async {
    final api = _api;
    if (api == null) return;
    switch (action) {
      case 'pause':
        await api.pauseGoal(sessionId: arg.sessionId, ref: ref);
      case 'resume':
        await api.resumeGoal(sessionId: arg.sessionId, ref: ref);
      case 'complete':
        await api.completeGoal(sessionId: arg.sessionId, ref: ref);
      case 'clear':
        await api.clearGoal(sessionId: arg.sessionId, ref: ref);
      default:
        return;
    }
    await _refreshProjections();
  }

  /// 分叉当前会话，返回新会话 id。
  Future<String> fork() async {
    final api = _api;
    if (api == null) return '';
    return api.fork(arg.sessionId);
  }

  /// 选择会话级模型。
  Future<void> selectModel({
    required String provider,
    required String model,
    String? reasoningEffort,
  }) async {
    final api = _api;
    if (api == null) return;
    await api.selectModel(
      sessionId: arg.sessionId,
      provider: provider,
      model: model,
      reasoningEffort: reasoningEffort,
    );
    await _refreshProjections();
  }

  /// 回填一次工具审批 waterfall。
  Future<void> answerApproval(String eventId, {required bool allowed}) async {
    final hub = _hub;
    if (hub == null) return;
    await hub.events.answerApproval(eventId, allowed: allowed);
    _approvals = [
      for (final item in _approvals)
        if (item.eventId != eventId) item,
    ];
    _publish();
  }

  /// 应答提问：窗口内走 waterfall，continued 走一元回填。
  Future<void> answerQuestion(
    SessionQuestionPrompt prompt,
    List<QuestionAnswer> answers,
  ) async {
    final hub = _hub;
    final api = _api;
    final replica = _replica;
    if (hub == null || api == null || replica == null) return;
    _answeredQuestionKeys.add(prompt.key);
    _publish();
    try {
      if (prompt.eventId != null) {
        await hub.events.answerQuestions(prompt.eventId!, answers);
        _waterfallQuestions = [
          for (final item in _waterfallQuestions)
            if (item.eventId != prompt.eventId) item,
        ];
        _syncWaterfallQuestions();
      } else {
        await api.answerQuestions(
          sessionId: arg.sessionId,
          callId: prompt.callId ?? '',
          answers: answers,
        );
        await _refreshProjections();
      }
      _publish();
    } on AppException {
      _answeredQuestionKeys.remove(prompt.key);
      _publish();
      rethrow;
    }
  }

  /// 限时提问的剩余等待流（帧为毫秒数）；非限时提问返回 null。
  Stream<Object?>? attachWait(SessionQuestionPrompt prompt) {
    final hub = _hub;
    final callId = prompt.callId;
    if (hub == null || !prompt.viaWaterfall || !prompt.timedWait) return null;
    if (callId == null || callId.isEmpty) return null;
    return hub.events.attachWait(agentId: prompt.agentId, callId: callId);
  }

  /// 限时提问本地倒计时归零：以 ASK_TIMED_OUT 拒绝 waterfall，宿主转为 pending。
  Future<void> questionTimedOut(SessionQuestionPrompt prompt) async {
    final hub = _hub;
    final eventId = prompt.eventId;
    if (hub == null || eventId == null) return;
    try {
      await hub.events.rejectQuestion(eventId, 'ASK_TIMED_OUT');
    } finally {
      _waterfallQuestions = [
        for (final item in _waterfallQuestions)
          if (item.eventId != eventId) item,
      ];
      _syncWaterfallQuestions();
      _publish();
    }
  }

  /// 用户主动跳过：以 ASK_SKIPPED 拒绝 waterfall，通道与超时同构；
  /// 若宿主不认未知错误码，退化为 ASK_TIMED_OUT（行为等价）。
  Future<void> skipQuestion(SessionQuestionPrompt prompt) async {
    final hub = _hub;
    final eventId = prompt.eventId;
    if (hub == null || eventId == null) return;
    try {
      await hub.events.rejectQuestion(eventId, 'ASK_SKIPPED');
    } finally {
      _waterfallQuestions = [
        for (final item in _waterfallQuestions)
          if (item.eventId != eventId) item,
      ];
      _syncWaterfallQuestions();
      _publish();
    }
  }

  /// 立即重连 mux（用户点击断线横幅时）。
  void reconnect() {
    _hub?.client.reconnectNow();
  }

  Future<void> _refreshProjections() async {
    final api = _api;
    final replica = _replica;
    if (api == null || replica == null) return;
    try {
      final projections = await api.projections(arg.sessionId);
      if (projections.migrationRequired && projections.values.isEmpty) return;
      replica.applyControlValues(projections.values, projections.asOfSeq);
      _publish();
    } on AppException {
      // 一元刷新只是兜底；control / follow 仍是权威来源。
    }
  }

  void _dispose() {
    _disposed = true;
    _publishTimer?.cancel();
    _publishTimer = null;
    _readyTimeout?.cancel();
    _readyTimeout = null;
    for (final sub in _waitSubs.values) {
      sub.cancel();
    }
    _waitSubs.clear();
    for (final timer in _waitTickers.values) {
      timer.cancel();
    }
    _waitTickers.clear();
    _questionRemaining.clear();
    _connectionSub?.cancel();
    _controlSub?.cancel();
    _approvalSub?.cancel();
    _questionSub?.cancel();
    _signalSub?.cancel();
    _connectionSub = null;
    _controlSub = null;
    _approvalSub = null;
    _questionSub = null;
    _signalSub = null;
    _follow?.dispose();
    _follow = null;
    _replica = null;
    _loader = null;
  }
}
