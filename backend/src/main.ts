import 'reflect-metadata';

import { existsSync } from 'fs';
import { resolve } from 'path';

import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { config as loadEnv } from 'dotenv';

import { AppModule } from './app.module';

function bootstrapEnv() {
  const envFiles = [
    resolve(process.cwd(), '.env'),
    resolve(process.cwd(), '.env.local'),
    resolve(process.cwd(), '../.env.local'),
    resolve(process.cwd(), '../supabase/.env.local'),
  ];

  for (const filePath of envFiles) {
    if (existsSync(filePath)) {
      loadEnv({ path: filePath, override: false });
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

  const app = await NestFactory.create(AppModule, {
    cors: {
      origin: [
        'https://weafrica.com',
        'https://musicweb.weafrica.net',
        'http://localhost:8080',
        'http://localhost:3000',
        'http://127.0.0.1:8080',
        'http://127.0.0.1:3000',
      ],
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'apikey'],
    },
  });

  const port = Number.parseInt(process.env.PORT ?? '3000', 10);
  await app.listen(Number.isFinite(port) ? port : 3000);

  Logger.log(`Nest orchestrator listening on :${port}`, 'Bootstrap');
}

void bootstrap();
