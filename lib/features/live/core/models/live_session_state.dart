import '../enums/live_mode.dart';
import '../enums/stream_status.dart';
import 'live_session_model.dart';
import 'live_user_model.dart';
import 'battle_request_model.dart';

/// Complete UI state for a live session screen.
class LiveSessionState {
  final StreamStatus status;
  final LiveMode mode;
  final LiveSessionModel? session;
  final LiveUserModel? localUser;
  final List<LiveUserModel> participants;
  final BattleRequestModel? pendingBattleRequest;
  final List<Map<String, dynamic>> comments;
  final int viewerCount;
  final bool isMuted;
  final bool isVideoOff;
  final bool isFrontCamera;
  final String? errorMessage;
  final bool showReconnecting;

  const LiveSessionState({
    this.status = StreamStatus.idle,
    this.mode = LiveMode.solo,
    this.session,
    this.localUser,
    this.participants = const [],
    this.pendingBattleRequest,
    this.comments = const [],
    this.viewerCount = 0,
    this.isMuted = false,
    this.isVideoOff = false,
    this.isFrontCamera = true,
    this.errorMessage,
    this.showReconnecting = false,
  });

  LiveSessionState copyWith({
    StreamStatus? status,
    LiveMode? mode,
    LiveSessionModel? session,
    LiveUserModel? localUser,
    List<LiveUserModel>? participants,
    BattleRequestModel? pendingBattleRequest,
    List<Map<String, dynamic>>? comments,
    int? viewerCount,
    bool? isMuted,
    bool? isVideoOff,
    bool? isFrontCamera,
    String? errorMessage,
    bool? showReconnecting,
    bool clearError = false,
  }) {
    return LiveSessionState(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      session: session ?? this.session,
      localUser: localUser ?? this.localUser,
      participants: participants ?? this.participants,
      pendingBattleRequest: pendingBattleRequest,
      comments: comments ?? this.comments,
      viewerCount: viewerCount ?? this.viewerCount,
      isMuted: isMuted ?? this.isMuted,
      isVideoOff: isVideoOff ?? this.isVideoOff,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      showReconnecting: showReconnecting ?? this.showReconnecting,
    );
  }
}