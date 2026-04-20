import { Module } from '@nestjs/common';

import { SupabaseModule } from '../common/supabase/supabase.module';
import { BattleService } from './battle.service';

@Module({
  imports: [SupabaseModule],
  providers: [BattleService],
  exports: [BattleService],
})
export class BattleModule {}
