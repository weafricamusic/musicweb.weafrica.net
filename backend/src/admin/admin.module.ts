import { Module } from '@nestjs/common';

import { FirebaseAuthModule } from '../auth/firebase-auth.module';
import { SupabaseModule } from '../common/supabase/supabase.module';
import { StreamModule } from '../stream/stream.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AdminGuard, AdminPermissionGuard } from '../auth/admin.guard';

@Module({
  imports: [SupabaseModule, FirebaseAuthModule, StreamModule],
  controllers: [AdminController],
  providers: [AdminService, AdminGuard, AdminPermissionGuard],
  exports: [AdminService],
})
export class AdminModule {}
