import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知能力的可注入抽象（单测用假实现替换）。
abstract class NotificationApi {
  Future<void> init();

  Future<bool> requestPermission();

  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

class LocalNotificationsApi implements NotificationApi {
  static const _channelId = 'dsh_input_request';
  static const _channelName = '任务等待输入';
  static const _channelDescription = '会话等待你回答问题或确认计划';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        // ohos 侧原生经 resourceManager.getMediaByName 解析，须为 entry
        // 模块 media 资源名（entry/src/main/resources/base/media/icon.png）。
        ohos: OhosInitializationSettings('icon'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      final ohos = _plugin
          .resolvePlatformSpecificImplementation<
            OhosFlutterLocalNotificationsPlugin
          >();
      if (ohos != null) {
        return await ohos.requestNotificationsPermission() ?? false;
      }
      return false;
    } catch (_) {
      // 权限失败不阻塞功能：未授权时 show 会静默失败。
      return false;
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBanner: true,
        ),
        ohos: OhosNotificationDetails(
          OhosNotificationSlotType.SOCIAL_COMMUNICATION,
          importance: OhosImportance.high,
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
