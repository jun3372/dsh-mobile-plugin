import 'dart:convert';

import 'mux_error.dart';

/// mux WebSocket 的服务端帧。
sealed class MuxServerFrame {
  final String streamId;

  const MuxServerFrame(this.streamId);
}

class MuxItemFrame extends MuxServerFrame {
  final Object? value;

  const MuxItemFrame(super.streamId, this.value);
}

class MuxEndFrame extends MuxServerFrame {
  const MuxEndFrame(super.streamId);
}

class MuxErrorFrame extends MuxServerFrame {
  final MuxError error;

  const MuxErrorFrame(super.streamId, this.error);
}

/// 解码一条服务端文本消息；未知/非法帧返回 null（客户端容忍并计数）。
MuxServerFrame? decodeMuxServerFrame(Object? raw) {
  final Object? decoded;
  if (raw is String) {
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
  } else {
    decoded = raw;
  }
  if (decoded is! Map) return null;
  final type = decoded['type'];
  final streamId = decoded['streamId'];
  if (type is! String || streamId is! String || streamId.isEmpty) return null;
  switch (type) {
    case 'item':
      if (!_hasOnlyKeys(decoded, const ['type', 'streamId'], const ['value'])) {
        return null;
      }
      return MuxItemFrame(streamId, decoded['value']);
    case 'end':
      if (!_hasOnlyKeys(decoded, const ['type', 'streamId'], const [])) {
        return null;
      }
      return MuxEndFrame(streamId);
    case 'error':
      if (!_hasOnlyKeys(decoded, const [
        'type',
        'streamId',
        'error',
      ], const [])) {
        return null;
      }
      final error = MuxError.fromValue(decoded['error']);
      if (error == null) return null;
      return MuxErrorFrame(streamId, error);
    default:
      return null;
  }
}

bool _hasOnlyKeys(Map value, List<String> required, List<String> optional) {
  for (final key in required) {
    if (!value.containsKey(key)) return false;
  }
  for (final key in value.keys) {
    if (!required.contains(key) && !optional.contains(key)) return false;
  }
  return true;
}

/// 打开一个逻辑流；payload 为 `{args: ...}`。
Map<String, Object?> encodeMuxOpen({
  required String streamId,
  required String endpoint,
  required Map<String, Object?> payload,
}) => {
  'type': 'open',
  'streamId': streamId,
  'endpoint': endpoint,
  'payload': payload,
};

Map<String, Object?> encodeMuxCancel(String streamId) => {
  'type': 'cancel',
  'streamId': streamId,
};
