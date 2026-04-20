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
var LiveGateway_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.LiveGateway = void 0;
const websockets_1 = require("@nestjs/websockets");
const common_1 = require("@nestjs/common");
const socket_io_1 = require("socket.io");
const stream_service_1 = require("../stream/stream.service");
const challenge_service_1 = require("../challenge/challenge.service");
let LiveGateway = LiveGateway_1 = class LiveGateway {
    constructor(streamService, 
    // Keeping ChallengeService injected for future challenge events.
    challengeService) {
        this.streamService = streamService;
        this.challengeService = challengeService;
        this.logger = new common_1.Logger(LiveGateway_1.name);
        this.viewers = new Map(); // streamSessionId -> socketIds
        this.socketToStream = new Map(); // socketId -> streamSessionId
        this.socketToUser = new Map(); // socketId -> userId
    }
    handleConnection(client) {
        this.logger.log(`Client connected: ${client.id}`);
    }
    handleDisconnect(client) {
        this.logger.log(`Client disconnected: ${client.id}`);
        const streamId = this.socketToStream.get(client.id);
        if (streamId) {
            this.socketToStream.delete(client.id);
            const set = this.viewers.get(streamId);
            if (set) {
                set.delete(client.id);
                if (set.size === 0) {
                    this.viewers.delete(streamId);
                }
            }
            void this.updateViewerCount(streamId);
        }
        this.socketToUser.delete(client.id);
    }
    handleIdentify(client, data) {
        const userId = String(data?.userId ?? '').trim();
        if (!userId)
            return { success: false };
        this.socketToUser.set(client.id, userId);
        client.join(`user:${userId}`);
        return { success: true };
    }
    async handleJoinStream(client, data) {
        const streamId = String(data?.streamId ?? '').trim();
        const userId = String(data?.userId ?? '').trim();
        if (!streamId) {
            return { success: false, error: 'Missing streamId' };
        }
        if (!this.viewers.has(streamId)) {
            this.viewers.set(streamId, new Set());
        }
        // If the socket was previously watching another stream, clean it up first.
        const previousStreamId = this.socketToStream.get(client.id);
        if (previousStreamId && previousStreamId !== streamId) {
            const prevSet = this.viewers.get(previousStreamId);
            if (prevSet) {
                prevSet.delete(client.id);
                if (prevSet.size === 0) {
                    this.viewers.delete(previousStreamId);
                }
            }
            client.leave(`stream:${previousStreamId}`);
            void this.updateViewerCount(previousStreamId);
        }
        this.viewers.get(streamId).add(client.id);
        this.socketToStream.set(client.id, streamId);
        if (userId) {
            this.socketToUser.set(client.id, userId);
            client.join(`user:${userId}`);
        }
        client.join(`stream:${streamId}`);
        await this.updateViewerCount(streamId);
        const viewerCount = this.viewers.get(streamId).size;
        this.server.to(`stream:${streamId}`).emit('viewer-count', {
            streamId,
            count: viewerCount,
        });
        if (userId) {
            this.server.to(`stream:${streamId}`).emit('user-joined', { userId });
        }
        return { success: true, viewerCount };
    }
    async handleLeaveStream(client, data) {
        const streamId = String(data?.streamId ?? '').trim();
        if (!streamId)
            return { success: false, error: 'Missing streamId' };
        const set = this.viewers.get(streamId);
        if (set) {
            set.delete(client.id);
            if (set.size === 0) {
                this.viewers.delete(streamId);
            }
        }
        this.socketToStream.delete(client.id);
        client.leave(`stream:${streamId}`);
        await this.updateViewerCount(streamId);
        const viewerCount = this.viewers.get(streamId)?.size ?? 0;
        this.server.to(`stream:${streamId}`).emit('viewer-count', {
            streamId,
            count: viewerCount,
        });
        return { success: true };
    }
    handleStreamStarted(_client, data) {
        const streamId = String(data?.streamId ?? '').trim();
        const userId = String(data?.userId ?? '').trim();
        if (!streamId)
            return;
        this.server.emit('new-stream', {
            streamId,
            userId: userId || null,
            streamData: data?.streamData ?? null,
            timestamp: new Date().toISOString(),
        });
        this.logger.log(`New stream started: ${streamId}${userId ? ` by user ${userId}` : ''}`);
    }
    handleStreamEnded(_client, data) {
        const streamId = String(data?.streamId ?? '').trim();
        const userId = String(data?.userId ?? '').trim();
        if (!streamId)
            return;
        this.viewers.delete(streamId);
        this.server.emit('stream-ended', {
            streamId,
            userId: userId || null,
            timestamp: new Date().toISOString(),
        });
        this.logger.log(`Stream ended: ${streamId}`);
    }
    handleChallengeSent(_client, data) {
        const targetUserId = String(data?.targetUserId ?? '').trim();
        const challengeId = String(data?.challengeId ?? '').trim();
        if (!targetUserId || !challengeId)
            return;
        this.server.to(`user:${targetUserId}`).emit('new-challenge', {
            challengeId,
            challengeData: data?.challengeData ?? null,
        });
    }
    handleChallengeAccepted(_client, data) {
        const challengeId = String(data?.challengeId ?? '').trim();
        const streamId = String(data?.streamId ?? '').trim();
        if (!challengeId || !streamId)
            return;
        this.server.emit('battle-starting', {
            challengeId,
            streamId,
        });
    }
    // Server-side helpers (safe to call from controllers/services)
    emitStreamStarted(payload) {
        this.server.emit('new-stream', {
            streamId: payload.streamId,
            userId: payload.userId,
            streamData: payload.streamData,
            timestamp: new Date().toISOString(),
        });
    }
    emitStreamEnded(payload) {
        this.viewers.delete(payload.streamId);
        this.server.emit('stream-ended', {
            streamId: payload.streamId,
            userId: payload.userId,
            timestamp: new Date().toISOString(),
        });
    }
    emitChallengeSent(payload) {
        this.server.to(`user:${payload.targetUserId}`).emit('new-challenge', {
            challengeId: payload.challengeId,
            challengeData: payload.challengeData,
        });
    }
    emitChallengeAccepted(payload) {
        this.server.emit('battle-starting', {
            challengeId: payload.challengeId,
            streamId: payload.streamId,
        });
    }
    async updateViewerCount(streamId) {
        const count = this.viewers.get(streamId)?.size ?? 0;
        try {
            await this.streamService.updateViewerCount(streamId, count);
        }
        catch (e) {
            // Best-effort; stream session may not exist yet.
            this.logger.debug(`updateViewerCount best-effort failed: ${String(e)}`);
        }
    }
};
exports.LiveGateway = LiveGateway;
__decorate([
    (0, websockets_1.WebSocketServer)(),
    __metadata("design:type", socket_io_1.Server)
], LiveGateway.prototype, "server", void 0);
__decorate([
    (0, websockets_1.SubscribeMessage)('identify'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], LiveGateway.prototype, "handleIdentify", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('join-stream'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", Promise)
], LiveGateway.prototype, "handleJoinStream", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('leave-stream'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", Promise)
], LiveGateway.prototype, "handleLeaveStream", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('stream-started'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], LiveGateway.prototype, "handleStreamStarted", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('stream-ended'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], LiveGateway.prototype, "handleStreamEnded", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('challenge-sent'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], LiveGateway.prototype, "handleChallengeSent", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('challenge-accepted'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], LiveGateway.prototype, "handleChallengeAccepted", null);
exports.LiveGateway = LiveGateway = LiveGateway_1 = __decorate([
    (0, websockets_1.WebSocketGateway)({
        cors: {
            origin: '*',
            credentials: true,
        },
        namespace: 'live',
    }),
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [stream_service_1.StreamService,
        challenge_service_1.ChallengeService])
], LiveGateway);
//# sourceMappingURL=live.gateway.js.map