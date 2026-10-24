import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_profile.dart';

/// 服务端档案持久化（SharedPreferences JSON 列表，坏数据容错跳过）。
class ServerStore {
  static const _kServers = 'dsh.servers';
  static const _kCurrentId = 'dsh.currentServerId';
  static const _kArchivedPrefix = 'dsh.archived.';
  static const _kPinnedPrefix = 'dsh.pinned.';

  final SharedPreferences _prefs;

  ServerStore(this._prefs);

  List<ServerProfile> loadServers() {
    final raw = _prefs.getString(_kServers);
    if (raw == null || raw.isEmpty) return const [];
    final List<dynamic> decoded;
    try {
      final value = jsonDecode(raw);
      if (value is! List) return const [];
      decoded = value;
    } catch (_) {
      return const [];
    }
    final servers = <ServerProfile>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      final origin = item['origin'];
      if (id is! String || id.isEmpty || origin is! String || origin.isEmpty) {
        continue;
      }
      try {
        servers.add(ServerProfile.fromJson(item));
      } catch (_) {
        // 单条坏数据不拖垮整个列表。
      }
    }
    return servers;
  }

  Future<void> saveServers(List<ServerProfile> servers) {
    return _prefs.setString(
      _kServers,
      jsonEncode(servers.map((s) => s.toJson()).toList()),
    );
  }

  String? loadCurrentServerId() => _prefs.getString(_kCurrentId);

  Future<void> setCurrentServerId(String? id) {
    if (id == null) return _prefs.remove(_kCurrentId);
    return _prefs.setString(_kCurrentId, id);
  }

  /// 已归档/置顶会话 id 集合（按服务端隔离）。
  /// 宿主只在 archive/pin 等写操作的返回里给出权威集合，这里持久化最近一次同步的值。
  List<String> loadArchivedIds(String serverId) =>
      _prefs.getStringList('$_kArchivedPrefix$serverId') ?? const [];

  Future<void> saveArchivedIds(String serverId, List<String> ids) =>
      _prefs.setStringList('$_kArchivedPrefix$serverId', ids);

  List<String> loadPinnedIds(String serverId) =>
      _prefs.getStringList('$_kPinnedPrefix$serverId') ?? const [];

  Future<void> savePinnedIds(String serverId, List<String> ids) =>
      _prefs.setStringList('$_kPinnedPrefix$serverId', ids);
}
