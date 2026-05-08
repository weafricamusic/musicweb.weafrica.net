/// General live-streaming constants.
class LiveConstants {
  /// Max duration of a heartbeat interval before a session is considered stale.
  static const int heartbeatTimeoutSeconds = 90;

  /// Max duration (seconds) for a battle round.
  static const int battleRoundDuration = 120;

  /// Max number of comments shown in the overlay.
  static const int maxCommentsDisplayed = 50;

  /// Channel name prefix for solo streams.
  static const String soloChannelPrefix = 'solo_';

  /// Channel name prefix for battle streams.
  static const String battleChannelPrefix = 'battle_';
}