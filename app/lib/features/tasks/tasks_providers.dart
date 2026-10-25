import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/models/dsh_session.dart';
import '../../core/mux/mux_hub.dart';
import '../../core/mux/remote_events.dart';
import '../../core/mux/workspace_hub.dart';
import '../../core/services/dsh_api.dart';
import '../servers/servers_providers.dart';

/// 列表分组方式（对应设计图 ⋯ 菜单「分组方式」）。
enum TaskGroupMode { date, workspace, status }

class TaskPrefs {
  final TaskGroupMode groupMode;
  final bool onlyRunning;

  const TaskPrefs({
    this.groupMode = TaskGroupMode.workspace,
    this.onlyRunning = false,
  });

  TaskPrefs copyWith({TaskGroupMode? groupMode, bool? onlyRunning}) =>
      TaskPrefs(
        groupMode: groupMode ?? this.groupMode,
        onlyRunning: onlyRunning ?? this.onlyRunning,
      );
}

final taskPrefsProvider = NotifierProvider<TaskPrefsNotifier, TaskPrefs>(
  TaskPrefsNotifier.new,
);

class TaskPrefsNotifier extends Notifier<TaskPrefs> {
  @override
  TaskPrefs build() => const TaskPrefs();

  void setGroupMode(TaskGroupMode mode) =>
      state = state.copyWith(groupMode: mode);

  void toggleOnlyRunning() =>
      state = state.copyWith(onlyRunning: !state.onlyRunning);
}

/// 一个分组（文件夹行 / 日期行 / 状态行）。
class TaskGroup {
  final String title;
  final List<SessionSummary> sessions;

  const TaskGroup(this.title, this.sessions);
}

/// 会话列表：首次 `session/list` 兜底，随后由 control 投影 + `$events` 信号增量更新。
final tasksProvider =
    AsyncNotifierProvider<TasksNotifier, List<SessionSummary>>(
      TasksNotifier.new,
    );

class TasksNotifier extends AsyncNotifier<List<SessionSummary>> {
  DshApi? _api;
  MuxHub? _hub;
  StreamSubscription<String>? _controlSub;
  StreamSubscription<RemoteSessionSignal>? _signalSub;
  StreamSubscription<void>? _reconnectedSub;
  Timer? _reloadTimer;
  bool _reloading = false;
  bool _reloadQueued = false;
  bool _disposed = false;

  @override
  Future<List<SessionSummary>> build() async {
    _disposed = false;
    _cancelSubscriptions();
    ref.onDispose(_dispose);
    final api = ref.watch(dshApiProvider);
    final hub = ref.watch(muxHubProvider);
    _api = api;
    _hub = hub;
    if (api == null) return const [];
    final sessions = withoutSubagentSessions(await api.listSessions());
    if (hub == null) return sessions;
    _bind(hub);
    return _merge(sessions, hub);
  }

  void _bind(MuxHub hub) {
    _controlSub = hub.control.changes.listen(_onControlChanged);
    _signalSub = hub.events.sessionSignals.listen(_onSignal);
    _reconnectedSub = hub.events.reconnected.listen((_) => _scheduleReload());
  }

  void _onControlChanged(String sessionId) {
    final current = state.value;
    if (current == null || sessionId.isEmpty) return;
    final values = _hub?.control.store.valuesOf(sessionId);
    if (values == null || !values.containsKey('title')) return;
    final updated = [
      for (final session in current)
        session.sessionId == sessionId
            ? session.copyWith(title: values['title'] as String?)
            : session,
    ];
    state = AsyncData(updated);
  }

  void _onSignal(RemoteSessionSignal signal) {
    final current = state.value ?? const <SessionSummary>[];
    switch (signal) {
      case RemoteSessionStatus(:final sessionId, :final running):
        state = AsyncData([
          for (final session in current)
            session.sessionId == sessionId
                ? session.copyWith(running: running)
                : session,
        ]);
      case RemoteSessionAdded():
      case RemoteSessionRemoved():
        _scheduleReload();
      case RemoteSessionError(:final sessionId):
        state = AsyncData([
          for (final session in current)
            session.sessionId == sessionId
                ? session.copyWith(running: false)
                : session,
        ]);
      case RemoteSessionActivity(:final sessionId, :final time):
        state = AsyncData([
          for (final session in current)
            session.sessionId == sessionId
                ? session.copyWith(
                    updatedAt: DateTime.fromMillisecondsSinceEpoch(time),
                  )
                : session,
        ]);
    }
  }

  void _scheduleReload() {
    if (_disposed || _reloadTimer != null) return;
    _reloadTimer = Timer(const Duration(milliseconds: 250), () {
      _reloadTimer = null;
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    if (_disposed) return;
    if (_reloading) {
      _reloadQueued = true;
      return;
    }
    final api = _api;
    final hub = _hub;
    if (api == null) return;
    _reloading = true;
    try {
      final sessions = withoutSubagentSessions(await api.listSessions());
      if (_disposed) return;
      state = AsyncData(hub == null ? sessions : _merge(sessions, hub));
    } on AppException {
      // 增量信号失败不打断列表；下次信号或用户刷新重试。
    } finally {
      _reloading = false;
      if (_reloadQueued) {
        _reloadQueued = false;
        _scheduleReload();
      }
    }
  }

  List<SessionSummary> _merge(List<SessionSummary> sessions, MuxHub hub) {
    return [
      for (final session in sessions)
        _withProjection(session, hub.control.store.valuesOf(session.sessionId)),
    ];
  }

  SessionSummary _withProjection(
    SessionSummary session,
    Map<String, Object?>? values,
  ) {
    if (values == null) return session;
    final title = values['title'];
    return session.copyWith(title: title is String ? title : session.title);
  }

  void _cancelSubscriptions() {
    _controlSub?.cancel();
    _signalSub?.cancel();
    _reconnectedSub?.cancel();
    _controlSub = null;
    _signalSub = null;
    _reconnectedSub = null;
  }

  void _dispose() {
    _disposed = true;
    _reloadTimer?.cancel();
    _reloadTimer = null;
    _cancelSubscriptions();
  }
}

/// 当前服务端的已归档会话 id 集合。
///
/// 首次用本地缓存占位；`workspace/follow` 基线到达后以宿主为准。
final archivedIdsProvider = NotifierProvider<ArchivedIdsNotifier, Set<String>>(
  ArchivedIdsNotifier.new,
);

class ArchivedIdsNotifier extends Notifier<Set<String>> {
  StreamSubscription<void>? _subscription;

  @override
  Set<String> build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    final hub = ref.watch(muxHubProvider);
    _subscription?.cancel();
    _subscription = null;
    if (hub != null) {
      _subscription = hub.workspace.changes.listen((_) => _applyHub(hub));
      if (hub.workspace.hasBaseline) return hub.workspace.archivedSet;
    }
    final server = ref.watch(currentServerProvider);
    if (server == null) return const {};
    return ref.watch(serverStoreProvider).loadArchivedIds(server.id).toSet();
  }

  void _applyHub(MuxHub hub) {
    if (!hub.workspace.hasBaseline) return;
    final ids = hub.workspace.archivedSet;
    if (setEquals(state, ids)) return;
    state = ids;
    final server = ref.read(currentServerProvider);
    if (server != null) {
      unawaited(
        ref.read(serverStoreProvider).saveArchivedIds(server.id, ids.toList()),
      );
    }
  }

  Future<void> _save(String serverId, Set<String> ids) async {
    // 请求期间切换了服务端则丢弃旧结果，避免污染新服务端的归档集合。
    if (ref.read(currentServerIdProvider) != serverId) return;
    state = ids;
    await ref.read(serverStoreProvider).saveArchivedIds(serverId, ids.toList());
  }

  Future<void> archive(String sessionId) async {
    final api = ref.read(dshApiProvider);
    final serverId = ref.read(currentServerIdProvider);
    if (api == null || serverId == null) return;
    final ids = await api.archive(sessionId);
    await _save(serverId, ids.toSet());
  }

  Future<void> unarchive(String sessionId) async {
    final api = ref.read(dshApiProvider);
    final serverId = ref.read(currentServerIdProvider);
    if (api == null || serverId == null) return;
    final ids = await api.unarchive(sessionId);
    await _save(serverId, ids.toSet());
  }
}

/// 当前服务端的工作区列表（`workspace/follow` 权威序）。
final workspacesProvider =
    NotifierProvider<WorkspacesNotifier, List<WorkspaceRow>>(
      WorkspacesNotifier.new,
    );

class WorkspacesNotifier extends Notifier<List<WorkspaceRow>> {
  StreamSubscription<void>? _subscription;

  @override
  List<WorkspaceRow> build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    final hub = ref.watch(muxHubProvider);
    _subscription?.cancel();
    _subscription = null;
    if (hub == null) return const [];
    _subscription = hub.workspace.changes.listen((_) => _sync(hub));
    return hub.workspace.items;
  }

  void _sync(MuxHub hub) {
    if (!hub.workspace.hasBaseline) return;
    state = hub.workspace.items;
  }

  WorkspaceRow? findByFolder(String? folder) {
    if (folder == null) return null;
    for (final row in state) {
      if (row.title == folder || folderNameOf(row.path) == folder) return row;
    }
    return null;
  }

  /// [workspaceId] 在权威顺序中的前一个工作区 id（用于上移）。
  String? workspaceBefore(String workspaceId) {
    final hub = ref.read(muxHubProvider);
    if (hub == null) return null;
    final order = hub.workspace.items.map((row) => row.workspaceId).toList();
    final index = order.indexOf(workspaceId);
    if (index <= 0) return null;
    return order[index - 1];
  }

  /// 会话在工作区内当前的前一个会话 id（用于上移）；已是第一个返回 null。
  String? sessionBefore(String workspaceId, String sessionId) {
    final row = state
        .where((item) => item.workspaceId == workspaceId)
        .firstOrNull;
    if (row == null) return null;
    final index = row.sessionIds.indexOf(sessionId);
    if (index <= 0) return null;
    return row.sessionIds[index - 1];
  }

  Future<WorkspaceRow> create(String path) async {
    final api = ref.read(dshApiProvider);
    if (api == null) throw const ServerException('请先绑定服务端');
    final info = await api.createWorkspace(path);
    // workspace/follow 会推送 upsert；这里直接返回已解析的工作区。
    final existing = findByFolder(folderNameOf(info.path));
    return existing ??
        WorkspaceRow(
          workspaceId: info.workspaceId,
          path: info.path,
          title: info.title,
        );
  }

  Future<void> rename(String workspaceId, String title) async {
    final api = ref.read(dshApiProvider);
    if (api == null) return;
    await api.renameWorkspace(workspaceId, title);
  }

  Future<void> delete(String workspaceId) async {
    final api = ref.read(dshApiProvider);
    if (api == null) return;
    await api.deleteWorkspace(workspaceId);
  }

  Future<void> moveBefore(String workspaceId, String? beforeWorkspaceId) async {
    final api = ref.read(dshApiProvider);
    if (api == null) return;
    await api.moveWorkspaceBefore(
      workspaceId: workspaceId,
      beforeWorkspaceId: beforeWorkspaceId,
    );
  }

  Future<void> moveSessionBefore({
    required String workspaceId,
    required String sessionId,
    String? beforeSessionId,
  }) async {
    final api = ref.read(dshApiProvider);
    if (api == null) return;
    await api.moveSessionBefore(
      workspaceId: workspaceId,
      sessionId: sessionId,
      beforeSessionId: beforeSessionId,
    );
  }
}

/// 当前服务端的置顶会话 id 集合。
///
/// 0.2.1 宿主没有置顶能力（`workspace/follow` 也没有对应字段），
/// 这里保持纯本地偏好，仅影响列表排序。
final pinnedIdsProvider = NotifierProvider<PinnedIdsNotifier, Set<String>>(
  PinnedIdsNotifier.new,
);

class PinnedIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final server = ref.watch(currentServerProvider);
    if (server == null) return const {};
    return ref.watch(serverStoreProvider).loadPinnedIds(server.id).toSet();
  }

  Future<void> _save(String serverId, Set<String> ids) async {
    if (ref.read(currentServerIdProvider) != serverId) return;
    state = ids;
    await ref.read(serverStoreProvider).savePinnedIds(serverId, ids.toList());
  }

  Future<void> pin(String sessionId) async {
    final serverId = ref.read(currentServerIdProvider);
    if (serverId == null) return;
    await _save(serverId, {...state, sessionId});
    ref.invalidate(tasksProvider);
  }

  Future<void> unpin(String sessionId) async {
    final serverId = ref.read(currentServerIdProvider);
    if (serverId == null) return;
    await _save(serverId, {...state}..remove(sessionId));
    ref.invalidate(tasksProvider);
  }
}

/// 列表视图过滤排序（纯函数，可单测）：归档过滤 + 置顶优先。
/// 会话列表与搜索共用的可见集合：子任务（subagent）会话归属父会话，
/// 不在首页、归档、搜索里单独展示。
List<SessionSummary> withoutSubagentSessions(List<SessionSummary> sessions) {
  return [
    for (final session in sessions)
      if (!session.isSubagent) session,
  ];
}

List<SessionSummary> visibleSessions(
  List<SessionSummary> sessions, {
  required Set<String> archivedIds,
  required Set<String> pinnedIds,
  bool archivedView = false,
}) {
  final filtered = sessions
      .where((s) => archivedIds.contains(s.sessionId) == archivedView)
      .toList();
  int rank(SessionSummary s) => pinnedIds.contains(s.sessionId) ? 0 : 1;
  filtered.sort((a, b) {
    final byPin = rank(a).compareTo(rank(b));
    if (byPin != 0) return byPin;
    final aTime = a.updatedAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.updatedAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  });
  return filtered;
}

/// 按工作区过滤（分组前应用，日期/状态分组下同样生效）。
List<SessionSummary> filterSessionsByFolder(
  List<SessionSummary> sessions,
  String? folder,
) {
  if (folder == null) return sessions;
  return sessions.where((s) => s.folderName == folder).toList();
}

/// 按偏好分组过滤（纯函数，可单测）。
///
/// 工作区分组在 [workspaces] 非空时以宿主权威顺序为准；宿主只对桌面端登记过的
/// 会话回填 `sessionIds`（移动端 `session/create` 的会话不在其中），这类未登记
/// 会话按 cwd 并入对应工作区分组，保证分组标题唯一、不出现重名分区。
List<TaskGroup> groupTasks(
  List<SessionSummary> sessions,
  TaskPrefs prefs, {
  List<WorkspaceRow> workspaces = const [],
}) {
  var filtered = prefs.onlyRunning
      ? sessions.where((s) => s.running).toList()
      : sessions;
  final groups = <TaskGroup>[];
  switch (prefs.groupMode) {
    case TaskGroupMode.workspace:
      if (workspaces.isNotEmpty) {
        return _groupByWorkspace(filtered, workspaces);
      }
      for (final entry in _byFolder(filtered).entries) {
        groups.add(TaskGroup(entry.key, entry.value));
      }
    case TaskGroupMode.status:
      final running = filtered.where((s) => s.running).toList();
      final pending = filtered.where((s) => !s.running && s.blank).toList();
      final done = filtered.where((s) => !s.running && !s.blank).toList();
      if (running.isNotEmpty) groups.add(TaskGroup('进行中', running));
      if (pending.isNotEmpty) groups.add(TaskGroup('待处理', pending));
      if (done.isNotEmpty) groups.add(TaskGroup('已完成', done));
    case TaskGroupMode.date:
      final byDay = <DateTime, List<SessionSummary>>{};
      for (final session in filtered) {
        final day = session.updatedAt == null
            ? null
            : DateTime(
                session.updatedAt!.year,
                session.updatedAt!.month,
                session.updatedAt!.day,
              );
        byDay.putIfAbsent(day ?? DateTime(0), () => []).add(session);
      }
      final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final day in days) {
        groups.add(TaskGroup(_dayLabel(day), byDay[day]!));
      }
  }
  return groups;
}

/// 工作区分组：先按宿主权威顺序落位，再把未认领会话并入同名/同目录分组。
List<TaskGroup> _groupByWorkspace(
  List<SessionSummary> sessions,
  List<WorkspaceRow> workspaces,
) {
  final byId = {for (final session in sessions) session.sessionId: session};
  final claimed = <String>{};
  final titles = <String>[];
  final members = <List<SessionSummary>>[];
  final indexByPath = <String, int>{};
  final indexByTitle = <String, int>{};

  int addGroup(String title, {String? path}) {
    final index = titles.length;
    titles.add(title);
    members.add(<SessionSummary>[]);
    if (path != null && path.isNotEmpty) {
      indexByPath.putIfAbsent(_trimPath(path), () => index);
    }
    indexByTitle.putIfAbsent(title, () => index);
    return index;
  }

  for (final row in workspaces) {
    final list = <SessionSummary>[];
    for (final id in row.sessionIds) {
      final session = byId[id];
      if (session != null && claimed.add(id)) list.add(session);
    }
    if (list.isEmpty) continue;
    final title = row.title.isNotEmpty
        ? row.title
        : (folderNameOf(row.path) ?? row.path);
    members[addGroup(title, path: row.path)].addAll(list);
  }

  for (final session in sessions) {
    if (claimed.contains(session.sessionId)) continue;
    final folder = session.folderName;
    final target =
        indexByPath[_trimPath(session.cwd ?? '')] ??
        (folder == null ? null : indexByTitle[folder]);
    if (target != null) {
      members[target].add(session);
      continue;
    }
    final index = addGroup(folder ?? '未指定工作区');
    members[index].add(session);
  }

  return [
    for (var i = 0; i < titles.length; i++)
      if (members[i].isNotEmpty) TaskGroup(titles[i], members[i]),
  ];
}

String _trimPath(String path) => path.replaceAll(RegExp(r'[\\/]+$'), '');

Map<String, List<SessionSummary>> _byFolder(List<SessionSummary> sessions) {
  final byFolder = <String, List<SessionSummary>>{};
  for (final session in sessions) {
    byFolder.putIfAbsent(session.folderName ?? '未指定工作区', () => []).add(session);
  }
  return byFolder;
}

String _dayLabel(DateTime day) {
  if (day.year == 0) return '未知时间';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return '今天';
  if (day == today.subtract(const Duration(days: 1))) return '昨天';
  return '${day.year}/${day.month}/${day.day}';
}
