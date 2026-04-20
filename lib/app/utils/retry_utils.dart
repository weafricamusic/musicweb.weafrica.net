import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

class RetryUtils {
  static Future<T> withRetry<T>({
    required String operation,
    required Future<T> Function() action,
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    bool Function(Object error)? shouldRetry,
    void Function(int attempt, Duration delay)? onRetry,
  }) async {
    var attempt = 0;

    while (true) {
      attempt++;

      try {
        return await action();
      } catch (error, stackTrace) {
        final canRetry = attempt < maxRetries && (shouldRetry?.call(error) ?? _isRetryable(error));

        if (!canRetry) {
          developer.log(
            '$operation failed after $attempt attempts',
            name: 'WEAFRICA.Retry',
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }

        final multiplier = pow(2, attempt - 1).toDouble();
        final baseMs = (initialDelay.inMilliseconds * multiplier).round();
        final jitterMs = Random().nextInt(500);
        final delay = Duration(milliseconds: baseMs + jitterMs);

        developer.log(
          '$operation failed (attempt $attempt/$maxRetries), retrying in ${delay.inMilliseconds}ms',
          name: 'WEAFRICA.Retry',
          error: error,
        );

        onRetry?.call(attempt, delay);
        await Future.delayed(delay);
      }
    }
  }

  static bool _isRetryable(Object error) {
    if (error is TimeoutException) return true;

    final msg = error.toString().toLowerCase();
    if (msg.contains('timeout')) return true;
    if (msg.contains('socket')) return true;
    if (msg.contains('connection')) return true;
    if (msg.contains('network')) return true;

    return false;
  }
}
