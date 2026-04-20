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
exports.FeedController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const firebase_auth_guard_1 = require("../auth/firebase-auth.guard");
const feed_service_1 = require("./feed.service");
let FeedController = class FeedController {
    constructor(feedService) {
        this.feedService = feedService;
    }
    async getGlobalFeed(limit) {
        return this.feedService.generateGlobalFeed(this.parseLimit(limit, 50, 200));
    }
    async getPersonalFeed(user, limit) {
        return this.feedService.generatePersonalizedFeed(user.uid, this.parseLimit(limit, 50, 200));
    }
    async getTrending(hours, limit) {
        return this.feedService.getTrending(this.parseHours(hours, 24), this.parseLimit(limit, 20, 100));
    }
    async getRecommended(user, limit) {
        return this.feedService.getRecommended(user.uid, this.parseLimit(limit, 20, 100));
    }
    async trackEngagement(user, body) {
        const targetType = String(body.targetType ?? '').trim();
        const targetId = String(body.targetId ?? '').trim();
        const eventType = String(body.eventType ?? '').trim();
        if (!['live', 'battle', 'song', 'video', 'artist', 'event', 'photo_post'].includes(targetType)) {
            throw new common_1.BadRequestException('Invalid targetType');
        }
        if (!targetId) {
            throw new common_1.BadRequestException('Missing targetId');
        }
        if (!['view', 'like', 'comment', 'gift', 'share', 'follow'].includes(eventType)) {
            throw new common_1.BadRequestException('Invalid eventType');
        }
        await this.feedService.trackEngagement({
            userId: user.uid,
            targetType,
            targetId,
            eventType,
            metadata: body.metadata,
        });
        return { success: true };
    }
    parseLimit(value, fallback, max) {
        const parsed = Number(value ?? fallback);
        if (!Number.isFinite(parsed)) {
            return fallback;
        }
        return Math.max(1, Math.min(max, Math.floor(parsed)));
    }
    parseHours(value, fallback) {
        const parsed = Number(value ?? fallback);
        if (!Number.isFinite(parsed)) {
            return fallback;
        }
        return Math.max(1, Math.min(24 * 30, Math.floor(parsed)));
    }
};
exports.FeedController = FeedController;
__decorate([
    (0, common_1.Get)('global'),
    __param(0, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], FeedController.prototype, "getGlobalFeed", null);
__decorate([
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    (0, common_1.Get)('personal'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], FeedController.prototype, "getPersonalFeed", null);
__decorate([
    (0, common_1.Get)('trending'),
    __param(0, (0, common_1.Query)('hours')),
    __param(1, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], FeedController.prototype, "getTrending", null);
__decorate([
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    (0, common_1.Get)('recommended'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], FeedController.prototype, "getRecommended", null);
__decorate([
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    (0, common_1.Post)('track'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], FeedController.prototype, "trackEngagement", null);
exports.FeedController = FeedController = __decorate([
    (0, common_1.Controller)('feed'),
    __metadata("design:paramtypes", [feed_service_1.FeedService])
], FeedController);
//# sourceMappingURL=feed.controller.js.map