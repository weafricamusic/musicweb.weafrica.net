import { BadRequestException, Injectable, InternalServerErrorException, Logger } from '@nestjs/common';

import { RedisService } from '../common/redis/redis.service';
import { SupabaseService } from '../common/supabase/supabase.service';

type WalletSummaryResponse = {
  ok: true;
  user_id: string;
  coin_balance: number;
  total_earned: number;
  cash_balances: Record<string, number>;
  updated_at: string;
};

type WalletTransactionResponse = {
  id: string;
  type: string;
  amount: number;
  balance_type: string;
  description: string;
  currency: string | null;
  created_at: string | null;
};

type WithdrawalResponse = {
  id: string;
  amount: number;
  status: string;
  payment_method: string;
  method_label: string | null;
  currency: string | null;
  admin_notes: string | null;
  created_at: string | null;
  updated_at: string | null;
};

type CreditWalletParams = {
  userId: string;
  amount: number;
  type: string;
  description?: string;
  reference?: string;
  metadata?: Record<string, unknown>;
  incrementTotalEarned?: boolean;
};

type RequestWithdrawalParams = {
  userId: string;
  amount: number;
  currency: string;
  paymentMethod: string;
  accountDetails: Record<string, unknown>;
};

@Injectable()
export class WalletService {
  private readonly logger = new Logger(WalletService.name);
  private readonly walletSummaryTtlSeconds = 15;

  constructor(
    private readonly supabase: SupabaseService,
    private readonly redis: RedisService,
  ) {}

  async getWalletSummary(userId: string): Promise<WalletSummaryResponse> {
    const cacheKey = this.walletSummaryCacheKey(userId);

    try {
      const cached = await this.redis.client.get(cacheKey);
      if (cached) {
        return JSON.parse(cached) as WalletSummaryResponse;
      }
    } catch (error) {
      this.logger.warn(`Wallet summary cache read failed for ${userId}: ${this.stringifyError(error)}`);
    }

    const wallet = await this.ensureWallet(userId);
    const balances: Record<string, number> = { MWK: 0, USD: 0, ZAR: 0 };

    try {
      const { data, error } = await this.supabase.client
        .from('wallet_cash_balances')
        .select('currency,balance')
        .eq('user_id', userId)
        .in('currency', ['MWK', 'USD', 'ZAR'])
        .limit(10);

      if (error) {
        throw error;
      }

      for (const row of data ?? []) {
        const currency = String(row.currency ?? '').trim().toUpperCase();
        if (currency in balances) {
          balances[currency] = Number(row.balance ?? 0);
        }
      }
    } catch (_) {
      balances.MWK = Number(wallet.cash_balance ?? 0);
    }

    if (balances.MWK === 0) {
      balances.MWK = Number(wallet.cash_balance ?? 0);
    }

    const summary: WalletSummaryResponse = {
      ok: true,
      user_id: userId,
      coin_balance: Number(wallet.coin_balance ?? 0),
      total_earned: Number(wallet.total_earned ?? 0),
      cash_balances: balances,
      updated_at: String(wallet.updated_at ?? new Date().toISOString()),
    };

    await this.cacheWalletSummary(userId, summary);
    return summary;
  }

  async getWalletTransactions(userId: string, limit: number): Promise<WalletTransactionResponse[]> {
    const { data, error } = await this.supabase.client
      .from('wallet_transactions')
      .select('id,type,amount,balance_type,description,metadata,created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) {
      throw new InternalServerErrorException(`Failed to load wallet transactions: ${error.message}`);
    }

    return (data ?? []).map((row) => {
      const metadata = this.toObject(row.metadata);
      const currency = String(metadata.currency ?? '').trim().toUpperCase();
      return {
        id: String(row.id ?? ''),
        type: String(row.type ?? ''),
        amount: Number(row.amount ?? 0),
        balance_type: String(row.balance_type ?? ''),
        description: String(row.description ?? ''),
        currency: currency || null,
        created_at: row.created_at ? String(row.created_at) : null,
      };
    });
  }

  async getWithdrawals(userId: string, limit: number): Promise<WithdrawalResponse[]> {
    try {
      const { data, error } = await this.supabase.client
        .from('withdrawal_requests')
        .select('id,amount,status,payment_method,account_details,admin_notes,created_at,updated_at')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(limit);

      if (error) {
        throw error;
      }

      return (data ?? []).map((row) => this.mapLegacyWithdrawal(row));
    } catch (_) {
      const { data, error } = await this.supabase.client
        .from('withdrawals')
        .select('id,amount_mwk,status,method,note,requested_at')
        .eq('beneficiary_id', userId)
        .order('requested_at', { ascending: false })
        .limit(limit);

      if (error) {
        throw new InternalServerErrorException(`Failed to load withdrawals: ${error.message}`);
      }

      return (data ?? []).map((row) => ({
        id: String(row.id ?? ''),
        amount: Number(row.amount_mwk ?? 0),
        status: String(row.status ?? 'pending'),
        payment_method: String(row.method ?? ''),
        method_label: String(row.method ?? '') || null,
        currency: 'MWK',
        admin_notes: row.note ? String(row.note) : null,
        created_at: row.requested_at ? String(row.requested_at) : null,
        updated_at: row.requested_at ? String(row.requested_at) : null,
      }));
    }
  }

  async requestWithdrawal(params: RequestWithdrawalParams): Promise<{ ok: true; request_id: string | null; new_balance: number; currency: string }> {
    const rpc = await this.supabase.client.rpc('request_withdrawal', {
      p_user_id: params.userId,
      p_amount: params.amount,
      p_payment_method: params.paymentMethod,
      p_account_details: params.accountDetails,
    });

    if (rpc.error) {
      if (this.shouldUseWalletMutationFallback(rpc.error, 'request_withdrawal')) {
        this.logger.warn(`Falling back to non-RPC withdrawal flow for ${params.userId}: ${rpc.error.message}`);
        return this.requestWithdrawalFallback(params);
      }

      const message = rpc.error.message ?? 'Withdrawal request failed';
      const normalized = message.toLowerCase();
      if (normalized.includes('insufficient') || normalized.includes('minimum') || normalized.includes('amount')) {
        throw new BadRequestException(message);
      }

      throw new InternalServerErrorException(`request_withdrawal failed: ${message}`);
    }

    await this.invalidateWalletSummary(params.userId);

    const row = Array.isArray(rpc.data) ? rpc.data[0] : rpc.data;
    return {
      ok: true,
      request_id: row?.request_id ? String(row.request_id) : null,
      new_balance: Number(row?.new_cash_balance ?? 0),
      currency: params.currency,
    };
  }

  async addCoins(params: { userId: string; amount: number; type: string; reference: string }): Promise<void> {
    await this.creditWallet({
      userId: params.userId,
      amount: params.amount,
      type: params.type,
      description: this.describeCreditType(params.type),
      reference: params.reference,
      metadata: { source: params.type },
      incrementTotalEarned: true,
    });
  }

  async recordBattlePayouts(finalizedBattle: {
    battle_id: string;
    host_a_id: string | null;
    host_b_id: string | null;
    host_a_payout_coins: number | null;
    host_b_payout_coins: number | null;
  }): Promise<void> {
    const payouts = [
      {
        userId: finalizedBattle.host_a_id,
        amount: finalizedBattle.host_a_payout_coins,
        side: 'host_a',
      },
      {
        userId: finalizedBattle.host_b_id,
        amount: finalizedBattle.host_b_payout_coins,
        side: 'host_b',
      },
    ];

    for (const payout of payouts) {
      if (!payout.userId || !payout.amount || payout.amount <= 0) {
        continue;
      }

      await this.creditWallet({
        userId: payout.userId,
        amount: payout.amount,
        type: 'battle_reward',
        description: 'Battle reward',
        reference: `battle_reward:${finalizedBattle.battle_id}:${payout.userId}`,
        metadata: {
          source: 'battle_finalize',
          battle_id: finalizedBattle.battle_id,
          payout_side: payout.side,
        },
        incrementTotalEarned: true,
      });
    }
  }

  private async creditWallet(params: CreditWalletParams): Promise<void> {
    const rpc = await this.supabase.client.rpc('credit_wallet_balance', {
      p_user_id: params.userId,
      p_amount: params.amount,
      p_type: params.type,
      p_description: params.description ?? null,
      p_reference: params.reference ?? null,
      p_metadata: params.metadata ?? {},
      p_increment_total_earned: params.incrementTotalEarned ?? true,
    });

    if (rpc.error) {
      if (this.shouldUseWalletMutationFallback(rpc.error, 'credit_wallet_balance')) {
        this.logger.warn(`Falling back to direct wallet credit for ${params.userId}: ${rpc.error.message}`);
        await this.creditWalletFallback(params);
        return;
      }

      throw new InternalServerErrorException(`credit_wallet_balance failed: ${rpc.error.message}`);
    }

    await this.invalidateWalletSummary(params.userId);
  }

  private async ensureWallet(userId: string): Promise<Record<string, unknown>> {
    const now = new Date().toISOString();
    const { error: upsertError } = await this.supabase.client
      .from('wallets')
      .upsert(
        {
          user_id: userId,
          coin_balance: 0,
          cash_balance: 0,
          total_earned: 0,
          updated_at: now,
        },
        { onConflict: 'user_id', ignoreDuplicates: true },
      );

    if (upsertError) {
      if (this.isMissingConflictTargetError(upsertError)) {
        return this.ensureWalletWithoutUpsert(userId, now);
      }

      throw new InternalServerErrorException(`Failed to create wallet: ${upsertError.message}`);
    }

    const { data, error } = await this.supabase.client
      .from('wallets')
      .select('user_id,coin_balance,cash_balance,total_earned,updated_at')
      .eq('user_id', userId)
      .maybeSingle();

    if (error) {
      throw new InternalServerErrorException(`Failed to load wallet: ${error.message}`);
    }

    return data ?? {
      user_id: userId,
      coin_balance: 0,
      cash_balance: 0,
      total_earned: 0,
      updated_at: now,
    };
  }

  private async requestWithdrawalFallback(params: RequestWithdrawalParams): Promise<{ ok: true; request_id: string | null; new_balance: number; currency: string }> {
    const wallet = await this.ensureWallet(params.userId);
    const currentCashBalance = Number(wallet.cash_balance ?? 0);

    if (params.amount < 10) {
      throw new BadRequestException('minimum withdrawal amount is 10');
    }

    if (currentCashBalance < params.amount) {
      throw new BadRequestException('insufficient cash balance');
    }

    const now = new Date().toISOString();
    const newCashBalance = currentCashBalance - params.amount;

    const insertWithdrawal = await this.supabase.client
      .from('withdrawal_requests')
      .insert({
        user_id: params.userId,
        amount: params.amount,
        status: 'pending',
        payment_method: params.paymentMethod,
        account_details: params.accountDetails,
        created_at: now,
        updated_at: now,
      })
      .select('id')
      .single();

    if (insertWithdrawal.error) {
      throw new InternalServerErrorException(`Failed to create withdrawal request: ${insertWithdrawal.error.message}`);
    }

    const updateWallet = await this.supabase.client
      .from('wallets')
      .update({
        cash_balance: newCashBalance,
        updated_at: now,
      })
      .eq('user_id', params.userId);

    if (updateWallet.error) {
      throw new InternalServerErrorException(`Failed to update wallet cash balance: ${updateWallet.error.message}`);
    }

    await this.syncMwkCashBalance(params.userId, newCashBalance, now);

    const transactionInsert = await this.supabase.client
      .from('wallet_transactions')
      .insert({
        user_id: params.userId,
        type: 'debit',
        amount: params.amount,
        balance_type: 'cash',
        description: 'Withdrawal request',
        metadata: {
          request_id: insertWithdrawal.data?.id ?? null,
          payment_method: params.paymentMethod,
          currency: params.currency,
          source: 'withdrawal_request_fallback',
        },
        created_at: now,
      });

    if (transactionInsert.error) {
      throw new InternalServerErrorException(`Failed to write withdrawal ledger entry: ${transactionInsert.error.message}`);
    }

    await this.invalidateWalletSummary(params.userId);

    return {
      ok: true,
      request_id: insertWithdrawal.data?.id ? String(insertWithdrawal.data.id) : null,
      new_balance: newCashBalance,
      currency: params.currency,
    };
  }

  private async creditWalletFallback(params: CreditWalletParams): Promise<void> {
    const battleId = typeof params.metadata?.battle_id === 'string' ? params.metadata.battle_id : null;

    if (battleId) {
      const battleEarningInsert = await this.supabase.client
        .from('battle_earnings')
        .insert({
          user_id: params.userId,
          battle_id: battleId,
          amount: params.amount,
          status: 'credited',
        });

      if (battleEarningInsert.error) {
        if (battleEarningInsert.error.code === '23505') {
          await this.invalidateWalletSummary(params.userId);
          return;
        }

        throw new InternalServerErrorException(`Failed to record battle earning: ${battleEarningInsert.error.message}`);
      }
    } else if (params.reference) {
      const existingTransaction = await this.supabase.client
        .from('wallet_transactions')
        .select('id')
        .eq('user_id', params.userId)
        .eq('type', params.type)
        .contains('metadata', { reference: params.reference })
        .limit(1)
        .maybeSingle();

      if (existingTransaction.error) {
        throw new InternalServerErrorException(`Failed to check existing wallet credit: ${existingTransaction.error.message}`);
      }

      if (existingTransaction.data) {
        await this.invalidateWalletSummary(params.userId);
        return;
      }
    }

    const wallet = await this.ensureWallet(params.userId);
    const nextCoinBalance = Number(wallet.coin_balance ?? 0) + params.amount;
    const nextTotalEarned = Number(wallet.total_earned ?? 0) + (params.incrementTotalEarned ?? true ? params.amount : 0);
    const now = new Date().toISOString();

    const walletUpdate = await this.supabase.client
      .from('wallets')
      .update({
        coin_balance: nextCoinBalance,
        total_earned: nextTotalEarned,
        updated_at: now,
      })
      .eq('user_id', params.userId);

    if (walletUpdate.error) {
      throw new InternalServerErrorException(`Failed to update wallet coin balance: ${walletUpdate.error.message}`);
    }

    const metadata = {
      ...(params.metadata ?? {}),
      ...(params.reference ? { reference: params.reference } : {}),
      fallback: 'wallet_service',
    };

    const ledgerInsert = await this.supabase.client
      .from('wallet_transactions')
      .insert({
        user_id: params.userId,
        type: params.type,
        amount: params.amount,
        balance_type: 'coin',
        description: params.description ?? this.describeCreditType(params.type),
        metadata,
        created_at: now,
      });

    if (ledgerInsert.error) {
      throw new InternalServerErrorException(`Failed to write wallet ledger entry: ${ledgerInsert.error.message}`);
    }

    await this.invalidateWalletSummary(params.userId);
  }

  private async ensureWalletWithoutUpsert(userId: string, now: string): Promise<Record<string, unknown>> {
    const existing = await this.supabase.client
      .from('wallets')
      .select('user_id,coin_balance,cash_balance,total_earned,updated_at')
      .eq('user_id', userId)
      .limit(1)
      .maybeSingle();

    if (existing.error) {
      throw new InternalServerErrorException(`Failed to load wallet: ${existing.error.message}`);
    }

    if (existing.data) {
      return existing.data;
    }

    const insert = await this.supabase.client
      .from('wallets')
      .insert({
        user_id: userId,
        coin_balance: 0,
        cash_balance: 0,
        total_earned: 0,
        updated_at: now,
      })
      .select('user_id,coin_balance,cash_balance,total_earned,updated_at')
      .single();

    if (insert.error) {
      throw new InternalServerErrorException(`Failed to create wallet without upsert: ${insert.error.message}`);
    }

    return insert.data;
  }

  private async syncMwkCashBalance(userId: string, balance: number, now: string): Promise<void> {
    const update = await this.supabase.client
      .from('wallet_cash_balances')
      .update({ balance, updated_at: now })
      .eq('user_id', userId)
      .eq('currency', 'MWK')
      .select('user_id')
      .limit(1);

    if (update.error) {
      this.logger.warn(`Failed to update wallet_cash_balances for ${userId}: ${update.error.message}`);
      return;
    }

    if ((update.data?.length ?? 0) > 0) {
      return;
    }

    const insert = await this.supabase.client
      .from('wallet_cash_balances')
      .insert({
        user_id: userId,
        currency: 'MWK',
        balance,
        updated_at: now,
      });

    if (insert.error) {
      this.logger.warn(`Failed to insert wallet_cash_balances for ${userId}: ${insert.error.message}`);
    }
  }

  private shouldUseWalletMutationFallback(error: { code?: string | null; message?: string | null }, functionName: string): boolean {
    if (this.isMissingConflictTargetError(error)) {
      return true;
    }

    return this.isMissingRpcError(error, functionName);
  }

  private isMissingConflictTargetError(error: { code?: string | null; message?: string | null }): boolean {
    return error.code === '42P10' || (error.message ?? '').toLowerCase().includes('no unique or exclusion constraint');
  }

  private isMissingRpcError(error: { code?: string | null; message?: string | null }, functionName: string): boolean {
    const message = (error.message ?? '').toLowerCase();
    return error.code === 'PGRST202' || message.includes(`could not find the function public.${functionName.toLowerCase()}`);
  }

  private mapLegacyWithdrawal(row: Record<string, unknown>): WithdrawalResponse {
    const accountDetails = this.toObject(row.account_details);
    const currency = String(accountDetails.currency ?? '').trim().toUpperCase();
    const methodLabel = String(accountDetails.method ?? '').trim();

    return {
      id: String(row.id ?? ''),
      amount: Number(row.amount ?? 0),
      status: String(row.status ?? 'pending'),
      payment_method: String(row.payment_method ?? ''),
      method_label: methodLabel || String(row.payment_method ?? '') || null,
      currency: currency || null,
      admin_notes: row.admin_notes ? String(row.admin_notes) : null,
      created_at: row.created_at ? String(row.created_at) : null,
      updated_at: row.updated_at ? String(row.updated_at) : null,
    };
  }

  private toObject(value: unknown): Record<string, unknown> {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }

    return {};
  }

  private describeCreditType(type: string): string {
    switch (type) {
      case 'battle_reward':
        return 'Battle reward';
      case 'gift_reward':
        return 'Gift reward';
      default:
        return 'Wallet credit';
    }
  }

  private walletSummaryCacheKey(userId: string): string {
    return `wallet:summary:${userId}`;
  }

  private async cacheWalletSummary(userId: string, summary: WalletSummaryResponse): Promise<void> {
    try {
      await this.redis.client.set(this.walletSummaryCacheKey(userId), JSON.stringify(summary), {
        EX: this.walletSummaryTtlSeconds,
      });
    } catch (error) {
      this.logger.warn(`Wallet summary cache write failed for ${userId}: ${this.stringifyError(error)}`);
    }
  }

  private async invalidateWalletSummary(userId: string): Promise<void> {
    try {
      await this.redis.client.del(this.walletSummaryCacheKey(userId));
    } catch (error) {
      this.logger.warn(`Wallet summary cache invalidation failed for ${userId}: ${this.stringifyError(error)}`);
    }
  }

  private stringifyError(error: unknown): string {
    if (error instanceof Error) {
      return error.message;
    }

    return String(error);
  }
}
