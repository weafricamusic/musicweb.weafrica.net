"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupabaseService = void 0;
const common_1 = require("@nestjs/common");
const supabase_js_1 = require("@supabase/supabase-js");
let SupabaseService = class SupabaseService {
    constructor() {
        this._client = null;
    }
    get isConfigured() {
        const url = (process.env.SUPABASE_URL ?? '').trim();
        const key = (process.env.SUPABASE_SERVICE_KEY ?? '').trim();
        return url.length > 0 && key.length > 0;
    }
    get client() {
        if (!this._client) {
            const url = (process.env.SUPABASE_URL ?? '').trim();
            const key = (process.env.SUPABASE_SERVICE_KEY ?? '').trim();
            if (!url || !key) {
                throw new Error('Supabase env not configured (SUPABASE_URL / SUPABASE_SERVICE_KEY)');
            }
            this._client = (0, supabase_js_1.createClient)(url, key);
        }
        return this._client;
    }
};
exports.SupabaseService = SupabaseService;
exports.SupabaseService = SupabaseService = __decorate([
    (0, common_1.Injectable)()
], SupabaseService);
//# sourceMappingURL=supabase.service.js.map