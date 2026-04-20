import { Module } from '@nestjs/common';

import { FirebaseAuthGuard } from './firebase-auth.guard';
import { FirebaseAuthService } from './firebase-auth.service';

@Module({
  providers: [FirebaseAuthService, FirebaseAuthGuard],
  exports: [FirebaseAuthService, FirebaseAuthGuard],
})
export class FirebaseAuthModule {}