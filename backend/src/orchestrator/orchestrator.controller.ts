import { Body, Controller, Post } from '@nestjs/common';

import { OrchestratorService } from './orchestrator.service';

@Controller('orchestrator')
export class OrchestratorController {
  constructor(private readonly orchestrator: OrchestratorService) {}

  @Post('solo/start')
  async startSoloLive(
    @Body()
    body: {
      userId: string;
      userType: 'artist' | 'dj';
      title: string;
      category: string;
      coverImage?: string;
      privacy: 'public' | 'followers';
    },
  ) {
    return this.orchestrator.startSoloLive(body);
  }

  @Post('battle/invite')
  async startBattleInvite(
    @Body()
    body: {
      userId: string;
      userType: 'artist' | 'dj';
      title: string;
      category: string;
      coverImage?: string;
      durationSeconds: number;
      coinGoal: number;
      beatName: string;
      opponentId: string;
    },
  ) {
    return this.orchestrator.startBattleInvite(body);
  }

  @Post('battle/accept')
  async acceptBattleInvite(@Body() body: { inviteId: string; userId: string }) {
    return this.orchestrator.acceptBattleInvite(body);
  }

  @Post('stream/start')
  async startStream(
    @Body()
    body: { liveRoomId: string; userId: string; streamSessionId: string },
  ) {
    return this.orchestrator.startStream(body);
  }

  @Post('stream/end')
  async endStream(@Body() body: { liveRoomId: string; userId: string }) {
    return this.orchestrator.endStream(body);
  }
}
