import {
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';

import { StreamService } from '../stream/stream.service';
import { ChallengeService } from '../challenge/challenge.service';

@WebSocketGateway({
  cors: {
    origin: '*',
    credentials: true,
  },
  namespace: 'live',
})
@Injectable()
export class LiveGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(LiveGateway.name);

  private readonly viewers = new Map<string, Set<string>>(); // streamSessionId -> socketIds
  private readonly socketToStream = new Map<string, string>(); // socketId -> streamSessionId
  private readonly socketToUser = new Map<string, string>(); // socketId -> userId

  constructor(
    private readonly streamService: StreamService,
    // Keeping ChallengeService injected for future challenge events.
    private readonly challengeService: ChallengeService,
  ) {}

  handleConnection(client: Socket) {
    this.logger.log(`Client connected: ${client.id}`);
  }

  handleDisconnect(client: Socket) {
    this.logger.log(`Client disconnected: ${client.id}`);

    const streamId = this.socketToStream.get(client.id);
    if (streamId) {
      this.socketToStream.delete(client.id);
      const set = this.viewers.get(streamId);
      if (set) {
        set.delete(client.id);
        if (set.size === 0) {
          this.viewers.delete(streamId);
        }
      }
      void this.updateViewerCount(streamId);
    }

    this.socketToUser.delete(client.id);
  }

  @SubscribeMessage('identify')
  handleIdentify(
    client: Socket,
    @MessageBody() data: { userId?: string },
  ) {
    const userId = String(data?.userId ?? '').trim();
    if (!userId) return { success: false };

    this.socketToUser.set(client.id, userId);
    client.join(`user:${userId}`);
    return { success: true };
  }

  @SubscribeMessage('join-stream')
  async handleJoinStream(
    client: Socket,
    @MessageBody() data: { streamId?: string; userId?: string },
  ) {
    const streamId = String(data?.streamId ?? '').trim();
    const userId = String(data?.userId ?? '').trim();

    if (!streamId) {
      return { success: false, error: 'Missing streamId' };
    }

    if (!this.viewers.has(streamId)) {
      this.viewers.set(streamId, new Set());
    }

    // If the socket was previously watching another stream, clean it up first.
    const previousStreamId = this.socketToStream.get(client.id);
    if (previousStreamId && previousStreamId !== streamId) {
      const prevSet = this.viewers.get(previousStreamId);
      if (prevSet) {
        prevSet.delete(client.id);
        if (prevSet.size === 0) {
          this.viewers.delete(previousStreamId);
        }
      }
      client.leave(`stream:${previousStreamId}`);
      void this.updateViewerCount(previousStreamId);
    }

    this.viewers.get(streamId)!.add(client.id);
    this.socketToStream.set(client.id, streamId);

    if (userId) {
      this.socketToUser.set(client.id, userId);
      client.join(`user:${userId}`);
    }

    client.join(`stream:${streamId}`);

    await this.updateViewerCount(streamId);

    const viewerCount = this.viewers.get(streamId)!.size;
    this.server.to(`stream:${streamId}`).emit('viewer-count', {
      streamId,
      count: viewerCount,
    });

    if (userId) {
      this.server.to(`stream:${streamId}`).emit('user-joined', { userId });
    }

    return { success: true, viewerCount };
  }

  @SubscribeMessage('leave-stream')
  async handleLeaveStream(
    client: Socket,
    @MessageBody() data: { streamId?: string },
  ) {
    const streamId = String(data?.streamId ?? '').trim();
    if (!streamId) return { success: false, error: 'Missing streamId' };

    const set = this.viewers.get(streamId);
    if (set) {
      set.delete(client.id);
      if (set.size === 0) {
        this.viewers.delete(streamId);
      }
    }

    this.socketToStream.delete(client.id);
    client.leave(`stream:${streamId}`);

    await this.updateViewerCount(streamId);

    const viewerCount = this.viewers.get(streamId)?.size ?? 0;
    this.server.to(`stream:${streamId}`).emit('viewer-count', {
      streamId,
      count: viewerCount,
    });

    return { success: true };
  }

  @SubscribeMessage('stream-started')
  handleStreamStarted(
    _client: Socket,
    @MessageBody() data: { streamId?: string; userId?: string; streamData?: unknown },
  ) {
    const streamId = String(data?.streamId ?? '').trim();
    const userId = String(data?.userId ?? '').trim();

    if (!streamId) return;

    this.server.emit('new-stream', {
      streamId,
      userId: userId || null,
      streamData: data?.streamData ?? null,
      timestamp: new Date().toISOString(),
    });

    this.logger.log(`New stream started: ${streamId}${userId ? ` by user ${userId}` : ''}`);
  }

  @SubscribeMessage('stream-ended')
  handleStreamEnded(
    _client: Socket,
    @MessageBody() data: { streamId?: string; userId?: string },
  ) {
    const streamId = String(data?.streamId ?? '').trim();
    const userId = String(data?.userId ?? '').trim();

    if (!streamId) return;

    this.viewers.delete(streamId);

    this.server.emit('stream-ended', {
      streamId,
      userId: userId || null,
      timestamp: new Date().toISOString(),
    });

    this.logger.log(`Stream ended: ${streamId}`);
  }

  @SubscribeMessage('challenge-sent')
  handleChallengeSent(
    _client: Socket,
    @MessageBody() data: { challengeId?: string; targetUserId?: string; challengeData?: unknown },
  ) {
    const targetUserId = String(data?.targetUserId ?? '').trim();
    const challengeId = String(data?.challengeId ?? '').trim();

    if (!targetUserId || !challengeId) return;

    this.server.to(`user:${targetUserId}`).emit('new-challenge', {
      challengeId,
      challengeData: data?.challengeData ?? null,
    });
  }

  @SubscribeMessage('challenge-accepted')
  handleChallengeAccepted(
    _client: Socket,
    @MessageBody() data: { challengeId?: string; streamId?: string },
  ) {
    const challengeId = String(data?.challengeId ?? '').trim();
    const streamId = String(data?.streamId ?? '').trim();

    if (!challengeId || !streamId) return;

    this.server.emit('battle-starting', {
      challengeId,
      streamId,
    });
  }

  // Server-side helpers (safe to call from controllers/services)
  emitStreamStarted(payload: { streamId: string; userId: string; streamData: unknown }) {
    this.server.emit('new-stream', {
      streamId: payload.streamId,
      userId: payload.userId,
      streamData: payload.streamData,
      timestamp: new Date().toISOString(),
    });
  }

  emitStreamEnded(payload: { streamId: string; userId: string }) {
    this.viewers.delete(payload.streamId);
    this.server.emit('stream-ended', {
      streamId: payload.streamId,
      userId: payload.userId,
      timestamp: new Date().toISOString(),
    });
  }

  emitChallengeSent(payload: { challengeId: string; targetUserId: string; challengeData: unknown }) {
    this.server.to(`user:${payload.targetUserId}`).emit('new-challenge', {
      challengeId: payload.challengeId,
      challengeData: payload.challengeData,
    });
  }

  emitChallengeAccepted(payload: { challengeId: string; streamId: string }) {
    this.server.emit('battle-starting', {
      challengeId: payload.challengeId,
      streamId: payload.streamId,
    });
  }

  private async updateViewerCount(streamId: string) {
    const count = this.viewers.get(streamId)?.size ?? 0;

    try {
      await this.streamService.updateViewerCount(streamId, count);
    } catch (e) {
      // Best-effort; stream session may not exist yet.
      this.logger.debug(`updateViewerCount best-effort failed: ${String(e)}`);
    }
  }
}
