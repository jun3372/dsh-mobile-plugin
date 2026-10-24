/// 0.2.1 `turnOutline` 投影中的一轮摘要。
class TurnOutlineEntry {
  final int turn;
  final int seq;
  final String prompt;
  final String response;

  const TurnOutlineEntry({
    required this.turn,
    required this.seq,
    this.prompt = '',
    this.response = '',
  });

  static List<TurnOutlineEntry> listFromValue(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map && item['turn'] is num && item['seq'] is num)
          TurnOutlineEntry(
            turn: (item['turn'] as num).toInt(),
            seq: (item['seq'] as num).toInt(),
            prompt: item['prompt'] as String? ?? '',
            response: item['response'] as String? ?? '',
          ),
    ];
  }
}
