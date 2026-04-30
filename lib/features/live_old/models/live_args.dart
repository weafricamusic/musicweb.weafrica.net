import 'package:weafrica_music/features/auth/user_role.dart';

/// Arguments for live streaming and battle navigation
class LiveArgs {
  // Core identifiers
  final String? liveId;
  final String? hostId;
  final String? hostName;
  final String? channelId;
  final String? battleId;
  final String? sessionId;
  
  // User info
  final String? userId;
  final String? userName;
  final UserRole? role;
  
  // Stream type
  final bool? isBattle;
  final bool? isHost;
  final String? title;
  
  // Battle specific
  final List<String>? battleArtists;
  final String? competitor1Id;
  final String? competitor2Id;
  final String? competitor1Name;
  final String? competitor2Name;
  final String? competitor1Type;
  final String? competitor2Type;
  final int? durationSeconds;
  
  // Agora credentials
  final String? agoraAppId;
  final String? agoraToken;
  final int? agoraUid;
  
  // Legacy token field
  final String? token;

  const LiveArgs({
    this.liveId,
    this.hostId,
    this.hostName,
    this.channelId,
    this.battleId,
    this.sessionId,
    this.userId,
    this.userName,
    this.role,
    this.isBattle,
    this.isHost,
    this.title,
    this.battleArtists,
    this.competitor1Id,
    this.competitor2Id,
    this.competitor1Name,
    this.competitor2Name,
    this.competitor1Type,
    this.competitor2Type,
    this.durationSeconds,
    this.agoraAppId,
    this.agoraToken,
    this.agoraUid,
    this.token,
  });
}