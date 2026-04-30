"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.FeedService = exports.EngagementTargetType = exports.EngagementEventType = void 0;
const common_1 = require("@nestjs/common");
var EngagementEventType;
(function (EngagementEventType) {
    EngagementEventType["VIEW"] = "view";
    EngagementEventType["LIKE"] = "like";
    EngagementEventType["COMMENT"] = "comment";
    EngagementEventType["GIFT"] = "gift";
    EngagementEventType["SHARE"] = "share";
    EngagementEventType["FOLLOW"] = "follow";
})(EngagementEventType || (exports.EngagementEventType = EngagementEventType = {}));
var EngagementTargetType;
(function (EngagementTargetType) {
    EngagementTargetType["LIVE"] = "live";
    EngagementTargetType["BATTLE"] = "battle";
    EngagementTargetType["SONG"] = "song";
    EngagementTargetType["VIDEO"] = "video";
    EngagementTargetType["ARTIST"] = "artist";
    EngagementTargetType["EVENT"] = "event";
    EngagementTargetType["PHOTO_POST"] = "photo_post";
})(EngagementTargetType || (exports.EngagementTargetType = EngagementTargetType = {}));
let FeedService = class FeedService {
    async generateGlobalFeed() {
        // Return mock data for now
        return {
            items: [],
            total: 0,
            page: 1,
            limit: 20,
        };
    }
    async generatePersonalizedFeed(userId, limit) {
        // Return mock data for now
        return {
            items: [],
            total: 0,
            page: 1,
            limit,
            userId,
        };
    }
    async getTrending(hours, limit) {
        // Return mock data for now
        return {
            items: [],
            total: 0,
            hours,
            limit,
        };
    }
    async getRecommended(userId, limit) {
        // Return mock data for now
        return {
            items: [],
            total: 0,
            userId,
            limit,
        };
    }
    async trackEngagement(data) {
        // Log the engagement for now
        console.log('Tracking engagement:', data);
        return { success: true };
    }
    parseLimit(limit, defaultLimit = 20, maxLimit = 100) {
        const parsed = parseInt(limit || '', 10);
        if (isNaN(parsed) || parsed <= 0)
            return defaultLimit;
        return Math.min(parsed, maxLimit);
    }
    parseHours(hours, defaultHours = 24) {
        const parsed = parseInt(hours || '', 10);
        if (isNaN(parsed) || parsed <= 0)
            return defaultHours;
        return Math.min(parsed, 168); // Max 1 week
    }
};
exports.FeedService = FeedService;
exports.FeedService = FeedService = __decorate([
    (0, common_1.Injectable)()
], FeedService);
//# sourceMappingURL=feed.service.js.map