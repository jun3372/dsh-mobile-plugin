/// 0.2.1 `goal` 投影：当前目标及其已开始的轮数。
class GoalInfo {
  final String id;
  final int revision;
  final String objective;
  final String phase;
  final String? blockedCode;
  final String? blockedMessage;
  final int maxGoalRounds;
  final int roundsStarted;

  const GoalInfo({
    required this.id,
    required this.revision,
    required this.objective,
    required this.phase,
    this.blockedCode,
    this.blockedMessage,
    this.maxGoalRounds = 0,
    this.roundsStarted = 0,
  });

  bool get isActive => phase == 'active';
  bool get isBlocked => phase == 'blocked';

  String get phaseLabel => switch (phase) {
    'active' => '进行中',
    'paused' => '已暂停',
    'blocked' => '受阻',
    'complete' => '已完成',
    _ => phase,
  };

  static GoalInfo? fromValue(Object? value) {
    if (value is! Map) return null;
    final goal = value['goal'];
    if (goal is! Map) return null;
    final id = goal['id'];
    final objective = goal['objective'];
    if (id is! String || objective is! String) return null;
    final blocked = goal['blockedReason'];
    return GoalInfo(
      id: id,
      revision: (goal['revision'] as num?)?.toInt() ?? 0,
      objective: objective,
      phase: goal['phase'] as String? ?? 'active',
      blockedCode: blocked is Map ? blocked['code'] as String? : null,
      blockedMessage: blocked is Map ? blocked['message'] as String? : null,
      maxGoalRounds: (goal['maxGoalRounds'] as num?)?.toInt() ?? 0,
      roundsStarted: (value['roundsStarted'] as num?)?.toInt() ?? 0,
    );
  }
}
