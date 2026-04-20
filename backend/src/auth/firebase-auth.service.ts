import { existsSync, readFileSync } from 'fs';
import { join } from 'path';

import { Injectable } from '@nestjs/common';
import { App, applicationDefault, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

export type FirebaseRequestUser = {
  uid: string;
  email?: string | null;
};

type ServiceAccountShape = {
  project_id?: string;
  client_email?: string;
  private_key?: string;
};

@Injectable()
export class FirebaseAuthService {
  private readonly app: App;

  constructor() {
    this.app = this.initializeFirebaseApp();
  }

  async verifyAuthorizationHeader(authorizationHeader?: string): Promise<FirebaseRequestUser> {
    if (!authorizationHeader || !authorizationHeader.startsWith('Bearer ')) {
      throw new Error('Missing bearer token');
    }

    const token = authorizationHeader.slice('Bearer '.length).trim();
    if (!token) {
      throw new Error('Missing bearer token');
    }

    const decoded = await getAuth(this.app).verifyIdToken(token);
    return {
      uid: decoded.uid,
      email: decoded.email ?? null,
    };
  }

  private initializeFirebaseApp(): App {
    const existing = getApps();
    if (existing.length > 0) {
      return existing[0];
    }

    const inlineCredential = this.readInlineCredential();
    if (inlineCredential) {
      return initializeApp({
        credential: cert({
          projectId: inlineCredential.project_id,
          clientEmail: inlineCredential.client_email,
          privateKey: inlineCredential.private_key,
        }),
        projectId: inlineCredential.project_id ?? process.env.FIREBASE_PROJECT_ID,
      });
    }

    const fileCredential = this.readFileCredential();
    if (fileCredential) {
      return initializeApp({
        credential: cert({
          projectId: fileCredential.project_id,
          clientEmail: fileCredential.client_email,
          privateKey: fileCredential.private_key,
        }),
        projectId: fileCredential.project_id ?? process.env.FIREBASE_PROJECT_ID,
      });
    }

    return initializeApp({
      credential: applicationDefault(),
      projectId: process.env.FIREBASE_PROJECT_ID,
    });
  }

  private readInlineCredential(): ServiceAccountShape | null {
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

  private readFileCredential(): ServiceAccountShape | null {
    const explicitPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS ?? '').trim();
    const fallbackPaths = [
      explicitPath,
      join(process.cwd(), 'firebase-service-account.json'),
      join(process.cwd(), '..', 'admin_dashboard', 'firebase-service-account.json'),
    ].filter((candidate) => candidate.length > 0);

    for (const candidate of fallbackPaths) {
      if (!existsSync(candidate)) {
        continue;
      }

      try {
        const raw = JSON.parse(readFileSync(candidate, 'utf8')) as ServiceAccountShape;
        if (raw.project_id && raw.client_email && raw.private_key) {
          return raw;
        }
      } catch (_) {
        // Continue to the next credential source.
      }
    }

    return null;
  }
}