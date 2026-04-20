export enum BattleStatus {
  WAITING = 'WAITING',
  READY = 'READY',
  LIVE = 'LIVE',
  PAUSED = 'PAUSED',
  ENDED = 'ENDED',
  CANCELLED = 'CANCELLED',
}

export class BattleStateMachine {
  private static readonly transitions: Map<BattleStatus, BattleStatus[]> = new Map([
    [BattleStatus.WAITING, [BattleStatus.READY, BattleStatus.CANCELLED]],
    [BattleStatus.READY, [BattleStatus.LIVE, BattleStatus.CANCELLED]],
    [BattleStatus.LIVE, [BattleStatus.PAUSED, BattleStatus.ENDED]],
    [BattleStatus.PAUSED, [BattleStatus.LIVE, BattleStatus.ENDED]],
    [BattleStatus.ENDED, []],
    [BattleStatus.CANCELLED, []],
  ]);

  static canTransition(from: BattleStatus, to: BattleStatus): boolean {
    const allowed = this.transitions.get(from);
    return allowed ? allowed.includes(to) : false;
  }

  static validateTransition(from: BattleStatus, to: BattleStatus): void {
    if (!this.canTransition(from, to)) {
      throw new Error(`Invalid state transition: ${from} → ${to}`);
    }
  }
}
