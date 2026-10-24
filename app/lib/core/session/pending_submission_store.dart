import '../models/pending_submission.dart';

/// 本地待回显消息：requestId 与服务端 `user/message.source.rpcId` 一一对账。
///
/// 不做文本匹配；重试会换新的 requestId（宿主没有去重）。
class PendingSubmissionStore {
  final Map<String, PendingSubmission> _items = {};

  List<PendingSubmission> get items =>
      List.unmodifiable(_items.values.toList(growable: false));

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  PendingSubmission? byId(String requestId) => _items[requestId];

  void add(PendingSubmission submission) {
    _items[submission.requestId] = submission;
  }

  void markAccepted(String requestId) {
    final current = _items[requestId];
    if (current == null) return;
    _items[requestId] = current.copyWith(
      status: PendingSubmissionStatus.accepted,
    );
  }

  void markFailed(String requestId, String error) {
    final current = _items[requestId];
    if (current == null) return;
    _items[requestId] = current.copyWith(
      status: PendingSubmissionStatus.failed,
      error: error,
    );
  }

  void remove(String requestId) {
    _items.remove(requestId);
  }

  /// 回显（持久用户消息）或宿主 inbox 收据出现后回收本地气泡。
  ///
  /// 返回是否有条目被移除。
  bool reconcile({
    required Set<String> echoedRpcIds,
    required Set<String> inboxRpcIds,
  }) {
    final removable = [
      for (final entry in _items.entries)
        if (echoedRpcIds.contains(entry.key) || inboxRpcIds.contains(entry.key))
          entry.key,
    ];
    for (final requestId in removable) {
      _items.remove(requestId);
    }
    return removable.isNotEmpty;
  }

  void clear() => _items.clear();
}
