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

  /// 只写穿持久化，不更新响应式状态：lastUsedAt 不参与任何 UI 展示与排序，
  /// 一旦同步进 state 会生成新 List，连带重建所有 watch 整表的 family provider
  /// （全部 ApiClient/MuxHub 断开重连、后台等待输入通知被撤下重弹）。
  /// 新值下次冷启动从 ServerStore 载入。
  Future<void> touch(String id) async {
    final now = DateTime.now();
    final servers = [
      for (final s in state) s.id == id ? s.copyWith(lastUsedAt: now) : s,
    ];
    await ref.read(serverStoreProvider).saveServers(servers);
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

/// 取列表中指定 id 的档案（无则 null）。作为 select 选择器使用：
/// 只有本 id 的档案实例变化才会触发依赖方重建，其他服务端增删改不连坐。
ServerProfile? _profileById(List<ServerProfile> servers, String id) {
  for (final server in servers) {
    if (server.id == id) return server;
  }
  return null;
}

/// 按服务端 id 的 HTTP 客户端家族：多服务端并行保活时各自独立
/// （单飞登录/刷新、401 重放互不影响）。
final apiClientFamilyProvider = Provider.family<ApiClient?, String>((ref, id) {
  final server = ref.watch(
    serversProvider.select((servers) => _profileById(servers, id)),
  );
  if (server == null) return null;
  final client = ApiClient(origin: server.origin, password: server.password);
  ref.onDispose(client.close);
  return client;
});

/// 当前服务端共享的 HTTP 客户端。
///
/// 切换服务端不会关闭旧实例——家族实例由仍在其上的保活订阅持有。
final apiClientProvider = Provider<ApiClient?>((ref) {
  final id = ref.watch(currentServerIdProvider);
  if (id == null) return null;
  return ref.watch(apiClientFamilyProvider(id));
});

/// 按服务端 id 的业务 API。
final dshApiFamilyProvider = Provider.family<DshApi?, String>((ref, id) {
  final client = ref.watch(apiClientFamilyProvider(id));
  if (client == null) return null;
  return DshApi(client);
});

/// 当前服务端的业务 API；未绑定时为 null。
final dshApiProvider = Provider<DshApi?>((ref) {
  final id = ref.watch(currentServerIdProvider);
  if (id == null) return null;
  return ref.watch(dshApiFamilyProvider(id));
});

/// 按服务端 id 的 mux 组合：一条 `/api/remote.mux` + 服务器级长活流。
///
/// 首次读取即开始连接；非 autoDispose，创建后即使不再被当前页使用也保活
/// （多服务端后台通知依赖这里的长活流），直到服务端被解绑。
final muxHubFamilyProvider = Provider.family<MuxHub?, String>((ref, id) {
  final client = ref.watch(apiClientFamilyProvider(id));
  final api = ref.watch(dshApiFamilyProvider(id));
  final server = ref.watch(
    serversProvider.select((servers) => _profileById(servers, id)),
  );
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

/// 当前服务端的 mux 组合；其余已绑定服务端的 hub 由
/// [muxHubFamilyProvider] 的保活订阅方（如等待输入通知控制器）持有。
final muxHubProvider = Provider<MuxHub?>((ref) {
  final id = ref.watch(currentServerIdProvider);
  if (id == null) return null;
  return ref.watch(muxHubFamilyProvider(id));
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
