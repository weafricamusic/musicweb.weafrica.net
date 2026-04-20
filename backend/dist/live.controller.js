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
exports.LiveController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("./auth/current-user.decorator");
const firebase_auth_guard_1 = require("./auth/firebase-auth.guard");
const challenge_service_1 = require("./challenge/challenge.service");
const supabase_service_1 = require("./common/supabase/supabase.service");
const live_gateway_1 = require("./gateways/live.gateway");
const orchestrator_service_1 = require("./orchestrator/orchestrator.service");
let LiveController = class LiveController {
    constructor(orchestrator, challengeService, liveGateway, supabase) {
        this.orchestrator = orchestrator;
        this.challengeService = challengeService;
        this.liveGateway = liveGateway;
        this.supabase = supabase;
    }
    async startLive(user, body) {
        if (!this.supabase.isConfigured) {
            throw new common_1.BadRequestException('Supabase is not configured on this server');
        }
        const { data: profile, error } = await this.supabase.client
            .from('profiles')
            .select('*')
            .eq('id', user.uid)
            .maybeSingle();
        if (error) {
            throw new common_1.BadRequestException(`Failed to load user profile: ${error.message}`);
        }
        const rawType = String(profile?.user_type ?? profile?.role ?? '').trim().toLowerCase();
        const userType = rawType === 'artist' ? 'artist' : rawType === 'dj' ? 'dj' : null;
        if (!userType) {
            throw new common_1.ForbiddenException('Only artists and DJs can go live');
        }
        const title = String(body?.title ?? '').trim() || `${userType} Live Session`;
        const category = String(body?.category ?? '').trim() || 'music';
        const coverImage = String(body?.coverImage ?? '').trim() || undefined;
        const privacy = body?.privacy === 'followers' ? 'followers' : 'public';
        const created = await this.orchestrator.startSoloLive({
            userId: user.uid,
            userType,
            title,
            category,
            coverImage,
            privacy,
        });
        this.liveGateway.emitStreamStarted({
            streamId: created.streamSession.id,
            userId: user.uid,
            streamData: {
                liveRoomId: created.liveRoom.id,
                title: created.liveRoom.title,
                hostName: profile?.name ?? profile?.stage_name ?? profile?.display_name ?? null,
                hostAvatar: profile?.avatar_url ?? null,
            },
        });
        return {
            success: true,
            streamId: created.streamSession.id,
            liveRoomId: created.liveRoom.id,
            channelId: created.streamSession.channelId,
            token: created.token,
            agoraAppId: process.env.AGORA_APP_ID,
        };
    }
    async challengeUser(user, targetUserId, body) {
        const challenge = await this.challengeService.challengeUser(user.uid, targetUserId, body?.message, body?.metadata);
        this.liveGateway.emitChallengeSent({
            challengeId: String(challenge?.id ?? ''),
            targetUserId,
            challengeData: challenge,
        });
        return challenge;
    }
    async acceptChallenge(user, challengeId) {
        const result = await this.challengeService.acceptChallenge(challengeId, user.uid);
        if (result?.success === true) {
            const streamId = String(result?.streamSessionId ?? result?.liveRoomId ?? '');
            this.liveGateway.emitChallengeAccepted({
                challengeId,
                streamId,
            });
        }
        return result;
    }
    async getActiveStreams() {
        if (!this.supabase.isConfigured) {
            return [];
        }
        const { data, error } = await this.supabase.client
            .from('live_sessions')
            .select('id, channel_id, title, host_id, host_name, thumbnail_url, viewer_count, mode, started_at, access_tier')
            .eq('is_live', true)
            .order('started_at', { ascending: false });
        if (error) {
            throw new common_1.BadRequestException(error.message);
        }
        return (data ?? []).map((session) => ({
            streamId: String(session.id),
            channelId: String(session.channel_id ?? ''),
            title: String(session.title ?? ''),
            hostId: String(session.host_id ?? ''),
            hostName: session.host_name ?? null,
            thumbnail: session.thumbnail_url ?? null,
            viewerCount: Number(session.viewer_count ?? 0),
            mode: session.mode ?? null,
            startedAt: session.started_at ?? null,
            privacy: session.access_tier ?? null,
        }));
    }
    async getPendingChallenges(user) {
        return this.challengeService.getPendingChallenges(user.uid);
    }
};
exports.LiveController = LiveController;
__decorate([
    (0, common_1.Post)('start'),
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], LiveController.prototype, "startLive", null);
__decorate([
    (0, common_1.Post)('challenge/:userId'),
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('userId')),
    __param(2, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String, Object]),
    __metadata("design:returntype", Promise)
], LiveController.prototype, "challengeUser", null);
__decorate([
    (0, common_1.Post)('accept-challenge/:challengeId'),
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('challengeId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], LiveController.prototype, "acceptChallenge", null);
__decorate([
    (0, common_1.Get)('active'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], LiveController.prototype, "getActiveStreams", null);
__decorate([
    (0, common_1.Get)('challenges/pending'),
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], LiveController.prototype, "getPendingChallenges", null);
exports.LiveController = LiveController = __decorate([
    (0, common_1.Controller)('live'),
    __metadata("design:paramtypes", [orchestrator_service_1.OrchestratorService,
        challenge_service_1.ChallengeService,
        live_gateway_1.LiveGateway,
        supabase_service_1.SupabaseService])
], LiveController);
//# sourceMappingURL=live.controller.js.map