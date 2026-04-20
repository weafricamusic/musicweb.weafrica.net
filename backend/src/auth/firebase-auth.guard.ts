import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';

import { FirebaseAuthService, FirebaseRequestUser } from './firebase-auth.service';

type AuthenticatedRequest = {
  headers: Record<string, string | string[] | undefined>;
  user?: FirebaseRequestUser;
};

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  constructor(private readonly firebaseAuth: FirebaseAuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const rawAuthorization = request.headers.authorization;
    const authorizationHeader = Array.isArray(rawAuthorization) ? rawAuthorization[0] : rawAuthorization;

    try {
      request.user = await this.firebaseAuth.verifyAuthorizationHeader(authorizationHeader);
      return true;
    } catch (error) {
      throw new UnauthorizedException(error instanceof Error ? error.message : 'Invalid authentication token');
    }
  }
}