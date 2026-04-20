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
exports.WithdrawalsController = exports.WalletController = void 0;
const common_1 = require("@nestjs/common");
const current_user_decorator_1 = require("../auth/current-user.decorator");
const firebase_auth_guard_1 = require("../auth/firebase-auth.guard");
const wallet_service_1 = require("./wallet.service");
let WalletController = class WalletController {
    constructor(walletService) {
        this.walletService = walletService;
    }
    async getMySummary(user) {
        return this.walletService.getWalletSummary(user.uid);
    }
    async getMyTransactions(user, limit) {
        const parsedLimit = this.parseLimit(limit);
        const transactions = await this.walletService.getWalletTransactions(user.uid, parsedLimit);
        return { ok: true, transactions, limit: parsedLimit };
    }
    parseLimit(limit) {
        const parsed = Number(limit ?? 50);
        if (!Number.isFinite(parsed)) {
            return 50;
        }
        return Math.max(1, Math.min(200, Math.floor(parsed)));
    }
};
exports.WalletController = WalletController;
__decorate([
    (0, common_1.Get)('summary/me'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], WalletController.prototype, "getMySummary", null);
__decorate([
    (0, common_1.Get)('transactions/me'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], WalletController.prototype, "getMyTransactions", null);
exports.WalletController = WalletController = __decorate([
    (0, common_1.Controller)('api/wallet'),
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    __metadata("design:paramtypes", [wallet_service_1.WalletService])
], WalletController);
let WithdrawalsController = class WithdrawalsController {
    constructor(walletService) {
        this.walletService = walletService;
    }
    async getMyWithdrawals(user, limit) {
        const parsed = Number(limit ?? 50);
        const normalizedLimit = Number.isFinite(parsed) ? Math.max(1, Math.min(200, Math.floor(parsed))) : 50;
        const withdrawals = await this.walletService.getWithdrawals(user.uid, normalizedLimit);
        return { ok: true, withdrawals, limit: normalizedLimit };
    }
    async requestWithdrawal(user, body) {
        const amount = Number(body.amount);
        if (!Number.isFinite(amount) || amount <= 0) {
            throw new common_1.BadRequestException('Invalid amount');
        }
        const currency = String(body.currency ?? 'MWK').trim().toUpperCase() || 'MWK';
        if (!['MWK', 'USD', 'ZAR'].includes(currency)) {
            throw new common_1.BadRequestException('Unsupported currency (expected MWK, USD, or ZAR)');
        }
        const paymentMethod = String(body.payment_method ?? body.paymentMethod ?? '').trim();
        if (!paymentMethod) {
            throw new common_1.BadRequestException('Missing payment_method');
        }
        const accountDetails = {
            ...(body.account_details ?? body.accountDetails ?? {}),
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
};
exports.WithdrawalsController = WithdrawalsController;
__decorate([
    (0, common_1.Get)('me'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Query)('limit')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", Promise)
], WithdrawalsController.prototype, "getMyWithdrawals", null);
__decorate([
    (0, common_1.Post)('request'),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], WithdrawalsController.prototype, "requestWithdrawal", null);
exports.WithdrawalsController = WithdrawalsController = __decorate([
    (0, common_1.Controller)('api/withdrawals'),
    (0, common_1.UseGuards)(firebase_auth_guard_1.FirebaseAuthGuard),
    __metadata("design:paramtypes", [wallet_service_1.WalletService])
], WithdrawalsController);
//# sourceMappingURL=wallet.controller.js.map