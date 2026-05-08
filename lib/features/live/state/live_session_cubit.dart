import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/enums/live_role.dart';
import '../core/enums/stream_status.dart';
import '../core/models/live_session_state.dart';
import '../core/models/live_user_model.dart';
import '../core/constants/live_constants.dart';
import '../engine/live_engine_interface.dart';
import '../data/repositories/live_session_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/viewer_repository.dart';
import '../data/repositories/battle_repository.dart';
import '../../../data/services/agora_token_service.dart';

/// Manages the full lifecycle of a live session: connect, stream, controls, end.
class LiveSessionCubit extends ValueNotifier<LiveSessionState> {
  final LiveEngineInterface engine;
  final LiveSessionRepository sessionRepo;
  final ChatRepository chatRepo;
  final ViewerRepository viewerRepo;
  final BattleRepository? battleRepo;
  final String userId;
  final String userName;

  Timer? _heartbeatTimer;
  StreamSubscription? _chatSub;

  LiveSessionCubit({
    required this.engine,
    required this.sessionRepo,
    required this.chatRepo,
    required this.viewerRepo,
    this.battleRepo,
    required this.userId,
    required this.userName,
  }) : super(const LiveSessionState());

  /// Start a solo broadcast.
  Future<void> startSoloLive({
    required String title,
    String? category,
  }) async {
    value = value.copyWith(status: StreamStatus.connecting);

    try {
      final channelName = 'solo_${userId}_${DateTime.now().millisecondsSinceEpoch}';
      final session = await sessionRepo.startSession(
        hostId: userId,
        hostName: userName,
        title: title,
        channelId: channelName,
        category: category,
      );

      await engine.initialize();

      // Fetch token BEFORE joining
      final token = await _fetchAgoraToken(
        channelName: channelName,
        role: LiveRole.broadcaster,
      );

      await engine.joinChannel(
        channelName: channelName,
        role: LiveRole.broadcaster,
        token: token,
      );

      engine.createLocalVideoOverlay();

      value = value.copyWith(
        status: StreamStatus.live,
        session: session,
        localUser: LiveUserModel(id: userId, name: userName, uid: 0, isHost: true),
      );

      _startHeartbeat(channelName);
      _subscribeChat(channelName);
    } catch (e) {
      value = value.copyWith(
        status: StreamStatus.error,
        errorMessage: 'Failed to start live: $e',
      );
    }
  }

  /// Join an existing live session as a viewer.
  Future<void> joinAsViewer({
    required String sessionId,
    required String channelName,
  }) async {
    value = value.copyWith(status: StreamStatus.connecting);

    try {
      await engine.initialize();

      // Fetch token BEFORE joining
      final token = await _fetchAgoraToken(
        channelName: channelName,
        role: LiveRole.audience,
      );

      await engine.joinChannel(
        channelName: channelName,
        role: LiveRole.audience,
        token: token,
      );

      // On web, watch for remote video arrival
      engine.remoteUid.addListener(() {
        if (engine.remoteUid.value != null) {
          engine.createRemoteVideoOverlay();
        }
      });

      await viewerRepo.joinLive(liveSessionId: sessionId, userId: userId);

      _subscribeChat(channelName);

      value = value.copyWith(status: StreamStatus.live);
    } catch (e) {
      value = value.copyWith(
        status: StreamStatus.error,
        errorMessage: 'Failed to join live: $e',
      );
    }
  }

  /// Fetch a short-lived Agora token from the backend.
  Future<String?> _fetchAgoraToken({
    required String channelName,
    required LiveRole role,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ LiveSessionCubit: User not logged in, token will be empty');
        return null;
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        debugPrint('⚠️ LiveSessionCubit: Firebase ID token is empty');
        return null;
      }

      final roleStr = role == LiveRole.broadcaster ? 'broadcaster' : 'audience';
      final token = await AgoraTokenService().fetchRtcToken(
        channelName: channelName,
        uid: 0, // Let Agora auto-assign UID
        role: roleStr,
        authToken: idToken,
      );

      debugPrint('🔑 LiveSessionCubit: Token fetched (${token.length} chars)');
      return token;
    } catch (e) {
      debugPrint('⚠️ LiveSessionCubit: Token fetch failed: $e');
      // Return null so the engine tries its own fallback
      return null;
    }
  }

  /// End the current live session.
  Future<void> endLive() async {
    _heartbeatTimer?.cancel();
    _chatSub?.cancel();

    engine.removeVideoOverlay();
    await engine.leaveChannel();

    if (value.session != null) {
      await sessionRepo.endSession(value.session!.id);
    }

    await viewerRepo.leaveLive();
    value = value.copyWith(status: StreamStatus.ended);
  }

  void toggleMute() {
    engine.toggleMute();
    value = value.copyWith(isMuted: !value.isMuted);
  }

  void toggleVideo() {
    engine.toggleVideo();
    value = value.copyWith(isVideoOff: !value.isVideoOff);
  }

  void switchCamera() {
    engine.switchCamera();
    value = value.copyWith(isFrontCamera: !value.isFrontCamera);
  }

  /// Send a chat message.
  Future<void> sendComment(String text) async {
    if (value.session == null) return;
    await chatRepo.sendMessage(
      channelId: value.session!.channelId,
      userId: userId,
      username: userName,
      text: text,
    );
  }

  // ─── Private ───────────────────────────────────────────

  void _startHeartbeat(String channelId) {
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: LiveConstants.heartbeatTimeoutSeconds),
      (_) => sessionRepo.heartbeat(channelId),
    );
  }

  void _subscribeChat(String channelId) {
    _chatSub = chatRepo.streamMessages(channelId).listen((messages) {
      value = value.copyWith(comments: messages);
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _chatSub?.cancel();
    engine.dispose();
    super.dispose();
  }
}
