import { Body, Controller, Get, Param, Post, Put, Query, UseGuards } from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { AdminPermissionGuard, AdminGuard } from '../auth/admin.guard';
import { RequireAdminPermission } from '../auth/admin-permission.decorator';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import type { FirebaseRequestUser } from '../auth/firebase-auth.service';
import { AdminService } from './admin.service';

@Controller('admin')
@UseGuards(FirebaseAuthGuard, AdminGuard, AdminPermissionGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('dashboard')
  @RequireAdminPermission('dashboard')
  async getDashboard() {
    return this.adminService.getDashboard();
  }

  @Get('viral')
  @RequireAdminPermission('dashboard')
  async getViralContent(@Query('hours') hours?: string, @Query('limit') limit?: string) {
    return this.adminService.getViralContent(hours ? Number(hours) : undefined, limit ? Number(limit) : undefined);
  }

  @Get('viral/alerts')
  @RequireAdminPermission('dashboard')
  async getViralAlerts(@Query('acknowledged') acknowledged?: string) {
    const normalized = acknowledged === undefined ? undefined : acknowledged === 'true';
    return this.adminService.getViralAlerts(normalized);
  }

  @Post('viral/alerts/:alertId/acknowledge')
  @RequireAdminPermission('dashboard')
  async acknowledgeViralAlert(@Param('alertId') alertId: string, @CurrentUser() admin: FirebaseRequestUser) {
    return this.adminService.acknowledgeViralAlert(alertId, admin.uid);
  }

  @Get('users')
  @RequireAdminPermission('users')
  async getAllUsers(@Query('limit') limit?: string, @Query('offset') offset?: string) {
    return this.adminService.getAllUsers(limit ? Number(limit) : undefined, offset ? Number(offset) : undefined);
  }

  @Get('users/:userId')
  @RequireAdminPermission('users')
  async getUserDetails(@Param('userId') userId: string) {
    return this.adminService.getUserDetails(userId);
  }

  @Put('users/:userId/role')
  @RequireAdminPermission('users')
  async updateUserRole(@Param('userId') userId: string, @Body('role') role: string, @CurrentUser() admin: FirebaseRequestUser) {
    return this.adminService.updateUserRole(userId, role, admin.uid);
  }

  @Post('users/:userId/suspend')
  @RequireAdminPermission('users')
  async suspendUser(
    @Param('userId') userId: string,
    @Body('reason') reason: string,
    @CurrentUser() admin: FirebaseRequestUser,
  ) {
    return this.adminService.suspendUser(userId, reason, admin.uid);
  }

  @Post('users/:userId/unsuspend')
  @RequireAdminPermission('users')
  async unsuspendUser(@Param('userId') userId: string, @CurrentUser() admin: FirebaseRequestUser) {
    return this.adminService.unsuspendUser(userId, admin.uid);
  }

  @Post('users/:userId/ban')
  @RequireAdminPermission('users')
  async banUser(@Param('userId') userId: string, @Body('reason') reason: string, @CurrentUser() admin: FirebaseRequestUser) {
    return this.adminService.banUser(userId, reason, admin.uid);
  }

  @Post('users/:userId/unban')
  @RequireAdminPermission('users')
  async unbanUser(@Param('userId') userId: string, @CurrentUser() admin: FirebaseRequestUser) {
    return this.adminService.unbanUser(userId, admin.uid);
  }

  @Post('users/:userId/make-admin')
  @RequireAdminPermission('users')
  async makeAdmin(
    @Param('userId') userId: string,
    @Body('role') role: 'viewer' | 'moderator' | 'admin' | 'super_admin',
    @CurrentUser() admin: FirebaseRequestUser,
  ) {
    return this.adminService.makeAdmin(userId, role, admin.uid);
  }

  @Get('reports')
  @RequireAdminPermission('moderate')
  async getReportedContent(@Query('status') status?: string, @Query('limit') limit?: string) {
    return this.adminService.getReportedContent(status, limit ? Number(limit) : undefined);
  }

  @Get('reports/:reportId')
  @RequireAdminPermission('moderate')
  async getReportDetails(@Param('reportId') reportId: string) {
    return this.adminService.getReportDetails(reportId);
  }

  @Get('content/flags')
  @RequireAdminPermission('moderate')
  async getContentFlags(@Query('status') status?: string, @Query('limit') limit?: string) {
    return this.adminService.getContentFlags(status, limit ? Number(limit) : undefined);
  }

  @Post('content/:contentType/:contentId/flag')
  @RequireAdminPermission('moderate')
  async createContentFlag(
    @Param('contentType') contentType: string,
    @Param('contentId') contentId: string,
    @Body('reason') reason: string,
    @Body('severity') severity: number,
    @CurrentUser() admin: FirebaseRequestUser,
  ) {
    return this.adminService.createContentFlag(contentType, contentId, reason, severity, admin.uid);
  }

  @Post('content/flags/:flagId/resolve')
  @RequireAdminPermission('moderate')
  async resolveContentFlag(
    @Param('flagId') flagId: string,
    @Body('action') action: 'dismiss' | 'remove',
    @Body('notes') notes: string,
    @CurrentUser() admin: FirebaseRequestUser,
  ) {
    return this.adminService.resolveContentFlag(flagId, action, notes, admin.uid);
  }

  @Post('reports/:reportId/review')
  @RequireAdminPermission('moderate')
  async reviewReport(
    @Param('reportId') reportId: string,
    @Body('action') action: 'approve' | 'remove' | 'dismiss',
    @Body('notes') notes: string,
    @CurrentUser() admin: FirebaseRequestUser,
  ) {
    return this.adminService.reviewReport(reportId, action, admin.uid, notes);
  }

  @Get('metrics')
  @RequireAdminPermission('dashboard')
  async getMetrics(@Query('start') start: string, @Query('end') end: string) {
    return this.adminService.getMetrics({ start: new Date(start), end: new Date(end) });
  }

  @Get('metrics/realtime')
  @RequireAdminPermission('dashboard')
  async getRealTimeStats() {
    return this.adminService.getRealtimeMetrics();
  }

  @Get('analytics')
  @RequireAdminPermission('dashboard')
  async getAnalytics(@Query('days') days?: string, @Query('country') country?: string) {
    return this.adminService.getAnalyticsOverview(days ? Number(days) : undefined, country);
  }

  @Get('finance/summary')
  @RequireAdminPermission('finance')
  async getFinanceSummary(@Query('period') period?: string) {
    return this.adminService.getFinanceSummary(period);
  }

  @Get('finance/transactions')
  @RequireAdminPermission('finance')
  async getFinanceTransactions(@Query('limit') limit?: string, @Query('offset') offset?: string, @Query('type') type?: string) {
    return this.adminService.getFinanceTransactions(limit ? Number(limit) : undefined, offset ? Number(offset) : undefined, type);
  }

  @Get('finance/withdrawals')
  @RequireAdminPermission('finance')
  async getWithdrawals(@Query('status') status?: string) {
    return this.adminService.getWithdrawals(status);
  }

  @Post('finance/withdrawals/:withdrawalId/process')
  @RequireAdminPermission('finance')
  async processWithdrawal(
    @Param('withdrawalId') withdrawalId: string,
    @Body('action') action: 'approve' | 'reject' | 'mark_paid',
    @Body('notes') notes: string,
    @CurrentUser() admin: FirebaseRequestUser,
  ) {
    return this.adminService.processWithdrawal(withdrawalId, action, notes, admin.uid);
  }

  @Get('streams/active')
  @RequireAdminPermission('moderate')
  async getActiveStreams() {
    return this.adminService.getActiveStreams();
  }

  @Get('streams')
  @RequireAdminPermission('moderate')
  async getStreams(@Query('status') status?: string, @Query('region') region?: string, @Query('limit') limit?: string) {
    return this.adminService.getStreams(status, region, limit ? Number(limit) : undefined);
  }

  @Get('streams/:streamId')
  @RequireAdminPermission('moderate')
  async getStreamDetails(@Param('streamId') streamId: string) {
    return this.adminService.getStreamDetails(streamId);
  }

  @Post('streams/:streamId/stop')
  @RequireAdminPermission('moderate')
  async stopStream(@Param('streamId') streamId: string, @Body('reason') reason: string, @CurrentUser() admin: FirebaseRequestUser) {
    return this.adminService.stopStream(streamId, reason, admin.uid);
  }

  @Get('health')
  @RequireAdminPermission('dashboard')
  async getSystemHealth() {
    return this.adminService.getSystemHealth();
  }

  @Get('health/:service')
  @RequireAdminPermission('dashboard')
  async getHealthHistory(@Param('service') service: string, @Query('hours') hours?: string) {
    return this.adminService.getServiceHealth(service, hours ? Number(hours) : undefined);
  }

  @Get('audit')
  @RequireAdminPermission('admin')
  async getAuditLogs(@Query('limit') limit?: string, @Query('offset') offset?: string) {
    return this.adminService.getAuditLogs(limit ? Number(limit) : undefined, offset ? Number(offset) : undefined);
  }
}
