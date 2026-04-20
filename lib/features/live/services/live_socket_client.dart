import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../../app/config/api_env.dart';

@immutable
class LiveViewerCountEvent {
  const LiveViewerCountEvent({required this.streamId, required this.count});

  final String streamId;
  final int count;
}

/// Minimal Socket.IO client for the Nest `/live` namespace.
///
/// Server events:
/// - `viewer-count`: `{ streamId, count }`
/// - `new-challenge`: `{ challengeData | challenge | data }`
/// - `battle-starting`: `{ liveRoomId, streamSessionId? }`
class LiveSocketClient {
  LiveSocketClient({String? userId}) : _userId = (userId ?? '').trim();

  final String _userId;

  sio.Socket? _socket;
  String? _joinedStreamId;

  final StreamController<LiveViewerCountEvent> _viewerCountController =
      StreamController<LiveViewerCountEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _newChallengeController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _battleStartingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _newStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _streamEndedController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<LiveViewerCountEvent> get viewerCountStream => _viewerCountController.stream;
  Stream<Map<String, dynamic>> get newChallengeStream => _newChallengeController.stream;
  Stream<Map<String, dynamic>> get battleStartingStream => _battleStartingController.stream;
  Stream<Map<String, dynamic>> get newStreamStream => _newStreamController.stream;
  Stream<Map<String, dynamic>> get streamEndedStream => _streamEndedController.stream;

  bool get isConnected => _socket?.connected == true;

  String _socketOrigin() {
    final base = ApiEnv.baseUrl.trim();
    final uri = Uri.tryParse(base);
    if (uri == null) return base;
    // Ensure we connect to an origin (no path) so namespace `/live` is correct.
    return uri.origin;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  Future<void> connect() async {
    if (_socket != null) return;

    final origin = _socketOrigin();

    final socket = sio.io(
      '$origin/live',
      <String, dynamic>{
        'transports': <String>['websocket'],
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 10,
        'reconnectionDelay': 500,
        'timeout': 8000,
      },
    );

    _socket = socket;

    socket.on('connect', (_) {
      developer.log('socket connected', name: 'WEAFRICA.LiveSocket');
      final uid = _userId;
      if (uid.isNotEmpty) {
        socket.emit('identify', <String, dynamic>{'userId': uid});
      }

      final streamId = _joinedStreamId;
      if (streamId != null && streamId.trim().isNotEmpty) {
        socket.emit('join-stream', <String, dynamic>{'streamSessionId': streamId});
      }
    });

    socket.on('connect_error', (err) {
      developer.log('socket connect_error $err', name: 'WEAFRICA.LiveSocket');
    });

    socket.on('disconnect', (reason) {
      developer.log('socket disconnected $reason', name: 'WEAFRICA.LiveSocket');
    });

    socket.on('viewer-count', (data) {
      final m = _asMap(data);
      final streamId = (m['streamId'] ?? m['stream_id'] ?? '').toString().trim();
      if (streamId.isEmpty) return;
      final count = _asInt(m['count'] ?? m['viewerCount'] ?? m['viewer_count']);
      _viewerCountController.add(LiveViewerCountEvent(streamId: streamId, count: count));
    });

    socket.on('new-challenge', (data) {
      final m = _asMap(data);
      final payload = m['challengeData'] ?? m['challenge'] ?? m['data'] ?? m;
      _newChallengeController.add(_asMap(payload));
    });

    socket.on('battle-starting', (data) {
      _battleStartingController.add(_asMap(data));
    });

    socket.on('new-stream', (data) {
      _newStreamController.add(_asMap(data));
    });

    socket.on('stream-ended', (data) {
      _streamEndedController.add(_asMap(data));
    });

    socket.connect();
  }

  Future<void> identify(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    await connect();
    _socket?.emit('identify', <String, dynamic>{'userId': uid});
  }

  Future<void> joinStream(String streamSessionId) async {
    final sid = streamSessionId.trim();
    if (sid.isEmpty) return;

    _joinedStreamId = sid;
    await connect();
    _socket?.emit('join-stream', <String, dynamic>{'streamSessionId': sid});
  }

  Future<void> leaveStream() async {
    final sid = (_joinedStreamId ?? '').trim();
    _joinedStreamId = null;

    final socket = _socket;
    if (socket == null) return;

    if (sid.isNotEmpty) {
      socket.emit('leave-stream', <String, dynamic>{'streamSessionId': sid});
    }
  }

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;

    if (socket != null) {
      await leaveStream();

      socket.dispose();
    }
  }

  Future<void> dispose() async {
    await disconnect();

    await _viewerCountController.close();
    await _newChallengeController.close();
    await _battleStartingController.close();
    await _newStreamController.close();
    await _streamEndedController.close();
  }
}
