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
Object.defineProperty(exports, "__esModule", { value: true });
exports.BattleService = void 0;
const crypto_1 = require("crypto");
const common_1 = require("@nestjs/common");
const supabase_service_1 = require("../common/supabase/supabase.service");
const battle_state_1 = require("../orchestrator/state-machine/battle.state");
let BattleService = class BattleService {
    constructor(supabase) {
        this.supabase = supabase;
    }
    async findActiveByUser(userId) {
        const { data, error } = await this.supabase.client
            .from('live_battles')
            .select('*')
            .or(`host_a_id.eq.${userId},host_b_id.eq.${userId}`)
            .in('status', ['waiting', 'ready', 'countdown', 'live'])
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle();
        if (error) {
            throw error;
        }
        return data ? this.mapBattleRow(data) : null;
    }
    async findById(battleId) {
        const { data, error } = await this.supabase.client
            .from('live_battles')
            .select('*')
            .eq('battle_id', battleId)
            .maybeSingle();
        if (error) {
            throw error;
        }
        return data ? this.mapBattleRow(data) : null;
    }
    async findByLiveRoom(liveRoomId) {
        const { data, error } = await this.supabase.client
            .from('live_battles')
            .select('*')
            .eq('live_room_id', liveRoomId)
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle();
        if (error) {
            throw error;
        }
        return data ? this.mapBattleRow(data) : null;
    }
    async create(input) {
        const battleId = (0, crypto_1.randomUUID)();
        const channelId = `weafrica_battle_${battleId}`;
        const hostAgoraUid = this.stableAgoraUid(input.hostId);
        const { data, error } = await this.supabase.client
            .from('live_battles')
            .insert({
            battle_id: battleId,
            live_room_id: input.liveRoomId,
            channel_id: channelId,
            status: this.toDbBattleStatus(input.status ?? battle_state_1.BattleStatus.WAITING),
            host_a_id: input.hostId,
            host_a_agora_uid: hostAgoraUid,
            host_a_ready: false,
            host_b_ready: false,
            duration_seconds: input.durationSeconds,
            price_coins: input.coinGoal,
            beat_name: input.beatName,
            coin_goal: input.coinGoal,
            title: input.title ?? null,
            category: input.category ?? null,
            country: input.country ?? null,
            gift_enabled: true,
            voting_enabled: false,
            battle_format: 'continuous',
            round_count: 3,
            scheduled_at: new Date().toISOString(),
        })
            .select('*')
            .single();
        if (error) {
            throw error;
        }
        return this.mapBattleRow(data);
    }
    async createInvite(input) {
        const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();
        const { data, error } = await this.supabase.client
            .from('battle_invites')
            .insert({
            battle_id: input.battleId,
            from_uid: input.fromUserId,
            to_uid: input.toUserId,
            status: 'pending',
            expires_at: expiresAt,
        })
            .select('*')
            .single();
        if (error) {
            throw error;
        }
        return this.mapInviteRow(data);
    }
    async getInvite(inviteId) {
        const { data, error } = await this.supabase.client
            .from('battle_invites')
            .select('*')
            .eq('id', inviteId)
            .maybeSingle();
        if (error) {
            throw error;
        }
        return data ? this.mapInviteRow(data) : null;
    }
    async getInviteByBattleAndUser(battleId, toUserId) {
        const { data, error } = await this.supabase.client
            .from('battle_invites')
            .select('*')
            .eq('battle_id', battleId)
            .eq('to_uid', toUserId)
            .eq('status', 'pending')
            .gt('expires_at', new Date().toISOString())
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle();
        if (error) {
            throw error;
        }
        return data ? this.mapInviteRow(data) : null;
    }
    async updateInviteStatus(inviteId, status) {
        const { data, error } = await this.supabase.client
            .from('battle_invites')
            .update({
            status: this.toDbInviteStatus(status),
            responded_at: new Date().toISOString(),
        })
            .eq('id', inviteId)
            .select('*')
            .single();
        if (error) {
            throw error;
        }
        return this.mapInviteRow(data);
    }
    async getPendingInvites(userId) {
        const { data, error } = await this.supabase.client
            .from('battle_invites')
            .select('*, live_battles!inner(*)')
            .eq('to_uid', userId)
            .eq('status', 'pending')
            .gt('expires_at', new Date().toISOString())
            .order('created_at', { ascending: false });
        if (error) {
            throw error;
        }
        return (data ?? []).map((row) => this.mapInviteRow(row));
    }
    async update(battleId, patch) {
        const updatePayload = {};
        if (patch.liveRoomId !== undefined)
            updatePayload.live_room_id = patch.liveRoomId;
        if (patch.channelId !== undefined)
            updatePayload.channel_id = patch.channelId;
        if (patch.hostId !== undefined)
            updatePayload.host_a_id = patch.hostId;
        if (patch.opponentId !== undefined)
            updatePayload.host_b_id = patch.opponentId;
        if (patch.hostAgoraUid !== undefined)
            updatePayload.host_a_agora_uid = patch.hostAgoraUid;
        if (patch.opponentAgoraUid !== undefined)
            updatePayload.host_b_agora_uid = patch.opponentAgoraUid;
        if (patch.durationSeconds !== undefined)
            updatePayload.duration_seconds = patch.durationSeconds;
        if (patch.coinGoal !== undefined) {
            updatePayload.coin_goal = patch.coinGoal;
            updatePayload.price_coins = patch.coinGoal;
        }
        if (patch.beatName !== undefined)
            updatePayload.beat_name = patch.beatName;
        if (patch.title !== undefined)
            updatePayload.title = patch.title;
        if (patch.category !== undefined)
            updatePayload.category = patch.category;
        if (patch.country !== undefined)
            updatePayload.country = patch.country;
        if (patch.status !== undefined)
            updatePayload.status = this.toDbBattleStatus(patch.status);
        if (patch.hostReady !== undefined)
            updatePayload.host_a_ready = patch.hostReady;
        if (patch.opponentReady !== undefined)
            updatePayload.host_b_ready = patch.opponentReady;
        if (patch.startedAt !== undefined)
            updatePayload.started_at = patch.startedAt;
        if (patch.endedAt !== undefined)
            updatePayload.ended_at = patch.endedAt;
        if (patch.endsAt !== undefined)
            updatePayload.ends_at = patch.endsAt;
        if (patch.scheduledAt !== undefined)
            updatePayload.scheduled_at = patch.scheduledAt;
        const { data, error } = await this.supabase.client
            .from('live_battles')
            .update(updatePayload)
            .eq('battle_id', battleId)
            .select('*')
            .single();
        if (error) {
            throw error;
        }
        return this.mapBattleRow(data);
    }
    async updateStatus(battleId, status) {
        return this.update(battleId, { status });
    }
    async setOpponent(battleId, opponentId) {
        return this.update(battleId, {
            opponentId,
            opponentAgoraUid: this.stableAgoraUid(opponentId),
            status: battle_state_1.BattleStatus.READY,
        });
    }
    async finalizeBattle(battleId) {
        const { data, error } = await this.supabase.client.rpc('battle_finalize_due', {
            p_battle_id: battleId,
        });
        if (error) {
            throw error;
        }
        return data;
    }
    async startScoringEngine(_battleId) {
        return;
    }
    async computeWinner(battleId) {
        const finalized = await this.finalizeBattle(battleId);
        return finalized.winner_uid;
    }
    mapBattleRow(row) {
        return {
            id: String(row.battle_id),
            liveRoomId: String(row.live_room_id ?? ''),
            channelId: String(row.channel_id ?? ''),
            hostId: String(row.host_a_id ?? ''),
            opponentId: row.host_b_id ? String(row.host_b_id) : undefined,
            hostAgoraUid: this.toNullableNumber(row.host_a_agora_uid),
            opponentAgoraUid: this.toNullableNumber(row.host_b_agora_uid),
            durationSeconds: Number(row.duration_seconds ?? 0),
            coinGoal: Number(row.coin_goal ?? row.price_coins ?? 0),
            beatName: String(row.beat_name ?? ''),
            title: row.title ? String(row.title) : undefined,
            category: row.category ? String(row.category) : undefined,
            country: row.country ? String(row.country) : undefined,
            status: this.fromDbBattleStatus(String(row.status ?? 'waiting')),
            createdAt: row.created_at ? String(row.created_at) : undefined,
            updatedAt: row.updated_at ? String(row.updated_at) : undefined,
            startedAt: row.started_at ? String(row.started_at) : null,
            endedAt: row.ended_at ? String(row.ended_at) : null,
            endsAt: row.ends_at ? String(row.ends_at) : null,
        };
    }
    mapInviteRow(row) {
        return {
            id: String(row.id),
            battleId: String(row.battle_id),
            fromUserId: String(row.from_uid),
            toUserId: String(row.to_uid),
            status: this.fromDbInviteStatus(String(row.status ?? 'pending')),
            expiresAt: String(row.expires_at),
            respondedAt: row.responded_at ? String(row.responded_at) : null,
            createdAt: String(row.created_at),
        };
    }
    toDbBattleStatus(status) {
        switch (status) {
            case battle_state_1.BattleStatus.WAITING:
                return 'waiting';
            case battle_state_1.BattleStatus.READY:
                return 'ready';
            case battle_state_1.BattleStatus.LIVE:
                return 'live';
            case battle_state_1.BattleStatus.PAUSED:
                return 'countdown';
            case battle_state_1.BattleStatus.ENDED:
            case battle_state_1.BattleStatus.CANCELLED:
                return 'ended';
        }
    }
    fromDbBattleStatus(status) {
        switch (status) {
            case 'ready':
            case 'countdown':
                return battle_state_1.BattleStatus.READY;
            case 'live':
                return battle_state_1.BattleStatus.LIVE;
            case 'ended':
                return battle_state_1.BattleStatus.ENDED;
            default:
                return battle_state_1.BattleStatus.WAITING;
        }
    }
    toDbInviteStatus(status) {
        switch (status) {
            case 'ACCEPTED':
                return 'accepted';
            case 'DECLINED':
                return 'declined';
            case 'EXPIRED':
                return 'expired';
            default:
                return 'pending';
        }
    }
    fromDbInviteStatus(status) {
        switch (status) {
            case 'accepted':
                return 'ACCEPTED';
            case 'declined':
                return 'DECLINED';
            case 'expired':
                return 'EXPIRED';
            default:
                return 'PENDING';
        }
    }
    stableAgoraUid(userId) {
        let hash = 0;
        for (let index = 0; index < userId.length; index += 1) {
            hash = (hash << 5) - hash + userId.charCodeAt(index);
            hash |= 0;
        }
        const uid = Math.abs(hash) % 2000000000;
        return uid === 0 ? 1 : uid;
    }
    toNullableNumber(value) {
        if (value === null || value === undefined) {
            return null;
        }
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
    }
};
exports.BattleService = BattleService;
exports.BattleService = BattleService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [supabase_service_1.SupabaseService])
], BattleService);
//# sourceMappingURL=battle.service.js.map