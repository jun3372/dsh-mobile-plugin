import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mux/mux_hub.dart';
import '../../core/mux/remote_events.dart';
import '../../core/models/dsh_models.dart';
import '../servers/servers_providers.dart';
import '../tasks/tasks_providers.dart';
import 'notification_service.dart';

final notificationApiProvider = Provider<NotificationApi>(
  (ref) => LocalNotificationsApi(),
);

/// 多服务端并行保活：为每个已绑定服务端持有 mux 长活流，并在以下情形
/// 立即弹本地通知——
/// 1. 会话等待输入（ask_user_question / 计划评审 waterfall）；
/// 2. 任务完成（`api-session/status` running 转变）。
///
/// questions 流做镜像同步：新 eventId 弹一次，从 pending 消失（应答 /
/// 宿主 cancel 帧 / 超时）即撤销；重连重放 pending 幂等不重弹。
final backgroundAlertControllerProvider =
    NotifierProvider<BackgroundAlertNotifier, int>(BackgroundAlertNotifier.new);

class _Awaiting {
  final String serverId;
  final RemoteQuestionRequest request;

  const _Awaiting(this.serverId, this.request);
}

class BackgroundAlertNotifier extends Notifier<int> {
  static const _completeGrace = Duration(seconds: 3);

  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Map<String, _Awaiting> _shown = {};

  /// 已观测到 running 的 `serverId|sessionId`；`api-session/status` 只在
  /// 变化时推送，转为 false 且命中此集合才视为任务完成。
  final Set<String> _running = {};

  /// 完成通知的缓冲：若随后到达的是提问/计划评审 waterfall，
  /// 则该会话是等待输入而非完成，撤销待发的完成通知。
  final Map<String, Timer> _completeTimers = {};

  @override
  int build() {
    final servers = ref.watch(serversProvider);
    final api = ref.watch(notificationApiProvider);
    ref.onDispose(_dispose);
    final hubs = <String, MuxHub>{};
    for (final server in servers) {
      final hub = ref.watch(muxHubFamilyProvider(server.id));
      if (hub != null) hubs[server.id] = hub;
    }
    for (final entry in hubs.entries) {
      final serverId = entry.key;
      final hub = entry.value;
      _subscriptions.add(
        hub.events.questions.listen(
          (pending) => _onQuestions(serverId, pending),
        ),
      );
      _subscriptions.add(
        hub.events.sessionSignals.listen(
          (signal) => _onSignal(serverId, signal),
        ),
      );
    }
    unawaited(_bootstrap(api, hubs));
    return 0;
  }

  Future<void> _bootstrap(NotificationApi api, Map<String, MuxHub> hubs) async {
    try {
      await api.init();
      // 冷启动必然在前台，清掉上次进程残留的通知。
      await api.cancelAll();
    } catch (_) {}
    await _ensurePermissionAsked();
    // init 期间可能已有事件到达；此时补一次同步。
    for (final entry in hubs.entries) {
      if (ref.read(muxHubFamilyProvider(entry.key)) == null) continue;
      _onQuestions(entry.key, entry.value.events.pendingQuestions);
    }
  }

  Future<void> _ensurePermissionAsked() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool('notifications.asked') ?? false) return;
    await prefs.setBool('notifications.asked', true);
    await ref.read(notificationApiProvider).requestPermission();
  }

  void _onQuestions(String serverId, List<RemoteQuestionRequest> pending) {
    final pendingById = {
      for (final request in pending) request.eventId: request,
    };
    final prefix = '$serverId|';
    final diff = diffNotifications(
      pending: pending,
      shown: {
        for (final key in _shown.keys)
          if (key.startsWith(prefix)) key.substring(prefix.length),
      },
      resolveTitle: (agentId) => _resolveTitle(serverId, agentId),
    );
    final api = ref.read(notificationApiProvider);
    for (final plan in diff.show) {
      final request = pendingById[plan.eventId];
      if (request != null) {
        _shown['$prefix${plan.eventId}'] = _Awaiting(serverId, request);
        // 会话转入等待输入，取消其待发的完成通知。
        _completeTimers['$prefix${request.agentId}']?.cancel();
        _completeTimers.remove('$prefix${request.agentId}');
      }
      unawaited(
        api
            .show(id: plan.id, title: plan.title, body: plan.body)
            .catchError((_) {}),
      );
    }
    for (final eventId in diff.cancel) {
      if (_shown.remove('$prefix$eventId') != null) {
        unawaited(api.cancel(eventId.hashCode).catchError((_) {}));
      }
    }
    state = _shown.length;
  }

  void _onSignal(String serverId, RemoteSessionSignal signal) {
    final prefix = '$serverId|';
    switch (signal) {
      case RemoteSessionStatus(:final sessionId, :final running):
        if (running) {
          _running.add('$prefix$sessionId');
          _withdrawForSession(serverId, sessionId);
        } else if (_running.remove('$prefix$sessionId')) {
          _scheduleCompleteNotify(serverId, sessionId);
        }
      case RemoteSessionActivity(:final sessionId):
        // app 启动前已在运行的任务收不到 running:true（status 只在变化时
        // 推送）；activity 即代理在工作，据此补记运行中，任务完成时才通知。
        _running.add('$serverId|$sessionId');
      case RemoteSessionRemoved(:final sessionId):
        _running.remove('$prefix$sessionId');
        _withdrawForSession(serverId, sessionId);
      case RemoteSessionError(:final sessionId):
        _running.remove('$prefix$sessionId');
      case RemoteSessionAdded():
        break;
    }
  }

  void _scheduleCompleteNotify(String serverId, String sessionId) {
    final key = '$serverId|$sessionId';
    _completeTimers[key]?.cancel();
    _completeTimers[key] = Timer(_completeGrace, () {
      _completeTimers.remove(key);
      _notifyComplete(serverId, sessionId);
    });
  }

  void _notifyComplete(String serverId, String sessionId) {
    // 已在等待输入（提问/计划评审）的会话不算完成。
    if (_shown.values.any(
      (awaiting) =>
          awaiting.serverId == serverId &&
          awaiting.request.agentId == sessionId,
    )) {
      return;
    }
    final title = _resolveTitle(serverId, sessionId);
    final hasTitle = title != null && title.isNotEmpty;
    final api = ref.read(notificationApiProvider);
    unawaited(
      api
          .show(
            id: 'done:$serverId|$sessionId'.hashCode,
            title: hasTitle ? '「$title」任务已完成' : '有一个任务已完成',
            body: '任务执行完毕，点击查看结果',
          )
          .catchError((_) {}),
    );
  }

  /// 兜底：宿主桌面端直接应答可能不广播 cancel 帧；agent 恢复运行或
  /// 会话被删除即视为不再等待输入，撤销该会话的等待通知。
  void _withdrawForSession(String serverId, String sessionId) {
    final prefix = '$serverId|';
    final stale = [
      for (final entry in _shown.entries)
        if (entry.value.serverId == serverId &&
            entry.value.request.agentId == sessionId)
          entry.key,
    ];
    if (stale.isEmpty) return;
    final api = ref.read(notificationApiProvider);
    for (final key in stale) {
      final eventId = key.substring(prefix.length);
      _shown.remove(key);
      unawaited(api.cancel(eventId.hashCode).catchError((_) {}));
    }
    state = _shown.length;
  }

  String? _resolveTitle(String serverId, String agentId) {
    if (ref.read(currentServerIdProvider) == serverId) {
      for (final session in ref.read(tasksProvider).value ?? const []) {
        if (session.sessionId != agentId) continue;
        final title = session.title;
        if (title != null && title.isNotEmpty) return title;
      }
    }
    // 非当前服务端没有会话列表兜底，改读 control 投影里的标题。
    final values = ref
        .read(muxHubFamilyProvider(serverId))
        ?.control
        .store
        .valuesOf(agentId);
    final title = values?['title'];
    return title is String && title.isNotEmpty ? title : null;
  }

  void _dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final timer in _completeTimers.values) {
      timer.cancel();
    }
    _completeTimers.clear();
  }
}

/// 一条待弹通知的完整计划（纯数据，便于单测断言）。
class NotificationPlan {
  final String eventId;
  final int id;
  final String title;
  final String body;

  const NotificationPlan({
    required this.eventId,
    required this.id,
    required this.title,
    required this.body,
  });
}

/// 由一条 questions waterfall 生成通知文案。
NotificationPlan planFor(RemoteQuestionRequest request, String? sessionTitle) {
  final isPlanReview =
      request.questions.length == 1 &&
      request.questions.first.intentKind == 'plan-review';
  final hasTitle = sessionTitle != null && sessionTitle.isNotEmpty;
  final title = isPlanReview
      ? (hasTitle ? '「$sessionTitle」计划待你确认' : '有一个计划待确认')
      : (hasTitle ? '「$sessionTitle」等待你的输入' : '有一个会话等待你的输入');
  return NotificationPlan(
    eventId: request.eventId,
    id: request.eventId.hashCode,
    title: title,
    body: isPlanReview
        ? _planBody(request.questions.first)
        : _questionBody(request.questions),
  );
}

/// diff 当前 pending 与已弹集合：返回要新弹的计划与要撤销的 eventId。
({List<NotificationPlan> show, List<String> cancel}) diffNotifications({
  required List<RemoteQuestionRequest> pending,
  required Set<String> shown,
  String? Function(String agentId)? resolveTitle,
}) {
  final pendingById = {for (final request in pending) request.eventId: request};
  return (
    show: [
      for (final request in pendingById.values)
        if (!shown.contains(request.eventId))
          planFor(request, resolveTitle?.call(request.agentId)),
    ],
    cancel: [
      for (final eventId in shown)
        if (!pendingById.containsKey(eventId)) eventId,
    ],
  );
}

String _questionBody(List<UserQuestion> questions) {
  final first = _clip(questions.first.question.trim(), 120);
  return questions.length > 1 ? '${questions.length} 个问题待回答：$first' : first;
}

String _planBody(UserQuestion question) {
  for (final line in (question.detail ?? '').split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      return _clip(trimmed, 80);
    }
  }
  return '请审阅执行计划';
}

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';
