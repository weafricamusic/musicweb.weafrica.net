"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminModule = void 0;
const common_1 = require("@nestjs/common");
const firebase_auth_module_1 = require("../auth/firebase-auth.module");
const supabase_module_1 = require("../common/supabase/supabase.module");
const stream_module_1 = require("../stream/stream.module");
const admin_controller_1 = require("./admin.controller");
const admin_service_1 = require("./admin.service");
const admin_guard_1 = require("../auth/admin.guard");
let AdminModule = class AdminModule {
};
exports.AdminModule = AdminModule;
exports.AdminModule = AdminModule = __decorate([
    (0, common_1.Module)({
        imports: [supabase_module_1.SupabaseModule, firebase_auth_module_1.FirebaseAuthModule, stream_module_1.StreamModule],
        controllers: [admin_controller_1.AdminController],
        providers: [admin_service_1.AdminService, admin_guard_1.AdminGuard, admin_guard_1.AdminPermissionGuard],
        exports: [admin_service_1.AdminService],
    })
], AdminModule);
//# sourceMappingURL=admin.module.js.map