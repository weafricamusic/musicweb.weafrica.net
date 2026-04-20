import { Module } from '@nestjs/common';

import { BattleModule } from '../battle/battle.module';
import { EventsModule } from '../events/events.module';
import { LiveRoomModule } from '../live-room/live-room.module';
import { StreamModule } from '../stream/stream.module';
import { WalletModule } from '../wallet/wallet.module';
import { DistributedLockService } from './locks/distributed-lock.service';
import { OrchestratorController } from './orchestrator.controller';
import { OrchestratorService } from './orchestrator.service';

@Module({
  imports: [EventsModule, LiveRoomModule, BattleModule, StreamModule, WalletModule],
  controllers: [OrchestratorController],
  providers: [DistributedLockService, OrchestratorService],
  exports: [OrchestratorService],
})
export class OrchestratorModule {}
