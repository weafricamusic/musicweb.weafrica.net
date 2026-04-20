import { Module } from '@nestjs/common';

import { LiveRoomService } from './live-room.service';

@Module({
  imports: [],
  providers: [LiveRoomService],
  exports: [LiveRoomService],
})
export class LiveRoomModule {}

