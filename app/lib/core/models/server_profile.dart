/// 已绑定的 DSH 服务端档案。id 取网关 instanceId，用于去重与更新。
class ServerProfile {
  final String id;
  final String name;
  final Uri origin;
  final String password;
  final String mode;
  final DateTime addedAt;
  final DateTime lastUsedAt;

  const ServerProfile({
    required this.id,
    required this.name,
    required this.origin,
    required this.password,
    required this.mode,
    required this.addedAt,
    required this.lastUsedAt,
  });

  ServerProfile copyWith({
    String? name,
    String? password,
    String? mode,
    DateTime? lastUsedAt,
  }) {
    return ServerProfile(
      id: id,
      name: name ?? this.name,
      origin: origin,
      password: password ?? this.password,
      mode: mode ?? this.mode,
      addedAt: addedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'origin': origin.toString(),
    'password': password,
    'mode': mode,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'lastUsedAt': lastUsedAt.millisecondsSinceEpoch,
  };

  static ServerProfile fromJson(Map<String, dynamic> json) {
    final origin = Uri.tryParse(json['origin'] as String? ?? '');
    return ServerProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? origin?.host ?? 'DSH 服务端',
      origin: origin ?? Uri(),
      password: json['password'] as String? ?? '',
      mode: json['mode'] as String? ?? 'lan',
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['addedAt'] as num?)?.toInt() ?? 0,
      ),
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['lastUsedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
