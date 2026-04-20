import { Injectable } from '@nestjs/common';
import { Buffer } from 'buffer';
import { RtcRole, RtcTokenBuilder } from 'agora-access-token';

type AgoraKickChannelResult =
  | { attempted: false; ok: false; error: string }
  | { attempted: true; ok: true; ruleId: number | null; status: number; response: unknown }
  | { attempted: true; ok: false; status?: number; error: string; responseText?: string };

type AgoraDeleteKickingRuleResult =
  | { attempted: false; ok: false; error: string }
  | { attempted: true; ok: true; status: number; response: unknown }
  | { attempted: true; ok: false; status?: number; error: string; responseText?: string };

@Injectable()
export class AgoraService {
  private normalizeEnvOptional(name: string): string | undefined {
    const raw = process.env[name];
    if (!raw) return undefined;
    const value = raw.trim().replace(/^['"]|['"]$/g, '');
    return value.length ? value : undefined;
  }

  private getAgoraCustomerBasicAuth(): { appId: string; authHeader: string } | null {
    const appId = this.normalizeEnvOptional('AGORA_APP_ID');
    const customerId = this.normalizeEnvOptional('AGORA_CUSTOMER_ID');
    const customerSecret = this.normalizeEnvOptional('AGORA_CUSTOMER_SECRET');
    if (!appId || !customerId || !customerSecret) {
      return null;
    }

    const basic = Buffer.from(`${customerId}:${customerSecret}`).toString('base64');
    return { appId, authHeader: `Basic ${basic}` };
  }

  generateRtcToken(params: { channelId: string; uid: string | number; role: 'broadcaster' | 'audience'; ttlSeconds?: number }): string {
    const appId = (process.env.AGORA_APP_ID ?? '').trim();
    const cert = (process.env.AGORA_APP_CERTIFICATE ?? '').trim();
    if (!appId || !cert) {
      throw new Error('Agora env not configured (AGORA_APP_ID / AGORA_APP_CERTIFICATE)');
    }

    const expirationTimeInSeconds = params.ttlSeconds ?? 3600;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

    const role = params.role === 'broadcaster' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;

    if (typeof params.uid === 'number') {
      return RtcTokenBuilder.buildTokenWithUid(appId, cert, params.channelId, params.uid, role, privilegeExpiredTs);
    }

    return RtcTokenBuilder.buildTokenWithAccount(appId, cert, params.channelId, params.uid, role, privilegeExpiredTs);
  }

  async tryKickChannel(params: { channelName: string; seconds?: number }): Promise<AgoraKickChannelResult> {
    const auth = this.getAgoraCustomerBasicAuth();
    if (!auth) {
      return {
        attempted: false,
        ok: false,
        error:
          'Missing Agora REST credentials. Set AGORA_APP_ID, AGORA_CUSTOMER_ID, and AGORA_CUSTOMER_SECRET to enable real stop.',
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
      let parsed: unknown = null;
      try {
        parsed = text ? (JSON.parse(text) as unknown) : null;
      } catch {
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

      const ruleId = parsed && typeof parsed === 'object' && 'id' in parsed ? Number((parsed as { id?: unknown }).id) : null;

      return {
        attempted: true,
        ok: true,
        ruleId: Number.isFinite(ruleId) ? ruleId : null,
        status: response.status,
        response: parsed,
      };
    } catch (error) {
      return {
        attempted: true,
        ok: false,
        error: error instanceof Error ? error.message : 'Agora request failed',
      };
    }
  }

  async tryDeleteKickingRule(params: { ruleId: number }): Promise<AgoraDeleteKickingRuleResult> {
    const auth = this.getAgoraCustomerBasicAuth();
    if (!auth) {
      return {
        attempted: false,
        ok: false,
        error:
          'Missing Agora REST credentials. Set AGORA_APP_ID, AGORA_CUSTOMER_ID, and AGORA_CUSTOMER_SECRET to manage rules.',
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
      let parsed: unknown = null;
      try {
        parsed = text ? (JSON.parse(text) as unknown) : null;
      } catch {
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
    } catch (error) {
      return {
        attempted: true,
        ok: false,
        error: error instanceof Error ? error.message : 'Agora request failed',
      };
    }
  }
}
