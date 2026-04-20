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
var ChallengeService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ChallengeService = void 0;
const common_1 = require("@nestjs/common");
const supabase_service_1 = require("../common/supabase/supabase.service");
const live_room_service_1 = require("../live-room/live-room.service");
const stream_service_1 = require("../stream/stream.service");
const live_room_state_1 = require("../orchestrator/state-machine/live-room.state");
let ChallengeService = ChallengeService_1 = class ChallengeService {
    constructor(supabase, streamService, liveRoomService) {
        this.supabase = supabase;
        this.streamService = streamService;
        this.liveRoomService = liveRoomService;
        this.logger = new common_1.Logger(ChallengeService_1.name);
    }
    async challengeUser(challengerId, targetUserId, message, metadata) {
        this.ensureSupabase();
        const challengerProfile = await this.getProfile(challengerId);
        const challengerType = this.getCreatorType(challengerProfile);
        if (!challengerType) {
            throw new common_1.ForbiddenException('Only artists and DJs can challenge others');
        }
        const activeRoom = await this.liveRoomService.findActiveByUser(targetUserId);
        if (!activeRoom || activeRoom.status !== live_room_state_1.LiveRoomStatus.LIVE) {
            throw new common_1.BadRequestException('User is not currently live');
        }
        const nowIso = new Date().toISOString();
        const { data: existingChallenge, error: existingErr } = await this.supabase.client
            .from('stream_challenges')
            .select('*')
            .eq('target_id', targetUserId)
            .eq('challenger_id', challengerId)
            .eq('status', 'pending')
            .gt('expires_at', nowIso)
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle();
        if (existingErr) {
            this.logger.warn(`Error checking existing challenge: ${existingErr.message}`);
        }
        if (existingChallenge) {
            throw new common_1.BadRequestException('You already have a pending challenge to this user');
        }
        const expiresAt = new Date(Date.now() + 5 * 60_000).toISOString();
        const challengeMetadata = metadata && typeof metadata === 'object' && !Array.isArray(metadata)
            ? metadata
            : {};
        const { data, error } = await this.supabase.client
            .from('stream_challenges')
            .insert({
            challenger_id: challengerId,
            target_id: targetUserId,
            live_room_id: activeRoom.id,
            status: 'pending',
            message: message || `${challengerType} challenges you to a battle!`,
            metadata: challengeMetadata,
            expires_at: expiresAt,
        })
            .select('*')
            .single();
        if (error) {
            this.logger.error(`Error creating challenge: ${error.message}`);
            throw new common_1.BadRequestException('Failed to create challenge');
        }
        const targetProfile = await this.getProfile(targetUserId);
        return {
            ...data,
            challenger: challengerProfile,
            target: targetProfile,
        };
    }
    async acceptChallenge(challengeId, userId) {
        this.ensureSupabase();
        const { data: challenge, error: fetchError } = await this.supabase.client
            .from('stream_challenges')
            .select('*')
            .eq('id', challengeId)
            .maybeSingle();
        if (fetchError || !challenge) {
            throw new common_1.BadRequestException('Challenge not found');
        }
        const ch = challenge;
        if (ch.target_id !== userId) {
            throw new common_1.ForbiddenException('This challenge is not for you');
        }
        if (String(ch.status) !== 'pending') {
            throw new common_1.BadRequestException('Challenge already responded to');
        }
        if (new Date(ch.expires_at) < new Date()) {
            await this.supabase.client
                .from('stream_challenges')
                .update({ status: 'expired', updated_at: new Date().toISOString() })
                .eq('id', challengeId);
            throw new common_1.BadRequestException('Challenge has expired');
        }
        const { error: updateErr } = await this.supabase.client
            .from('stream_challenges')
            .update({ status: 'accepted', updated_at: new Date().toISOString() })
            .eq('id', challengeId);
        if (updateErr) {
            this.logger.warn(`Failed to update challenge status: ${updateErr.message}`);
        }
        // Ensure live room exists.
        await this.liveRoomService.findById(ch.live_room_id);
        // Best-effort: switch live session to battle mode.
        await this.updateLiveSessionBattleMode(ch.live_room_id, ch.challenger_id);
        // Add challenger to the active stream session (best-effort).
        const streamSession = await this.streamService.findByLiveRoom(ch.live_room_id);
        if (streamSession) {
            try {
                await this.streamService.addParticipant(streamSession.id, ch.challenger_id);
            }
            catch (e) {
                this.logger.warn(`Failed adding participant to stream session: ${String(e)}`);
            }
        }
        return {
            success: true,
            liveRoomId: ch.live_room_id,
            streamSessionId: streamSession?.id ?? null,
            message: 'Challenge accepted! Battle mode activated.',
        };
    }
    async getPendingChallenges(userId) {
        this.ensureSupabase();
        const nowIso = new Date().toISOString();
        const { data, error } = await this.supabase.client
            .from('stream_challenges')
            .select('*')
            .eq('target_id', userId)
            .eq('status', 'pending')
            .gt('expires_at', nowIso)
            .order('created_at', { ascending: false });
        if (error) {
            this.logger.error(`Error fetching pending challenges: ${error.message}`);
            return [];
        }
        const rows = (data ?? []);
        const challengerIds = [...new Set(rows.map((row) => String(row.challenger_id)).filter(Boolean))];
        const challengerProfiles = new Map();
        if (challengerIds.length > 0) {
            const { data: profiles, error: profileErr } = await this.supabase.client
                .from('profiles')
                .select('*')
                .in('id', challengerIds);
            if (profileErr) {
                this.logger.warn(`Error fetching challenger profiles: ${profileErr.message}`);
            }
            else {
                (profiles ?? []).forEach((p) => {
                    const id = String(p?.id ?? '');
                    if (id)
                        challengerProfiles.set(id, p);
                });
            }
        }
        return rows.map((row) => ({
            ...row,
            challenger: challengerProfiles.get(String(row.challenger_id)) ?? null,
        }));
    }
    ensureSupabase() {
        if (!this.supabase.isConfigured) {
            throw new common_1.BadRequestException('Supabase is not configured on this server');
        }
    }
    async getProfile(userId) {
        const { data, error } = await this.supabase.client
            .from('profiles')
            .select('*')
            .eq('id', userId)
            .maybeSingle();
        if (error) {
            this.logger.warn(`Error fetching profile(${userId}): ${error.message}`);
            return { id: userId };
        }
        return (data ?? { id: userId });
    }
    getCreatorType(profile) {
        const raw = this.firstString(profile?.user_type, profile?.role, profile?.userType, profile?.type);
        const normalized = raw.trim().toLowerCase();
        if (normalized === 'artist')
            return 'artist';
        if (normalized === 'dj')
            return 'dj';
        return null;
    }
    firstString(...values) {
        for (const v of values) {
            if (typeof v === 'string' && v.trim().length > 0) {
                return v;
            }
        }
        return '';
    }
    async updateLiveSessionBattleMode(liveRoomId, challengerId) {
        const now = new Date().toISOString();
        // Some schemas may not include challenger_id; treat it as best-effort.
        const patch = {
            mode: 'battle',
            challenger_id: challengerId,
            updated_at: now,
        };
        try {
            const { error } = await this.supabase.client
                .from('live_sessions')
                .update(patch)
                .eq('id', liveRoomId);
            if (!error)
                return;
            const msg = error.message.toLowerCase();
            if (msg.includes('challenger_id') && msg.includes('column')) {
                delete patch.challenger_id;
            }
            if (msg.includes('mode') && msg.includes('column')) {
                delete patch.mode;
            }
            const { error: retryError } = await this.supabase.client
                .from('live_sessions')
                .update(patch)
                .eq('id', liveRoomId);
            if (retryError) {
                this.logger.warn(`Failed to update live_session battle mode: ${retryError.message}`);
            }
        }
        catch (e) {
            this.logger.warn(`Failed to update live_session battle mode (exception): ${String(e)}`);
        }
    }
};
exports.ChallengeService = ChallengeService;
exports.ChallengeService = ChallengeService = ChallengeService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [supabase_service_1.SupabaseService,
        stream_service_1.StreamService,
        live_room_service_1.LiveRoomService])
], ChallengeService);
//# sourceMappingURL=challenge.service.js.map