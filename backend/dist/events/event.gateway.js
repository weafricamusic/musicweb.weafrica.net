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
var EventGateway_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.EventGateway = void 0;
const websockets_1 = require("@nestjs/websockets");
const common_1 = require("@nestjs/common");
const socket_io_1 = require("socket.io");
let EventGateway = EventGateway_1 = class EventGateway {
    constructor() {
        this.logger = new common_1.Logger(EventGateway_1.name);
        this.clients = new Map();
    }
    handleConnection(client) {
        this.logger.log(`Client connected: ${client.id}`);
    }
    handleDisconnect(client) {
        this.logger.log(`Client disconnected: ${client.id}`);
        for (const [roomId, sockets] of this.clients.entries()) {
            if (sockets.delete(client.id)) {
                if (sockets.size === 0) {
                    this.clients.delete(roomId);
                }
                this.emitToRoom(roomId, 'VIEWER_COUNT_UPDATED', { count: sockets.size });
            }
        }
    }
    handleJoinRoom(client, payload) {
        const roomId = payload?.roomId?.trim();
        if (!roomId)
            return;
        client.join(roomId);
        if (!this.clients.has(roomId)) {
            this.clients.set(roomId, new Set());
        }
        this.clients.get(roomId).add(client.id);
        this.logger.log(`Client ${client.id} joined room ${roomId}`);
        this.emitToRoom(roomId, 'VIEWER_COUNT_UPDATED', {
            count: this.clients.get(roomId).size,
        });
    }
    handleLeaveRoom(client, payload) {
        const roomId = payload?.roomId?.trim();
        if (!roomId)
            return;
        client.leave(roomId);
        const set = this.clients.get(roomId);
        if (!set)
            return;
        set.delete(client.id);
        if (set.size === 0) {
            this.clients.delete(roomId);
        }
        this.emitToRoom(roomId, 'VIEWER_COUNT_UPDATED', {
            count: this.clients.get(roomId)?.size ?? 0,
        });
    }
    emitToRoom(roomId, event, payload) {
        this.server.to(roomId).emit(event, payload);
    }
    emitToAll(event, payload) {
        this.server.emit(event, payload);
    }
};
exports.EventGateway = EventGateway;
__decorate([
    (0, websockets_1.WebSocketServer)(),
    __metadata("design:type", socket_io_1.Server)
], EventGateway.prototype, "server", void 0);
__decorate([
    (0, websockets_1.SubscribeMessage)('JOIN_ROOM'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], EventGateway.prototype, "handleJoinRoom", null);
__decorate([
    (0, websockets_1.SubscribeMessage)('LEAVE_ROOM'),
    __param(1, (0, websockets_1.MessageBody)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [socket_io_1.Socket, Object]),
    __metadata("design:returntype", void 0)
], EventGateway.prototype, "handleLeaveRoom", null);
exports.EventGateway = EventGateway = EventGateway_1 = __decorate([
    (0, websockets_1.WebSocketGateway)({
        cors: {
            origin: '*',
            credentials: true,
        },
    })
], EventGateway);
//# sourceMappingURL=event.gateway.js.map