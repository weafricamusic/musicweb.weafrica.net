"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AgoraService = void 0;
const common_1 = require("@nestjs/common");
const buffer_1 = require("buffer");
const agora_access_token_1 = require("agora-access-token");
let AgoraService = class AgoraService {
    normalizeEnvOptional(name) {
        const raw = process.env[name];
        if (!raw)
            return undefined;
        const value = raw.trim().replace(/^['"]|['"]$/g, '');
        return value.length ? value : undefined;
    }
    getAgoraCustomerBasicAuth() {
        const appId = this.normalizeEnvOptional('AGORA_APP_ID');
        const customerId = this.normalizeEnvOptional('AGORA_CUSTOMER_ID');
        const customerSecret = this.normalizeEnvOptional('AGORA_CUSTOMER_SECRET');
        if (!appId || !customerId || !customerSecret) {
            return null;
        }
        const basic = buffer_1.Buffer.from(`${customerId}:${customerSecret}`).toString('base64');
        return { appId, authHeader: `Basic ${basic}` };
    }
    generateRtcToken(params) {
        const appId = (process.env.AGORA_APP_ID ?? '').trim();
        const cert = (process.env.AGORA_APP_CERTIFICATE ?? '').trim();
        if (!appId || !cert) {
            throw new Error('Agora env not configured (AGORA_APP_ID / AGORA_APP_CERTIFICATE)');
        }
        const expirationTimeInSeconds = params.ttlSeconds ?? 3600;
        const currentTimestamp = Math.floor(Date.now() / 1000);
        const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;
        const role = params.role === 'broadcaster' ? agora_access_token_1.RtcRole.PUBLISHER : agora_access_token_1.RtcRole.SUBSCRIBER;
        if (typeof params.uid === 'number') {
            return agora_access_token_1.RtcTokenBuilder.buildTokenWithUid(appId, cert, params.channelId, params.uid, role, privilegeExpiredTs);
        }
        return agora_access_token_1.RtcTokenBuilder.buildTokenWithAccount(appId, cert, params.channelId, params.uid, role, privilegeExpiredTs);
    }
    async tryKickChannel(params) {
        const auth = this.getAgoraCustomerBasicAuth();
        if (!auth) {
            return {
                attempted: false,
                ok: false,
                error: 'Missing Agora REST credentials. Set AGORA_APP_ID, AGORA_CUSTOMER_ID, and AGORA_CUSTOMER_SECRET to enable real stop.',
            };
        }
        const channelName = params.channelName.trim();
        if (!channelName) {
            return { attempted: true, ok: false, error: 'Missing channelName' };
        }
        const timeInSeconds = Number.isFinite(params.seconds) ? Math.max(1, Math.floor(params.seconds ?? 600)) : 600;
        try {
            const response = await fetch('https://api.agora.io/dev/v1/kicking-rule', {
                method: 'POST',
                headers: {
                    accept: 'application/json',
                    authorization: auth.authHeader,
                    'content-type': 'application/json',
                },
                body: JSON.stringify({
                    appid: auth.appId,
                    cname: channelName,
                    privileges: ['join_channel'],
                    time_in_seconds: timeInSeconds,
                }),
            });
            const text = await response.text().catch(() => '');
            let parsed = null;
            try {
                parsed = text ? JSON.parse(text) : null;
            }
            catch {
                parsed = text;
            }
            if (!response.ok) {
                return {
                    attempted: true,
                    ok: false,
                    status: response.status,
                    error: `Agora kicking-rule failed (${response.status})`,
                    responseText: text,
                };
            }
            const ruleId = parsed && typeof parsed === 'object' && 'id' in parsed ? Number(parsed.id) : null;
            return {
                attempted: true,
                ok: true,
                ruleId: Number.isFinite(ruleId) ? ruleId : null,
                status: response.status,
                response: parsed,
            };
        }
        catch (error) {
            return {
                attempted: true,
                ok: false,
                error: error instanceof Error ? error.message : 'Agora request failed',
            };
        }
    }
    async tryDeleteKickingRule(params) {
        const auth = this.getAgoraCustomerBasicAuth();
        if (!auth) {
            return {
                attempted: false,
                ok: false,
                error: 'Missing Agora REST credentials. Set AGORA_APP_ID, AGORA_CUSTOMER_ID, and AGORA_CUSTOMER_SECRET to manage rules.',
            };
        }
        const ruleId = Number(params.ruleId);
        if (!Number.isFinite(ruleId)) {
            return { attempted: true, ok: false, error: 'Invalid ruleId' };
        }
        try {
            const response = await fetch('https://api.agora.io/dev/v1/kicking-rule', {
                method: 'DELETE',
                headers: {
                    accept: 'application/json',
                    authorization: auth.authHeader,
                    'content-type': 'application/json',
                },
                body: JSON.stringify({ appid: auth.appId, id: ruleId }),
            });
            const text = await response.text().catch(() => '');
            let parsed = null;
            try {
                parsed = text ? JSON.parse(text) : null;
            }
            catch {
                parsed = text;
            }
            if (!response.ok) {
                return {
                    attempted: true,
                    ok: false,
                    status: response.status,
                    error: `Agora delete kicking-rule failed (${response.status})`,
                    responseText: text,
                };
            }
            return {
                attempted: true,
                ok: true,
                status: response.status,
                response: parsed,
            };
        }
        catch (error) {
            return {
                attempted: true,
                ok: false,
                error: error instanceof Error ? error.message : 'Agora request failed',
            };
        }
    }
};
exports.AgoraService = AgoraService;
exports.AgoraService = AgoraService = __decorate([
    (0, common_1.Injectable)()
], AgoraService);
//# sourceMappingURL=agora.service.js.map