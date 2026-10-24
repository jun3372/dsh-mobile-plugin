import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/models/server_profile.dart';
import '../../core/services/api_client.dart';
import '../../core/services/pairing.dart';
import 'servers_providers.dart';

enum PairingStatus { idle, checking, loggingIn, success, failed }

/// 绑定流程状态机：parse → GET info 验证 → POST login → 入库并设为当前。
class PairingState {
  final PairingStatus status;
  final String message;
  final Uri? origin;

  const PairingState({
    this.status = PairingStatus.idle,
    this.message = '',
    this.origin,
  });
}

final pairingControllerProvider =
    NotifierProvider<PairingController, PairingState>(PairingController.new);

class PairingController extends Notifier<PairingState> {
  @override
  PairingState build() => const PairingState();

  void reset() => state = const PairingState();

  /// 解析并绑定；返回是否成功。状态变化通过 [pairingControllerProvider] 观察。
  Future<bool> bind(String raw, {String? manualPassword}) async {
    final PairingPayload payload;
    try {
      payload = parsePairingPayload(raw);
    } on PairingException catch (e) {
      state = PairingState(
        status: PairingStatus.failed,
        message: e.userMessage,
      );
      return false;
    }
    state = PairingState(
      status: PairingStatus.checking,
      origin: payload.origin,
    );
    final client = ApiClient(
      origin: payload.origin,
      password: manualPassword ?? payload.token,
    );
    try {
      final info = await client.fetchInfo();
      if (!info.isDshMobile || info.instanceId.isEmpty) {
        state = const PairingState(
          status: PairingStatus.failed,
          message: '目标不是 DSH Mobile 网关',
        );
        return false;
      }
      state = PairingState(
        status: PairingStatus.loggingIn,
        origin: payload.origin,
      );
      await client.login();
      final now = DateTime.now();
      // 以 origin 为去重键：同一服务器的局域网/公网隧道入口并存为多条记录，
      // 重复扫同一二维码则原地更新。
      final servers = ref.read(serversProvider);
      final existing = servers
          .where((s) => s.origin == payload.origin)
          .firstOrNull;
      final hasExplicitPort =
          payload.origin.hasPort ||
          (payload.origin.scheme == 'https'
              ? payload.origin.port != 443
              : payload.origin.port != 80);
      await ref
          .read(serversProvider.notifier)
          .upsert(
            ServerProfile(
              id:
                  existing?.id ??
                  '${info.instanceId}@${payload.origin.host}:'
                      '${payload.origin.port}',
              name: hasExplicitPort
                  ? '${payload.origin.host}:${payload.origin.port}'
                  : payload.origin.host,
              origin: payload.origin,
              password: manualPassword ?? payload.token,
              mode: info.mode,
              addedAt: existing?.addedAt ?? now,
              lastUsedAt: now,
            ),
          );
      state = PairingState(
        status: PairingStatus.success,
        origin: payload.origin,
      );
      return true;
    } on AuthException catch (e) {
      state = PairingState(
        status: PairingStatus.failed,
        message: e.userMessage,
        origin: payload.origin,
      );
      return false;
    } on AppException catch (e) {
      state = PairingState(
        status: PairingStatus.failed,
        message: e.userMessage,
        origin: payload.origin,
      );
      return false;
    } finally {
      client.close();
    }
  }
}
