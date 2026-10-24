/// 0.2.1 `todos` 投影中的一项。
class TodoItem {
  final String content;
  final String status;

  const TodoItem({required this.content, required this.status});

  bool get isDone => status == 'completed';
  bool get isActive => status == 'in_progress';

  static List<TodoItem> listFromValue(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map && item['content'] is String)
          TodoItem(
            content: item['content'] as String,
            status: item['status'] as String? ?? 'pending',
          ),
    ];
  }
}
