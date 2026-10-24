import 'package:dsh_mobile/core/models/server_profile.dart';
import 'package:dsh_mobile/core/services/server_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ServerStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = ServerStore(prefs);
  });

  ServerProfile profile(
    String id, {
    String origin = 'http://192.168.1.50:39081',
  }) {
    final now = DateTime.now();
    return ServerProfile(
      id: id,
      name: 'server-$id',
      origin: Uri.parse(origin),
      password: 'pw-$id',
      mode: 'lan',
      addedAt: now,
      lastUsedAt: now,
    );
  }

  test('初始为空列表与空当前 id', () {
    expect(store.loadServers(), isEmpty);
    expect(store.loadCurrentServerId(), isNull);
  });

  test('保存与读取往返一致', () async {
    final servers = [profile('a'), profile('b')];
    await store.saveServers(servers);
    await store.setCurrentServerId('b');
    final loaded = store.loadServers();
    expect(loaded, hasLength(2));
    expect(loaded[1].id, 'b');
    expect(loaded[1].password, 'pw-b');
    expect(store.loadCurrentServerId(), 'b');
  });

  test('清空当前 id', () async {
    await store.setCurrentServerId('a');
    await store.setCurrentServerId(null);
    expect(store.loadCurrentServerId(), isNull);
  });

  test('坏 JSON 返回空列表而不是抛错', () async {
    await prefs.setString('dsh.servers', '{not json');
    expect(store.loadServers(), isEmpty);
  });

  test('非列表 JSON 返回空列表', () async {
    await prefs.setString('dsh.servers', '{"a":1}');
    expect(store.loadServers(), isEmpty);
  });

  test('缺必填字段的条目被跳过，完好条目保留', () async {
    await prefs.setString(
      'dsh.servers',
      '[{"id":"ok","origin":"http://x:1","name":"n","password":"p","mode":"lan",'
          '"addedAt":1,"lastUsedAt":1},{"id":"","origin":"http://x:1"},{"origin":"http://x:1"}]',
    );
    final loaded = store.loadServers();
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'ok');
  });
}
