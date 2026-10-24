/// 会话日志中的一条事件（会话 follow / page 的共同载体）。
///
/// 宿主在 0.2.1 中以 `{type:'event', event:{type, seq, time, data}}` 包装
/// 持久事件；这里只做无损解包，事件类型的语义由转写构建器负责。
class SessionWireEvent {
  final String type;
  final int seq;
  final int time;
  final Object? data;

  /// 表面事件的操作：`append` 新插入，`replace` 压缩替换。
  final String? surfaceOp;

  const SessionWireEvent({
    required this.type,
    required this.seq,
    required this.time,
    required this.data,
    this.surfaceOp,
  });

  /// 解析一条记录；格式不符返回 null（未知记录不抛错）。
  static SessionWireEvent? fromRecord(Object? record) {
    if (record is! Map) return null;
    if (record['type'] != 'event') return null;
    final event = record['event'];
    if (event is! Map) return null;
    final type = event['type'];
    final seq = event['seq'];
    if (type is! String || seq is! num) return null;
    final surfaceOp = event['surfaceOp'];
    return SessionWireEvent(
      type: type,
      seq: seq.toInt(),
      time: (event['time'] as num?)?.toInt() ?? 0,
      data: event['data'],
      surfaceOp: surfaceOp is String ? surfaceOp : null,
    );
  }

  static List<SessionWireEvent> fromRecords(Object? records) {
    if (records is! List) return const [];
    return [for (final record in records) ?SessionWireEvent.fromRecord(record)];
  }
}

/// `session/page` 的返回：一页事件 + 是否还有更早的历史。
class SessionHistoryPage {
  final List<SessionWireEvent> events;
  final bool hasMore;

  const SessionHistoryPage({this.events = const [], this.hasMore = false});
}

/// 转写中的一张图片：宿主附件引用或本地内嵌 base64（乐观消息）。
class TranscriptImage {
  /// 宿主附件 id；为空时使用 [inlineBase64]。
  final String attachmentId;

  final String? inlineBase64;
  final String? mediaType;
  final String? name;

  const TranscriptImage({
    this.attachmentId = '',
    this.inlineBase64,
    this.mediaType,
    this.name,
  });

  bool get isInline => attachmentId.isEmpty;
}

/// 从事件 data 的 content 数组提取纯文本、思考与图片引用。
({String text, String? reasoning, int imageCount, List<TranscriptImage> images})
summarizeContent(Object? content) {
  if (content is! List) {
    return (text: '', reasoning: null, imageCount: 0, images: const []);
  }
  final text = <String>[];
  final reasoning = <String>[];
  final images = <TranscriptImage>[];
  for (final part in content) {
    if (part is! Map) continue;
    switch (part['type']) {
      case 'text':
        final value = part['text'];
        if (value is String && value.isNotEmpty) text.add(value);
      case 'reasoning':
        final value = part['text'];
        if (value is String && value.isNotEmpty) reasoning.add(value);
      case 'image':
        images.add(_imageOf(part));
    }
  }
  return (
    text: text.join('\n'),
    reasoning: reasoning.isEmpty ? null : reasoning.join('\n\n'),
    imageCount: images.length,
    images: List.unmodifiable(images),
  );
}

/// 持久事件的 image 块：`{type:'image', attachment:{attachmentId,…}}`。
TranscriptImage _imageOf(Map part) {
  final attachment = part['attachment'];
  if (attachment is Map && attachment['attachmentId'] is String) {
    return TranscriptImage(
      attachmentId: attachment['attachmentId'] as String,
      mediaType: attachment['mediaType'] is String
          ? attachment['mediaType'] as String
          : null,
      name: attachment['name'] is String ? attachment['name'] as String : null,
    );
  }
  final data = part['data'];
  return TranscriptImage(
    inlineBase64: data is String && data.isNotEmpty ? data : null,
    mediaType: part['mediaType'] is String ? part['mediaType'] as String : null,
  );
}

/// 从 user/message 的 source 读取 prompt 对账 id。
String? promptRpcIdOf(Object? source) {
  if (source is! Map) return null;
  if (source['kind'] != 'user') return null;
  final rpcId = source['rpcId'];
  return rpcId is String && rpcId.isNotEmpty ? rpcId : null;
}
