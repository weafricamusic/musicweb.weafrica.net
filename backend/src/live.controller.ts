import { BadRequestException, Body, Controller, ForbiddenException, Get, Param, Post, UseGuards } from '@nestjs/common';

import { CurrentUser } from './auth/current-user.decorator';
import { FirebaseAuthGuard } from './auth/firebase-auth.guard';
import { FirebaseRequestUser } from './auth/firebase-auth.service';
import { ChallengeService } from './challenge/challenge.service';
import { SupabaseService } from './common/supabase/supabase.service';
import { LiveGateway } from './gateways/live.gateway';
import { OrchestratorService } from './orchestrator/orchestrator.service';

@Controller('live')
export class LiveController {
  constructor(
    private readonly orchestrator: OrchestratorService,
    private readonly challengeService: ChallengeService,
    private readonly liveGateway: LiveGateway,
    private readonly supabase: SupabaseService,
  ) {}

  @Post('start')
  @UseGuards(FirebaseAuthGuard)
  async startLive(
    @CurrentUser() user: FirebaseRequestUser,
    @Body() body: { title?: string; category?: string; coverImage?: string; privacy?: 'public' | 'followers' },
  ) {
    if (!this.supabase.isConfigured) {
      throw new BadRequestException('Supabase is not configured on this server');
    }

    const { data: profile, error } = await this.supabase.client
      .from('profiles')
      .select('*')
      .eq('id', user.uid)
      .maybeSingle();

    if (error) {
      throw new BadRequestException(`Failed to load user profile: ${error.message}`);
    }

    const rawType = String((profile as any)?.user_type ?? (profile as any)?.role ?? '').trim().toLowerCase();
    const userType = rawType === 'artist' ? 'artist' : rawType === 'dj' ? 'dj' : null;

    if (!userType) {
      throw new ForbiddenException('Only artists and DJs can go live');
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
        hostName: (profile as any)?.name ?? (profile as any)?.stage_name ?? (profile as any)?.display_name ?? null,
        hostAvatar: (profile as any)?.avatar_url ?? null,
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

  @Post('challenge/:userId')
  @UseGuards(FirebaseAuthGuard)
  async challengeUser(
    @CurrentUser() user: FirebaseRequestUser,
    @Param('userId') targetUserId: string,
    @Body() body: { message?: string; metadata?: Record<string, unknown> },
  ) {
    const challenge = await this.challengeService.challengeUser(
      user.uid,
      targetUserId,
      body?.message,
      body?.metadata,
    );

    this.liveGateway.emitChallengeSent({
      challengeId: String((challenge as any)?.id ?? ''),
      targetUserId,
      challengeData: challenge,
    });

    return challenge;
  }

  @Post('accept-challenge/:challengeId')
  @UseGuards(FirebaseAuthGuard)
  async acceptChallenge(
    @CurrentUser() user: FirebaseRequestUser,
    @Param('challengeId') challengeId: string,
  ) {
    const result = await this.challengeService.acceptChallenge(challengeId, user.uid);

    if ((result as any)?.success === true) {
      const streamId = String((result as any)?.streamSessionId ?? (result as any)?.liveRoomId ?? '');
      this.liveGateway.emitChallengeAccepted({
        challengeId,
        streamId,
      });
    }

    return result;
  }

  @Get('active')
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
      throw new BadRequestException(error.message);
    }

    return (data ?? []).map((session: any) => ({
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

  @Get('challenges/pending')
  @UseGuards(FirebaseAuthGuard)
  async getPendingChallenges(@CurrentUser() user: FirebaseRequestUser) {
    return this.challengeService.getPendingChallenges(user.uid);
  }
}
