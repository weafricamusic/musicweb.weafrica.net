import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static ConnectivityService? _instance;
  static ConnectivityService get instance => _instance ??= ConnectivityService._();

  ConnectivityService._() {
    _connectivity = Connectivity();
    _init();
  }

  late final Connectivity _connectivity;
  StreamSubscription<dynamic>? _subscription;
  bool _isOnline = true;

  /// Synchronous snapshot: true if last known connected.
  bool get isOnlineSync => _isOnline;

  /// Stream of online/offline changes.
  Stream<bool> get isOnlineStream => _controller.stream;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  Future<bool> isOnline() async {
    final dynamic raw = await _connectivity.checkConnectivity();
    ConnectivityResult result;
    if (raw is ConnectivityResult) {
      result = raw;
    } else if (raw is Iterable && raw.isNotEmpty && raw.first is ConnectivityResult) {
      result = raw.first as ConnectivityResult;
    } else {
      result = ConnectivityResult.none;
    }
    final online = _isConnected(result);
    _isOnline = online;
    _controller.add(online);
    return online;
  }

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen((dynamic results) {
      ConnectivityResult result;
      if (results is ConnectivityResult) {
        result = results;
      } else if (results is Iterable && results.isNotEmpty && results.first is ConnectivityResult) {
        result = results.first as ConnectivityResult;
      } else {
        result = ConnectivityResult.none;
      }
      final online = _parseConnectivityResultToOnline(results);
      if (_isOnline != online) {
        _isOnline = online;
        _controller.add(online);
        if (kDebugMode) {
          final desc = _describeConnectivityResult(result);
          debugPrint('🌐 Connectivity: ${online ? 'ONLINE' : 'OFFLINE'} ($desc)');
        }
      }
    });
  }

  bool _parseConnectivityResultToOnline(dynamic result) {
    if (result is ConnectivityResult) return _isConnected(result);
    if (result is Iterable) {
      for (final r in result) {
        if (r is ConnectivityResult && _isConnected(r)) return true;
        // Some environments may emit strings or maps; defensively handle common string names.
        if (r is String) {
          final lower = r.toLowerCase();
          if (lower.contains('wifi') || lower.contains('mobile') || lower.contains('ethernet')) return true;
        }
      }
      return false;
    }
    return false;
  }

  String _describeConnectivityResult(dynamic result) {
    if (result is ConnectivityResult) return result.name;
    if (result is Iterable) return result.map((e) => e?.toString() ?? 'null').join(',');
    return result?.toString() ?? 'unknown';
  }

  bool _isConnected(ConnectivityResult result) {
    return switch (result) {
      ConnectivityResult.wifi || ConnectivityResult.mobile || ConnectivityResult.ethernet => true,
      _ => false,
    };
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
