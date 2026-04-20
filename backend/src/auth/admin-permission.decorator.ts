import { SetMetadata } from '@nestjs/common';

export const ADMIN_PERMISSIONS_KEY = 'admin_permissions_required';

export function RequireAdminPermission(...permissions: string[]) {
  return SetMetadata(ADMIN_PERMISSIONS_KEY, permissions);
}
