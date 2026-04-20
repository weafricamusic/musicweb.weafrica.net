import { Module } from '@nestjs/common';

import { RedisModule } from '../common/redis/redis.module';
import { EventBusService } from './event-bus.service';
import { EventGateway } from './event.gateway';

@Module({
  imports: [RedisModule],
  providers: [EventGateway, EventBusService],
  exports: [EventBusService, EventGateway],
})
export class EventsModule {}
