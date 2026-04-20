"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminPermissionGuard = exports.AdminGuard = void 0;
const common_1 = require("@nestjs/common");
const core_1 = require("@nestjs/core");
const supabase_service_1 = require("../common/supabase/supabase.service");
const admin_permission_decorator_1 = require("./admin-permission.decorator");
let AdminGuard = class AdminGuard {
    constructor(supabase) {
        this.supabase = supabase;
    }
    async canActivate(context) {
        const request = context.switchToHttp().getRequest();
        const user = request.user;
        if (!user) {
            throw new common_1.ForbiddenException('Not authenticated');
        }
        const { data: profile, error } = await this.supabase.client
            .from('profiles')
            .select('is_admin, admin_role')
            .eq('id', user.uid)
            .single();
        if (error || !profile || profile.is_admin !== true) {
            throw new common_1.ForbiddenException('Admin access required');
        }
        request.adminRole = profile.admin_role ?? 'viewer';
        return true;
    }
};
exports.AdminGuard = AdminGuard;
exports.AdminGuard = AdminGuard = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [supabase_service_1.SupabaseService])
], AdminGuard);
let AdminPermissionGuard = class AdminPermissionGuard {
    constructor(supabase, reflector) {
        this.supabase = supabase;
        this.reflector = reflector;
    }
    async canActivate(context) {
        const required = this.reflector.getAllAndOverride(admin_permission_decorator_1.ADMIN_PERMISSIONS_KEY, [context.getHandler(), context.getClass()]) ??
            [];
        if (required.length === 0) {
            return true;
        }
        const request = context.switchToHttp().getRequest();
        const adminRole = (request.adminRole ?? '').trim();
        if (!request.user || !adminRole) {
            throw new common_1.ForbiddenException('Admin access required');
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
            throw new common_1.ForbiddenException('Invalid admin role');
        }
        const permissions = (role.permissions ?? {});
        if (permissions.all === true) {
            return true;
        }
        for (const permission of required) {
            if (permission === 'all') {
                throw new common_1.ForbiddenException('Permission denied: all');
            }
            if (permissions[permission] !== true) {
                throw new common_1.ForbiddenException(`Permission denied: ${permission}`);
            }
        }
        return true;
    }
};
exports.AdminPermissionGuard = AdminPermissionGuard;
exports.AdminPermissionGuard = AdminPermissionGuard = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [supabase_service_1.SupabaseService,
        core_1.Reflector])
], AdminPermissionGuard);
//# sourceMappingURL=admin.guard.js.map