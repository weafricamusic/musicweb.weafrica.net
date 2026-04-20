import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Retry an initialization operation with exponential backoff.
///
/// Delays: 1s, 2s, 4s … between attempts.
Future<bool> initializeWithRetry({
  required String operation,
  required int retryCount,
  required Future<void> Function() action,
  void Function(Object error, StackTrace stackTrace)? onAttemptFailure,
  VoidCallback? onAttemptSuccess,
}) async {
  for (int attempt = 1; attempt <= retryCount; attempt++) {
    try {
      await action();
      onAttemptSuccess?.call();
      developer.log(
        '$operation initialized (attempt $attempt)',
        name: 'WEAFRICA.Bootstrap',
      );
      return true;
    } catch (e, st) {
      onAttemptFailure?.call(e, st);

      if (attempt == retryCount) {
        developer.log(
          '$operation failed after $retryCount attempts',
          name: 'WEAFRICA.Bootstrap',
          error: e,
          stackTrace: st,
        );
        return false;
      }

      final waitTime = Duration(seconds: 1 << (attempt - 1));
      developer.log(
        '$operation attempt $attempt failed; retrying in ${waitTime.inSeconds}s',
        name: 'WEAFRICA.Bootstrap',
        error: e,
      );
      await Future.delayed(waitTime);
    }
  }

  return false;
}
