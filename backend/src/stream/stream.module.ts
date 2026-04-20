import { Module } from '@nestjs/common';

import { SupabaseModule } from '../common/supabase/supabase.module';
import { AgoraService } from './agora/agora.service';
import { StreamService } from './stream.service';

@Module({
  imports: [SupabaseModule],
  providers: [AgoraService, StreamService],
  exports: [AgoraService, StreamService],
})
export class StreamModule {}
