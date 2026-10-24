import 'dart:math';

/// 指数退避：500ms 起、×2、10s 封顶、±20% 抖动。
class ReconnectPolicy {
  final Duration initial;
  final Duration maximum;
  final double factor;
  final double jitter;

  const ReconnectPolicy({
    this.initial = const Duration(milliseconds: 500),
    this.maximum = const Duration(seconds: 10),
    this.factor = 2,
    this.jitter = 0.2,
  });

  /// [attempt] 从 1 开始。
  Duration delayFor(int attempt, {Random? random}) {
    var millis = initial.inMilliseconds.toDouble();
    for (var i = 1; i < attempt && millis < maximum.inMilliseconds; i++) {
      millis *= factor;
    }
    if (millis > maximum.inMilliseconds) {
      millis = maximum.inMilliseconds.toDouble();
    }
    if (jitter > 0) {
      final rng = random ?? Random();
      final ratio = 1 + (rng.nextDouble() * 2 - 1) * jitter;
      millis *= ratio;
    }
    final rounded = millis.round();
    return Duration(milliseconds: rounded < 0 ? 0 : rounded);
  }
}
