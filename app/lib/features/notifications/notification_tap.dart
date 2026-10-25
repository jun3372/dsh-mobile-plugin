import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/models/dsh_session.dart';
import '../servers/servers_providers.dart';
import '../sessions/session_page.dart';

/// 通知 payload 编解码：`kind|serverId|sessionId`。
///
/// 只携带路由目标，不含密码/token（日志脱敏约束）；分隔符依赖
/// serverId/sessionId 不含 `|`（与通知去重键 `$serverId|$sessionId` 同约定）。
String encodeNotificationPayload({
  required String kind,
  required String serverId,
  required String sessionId,
}) => '$kind|$serverId|$sessionId';

class NotificationTarget {
  final String kind;
  final String serverId;
  final String sessionId;

  const NotificationTarget({
    required this.kind,
    required this.serverId,
    required this.sessionId,
  });
}

NotificationTarget? decodeNotificationPayload(String payload) {
  final parts = payload.split('|');
  if (parts.length != 3) return null;
  final kind = parts[0];
  final serverId = parts[1];
  final sessionId = parts[2];
  if (kind.isEmpty || serverId.isEmpty || sessionId.isEmpty) return null;
  return NotificationTarget(
    kind: kind,
    serverId: serverId,
    sessionId: sessionId,
  );
}

/// 通知点击统一入口：解析 payload → 切到对应服务端 → 回到首页并打开会话。
///
/// 冷启动场景 navigator 可能尚未挂载，逐帧重试一小段时间。
void handleNotificationTap(String payload) {
  final target = decodeNotificationPayload(payload);
  if (target == null) return;
  _openTarget(target, attempts: 12);
}

void _openTarget(NotificationTarget target, {required int attempts}) {
  final context = dshNavigatorKey.currentContext;
  if (context == null) {
    if (attempts <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openTarget(target, attempts: attempts - 1);
    });
    return;
  }
  _openTargetOnContext(context, target);
}

void _openTargetOnContext(BuildContext context, NotificationTarget target) {
  final container = ProviderScope.containerOf(context);
  // 会话属于其他服务端时先切当前服务端（SessionPage 依赖当前服务端的
  // api/mux 组合；切换完成后 SessionPage 因 watch currentServerProvider
  // 自动以新服务端重建）。
  if (container.read(currentServerIdProvider) != target.serverId) {
    unawaited(
      container
          .read(currentServerIdProvider.notifier)
          .setCurrent(target.serverId)
          .catchError((Object _) {}),
    );
  }
  final navigator = Navigator.of(context);
  navigator.popUntil((route) => route.isFirst);
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) =>
          SessionPage(summary: SessionSummary(sessionId: target.sessionId)),
    ),
  );
}
