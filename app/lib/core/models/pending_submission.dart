import '../services/dsh_api.dart';

/// 本地乐观提交：从点击发送到宿主回显之间的状态。
enum PendingSubmissionStatus { sending, accepted, failed }

class PendingSubmission {
  final String requestId;
  final String text;

  /// 与 dsh 一致：图片与文件按选择顺序混排，失败重试时原样回发。
  final List<PromptAttachment> attachments;

  /// prompt 发出时宿主是否在运行：决定气泡落在转写还是队列。
  final bool queued;

  /// 发送模式：queue / steer；重试时沿用。
  final String mode;
  final PendingSubmissionStatus status;
  final String? error;

  const PendingSubmission({
    required this.requestId,
    required this.text,
    this.attachments = const [],
    this.queued = false,
    this.mode = 'queue',
    this.status = PendingSubmissionStatus.sending,
    this.error,
  });

  int get imageCount => attachments.whereType<PromptImage>().length;

  int get fileCount => attachments.whereType<PromptFile>().length;

  bool get hasAttachments => attachments.isNotEmpty;

  PendingSubmission copyWith({
    String? requestId,
    List<PromptAttachment>? attachments,
    bool? queued,
    String? mode,
    PendingSubmissionStatus? status,
    String? error,
  }) {
    return PendingSubmission(
      requestId: requestId ?? this.requestId,
      text: text,
      attachments: attachments ?? this.attachments,
      queued: queued ?? this.queued,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      error: error,
    );
  }
}
