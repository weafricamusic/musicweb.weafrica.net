import { BadRequestException, Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';

import { CurrentUser } from '../auth/current-user.decorator';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { FirebaseRequestUser } from '../auth/firebase-auth.service';
import { WalletService } from './wallet.service';

@Controller('api/wallet')
@UseGuards(FirebaseAuthGuard)
export class WalletController {
  constructor(private readonly walletService: WalletService) {}

  @Get('summary/me')
  async getMySummary(@CurrentUser() user: FirebaseRequestUser) {
    return this.walletService.getWalletSummary(user.uid);
  }

  @Get('transactions/me')
  async getMyTransactions(
    @CurrentUser() user: FirebaseRequestUser,
    @Query('limit') limit?: string,
  ) {
    const parsedLimit = this.parseLimit(limit);
    const transactions = await this.walletService.getWalletTransactions(user.uid, parsedLimit);
    return { ok: true, transactions, limit: parsedLimit };
  }

  private parseLimit(limit?: string): number {
    const parsed = Number(limit ?? 50);
    if (!Number.isFinite(parsed)) {
      return 50;
    }

    return Math.max(1, Math.min(200, Math.floor(parsed)));
  }
}

@Controller('api/withdrawals')
@UseGuards(FirebaseAuthGuard)
export class WithdrawalsController {
  constructor(private readonly walletService: WalletService) {}

  @Get('me')
  async getMyWithdrawals(
    @CurrentUser() user: FirebaseRequestUser,
    @Query('limit') limit?: string,
  ) {
    const parsed = Number(limit ?? 50);
    const normalizedLimit = Number.isFinite(parsed) ? Math.max(1, Math.min(200, Math.floor(parsed))) : 50;
    const withdrawals = await this.walletService.getWithdrawals(user.uid, normalizedLimit);
    return { ok: true, withdrawals, limit: normalizedLimit };
  }

  @Post('request')
  async requestWithdrawal(
    @CurrentUser() user: FirebaseRequestUser,
    @Body()
    body: {
      amount?: number;
      currency?: string;
      payment_method?: string;
      paymentMethod?: string;
      account_details?: Record<string, unknown>;
      accountDetails?: Record<string, unknown>;
    },
  ) {
    const amount = Number(body.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new BadRequestException('Invalid amount');
    }

    const currency = String(body.currency ?? 'MWK').trim().toUpperCase() || 'MWK';
    if (!['MWK', 'USD', 'ZAR'].includes(currency)) {
      throw new BadRequestException('Unsupported currency (expected MWK, USD, or ZAR)');
    }

    const paymentMethod = String(body.payment_method ?? body.paymentMethod ?? '').trim();
    if (!paymentMethod) {
      throw new BadRequestException('Missing payment_method');
    }

    const accountDetails = {
      ...((body.account_details ?? body.accountDetails ?? {}) as Record<string, unknown>),
      currency,
    };

    return this.walletService.requestWithdrawal({
      userId: user.uid,
      amount,
      currency,
      paymentMethod,
      accountDetails,
    });
  }
}