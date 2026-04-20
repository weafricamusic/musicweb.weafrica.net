"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.EventsModule = void 0;
const common_1 = require("@nestjs/common");
const redis_module_1 = require("../common/redis/redis.module");
const event_bus_service_1 = require("./event-bus.service");
const event_gateway_1 = require("./event.gateway");
let EventsModule = class EventsModule {
};
exports.EventsModule = EventsModule;
exports.EventsModule = EventsModule = __decorate([
    (0, common_1.Module)({
        imports: [redis_module_1.RedisModule],
        providers: [event_gateway_1.EventGateway, event_bus_service_1.EventBusService],
        exports: [event_bus_service_1.EventBusService, event_gateway_1.EventGateway],
    })
], EventsModule);
//# sourceMappingURL=events.module.js.map