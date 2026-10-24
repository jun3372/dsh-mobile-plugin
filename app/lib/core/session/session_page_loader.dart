import '../models/session_event.dart';
import '../services/dsh_api.dart';

/// `session/page` 历史分页：通过 `throughSeq` 固定窗口上界，用 `beforeSeq` 向前翻页。
class SessionPageLoader {
  final DshApi _api;
  final String sessionId;

  SessionPageLoader(this._api, this.sessionId);

  bool _loading = false;

  bool get isLoading => _loading;

  /// 加载比 [beforeSeq] 更早的一页；无更多历史时返回空页。
  Future<SessionHistoryPage> loadOlder({
    required int throughSeq,
    required int beforeSeq,
    int maxMessages = 80,
    Map<String, Object?>? turnWindow,
  }) async {
    if (_loading) {
      return const SessionHistoryPage();
    }
    _loading = true;
    try {
      return await _api.page(
        sessionId,
        throughSeq: throughSeq,
        beforeSeq: beforeSeq,
        maxMessages: maxMessages,
        turnWindow: turnWindow,
      );
    } finally {
      _loading = false;
    }
  }
}
