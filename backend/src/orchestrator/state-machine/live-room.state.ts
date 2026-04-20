export enum LiveRoomStatus {
  DRAFT = 'DRAFT',
  SCHEDULED = 'SCHEDULED',
  WAITING = 'WAITING',
  READY = 'READY',
  LIVE = 'LIVE',
  ENDED = 'ENDED',
  CANCELLED = 'CANCELLED',
}

export enum LiveRoomMode {
  SOLO = 'SOLO',
  BATTLE = 'BATTLE',
}

export class LiveRoomStateMachine {
  private static readonly transitions: Map<LiveRoomStatus, LiveRoomStatus[]> = new Map([
    [LiveRoomStatus.DRAFT, [LiveRoomStatus.SCHEDULED, LiveRoomStatus.CANCELLED]],
    [LiveRoomStatus.SCHEDULED, [LiveRoomStatus.WAITING, LiveRoomStatus.CANCELLED]],
    [LiveRoomStatus.WAITING, [LiveRoomStatus.READY, LiveRoomStatus.CANCELLED]],
    [LiveRoomStatus.READY, [LiveRoomStatus.LIVE, LiveRoomStatus.CANCELLED]],
    [LiveRoomStatus.LIVE, [LiveRoomStatus.ENDED]],
    [LiveRoomStatus.ENDED, []],
    [LiveRoomStatus.CANCELLED, []],
  ]);

  static canTransition(from: LiveRoomStatus, to: LiveRoomStatus): boolean {
    const allowed = this.transitions.get(from);
    return allowed ? allowed.includes(to) : false;
  }

  static validateTransition(from: LiveRoomStatus, to: LiveRoomStatus): void {
    if (!this.canTransition(from, to)) {
      throw new Error(`Invalid state transition: ${from} → ${to}`);
    }
  }
}
