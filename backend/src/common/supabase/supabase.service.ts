import { Injectable } from '@nestjs/common';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

@Injectable()
export class SupabaseService {
  private _client: SupabaseClient | null = null;

  get isConfigured(): boolean {
    const url = (process.env.SUPABASE_URL ?? '').trim();
    const key = (process.env.SUPABASE_SERVICE_KEY ?? '').trim();
    return url.length > 0 && key.length > 0;
  }

  get client(): SupabaseClient {
    if (!this._client) {
      const url = (process.env.SUPABASE_URL ?? '').trim();
      const key = (process.env.SUPABASE_SERVICE_KEY ?? '').trim();
      if (!url || !key) {
        throw new Error('Supabase env not configured (SUPABASE_URL / SUPABASE_SERVICE_KEY)');
      }
      this._client = createClient(url, key);
    }
    return this._client;
  }
}
