import { createParamDecorator, ExecutionContext } from '@nestjs/common';

import { FirebaseRequestUser } from './firebase-auth.service';

type AuthenticatedRequest = {
  user?: FirebaseRequestUser;
};

export const CurrentUser = createParamDecorator((_data: unknown, context: ExecutionContext): FirebaseRequestUser => {
  const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
  if (!request.user) {
    throw new Error('Authenticated user missing from request');
  }

  return request.user;
});