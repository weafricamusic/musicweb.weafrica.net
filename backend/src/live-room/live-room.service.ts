import { Injectable, Logger } from '@nestjs/common';

import { SupabaseService } from '../common/supabase/supabase.service';
import { LiveRoomMode, LiveRoomStatus } from '../orchestrator/state-machine/live-room.state';

export type LiveRoomRecord = {
  id: string;
  creatorId: string;
  creatorType: 'artist' | 'dj';
  title: string;
  category: string;
  coverImage?: string;
  mode: LiveRoomMode;
  status: LiveRoomStatus;
  privacy?: 'public' | 'followers';
  createdAt: string;
  updatedAt: string;
};

@Injectable()
export class LiveRoomService {
  private readonly logger = new Logger(LiveRoomService.name);
  private readonly unsupportedInsertColumns = new Set<string>();
  private readonly unsupportedUpdateColumns = new Set<string>();
  private readonly invalidInsertColumns = new Set<string>();
  private readonly invalidUpdateColumns = new Set<string>();

  private readonly rooms = new Map<string, LiveRoomRecord>();

  constructor(private readonly supabase: SupabaseService) {}

  async findActiveByUser(userId: string): Promise<LiveRoomRecord | null> {
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
      } else if (data && data.length > 0) {
        return this.mergeCachedRecord(this.mapLiveSessionRowToRecord(data[0]));
      }
    }

    for (const r of this.rooms.values()) {
      if (r.creatorId === userId && (r.status === LiveRoomStatus.READY || r.status === LiveRoomStatus.LIVE)) {
        return r;
      }
    }
    return null;
  }

  async findById(id: string): Promise<LiveRoomRecord> {
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
      if (byId) return this.mergeCachedRecord(this.mapLiveSessionRowToRecord(byId));

      const { data: byChannel, error: chErr } = await this.supabase.client
        .from('live_sessions')
        .select('*')
        .eq('channel_id', id)
        .maybeSingle();
      if (chErr) {
        this.logger.warn(`Supabase findById(channel_id) error: ${chErr.message}`);
      }
      if (byChannel) return this.mergeCachedRecord(this.mapLiveSessionRowToRecord(byChannel));
    }

    const r = this.rooms.get(id);
    if (!r) throw new Error('Live room not found');
    return r;
  }

  async create(input: {
    creatorId: string;
    creatorType: 'artist' | 'dj';
    title: string;
    category: string;
    coverImage?: string;
    mode: LiveRoomMode;
    status: LiveRoomStatus;
    privacy?: 'public' | 'followers';
  }): Promise<LiveRoomRecord> {
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
      } as Record<string, unknown>;

      const data = await this.insertLiveSessionWithFallback(insert);
      if (data) {
        const persisted = this.mergeCachedRecord(this.mapLiveSessionRowToRecord(data));
        const record: LiveRoomRecord = {
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

    const rec: LiveRoomRecord = {
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

  async updateStatus(id: string, status: LiveRoomStatus): Promise<LiveRoomRecord> {
    if (this.supabase.isConfigured) {
      const patch: Record<string, unknown> = {
        updated_at: new Date().toISOString(),
        status: this.mapStatusToDb(status),
      };

      if (status === LiveRoomStatus.LIVE) {
        patch.is_live = true;
        patch.started_at = new Date().toISOString();
      }

      if (status === LiveRoomStatus.ENDED || status === LiveRoomStatus.CANCELLED) {
        patch.is_live = false;
        patch.ended_at = new Date().toISOString();
      }

      const data = await this.updateLiveSessionWithFallback(id, patch);
      if (data) {
        const persisted = this.mergeCachedRecord(this.mapLiveSessionRowToRecord(data));
        const next: LiveRoomRecord = {
          ...persisted,
          status,
          updatedAt: String(data.updated_at ?? new Date().toISOString()),
        };
        this.rooms.set(id, next);
        return next;
      }
    }

    const r = await this.findById(id);
    const next: LiveRoomRecord = { ...r, status, updatedAt: new Date().toISOString() };
    this.rooms.set(id, next);
    return next;
  }

  private mapLiveSessionRowToRecord(row: any): LiveRoomRecord {
    const status = this.mapDbToStatus(row?.status, row?.is_live);
    return {
      id: String(row?.id ?? row?.channel_id),
      creatorId: String(row?.host_id ?? row?.creator_id ?? ''),
      creatorType: 'artist',
      title: String(row?.title ?? ''),
      category: String(row?.category ?? ''),
      coverImage: (row?.thumbnail_url ?? undefined) as string | undefined,
      mode: (row?.mode === LiveRoomMode.BATTLE ? LiveRoomMode.BATTLE : LiveRoomMode.SOLO) as LiveRoomMode,
      status,
      privacy: (row?.access_tier ?? row?.privacy ?? 'public') as LiveRoomRecord['privacy'],
      createdAt: String(row?.created_at ?? new Date().toISOString()),
      updatedAt: String(row?.updated_at ?? row?.created_at ?? new Date().toISOString()),
    };
  }

  private mapStatusToDb(status: LiveRoomStatus): string {
    switch (status) {
      case LiveRoomStatus.DRAFT:
      case LiveRoomStatus.SCHEDULED:
      case LiveRoomStatus.WAITING:
      case LiveRoomStatus.READY:
        return 'scheduled';
      case LiveRoomStatus.LIVE:
        return 'live';
      case LiveRoomStatus.ENDED:
        return 'ended';
      case LiveRoomStatus.CANCELLED:
        return 'cancelled';
    }
  }

  private mapDbToStatus(rawStatus: unknown, isLive: unknown): LiveRoomStatus {
    if (isLive === true) return LiveRoomStatus.LIVE;
    const s = String(rawStatus ?? '').toLowerCase();
    if (s === 'live') return LiveRoomStatus.LIVE;
    if (s === 'scheduled') return LiveRoomStatus.SCHEDULED;
    if (s === 'ended') return LiveRoomStatus.ENDED;
    if (s === 'cancelled' || s === 'canceled') return LiveRoomStatus.CANCELLED;
    return LiveRoomStatus.SCHEDULED;
  }

  private mergeCachedRecord(record: LiveRoomRecord): LiveRoomRecord {
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

  private async insertLiveSessionWithFallback(
    insert: Record<string, unknown>,
  ): Promise<Record<string, unknown> | null> {
    let candidate = this.omitColumns(insert, this.unsupportedInsertColumns, this.invalidInsertColumns);

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const { data, error } = await this.supabase.client
        .from('live_sessions')
        .insert(candidate)
        .select('*')
        .single();

      if (!error) {
        return data as Record<string, unknown>;
      }

      const missingColumn = this.extractMissingColumn(error.message);
      if (missingColumn) {
        this.unsupportedInsertColumns.add(missingColumn);
        candidate = this.omitColumns(insert, this.unsupportedInsertColumns, this.invalidInsertColumns);
        this.logger.warn(
          `Supabase create live_session retrying without unsupported column '${missingColumn}'`,
        );
        continue;
      }

      const invalidColumn = this.extractInvalidColumn(error.message, candidate);
      if (invalidColumn) {
        this.invalidInsertColumns.add(invalidColumn);
        candidate = this.omitColumns(insert, this.unsupportedInsertColumns, this.invalidInsertColumns);
        this.logger.warn(
          `Supabase create live_session retrying without invalid column '${invalidColumn}'`,
        );
        continue;
      }

      this.logger.warn(`Supabase create live_session failed: ${error.message}`);
      return null;
    }

    return null;
  }

  private async updateLiveSessionWithFallback(
    id: string,
    patch: Record<string, unknown>,
  ): Promise<Record<string, unknown> | null> {
    let candidate = this.omitColumns(patch, this.unsupportedUpdateColumns, this.invalidUpdateColumns);

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const { data, error } = await this.supabase.client
        .from('live_sessions')
        .update(candidate)
        .eq('id', id)
        .select('*')
        .maybeSingle();

      if (!error) {
        return (data ?? null) as Record<string, unknown> | null;
      }

      const missingColumn = this.extractMissingColumn(error.message);
      if (missingColumn) {
        this.unsupportedUpdateColumns.add(missingColumn);
        candidate = this.omitColumns(patch, this.unsupportedUpdateColumns, this.invalidUpdateColumns);
        this.logger.warn(
          `Supabase update live_session retrying without unsupported column '${missingColumn}'`,
        );
        continue;
      }

      const invalidColumn = this.extractInvalidColumn(error.message, candidate);
      if (invalidColumn) {
        this.invalidUpdateColumns.add(invalidColumn);
        candidate = this.omitColumns(patch, this.unsupportedUpdateColumns, this.invalidUpdateColumns);
        this.logger.warn(
          `Supabase update live_session retrying without invalid column '${invalidColumn}'`,
        );
        continue;
      }

      this.logger.warn(`Supabase updateStatus failed: ${error.message}`);
      return null;
    }

    return null;
  }

  private omitColumns(
    values: Record<string, unknown>,
    unsupported: Set<string>,
    invalid: Set<string>,
  ): Record<string, unknown> {
    return Object.fromEntries(
      Object.entries(values).filter(([key]) => !unsupported.has(key) && !invalid.has(key)),
    );
  }

  private extractMissingColumn(message: string): string | null {
    const match = /Could not find the '([^']+)' column of 'live_sessions'/.exec(message);
    return match?.[1] ?? null;
  }

  private extractInvalidColumn(
    message: string,
    candidate: Record<string, unknown>,
  ): string | null {
    if (/live_sessions_status_check/.test(message) && 'status' in candidate) {
      return 'status';
    }

    return null;
  }
}
