// Pure Dart model - no backend visible

enum UserRole { host, opponent, audience }
enum SessionStatus { live, scheduled, ended }

class LiveSession {
  const LiveSession({
    required this.id,
    required this.title,
    required this.hostName,
    this.opponentName,
    required this.viewerCount,
    required this.giftCount,
    required this.status,
    this.scheduledAt,
    required this.channelId,
    required this.token,
    required this.userRole,
    this.liveType = 'normal',
    this.liveId,
  });

  final String id;
  final String title;
  final String hostName;
  final String? opponentName;
  final int viewerCount;
  final int giftCount;
  final SessionStatus status;
  final DateTime? scheduledAt;

  // Internal use only (never exposed to UI directly)
  final String channelId;
  final String token;
  final UserRole userRole;

  /// Live stream type.
  /// - normal: free, real-time live session
  /// - premium: future (subscriber/followers gated)
  /// - event: future (ticket gated)
  final String liveType;

  /// Database UUID from `public.live_sessions.id` (used by `live_messages`).
  ///
  /// This may be null for pre-live battle lobbies where `live_sessions` has
  /// not been mirrored yet.
  final String? liveId;

  String get displayStatus {
    switch (status) {
      case SessionStatus.live:
        return 'LIVE NOW';
      case SessionStatus.scheduled:
        return 'UPCOMING';
      case SessionStatus.ended:
        return 'ENDED';
    }
  }

  String get formattedTime {
    final at = scheduledAt;
    if (at == null) return '';
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
