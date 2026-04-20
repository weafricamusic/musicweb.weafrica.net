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
var DistributedLockService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.DistributedLockService = void 0;
const common_1 = require("@nestjs/common");
const crypto_1 = require("crypto");
const redis_service_1 = require("../../common/redis/redis.service");
let DistributedLockService = DistributedLockService_1 = class DistributedLockService {
    constructor(redis) {
        this.redis = redis;
        this.logger = new common_1.Logger(DistributedLockService_1.name);
        this.DEFAULT_TTL_SECONDS = 30;
    }
    lockKey(key) {
        return `lock:${key}`;
    }
    async acquireLock(key, ttlSeconds = this.DEFAULT_TTL_SECONDS) {
        const lockKey = this.lockKey(key);
        const token = (0, crypto_1.randomUUID)();
        const res = await this.redis.client.set(lockKey, token, {
            NX: true,
            EX: ttlSeconds,
        });
        if (res === 'OK') {
            this.logger.debug(`Lock acquired: ${lockKey}`);
            return token;
        }
        return null;
    }
    async releaseLock(key, token) {
        const lockKey = this.lockKey(key);
        // Safe release: delete only if the token matches.
        const lua = `
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        return redis.call('DEL', KEYS[1])
      else
        return 0
      end
    `;
        await this.redis.client.eval(lua, {
            keys: [lockKey],
            arguments: [token],
        });
        this.logger.debug(`Lock released: ${lockKey}`);
    }
    async executeWithLock(key, fn, ttlSeconds = this.DEFAULT_TTL_SECONDS) {
        const token = await this.acquireLock(key, ttlSeconds);
        if (!token) {
            throw new Error(`Failed to acquire lock for ${key}`);
        }
        try {
            return await fn();
        }
        finally {
            await this.releaseLock(key, token);
        }
    }
};
exports.DistributedLockService = DistributedLockService;
exports.DistributedLockService = DistributedLockService = DistributedLockService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [redis_service_1.RedisService])
], DistributedLockService);
//# sourceMappingURL=distributed-lock.service.js.map