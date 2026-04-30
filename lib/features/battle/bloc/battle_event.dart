part of 'battle_bloc.dart';

abstract class BattleEvent extends Equatable {
  const BattleEvent();
  @override
  List<Object?> get props => [];
}

class StartSoloLive extends BattleEvent {
  final String hostName;
  final int viewers;
  const StartSoloLive(this.hostName, this.viewers);
}

class RequestBattle extends BattleEvent {
  final String opponentName;
  final int opponentViewers;
  const RequestBattle(this.opponentName, this.opponentViewers);
}

class AcceptBattle extends BattleEvent {
  final String artistAName;
  final String artistBName;
  const AcceptBattle(this.artistAName, this.artistBName);
}

class DeclineBattle extends BattleEvent {
  const DeclineBattle();
}

class StartBattle extends BattleEvent {
  const StartBattle();
}

class UpdateScore extends BattleEvent {
  final int artistAScore;
  final int artistBScore;
  final Duration timeRemaining;
  const UpdateScore(this.artistAScore, this.artistBScore, this.timeRemaining);
}

class EndBattle extends BattleEvent {
  final String? winnerName;
  const EndBattle(this.winnerName);
}

class SwitchVideoFocus extends BattleEvent {
  const SwitchVideoFocus();
}