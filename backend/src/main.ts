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
    cors: true,
  });

  const port = Number.parseInt(process.env.PORT ?? '3000', 10);
  await app.listen(Number.isFinite(port) ? port : 3000);

  Logger.log(`Nest orchestrator listening on :${port}`, 'Bootstrap');
}

void bootstrap();
