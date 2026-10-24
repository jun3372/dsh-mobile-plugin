import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors.dart';
import '../../core/models/server_profile.dart';
import '../../core/mux/mux_hub.dart';
import '../../core/services/api_client.dart';
import '../../core/services/dsh_api.dart';
import '../../core/services/server_store.dart';

/// 在 main 中 overrideWithValue 注入。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('main 中必须 override sharedPreferencesProvider'),
);

final serverStoreProvider = Provider<ServerStore>(
  (ref) => ServerStore(ref.watch(sharedPreferencesProvider)),
);

/// 已绑定的服务端列表（写穿 ServerStore）。
final serversProvider = NotifierProvider<ServersNotifier, List<ServerProfile>>(
  ServersNotifier.new,
);

class ServersNotifier extends Notifier<List<ServerProfile>> {
  @override
  List<ServerProfile> build() => ref.watch(serverStoreProvider).loadServers();

  Future<void> upsert(ServerProfile profile, {bool makeCurrent = true}) async {
    final servers = [...state];
    final index = servers.indexWhere((s) => s.id == profile.id);
    if (index >= 0) {
      servers[index] = profile;
    } else {
      servers.add(profile);
    }
    state = servers;
    final store = ref.read(serverStoreProvider);
    await store.saveServers(servers);
    if (makeCurrent) {
      await ref.read(currentServerIdProvider.notifier).setCurrent(profile.id);
    }
  }

  Future<void> remove(String id) async {
    final servers = state.where((s) => s.id != id).toList();
    state = servers;
    await ref.read(serverStoreProvider).saveServers(servers);
    if (ref.read(currentServerIdProvider) == id) {
      await ref
          .read(currentServerIdProvider.notifier)
          .setCurrent(servers.isEmpty ? null : servers.first.id);
    }
  }

  Future<void> touch(String id) async {
    state = [
      for (final s in state)
        s.id == id ? s.copyWith(lastUsedAt: DateTime.now()) : s,
    ];
    await ref.read(serverStoreProvider).saveServers(state);
  }
}

/// 当前服务端 id：存储值仍存在于列表则用之，否则回退列表首个。
final currentServerIdProvider =
    NotifierProvider<CurrentServerIdNotifier, String?>(
      CurrentServerIdNotifier.new,
    );

class CurrentServerIdNotifier extends Notifier<String?> {
  /// 只依赖 ServerStore，不 watch serversProvider：后者写入时会调用
  /// setCurrent，反过来 watch 会构成 provider 环（debug 下直接抛
  /// CircularDependencyError，绑定流程中断）。列表变化由
  /// [ServersNotifier.upsert] / [ServersNotifier.remove] 显式同步。
  @override
  String? build() {
    final store = ref.watch(serverStoreProvider);
    final servers = store.loadServers();
    if (servers.isEmpty) return null;
    final stored = store.loadCurrentServerId();
    return servers.any((s) => s.id == stored) ? stored : servers.first.id;
  }

  Future<void> setCurrent(String? id) async {
    await ref.read(serverStoreProvider).setCurrentServerId(id);
    state = id;
  }
}

final currentServerProvider = Provider<ServerProfile?>((ref) {
  final id = ref.watch(currentServerIdProvider);
  if (id == null) return null;
  for (final server in ref.watch(serversProvider)) {
    if (server.id == id) return server;
  }
  return null;
});

/// 当前服务端共享的 HTTP 客户端（单飞登录/刷新、401 重放）。
///
/// 切换服务端会重建并关闭旧实例；WS 握手也复用这里的 token。
final apiClientProvider = Provider<ApiClient?>((ref) {
  final server = ref.watch(currentServerProvider);
  if (server == null) return null;
  final client = ApiClient(origin: server.origin, password: server.password);
  ref.onDispose(client.close);
  return client;
});

/// 当前服务端的业务 API；未绑定时为 null。生命周期跟随 [apiClientProvider]。
final dshApiProvider = Provider<DshApi?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return null;
  return DshApi(client);
});

/// 当前服务端的 mux 组合：一条 `/api/remote.mux` + 服务器级长活流。
///
/// 首次读取即开始连接；切换服务端时整体释放。
final muxHubProvider = Provider<MuxHub?>((ref) {
  final server = ref.watch(currentServerProvider);
  final client = ref.watch(apiClientProvider);
  final api = ref.watch(dshApiProvider);
  if (server == null || client == null || api == null) return null;
  final hub = MuxHub(
    origin: server.origin,
    api: api,
    tokenProvider: () async {
      try {
        return await client.authToken();
      } on AppException {
        return null;
      }
    },
  );
  ref.onDispose(hub.dispose);
  hub.start();
  return hub;
});

/// 连接探活：能拉到会话列表视为在线。
final connectionCheckProvider = FutureProvider.autoDispose<bool>((ref) async {
  final api = ref.watch(dshApiProvider);
  if (api == null) return false;
  try {
    await api.listSessions();
    return true;
  } on AppException {
    return false;
  }
});
