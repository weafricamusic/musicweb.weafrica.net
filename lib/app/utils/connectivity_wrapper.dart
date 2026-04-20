import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityWrapper {
  static final ConnectivityWrapper _instance = ConnectivityWrapper._internal();
  factory ConnectivityWrapper() => _instance;
  ConnectivityWrapper._internal();

  final Connectivity _connectivity = Connectivity();
  final _statusController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _statusController.stream;

  bool _hasConnection = true;
  bool get hasConnectionSync => _hasConnection;

  static Future<bool> get hasConnection async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  void initialize() {
    _connectivity.onConnectivityChanged.listen((results) {
      _hasConnection = results.any((r) => r != ConnectivityResult.none);
      _statusController.add(_hasConnection);
    });
  }

  Future<void> dispose() async {
    await _statusController.close();
  }
}
