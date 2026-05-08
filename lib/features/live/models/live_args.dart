import '../../auth/user_role.dart';

/// Arguments passed to live screens to configure the live session.
class LiveArgs {
  final String liveId;
  final String channelId;
  final UserRole role;
  final String hostId;
  final String hostName;
  final bool isBattle;
  final String? battleId;
  final List<String> battleArtists;

  LiveArgs({
    required this.liveId,
    required this.channelId,
    required this.role,
    required this.hostId,
    required this.hostName,
    this.isBattle = false,
    this.battleId,
    this.battleArtists = const [],
  });
}