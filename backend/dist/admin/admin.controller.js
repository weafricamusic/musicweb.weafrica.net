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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const admin_guard_1 = require("../auth/admin.guard");
const admin_permission_decorator_1 = require("../auth/admin-permission.decorator");
const firebase_auth_guard_1 = require("../auth/firebase-auth.guard");
const admin_service_1 = require("./admin.service");
let AdminController = class AdminController {
    constructor(adminService) {
        this.adminService = adminService;
    }
    async getDashboard() {
        return this.adminService.getDashboard();
    }
    async getViralContent(hours, limit) {
        return this.adminService.getViralContent(hours ? Number(hours) : undefined, limit ? Number(limit) : undefined);
    }
    async getViralAlerts(acknowledged) {
        const normalized = acknowledged === undefined ? undefined : acknowledged === 'true';
        return this.adminService.getViralAlerts(normalized);
    }
    async acknowledgeViralAlert(alertId, admin) {
        return this.adminService.acknowledgeViralAlert(alertId, admin.uid);
    }
    async getAllUsers(limit, offset) {
        return this.adminService.getAllUsers(limit ? Number(limit) : undefined, offset ? Number(offset) : undefined);
    }
    async getUserDetails(userId) {
        return this.adminService.getUserDetails(userId);
    }
    async updateUserRole(userId, role, admin) {
        return this.adminService.updateUserRole(userId, role, admin.uid);
    }
    async suspendUser(userId, reason, admin) {
        return this.adminService.suspendUser(userId, reason, admin.uid);
    }
    async unsuspendUser(userId, admin) {
        return this.adminService.unsuspendUser(userId, admin.uid);
    }
    async banUser(userId, reason, admin) {
        return this.adminService.banUser(userId, reason, admin.uid);
    }
    async unbanUser(userId, admin) {
        return this.adminService.unbanUser(userId, admin.uid);
    }
    async makeAdmin(userId, role, admin) {
        return this.adminService.makeAdmin(userId, role, admin.uid);
    }
    async getReportedContent(status, limit) {
        return this.adminService.getReportedContent(status, limit ? Number(limit) : undefined);
    }
    async getReportDetails(reportId) {
        return this.adminService.getReportDetails(reportId);
    }
    async getContentFlags(status, limit) {
        return this.adminService.getContentFlags(status, limit ? Number(limit) : undefined);
    }
    async createContentFlag(contentType, contentId, reason, severity, admin) {
        return this.adminService.createContentFlag(contentType, contentId, reason, severity, admin.uid);
    }
    async resolveContentFlag(flagId, action, notes, admin) {
        return this.adminService.resolveContentFlag(flagId, action, notes, admin.uid);
    }
    async reviewReport(reportId, action, notes, admin) {
        return this.adminService.reviewReport(reportId, action, admin.uid, notes);
    }
    async getMetrics(start, end) {
        return this.adminService.getMetrics({ start: new Date(start), end: new Date(end) });
    }
    async getRealTimeStats() {
        return this.adminService.getRealtimeMetrics();
    }
    async getAnalytics(days, country) {
        return this.adminService.getAnalyticsOverview(days ? Number(days) : undefined, country);
    }
    async getFinanceSummary(period) {
        return this.adminService.getFinanceSummary(period);
    }
    async getFinanceTransactions(limit, offset, type) {
        return this.adminService.getFinanceTransactions(limit ? Number(limit) : undefined, offset ? Number(offset) : undefined, type);
    }
    async getWithdrawals(status) {
        return this.adminService.getWithdrawals(status);
    }
    async processWithdrawal(withdrawalId, action, notes, admin) {
        return this.adminService.processWithdrawal(withdrawalId, action, notes, admin.uid);
    }
    async getActiveStreams() {
        return this.adminService.getActiveStreams();
    }
    async getStreams(status, region, limit) {
        return this.adminService.getStreams(status, region, limit ? Number(limit) : undefined);
    }
    async getStreamDetails(streamId) {
        return this.adminService.getStreamDetails(streamId);
    }
    async stopStream(streamId, reason, admin) {
        return this.adminService.stopStream(streamId, reason, admin.uid);
    }
    async getSystemHealth() {
        return this.adminService.getSystemHealth();
    }
    async getHealthHistory(service, hours) {
        return this.adminService.getServiceHealth(service, hours ? Number(hours) : undefined);
    }
    async getAuditLogs(limit, offset) {
        return this.adminService.getAuditLogs(limit ? Number(limit) : undefined, offset ? Number(offset) : undefined);
    }
};
exports.AdminController = AdminController;
__decorate([
    (0, common_1.Get)('dashboard'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getDashboard", null);
__decorate([
    (0, common_1.Get)('viral'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __param(0, (0, common_1.Query)('hours')),
    __param(1, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getViralContent", null);
__decorate([
    (0, common_1.Get)('viral/alerts'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __param(0, (0, common_1.Query)('acknowledged')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getViralAlerts", null);
__decorate([
    (0, common_1.Post)('viral/alerts/:alertId/acknowledge'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __param(0, (0, common_1.Param)('alertId')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "acknowledgeViralAlert", null);
__decorate([
    (0, common_1.Get)('users'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('users'),
    __param(0, (0, common_1.Query)('limit')),
    __param(1, (0, common_1.Query)('offset')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getAllUsers", null);
__decorate([
    (0, common_1.Get)('users/:userId'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('users'),
    __param(0, (0, common_1.Param)('userId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getUserDetails", null);
__decorate([
    (0, common_1.Put)('users/:userId/role'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('users'),
    __param(0, (0, common_1.Param)('userId')),
    __param(1, (0, common_1.Body)('role')),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "updateUserRole", null);
__decorate([
    (0, common_1.Post)('users/:userId/suspend'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('users'),
    __param(0, (0, common_1.Param)('userId')),
    __param(1, (0, common_1.Body)('reason')),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "suspendUser", null);
__decorate([
    (0, common_1.Post)('users/:userId/unsuspend'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('users'),
    __param(0, (0, common_1.Param)('userId')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "unsuspendUser", null);
__decorate([
    (0, common_1.Post)('users/:userId/ban'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('users'),
    __param(0, (0, common_1.Param)('userId')),
    __param(1, (0, common_1.Body)('reason')),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "banUser", null);
__decorate([
    (0, common_1.Post)('users/:userId/unban'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('users'),
    __param(0, (0, common_1.Param)('userId')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "unbanUser", null);
__decorate([
    (0, common_1.Post)('users/:userId/make-admin'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('users'),
    __param(0, (0, common_1.Param)('userId')),
    __param(1, (0, common_1.Body)('role')),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "makeAdmin", null);
__decorate([
    (0, common_1.Get)('reports'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Query)('status')),
    __param(1, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getReportedContent", null);
__decorate([
    (0, common_1.Get)('reports/:reportId'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Param)('reportId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getReportDetails", null);
__decorate([
    (0, common_1.Get)('content/flags'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Query)('status')),
    __param(1, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getContentFlags", null);
__decorate([
    (0, common_1.Post)('content/:contentType/:contentId/flag'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Param)('contentType')),
    __param(1, (0, common_1.Param)('contentId')),
    __param(2, (0, common_1.Body)('reason')),
    __param(3, (0, common_1.Body)('severity')),
    __param(4, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, Number, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "createContentFlag", null);
__decorate([
    (0, common_1.Post)('content/flags/:flagId/resolve'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Param)('flagId')),
    __param(1, (0, common_1.Body)('action')),
    __param(2, (0, common_1.Body)('notes')),
    __param(3, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "resolveContentFlag", null);
__decorate([
    (0, common_1.Post)('reports/:reportId/review'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Param)('reportId')),
    __param(1, (0, common_1.Body)('action')),
    __param(2, (0, common_1.Body)('notes')),
    __param(3, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "reviewReport", null);
__decorate([
    (0, common_1.Get)('metrics'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __param(0, (0, common_1.Query)('start')),
    __param(1, (0, common_1.Query)('end')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getMetrics", null);
__decorate([
    (0, common_1.Get)('metrics/realtime'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getRealTimeStats", null);
__decorate([
    (0, common_1.Get)('analytics'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __param(0, (0, common_1.Query)('days')),
    __param(1, (0, common_1.Query)('country')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getAnalytics", null);
__decorate([
    (0, common_1.Get)('finance/summary'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('finance'),
    __param(0, (0, common_1.Query)('period')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getFinanceSummary", null);
__decorate([
    (0, common_1.Get)('finance/transactions'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('finance'),
    __param(0, (0, common_1.Query)('limit')),
    __param(1, (0, common_1.Query)('offset')),
    __param(2, (0, common_1.Query)('type')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getFinanceTransactions", null);
__decorate([
    (0, common_1.Get)('finance/withdrawals'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('finance'),
    __param(0, (0, common_1.Query)('status')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getWithdrawals", null);
__decorate([
    (0, common_1.Post)('finance/withdrawals/:withdrawalId/process'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('finance'),
    __param(0, (0, common_1.Param)('withdrawalId')),
    __param(1, (0, common_1.Body)('action')),
    __param(2, (0, common_1.Body)('notes')),
    __param(3, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "processWithdrawal", null);
__decorate([
    (0, common_1.Get)('streams/active'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getActiveStreams", null);
__decorate([
    (0, common_1.Get)('streams'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Query)('status')),
    __param(1, (0, common_1.Query)('region')),
    __param(2, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getStreams", null);
__decorate([
    (0, common_1.Get)('streams/:streamId'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Param)('streamId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getStreamDetails", null);
__decorate([
    (0, common_1.Post)('streams/:streamId/stop'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('moderate'),
    __param(0, (0, common_1.Param)('streamId')),
    __param(1, (0, common_1.Body)('reason')),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "stopStream", null);
__decorate([
    (0, common_1.Get)('health'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getSystemHealth", null);
__decorate([
    (0, common_1.Get)('health/:service'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('dashboard'),
    __param(0, (0, common_1.Param)('service')),
    __param(1, (0, common_1.Query)('hours')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getHealthHistory", null);
__decorate([
    (0, common_1.Get)('audit'),
    (0, admin_permission_decorator_1.RequireAdminPermission)('admin'),
    __param(0, (0, common_1.Query)('limit')),
    __param(1, (0, common_1.Query)('offset')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getAuditLogs", null);
exports.AdminController = AdminController = __decorate([
    (0, common_1.Controller)('admin'),
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard, admin_guard_1.AdminGuard, admin_guard_1.AdminPermissionGuard),
    __metadata("design:paramtypes", [admin_service_1.AdminService])
], AdminController);
//# sourceMappingURL=admin.controller.js.map