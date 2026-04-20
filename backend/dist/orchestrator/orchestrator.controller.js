"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.OrchestratorController = void 0;
const common_1 = require("@nestjs/common");
const orchestrator_service_1 = require("./orchestrator.service");
let OrchestratorController = class OrchestratorController {
    constructor(orchestrator) {
        this.orchestrator = orchestrator;
    }
    async startSoloLive(body) {
        return this.orchestrator.startSoloLive(body);
    }
    async startBattleInvite(body) {
        return this.orchestrator.startBattleInvite(body);
    }
    async acceptBattleInvite(body) {
        return this.orchestrator.acceptBattleInvite(body);
    }
    async startStream(body) {
        return this.orchestrator.startStream(body);
    }
    async endStream(body) {
        return this.orchestrator.endStream(body);
    }
};
exports.OrchestratorController = OrchestratorController;
__decorate([
    (0, common_1.Post)('solo/start'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], OrchestratorController.prototype, "startSoloLive", null);
__decorate([
    (0, common_1.Post)('battle/invite'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], OrchestratorController.prototype, "startBattleInvite", null);
__decorate([
    (0, common_1.Post)('battle/accept'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], OrchestratorController.prototype, "acceptBattleInvite", null);
__decorate([
    (0, common_1.Post)('stream/start'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], OrchestratorController.prototype, "startStream", null);
__decorate([
    (0, common_1.Post)('stream/end'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], OrchestratorController.prototype, "endStream", null);
exports.OrchestratorController = OrchestratorController = __decorate([
    (0, common_1.Controller)('orchestrator'),
    __metadata("design:paramtypes", [orchestrator_service_1.OrchestratorService])
], OrchestratorController);
//# sourceMappingURL=orchestrator.controller.js.map