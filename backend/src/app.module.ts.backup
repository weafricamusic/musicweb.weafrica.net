import { Module } from '@nestjs/common';

import { FirebaseAuthModule } from './auth/firebase-auth.module';
import { SupabaseModule } from './common/supabase/supabase.module';
import { AdminModule } from './admin/admin.module';
import { ChallengeModule } from './challenge/challenge.module';
import { EventsModule } from './events/events.module';
import { FeedModule } from './feed/feed.module';
import { LiveRoomModule } from './live-room/live-room.module';
import { LiveController } from './live.controller';
import { LiveGateway } from './gateways/live.gateway';
import { OrchestratorModule } from './orchestrator/orchestrator.module';
import { StreamModule } from './stream/stream.module';

@Module({
  imports: [
    SupabaseModule,
    FirebaseAuthModule,
    StreamModule,
    LiveRoomModule,
    ChallengeModule,
    EventsModule,
    FeedModule,
    OrchestratorModule,
    AdminModule,
  ],
  controllers: [LiveController],
  providers: [LiveGateway],
})
export class AppModule {}
