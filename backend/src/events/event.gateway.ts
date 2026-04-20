import {
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';

@WebSocketGateway({
  cors: {
    origin: '*',
    credentials: true,
  },
})
export class EventGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(EventGateway.name);
  private readonly clients: Map<string, Set<string>> = new Map();

  handleConnection(client: Socket) {
    this.logger.log(`Client connected: ${client.id}`);
  }

  handleDisconnect(client: Socket) {
    this.logger.log(`Client disconnected: ${client.id}`);

    for (const [roomId, sockets] of this.clients.entries()) {
      if (sockets.delete(client.id)) {
        if (sockets.size === 0) {
          this.clients.delete(roomId);
        }
        this.emitToRoom(roomId, 'VIEWER_COUNT_UPDATED', { count: sockets.size });
      }
    }
  }

  @SubscribeMessage('JOIN_ROOM')
  handleJoinRoom(
    client: Socket,
    @MessageBody() payload: { roomId: string },
  ) {
    const roomId = payload?.roomId?.trim();
    if (!roomId) return;

    client.join(roomId);
    if (!this.clients.has(roomId)) {
      this.clients.set(roomId, new Set());
    }
    this.clients.get(roomId)!.add(client.id);
    this.logger.log(`Client ${client.id} joined room ${roomId}`);

    this.emitToRoom(roomId, 'VIEWER_COUNT_UPDATED', {
      count: this.clients.get(roomId)!.size,
    });
  }

  @SubscribeMessage('LEAVE_ROOM')
  handleLeaveRoom(
    client: Socket,
    @MessageBody() payload: { roomId: string },
  ) {
    const roomId = payload?.roomId?.trim();
    if (!roomId) return;

    client.leave(roomId);
    const set = this.clients.get(roomId);
    if (!set) return;
    set.delete(client.id);
    if (set.size === 0) {
      this.clients.delete(roomId);
    }

    this.emitToRoom(roomId, 'VIEWER_COUNT_UPDATED', {
      count: this.clients.get(roomId)?.size ?? 0,
    });
  }

  emitToRoom(roomId: string, event: string, payload: unknown) {
    this.server.to(roomId).emit(event, payload);
  }

  emitToAll(event: string, payload: unknown) {
    this.server.emit(event, payload);
  }
}
