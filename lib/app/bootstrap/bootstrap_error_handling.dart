import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

void configureBootstrapErrorHandling() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'FlutterError: ${details.exceptionAsString()}',
      name: 'WEAFRICA.Bootstrap',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Uncaught PlatformDispatcher error',
      name: 'WEAFRICA.Bootstrap',
      error: error,
      stackTrace: stack,
    );
    return true;
  };
}
