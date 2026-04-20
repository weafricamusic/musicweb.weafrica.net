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
var StreamService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.StreamService = void 0;
const common_1 = require("@nestjs/common");
const supabase_service_1 = require("../common/supabase/supabase.service");
const agora_service_1 = require("./agora/agora.service");
let StreamService = StreamService_1 = class StreamService {
    constructor(agora, supabase) {
        this.agora = agora;
        this.supabase = supabase;
        this.logger = new common_1.Logger(StreamService_1.name);
        this.sessions = new Map();
    }
    async create(input) {
        const id = `ss_${Date.now()}_${Math.random().toString(36).slice(2)}`;
        const channelId = `live_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        const now = new Date().toISOString();
        if (this.supabase.isConfigured) {
            const { data, error } = await this.supabase.client
                .from('stream_sessions')
                .insert({
                id,
                live_room_id: input.liveRoomId,
                channel_id: channelId,
                participants: input.participants ?? [],
                status: input.status,
                viewer_count: 0,
                peak_viewers: 0,
                metadata: {},
                created_at: now,
                updated_at: now,
            })
                .select('*')
                .single();
            if (error) {
                this.logger.warn(`Supabase create stream_session failed: ${error.message}`);
            }
            else if (data) {
                const record = this.mapRowToRecord(data);
                this.sessions.set(record.id, record);
                return record;
            }
        }
        const rec = {
            id,
            liveRoomId: input.liveRoomId,
            channelId,
            participants: input.participants ?? [],
            status: input.status,
            startedAt: null,
            endedAt: null,
            viewerCount: 0,
            peakViewers: 0,
            metadata: {},
        };
        this.sessions.set(id, rec);
        return rec;
    }
    async findById(streamSessionId) {
        if (this.supabase.isConfigured) {
            const { data, error } = await this.supabase.client
                .from('stream_sessions')
                .select('*')
                .eq('id', streamSessionId)
                .maybeSingle();
            if (error) {
                this.logger.warn(`Supabase find stream_session failed: ${error.message}`);
            }
            else if (data) {
                const record = this.mergeCachedRecord(this.mapRowToRecord(data));
                this.sessions.set(record.id, record);
                return record;
            }
        }
        return this.sessions.get(streamSessionId) ?? null;
    }
    async findByLiveRoom(liveRoomId) {
        if (this.supabase.isConfigured) {
            const { data, error } = await this.supabase.client
                .from('stream_sessions')
                .select('*')
                .eq('live_room_id', liveRoomId)
                .order('created_at', { ascending: false })
                .limit(1)
                .maybeSingle();
            if (error) {
                this.logger.warn(`Supabase find stream_session by live_room failed: ${error.message}`);
            }
            else if (data) {
                const record = this.mergeCachedRecord(this.mapRowToRecord(data));
                this.sessions.set(record.id, record);
                return record;
            }
        }
        const matches = [...this.sessions.values()].filter((session) => session.liveRoomId === liveRoomId);
        return matches.at(-1) ?? null;
    }
    async generateToken(input) {
        return this.agora.generateRtcToken({
            channelId: input.channelId,
            uid: input.userId,
            role: input.role ?? 'broadcaster',
        });
    }
    async updateStatus(streamSessionId, status) {
        const ss = await this.findById(streamSessionId);
        if (!ss)
            throw new Error('Stream session not found');
        const now = new Date().toISOString();
        const patch = { status, updated_at: now };
        if (status === 'ACTIVE' && !ss.startedAt) {
            patch.started_at = now;
        }
        if (status === 'CLOSED' && !ss.endedAt) {
            patch.ended_at = now;
        }
        if (this.supabase.isConfigured) {
            const { data, error } = await this.supabase.client
                .from('stream_sessions')
                .update(patch)
                .eq('id', streamSessionId)
                .select('*')
                .single();
            if (error) {
                this.logger.warn(`Supabase update stream_session failed: ${error.message}`);
            }
            else if (data) {
                const record = this.mergeCachedRecord(this.mapRowToRecord(data));
                this.sessions.set(record.id, record);
                return record;
            }
        }
        const next = {
            ...ss,
            status,
            startedAt: patch.started_at ?? ss.startedAt ?? null,
            endedAt: patch.ended_at ?? ss.endedAt ?? null,
        };
        this.sessions.set(streamSessionId, next);
        return next;
    }
    async updateStatusByLiveRoom(liveRoomId, status) {
        const session = await this.findByLiveRoom(liveRoomId);
        if (!session) {
            return;
        }
        await this.updateStatus(session.id, status);
    }
    async updateViewerCount(streamSessionId, viewerCount) {
        const session = await this.findById(streamSessionId);
        if (!session) {
            throw new Error('Stream session not found');
        }
        const peakViewers = Math.max(session.peakViewers, viewerCount);
        if (this.supabase.isConfigured) {
            const { error } = await this.supabase.client
                .from('stream_sessions')
                .update({
                viewer_count: viewerCount,
                peak_viewers: peakViewers,
                updated_at: new Date().toISOString(),
            })
                .eq('id', streamSessionId);
            if (error) {
                this.logger.warn(`Supabase update viewer count failed: ${error.message}`);
            }
        }
        this.sessions.set(streamSessionId, {
            ...session,
            viewerCount,
            peakViewers,
        });
    }
    async addParticipant(streamSessionId, userId) {
        const session = await this.findById(streamSessionId);
        if (!session) {
            throw new Error('Stream session not found');
        }
        const participants = session.participants.includes(userId)
            ? session.participants
            : [...session.participants, userId];
        return this.updateParticipants(streamSessionId, participants, session);
    }
    async removeParticipant(streamSessionId, userId) {
        const session = await this.findById(streamSessionId);
        if (!session) {
            throw new Error('Stream session not found');
        }
        const participants = session.participants.filter((participant) => participant !== userId);
        return this.updateParticipants(streamSessionId, participants, session);
    }
    async getStreamAnalytics(streamSessionId) {
        const session = await this.findById(streamSessionId);
        if (!session) {
            throw new Error('Stream session not found');
        }
        const durationSeconds = session.startedAt && session.endedAt
            ? Math.max(0, Math.floor((Date.parse(session.endedAt) - Date.parse(session.startedAt)) / 1000))
            : null;
        return {
            sessionId: session.id,
            liveRoomId: session.liveRoomId,
            status: session.status,
            durationSeconds,
            totalParticipants: session.participants.length,
            peakViewers: session.peakViewers,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
        };
    }
    async updateParticipants(streamSessionId, participants, existing) {
        if (this.supabase.isConfigured) {
            const { data, error } = await this.supabase.client
                .from('stream_sessions')
                .update({
                participants,
                updated_at: new Date().toISOString(),
            })
                .eq('id', streamSessionId)
                .select('*')
                .single();
            if (error) {
                this.logger.warn(`Supabase update stream participants failed: ${error.message}`);
            }
            else if (data) {
                const record = this.mergeCachedRecord(this.mapRowToRecord(data));
                this.sessions.set(record.id, record);
                return record;
            }
        }
        const next = { ...existing, participants };
        this.sessions.set(streamSessionId, next);
        return next;
    }
    mapRowToRecord(row) {
        return {
            id: String(row.id),
            liveRoomId: String(row.live_room_id),
            channelId: String(row.channel_id),
            participants: Array.isArray(row.participants)
                ? row.participants.map((participant) => String(participant))
                : [],
            status: this.toStatus(row.status),
            startedAt: row.started_at ? String(row.started_at) : null,
            endedAt: row.ended_at ? String(row.ended_at) : null,
            viewerCount: Number(row.viewer_count ?? 0),
            peakViewers: Number(row.peak_viewers ?? 0),
            metadata: this.toMetadata(row.metadata),
        };
    }
    mergeCachedRecord(record) {
        const cached = this.sessions.get(record.id);
        if (!cached) {
            return record;
        }
        return {
            ...record,
            participants: cached.participants.length > record.participants.length
                ? cached.participants
                : record.participants,
            metadata: Object.keys(cached.metadata).length > 0
                ? { ...record.metadata, ...cached.metadata }
                : record.metadata,
        };
    }
    toStatus(value) {
        switch (String(value ?? '').toUpperCase()) {
            case 'ACTIVE':
                return 'ACTIVE';
            case 'DISCONNECTED':
                return 'DISCONNECTED';
            case 'CLOSED':
                return 'CLOSED';
            default:
                return 'CREATED';
        }
    }
    toMetadata(value) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) {
            return {};
        }
        return value;
    }
};
exports.StreamService = StreamService;
exports.StreamService = StreamService = StreamService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [agora_service_1.AgoraService,
        supabase_service_1.SupabaseService])
], StreamService);
//# sourceMappingURL=stream.service.js.map