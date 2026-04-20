import { randomUUID } from 'crypto';

import { Injectable } from '@nestjs/common';

import { SupabaseService } from '../common/supabase/supabase.service';
import { BattleStatus } from '../orchestrator/state-machine/battle.state';

export type BattleRecord = {
  id: string;
  liveRoomId: string;
  channelId: string;
  hostId: string;
  opponentId?: string;
  hostAgoraUid?: number | null;
  opponentAgoraUid?: number | null;
  durationSeconds: number;
  coinGoal: number;
  beatName: string;
  title?: string;
  category?: string;
  country?: string;
  status: BattleStatus;
  createdAt?: string;
  updatedAt?: string;
  startedAt?: string | null;
  endedAt?: string | null;
  endsAt?: string | null;
};

export type BattleInviteRecord = {
  id: string;
  battleId: string;
  fromUserId: string;
  toUserId: string;
  status: 'PENDING' | 'ACCEPTED' | 'DECLINED' | 'EXPIRED';
  expiresAt: string;
  respondedAt?: string | null;
  createdAt: string;
};

export type FinalizedBattleRecord = {
  battle_id: string;
  host_a_id: string | null;
  host_b_id: string | null;
  host_a_score: number | null;
  host_b_score: number | null;
  host_a_payout_coins: number | null;
  host_b_payout_coins: number | null;
  winner_uid: string | null;
  winner_payout_coins: number | null;
  loser_payout_coins: number | null;
  platform_fee_coins: number | null;
  finalized_at: string | null;
};

type DbBattleStatus = 'waiting' | 'ready' | 'countdown' | 'live' | 'ended';
type DbInviteStatus = 'pending' | 'accepted' | 'declined' | 'expired';

@Injectable()
export class BattleService {
  constructor(private readonly supabase: SupabaseService) {}

  async findActiveByUser(userId: string): Promise<BattleRecord | null> {
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

  async findById(battleId: string): Promise<BattleRecord | null> {
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

  async findByLiveRoom(liveRoomId: string): Promise<BattleRecord | null> {
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

  async create(input: {
    liveRoomId: string;
    hostId: string;
    durationSeconds: number;
    coinGoal: number;
    beatName: string;
    status?: BattleStatus;
    title?: string;
    category?: string;
    country?: string;
  }): Promise<BattleRecord> {
    const battleId = randomUUID();
    const channelId = `weafrica_battle_${battleId}`;
    const hostAgoraUid = this.stableAgoraUid(input.hostId);

    const { data, error } = await this.supabase.client
      .from('live_battles')
      .insert({
        battle_id: battleId,
        live_room_id: input.liveRoomId,
        channel_id: channelId,
        status: this.toDbBattleStatus(input.status ?? BattleStatus.WAITING),
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

  async createInvite(input: { battleId: string; fromUserId: string; toUserId: string }): Promise<BattleInviteRecord> {
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

  async getInvite(inviteId: string): Promise<BattleInviteRecord | null> {
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

  async getInviteByBattleAndUser(battleId: string, toUserId: string): Promise<BattleInviteRecord | null> {
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

  async updateInviteStatus(inviteId: string, status: BattleInviteRecord['status']): Promise<BattleInviteRecord> {
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

  async getPendingInvites(userId: string): Promise<BattleInviteRecord[]> {
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

  async update(
    battleId: string,
    patch: Partial<{
      liveRoomId: string;
      channelId: string;
      hostId: string;
      opponentId: string | null;
      hostAgoraUid: number | null;
      opponentAgoraUid: number | null;
      durationSeconds: number;
      coinGoal: number;
      beatName: string;
      title: string | null;
      category: string | null;
      country: string | null;
      status: BattleStatus;
      hostReady: boolean;
      opponentReady: boolean;
      startedAt: string | null;
      endedAt: string | null;
      endsAt: string | null;
      scheduledAt: string | null;
    }>,
  ): Promise<BattleRecord> {
    const updatePayload: Record<string, unknown> = {};

    if (patch.liveRoomId !== undefined) updatePayload.live_room_id = patch.liveRoomId;
    if (patch.channelId !== undefined) updatePayload.channel_id = patch.channelId;
    if (patch.hostId !== undefined) updatePayload.host_a_id = patch.hostId;
    if (patch.opponentId !== undefined) updatePayload.host_b_id = patch.opponentId;
    if (patch.hostAgoraUid !== undefined) updatePayload.host_a_agora_uid = patch.hostAgoraUid;
    if (patch.opponentAgoraUid !== undefined) updatePayload.host_b_agora_uid = patch.opponentAgoraUid;
    if (patch.durationSeconds !== undefined) updatePayload.duration_seconds = patch.durationSeconds;
    if (patch.coinGoal !== undefined) {
      updatePayload.coin_goal = patch.coinGoal;
      updatePayload.price_coins = patch.coinGoal;
    }
    if (patch.beatName !== undefined) updatePayload.beat_name = patch.beatName;
    if (patch.title !== undefined) updatePayload.title = patch.title;
    if (patch.category !== undefined) updatePayload.category = patch.category;
    if (patch.country !== undefined) updatePayload.country = patch.country;
    if (patch.status !== undefined) updatePayload.status = this.toDbBattleStatus(patch.status);
    if (patch.hostReady !== undefined) updatePayload.host_a_ready = patch.hostReady;
    if (patch.opponentReady !== undefined) updatePayload.host_b_ready = patch.opponentReady;
    if (patch.startedAt !== undefined) updatePayload.started_at = patch.startedAt;
    if (patch.endedAt !== undefined) updatePayload.ended_at = patch.endedAt;
    if (patch.endsAt !== undefined) updatePayload.ends_at = patch.endsAt;
    if (patch.scheduledAt !== undefined) updatePayload.scheduled_at = patch.scheduledAt;

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

  async updateStatus(battleId: string, status: BattleStatus): Promise<BattleRecord> {
    return this.update(battleId, { status });
  }

  async setOpponent(battleId: string, opponentId: string): Promise<BattleRecord> {
    return this.update(battleId, {
      opponentId,
      opponentAgoraUid: this.stableAgoraUid(opponentId),
      status: BattleStatus.READY,
    });
  }

  async finalizeBattle(battleId: string): Promise<FinalizedBattleRecord> {
    const { data, error } = await this.supabase.client.rpc('battle_finalize_due', {
      p_battle_id: battleId,
    });

    if (error) {
      throw error;
    }

    return data as FinalizedBattleRecord;
  }

  async startScoringEngine(_battleId: string): Promise<void> {
    return;
  }

  async computeWinner(battleId: string): Promise<string | null> {
    const finalized = await this.finalizeBattle(battleId);
    return finalized.winner_uid;
  }

  private mapBattleRow(row: Record<string, unknown>): BattleRecord {
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

  private mapInviteRow(row: Record<string, unknown>): BattleInviteRecord {
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

  private toDbBattleStatus(status: BattleStatus): DbBattleStatus {
    switch (status) {
      case BattleStatus.WAITING:
        return 'waiting';
      case BattleStatus.READY:
        return 'ready';
      case BattleStatus.LIVE:
        return 'live';
      case BattleStatus.PAUSED:
        return 'countdown';
      case BattleStatus.ENDED:
      case BattleStatus.CANCELLED:
        return 'ended';
    }
  }

  private fromDbBattleStatus(status: string): BattleStatus {
    switch (status) {
      case 'ready':
      case 'countdown':
        return BattleStatus.READY;
      case 'live':
        return BattleStatus.LIVE;
      case 'ended':
        return BattleStatus.ENDED;
      default:
        return BattleStatus.WAITING;
    }
  }

  private toDbInviteStatus(status: BattleInviteRecord['status']): DbInviteStatus {
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

  private fromDbInviteStatus(status: string): BattleInviteRecord['status'] {
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

  private stableAgoraUid(userId: string): number {
    let hash = 0;
    for (let index = 0; index < userId.length; index += 1) {
      hash = (hash << 5) - hash + userId.charCodeAt(index);
      hash |= 0;
    }

    const uid = Math.abs(hash) % 2000000000;
    return uid === 0 ? 1 : uid;
  }

  private toNullableNumber(value: unknown): number | null {
    if (value === null || value === undefined) {
      return null;
    }

    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
}
