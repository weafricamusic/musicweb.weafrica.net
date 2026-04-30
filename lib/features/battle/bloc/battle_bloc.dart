import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

part 'battle_event.dart';
part 'battle_state.dart';

class BattleBloc extends Bloc<BattleEvent, BattleState> {
  BattleBloc() : super(BattleInitial()) {
    on<StartSoloLive>(_onStartSolo);
    on<RequestBattle>(_onRequestBattle);
    on<AcceptBattle>(_onAcceptBattle);
    on<DeclineBattle>(_onDeclineBattle);
    on<StartBattle>(_onStartBattle);
    on<UpdateScore>(_onUpdateScore);
    on<EndBattle>(_onEndBattle);
    on<SwitchVideoFocus>(_onSwitchFocus);
  }

  void _onStartSolo(StartSoloLive event, Emitter<BattleState> emit) {
    emit(SoloLiveState(
      hostName: event.hostName,
      viewers: event.viewers,
      comments: const [],
    ));
  }

  void _onRequestBattle(RequestBattle event, Emitter<BattleState> emit) {
    if (state is SoloLiveState) {
      final current = state as SoloLiveState;
      emit(BattleRequestSent(
        opponentName: event.opponentName,
        opponentViewers: event.opponentViewers,
        previousState: current,
      ));
    }
  }

  void _onAcceptBattle(AcceptBattle event, Emitter<BattleState> emit) {
    emit(BattleActive(
      artistAName: event.artistAName,
      artistBName: event.artistBName,
      artistAScore: 0,
      artistBScore: 0,
      timeRemaining: const Duration(minutes: 20),
      isArtistAFullScreen: true,
      comments: const [],
    ));
  }

  void _onDeclineBattle(DeclineBattle event, Emitter<BattleState> emit) {
    if (state is BattleRequestSent) {
      final previous = (state as BattleRequestSent).previousState;
      emit(previous);
    }
  }

  void _onStartBattle(StartBattle event, Emitter<BattleState> emit) {
    // Handled by Agora channel migration
  }

  void _onUpdateScore(UpdateScore event, Emitter<BattleState> emit) {
    if (state is BattleActive) {
      final current = state as BattleActive;
      emit(current.copyWith(
        artistAScore: event.artistAScore,
        artistBScore: event.artistBScore,
        timeRemaining: event.timeRemaining,
      ));
    }
  }

  void _onEndBattle(EndBattle event, Emitter<BattleState> emit) {
    if (state is BattleActive) {
      final current = state as BattleActive;
      emit(BattleEnded(
        winnerName: event.winnerName,
        artistAScore: current.artistAScore,
        artistBScore: current.artistBScore,
        artistAName: current.artistAName,
        artistBName: current.artistBName,
        duration: const Duration(minutes: 20) - current.timeRemaining,
      ));
    }
  }

  void _onSwitchFocus(SwitchVideoFocus event, Emitter<BattleState> emit) {
    if (state is BattleActive) {
      final current = state as BattleActive;
      emit(current.copyWith(isArtistAFullScreen: !current.isArtistAFullScreen));
    }
  }
}