import 'session_event.dart';

/// 宿主 inbox 投影里的一条待处理用户消息。
class QueuedMessage {
  final String itemId;
  final String text;
  final int imageCount;
  final String target;
  final String? rpcId;

  const QueuedMessage({
    required this.itemId,
    required this.text,
    required this.target,
    this.imageCount = 0,
    this.rpcId,
  });

  /// 本地乐观项：宿主还没回收据，任何队列操作都会被拒，先禁掉。
  bool get isLocal => itemId.startsWith('local-');

  static List<QueuedMessage> listFromValue(Object? inbox) =>
      fromProjection(inbox);

  /// 对齐 Web 队列面板语义（控制帧 `placement === 'queued'`）：
  /// 只透出 `source.kind === 'user'` 的真实 prompt。切换授权预设时宿主会向
  /// inbox `next-step` 注入模型通知（如「The approval policy changed…」，
  /// source.kind=user-approval，Web 侧归为 context 不展示），这类条目既不可
  /// 编辑也不能插队/撤回，必须过滤，否则会在队列里卡成无法处理的「待处理」。
  static List<QueuedMessage> fromProjection(Object? inbox) {
    if (inbox is! Map) return const [];
    final result = <QueuedMessage>[];
    for (final target in const ['next-turn', 'next-step']) {
      final items = inbox[target];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id is! String) continue;
        final source = item['source'];
        if (source is! Map || source['kind'] != 'user') continue;
        final summary = summarizeContent(item['content']);
        if (summary.text.isEmpty && summary.imageCount == 0) continue;
        result.add(
          QueuedMessage(
            itemId: id,
            text: summary.text,
            imageCount: summary.imageCount,
            target: target,
            rpcId: promptRpcIdOf(source),
          ),
        );
      }
    }
    return result;
  }
}
