import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { createClient } from 'redis';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private _client: ReturnType<typeof createClient> | null = null;

  get client(): ReturnType<typeof createClient> {
    if (!this._client) {
      throw new Error('Redis client not initialized');
    }
    return this._client;
  }

  async onModuleInit() {
    const url = process.env.REDIS_URL ?? 'redis://localhost:6379';
    const password = (process.env.REDIS_PASSWORD ?? '').trim();

    const client = createClient({
      url,
      password: password.length > 0 ? password : undefined,
    });

    client.on('error', (err) => {
      this.logger.error('Redis error', err);
    });
    client.on('connect', () => {
      this.logger.log('Redis connected');
    });

    await client.connect();
    this._client = client;
  }

  async onModuleDestroy() {
    try {
      await this._client?.quit();
    } catch (_) {
      // best-effort
    } finally {
      this._client = null;
    }
  }
}
