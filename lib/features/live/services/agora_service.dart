import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:agora_rtm/agora_rtm.dart';

import '../../../app/config/app_env.dart';
import 'agora_token_api.dart';

class AgoraRtmChannelMessageEvent {
  const AgoraRtmChannelMessageEvent({
    required this.channelId,
    required this.message,
    required this.fromMember,
    required this.receivedAt,
  });

  final String channelId;
  final RtmMessage message;
  final RtmChannelMember fromMember;
  final DateTime receivedAt;
}

class AgoraService {
  // ⚔️ BATTLE REQUEST SYSTEM
Future<void> sendBattleRequest({
    required String hostId,
    required String fromUserId,
    required String channelId,
  }) async {
    final message = {
      "type": "battle_request",
      "from": fromUserId,
      "to": hostId,
      "channelId": channelId,
    };

    await sendChannelMessage(jsonEncode(message));
  }

Future<void> sendChannelMessage(String text) async {
  await sendRtmChannelMessage(text);
}

  AgoraService({AgoraTokenApi? tokenApi})
    : _tokenApi = tokenApi ?? const AgoraTokenApi();


  final AgoraTokenApi _tokenApi;

  AgoraRtmClient? _rtmClient;
  AgoraRtmChannel? _rtmChannel;
  String? _rtmUserId;
  String? _rtmChannelId;

  final StreamController<AgoraRtmChannelMessageEvent> _rtmChannelMessages =
      StreamController<AgoraRtmChannelMessageEvent>.broadcast();

  Stream<AgoraRtmChannelMessageEvent> get rtmChannelMessages =>
      _rtmChannelMessages.stream;

  bool get isRtmConnected => _rtmClient != null;
  String? get rtmUserId => _rtmUserId;
  String? get rtmChannelId => _rtmChannelId;

  Future<void> connectRtm({
    required String userId,
    required String idToken,
    int ttlSeconds = 3600,
  }) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      throw StateError('RTM userId is required.');
    }

    final appId = AppEnv.agoraAppId.trim();
    if (appId.isEmpty) {
      throw StateError('Missing Agora App ID (AppEnv.agoraAppId).');
    }

    if (_rtmClient != null && _rtmUserId == trimmedUserId) {
      return;
    }

    await disconnectRtm();

    final rtmToken = await _tokenApi.fetchRtmToken(
      idToken: idToken,
      ttlSeconds: ttlSeconds,
    );

    final client = await AgoraRtmClient.createInstance(appId);
    client.onError = (error) {
      developer.log('Agora RTM error', error: error);
    };
    client.onConnectionStateChanged2 = (state, reason) {
      developer.log(
        'Agora RTM connection state',
        error: {'state': state, 'reason': reason},
      );
    };
    client.onTokenExpired = () {
      developer.log('Agora RTM token expired');
    };
    client.onTokenPrivilegeWillExpire = () {
      developer.log('Agora RTM token privilege will expire');
    };

    await client.login(rtmToken, trimmedUserId);

    _rtmClient = client;
    _rtmUserId = trimmedUserId;
  }

  Future<void> joinRtmChannel({required String channelId}) async {
    final client = _rtmClient;
    if (client == null) {
      throw StateError('RTM client not connected. Call connectRtm() first.');
    }

    final trimmedChannelId = channelId.trim();
    if (trimmedChannelId.isEmpty) {
      throw StateError('RTM channelId is required.');
    }

    if (_rtmChannelId == trimmedChannelId && _rtmChannel != null) {
      return;
    }

    await _rtmChannel?.leave();
    await _rtmChannel?.release();

    final channel = await client.createChannel(trimmedChannelId);
    if (channel == null) {
      throw StateError('Failed to create RTM channel.');
    }

    channel.onError = (error) {
      developer.log('Agora RTM channel error', error: error);
    };

    channel.onMessageReceived = (message, fromMember) async {
      try {
        _rtmChannelMessages.add(
          AgoraRtmChannelMessageEvent(
            channelId: trimmedChannelId,
            message: message,
            fromMember: fromMember,
            receivedAt: DateTime.now(),
          ),
        );
      } catch (e) {
        developer.log("Invalid RTM message format", error: e);
      }
    };


    await channel.join();

    _rtmChannel = channel;
    _rtmChannelId = trimmedChannelId;
  }

  Future<void> sendRtmChannelMessage(String text) async {
    final client = _rtmClient;
    final channel = _rtmChannel;
    if (client == null || channel == null) {
      throw StateError('RTM channel not joined. Call joinRtmChannel() first.');
    }

    final t = text.trim();
    if (t.isEmpty) return;

    final message = client.createTextMessage(t);
    await channel.sendMessage2(message);
  }

  Future<void> renewRtmToken({
    required String idToken,
    int ttlSeconds = 3600,
  }) async {
    final client = _rtmClient;
    if (client == null) return;

    final token = await _tokenApi.fetchRtmToken(
      idToken: idToken,
      ttlSeconds: ttlSeconds,
    );

    await client.renewToken(token);
  }

  Future<void> disconnectRtm() async {
    Object? firstError;
    StackTrace? firstStack;

    Future<void> attempt(String label, Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e, st) {
        developer.log(
          'Agora RTM disconnect step failed: $label',
          error: e,
          stackTrace: st,
        );
        firstError ??= e;
        firstStack ??= st;
      }
    }

    await attempt('channel.leave', () async {
      final channel = _rtmChannel;
      if (channel == null) return;
      await channel.leave();
    });

    await attempt('channel.release', () async {
      final channel = _rtmChannel;
      if (channel == null) return;
      await channel.release();
    });

    _rtmChannel = null;
    _rtmChannelId = null;

    await attempt('client.logout', () async {
      final client = _rtmClient;
      if (client == null) return;
      await client.logout();
    });

    await attempt('client.release', () async {
      final client = _rtmClient;
      if (client == null) return;
      await client.release();
    });

    _rtmClient = null;
    _rtmUserId = null;

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.current);
    }
  }

  Future<void> dispose() async {
    try {
      await disconnectRtm();
    } finally {
      await _rtmChannelMessages.close();
    }
  }
}
