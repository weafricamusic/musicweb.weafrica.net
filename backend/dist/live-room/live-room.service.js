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
var LiveRoomService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.LiveRoomService = void 0;
const common_1 = require("@nestjs/common");
const supabase_service_1 = require("../common/supabase/supabase.service");
const live_room_state_1 = require("../orchestrator/state-machine/live-room.state");
let LiveRoomService = LiveRoomService_1 = class LiveRoomService {
    constructor(supabase) {
        this.supabase = supabase;
        this.logger = new common_1.Logger(LiveRoomService_1.name);
        this.unsupportedInsertColumns = new Set();
        this.unsupportedUpdateColumns = new Set();
        this.invalidInsertColumns = new Set();
        this.invalidUpdateColumns = new Set();
        this.rooms = new Map();
    }
    async findActiveByUser(userId) {
        if (this.supabase.isConfigured) {
            const { data, error } = await this.supabase.client
                .from('live_sessions')
                .select('*')
                .eq('host_id', userId)
                .eq('is_live', true)
                .order('started_at', { ascending: false })
                .limit(1);
            if (error) {
                this.logger.warn(`Supabase findActiveByUser error: ${error.message}`);
            }
            else if (data && data.length > 0) {
                return this.mergeCachedRecord(this.mapLiveSessionRowToRecord(data[0]));
            }
        }
        for (const r of this.rooms.values()) {
            if (r.creatorId === userId && (r.status === live_room_state_1.LiveRoomStatus.READY || r.status === live_room_state_1.LiveRoomStatus.LIVE)) {
                return r;
            }
        }
        return null;
    }
    async findById(id) {
        if (this.supabase.isConfigured) {
            // Support both primary key lookup and channel_id-like lookup (matches Flutter fallback behavior).
            const { data: byId, error: idErr } = await this.supabase.client
                .from('live_sessions')
                .select('*')
                .eq('id', id)
                .maybeSingle();
            if (idErr) {
                this.logger.warn(`Supabase findById(id) error: ${idErr.message}`);
            }
            if (byId)
                return this.mergeCachedRecord(this.mapLiveSessionRowToRecord(byId));
            const { data: byChannel, error: chErr } = await this.supabase.client
                .from('live_sessions')
                .select('*')
                .eq('channel_id', id)
                .maybeSingle();
            if (chErr) {
                this.logger.warn(`Supabase findById(channel_id) error: ${chErr.message}`);
            }
            if (byChannel)
                return this.mergeCachedRecord(this.mapLiveSessionRowToRecord(byChannel));
        }
        const r = this.rooms.get(id);
        if (!r)
            throw new Error('Live room not found');
        return r;
    }
    async create(input) {
        const now = new Date().toISOString();
        const channelId = `live_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        if (this.supabase.isConfigured) {
            const insert = {
                channel_id: channelId,
                host_id: input.creatorId,
                artist_id: input.creatorId,
                host_name: null,
                title: input.title,
                category: input.category,
                thumbnail_url: input.coverImage ?? null,
                is_live: false,
                started_at: null,
                ended_at: null,
                access_tier: input.privacy ?? 'public',
                // Some schemas include status; keep it best-effort.
                status: this.mapStatusToDb(input.status),
                mode: input.mode,
                created_at: now,
                updated_at: now,
            };
            const data = await this.insertLiveSessionWithFallback(insert);
            if (data) {
                const persisted = this.mergeCachedRecord(this.mapLiveSessionRowToRecord(data));
                const record = {
                    ...persisted,
                    creatorType: input.creatorType,
                    coverImage: input.coverImage ?? persisted.coverImage,
                    mode: input.mode,
                    status: input.status,
                    privacy: input.privacy,
                };
                this.rooms.set(record.id, record);
                return record;
            }
        }
        const id = `lr_${Date.now()}_${Math.random().toString(36).slice(2)}`;
        const rec = {
            id,
            creatorId: input.creatorId,
            creatorType: input.creatorType,
            title: input.title,
            category: input.category,
            coverImage: input.coverImage,
            mode: input.mode,
            status: input.status,
            privacy: input.privacy,
            createdAt: now,
            updatedAt: now,
        };
        this.rooms.set(id, rec);
        return rec;
    }
    async updateStatus(id, status) {
        if (this.supabase.isConfigured) {
            const patch = {
                updated_at: new Date().toISOString(),
                status: this.mapStatusToDb(status),
            };
            if (status === live_room_state_1.LiveRoomStatus.LIVE) {
                patch.is_live = true;
                patch.started_at = new Date().toISOString();
            }
            if (status === live_room_state_1.LiveRoomStatus.ENDED || status === live_room_state_1.LiveRoomStatus.CANCELLED) {
                patch.is_live = false;
                patch.ended_at = new Date().toISOString();
            }
            const data = await this.updateLiveSessionWithFallback(id, patch);
            if (data) {
                const persisted = this.mergeCachedRecord(this.mapLiveSessionRowToRecord(data));
                const next = {
                    ...persisted,
                    status,
                    updatedAt: String(data.updated_at ?? new Date().toISOString()),
                };
                this.rooms.set(id, next);
                return next;
            }
        }
        const r = await this.findById(id);
        const next = { ...r, status, updatedAt: new Date().toISOString() };
        this.rooms.set(id, next);
        return next;
    }
    mapLiveSessionRowToRecord(row) {
        const status = this.mapDbToStatus(row?.status, row?.is_live);
        return {
            id: String(row?.id ?? row?.channel_id),
            creatorId: String(row?.host_id ?? row?.creator_id ?? ''),
            creatorType: 'artist',
            title: String(row?.title ?? ''),
            category: String(row?.category ?? ''),
            coverImage: (row?.thumbnail_url ?? undefined),
            mode: (row?.mode === live_room_state_1.LiveRoomMode.BATTLE ? live_room_state_1.LiveRoomMode.BATTLE : live_room_state_1.LiveRoomMode.SOLO),
            status,
            privacy: (row?.access_tier ?? row?.privacy ?? 'public'),
            createdAt: String(row?.created_at ?? new Date().toISOString()),
            updatedAt: String(row?.updated_at ?? row?.created_at ?? new Date().toISOString()),
        };
    }
    mapStatusToDb(status) {
        switch (status) {
            case live_room_state_1.LiveRoomStatus.DRAFT:
            case live_room_state_1.LiveRoomStatus.SCHEDULED:
            case live_room_state_1.LiveRoomStatus.WAITING:
            case live_room_state_1.LiveRoomStatus.READY:
                return 'scheduled';
            case live_room_state_1.LiveRoomStatus.LIVE:
                return 'live';
            case live_room_state_1.LiveRoomStatus.ENDED:
                return 'ended';
            case live_room_state_1.LiveRoomStatus.CANCELLED:
                return 'cancelled';
        }
    }
    mapDbToStatus(rawStatus, isLive) {
        if (isLive === true)
            return live_room_state_1.LiveRoomStatus.LIVE;
        const s = String(rawStatus ?? '').toLowerCase();
        if (s === 'live')
            return live_room_state_1.LiveRoomStatus.LIVE;
        if (s === 'scheduled')
            return live_room_state_1.LiveRoomStatus.SCHEDULED;
        if (s === 'ended')
            return live_room_state_1.LiveRoomStatus.ENDED;
        if (s === 'cancelled' || s === 'canceled')
            return live_room_state_1.LiveRoomStatus.CANCELLED;
        return live_room_state_1.LiveRoomStatus.SCHEDULED;
    }
    mergeCachedRecord(record) {
        const cached = this.rooms.get(record.id);
        if (!cached) {
            return record;
        }
        return {
            ...record,
            creatorType: cached.creatorType,
            coverImage: cached.coverImage ?? record.coverImage,
            mode: cached.mode,
            status: cached.status,
            privacy: cached.privacy ?? record.privacy,
            createdAt: cached.createdAt ?? record.createdAt,
            updatedAt: cached.updatedAt ?? record.updatedAt,
        };
    }
    async insertLiveSessionWithFallback(insert) {
        let candidate = this.omitColumns(insert, this.unsupportedInsertColumns, this.invalidInsertColumns);
        for (let attempt = 0; attempt < 5; attempt += 1) {
            const { data, error } = await this.supabase.client
                .from('live_sessions')
                .insert(candidate)
                .select('*')
                .single();
            if (!error) {
                return data;
            }
            const missingColumn = this.extractMissingColumn(error.message);
            if (missingColumn) {
                this.unsupportedInsertColumns.add(missingColumn);
                candidate = this.omitColumns(insert, this.unsupportedInsertColumns, this.invalidInsertColumns);
                this.logger.warn(`Supabase create live_session retrying without unsupported column '${missingColumn}'`);
                continue;
            }
            const invalidColumn = this.extractInvalidColumn(error.message, candidate);
            if (invalidColumn) {
                this.invalidInsertColumns.add(invalidColumn);
                candidate = this.omitColumns(insert, this.unsupportedInsertColumns, this.invalidInsertColumns);
                this.logger.warn(`Supabase create live_session retrying without invalid column '${invalidColumn}'`);
                continue;
            }
            this.logger.warn(`Supabase create live_session failed: ${error.message}`);
            return null;
        }
        return null;
    }
    async updateLiveSessionWithFallback(id, patch) {
        let candidate = this.omitColumns(patch, this.unsupportedUpdateColumns, this.invalidUpdateColumns);
        for (let attempt = 0; attempt < 5; attempt += 1) {
            const { data, error } = await this.supabase.client
                .from('live_sessions')
                .update(candidate)
                .eq('id', id)
                .select('*')
                .maybeSingle();
            if (!error) {
                return (data ?? null);
            }
            const missingColumn = this.extractMissingColumn(error.message);
            if (missingColumn) {
                this.unsupportedUpdateColumns.add(missingColumn);
                candidate = this.omitColumns(patch, this.unsupportedUpdateColumns, this.invalidUpdateColumns);
                this.logger.warn(`Supabase update live_session retrying without unsupported column '${missingColumn}'`);
                continue;
            }
            const invalidColumn = this.extractInvalidColumn(error.message, candidate);
            if (invalidColumn) {
                this.invalidUpdateColumns.add(invalidColumn);
                candidate = this.omitColumns(patch, this.unsupportedUpdateColumns, this.invalidUpdateColumns);
                this.logger.warn(`Supabase update live_session retrying without invalid column '${invalidColumn}'`);
                continue;
            }
            this.logger.warn(`Supabase updateStatus failed: ${error.message}`);
            return null;
        }
        return null;
    }
    omitColumns(values, unsupported, invalid) {
        return Object.fromEntries(Object.entries(values).filter(([key]) => !unsupported.has(key) && !invalid.has(key)));
    }
    extractMissingColumn(message) {
        const match = /Could not find the '([^']+)' column of 'live_sessions'/.exec(message);
        return match?.[1] ?? null;
    }
    extractInvalidColumn(message, candidate) {
        if (/live_sessions_status_check/.test(message) && 'status' in candidate) {
            return 'status';
        }
        return null;
    }
};
exports.LiveRoomService = LiveRoomService;
exports.LiveRoomService = LiveRoomService = LiveRoomService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [supabase_service_1.SupabaseService])
], LiveRoomService);
//# sourceMappingURL=live-room.service.js.map