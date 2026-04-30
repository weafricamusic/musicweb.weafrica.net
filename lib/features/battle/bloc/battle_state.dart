part of 'battle_bloc.dart';

abstract class BattleState extends Equatable {
  const BattleState();
  @override
  List<Object?> get props => [];
}

class BattleInitial extends BattleState {}

class SoloLiveState extends BattleState {
  final String hostName;
  final int viewers;
  final List<String> comments;
  const SoloLiveState({
    required this.hostName,
    required this.viewers,
    required this.comments,
  });
}

class BattleRequestSent extends BattleState {
  final String opponentName;
  final int opponentViewers;
  final SoloLiveState previousState;
  const BattleRequestSent({
    required this.opponentName,
    required this.opponentViewers,
    required this.previousState,
  });
}

class BattleActive extends BattleState {
  final String artistAName;
  final String artistBName;
  final int artistAScore;
  final int artistBScore;
  final Duration timeRemaining;
  final bool isArtistAFullScreen;
  final List<String> comments;

  const BattleActive({
    required this.artistAName,
    required this.artistBName,
    required this.artistAScore,
    required this.artistBScore,
    required this.timeRemaining,
    required this.isArtistAFullScreen,
    required this.comments,
  });

  BattleActive copyWith({
    String? artistAName,
    String? artistBName,
    int? artistAScore,
    int? artistBScore,
    Duration? timeRemaining,
    bool? isArtistAFullScreen,
    List<String>? comments,
  }) {
    return BattleActive(
      artistAName: artistAName ?? this.artistAName,
      artistBName: artistBName ?? this.artistBName,
      artistAScore: artistAScore ?? this.artistAScore,
      artistBScore: artistBScore ?? this.artistBScore,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      isArtistAFullScreen: isArtistAFullScreen ?? this.isArtistAFullScreen,
      comments: comments ?? this.comments,
    );
  }

  @override
  List<Object?> get props => [
        artistAName, artistBName, artistAScore, artistBScore,
        timeRemaining, isArtistAFullScreen, comments
      ];
}

class BattleEnded extends BattleState {
  final String? winnerName;
  final String artistAName;
  final String artistBName;
  final int artistAScore;
  final int artistBScore;
  final Duration duration;
  const BattleEnded({
    this.winnerName,
    required this.artistAName,
    required this.artistBName,
    required this.artistAScore,
    required this.artistBScore,
    required this.duration,
  });
}