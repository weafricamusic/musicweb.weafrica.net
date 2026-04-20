import { Module } from '@nestjs/common';

import { FirebaseAuthModule } from '../auth/firebase-auth.module';
import { RedisModule } from '../common/redis/redis.module';
import { SupabaseModule } from '../common/supabase/supabase.module';
import { WalletController, WithdrawalsController } from './wallet.controller';
import { WalletService } from './wallet.service';

@Module({
  imports: [FirebaseAuthModule, RedisModule, SupabaseModule],
  controllers: [WalletController, WithdrawalsController],
  providers: [WalletService],
  exports: [WalletService],
})
export class WalletModule {}
