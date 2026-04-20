"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppModule = void 0;
const common_1 = require("@nestjs/common");
const firebase_auth_module_1 = require("./auth/firebase-auth.module");
const supabase_module_1 = require("./common/supabase/supabase.module");
const admin_module_1 = require("./admin/admin.module");
const challenge_module_1 = require("./challenge/challenge.module");
const events_module_1 = require("./events/events.module");
const feed_module_1 = require("./feed/feed.module");
const live_room_module_1 = require("./live-room/live-room.module");
const live_controller_1 = require("./live.controller");
const live_gateway_1 = require("./gateways/live.gateway");
const orchestrator_module_1 = require("./orchestrator/orchestrator.module");
const stream_module_1 = require("./stream/stream.module");
let AppModule = class AppModule {
};
exports.AppModule = AppModule;
exports.AppModule = AppModule = __decorate([
    (0, common_1.Module)({
        imports: [
            supabase_module_1.SupabaseModule,
            firebase_auth_module_1.FirebaseAuthModule,
            stream_module_1.StreamModule,
            live_room_module_1.LiveRoomModule,
            challenge_module_1.ChallengeModule,
            events_module_1.EventsModule,
            feed_module_1.FeedModule,
            orchestrator_module_1.OrchestratorModule,
            admin_module_1.AdminModule,
        ],
        controllers: [live_controller_1.LiveController],
        providers: [live_gateway_1.LiveGateway],
    })
], AppModule);
//# sourceMappingURL=app.module.js.map