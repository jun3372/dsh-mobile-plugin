import 'dart:async';

import '../mux/dsh_mux_client.dart';
import '../mux/mux_subscription.dart';

/// `workspace/follow` 中的工作区行。
class WorkspaceRow {
  final String workspaceId;
  final String path;
  final String title;
  final List<String> sessionIds;

  /// 0.2.1 的 `WorkspaceView.createdAt/updatedAt` 都是 ISO 字符串。
  final String? createdAt;
  final String? updatedAt;

  const WorkspaceRow({
    required this.workspaceId,
    required this.path,
    this.title = '',
    this.sessionIds = const [],
    this.createdAt,
    this.updatedAt,
  });

  static WorkspaceRow? fromValue(Object? value) {
    if (value is! Map) return null;
    final workspaceId = value['workspaceId'];
    if (workspaceId is! String) return null;
    return WorkspaceRow(
      workspaceId: workspaceId,
      path: value['path'] as String? ?? '',
      title: value['title'] as String? ?? '',
      sessionIds: (value['sessionIds'] as List? ?? [])
          .whereType<String>()
          .toList(),
      createdAt: value['createdAt'] is String
          ? value['createdAt'] as String
          : null,
      updatedAt: value['updatedAt'] is String
          ? value['updatedAt'] as String
          : null,
    );
  }
}

/// 服务器级 `workspace/follow`：工作区顺序 + 权威归档/置顶集合。
class WorkspaceHub {
  final DshMuxClient _client;
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );
  final StreamController<void> _reconnected = StreamController<void>.broadcast(
    sync: true,
  );

  MuxSubscription? _subscription;
  StreamSubscription<MuxStreamEvent>? _events;
  final List<WorkspaceRow> _items = [];
  final List<String> _order = [];
  List<String> _archived = const [];
  bool _started = false;
  bool _disposed = false;
  bool _hasBaseline = false;

  WorkspaceHub(this._client);

  Stream<void> get changes => _changes.stream;

  /// 重连拿到新基线后触发，供列表重新拉取兜底。
  Stream<void> get reconnected => _reconnected.stream;

  List<WorkspaceRow> get items => List.unmodifiable(_items);

  /// 是否已经收到过头帧基线；未就绪时 UI 用本地缓存占位。
  bool get hasBaseline => _hasBaseline;

  List<String> get archivedSessionIds => _archived;

  Set<String> get archivedSet => _archived.toSet();

  /// 工作区内的会话顺序（0.2.1 的 baseline items 已按工作区顺序排列）。
  List<String> get orderedSessionIds {
    final result = <String>[];
    final seen = <String>{};
    for (final workspaceId in _order) {
      final row = _items.where((item) => item.workspaceId == workspaceId);
      if (row.isEmpty) continue;
      for (final sessionId in row.first.sessionIds) {
        if (seen.add(sessionId)) result.add(sessionId);
      }
    }
    for (final row in _items) {
      for (final sessionId in row.sessionIds) {
        if (seen.add(sessionId)) result.add(sessionId);
      }
    }
    return result;
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _subscription = _client.openStream(
      'workspace/follow',
      args: const <String, Object?>{},
    );
    _events = _subscription!.events.listen(_onEvent);
  }

  void _onEvent(MuxStreamEvent event) {
    switch (event) {
      case MuxStreamOpened(:final restarted):
        if (restarted && !_reconnected.isClosed) _reconnected.add(null);
      case MuxStreamItem():
        _onItem(event.value);
      case MuxStreamFailure():
      case MuxStreamEnded():
      case MuxStreamCarrierLost():
        break;
    }
  }

  void _onItem(Object? value) {
    if (value is! Map) return;
    switch (value['type']) {
      case 'baseline':
        _replaceBaseline(value['value']);
      case 'replace':
        _replaceBaseline(value['value']);
      case 'upsert':
        final row = WorkspaceRow.fromValue(value['workspace']);
        if (row == null) return;
        _upsert(row);
      case 'remove':
        final workspaceId = value['workspaceId'];
        if (workspaceId is! String) return;
        _items.removeWhere((item) => item.workspaceId == workspaceId);
        _order.remove(workspaceId);
      case 'order':
        final ids = value['workspaceIds'];
        if (ids is! List) return;
        _order
          ..clear()
          ..addAll(ids.whereType<String>());
      case 'archived':
        final ids = value['archivedSessionIds'];
        if (ids is! List) return;
        _archived = ids.whereType<String>().toList();
      default:
        return;
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  void _replaceBaseline(Object? value) {
    if (value is! Map) return;
    _hasBaseline = true;
    _items.clear();
    _order.clear();
    final items = value['items'];
    if (items is List) {
      for (final raw in items) {
        final row = WorkspaceRow.fromValue(raw);
        if (row != null) _items.add(row);
      }
    }
    _order.addAll(_items.map((item) => item.workspaceId));
    final order = value['workspaceIds'];
    if (order is List) {
      final ids = order.whereType<String>().toList();
      if (ids.isNotEmpty) {
        _order
          ..clear()
          ..addAll(ids);
      }
    }
    final archived = value['archivedSessionIds'];
    if (archived is List) _archived = archived.whereType<String>().toList();
  }

  void _upsert(WorkspaceRow row) {
    final index = _items.indexWhere(
      (item) => item.workspaceId == row.workspaceId,
    );
    if (index >= 0) {
      _items[index] = row;
    } else {
      _items.add(row);
      _order.add(row.workspaceId);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events?.cancel();
    _events = null;
    _subscription?.dispose();
    _subscription = null;
    unawaited(_changes.close());
    unawaited(_reconnected.close());
  }
}
