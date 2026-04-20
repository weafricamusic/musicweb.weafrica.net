import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

import { SupabaseService } from '../common/supabase/supabase.service';
import { ADMIN_PERMISSIONS_KEY } from './admin-permission.decorator';
import type { FirebaseRequestUser } from './firebase-auth.service';

type AdminAuthenticatedRequest = {
  user?: FirebaseRequestUser;
  adminRole?: string;
};

@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly supabase: SupabaseService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AdminAuthenticatedRequest>();
    const user = request.user;

    if (!user) {
      throw new ForbiddenException('Not authenticated');
    }

    const { data: profile, error } = await this.supabase.client
      .from('profiles')
      .select('is_admin, admin_role')
      .eq('id', user.uid)
      .single();

    if (error || !profile || profile.is_admin !== true) {
      throw new ForbiddenException('Admin access required');
    }

    request.adminRole = profile.admin_role ?? 'viewer';
    return true;
  }
}

@Injectable()
export class AdminPermissionGuard implements CanActivate {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const required =
      this.reflector.getAllAndOverride<string[]>(ADMIN_PERMISSIONS_KEY, [context.getHandler(), context.getClass()]) ??
      [];

    if (required.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AdminAuthenticatedRequest>();
    const adminRole = (request.adminRole ?? '').trim();

    if (!request.user || !adminRole) {
      throw new ForbiddenException('Admin access required');
    }

    if (adminRole === 'super_admin') {
      return true;
    }

    const { data: role, error } = await this.supabase.client
      .from('admin_role_permissions')
      .select('permissions')
      .eq('role_name', adminRole)
      .single();

    if (error || !role) {
      throw new ForbiddenException('Invalid admin role');
    }

    const permissions = (role.permissions ?? {}) as Record<string, unknown>;
    if (permissions.all === true) {
      return true;
    }

    for (const permission of required) {
      if (permission === 'all') {
        throw new ForbiddenException('Permission denied: all');
      }

      if (permissions[permission] !== true) {
        throw new ForbiddenException(`Permission denied: ${permission}`);
      }
    }

    return true;
  }
}
