import { Injectable, Logger } from '@nestjs/common';

import { RedisService } from '../common/redis/redis.service';
import { EventGateway } from './event.gateway';
import { DomainEvent } from './types/event-types';

type EventEnvelope = {
  type: DomainEvent;
  payload: unknown;
  timestamp: string;
  eventId: string;
};

@Injectable()
export class EventBusService {
  private readonly logger = new Logger(EventBusService.name);
  private readonly STREAM_KEY = 'events:stream';

  constructor(
    private readonly redis: RedisService,
    private readonly gateway: EventGateway,
  ) {}

  async emit(event: DomainEvent, payload: unknown): Promise<void> {
    const eventData: EventEnvelope = {
      type: event,
      payload,
      timestamp: new Date().toISOString(),
      eventId: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
    };

    this.logger.debug(`Emitting event: ${event}`);

    // Store in Redis Stream for replay / diagnostics.
    await this.redis.client.xAdd(this.STREAM_KEY, '*', {
      data: JSON.stringify(eventData),
    });

    // Push to WebSocket clients.
    this.gateway.emitToAll(event, payload);

    // Optional internal routing for background consumers.
    if (this.isDomainEvent(event)) {
      await this.redis.client.publish(`event:${event}`, JSON.stringify(payload));
    }
  }

  private isDomainEvent(event: DomainEvent): boolean {
    // Domain events go to internal handlers.
    const domainEvents: DomainEvent[] = [
      DomainEvent.STREAM_CREATED,
      DomainEvent.STREAM_STARTED,
      DomainEvent.STREAM_ENDED,
      DomainEvent.BATTLE_ACCEPTED,
      DomainEvent.BATTLE_ENDED,
      DomainEvent.GIFT_SENT,
      DomainEvent.VOTE_CAST,
    ];
    return domainEvents.includes(event);
  }
}
