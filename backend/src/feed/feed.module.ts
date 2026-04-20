import { Module } from '@nestjs/common';

import { FirebaseAuthModule } from '../auth/firebase-auth.module';
import { RedisModule } from '../common/redis/redis.module';
import { SupabaseModule } from '../common/supabase/supabase.module';
import { FeedController } from './feed.controller';
import { FeedService } from './feed.service';

@Module({
  imports: [FirebaseAuthModule, RedisModule, SupabaseModule],
  controllers: [FeedController],
  providers: [FeedService],
  exports: [FeedService],
})
export class FeedModule {}