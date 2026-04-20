import { Module } from '@nestjs/common';

import { SupabaseModule } from '../common/supabase/supabase.module';
import { LiveRoomModule } from '../live-room/live-room.module';
import { StreamModule } from '../stream/stream.module';
import { ChallengeService } from './challenge.service';

@Module({
  imports: [StreamModule, LiveRoomModule, SupabaseModule],
  providers: [ChallengeService],
  exports: [ChallengeService],
})
export class ChallengeModule {}
