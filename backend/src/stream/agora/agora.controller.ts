import { Body, Controller, Logger, Post } from '@nestjs/common';

import { AgoraService } from './agora.service';

@Controller('agora')
export class AgoraController {
    private readonly logger = new Logger(AgoraController.name);

    constructor(private readonly agora: AgoraService) { }

    /**
     * POST /api/agora/token
     * 
     * Generate RTC token for joining a live stream.
     * This endpoint is called by both artists (broadcaster) and consumers (audience).
     * 
     * Request body:
     *   - channel_id: string - The channel ID (live stream channel)
     *   - role: string - 'broadcaster' or 'audience'
     *   - uid: number - User ID for Agora (must match the UID used in the client)
     *   - ttl_seconds: number (optional) - Token expiration time in seconds
     *   - battle_id: string (optional) - Battle ID if this is a battle stream
     */
    @Post('token')
    async generateRtcToken(@Body() body: {
        channel_id: string;
        role: 'broadcaster' | 'audience';
        uid: number | string;
        ttl_seconds?: number;
        battle_id?: string;
    }) {
        try {
            const { channel_id, role, uid, ttl_seconds = 3600, battle_id } = body;

            if (!channel_id) {
                return {
                    statusCode: 400,
                    message: 'channel_id is required',
                };
            }

            if (!role || !['broadcaster', 'audience'].includes(role)) {
                return {
                    statusCode: 400,
                    message: 'role must be either "broadcaster" or "audience"',
                };
            }

            if (uid === undefined || uid === null) {
                return {
                    statusCode: 400,
                    message: 'uid is required',
                };
            }

            this.logger.log(
                `Generating Agora RTC token: channel=${channel_id}, role=${role}, uid=${uid}, battle=${battle_id || 'none'}`,
            );

            const token = this.agora.generateRtcToken({
                channelId: channel_id,
                uid,
                role,
                ttlSeconds: ttl_seconds,
            });

            this.logger.log(
                `Agora RTC token generated successfully for channel=${channel_id}`,
            );

            return {
                token,
                app_id: process.env.AGORA_APP_ID,
                channel_id,
                uid,
                role,
                expires_in: ttl_seconds,
            };
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            const errorStack = error instanceof Error ? error.stack : '';

            this.logger.error(
                `Failed to generate Agora RTC token: ${errorMessage}`,
                errorStack,
            );

            return {
                statusCode: 500,
                message: 'Failed to generate Agora token',
                error: errorMessage,
            };
        }
    }

    /**
     * POST /api/agora/rtm/token
     * 
     * Generate RTM token for real-time messaging (chat).
     * 
     * Request body:
     *   - ttl_seconds: number (optional) - Token expiration time in seconds
     *   - user_id: string (optional) - Specific user ID, or let server generate one
     */
    @Post('rtm/token')
    async generateRtmToken(@Body() body: {
        ttl_seconds?: number;
        user_id?: string;
    }) {
        try {
            const { ttl_seconds = 3600, user_id } = body;

            // For RTM, we use a random UID if not provided
            const uid = user_id || Math.floor(Math.random() * 100000).toString();

            this.logger.log(`Generating Agora RTM token for user=${uid}`);

            // RTM tokens use the same Agora service but with a different role
            // We'll generate a token with 'audience' role for RTM
            const token = this.agora.generateRtcToken({
                channelId: `rtm_${uid}`,
                uid,
                role: 'audience',
                ttlSeconds: ttl_seconds,
            });

            this.logger.log(`Agora RTM token generated successfully for user=${uid}`);

            return {
                token,
                app_id: process.env.AGORA_APP_ID,
                user_id: uid,
                expires_in: ttl_seconds,
            };
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            const errorStack = error instanceof Error ? error.stack : '';

            this.logger.error(
                `Failed to generate Agora RTM token: ${errorMessage}`,
                errorStack,
            );

            return {
                statusCode: 500,
                message: 'Failed to generate Agora RTM token',
                error: errorMessage,
            };
        }
    }

    /**
     * POST /api/agora/config
     * 
     * Get public Agora configuration.
     */
    @Post('config')
    getConfig() {
        return {
            app_id: process.env.AGORA_APP_ID || null,
            configured: !!(process.env.AGORA_APP_ID && process.env.AGORA_APP_CERTIFICATE),
        };
    }
}