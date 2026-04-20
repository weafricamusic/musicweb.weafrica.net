"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BattleStateMachine = exports.BattleStatus = void 0;
var BattleStatus;
(function (BattleStatus) {
    BattleStatus["WAITING"] = "WAITING";
    BattleStatus["READY"] = "READY";
    BattleStatus["LIVE"] = "LIVE";
    BattleStatus["PAUSED"] = "PAUSED";
    BattleStatus["ENDED"] = "ENDED";
    BattleStatus["CANCELLED"] = "CANCELLED";
})(BattleStatus || (exports.BattleStatus = BattleStatus = {}));
class BattleStateMachine {
    static canTransition(from, to) {
        const allowed = this.transitions.get(from);
        return allowed ? allowed.includes(to) : false;
    }
    static validateTransition(from, to) {
        if (!this.canTransition(from, to)) {
            throw new Error(`Invalid state transition: ${from} → ${to}`);
        }
    }
}
exports.BattleStateMachine = BattleStateMachine;
BattleStateMachine.transitions = new Map([
    [BattleStatus.WAITING, [BattleStatus.READY, BattleStatus.CANCELLED]],
    [BattleStatus.READY, [BattleStatus.LIVE, BattleStatus.CANCELLED]],
    [BattleStatus.LIVE, [BattleStatus.PAUSED, BattleStatus.ENDED]],
    [BattleStatus.PAUSED, [BattleStatus.LIVE, BattleStatus.ENDED]],
    [BattleStatus.ENDED, []],
    [BattleStatus.CANCELLED, []],
]);
//# sourceMappingURL=battle.state.js.map