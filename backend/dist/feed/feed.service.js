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
var FeedService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.FeedService = void 0;
const common_1 = require("@nestjs/common");
const redis_service_1 = require("../common/redis/redis.service");
const supabase_service_1 = require("../common/supabase/supabase.service");
let FeedService = FeedService_1 = class FeedService {
    constructor(supabase, redis) {
        this.supabase = supabase;
        this.redis = redis;
        this.logger = new common_1.Logger(FeedService_1.name);
        this.cacheTtlSeconds = 60;
        this.maxCacheScanKeys = 500;
    }
    async generateGlobalFeed(limit = 50) {
        const normalizedLimit = this.normalizeLimit(limit, 50, 200);
        const cacheKey = this.globalCacheKey(normalizedLimit);
        const cached = await this.readCachedFeed(cacheKey);
        if (cached) {
            return cached;
        }
        const [lives, battles, songs, videos, events, photoPosts] = await Promise.all([
            this.scoreLiveStreams(),
            this.scoreBattles(),
            this.scoreSongs(),
            this.scoreVideos(),
            this.scoreEvents(),
            this.scorePhotoPosts(),
        ]);
        const merged = [...lives, ...battles, ...songs, ...videos, ...events, ...photoPosts]
            .sort((left, right) => right.score - left.score)
            .slice(0, normalizedLimit);
        await this.persistFeedItems(merged);
        await this.writeCachedFeed(cacheKey, merged);
        return merged;
    }
    async generatePersonalizedFeed(userId, limit = 50) {
        const normalizedLimit = this.normalizeLimit(limit, 50, 200);
        const cacheKey = this.personalCacheKey(userId, normalizedLimit);
        const cached = await this.readCachedFeed(cacheKey);
        if (cached) {
            return cached;
        }
        const [globalFeed, userInterests, seenItems] = await Promise.all([
            this.generateGlobalFeed(normalizedLimit * 2),
            this.getUserInterests(userId),
            this.getSeenFeedItemIds(userId),
        ]);
        const personalized = globalFeed
            .map((item) => ({
            ...item,
            score: this.applyPersonalization(item, userInterests, seenItems),
        }))
            .sort((left, right) => right.score - left.score)
            .slice(0, normalizedLimit);
        await this.persistFeedItems(personalized);
        await this.syncUserFeed(userId, personalized);
        await this.writeCachedFeed(cacheKey, personalized);
        return personalized;
    }
    async trackEngagement(data) {
        try {
            const { error } = await this.supabase.client
                .from('engagement_events')
                .insert({
                user_id: data.userId,
                target_type: data.targetType,
                target_id: data.targetId,
                event_type: data.eventType,
                metadata: data.metadata ?? {},
                created_at: new Date().toISOString(),
            });
            if (error) {
                if (!this.isMissingFeedTableError(error)) {
                    this.logger.error(`Failed to track engagement: ${error.message}`);
                }
            }
        }
        catch (error) {
            this.logger.error(`Failed to insert engagement event: ${this.stringifyError(error)}`);
        }
        if (data.targetType !== 'artist') {
            await this.updateFeedItemCounts(data.targetType, data.targetId, data.eventType);
            await this.markUserFeedEngagement(data.userId, data.targetType, data.targetId, data.eventType);
        }
        await this.invalidateCaches(data.userId);
    }
    async getTrending(periodHours = 24, limit = 20) {
        const normalizedLimit = this.normalizeLimit(limit, 20, 100);
        const cutoffIso = new Date(Date.now() - (Math.max(periodHours, 1) * 60 * 60 * 1000)).toISOString();
        try {
            const { data, error } = await this.supabase.client
                .from('feed_items')
                .select('*')
                .gte('created_at', cutoffIso)
                .order('score', { ascending: false })
                .order('created_at', { ascending: false })
                .limit(normalizedLimit);
            if (error) {
                if (this.isMissingFeedTableError(error)) {
                    return this.generateGlobalFeed(normalizedLimit);
                }
                this.logger.error(`Failed to get trending feed items: ${error.message}`);
                return this.generateGlobalFeed(normalizedLimit);
            }
            const items = (data ?? [])
                .map((row) => this.mapPersistedFeedItem(row))
                .filter((item) => this.isNotExpired(item))
                .slice(0, normalizedLimit);
            if (items.length > 0) {
                return items;
            }
        }
        catch (error) {
            this.logger.warn(`Trending query fell back to generated feed: ${this.stringifyError(error)}`);
        }
        return this.generateGlobalFeed(normalizedLimit);
    }
    async getRecommended(userId, limit = 20) {
        return this.generatePersonalizedFeed(userId, limit);
    }
    async scoreLiveStreams() {
        const strictSelect = 'id,channel_id,host_id,host_name,title,viewer_count,thumbnail_url,started_at,created_at,trending_score,access_tier';
        const fallbackSelect = 'id,channel_id,host_id,host_name,title,viewer_count,thumbnail_url,started_at,created_at,access_tier';
        let rows = [];
        try {
            const { data, error } = await this.supabase.client
                .from('live_sessions')
                .select(strictSelect)
                .eq('is_live', true)
                .order('trending_score', { ascending: false })
                .order('viewer_count', { ascending: false })
                .order('started_at', { ascending: false })
                .limit(24);
            if (error) {
                throw error;
            }
            rows = (data ?? []);
        }
        catch (error) {
            if (!this.isMissingColumnError(error, 'trending_score')) {
                this.logger.warn(`Falling back in live scoring: ${this.stringifyError(error)}`);
            }
            try {
                const { data, error: fallbackError } = await this.supabase.client
                    .from('live_sessions')
                    .select(fallbackSelect)
                    .eq('is_live', true)
                    .order('viewer_count', { ascending: false })
                    .order('started_at', { ascending: false })
                    .limit(24);
                if (fallbackError) {
                    throw fallbackError;
                }
                rows = (data ?? []);
            }
            catch (fallbackError) {
                this.logger.error(`Failed to score live streams: ${this.stringifyError(fallbackError)}`);
                return [];
            }
        }
        return rows
            .filter((row) => this.asString(row.channel_id).length > 0)
            .map((row) => {
            const viewers = this.asNumber(row.viewer_count);
            const createdAt = this.asString(row.started_at) || this.asString(row.created_at) || new Date().toISOString();
            const persistedTrendingScore = this.asNumber(row.trending_score);
            const score = Math.max(persistedTrendingScore, this.calculateLiveScore(viewers, createdAt));
            return {
                id: `live_${this.asString(row.id)}`,
                type: 'live',
                itemId: this.asString(row.id),
                creatorId: this.asString(row.host_id) || undefined,
                title: this.asString(row.title) || this.asString(row.host_name) || 'Live now',
                thumbnailUrl: this.asString(row.thumbnail_url) || undefined,
                score,
                viewCount: viewers,
                likeCount: 0,
                commentCount: 0,
                giftCount: 0,
                createdAt,
                metadata: {
                    channelId: this.asString(row.channel_id),
                    hostName: this.asString(row.host_name) || undefined,
                    accessTier: this.asString(row.access_tier) || undefined,
                    trendingScore: persistedTrendingScore,
                },
            };
        });
    }
    async scoreBattles() {
        try {
            const { data, error } = await this.supabase.client
                .from('live_battles')
                .select('battle_id,title,host_a_id,host_b_id,status,created_at,started_at,host_a_score,host_b_score,channel_id,access_tier')
                .eq('status', 'live')
                .order('created_at', { ascending: false })
                .limit(24);
            if (error) {
                throw error;
            }
            return (data ?? []).map((row) => {
                const scoreA = this.asNumber(row.host_a_score);
                const scoreB = this.asNumber(row.host_b_score);
                return {
                    id: `battle_${this.asString(row.battle_id)}`,
                    type: 'battle',
                    itemId: this.asString(row.battle_id),
                    creatorId: this.asString(row.host_a_id) || undefined,
                    title: this.asString(row.title) || 'Live battle',
                    score: this.calculateBattleScore(scoreA, scoreB, this.asString(row.created_at) || this.asString(row.started_at)),
                    viewCount: 0,
                    likeCount: 0,
                    commentCount: 0,
                    giftCount: scoreA + scoreB,
                    createdAt: this.asString(row.started_at) || this.asString(row.created_at) || undefined,
                    metadata: {
                        channelId: this.asString(row.channel_id) || undefined,
                        hostAId: this.asString(row.host_a_id) || undefined,
                        hostBId: this.asString(row.host_b_id) || undefined,
                        accessTier: this.asString(row.access_tier) || undefined,
                        hostAScore: scoreA,
                        hostBScore: scoreB,
                    },
                };
            });
        }
        catch (error) {
            this.logger.error(`Failed to score battles: ${this.stringifyError(error)}`);
            return [];
        }
    }
    async scoreSongs() {
        const select = 'id,title,artist,artist_id,artists(name),thumbnail_url,thumbnail,image_url,artwork_url,plays_count,plays,streams,likes,likes_count,created_at';
        const attempts = [
            { includeApproved: true, includeIsPublic: true, includeStatus: true, orderByPlays: true },
            { includeApproved: false, includeIsPublic: true, includeStatus: true, orderByPlays: true },
            { includeApproved: false, includeIsPublic: false, includeStatus: true, orderByPlays: true },
            { includeApproved: false, includeIsPublic: false, includeStatus: false, orderByPlays: true },
            { includeApproved: false, includeIsPublic: false, includeStatus: false, orderByPlays: false },
        ];
        for (const attempt of attempts) {
            try {
                let query = this.supabase.client.from('songs').select(select);
                if (attempt.includeStatus) {
                    query = query.eq('status', 'active');
                }
                else {
                    query = query.eq('is_active', true);
                }
                if (attempt.includeApproved) {
                    query = query.eq('approved', true);
                }
                if (attempt.includeIsPublic) {
                    query = query.eq('is_public', true);
                }
                query = attempt.orderByPlays
                    ? query.order('plays_count', { ascending: false })
                    : query.order('created_at', { ascending: false });
                const { data, error } = await query.limit(24);
                if (error) {
                    throw error;
                }
                const rows = Array.isArray(data) ? data : [];
                return rows.map((row) => {
                    const plays = this.firstDefinedNumber(row.plays_count, row.plays, row.streams);
                    const likes = this.firstDefinedNumber(row.likes_count, row.likes);
                    return {
                        id: `song_${this.asString(row.id)}`,
                        type: 'song',
                        itemId: this.asString(row.id),
                        creatorId: this.asString(row.artist_id) || this.asString(row.artist) || undefined,
                        title: this.asString(row.title) || 'Untitled song',
                        thumbnailUrl: this.pickArtwork(row),
                        score: this.calculateSongScore(plays, likes, this.asString(row.created_at)),
                        viewCount: plays,
                        likeCount: likes,
                        commentCount: 0,
                        giftCount: 0,
                        createdAt: this.asString(row.created_at) || undefined,
                        metadata: {
                            artistName: this.pickArtistName(row) || undefined,
                        },
                    };
                });
            }
            catch (error) {
                if (!this.isRecoverableContentQueryError(error)) {
                    this.logger.error(`Failed to score songs: ${this.stringifyError(error)}`);
                    return [];
                }
            }
        }
        return [];
    }
    async scoreVideos() {
        const select = 'id,title,artist_id,artist_uid,user_id,owner_id,thumbnail_url,thumbnail,image_url,artwork_url,views,views_count,likes,likes_count,comments,comments_count,created_at,status';
        const attempts = [
            { includeStatus: true, orderByViews: true },
            { includeStatus: false, orderByViews: true },
            { includeStatus: false, orderByViews: false },
        ];
        for (const attempt of attempts) {
            try {
                let query = this.supabase.client.from('videos').select(select);
                if (attempt.includeStatus) {
                    query = query.eq('status', 'active');
                }
                query = attempt.orderByViews
                    ? query.order('views', { ascending: false })
                    : query.order('created_at', { ascending: false });
                const { data, error } = await query.limit(24);
                if (error) {
                    throw error;
                }
                return (data ?? []).map((row) => {
                    const views = this.firstDefinedNumber(row.views, row.views_count);
                    const likes = this.firstDefinedNumber(row.likes_count, row.likes);
                    const comments = this.firstDefinedNumber(row.comments_count, row.comments);
                    return {
                        id: `video_${this.asString(row.id)}`,
                        type: 'video',
                        itemId: this.asString(row.id),
                        creatorId: this.asString(row.artist_id) || this.asString(row.artist_uid) || this.asString(row.user_id) || this.asString(row.owner_id) || undefined,
                        title: this.asString(row.title) || 'Untitled video',
                        thumbnailUrl: this.pickArtwork(row),
                        score: this.calculateVideoScore(views, likes, comments, this.asString(row.created_at)),
                        viewCount: views,
                        likeCount: likes,
                        commentCount: comments,
                        giftCount: 0,
                        createdAt: this.asString(row.created_at) || undefined,
                    };
                });
            }
            catch (error) {
                if (!this.isRecoverableContentQueryError(error)) {
                    this.logger.error(`Failed to score videos: ${this.stringifyError(error)}`);
                    return [];
                }
            }
        }
        return [];
    }
    async scoreEvents() {
        const ticketingAttempts = [
            'id,title,host_user_id,published_at,created_at,access_channel_id',
            'id,title,host_user_id,created_at',
        ];
        for (const select of ticketingAttempts) {
            try {
                let query = this.supabase.client.from('ticketing_events').select(select);
                if (select.includes('published_at')) {
                    query = query.not('published_at', 'is', null).order('published_at', { ascending: false });
                }
                else {
                    query = query.order('created_at', { ascending: false });
                }
                const { data, error } = await query.limit(12);
                if (error) {
                    throw error;
                }
                return (data ?? []).map((row) => {
                    const createdAt = this.asString(row.published_at) || this.asString(row.created_at) || new Date().toISOString();
                    return {
                        id: `event_${this.asString(row.id)}`,
                        type: 'event',
                        itemId: this.asString(row.id),
                        creatorId: this.asString(row.host_user_id) || undefined,
                        title: this.asString(row.title) || 'Event',
                        score: this.calculateEventScore(createdAt),
                        viewCount: 0,
                        likeCount: 0,
                        commentCount: 0,
                        giftCount: 0,
                        createdAt,
                        metadata: {
                            accessChannelId: this.asString(row.access_channel_id) || undefined,
                        },
                    };
                });
            }
            catch (error) {
                if (!this.isMissingTableError(error)) {
                    this.logger.warn(`Ticketing events feed fallback triggered: ${this.stringifyError(error)}`);
                }
            }
        }
        try {
            const { data, error } = await this.supabase.client
                .from('events')
                .select('id,title,host_name,starts_at,created_at,is_live')
                .order('starts_at', { ascending: true })
                .limit(12);
            if (error) {
                throw error;
            }
            return (data ?? []).map((row) => {
                const createdAt = this.asString(row.starts_at) || this.asString(row.created_at) || new Date().toISOString();
                return {
                    id: `event_${this.asString(row.id)}`,
                    type: 'event',
                    itemId: this.asString(row.id),
                    title: this.asString(row.title) || this.asString(row.host_name) || 'Event',
                    score: this.calculateEventScore(createdAt),
                    viewCount: this.asBoolean(row.is_live) ? 1 : 0,
                    likeCount: 0,
                    commentCount: 0,
                    giftCount: 0,
                    createdAt,
                };
            });
        }
        catch (error) {
            if (!this.isMissingTableError(error)) {
                this.logger.warn(`Failed to score events: ${this.stringifyError(error)}`);
            }
            return [];
        }
    }
    async scorePhotoPosts() {
        try {
            const { data, error } = await this.supabase.client
                .from('photo_song_posts')
                .select('id,creator_uid,image_url,song_id,song_start,song_duration,caption,likes_count,comments_count,created_at')
                .order('created_at', { ascending: false })
                .limit(24);
            if (error) {
                throw error;
            }
            return (data ?? []).map((row) => {
                const likes = this.asNumber(row.likes_count);
                const comments = this.asNumber(row.comments_count);
                const createdAt = this.asString(row.created_at) || new Date().toISOString();
                return {
                    id: `photo_post_${this.asString(row.id)}`,
                    type: 'photo_post',
                    itemId: this.asString(row.id),
                    creatorId: this.asString(row.creator_uid) || undefined,
                    title: this.asString(row.caption) || 'Photo + Song',
                    thumbnailUrl: this.asString(row.image_url) || undefined,
                    score: this.calculatePhotoPostScore(likes, comments, createdAt),
                    viewCount: 0,
                    likeCount: likes,
                    commentCount: comments,
                    giftCount: 0,
                    createdAt,
                    metadata: {
                        songId: this.asString(row.song_id) || undefined,
                        songStart: this.asNumber(row.song_start),
                        songDuration: this.asNumber(row.song_duration),
                    },
                };
            });
        }
        catch (error) {
            if (!this.isMissingTableError(error)) {
                this.logger.warn(`Failed to score photo posts: ${this.stringifyError(error)}`);
            }
            return [];
        }
    }
    calculateLiveScore(viewers, createdAt) {
        const ageHours = Math.max(0, (Date.now() - new Date(createdAt).getTime()) / (1000 * 60 * 60));
        const freshness = Math.max(0.2, 1 - (ageHours / 24));
        return (viewers * 2) * (1 + freshness);
    }
    calculateBattleScore(scoreA, scoreB, createdAt) {
        const totalScore = scoreA + scoreB;
        const intensity = totalScore > 0 ? Math.abs(scoreA - scoreB) / totalScore : 0;
        const recencyBoost = createdAt ? Math.max(0.2, 1 - (((Date.now() - new Date(createdAt).getTime()) / (1000 * 60 * 60)) / 24)) : 1;
        return totalScore * (1 + intensity) * recencyBoost;
    }
    calculateSongScore(plays, likes, createdAt) {
        return (plays * 1) + (likes * 2) + this.recencyScore(createdAt, 14, 25);
    }
    calculateVideoScore(views, likes, comments, createdAt) {
        return views + (likes * 2) + comments + this.recencyScore(createdAt, 14, 20);
    }
    calculateEventScore(createdAt) {
        return this.recencyScore(createdAt, 7, 40);
    }
    calculatePhotoPostScore(likes, comments, createdAt) {
        return (likes * 2) + (comments * 3) + this.recencyScore(createdAt, 10, 30);
    }
    async getUserInterests(userId) {
        try {
            const { data, error } = await this.supabase.client
                .from('engagement_events')
                .select('target_type,target_id,event_type')
                .eq('user_id', userId)
                .order('created_at', { ascending: false })
                .limit(200);
            if (error) {
                if (!this.isMissingFeedTableError(error)) {
                    this.logger.warn(`Failed to read engagement history: ${error.message}`);
                }
                return new Map();
            }
            const interests = new Map();
            for (const event of (data ?? [])) {
                const key = `${this.asString(event.target_type)}:${this.asString(event.target_id)}`;
                if (!key.includes(':') || key.endsWith(':')) {
                    continue;
                }
                const weight = this.engagementWeight(this.asString(event.event_type));
                interests.set(key, (interests.get(key) ?? 0) + weight);
            }
            return interests;
        }
        catch (error) {
            this.logger.warn(`Engagement history fallback for ${userId}: ${this.stringifyError(error)}`);
            return new Map();
        }
    }
    async getSeenFeedItemIds(userId) {
        try {
            const { data, error } = await this.supabase.client
                .from('user_feed')
                .select('feed_item_id, feed_items!inner(item_type,item_id)')
                .eq('user_id', userId)
                .eq('seen', true)
                .order('updated_at', { ascending: false })
                .limit(200);
            if (error) {
                if (!this.isMissingFeedTableError(error)) {
                    this.logger.warn(`Failed to load user seen feed history: ${error.message}`);
                }
                return new Set();
            }
            return new Set((data ?? [])
                .map((row) => {
                const feedItems = row.feed_items;
                if (!feedItems || Array.isArray(feedItems)) {
                    return '';
                }
                const item = feedItems;
                const type = this.asString(item.item_type);
                const itemId = this.asString(item.item_id);
                return type && itemId ? `${type}:${itemId}` : '';
            })
                .filter((value) => value.length > 0));
        }
        catch (error) {
            this.logger.warn(`Seen-feed fallback for ${userId}: ${this.stringifyError(error)}`);
            return new Set();
        }
    }
    applyPersonalization(item, interests, seenItems) {
        const itemKey = `${item.type}:${item.itemId}`;
        const creatorKey = item.creatorId ? `artist:${item.creatorId}` : '';
        const itemBoost = interests.get(itemKey) ?? 0;
        const creatorBoost = creatorKey ? (interests.get(creatorKey) ?? 0) * 0.5 : 0;
        const seenPenalty = seenItems.has(itemKey) ? 0.65 : 1;
        return item.score * (1 + ((itemBoost + creatorBoost) / 10)) * seenPenalty;
    }
    async updateFeedItemCounts(type, itemId, eventType) {
        const field = this.counterFieldForEvent(eventType);
        if (!field) {
            return;
        }
        try {
            const { error } = await this.supabase.client.rpc('increment_feed_item_count', {
                p_type: type,
                p_item_id: itemId,
                p_field: field,
                p_increment: 1,
            });
            if (error && !this.isMissingFeedTableError(error)) {
                this.logger.warn(`Failed to increment feed item count: ${error.message}`);
            }
        }
        catch (error) {
            this.logger.warn(`Increment feed item count fallback: ${this.stringifyError(error)}`);
        }
    }
    async markUserFeedEngagement(userId, type, itemId, eventType) {
        try {
            const { data, error } = await this.supabase.client
                .from('feed_items')
                .select('id')
                .eq('item_type', type)
                .eq('item_id', itemId)
                .limit(1)
                .maybeSingle();
            if (error || !data?.id) {
                return;
            }
            const now = new Date().toISOString();
            const payload = {
                user_id: userId,
                feed_item_id: String(data.id),
                seen: true,
                engaged: eventType !== 'view',
                engagement_type: eventType,
                seen_at: now,
                updated_at: now,
            };
            const upsert = await this.supabase.client
                .from('user_feed')
                .upsert(payload, { onConflict: 'user_id,feed_item_id' });
            if (upsert.error && !this.isMissingFeedTableError(upsert.error)) {
                this.logger.warn(`Failed to update user_feed engagement row: ${upsert.error.message}`);
            }
        }
        catch (error) {
            this.logger.warn(`user_feed engagement fallback: ${this.stringifyError(error)}`);
        }
    }
    async persistFeedItems(items) {
        if (items.length === 0) {
            return;
        }
        try {
            const now = new Date().toISOString();
            const rows = items.map((item) => ({
                item_type: item.type,
                item_id: item.itemId,
                creator_id: item.creatorId ?? null,
                title: item.title ?? null,
                thumbnail_url: item.thumbnailUrl ?? null,
                score: item.score,
                view_count: item.viewCount,
                like_count: item.likeCount,
                comment_count: item.commentCount,
                gift_count: item.giftCount,
                created_at: item.createdAt ?? now,
                expires_at: item.expiresAt ?? null,
                metadata: item.metadata ?? {},
                updated_at: now,
            }));
            const { error } = await this.supabase.client
                .from('feed_items')
                .upsert(rows, { onConflict: 'item_type,item_id' });
            if (error && !this.isMissingFeedTableError(error)) {
                this.logger.warn(`Failed to persist feed items: ${error.message}`);
            }
        }
        catch (error) {
            this.logger.warn(`Feed persistence fallback: ${this.stringifyError(error)}`);
        }
    }
    async syncUserFeed(userId, items) {
        if (items.length === 0) {
            return;
        }
        try {
            const { data, error } = await this.supabase.client
                .from('feed_items')
                .select('id,item_type,item_id')
                .in('item_type', items.map((item) => item.type));
            if (error) {
                if (!this.isMissingFeedTableError(error)) {
                    this.logger.warn(`Failed to load feed item ids for user feed sync: ${error.message}`);
                }
                return;
            }
            const idByKey = new Map();
            for (const row of (data ?? [])) {
                const type = this.asString(row.item_type);
                const itemId = this.asString(row.item_id);
                const id = this.asString(row.id);
                if (type && itemId && id) {
                    idByKey.set(`${type}:${itemId}`, id);
                }
            }
            const now = new Date().toISOString();
            const rows = items
                .map((item) => {
                const feedItemId = idByKey.get(`${item.type}:${item.itemId}`);
                if (!feedItemId) {
                    return null;
                }
                return {
                    user_id: userId,
                    feed_item_id: feedItemId,
                    seen: false,
                    engaged: false,
                    created_at: now,
                    updated_at: now,
                };
            })
                .filter((row) => row !== null);
            if (rows.length === 0) {
                return;
            }
            const { error: upsertError } = await this.supabase.client
                .from('user_feed')
                .upsert(rows, { onConflict: 'user_id,feed_item_id', ignoreDuplicates: true });
            if (upsertError && !this.isMissingFeedTableError(upsertError)) {
                this.logger.warn(`Failed to sync user feed: ${upsertError.message}`);
            }
        }
        catch (error) {
            this.logger.warn(`User feed sync fallback: ${this.stringifyError(error)}`);
        }
    }
    async invalidateCaches(userId) {
        await this.deleteRedisKeysByPrefix('feed:global:');
        if (userId) {
            await this.deleteRedisKeysByPrefix(`feed:user:${userId}:`);
        }
    }
    async deleteRedisKeysByPrefix(prefix) {
        try {
            const keys = await this.redis.client.keys(`${prefix}*`);
            if (keys.length === 0) {
                return;
            }
            await this.redis.client.del(keys.slice(0, this.maxCacheScanKeys));
        }
        catch (error) {
            this.logger.warn(`Redis cache invalidation failed for prefix ${prefix}: ${this.stringifyError(error)}`);
        }
    }
    async readCachedFeed(cacheKey) {
        try {
            const cached = await this.redis.client.get(cacheKey);
            if (!cached) {
                return null;
            }
            const parsed = JSON.parse(cached);
            return Array.isArray(parsed) ? parsed : null;
        }
        catch (error) {
            this.logger.warn(`Redis feed cache read failed for ${cacheKey}: ${this.stringifyError(error)}`);
            return null;
        }
    }
    async writeCachedFeed(cacheKey, items) {
        try {
            await this.redis.client.set(cacheKey, JSON.stringify(items), {
                EX: this.cacheTtlSeconds,
            });
        }
        catch (error) {
            this.logger.warn(`Redis feed cache write failed for ${cacheKey}: ${this.stringifyError(error)}`);
        }
    }
    mapPersistedFeedItem(row) {
        return {
            id: this.asString(row.id),
            type: row.item_type,
            itemId: this.asString(row.item_id),
            creatorId: this.asString(row.creator_id) || undefined,
            title: this.asString(row.title) || undefined,
            thumbnailUrl: this.asString(row.thumbnail_url) || undefined,
            score: this.asNumber(row.score),
            viewCount: this.asNumber(row.view_count),
            likeCount: this.asNumber(row.like_count),
            commentCount: this.asNumber(row.comment_count),
            giftCount: this.asNumber(row.gift_count),
            createdAt: this.asString(row.created_at) || undefined,
            expiresAt: this.asString(row.expires_at) || undefined,
            metadata: row.metadata ?? {},
        };
    }
    isNotExpired(item) {
        return !item.expiresAt || new Date(item.expiresAt).getTime() > Date.now();
    }
    pickArtistName(row) {
        const direct = this.asString(row.artist);
        if (direct) {
            return direct;
        }
        const artists = row.artists;
        if (artists && typeof artists === 'object' && !Array.isArray(artists)) {
            return this.asString(artists.name);
        }
        if (Array.isArray(artists) && artists.length > 0) {
            const first = artists[0];
            if (first && typeof first === 'object') {
                return this.asString(first.name);
            }
        }
        return '';
    }
    pickArtwork(row) {
        const keys = ['artwork_url', 'thumbnail_url', 'thumbnail', 'image_url'];
        for (const key of keys) {
            const value = this.asString(row[key]);
            if (value) {
                return value;
            }
        }
        return undefined;
    }
    globalCacheKey(limit) {
        return `feed:global:${limit}`;
    }
    personalCacheKey(userId, limit) {
        return `feed:user:${userId}:${limit}`;
    }
    normalizeLimit(value, fallback, max) {
        if (!Number.isFinite(value) || value <= 0) {
            return fallback;
        }
        return Math.max(1, Math.min(max, Math.floor(value)));
    }
    recencyScore(createdAt, maxAgeDays, weight) {
        if (!createdAt) {
            return 0;
        }
        const ageDays = Math.max(0, (Date.now() - new Date(createdAt).getTime()) / (1000 * 60 * 60 * 24));
        return Math.max(0, 1 - (ageDays / maxAgeDays)) * weight;
    }
    engagementWeight(eventType) {
        switch (eventType) {
            case 'gift':
                return 5;
            case 'like':
            case 'follow':
                return 2;
            case 'comment':
            case 'share':
                return 3;
            case 'view':
            default:
                return 1;
        }
    }
    counterFieldForEvent(eventType) {
        switch (eventType) {
            case 'view':
                return 'view_count';
            case 'like':
                return 'like_count';
            case 'gift':
                return 'gift_count';
            case 'comment':
                return 'comment_count';
            default:
                return null;
        }
    }
    firstDefinedNumber(...values) {
        for (const value of values) {
            const numberValue = this.asNumber(value);
            if (numberValue !== 0 || value === 0 || value === '0') {
                return numberValue;
            }
        }
        return 0;
    }
    asString(value) {
        return value == null ? '' : String(value).trim();
    }
    asNumber(value) {
        if (typeof value === 'number') {
            return Number.isFinite(value) ? value : 0;
        }
        const parsed = Number(value ?? 0);
        return Number.isFinite(parsed) ? parsed : 0;
    }
    asBoolean(value) {
        if (typeof value === 'boolean') {
            return value;
        }
        if (typeof value === 'number') {
            return value !== 0;
        }
        const normalized = this.asString(value).toLowerCase();
        return normalized === 'true' || normalized === '1' || normalized === 'yes';
    }
    isRecoverableContentQueryError(error) {
        return this.isMissingColumnError(error) || this.isMissingTableError(error) || this.isSchemaCacheError(error);
    }
    isMissingFeedTableError(error) {
        return this.isMissingTableError(error) || this.isSchemaCacheError(error) || this.isMissingConflictTargetError(error);
    }
    isMissingTableError(error) {
        const text = this.stringifyError(error).toLowerCase();
        return text.includes('42p01') || text.includes('does not exist') || text.includes('could not find the table');
    }
    isSchemaCacheError(error) {
        const text = this.stringifyError(error).toLowerCase();
        return text.includes('schema cache') || text.includes('pgrst');
    }
    isMissingColumnError(error, columnName) {
        const text = this.stringifyError(error).toLowerCase();
        if (!(text.includes('column') || text.includes('could not find'))) {
            return false;
        }
        return columnName ? text.includes(columnName.toLowerCase()) : true;
    }
    isMissingConflictTargetError(error) {
        const text = this.stringifyError(error).toLowerCase();
        return text.includes('42p10') || text.includes('no unique or exclusion constraint');
    }
    stringifyError(error) {
        if (error instanceof Error) {
            return error.message;
        }
        try {
            return JSON.stringify(error);
        }
        catch (_) {
            return String(error);
        }
    }
};
exports.FeedService = FeedService;
exports.FeedService = FeedService = FeedService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [supabase_service_1.SupabaseService,
        redis_service_1.RedisService])
], FeedService);
//# sourceMappingURL=feed.service.js.map