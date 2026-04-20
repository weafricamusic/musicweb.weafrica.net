import { Injectable, Logger } from '@nestjs/common';

import { EventBusService } from '../events/event-bus.service';
import { DomainEvent } from '../events/types/event-types';
import { BattleService } from '../battle/battle.service';
import { LiveRoomService } from '../live-room/live-room.service';
import { StreamService } from '../stream/stream.service';
import { WalletService } from '../wallet/wallet.service';
import { DistributedLockService } from './locks/distributed-lock.service';
import { BattleStateMachine, BattleStatus } from './state-machine/battle.state';
import { LiveRoomMode, LiveRoomStateMachine, LiveRoomStatus } from './state-machine/live-room.state';

@Injectable()
export class OrchestratorService {
  private readonly logger = new Logger(OrchestratorService.name);

  constructor(
    private readonly lockService: DistributedLockService,
    private readonly eventBus: EventBusService,
    private readonly liveRoomService: LiveRoomService,
    private readonly battleService: BattleService,
    private readonly streamService: StreamService,
    private readonly walletService: WalletService,
  ) {}

  async startSoloLive(params: {
    userId: string;
    userType: 'artist' | 'dj';
    title: string;
    category: string;
    coverImage?: string;
    privacy: 'public' | 'followers';
  }) {
    const lockKey = `user:${params.userId}:stream`;

    return this.lockService.executeWithLock(lockKey, async () => {
      const activeRoom = await this.liveRoomService.findActiveByUser(params.userId);
      if (activeRoom) {
        throw new Error('You already have an active live stream');
      }

      const liveRoom = await this.liveRoomService.create({
        creatorId: params.userId,
        creatorType: params.userType,
        title: params.title,
        category: params.category,
        coverImage: params.coverImage,
        mode: LiveRoomMode.SOLO,
        status: LiveRoomStatus.SCHEDULED,
        privacy: params.privacy,
      });

      const streamSession = await this.streamService.create({
        liveRoomId: liveRoom.id,
        status: 'CREATED',
      });

      const token = await this.streamService.generateToken({
        channelId: streamSession.channelId,
        userId: params.userId,
        role: 'broadcaster',
      });

      LiveRoomStateMachine.validateTransition(liveRoom.status, LiveRoomStatus.READY);
      await this.liveRoomService.updateStatus(liveRoom.id, LiveRoomStatus.READY);

      await this.eventBus.emit(DomainEvent.STREAM_CREATED, {
        liveRoomId: liveRoom.id,
        creatorId: params.userId,
        title: params.title,
        streamSessionId: streamSession.id,
      });

      this.logger.log(`Solo live created: ${liveRoom.id} by ${params.userId}`);
      return { liveRoom, streamSession, token };
    });
  }

  async startBattleInvite(params: {
    userId: string;
    userType: 'artist' | 'dj';
    title: string;
    category: string;
    coverImage?: string;
    durationSeconds: number;
    coinGoal: number;
    beatName: string;
    opponentId: string;
  }) {
    const lockKey = `user:${params.userId}:battle`;

    return this.lockService.executeWithLock(lockKey, async () => {
      const activeBattle = await this.battleService.findActiveByUser(params.userId);
      if (activeBattle) {
        throw new Error('You already have an active battle');
      }

      const opponentActive = await this.battleService.findActiveByUser(params.opponentId);
      if (opponentActive) {
        throw new Error('Opponent is already in a battle');
      }

      const liveRoom = await this.liveRoomService.create({
        creatorId: params.userId,
        creatorType: params.userType,
        title: params.title,
        category: params.category,
        coverImage: params.coverImage,
        mode: LiveRoomMode.BATTLE,
        status: LiveRoomStatus.WAITING,
      });

      const battle = await this.battleService.create({
        liveRoomId: liveRoom.id,
        hostId: params.userId,
        durationSeconds: params.durationSeconds,
        coinGoal: params.coinGoal,
        beatName: params.beatName,
        status: BattleStatus.WAITING,
        title: params.title,
        category: params.category,
      });

      const invite = await this.battleService.createInvite({
        battleId: battle.id,
        fromUserId: params.userId,
        toUserId: params.opponentId,
      });

      await this.eventBus.emit(DomainEvent.BATTLE_INVITE_SENT, {
        battleId: battle.id,
        liveRoomId: liveRoom.id,
        fromUserId: params.userId,
        toUserId: params.opponentId,
        title: params.title,
      });

      this.logger.log(`Battle invite sent: ${battle.id} from ${params.userId} to ${params.opponentId}`);
      return { liveRoom, battle, invite };
    });
  }

  async acceptBattleInvite(params: { inviteId: string; userId: string }) {
    const invite = await this.battleService.getInvite(params.inviteId);
    if (!invite) {
      throw new Error('Invite not found');
    }

    if (invite.toUserId !== params.userId) {
      throw new Error('Not authorized to accept this invite');
    }

    const lockKey = `battle:${invite.battleId}:accept`;
    return this.lockService.executeWithLock(lockKey, async () => {
      await this.battleService.updateInviteStatus(invite.id, 'ACCEPTED');

      const battle = await this.battleService.setOpponent(invite.battleId, params.userId);

      const liveRoom = await this.liveRoomService.updateStatus(battle.liveRoomId, LiveRoomStatus.READY);

      const streamSession = await this.streamService.create({
        liveRoomId: liveRoom.id,
        participants: [battle.hostId, battle.opponentId ?? params.userId],
        status: 'CREATED',
      });

      const hostToken = await this.streamService.generateToken({
        channelId: streamSession.channelId,
        userId: battle.hostId,
        role: 'broadcaster',
      });

      const opponentToken = await this.streamService.generateToken({
        channelId: streamSession.channelId,
        userId: battle.opponentId ?? params.userId,
        role: 'broadcaster',
      });

      await this.eventBus.emit(DomainEvent.BATTLE_ACCEPTED, {
        battleId: battle.id,
        liveRoomId: liveRoom.id,
        hostId: battle.hostId,
        opponentId: battle.opponentId,
        streamSessionId: streamSession.id,
        channelId: streamSession.channelId,
      });

      this.logger.log(`Battle accepted: ${battle.id} between ${battle.hostId} and ${battle.opponentId}`);
      return { liveRoom, battle, streamSession, tokens: { host: hostToken, opponent: opponentToken } };
    });
  }

  async startStream(params: { liveRoomId: string; userId: string; streamSessionId: string }) {
    const lockKey = `stream:${params.liveRoomId}:start`;
    return this.lockService.executeWithLock(lockKey, async () => {
      const liveRoom = await this.liveRoomService.findById(params.liveRoomId);
      const battle = await this.battleService.findByLiveRoom(params.liveRoomId);

      // Validate permission.
      if (liveRoom.creatorId !== params.userId) {
        if (!battle || battle.opponentId !== params.userId) {
          throw new Error('Not authorized to start this stream');
        }
      }

      const streamSession = await this.streamService.updateStatus(params.streamSessionId, 'ACTIVE');
      let nextLiveRoom = liveRoom;
      let started = false;

      if (liveRoom.status !== LiveRoomStatus.LIVE) {
        LiveRoomStateMachine.validateTransition(liveRoom.status, LiveRoomStatus.LIVE);
        nextLiveRoom = await this.liveRoomService.updateStatus(params.liveRoomId, LiveRoomStatus.LIVE);
        started = true;
      }

      if (battle) {
        if (battle.status !== BattleStatus.LIVE) {
          BattleStateMachine.validateTransition(battle.status, BattleStatus.LIVE);
          await this.battleService.updateStatus(battle.id, BattleStatus.LIVE);
          await this.battleService.startScoringEngine(battle.id);
          started = true;
        }
      }

      if (started) {
        await this.eventBus.emit(DomainEvent.STREAM_STARTED, {
          liveRoomId: params.liveRoomId,
          streamSessionId: streamSession.id,
          channelId: streamSession.channelId,
        });
      }

      this.logger.log(`Stream started: ${params.liveRoomId}`);
      return { streamSession, liveRoom: nextLiveRoom.status === LiveRoomStatus.LIVE ? nextLiveRoom : await this.liveRoomService.findById(params.liveRoomId) };
    });
  }

  async endStream(params: { liveRoomId: string; userId: string }) {
    const lockKey = `stream:${params.liveRoomId}:end`;
    return this.lockService.executeWithLock(lockKey, async () => {
      const liveRoom = await this.liveRoomService.findById(params.liveRoomId);
      if (liveRoom.creatorId !== params.userId) {
        throw new Error('Only the host can end the stream');
      }

      await this.streamService.updateStatusByLiveRoom(params.liveRoomId, 'CLOSED');

      let nextLiveRoom = liveRoom;
      if (liveRoom.status !== LiveRoomStatus.ENDED) {
        LiveRoomStateMachine.validateTransition(liveRoom.status, LiveRoomStatus.ENDED);
        nextLiveRoom = await this.liveRoomService.updateStatus(params.liveRoomId, LiveRoomStatus.ENDED);
      }

      const battle = await this.battleService.findByLiveRoom(params.liveRoomId);
      let nextBattle = battle;
      if (battle && battle.status === BattleStatus.LIVE) {
        const finalizedBattle = await this.battleService.finalizeBattle(battle.id);
        await this.walletService.recordBattlePayouts(finalizedBattle);
        nextBattle = await this.battleService.updateStatus(battle.id, BattleStatus.ENDED);
        await this.eventBus.emit(DomainEvent.BATTLE_ENDED, {
          battleId: battle.id,
          winnerId: finalizedBattle.winner_uid,
          winnerPayout: finalizedBattle.winner_payout_coins,
          hostScore: finalizedBattle.host_a_score,
          opponentScore: finalizedBattle.host_b_score,
          hostId: battle.hostId,
          opponentId: battle.opponentId,
        });
      }

      await this.eventBus.emit(DomainEvent.STREAM_ENDED, { liveRoomId: params.liveRoomId });
      this.logger.log(`Stream ended: ${params.liveRoomId}`);
      return {
        liveRoom: nextLiveRoom.status === LiveRoomStatus.ENDED
          ? nextLiveRoom
          : await this.liveRoomService.findById(params.liveRoomId),
        battle: nextBattle,
      };
    });
  }
}
