import 'package:weafrica_music/features/auth/user_role.dart';

class LiveArgs {
  final String? liveId;
  final String? hostId;
  final String? hostName;
  final UserRole? role;
  final List<String>? battleArtists;
  final bool? isBattle;
  final String? channelId;
  final String? battleId;

  const LiveArgs({
    this.liveId,
    this.hostId,
    this.hostName,
    this.role,
    this.battleArtists,
    this.isBattle,
    this.channelId,
    this.battleId,
  });
}
