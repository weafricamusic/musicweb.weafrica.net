"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.OrchestratorModule = void 0;
const common_1 = require("@nestjs/common");
const battle_module_1 = require("../battle/battle.module");
const events_module_1 = require("../events/events.module");
const live_room_module_1 = require("../live-room/live-room.module");
const stream_module_1 = require("../stream/stream.module");
const wallet_module_1 = require("../wallet/wallet.module");
const distributed_lock_service_1 = require("./locks/distributed-lock.service");
const orchestrator_controller_1 = require("./orchestrator.controller");
const orchestrator_service_1 = require("./orchestrator.service");
let OrchestratorModule = class OrchestratorModule {
};
exports.OrchestratorModule = OrchestratorModule;
exports.OrchestratorModule = OrchestratorModule = __decorate([
    (0, common_1.Module)({
        imports: [events_module_1.EventsModule, live_room_module_1.LiveRoomModule, battle_module_1.BattleModule, stream_module_1.StreamModule, wallet_module_1.WalletModule],
        controllers: [orchestrator_controller_1.OrchestratorController],
        providers: [distributed_lock_service_1.DistributedLockService, orchestrator_service_1.OrchestratorService],
        exports: [orchestrator_service_1.OrchestratorService],
    })
], OrchestratorModule);
//# sourceMappingURL=orchestrator.module.js.map