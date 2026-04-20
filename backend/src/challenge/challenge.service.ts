import { BadRequestException, ForbiddenException, Injectable, Logger } from '@nestjs/common';

import { SupabaseService } from '../common/supabase/supabase.service';
import { LiveRoomService } from '../live-room/live-room.service';
import { StreamService } from '../stream/stream.service';
import { LiveRoomStatus } from '../orchestrator/state-machine/live-room.state';

type ProfileRow = Record<string, unknown>;

type StreamChallengeRow = {
  id: string;
  challenger_id: string;
  target_id: string;
  live_room_id: string;
  status: string;
  message?: string | null;
  metadata?: Record<string, unknown> | null;
  expires_at: string;
  created_at?: string;
  updated_at?: string;
};

@Injectable()
export class ChallengeService {
  private readonly logger = new Logger(ChallengeService.name);

  constructor(
    private readonly supabase: SupabaseService,
    private readonly streamService: StreamService,
    private readonly liveRoomService: LiveRoomService,
  ) {}

  async challengeUser(
    challengerId: string,
    targetUserId: string,
    message?: string,
    metadata?: Record<string, unknown>,
  ) {
    this.ensureSupabase();

    const challengerProfile = await this.getProfile(challengerId);
    const challengerType = this.getCreatorType(challengerProfile);

    if (!challengerType) {
      throw new ForbiddenException('Only artists and DJs can challenge others');
    }

    const activeRoom = await this.liveRoomService.findActiveByUser(targetUserId);
    if (!activeRoom || activeRoom.status !== LiveRoomStatus.LIVE) {
      throw new BadRequestException('User is not currently live');
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
      throw new BadRequestException('You already have a pending challenge to this user');
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
      throw new BadRequestException('Failed to create challenge');
    }

    const targetProfile = await this.getProfile(targetUserId);

    return {
      ...data,
      challenger: challengerProfile,
      target: targetProfile,
    };
  }

  async acceptChallenge(challengeId: string, userId: string) {
    this.ensureSupabase();

    const { data: challenge, error: fetchError } = await this.supabase.client
      .from('stream_challenges')
      .select('*')
      .eq('id', challengeId)
      .maybeSingle();

    if (fetchError || !challenge) {
      throw new BadRequestException('Challenge not found');
    }

    const ch = challenge as StreamChallengeRow;

    if (ch.target_id !== userId) {
      throw new ForbiddenException('This challenge is not for you');
    }

    if (String(ch.status) !== 'pending') {
      throw new BadRequestException('Challenge already responded to');
    }

    if (new Date(ch.expires_at) < new Date()) {
      await this.supabase.client
        .from('stream_challenges')
        .update({ status: 'expired', updated_at: new Date().toISOString() })
        .eq('id', challengeId);

      throw new BadRequestException('Challenge has expired');
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
      } catch (e) {
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

  async getPendingChallenges(userId: string) {
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

    const rows = (data ?? []) as StreamChallengeRow[];
    const challengerIds = [...new Set(rows.map((row) => String(row.challenger_id)).filter(Boolean))];

    const challengerProfiles = new Map<string, ProfileRow>();
    if (challengerIds.length > 0) {
      const { data: profiles, error: profileErr } = await this.supabase.client
        .from('profiles')
        .select('*')
        .in('id', challengerIds);

      if (profileErr) {
        this.logger.warn(`Error fetching challenger profiles: ${profileErr.message}`);
      } else {
        (profiles ?? []).forEach((p: any) => {
          const id = String(p?.id ?? '');
          if (id) challengerProfiles.set(id, p as ProfileRow);
        });
      }
    }

    return rows.map((row) => ({
      ...row,
      challenger: challengerProfiles.get(String(row.challenger_id)) ?? null,
    }));
  }

  private ensureSupabase() {
    if (!this.supabase.isConfigured) {
      throw new BadRequestException('Supabase is not configured on this server');
    }
  }

  private async getProfile(userId: string): Promise<ProfileRow> {
    const { data, error } = await this.supabase.client
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle();

    if (error) {
      this.logger.warn(`Error fetching profile(${userId}): ${error.message}`);
      return { id: userId };
    }

    return (data ?? { id: userId }) as ProfileRow;
  }

  private getCreatorType(profile: ProfileRow): 'artist' | 'dj' | null {
    const raw = this.firstString(
      (profile as any)?.user_type,
      (profile as any)?.role,
      (profile as any)?.userType,
      (profile as any)?.type,
    );

    const normalized = raw.trim().toLowerCase();
    if (normalized === 'artist') return 'artist';
    if (normalized === 'dj') return 'dj';
    return null;
  }

  private firstString(...values: unknown[]): string {
    for (const v of values) {
      if (typeof v === 'string' && v.trim().length > 0) {
        return v;
      }
    }
    return '';
  }

  private async updateLiveSessionBattleMode(liveRoomId: string, challengerId: string): Promise<void> {
    const now = new Date().toISOString();

    // Some schemas may not include challenger_id; treat it as best-effort.
    const patch: Record<string, unknown> = {
      mode: 'battle',
      challenger_id: challengerId,
      updated_at: now,
    };

    try {
      const { error } = await this.supabase.client
        .from('live_sessions')
        .update(patch)
        .eq('id', liveRoomId);

      if (!error) return;

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
    } catch (e) {
      this.logger.warn(`Failed to update live_session battle mode (exception): ${String(e)}`);
    }
  }
}
