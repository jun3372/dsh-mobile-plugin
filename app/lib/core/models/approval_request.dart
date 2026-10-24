/// 一条待应答的工具审批（`approval/request` waterfall）。
class ApprovalRequest {
  final String eventId;
  final String agentId;
  final String toolName;
  final String? callId;
  final String? reason;
  final String? displayReason;

  const ApprovalRequest({
    required this.eventId,
    required this.agentId,
    required this.toolName,
    this.callId,
    this.reason,
    this.displayReason,
  });

  static ApprovalRequest? fromInvocation({
    required String eventId,
    required String agentId,
    required Object? request,
  }) {
    if (request is! Map) return null;
    final toolName = request['toolName'];
    if (toolName is! String || toolName.isEmpty) return null;
    final display = request['displayReason'];
    return ApprovalRequest(
      eventId: eventId,
      agentId: agentId,
      toolName: toolName,
      callId: request['callId'] as String?,
      reason: request['reason'] as String?,
      displayReason: display is Map
          ? display['zh'] as String? ?? display['en'] as String?
          : null,
    );
  }

  String get detail => displayReason ?? reason ?? '该工具需要你的确认后才能继续';
}
