import 'session_event.dart';

/// 会话转写节点（对应 DSH Web transcript 的核心子集）。
enum TranscriptKind { user, assistant, tool, error, notice, compaction }

class TranscriptNode {
  final String id;
  final TranscriptKind kind;
  final int seq;

  /// 宿主事件时间（毫秒），供消息操作行展示；0 或缺失为 null。
  final int? timeMs;
  final String text;
  final String? reasoning;
  final int imageCount;

  /// 消息内图片（宿主附件引用或本地内嵌）。
  final List<TranscriptImage> images;

  /// 工具节点字段。
  final String? toolName;
  final String? toolCallId;
  final String? toolArguments;
  final String? toolResult;
  final bool toolFailed;
  final bool toolFinished;

  /// 本地乐观消息标记（未获宿主回显）。
  final bool optimistic;
  final bool failed;

  /// 正在流式输出的 assistant 节点。
  final bool live;

  const TranscriptNode({
    required this.id,
    required this.kind,
    required this.seq,
    this.timeMs,
    this.text = '',
    this.reasoning,
    this.imageCount = 0,
    this.images = const [],
    this.toolName,
    this.toolCallId,
    this.toolArguments,
    this.toolResult,
    this.toolFailed = false,
    this.toolFinished = false,
    this.optimistic = false,
    this.failed = false,
    this.live = false,
  });

  TranscriptNode copyWith({
    String? text,
    String? reasoning,
    int? imageCount,
    String? toolResult,
    bool? toolFailed,
    bool? toolFinished,
    bool? optimistic,
    bool? failed,
    bool? live,
  }) {
    return TranscriptNode(
      id: id,
      kind: kind,
      seq: seq,
      timeMs: timeMs,
      text: text ?? this.text,
      reasoning: reasoning ?? this.reasoning,
      imageCount: imageCount ?? this.imageCount,
      toolName: toolName,
      toolCallId: toolCallId,
      toolArguments: toolArguments,
      toolResult: toolResult ?? this.toolResult,
      toolFailed: toolFailed ?? this.toolFailed,
      toolFinished: toolFinished ?? this.toolFinished,
      optimistic: optimistic ?? this.optimistic,
      failed: failed ?? this.failed,
      live: live ?? this.live,
    );
  }
}
