import 'dart:async';

import 'mux_error.dart';

enum MuxSubscriptionPhase { idle, opening, open, waiting, ended, failed }

/// 单条逻辑流的事件。
sealed class MuxStreamEvent {
  const MuxStreamEvent();
}

/// 每次（重新）打开都会先发一条；上层据此丢弃旧基线并等待新基线。
class MuxStreamOpened extends MuxStreamEvent {
  final String streamId;
  final bool restarted;

  const MuxStreamOpened(this.streamId, {required this.restarted});
}

class MuxStreamItem extends MuxStreamEvent {
  final Object? value;

  const MuxStreamItem(this.value);
}

class MuxStreamEnded extends MuxStreamEvent {
  const MuxStreamEnded();
}

class MuxStreamFailure extends MuxStreamEvent {
  final MuxError error;

  const MuxStreamFailure(this.error);
}

/// 物理连接丢失；逻辑流会等待重连后自动重开。
class MuxStreamCarrierLost extends MuxStreamEvent {
  const MuxStreamCarrierLost();
}

/// 一条可重开的逻辑流。streamId 永不复用。
class MuxSubscription {
  final String endpoint;
  final Map<String, Object?> args;
  final bool autoReopen;

  final void Function(MuxSubscription subscription) _onCancel;
  final void Function(MuxSubscription subscription) _onRestart;

  /// 事件必须异步派发：订阅者常在事件回调里同步 restart/dispose，
  /// 同步广播会重入控制器（Cannot fire new event）；异步也保证
  /// openStream 后紧接的 listen 能收到 bind 产生的 Opened。
  final StreamController<MuxStreamEvent> _events =
      StreamController<MuxStreamEvent>.broadcast();

  String? _streamId;
  MuxSubscriptionPhase phase = MuxSubscriptionPhase.idle;
  bool _disposed = false;
  bool _openedOnce = false;

  MuxSubscription({
    required this.endpoint,
    required this.args,
    required this.autoReopen,
    required void Function(MuxSubscription) onCancel,
    required void Function(MuxSubscription) onRestart,
  }) : _onCancel = onCancel,
       _onRestart = onRestart;

  Stream<MuxStreamEvent> get events => _events.stream;

  String? get streamId => _streamId;

  bool get isOpen =>
      !_disposed && phase == MuxSubscriptionPhase.open && _streamId != null;

  bool get isDisposed => _disposed;

  /// 强制重开（assistant 流折叠违约 / 需要新基线时）。
  void restart() {
    if (_disposed) return;
    _onRestart(this);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    phase = MuxSubscriptionPhase.ended;
    _onCancel(this);
    _streamId = null;
    _events.close();
  }

  void bind(String streamId) {
    if (_disposed) return;
    _streamId = streamId;
    phase = MuxSubscriptionPhase.open;
    final restarted = _openedOnce;
    _openedOnce = true;
    _events.add(MuxStreamOpened(streamId, restarted: restarted));
  }

  void markWaiting() {
    if (_disposed) return;
    _streamId = null;
    phase = MuxSubscriptionPhase.waiting;
    _events.add(const MuxStreamCarrierLost());
  }

  /// 主动重开前作废旧 streamId（不发 CarrierLost）。
  void prepareRestart() {
    if (_disposed) return;
    _streamId = null;
    phase = MuxSubscriptionPhase.waiting;
  }

  void deliverItem(Object? value) {
    if (_disposed) return;
    _events.add(MuxStreamItem(value));
  }

  void deliverEnd() {
    if (_disposed) return;
    phase = MuxSubscriptionPhase.ended;
    _streamId = null;
    _events.add(const MuxStreamEnded());
  }

  void deliverFailure(MuxError error) {
    if (_disposed) return;
    phase = MuxSubscriptionPhase.failed;
    _streamId = null;
    _events.add(MuxStreamFailure(error));
  }
}
