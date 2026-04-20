"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("reflect-metadata");
const fs_1 = require("fs");
const path_1 = require("path");
const common_1 = require("@nestjs/common");
const core_1 = require("@nestjs/core");
const dotenv_1 = require("dotenv");
const app_module_1 = require("./app.module");
function bootstrapEnv() {
    const envFiles = [
        (0, path_1.resolve)(process.cwd(), '.env'),
        (0, path_1.resolve)(process.cwd(), '.env.local'),
        (0, path_1.resolve)(process.cwd(), '../.env.local'),
        (0, path_1.resolve)(process.cwd(), '../supabase/.env.local'),
    ];
    for (const filePath of envFiles) {
        if ((0, fs_1.existsSync)(filePath)) {
            (0, dotenv_1.config)({ path: filePath, override: false });
        }
    }
    if (!process.env.SUPABASE_URL && process.env.PUBLIC_SUPABASE_URL) {
        process.env.SUPABASE_URL = process.env.PUBLIC_SUPABASE_URL;
    }
    if (!process.env.SUPABASE_SERVICE_KEY && process.env.SUPABASE_SERVICE_ROLE_KEY) {
        process.env.SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
    }
}
async function bootstrap() {
    bootstrapEnv();
    const app = await core_1.NestFactory.create(app_module_1.AppModule, {
        cors: true,
    });
    const port = Number.parseInt(process.env.PORT ?? '3000', 10);
    await app.listen(Number.isFinite(port) ? port : 3000);
    common_1.Logger.log(`Nest orchestrator listening on :${port}`, 'Bootstrap');
}
void bootstrap();
//# sourceMappingURL=main.js.map