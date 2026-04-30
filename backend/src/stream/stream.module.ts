import { Module } from '@nestjs/common';

import { SupabaseModule } from '../common/supabase/supabase.module';
import { AgoraService } from './agora/agora.service';
import { AgoraController } from './agora/agora.controller';
import { StreamService } from './stream.service';

@Module({
  imports: [SupabaseModule],
  providers: [AgoraService, StreamService],
  controllers: [AgoraController],
  exports: [AgoraService, StreamService],
})
export class StreamModule { }
