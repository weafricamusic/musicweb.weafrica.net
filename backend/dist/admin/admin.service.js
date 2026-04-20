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
var AdminService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminService = void 0;
const common_1 = require("@nestjs/common");
const supabase_service_1 = require("../common/supabase/supabase.service");
const agora_service_1 = require("../stream/agora/agora.service");
let AdminService = AdminService_1 = class AdminService {
    constructor(supabase, agora) {
        this.supabase = supabase;
        this.agora = agora;
        this.logger = new common_1.Logger(AdminService_1.name);
    }
    async getDashboard() {
        const [metrics, realtime, pendingFlags, viralContent] = await Promise.all([
            this.getPlatformMetrics(),
            this.getRealtimeMetrics(),
            this.getPendingFlagsCount(),
            this.getViralContent(24, 5),
        ]);
        return {
            metrics,
            realtime,
            moderation: {
                pending_flags: pendingFlags,
            },
            viral: viralContent,
            timestamp: new Date().toISOString(),
        };
    }
    async getAllUsers(limit = 100, offset = 0) {
        const { data, error } = await this.supabase.client
            .from('profiles')
            .select('*')
            .range(offset, offset + limit - 1)
            .order('created_at', { ascending: false });
        if (error)
            throw error;
        return data;
    }
    async getUserDetails(userId) {
        const { data, error } = await this.supabase.client
            .from('profiles')
            .select('*')
            .eq('id', userId)
            .single();
        if (error)
            throw error;
        return data;
    }
    async updateUserRole(userId, role, adminId) {
        const { data, error } = await this.supabase.client
            .from('profiles')
            .update({ role, updated_at: new Date().toISOString() })
            .eq('id', userId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: 'UPDATE_USER_ROLE',
            targetType: 'user',
            targetId: userId,
            details: { newRole: role },
        });
        return data;
    }
    async suspendUser(userId, reason, adminId) {
        const { data, error } = await this.supabase.client
            .from('profiles')
            .update({ status: 'suspended', suspended_at: new Date().toISOString(), updated_at: new Date().toISOString() })
            .eq('id', userId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: 'SUSPEND_USER',
            targetType: 'user',
            targetId: userId,
            details: { reason },
        });
        return data;
    }
    async unsuspendUser(userId, adminId) {
        const { data, error } = await this.supabase.client
            .from('profiles')
            .update({ status: 'active', suspended_at: null, updated_at: new Date().toISOString() })
            .eq('id', userId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: 'UNSUSPEND_USER',
            targetType: 'user',
            targetId: userId,
        });
        return data;
    }
    async banUser(userId, reason, adminId) {
        const { data, error } = await this.supabase.client
            .from('profiles')
            .update({
            status: 'banned',
            banned_at: new Date().toISOString(),
            ban_reason: reason,
            banned_by: adminId,
            updated_at: new Date().toISOString(),
        })
            .eq('id', userId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: 'BAN_USER',
            targetType: 'user',
            targetId: userId,
            details: { reason },
        });
        return data;
    }
    async unbanUser(userId, adminId) {
        const { data, error } = await this.supabase.client
            .from('profiles')
            .update({
            status: 'active',
            banned_at: null,
            ban_reason: null,
            banned_by: null,
            updated_at: new Date().toISOString(),
        })
            .eq('id', userId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: 'UNBAN_USER',
            targetType: 'user',
            targetId: userId,
        });
        return data;
    }
    async makeAdmin(userId, role, adminId) {
        const { data: adminProfile, error: adminError } = await this.supabase.client
            .from('profiles')
            .select('admin_role')
            .eq('id', adminId)
            .single();
        if (adminError)
            throw adminError;
        if (!adminProfile || adminProfile.admin_role !== 'super_admin') {
            throw new common_1.ForbiddenException('Only super admin can promote users');
        }
        const { data, error } = await this.supabase.client
            .from('profiles')
            .update({
            is_admin: true,
            admin_role: role,
            promoted_by: adminId,
            promoted_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
        })
            .eq('id', userId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: 'MAKE_ADMIN',
            targetType: 'user',
            targetId: userId,
            details: { role },
        });
        return data;
    }
    async getReportedContent(status, limit = 50) {
        let query = this.supabase.client.from('content_reports').select('*').order('created_at', { ascending: false }).limit(limit);
        if (status) {
            query = query.eq('status', status);
        }
        const { data, error } = await query;
        if (error)
            throw error;
        return data;
    }
    async getReportDetails(reportId) {
        const { data: report, error } = await this.supabase.client
            .from('content_reports')
            .select('*')
            .eq('id', reportId)
            .maybeSingle();
        if (error)
            throw error;
        if (!report)
            return null;
        const { data: history, error: historyError } = await this.supabase.client
            .from('content_reports')
            .select('id,status,created_at,reason,reviewed_at')
            .eq('target_type', report.target_type)
            .eq('target_id', report.target_id)
            .order('created_at', { ascending: false })
            .limit(10);
        if (historyError)
            throw historyError;
        return {
            report,
            history: history ?? [],
        };
    }
    async reviewReport(reportId, action, adminId, notes) {
        const { data: report, error: fetchError } = await this.supabase.client
            .from('content_reports')
            .select('*')
            .eq('id', reportId)
            .single();
        if (fetchError)
            throw fetchError;
        const nextStatus = action === 'dismiss' ? 'dismissed' : 'reviewed';
        const { data, error } = await this.supabase.client
            .from('content_reports')
            .update({
            status: nextStatus,
            reviewed_by: adminId,
            reviewed_at: new Date().toISOString(),
            details: { action, notes },
        })
            .eq('id', reportId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: `REVIEW_REPORT_${action.toUpperCase()}`,
            targetType: 'report',
            targetId: reportId,
            details: { notes, target_type: report.target_type, target_id: report.target_id },
        });
        if (action === 'remove') {
            await this.removeContent(report.target_type, report.target_id, adminId, notes);
        }
        return data;
    }
    async getMetrics(dateRange) {
        const { data, error } = await this.supabase.client
            .from('platform_metrics')
            .select('*')
            .gte('date', dateRange.start.toISOString().split('T')[0])
            .lte('date', dateRange.end.toISOString().split('T')[0])
            .order('date', { ascending: true });
        if (error)
            throw error;
        return data;
    }
    async getRealTimeStats() {
        return this.getRealtimeMetrics();
    }
    async getRealtimeMetrics() {
        const [activeLives, activeBattles, activeUsers] = await Promise.all([
            this.supabase.client.from('live_sessions').select('count', { count: 'exact', head: true }).eq('is_live', true),
            this.supabase.client.from('live_battles').select('count', { count: 'exact', head: true }).eq('status', 'live'),
            this.supabase.client
                .from('profiles')
                .select('count', { count: 'exact', head: true })
                // best-effort: last_seen may not exist in all schemas.
                .gte('updated_at', new Date(Date.now() - 5 * 60 * 1000).toISOString()),
        ]);
        return {
            active_streams: activeLives.count || 0,
            active_battles: activeBattles.count || 0,
            active_users: activeUsers.count || 0,
            timestamp: new Date().toISOString(),
        };
    }
    async getViralContent(hours = 24, limit = 50) {
        const cutoff = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
        const { data, error } = await this.supabase.client
            .from('feed_items')
            .select('*')
            .gte('created_at', cutoff)
            .order('score', { ascending: false })
            .order('created_at', { ascending: false })
            .limit(limit);
        if (error)
            throw error;
        return data ?? [];
    }
    async getViralAlerts(acknowledged) {
        let query = this.supabase.client.from('viral_alerts').select('*').order('triggered_at', { ascending: false });
        if (acknowledged === true) {
            query = query.not('acknowledged_by', 'is', null);
        }
        else if (acknowledged === false) {
            query = query.is('acknowledged_by', null);
        }
        const { data, error } = await query;
        if (error)
            throw error;
        return data ?? [];
    }
    async acknowledgeViralAlert(alertId, adminId) {
        const { data, error } = await this.supabase.client
            .from('viral_alerts')
            .update({
            acknowledged_by: adminId,
            acknowledged_at: new Date().toISOString(),
        })
            .eq('id', alertId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: 'ACKNOWLEDGE_VIRAL_ALERT',
            targetType: 'viral_alert',
            targetId: alertId,
        });
        return data;
    }
    async getContentFlags(status, limit = 50) {
        let query = this.supabase.client.from('content_flags').select('*').order('created_at', { ascending: false }).limit(limit);
        if (status) {
            query = query.eq('status', status);
        }
        const { data, error } = await query;
        if (error)
            throw error;
        return data ?? [];
    }
    async createContentFlag(contentType, contentId, reason, severity = 1, adminId) {
        const { data, error } = await this.supabase.client
            .from('content_flags')
            .insert({
            content_type: contentType,
            content_id: contentId,
            reported_by: adminId,
            reason,
            severity,
            status: 'pending',
            created_at: new Date().toISOString(),
        })
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: 'CREATE_CONTENT_FLAG',
            targetType: contentType,
            targetId: contentId,
            details: { reason, severity },
        });
        return data;
    }
    async resolveContentFlag(flagId, action, notes, adminId) {
        const { data: flag, error: flagError } = await this.supabase.client
            .from('content_flags')
            .select('*')
            .eq('id', flagId)
            .single();
        if (flagError)
            throw flagError;
        if (action === 'remove') {
            await this.removeContent(flag.content_type, flag.content_id, adminId, notes);
        }
        const status = action === 'dismiss' ? 'dismissed' : 'resolved';
        const { data, error } = await this.supabase.client
            .from('content_flags')
            .update({
            status,
            resolution: action,
            resolution_notes: notes ?? null,
            resolved_by: adminId,
            resolved_at: new Date().toISOString(),
        })
            .eq('id', flagId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: `RESOLVE_CONTENT_FLAG_${action.toUpperCase()}`,
            targetType: flag.content_type,
            targetId: flag.content_id,
            details: { flagId, notes },
        });
        return data;
    }
    async getFinanceSummary(period = 'month') {
        const startDate = new Date();
        if (period === 'week')
            startDate.setDate(startDate.getDate() - 7);
        else if (period === 'year')
            startDate.setFullYear(startDate.getFullYear() - 1);
        else
            startDate.setMonth(startDate.getMonth() - 1);
        const financeCoreSummary = await this.tryGetFinanceCoreSummary(startDate.toISOString());
        if (financeCoreSummary) {
            return {
                period,
                start_date: startDate.toISOString(),
                ...financeCoreSummary,
            };
        }
        const [purchases, withdrawals] = await Promise.all([
            this.supabase.client.from('coin_purchases').select('amount_paid, status').gte('created_at', startDate.toISOString()),
            this.supabase.client.from('withdrawal_requests').select('amount, status').gte('created_at', startDate.toISOString()),
        ]);
        if (purchases.error)
            throw purchases.error;
        if (withdrawals.error)
            throw withdrawals.error;
        const totalRevenue = (purchases.data ?? []).reduce((sum, purchase) => sum + Number(purchase.amount_paid ?? 0), 0);
        const totalPayouts = (withdrawals.data ?? [])
            .filter((row) => ['approved', 'paid'].includes(String(row.status ?? '')))
            .reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
        return {
            period,
            start_date: startDate.toISOString(),
            total_revenue: totalRevenue,
            total_payouts: totalPayouts,
            platform_fees: totalRevenue * 0.3,
            net_revenue: totalRevenue - totalPayouts,
        };
    }
    async getFinanceTransactions(limit = 100, offset = 0, type) {
        let query = this.supabase.client
            .from('wallet_transactions')
            .select('*')
            .order('created_at', { ascending: false })
            .range(offset, offset + limit - 1);
        if (type) {
            query = query.eq('type', type);
        }
        const { data, error } = await query;
        if (error)
            throw error;
        return data ?? [];
    }
    async getWithdrawals(status) {
        const financeCoreRows = await this.tryGetFinanceCoreWithdrawals(status);
        if (financeCoreRows) {
            return this.enrichFinanceCoreWithdrawals(financeCoreRows);
        }
        let query = this.supabase.client.from('withdrawal_requests').select('*').order('created_at', { ascending: false });
        if (status) {
            query = query.eq('status', status);
        }
        const { data, error } = await query;
        if (error)
            throw error;
        return (data ?? []).map((row) => ({
            id: String(row.id),
            beneficiary_type: 'user',
            beneficiary_id: String(row.user_id ?? ''),
            display_name: String(row.user_id ?? 'User'),
            amount_mwk: Number(row.amount ?? 0),
            method: String(row.payment_method ?? 'unknown'),
            status: String(row.status ?? 'pending'),
            requested_at: String(row.created_at ?? new Date().toISOString()),
            admin_email: null,
            note: row.admin_notes ?? null,
            source_table: 'withdrawal_requests',
        }));
    }
    async processWithdrawal(withdrawalId, action, notes, adminId) {
        const processedFinanceCore = await this.tryProcessFinanceCoreWithdrawal(withdrawalId, action, notes, adminId);
        if (processedFinanceCore) {
            return processedFinanceCore;
        }
        const nextStatus = action === 'approve' ? 'approved' : action === 'mark_paid' ? 'paid' : 'rejected';
        const { data, error } = await this.supabase.client
            .from('withdrawal_requests')
            .update({
            status: nextStatus,
            admin_notes: notes ?? null,
            updated_at: new Date().toISOString(),
        })
            .eq('id', withdrawalId)
            .select()
            .single();
        if (error)
            throw error;
        await this.logAdminAction({
            adminId,
            action: `PROCESS_WITHDRAWAL_${action.toUpperCase()}`,
            targetType: 'withdrawal',
            targetId: withdrawalId,
            details: { notes },
        });
        return data;
    }
    async getAnalyticsOverview(days = 7, country) {
        const normalizedDays = Math.max(1, Math.min(90, Math.floor(days || 7)));
        const rangeStart = new Date(Date.now() - normalizedDays * 24 * 60 * 60 * 1000).toISOString();
        const warnings = [];
        const safeCount = async (table, apply) => {
            try {
                let query = this.supabase.client.from(table).select('*', { head: true, count: 'exact' });
                query = apply ? apply(query) : query;
                const { count, error } = await query;
                if (error)
                    return null;
                return typeof count === 'number' ? count : null;
            }
            catch {
                return null;
            }
        };
        const safeList = async (table, select, apply, limit = 5000) => {
            try {
                let query = this.supabase.client.from(table).select(select);
                query = apply ? apply(query) : query;
                query = query.limit(limit);
                const { data, error } = await query;
                if (error)
                    return null;
                return data ?? [];
            }
            catch {
                return null;
            }
        };
        const safeRpc = async (fn, args) => {
            try {
                const { data, error } = await this.supabase.client.rpc(fn, args);
                if (error)
                    return null;
                return (data ?? null);
            }
            catch {
                return null;
            }
        };
        const isoDay = (value) => {
            try {
                if (!value)
                    return null;
                const date = new Date(String(value));
                if (Number.isNaN(date.getTime()))
                    return null;
                return date.toISOString().slice(0, 10);
            }
            catch {
                return null;
            }
        };
        const daySeriesSum = (rows, dateCol, valueCol) => {
            if (!rows)
                return null;
            const byDay = new Map();
            for (const row of rows) {
                const day = isoDay(row?.[dateCol]);
                if (!day)
                    continue;
                const value = Number(row?.[valueCol] ?? 0);
                if (!Number.isFinite(value))
                    continue;
                byDay.set(day, (byDay.get(day) ?? 0) + value);
            }
            return Array.from(byDay.entries())
                .sort((a, b) => a[0].localeCompare(b[0]))
                .map(([day, value]) => ({ day, value }));
        };
        const daySeriesCount = (rows, dateCol) => {
            if (!rows)
                return null;
            const byDay = new Map();
            for (const row of rows) {
                const day = isoDay(row?.[dateCol]);
                if (!day)
                    continue;
                byDay.set(day, (byDay.get(day) ?? 0) + 1);
            }
            return Array.from(byDay.entries())
                .sort((a, b) => a[0].localeCompare(b[0]))
                .map(([day, value]) => ({ day, value }));
        };
        const sumNumber = (rows, key) => {
            if (!rows)
                return null;
            return rows.reduce((sum, row) => sum + (Number.isFinite(Number(row?.[key])) ? Number(row?.[key]) : 0), 0);
        };
        const sumByKey = (rows, keyCol, valueCol) => {
            if (!rows)
                return null;
            const output = {};
            for (const row of rows) {
                const key = String(row?.[keyCol] ?? '').trim() || 'unknown';
                const value = Number(row?.[valueCol] ?? 0);
                if (!Number.isFinite(value))
                    continue;
                output[key] = (output[key] ?? 0) + value;
            }
            return output;
        };
        const revenueTypes = ['coin_purchase', 'subscription', 'ad'];
        const transactions = await safeList('transactions', 'type,amount_mwk,coins,created_at,country_code', (query) => query.gte('created_at', rangeStart).in('type', revenueTypes).order('created_at', { ascending: false }));
        if (transactions === null)
            warnings.push('transactions table not accessible');
        const withdrawals = await this.getWithdrawals('pending').catch(() => null);
        if (withdrawals === null)
            warnings.push('withdrawals not accessible');
        const profileRows = await safeList('profiles', 'created_at', (query) => query.gte('created_at', rangeStart).order('created_at', { ascending: false }));
        if (profileRows === null)
            warnings.push('profiles time series not available');
        const songsRows = await safeList('songs', 'created_at', (query) => query.gte('created_at', rangeStart).order('created_at', { ascending: false }));
        if (songsRows === null)
            warnings.push('songs time series not available');
        const videosRows = await safeList('videos', 'created_at', (query) => query.gte('created_at', rangeStart).order('created_at', { ascending: false }));
        if (videosRows === null)
            warnings.push('videos time series not available');
        const openReports = await safeCount('content_reports', (query) => query.eq('status', 'pending'));
        if (openReports === null)
            warnings.push('content_reports table not accessible');
        const frozenEarningsAccounts = await safeCount('earnings_freeze_state', (query) => query.eq('frozen', true));
        if (frozenEarningsAccounts === null)
            warnings.push('earnings_freeze_state table not accessible');
        const activeStreams = await safeCount('live_sessions', (query) => query.eq('is_live', true));
        if (activeStreams === null)
            warnings.push('live_sessions table not accessible');
        const recentStreams = await safeList('live_sessions', 'viewer_count,started_at,is_live,region', (query) => query.gte('started_at', rangeStart).order('started_at', { ascending: false }), 2500);
        if (recentStreams === null)
            warnings.push('live_sessions time series not available');
        const avgViewersRecent = recentStreams && recentStreams.length
            ? recentStreams.reduce((sum, row) => sum + Number(row?.viewer_count ?? 0), 0) / recentStreams.length
            : null;
        const maxViewersRecent = recentStreams && recentStreams.length
            ? Math.max(...recentStreams.map((row) => Number(row?.viewer_count ?? 0)))
            : null;
        const dau1d = await safeRpc('analytics_distinct_users', {
            p_since: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
            p_event_name: 'app_open',
            p_country_code: country ?? null,
        });
        const mau30d = await safeRpc('analytics_distinct_users', {
            p_since: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
            p_event_name: 'app_open',
            p_country_code: country ?? null,
        });
        if (dau1d === null || mau30d === null)
            warnings.push('behavior telemetry not available');
        const joinTelemetry = await safeRpc('analytics_stream_join_success_rate', {
            p_days: normalizedDays,
            p_country_code: country ?? null,
        });
        if (!joinTelemetry)
            warnings.push('stream join telemetry not available');
        const joinRow = Array.isArray(joinTelemetry) ? joinTelemetry[0] : joinTelemetry;
        return {
            range: {
                days: normalizedDays,
                startIso: rangeStart,
            },
            country: country ?? null,
            revenueSeriesMwk: daySeriesSum(transactions, 'created_at', 'amount_mwk'),
            coinsSoldSeries: daySeriesSum(transactions, 'created_at', 'coins'),
            newUsersSeries: daySeriesCount(profileRows, 'created_at'),
            newSongsSeries: daySeriesCount(songsRows, 'created_at'),
            newVideosSeries: daySeriesCount(videosRows, 'created_at'),
            streamsStartedSeries: daySeriesCount(recentStreams, 'started_at'),
            revenueMwk: sumNumber(transactions, 'amount_mwk'),
            revenueByTypeMwk: sumByKey(transactions, 'type', 'amount_mwk'),
            coinsSold: sumNumber(transactions, 'coins'),
            pendingWithdrawalsMwk: Array.isArray(withdrawals)
                ? withdrawals.reduce((sum, row) => sum + Number(row?.amount_mwk ?? 0), 0)
                : null,
            pendingWithdrawalsCount: Array.isArray(withdrawals) ? withdrawals.length : null,
            newUsers: profileRows?.length ?? null,
            newSongs: songsRows?.length ?? null,
            newVideos: videosRows?.length ?? null,
            dau1d,
            mau30d,
            stickiness: dau1d != null && mau30d != null && mau30d > 0 ? dau1d / mau30d : null,
            openReports,
            frozenEarningsAccounts,
            activeStreams,
            avgViewersRecent,
            maxViewersRecent,
            streamJoinAttempts: joinRow ? Number(joinRow.attempts ?? 0) : null,
            streamJoinSuccesses: joinRow ? Number(joinRow.successes ?? 0) : null,
            streamJoinSuccessRate: joinRow?.success_rate == null ? null : Number(joinRow.success_rate),
            warnings,
        };
    }
    async getActiveStreams() {
        return this.getStreams('live');
    }
    async getStreams(status = 'live', region, limit = 250) {
        let query = this.supabase.client
            .from('live_sessions')
            .select('*')
            .order('is_live', { ascending: false })
            .order('viewer_count', { ascending: false })
            .order('started_at', { ascending: false })
            .limit(limit);
        const normalizedStatus = String(status ?? 'live').trim().toLowerCase();
        if (normalizedStatus === 'live') {
            query = query.eq('is_live', true);
        }
        else if (normalizedStatus === 'ended') {
            query = query.eq('is_live', false);
        }
        const normalizedRegion = String(region ?? '').trim().toUpperCase();
        if (normalizedRegion) {
            query = query.eq('region', normalizedRegion);
        }
        const { data, error } = await query;
        if (error)
            throw error;
        return this.enrichStreams(data ?? []);
    }
    async getStreamDetails(streamId) {
        const { data, error } = await this.supabase.client
            .from('live_sessions')
            .select('*')
            .eq('id', streamId)
            .maybeSingle();
        if (error)
            throw error;
        if (!data)
            return null;
        const [stream] = await this.enrichStreams([data]);
        return stream ?? null;
    }
    async stopStream(streamId, reason, adminId) {
        const { data: existing, error: readError } = await this.supabase.client
            .from('live_sessions')
            .select('*')
            .eq('id', streamId)
            .maybeSingle();
        if (readError)
            throw readError;
        if (!existing) {
            throw new Error('Stream not found');
        }
        let kickRuleId = null;
        const channelName = String(existing.channel_id ?? '').trim();
        if (channelName) {
            const kickResult = await this.agora.tryKickChannel({ channelName, seconds: 600 });
            if (kickResult.attempted && kickResult.ok) {
                kickRuleId = kickResult.ruleId ?? null;
            }
            else if (kickResult.attempted && !kickResult.ok) {
                this.logger.warn(`Agora kick failed for stream ${streamId}: ${kickResult.error}`);
            }
        }
        const { data, error } = await this.supabase.client
            .from('live_sessions')
            .update({
            is_live: false,
            status: 'ended',
            ended_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
        })
            .eq('id', streamId)
            .select()
            .single();
        if (error) {
            if (kickRuleId) {
                await this.agora.tryDeleteKickingRule({ ruleId: kickRuleId });
            }
            throw error;
        }
        await this.logAdminAction({
            adminId,
            action: 'STOP_STREAM',
            targetType: 'live_session',
            targetId: streamId,
            details: { reason, channel_id: existing.channel_id ?? null, agora_rule_id: kickRuleId },
        });
        const [stream] = await this.enrichStreams([data]);
        return stream ?? data;
    }
    async getSystemHealth() {
        const services = ['api', 'database', 'redis', 'agora'];
        const health = await Promise.all(services.map(async (service) => {
            const { data, error } = await this.supabase.client
                .from('system_health')
                .select('*')
                .eq('service', service)
                .order('checked_at', { ascending: false })
                .limit(1)
                .maybeSingle();
            if (error)
                throw error;
            return [service, data ?? { status: 'unknown' }];
        }));
        return Object.fromEntries(health);
    }
    async getServiceHealth(service, hours = 24) {
        return this.getHealthHistory(service, hours);
    }
    async recordHealthCheck(service, status, responseTimeMs, error) {
        const { error: dbError } = await this.supabase.client.from('system_health').insert({
            service,
            status,
            response_time_ms: responseTimeMs,
            error_message: error,
            checked_at: new Date().toISOString(),
        });
        if (dbError)
            throw dbError;
    }
    async getHealthHistory(service, hours = 24) {
        const cutoff = new Date(Date.now() - hours * 60 * 60 * 1000);
        const { data, error } = await this.supabase.client
            .from('system_health')
            .select('*')
            .eq('service', service)
            .gte('checked_at', cutoff.toISOString())
            .order('checked_at', { ascending: false });
        if (error)
            throw error;
        return data;
    }
    async logAdminAction(data) {
        const { error } = await this.supabase.client.from('admin_audit_logs').insert({
            admin_id: data.adminId,
            action: data.action,
            target_type: data.targetType,
            target_id: data.targetId,
            details: data.details ?? {},
            ip_address: data.ipAddress,
            user_agent: data.userAgent,
            created_at: new Date().toISOString(),
        });
        if (error) {
            this.logger.error(`Failed to log admin action: ${error.message}`);
        }
    }
    async getAuditLogs(limit = 100, offset = 0) {
        const { data, error } = await this.supabase.client
            .from('admin_audit_logs')
            .select('*')
            .order('created_at', { ascending: false })
            .range(offset, offset + limit - 1);
        if (error)
            throw error;
        return data;
    }
    async getPlatformMetrics() {
        const [users, songs, videos, battles, revenue] = await Promise.all([
            this.supabase.client.from('profiles').select('count', { count: 'exact', head: true }),
            this.supabase.client.from('songs').select('count', { count: 'exact', head: true }),
            this.supabase.client.from('videos').select('count', { count: 'exact', head: true }),
            this.supabase.client.from('live_battles').select('count', { count: 'exact', head: true }),
            this.supabase.client.from('coin_purchases').select('amount_paid'),
        ]);
        const totalRevenue = (revenue.data ?? []).reduce((sum, row) => sum + Number(row.amount_paid ?? 0), 0);
        return {
            total_users: users.count || 0,
            total_songs: songs.count || 0,
            total_videos: videos.count || 0,
            total_battles: battles.count || 0,
            total_revenue: totalRevenue,
        };
    }
    async getPendingFlagsCount() {
        const { count, error } = await this.supabase.client
            .from('content_flags')
            .select('count', { count: 'exact', head: true })
            .eq('status', 'pending');
        if (error)
            throw error;
        return count || 0;
    }
    async removeContent(contentType, contentId, adminId, reason) {
        if (contentType === 'song') {
            const { error } = await this.supabase.client
                .from('songs')
                .update({ status: 'removed' })
                .eq('id', contentId);
            if (error)
                throw error;
        }
        else if (contentType === 'video') {
            const { error } = await this.supabase.client
                .from('videos')
                .update({ status: 'removed' })
                .eq('id', contentId);
            if (error)
                throw error;
        }
        else if (contentType === 'event') {
            const { error } = await this.supabase.client
                .from('events')
                .update({ status: 'cancelled' })
                .eq('id', contentId);
            if (error)
                throw error;
        }
        else if (contentType === 'live') {
            const { error } = await this.supabase.client
                .from('live_sessions')
                .update({ is_live: false, ended_at: new Date().toISOString(), updated_at: new Date().toISOString() })
                .eq('id', contentId);
            if (error)
                throw error;
        }
        await this.logAdminAction({
            adminId,
            action: 'REMOVE_CONTENT',
            targetType: contentType,
            targetId: contentId,
            details: { reason },
        });
    }
    async tryGetFinanceCoreSummary(startIso) {
        try {
            const [transactions, withdrawals] = await Promise.all([
                this.supabase.client.from('transactions').select('amount_mwk,type').gte('created_at', startIso),
                this.supabase.client.from('withdrawals').select('amount_mwk,status').gte('requested_at', startIso),
            ]);
            if (transactions.error || withdrawals.error)
                return null;
            const totalRevenue = (transactions.data ?? []).reduce((sum, row) => sum + Number(row.amount_mwk ?? 0), 0);
            const totalPayouts = (withdrawals.data ?? [])
                .filter((row) => ['approved', 'paid'].includes(String(row.status ?? '')))
                .reduce((sum, row) => sum + Number(row.amount_mwk ?? 0), 0);
            return {
                total_revenue: totalRevenue,
                total_payouts: totalPayouts,
                platform_fees: totalRevenue * 0.3,
                net_revenue: totalRevenue - totalPayouts,
            };
        }
        catch {
            return null;
        }
    }
    async tryGetFinanceCoreWithdrawals(status) {
        try {
            let query = this.supabase.client.from('withdrawals').select('*').order('requested_at', { ascending: false });
            if (status)
                query = query.eq('status', status);
            const { data, error } = await query;
            if (error)
                return null;
            return data ?? [];
        }
        catch {
            return null;
        }
    }
    async enrichFinanceCoreWithdrawals(rows) {
        const artistIds = [...new Set(rows.filter((row) => row?.beneficiary_type === 'artist').map((row) => String(row.beneficiary_id)))];
        const djIds = [...new Set(rows.filter((row) => row?.beneficiary_type === 'dj').map((row) => String(row.beneficiary_id)))];
        const artistNames = new Map();
        const djNames = new Map();
        if (artistIds.length) {
            const { data } = await this.supabase.client.from('artists').select('id,name,stage_name').in('id', artistIds);
            (data ?? []).forEach((row) => artistNames.set(String(row.id), String(row.stage_name ?? row.name ?? 'Artist')));
        }
        if (djIds.length) {
            const { data } = await this.supabase.client.from('djs').select('id,name,stage_name').in('id', djIds);
            (data ?? []).forEach((row) => djNames.set(String(row.id), String(row.stage_name ?? row.name ?? 'DJ')));
        }
        return rows.map((row) => ({
            id: String(row.id),
            beneficiary_type: String(row.beneficiary_type ?? 'user'),
            beneficiary_id: String(row.beneficiary_id ?? ''),
            display_name: String(row.beneficiary_type) === 'artist'
                ? artistNames.get(String(row.beneficiary_id)) ?? 'Artist'
                : djNames.get(String(row.beneficiary_id)) ?? 'DJ',
            amount_mwk: Number(row.amount_mwk ?? 0),
            method: String(row.method ?? 'unknown'),
            status: String(row.status ?? 'pending'),
            requested_at: String(row.requested_at ?? new Date().toISOString()),
            admin_email: (row.admin_email ?? null),
            note: (row.note ?? null),
            source_table: 'withdrawals',
        }));
    }
    async tryProcessFinanceCoreWithdrawal(withdrawalId, action, notes, adminId) {
        try {
            const { data: adminProfile } = await this.supabase.client.from('profiles').select('email').eq('id', adminId).maybeSingle();
            const adminEmail = String(adminProfile?.email ?? '');
            const { data: row, error: readError } = await this.supabase.client.from('withdrawals').select('*').eq('id', withdrawalId).maybeSingle();
            if (readError || !row)
                return null;
            if (action === 'approve' && String(row.status) !== 'pending') {
                throw new Error('Only pending withdrawals can be approved');
            }
            if (action === 'reject' && String(row.status) !== 'pending') {
                throw new Error('Only pending withdrawals can be rejected');
            }
            if (action === 'mark_paid' && String(row.status) !== 'approved') {
                throw new Error('Only approved withdrawals can be marked paid');
            }
            const now = new Date().toISOString();
            const payload = {
                admin_email: adminEmail || null,
                note: notes ?? row.note ?? null,
            };
            if (action === 'approve') {
                payload.status = 'approved';
                payload.approved_at = now;
            }
            else if (action === 'reject') {
                payload.status = 'rejected';
                payload.rejected_at = now;
            }
            else {
                payload.status = 'paid';
                payload.paid_at = now;
            }
            const { data, error } = await this.supabase.client.from('withdrawals').update(payload).eq('id', withdrawalId).select().single();
            if (error)
                throw error;
            await this.logAdminAction({
                adminId,
                action: `PROCESS_WITHDRAWAL_${action.toUpperCase()}`,
                targetType: 'withdrawal',
                targetId: withdrawalId,
                details: { notes, source_table: 'withdrawals' },
            });
            const [normalized] = await this.enrichFinanceCoreWithdrawals([data]);
            return normalized ?? data;
        }
        catch (error) {
            if (error instanceof Error && /Only .* withdrawals can/.test(error.message)) {
                throw error;
            }
            return null;
        }
    }
    async enrichStreams(rows) {
        if (!rows.length)
            return [];
        const djIds = [...new Set(rows.filter((row) => row?.host_type === 'dj' && row?.host_id).map((row) => String(row.host_id)))];
        const artistIds = [
            ...new Set(rows
                .filter((row) => (row?.host_type === 'artist' || row?.artist_id) && (row?.artist_id ?? row?.host_id))
                .map((row) => String(row.artist_id ?? row.host_id))),
        ];
        const djsById = new Map();
        const artistsById = new Map();
        if (djIds.length) {
            const { data } = await this.supabase.client.from('djs').select('*').in('id', djIds);
            (data ?? []).forEach((row) => djsById.set(String(row.id), row));
        }
        if (artistIds.length) {
            const { data } = await this.supabase.client.from('artists').select('*').in('id', artistIds);
            (data ?? []).forEach((row) => artistsById.set(String(row.id), row));
        }
        return rows.map((row) => {
            const hostType = String(row?.host_type ?? (row?.artist_id ? 'artist' : 'dj')).toLowerCase() === 'artist' ? 'artist' : 'dj';
            const hostId = String(row?.artist_id ?? row?.host_id ?? '');
            const hostProfile = hostType === 'artist' ? artistsById.get(hostId) : djsById.get(hostId);
            const streamTypeRaw = String(row?.stream_type ?? (hostType === 'artist' ? 'artist_live' : 'dj_live')).toLowerCase();
            const status = row?.is_live === true || String(row?.status ?? '').toLowerCase() === 'live' ? 'live' : 'ended';
            return {
                id: String(row?.id ?? ''),
                channel_name: String(row?.channel_id ?? row?.channel_name ?? ''),
                streamer_name: String(hostProfile?.stage_name ?? hostProfile?.dj_name ?? hostProfile?.name ?? row?.host_name ?? row?.title ?? 'Creator'),
                streamer_avatar_url: (hostProfile?.avatar_url ?? hostProfile?.photo_url ?? hostProfile?.profile_image_url ?? row?.thumbnail_url ?? null),
                host_type: hostType,
                stream_type: streamTypeRaw === 'battle' ? 'battle' : streamTypeRaw === 'artist_live' ? 'artist_live' : 'dj_live',
                status,
                viewers: Number(row?.viewer_count ?? 0) || 0,
                started_at: (row?.started_at ?? null),
                ended_at: (row?.ended_at ?? null),
                region: String(hostProfile?.region ?? row?.region ?? 'MW').toUpperCase(),
                title: (row?.title ?? null),
                category: (row?.category ?? null),
                topic: (row?.topic ?? null),
                access_mode: (row?.access_mode ?? row?.access_tier ?? null),
                raw: row,
            };
        });
    }
};
exports.AdminService = AdminService;
exports.AdminService = AdminService = AdminService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [supabase_service_1.SupabaseService,
        agora_service_1.AgoraService])
], AdminService);
//# sourceMappingURL=admin.service.js.map