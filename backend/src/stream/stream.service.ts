import { Injectable, Logger } from '@nestjs/common';

import { SupabaseService } from '../common/supabase/supabase.service';
import { AgoraService } from './agora/agora.service';

export type StreamSessionRecord = {
  id: string;
  liveRoomId: string;
  channelId: string;
  participants: string[];
  status: 'CREATED' | 'ACTIVE' | 'DISCONNECTED' | 'CLOSED';
  startedAt?: string | null;
  endedAt?: string | null;
  viewerCount: number;
  peakViewers: number;
  metadata: Record<string, unknown>;
};

@Injectable()
export class StreamService {
  private readonly logger = new Logger(StreamService.name);
  private readonly sessions = new Map<string, StreamSessionRecord>();

  constructor(
    private readonly agora: AgoraService,
    private readonly supabase: SupabaseService,
  ) {}

  async create(input: { liveRoomId: string; participants?: string[]; status: StreamSessionRecord['status'] }): Promise<StreamSessionRecord> {
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
      } else if (data) {
        const record = this.mapRowToRecord(data);
        this.sessions.set(record.id, record);
        return record;
      }
    }

    const rec: StreamSessionRecord = {
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

  async findById(streamSessionId: string): Promise<StreamSessionRecord | null> {
    if (this.supabase.isConfigured) {
      const { data, error } = await this.supabase.client
        .from('stream_sessions')
        .select('*')
        .eq('id', streamSessionId)
        .maybeSingle();

      if (error) {
        this.logger.warn(`Supabase find stream_session failed: ${error.message}`);
      } else if (data) {
        const record = this.mergeCachedRecord(this.mapRowToRecord(data));
        this.sessions.set(record.id, record);
        return record;
      }
    }

    return this.sessions.get(streamSessionId) ?? null;
  }

  async findByLiveRoom(liveRoomId: string): Promise<StreamSessionRecord | null> {
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
      } else if (data) {
        const record = this.mergeCachedRecord(this.mapRowToRecord(data));
        this.sessions.set(record.id, record);
        return record;
      }
    }

    const matches = [...this.sessions.values()].filter((session) => session.liveRoomId === liveRoomId);
    return matches.at(-1) ?? null;
  }

  async generateToken(input: { channelId: string; userId: string; role?: 'broadcaster' | 'audience' }): Promise<string> {
    return this.agora.generateRtcToken({
      channelId: input.channelId,
      uid: input.userId,
      role: input.role ?? 'broadcaster',
    });
  }

  async updateStatus(streamSessionId: string, status: StreamSessionRecord['status']): Promise<StreamSessionRecord> {
    const ss = await this.findById(streamSessionId);
    if (!ss) throw new Error('Stream session not found');

    const now = new Date().toISOString();
    const patch: Record<string, unknown> = { status, updated_at: now };
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
      } else if (data) {
        const record = this.mergeCachedRecord(this.mapRowToRecord(data));
        this.sessions.set(record.id, record);
        return record;
      }
    }

    const next: StreamSessionRecord = {
      ...ss,
      status,
      startedAt: (patch.started_at as string | undefined) ?? ss.startedAt ?? null,
      endedAt: (patch.ended_at as string | undefined) ?? ss.endedAt ?? null,
    };
    this.sessions.set(streamSessionId, next);
    return next;
  }

  async updateStatusByLiveRoom(liveRoomId: string, status: StreamSessionRecord['status']): Promise<void> {
    const session = await this.findByLiveRoom(liveRoomId);
    if (!session) {
      return;
    }

    await this.updateStatus(session.id, status);
  }

  async updateViewerCount(streamSessionId: string, viewerCount: number): Promise<void> {
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

  async addParticipant(streamSessionId: string, userId: string): Promise<StreamSessionRecord> {
    const session = await this.findById(streamSessionId);
    if (!session) {
      throw new Error('Stream session not found');
    }

    const participants = session.participants.includes(userId)
      ? session.participants
      : [...session.participants, userId];

    return this.updateParticipants(streamSessionId, participants, session);
  }

  async removeParticipant(streamSessionId: string, userId: string): Promise<StreamSessionRecord> {
    const session = await this.findById(streamSessionId);
    if (!session) {
      throw new Error('Stream session not found');
    }

    const participants = session.participants.filter((participant) => participant !== userId);
    return this.updateParticipants(streamSessionId, participants, session);
  }

  async getStreamAnalytics(streamSessionId: string): Promise<{
    sessionId: string;
    liveRoomId: string;
    status: StreamSessionRecord['status'];
    durationSeconds: number | null;
    totalParticipants: number;
    peakViewers: number;
    startedAt?: string | null;
    endedAt?: string | null;
  }> {
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

  private async updateParticipants(
    streamSessionId: string,
    participants: string[],
    existing: StreamSessionRecord,
  ): Promise<StreamSessionRecord> {
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
      } else if (data) {
        const record = this.mergeCachedRecord(this.mapRowToRecord(data));
        this.sessions.set(record.id, record);
        return record;
      }
    }

    const next: StreamSessionRecord = { ...existing, participants };
    this.sessions.set(streamSessionId, next);
    return next;
  }

  private mapRowToRecord(row: Record<string, unknown>): StreamSessionRecord {
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

  private mergeCachedRecord(record: StreamSessionRecord): StreamSessionRecord {
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

  private toStatus(value: unknown): StreamSessionRecord['status'] {
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

  private toMetadata(value: unknown): Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return {};
    }

    return value as Record<string, unknown>;
  }
}
