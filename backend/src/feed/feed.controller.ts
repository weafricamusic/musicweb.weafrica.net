import { BadRequestException, Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { FirebaseRequestUser } from '../auth/firebase-auth.service';
import { EngagementEventType, EngagementTargetType, FeedService } from './feed.service';

@Controller('api/feed')
export class FeedController {
  constructor(private readonly feedService: FeedService) { }

  @Get('global')
  async getGlobalFeed() {
    return this.feedService.generateGlobalFeed();
  }

  @UseGuards(FirebaseAuthGuard)
  @Get('personal')
  async getPersonalFeed(
    @CurrentUser() user: FirebaseRequestUser,
    @Query('limit') limit?: string,
  ) {
    return this.feedService.generatePersonalizedFeed(user.uid, this.parseLimit(limit, 50, 200));
  }

  @Get('trending')
  async getTrending(
    @Query('hours') hours?: string,
    @Query('limit') limit?: string,
  ) {
    return this.feedService.getTrending(this.parseHours(hours, 24), this.parseLimit(limit, 20, 100));
  }

  @UseGuards(FirebaseAuthGuard)
  @Get('recommended')
  async getRecommended(
    @CurrentUser() user: FirebaseRequestUser,
    @Query('limit') limit?: string,
  ) {
    return this.feedService.getRecommended(user.uid, this.parseLimit(limit, 20, 100));
  }

  @UseGuards(FirebaseAuthGuard)
  @Post('track')
  async trackEngagement(
    @CurrentUser() user: FirebaseRequestUser,
    @Body()
    body: {
      targetType?: EngagementTargetType;
      targetId?: string;
      eventType?: EngagementEventType;
      metadata?: Record<string, unknown>;
    },
  ) {
    const targetType = String(body.targetType ?? '').trim() as EngagementTargetType;
    const targetId = String(body.targetId ?? '').trim();
    const eventType = String(body.eventType ?? '').trim() as EngagementEventType;

    if (!['live', 'battle', 'song', 'video', 'artist', 'event', 'photo_post'].includes(targetType)) {
      throw new BadRequestException('Invalid targetType');
    }

    if (!targetId) {
      throw new BadRequestException('Missing targetId');
    }

    if (!['view', 'like', 'comment', 'gift', 'share', 'follow'].includes(eventType)) {
      throw new BadRequestException('Invalid eventType');
    }

    await this.feedService.trackEngagement({
      userId: user.uid,
      targetType,
      targetId,
      eventType,
      metadata: body.metadata,
    });

    return { success: true };
  }

  private parseLimit(value: string | undefined, fallback: number, max: number): number {
    const parsed = Number(value ?? fallback);
    if (!Number.isFinite(parsed)) {
      return fallback;
    }

    return Math.max(1, Math.min(max, Math.floor(parsed)));
  }

  private parseHours(value: string | undefined, fallback: number): number {
    const parsed = Number(value ?? fallback);
    if (!Number.isFinite(parsed)) {
      return fallback;
    }

    return Math.max(1, Math.min(24 * 30, Math.floor(parsed)));
  }
}