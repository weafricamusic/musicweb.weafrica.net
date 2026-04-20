"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.LiveRoomStateMachine = exports.LiveRoomMode = exports.LiveRoomStatus = void 0;
var LiveRoomStatus;
(function (LiveRoomStatus) {
    LiveRoomStatus["DRAFT"] = "DRAFT";
    LiveRoomStatus["SCHEDULED"] = "SCHEDULED";
    LiveRoomStatus["WAITING"] = "WAITING";
    LiveRoomStatus["READY"] = "READY";
    LiveRoomStatus["LIVE"] = "LIVE";
    LiveRoomStatus["ENDED"] = "ENDED";
    LiveRoomStatus["CANCELLED"] = "CANCELLED";
})(LiveRoomStatus || (exports.LiveRoomStatus = LiveRoomStatus = {}));
var LiveRoomMode;
(function (LiveRoomMode) {
    LiveRoomMode["SOLO"] = "SOLO";
    LiveRoomMode["BATTLE"] = "BATTLE";
})(LiveRoomMode || (exports.LiveRoomMode = LiveRoomMode = {}));
class LiveRoomStateMachine {
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
exports.LiveRoomStateMachine = LiveRoomStateMachine;
LiveRoomStateMachine.transitions = new Map([
    [LiveRoomStatus.DRAFT, [LiveRoomStatus.SCHEDULED, LiveRoomStatus.CANCELLED]],
    [LiveRoomStatus.SCHEDULED, [LiveRoomStatus.WAITING, LiveRoomStatus.CANCELLED]],
    [LiveRoomStatus.WAITING, [LiveRoomStatus.READY, LiveRoomStatus.CANCELLED]],
    [LiveRoomStatus.READY, [LiveRoomStatus.LIVE, LiveRoomStatus.CANCELLED]],
    [LiveRoomStatus.LIVE, [LiveRoomStatus.ENDED]],
    [LiveRoomStatus.ENDED, []],
    [LiveRoomStatus.CANCELLED, []],
]);
//# sourceMappingURL=live-room.state.js.map