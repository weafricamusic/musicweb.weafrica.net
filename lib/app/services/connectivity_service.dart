import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<dynamic>? _sub;

  final StreamController<bool> _statusController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _statusController.stream;

  Future<bool> get hasConnection async {
    try {
      final dynamic result = await _connectivity.checkConnectivity();
      if (result is ConnectivityResult) {
        return result != ConnectivityResult.none;
      }
      if (result is List<ConnectivityResult>) {
        return result.isNotEmpty && result.any((r) => r != ConnectivityResult.none);
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  void startMonitoring() {
    _sub ??= _connectivity.onConnectivityChanged.listen((dynamic result) {
      bool connected = true;

      if (result is ConnectivityResult) {
        connected = result != ConnectivityResult.none;
      } else if (result is List<ConnectivityResult>) {
        connected = result.isNotEmpty && result.any((r) => r != ConnectivityResult.none);
      }

      _statusController.add(connected);
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _statusController.close();
  }
}
