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
var EventBusService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.EventBusService = void 0;
const common_1 = require("@nestjs/common");
const redis_service_1 = require("../common/redis/redis.service");
const event_gateway_1 = require("./event.gateway");
const event_types_1 = require("./types/event-types");
let EventBusService = EventBusService_1 = class EventBusService {
    constructor(redis, gateway) {
        this.redis = redis;
        this.gateway = gateway;
        this.logger = new common_1.Logger(EventBusService_1.name);
        this.STREAM_KEY = 'events:stream';
    }
    async emit(event, payload) {
        const eventData = {
            type: event,
            payload,
            timestamp: new Date().toISOString(),
            eventId: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
        };
        this.logger.debug(`Emitting event: ${event}`);
        // Store in Redis Stream for replay / diagnostics.
        await this.redis.client.xAdd(this.STREAM_KEY, '*', {
            data: JSON.stringify(eventData),
        });
        // Push to WebSocket clients.
        this.gateway.emitToAll(event, payload);
        // Optional internal routing for background consumers.
        if (this.isDomainEvent(event)) {
            await this.redis.client.publish(`event:${event}`, JSON.stringify(payload));
        }
    }
    isDomainEvent(event) {
        // Domain events go to internal handlers.
        const domainEvents = [
            event_types_1.DomainEvent.STREAM_CREATED,
            event_types_1.DomainEvent.STREAM_STARTED,
            event_types_1.DomainEvent.STREAM_ENDED,
            event_types_1.DomainEvent.BATTLE_ACCEPTED,
            event_types_1.DomainEvent.BATTLE_ENDED,
            event_types_1.DomainEvent.GIFT_SENT,
            event_types_1.DomainEvent.VOTE_CAST,
        ];
        return domainEvents.includes(event);
    }
};
exports.EventBusService = EventBusService;
exports.EventBusService = EventBusService = EventBusService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [redis_service_1.RedisService,
        event_gateway_1.EventGateway])
], EventBusService);
//# sourceMappingURL=event-bus.service.js.map