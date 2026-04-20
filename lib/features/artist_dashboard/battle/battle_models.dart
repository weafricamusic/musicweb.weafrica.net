import 'package:flutter/foundation.dart';

enum OsBattleStatus { live, pending, completed }
enum OsBattleResult { win, loss, none }

@immutable
class OsBattle {
  const OsBattle({
    required this.id,
    required this.opponentName,
    required this.opponentUsername,
    required this.status,
    required this.result,
    required this.yourVotes,
    required this.opponentVotes,
    required this.stakeCoins,
    required this.prizeCoins,
    required this.endsAt,
    required this.trackTitle,
  });

  final String id;
  final String opponentName;
  final String opponentUsername;
  final OsBattleStatus status;
  final OsBattleResult result;
  final int yourVotes;
  final int opponentVotes;
  final int stakeCoins;
  final int prizeCoins;
  final DateTime endsAt;
  final String trackTitle;

  Duration get timeLeft => endsAt.difference(DateTime.now());

  OsBattle copyWith({
    OsBattleStatus? status,
    OsBattleResult? result,
    int? yourVotes,
    int? opponentVotes,
    int? stakeCoins,
    int? prizeCoins,
    DateTime? endsAt,
    String? trackTitle,
  }) {
    return OsBattle(
      id: id,
      opponentName: opponentName,
      opponentUsername: opponentUsername,
      status: status ?? this.status,
      result: result ?? this.result,
      yourVotes: yourVotes ?? this.yourVotes,
      opponentVotes: opponentVotes ?? this.opponentVotes,
      stakeCoins: stakeCoins ?? this.stakeCoins,
      prizeCoins: prizeCoins ?? this.prizeCoins,
      endsAt: endsAt ?? this.endsAt,
      trackTitle: trackTitle ?? this.trackTitle,
    );
  }
}

@immutable
class TrackStubForBattle {
  const TrackStubForBattle({required this.id, required this.title, required this.artist});

  final String id;
  final String title;
  final String artist;
}

@immutable
class BattleDraft {
  const BattleDraft({
    required this.opponent,
    required this.track,
    required this.stakeCoins,
    required this.prizeCoins,
    required this.startNow,
  });

  final String opponent;
  final TrackStubForBattle? track;
  final int stakeCoins;
  final int prizeCoins;
  final bool startNow;

  BattleDraft copyWith({
    String? opponent,
    TrackStubForBattle? track,
    int? stakeCoins,
    int? prizeCoins,
    bool? startNow,
  }) {
    return BattleDraft(
      opponent: opponent ?? this.opponent,
      track: track ?? this.track,
      stakeCoins: stakeCoins ?? this.stakeCoins,
      prizeCoins: prizeCoins ?? this.prizeCoins,
      startNow: startNow ?? this.startNow,
    );
  }
}
