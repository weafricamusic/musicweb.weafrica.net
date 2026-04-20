import { Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'crypto';

import { RedisService } from '../../common/redis/redis.service';

@Injectable()
export class DistributedLockService {
  private readonly logger = new Logger(DistributedLockService.name);
  private readonly DEFAULT_TTL_SECONDS = 30;

  constructor(private readonly redis: RedisService) {}

  private lockKey(key: string) {
    return `lock:${key}`;
  }

  async acquireLock(key: string, ttlSeconds: number = this.DEFAULT_TTL_SECONDS): Promise<string | null> {
    const lockKey = this.lockKey(key);
    const token = randomUUID();

    const res = await this.redis.client.set(lockKey, token, {
      NX: true,
      EX: ttlSeconds,
    });

    if (res === 'OK') {
      this.logger.debug(`Lock acquired: ${lockKey}`);
      return token;
    }
    return null;
  }

  async releaseLock(key: string, token: string): Promise<void> {
    const lockKey = this.lockKey(key);

    // Safe release: delete only if the token matches.
    const lua = `
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        return redis.call('DEL', KEYS[1])
      else
        return 0
      end
    `;

    await this.redis.client.eval(lua, {
      keys: [lockKey],
      arguments: [token],
    });

    this.logger.debug(`Lock released: ${lockKey}`);
  }

  async executeWithLock<T>(
    key: string,
    fn: () => Promise<T>,
    ttlSeconds: number = this.DEFAULT_TTL_SECONDS,
  ): Promise<T> {
    const token = await this.acquireLock(key, ttlSeconds);
    if (!token) {
      throw new Error(`Failed to acquire lock for ${key}`);
    }

    try {
      return await fn();
    } finally {
      await this.releaseLock(key, token);
    }
  }
}
