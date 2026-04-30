"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var AgoraController_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AgoraController = void 0;
const common_1 = require("@nestjs/common");
const agora_service_1 = require("./agora.service");
let AgoraController = AgoraController_1 = class AgoraController {
    constructor(agora) {
        this.agora = agora;
        this.logger = new common_1.Logger(AgoraController_1.name);
    }
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
    async generateRtcToken(body) {
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
            this.logger.log(`Generating Agora RTC token: channel=${channel_id}, role=${role}, uid=${uid}, battle=${battle_id || 'none'}`);
            const token = this.agora.generateRtcToken({
                channelId: channel_id,
                uid,
                role,
                ttlSeconds: ttl_seconds,
            });
            this.logger.log(`Agora RTC token generated successfully for channel=${channel_id}`);
            return {
                token,
                app_id: process.env.AGORA_APP_ID,
                channel_id,
                uid,
                role,
                expires_in: ttl_seconds,
            };
        }
        catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            const errorStack = error instanceof Error ? error.stack : '';
            this.logger.error(`Failed to generate Agora RTC token: ${errorMessage}`, errorStack);
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
    async generateRtmToken(body) {
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
        }
        catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            const errorStack = error instanceof Error ? error.stack : '';
            this.logger.error(`Failed to generate Agora RTM token: ${errorMessage}`, errorStack);
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
    getConfig() {
        return {
            app_id: process.env.AGORA_APP_ID || null,
            configured: !!(process.env.AGORA_APP_ID && process.env.AGORA_APP_CERTIFICATE),
        };
    }
};
exports.AgoraController = AgoraController;
__decorate([
    (0, common_1.Post)('token'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], AgoraController.prototype, "generateRtcToken", null);
__decorate([
    (0, common_1.Post)('rtm/token'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], AgoraController.prototype, "generateRtmToken", null);
__decorate([
    (0, common_1.Post)('config'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AgoraController.prototype, "getConfig", null);
exports.AgoraController = AgoraController = AgoraController_1 = __decorate([
    (0, common_1.Controller)('agora'),
    __metadata("design:paramtypes", [agora_service_1.AgoraService])
], AgoraController);
//# sourceMappingURL=agora.controller.js.map