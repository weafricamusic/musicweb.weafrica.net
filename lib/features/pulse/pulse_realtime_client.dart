import 'dart:async';
import 'dart:developer' as developer;

import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../app/config/api_env.dart';

/// Socket.IO client for Pulse feed updates emitted by backend pg_notify routing.
class PulseRealtimeClient {
  sio.Socket? _socket;

  final StreamController<Map<String, dynamic>> _feedUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get feedUpdates => _feedUpdateController.stream;

  bool get isConnected => _socket?.connected == true;

  String _socketOrigin() {
    final base = ApiEnv.baseUrl.trim();
    final uri = Uri.tryParse(base);
    if (uri == null) return base;
    return uri.origin;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  Future<void> connect() async {
    if (_socket != null) return;

    final origin = _socketOrigin();
    final socket = sio.io(
      origin,
      <String, dynamic>{
        'transports': <String>['websocket'],
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 10,
        'reconnectionDelay': 600,
        'timeout': 8000,
      },
    );

    _socket = socket;

    socket.on('connect', (_) {
      developer.log('pulse socket connected', name: 'WEAFRICA.PulseSocket');
    });

    socket.on('connect_error', (err) {
      developer.log(
        'pulse socket connect_error $err',
        name: 'WEAFRICA.PulseSocket',
      );
    });

    socket.on('disconnect', (reason) {
      developer.log(
        'pulse socket disconnected $reason',
        name: 'WEAFRICA.PulseSocket',
      );
    });

    socket.on('weafrica:feed:update', (data) {
      _feedUpdateController.add(_asMap(data));
    });

    socket.connect();
  }

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    socket?.dispose();
  }

  Future<void> dispose() async {
    await disconnect();
    await _feedUpdateController.close();
  }
}