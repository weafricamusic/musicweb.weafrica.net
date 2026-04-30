import { Injectable } from '@nestjs/common';

export enum EngagementEventType {
  VIEW = 'view',
  LIKE = 'like',
  COMMENT = 'comment',
  GIFT = 'gift',
  SHARE = 'share',
  FOLLOW = 'follow',
}

export enum EngagementTargetType {
  LIVE = 'live',
  BATTLE = 'battle',
  SONG = 'song',
  VIDEO = 'video',
  ARTIST = 'artist',
  EVENT = 'event',
  PHOTO_POST = 'photo_post',
}

export interface EngagementData {
  userId: string;
  targetType: EngagementTargetType;
  targetId: string;
  eventType: EngagementEventType;
  metadata?: Record<string, unknown>;
}

@Injectable()
export class FeedService {
  async generateGlobalFeed() {
    // Return mock data for now
    return {
      items: [],
      total: 0,
      page: 1,
      limit: 20,
    };
  }

  async generatePersonalizedFeed(userId: string, limit: number) {
    // Return mock data for now
    return {
      items: [],
      total: 0,
      page: 1,
      limit,
      userId,
    };
  }

  async getTrending(hours: number, limit: number) {
    // Return mock data for now
    return {
      items: [],
      total: 0,
      hours,
      limit,
    };
  }

  async getRecommended(userId: string, limit: number) {
    // Return mock data for now
    return {
      items: [],
      total: 0,
      userId,
      limit,
    };
  }

  async trackEngagement(data: EngagementData) {
    // Log the engagement for now
    console.log('Tracking engagement:', data);
    return { success: true };
  }

  private parseLimit(limit?: string, defaultLimit = 20, maxLimit = 100): number {
    const parsed = parseInt(limit || '', 10);
    if (isNaN(parsed) || parsed <= 0) return defaultLimit;
    return Math.min(parsed, maxLimit);
  }

  private parseHours(hours?: string, defaultHours = 24): number {
    const parsed = parseInt(hours || '', 10);
    if (isNaN(parsed) || parsed <= 0) return defaultHours;
    return Math.min(parsed, 168); // Max 1 week
  }
}