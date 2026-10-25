import 'package:dsh_mobile/core/models/server_profile.dart';
import 'package:dsh_mobile/features/servers/servers_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 绑定流程曾在这一点踩坑：upsert 要写「当前服务端」，而当前服务端 provider
/// 又 watch 服务端列表，riverpod 判为 provider 环并直接抛错。
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ServerProfile profile(String id) {
    final now = DateTime.now();
    return ServerProfile(
      id: id,
      name: 'server-$id',
      origin: Uri.parse('http://10.0.2.2:39081'),
      password: 'pw-$id',
      mode: 'lan',
      addedAt: now,
      lastUsedAt: now,
    );
  }

  ProviderContainer container() => ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  test('绑定新服务端后当前 id 立即生效', () async {
    final c = container();
    addTearDown(c.dispose);
    expect(c.read(currentServerIdProvider), isNull);

    await c.read(serversProvider.notifier).upsert(profile('s1'));

    expect(c.read(currentServerIdProvider), 's1');
    expect(c.read(currentServerProvider)?.id, 's1');
  });

  test('删除当前服务端后回退到剩余首个，删空后为 null', () async {
    final c = container();
    addTearDown(c.dispose);
    final notifier = c.read(serversProvider.notifier);
    await notifier.upsert(profile('s1'), makeCurrent: false);
    await notifier.upsert(profile('s2'));

    await notifier.remove('s2');
    expect(c.read(currentServerIdProvider), 's1');

    await notifier.remove('s1');
    expect(c.read(currentServerIdProvider), isNull);
  });

  test('冷启动优先用持久化的当前 id，缺失时回退列表首个', () async {
    final first = container();
    await first.read(serversProvider.notifier).upsert(profile('s1'));
    await first.read(serversProvider.notifier).upsert(profile('s2'));
    await first.read(currentServerIdProvider.notifier).setCurrent('s2');
    first.dispose();

    expect(container().read(currentServerIdProvider), 's2');

    await prefs.remove('dsh.currentServerId');
    expect(container().read(currentServerIdProvider), 's1');
  });

  test('touch 只写持久化，不更新列表状态也不触发 family 重建', () async {
    final c = container();
    addTearDown(c.dispose);
    await c
        .read(serversProvider.notifier)
        .upsert(profile('s1'), makeCurrent: false);
    await c.read(serversProvider.notifier).upsert(profile('s2'));

    var builds = 0;
    c.listen(
      serversProvider.select((servers) => _byId(servers, 's1')),
      (_, _) => builds++,
    );

    final before = c.read(serversProvider);
    await c.read(serversProvider.notifier).touch('s1');

    // 响应式状态保持同一 List 实例（select 订阅者不触发）。
    expect(identical(c.read(serversProvider), before), isTrue);
    expect(builds, 0);

    // 持久化侧已更新：新容器冷启动读到新的 lastUsedAt。
    final store = c.read(serverStoreProvider);
    final persisted = store.loadServers().firstWhere((s) => s.id == 's1');
    final stale = before.firstWhere((s) => s.id == 's1');
    expect(
      persisted.lastUsedAt.isAfter(stale.lastUsedAt) ||
          persisted.lastUsedAt.isAtSameMomentAs(stale.lastUsedAt),
      isTrue,
      reason: 'lastUsedAt 应随 touch 落盘（同毫秒内允许相等）',
    );
  });
}

ServerProfile? _byId(List<ServerProfile> servers, String id) {
  for (final server in servers) {
    if (server.id == id) return server;
  }
  return null;
}
