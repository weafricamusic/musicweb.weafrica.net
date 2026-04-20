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
var OrchestratorService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.OrchestratorService = void 0;
const common_1 = require("@nestjs/common");
const event_bus_service_1 = require("../events/event-bus.service");
const event_types_1 = require("../events/types/event-types");
const battle_service_1 = require("../battle/battle.service");
const live_room_service_1 = require("../live-room/live-room.service");
const stream_service_1 = require("../stream/stream.service");
const wallet_service_1 = require("../wallet/wallet.service");
const distributed_lock_service_1 = require("./locks/distributed-lock.service");
const battle_state_1 = require("./state-machine/battle.state");
const live_room_state_1 = require("./state-machine/live-room.state");
let OrchestratorService = OrchestratorService_1 = class OrchestratorService {
    constructor(lockService, eventBus, liveRoomService, battleService, streamService, walletService) {
        this.lockService = lockService;
        this.eventBus = eventBus;
        this.liveRoomService = liveRoomService;
        this.battleService = battleService;
        this.streamService = streamService;
        this.walletService = walletService;
        this.logger = new common_1.Logger(OrchestratorService_1.name);
    }
    async startSoloLive(params) {
        const lockKey = `user:${params.userId}:stream`;
        return this.lockService.executeWithLock(lockKey, async () => {
            const activeRoom = await this.liveRoomService.findActiveByUser(params.userId);
            if (activeRoom) {
                throw new Error('You already have an active live stream');
            }
            const liveRoom = await this.liveRoomService.create({
                creatorId: params.userId,
                creatorType: params.userType,
                title: params.title,
                category: params.category,
                coverImage: params.coverImage,
                mode: live_room_state_1.LiveRoomMode.SOLO,
                status: live_room_state_1.LiveRoomStatus.SCHEDULED,
                privacy: params.privacy,
            });
            const streamSession = await this.streamService.create({
                liveRoomId: liveRoom.id,
                status: 'CREATED',
            });
            const token = await this.streamService.generateToken({
                channelId: streamSession.channelId,
                userId: params.userId,
                role: 'broadcaster',
            });
            live_room_state_1.LiveRoomStateMachine.validateTransition(liveRoom.status, live_room_state_1.LiveRoomStatus.READY);
            await this.liveRoomService.updateStatus(liveRoom.id, live_room_state_1.LiveRoomStatus.READY);
            await this.eventBus.emit(event_types_1.DomainEvent.STREAM_CREATED, {
                liveRoomId: liveRoom.id,
                creatorId: params.userId,
                title: params.title,
                streamSessionId: streamSession.id,
            });
            this.logger.log(`Solo live created: ${liveRoom.id} by ${params.userId}`);
            return { liveRoom, streamSession, token };
        });
    }
    async startBattleInvite(params) {
        const lockKey = `user:${params.userId}:battle`;
        return this.lockService.executeWithLock(lockKey, async () => {
            const activeBattle = await this.battleService.findActiveByUser(params.userId);
            if (activeBattle) {
                throw new Error('You already have an active battle');
            }
            const opponentActive = await this.battleService.findActiveByUser(params.opponentId);
            if (opponentActive) {
                throw new Error('Opponent is already in a battle');
            }
            const liveRoom = await this.liveRoomService.create({
                creatorId: params.userId,
                creatorType: params.userType,
                title: params.title,
                category: params.category,
                coverImage: params.coverImage,
                mode: live_room_state_1.LiveRoomMode.BATTLE,
                status: live_room_state_1.LiveRoomStatus.WAITING,
            });
            const battle = await this.battleService.create({
                liveRoomId: liveRoom.id,
                hostId: params.userId,
                durationSeconds: params.durationSeconds,
                coinGoal: params.coinGoal,
                beatName: params.beatName,
                status: battle_state_1.BattleStatus.WAITING,
                title: params.title,
                category: params.category,
            });
            const invite = await this.battleService.createInvite({
                battleId: battle.id,
                fromUserId: params.userId,
                toUserId: params.opponentId,
            });
            await this.eventBus.emit(event_types_1.DomainEvent.BATTLE_INVITE_SENT, {
                battleId: battle.id,
                liveRoomId: liveRoom.id,
                fromUserId: params.userId,
                toUserId: params.opponentId,
                title: params.title,
            });
            this.logger.log(`Battle invite sent: ${battle.id} from ${params.userId} to ${params.opponentId}`);
            return { liveRoom, battle, invite };
        });
    }
    async acceptBattleInvite(params) {
        const invite = await this.battleService.getInvite(params.inviteId);
        if (!invite) {
            throw new Error('Invite not found');
        }
        if (invite.toUserId !== params.userId) {
            throw new Error('Not authorized to accept this invite');
        }
        const lockKey = `battle:${invite.battleId}:accept`;
        return this.lockService.executeWithLock(lockKey, async () => {
            await this.battleService.updateInviteStatus(invite.id, 'ACCEPTED');
            const battle = await this.battleService.setOpponent(invite.battleId, params.userId);
            const liveRoom = await this.liveRoomService.updateStatus(battle.liveRoomId, live_room_state_1.LiveRoomStatus.READY);
            const streamSession = await this.streamService.create({
                liveRoomId: liveRoom.id,
                participants: [battle.hostId, battle.opponentId ?? params.userId],
                status: 'CREATED',
            });
            const hostToken = await this.streamService.generateToken({
                channelId: streamSession.channelId,
                userId: battle.hostId,
                role: 'broadcaster',
            });
            const opponentToken = await this.streamService.generateToken({
                channelId: streamSession.channelId,
                userId: battle.opponentId ?? params.userId,
                role: 'broadcaster',
            });
            await this.eventBus.emit(event_types_1.DomainEvent.BATTLE_ACCEPTED, {
                battleId: battle.id,
                liveRoomId: liveRoom.id,
                hostId: battle.hostId,
                opponentId: battle.opponentId,
                streamSessionId: streamSession.id,
                channelId: streamSession.channelId,
            });
            this.logger.log(`Battle accepted: ${battle.id} between ${battle.hostId} and ${battle.opponentId}`);
            return { liveRoom, battle, streamSession, tokens: { host: hostToken, opponent: opponentToken } };
        });
    }
    async startStream(params) {
        const lockKey = `stream:${params.liveRoomId}:start`;
        return this.lockService.executeWithLock(lockKey, async () => {
            const liveRoom = await this.liveRoomService.findById(params.liveRoomId);
            const battle = await this.battleService.findByLiveRoom(params.liveRoomId);
            // Validate permission.
            if (liveRoom.creatorId !== params.userId) {
                if (!battle || battle.opponentId !== params.userId) {
                    throw new Error('Not authorized to start this stream');
                }
            }
            const streamSession = await this.streamService.updateStatus(params.streamSessionId, 'ACTIVE');
            let nextLiveRoom = liveRoom;
            let started = false;
            if (liveRoom.status !== live_room_state_1.LiveRoomStatus.LIVE) {
                live_room_state_1.LiveRoomStateMachine.validateTransition(liveRoom.status, live_room_state_1.LiveRoomStatus.LIVE);
                nextLiveRoom = await this.liveRoomService.updateStatus(params.liveRoomId, live_room_state_1.LiveRoomStatus.LIVE);
                started = true;
            }
            if (battle) {
                if (battle.status !== battle_state_1.BattleStatus.LIVE) {
                    battle_state_1.BattleStateMachine.validateTransition(battle.status, battle_state_1.BattleStatus.LIVE);
                    await this.battleService.updateStatus(battle.id, battle_state_1.BattleStatus.LIVE);
                    await this.battleService.startScoringEngine(battle.id);
                    started = true;
                }
            }
            if (started) {
                await this.eventBus.emit(event_types_1.DomainEvent.STREAM_STARTED, {
                    liveRoomId: params.liveRoomId,
                    streamSessionId: streamSession.id,
                    channelId: streamSession.channelId,
                });
            }
            this.logger.log(`Stream started: ${params.liveRoomId}`);
            return { streamSession, liveRoom: nextLiveRoom.status === live_room_state_1.LiveRoomStatus.LIVE ? nextLiveRoom : await this.liveRoomService.findById(params.liveRoomId) };
        });
    }
    async endStream(params) {
        const lockKey = `stream:${params.liveRoomId}:end`;
        return this.lockService.executeWithLock(lockKey, async () => {
            const liveRoom = await this.liveRoomService.findById(params.liveRoomId);
            if (liveRoom.creatorId !== params.userId) {
                throw new Error('Only the host can end the stream');
            }
            await this.streamService.updateStatusByLiveRoom(params.liveRoomId, 'CLOSED');
            let nextLiveRoom = liveRoom;
            if (liveRoom.status !== live_room_state_1.LiveRoomStatus.ENDED) {
                live_room_state_1.LiveRoomStateMachine.validateTransition(liveRoom.status, live_room_state_1.LiveRoomStatus.ENDED);
                nextLiveRoom = await this.liveRoomService.updateStatus(params.liveRoomId, live_room_state_1.LiveRoomStatus.ENDED);
            }
            const battle = await this.battleService.findByLiveRoom(params.liveRoomId);
            let nextBattle = battle;
            if (battle && battle.status === battle_state_1.BattleStatus.LIVE) {
                const finalizedBattle = await this.battleService.finalizeBattle(battle.id);
                await this.walletService.recordBattlePayouts(finalizedBattle);
                nextBattle = await this.battleService.updateStatus(battle.id, battle_state_1.BattleStatus.ENDED);
                await this.eventBus.emit(event_types_1.DomainEvent.BATTLE_ENDED, {
                    battleId: battle.id,
                    winnerId: finalizedBattle.winner_uid,
                    winnerPayout: finalizedBattle.winner_payout_coins,
                    hostScore: finalizedBattle.host_a_score,
                    opponentScore: finalizedBattle.host_b_score,
                    hostId: battle.hostId,
                    opponentId: battle.opponentId,
                });
            }
            await this.eventBus.emit(event_types_1.DomainEvent.STREAM_ENDED, { liveRoomId: params.liveRoomId });
            this.logger.log(`Stream ended: ${params.liveRoomId}`);
            return {
                liveRoom: nextLiveRoom.status === live_room_state_1.LiveRoomStatus.ENDED
                    ? nextLiveRoom
                    : await this.liveRoomService.findById(params.liveRoomId),
                battle: nextBattle,
            };
        });
    }
};
exports.OrchestratorService = OrchestratorService;
exports.OrchestratorService = OrchestratorService = OrchestratorService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [distributed_lock_service_1.DistributedLockService,
        event_bus_service_1.EventBusService,
        live_room_service_1.LiveRoomService,
        battle_service_1.BattleService,
        stream_service_1.StreamService,
        wallet_service_1.WalletService])
], OrchestratorService);
//# sourceMappingURL=orchestrator.service.js.map