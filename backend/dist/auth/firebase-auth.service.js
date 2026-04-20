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
Object.defineProperty(exports, "__esModule", { value: true });
exports.FirebaseAuthService = void 0;
const fs_1 = require("fs");
const path_1 = require("path");
const common_1 = require("@nestjs/common");
const app_1 = require("firebase-admin/app");
const auth_1 = require("firebase-admin/auth");
let FirebaseAuthService = class FirebaseAuthService {
    constructor() {
        this.app = this.initializeFirebaseApp();
    }
    async verifyAuthorizationHeader(authorizationHeader) {
        if (!authorizationHeader || !authorizationHeader.startsWith('Bearer ')) {
            throw new Error('Missing bearer token');
        }
        const token = authorizationHeader.slice('Bearer '.length).trim();
        if (!token) {
            throw new Error('Missing bearer token');
        }
        const decoded = await (0, auth_1.getAuth)(this.app).verifyIdToken(token);
        return {
            uid: decoded.uid,
            email: decoded.email ?? null,
        };
    }
    initializeFirebaseApp() {
        const existing = (0, app_1.getApps)();
        if (existing.length > 0) {
            return existing[0];
        }
        const inlineCredential = this.readInlineCredential();
        if (inlineCredential) {
            return (0, app_1.initializeApp)({
                credential: (0, app_1.cert)({
                    projectId: inlineCredential.project_id,
                    clientEmail: inlineCredential.client_email,
                    privateKey: inlineCredential.private_key,
                }),
                projectId: inlineCredential.project_id ?? process.env.FIREBASE_PROJECT_ID,
            });
        }
        const fileCredential = this.readFileCredential();
        if (fileCredential) {
            return (0, app_1.initializeApp)({
                credential: (0, app_1.cert)({
                    projectId: fileCredential.project_id,
                    clientEmail: fileCredential.client_email,
                    privateKey: fileCredential.private_key,
                }),
                projectId: fileCredential.project_id ?? process.env.FIREBASE_PROJECT_ID,
            });
        }
        return (0, app_1.initializeApp)({
            credential: (0, app_1.applicationDefault)(),
            projectId: process.env.FIREBASE_PROJECT_ID,
        });
    }
    readInlineCredential() {
        const projectId = (process.env.FIREBASE_PROJECT_ID ?? '').trim();
        const clientEmail = (process.env.FIREBASE_CLIENT_EMAIL ?? '').trim();
        const privateKey = (process.env.FIREBASE_PRIVATE_KEY ?? '').trim().replace(/\\n/g, '\n');
        if (!projectId || !clientEmail || !privateKey) {
            return null;
        }
        return {
            project_id: projectId,
            client_email: clientEmail,
            private_key: privateKey,
        };
    }
    readFileCredential() {
        const explicitPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS ?? '').trim();
        const fallbackPaths = [
            explicitPath,
            (0, path_1.join)(process.cwd(), 'firebase-service-account.json'),
            (0, path_1.join)(process.cwd(), '..', 'admin_dashboard', 'firebase-service-account.json'),
        ].filter((candidate) => candidate.length > 0);
        for (const candidate of fallbackPaths) {
            if (!(0, fs_1.existsSync)(candidate)) {
                continue;
            }
            try {
                const raw = JSON.parse((0, fs_1.readFileSync)(candidate, 'utf8'));
                if (raw.project_id && raw.client_email && raw.private_key) {
                    return raw;
                }
            }
            catch (_) {
                // Continue to the next credential source.
            }
        }
        return null;
    }
};
exports.FirebaseAuthService = FirebaseAuthService;
exports.FirebaseAuthService = FirebaseAuthService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [])
], FirebaseAuthService);
//# sourceMappingURL=firebase-auth.service.js.map