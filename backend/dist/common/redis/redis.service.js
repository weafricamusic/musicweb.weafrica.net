"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var RedisService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.RedisService = void 0;
const common_1 = require("@nestjs/common");
const redis_1 = require("redis");
let RedisService = RedisService_1 = class RedisService {
    constructor() {
        this.logger = new common_1.Logger(RedisService_1.name);
        this._client = null;
    }
    get client() {
        if (!this._client) {
            throw new Error('Redis client not initialized');
        }
        return this._client;
    }
    async onModuleInit() {
        const url = process.env.REDIS_URL ?? 'redis://localhost:6379';
        const password = (process.env.REDIS_PASSWORD ?? '').trim();
        const client = (0, redis_1.createClient)({
            url,
            password: password.length > 0 ? password : undefined,
        });
        client.on('error', (err) => {
            this.logger.error('Redis error', err);
        });
        client.on('connect', () => {
            this.logger.log('Redis connected');
        });
        await client.connect();
        this._client = client;
    }
    async onModuleDestroy() {
        try {
            await this._client?.quit();
        }
        catch (_) {
            // best-effort
        }
        finally {
            this._client = null;
        }
    }
};
exports.RedisService = RedisService;
exports.RedisService = RedisService = RedisService_1 = __decorate([
    (0, common_1.Injectable)()
], RedisService);
//# sourceMappingURL=redis.service.js.map