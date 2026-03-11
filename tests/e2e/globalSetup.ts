/**
 * Playwright global setup: bootstrap E2E test users with correct group membership,
 * then pre-login and save the auth token to a file so individual tests don't need
 * to hit the auth endpoints (which have a strict 10 req/min rate limit).
 *
 * DB connection: PGPASSWORD=postgres psql -h localhost -U postgres monitor
 * Override via env vars: PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE
 */

import { execSync } from 'child_process';
import { request as playwrightRequest } from '@playwright/test';
import { writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BASE_URL || 'http://localhost:8080';
const AUTH_FILE = join(__dirname, '.auth.json');

export const TEST_USERS = {
  smoke:  { email: 'e2e-test@test.com', password: 'e2e-test-pass' },
  nav:    { email: 'e2e-nav@test.com',  password: 'e2e-nav-pass'  },
};

async function registerUser(email: string, password: string): Promise<void> {
  const ctx = await playwrightRequest.newContext({ baseURL: BASE_URL });
  await ctx.post('/api/auth/register', { data: { email, password } });
  // Ignore errors — user may already exist
  await ctx.dispose();
}

async function loginAndGetToken(email: string, password: string): Promise<string> {
  const ctx = await playwrightRequest.newContext({ baseURL: BASE_URL });
  const response = await ctx.post('/api/auth/login', { data: { email, password } });
  await ctx.dispose();
  if (!response.ok()) {
    throw new Error(`Failed to login as ${email}: ${response.status()}`);
  }
  const cookies = response.headers()['set-cookie'] || '';
  const match = cookies.match(/AUTH_TOKEN=([^;]+)/);
  if (!match) throw new Error('AUTH_TOKEN cookie not set after login');
  return match[1];
}

function assignUsersGroup(emails: string[]): void {
  const host     = process.env.PGHOST     || 'localhost';
  const port     = process.env.PGPORT     || '5432';
  const user     = process.env.PGUSER     || 'postgres';
  const password = process.env.PGPASSWORD || 'postgres';
  const database = process.env.PGDATABASE || 'monitor';

  const emailList = emails.map(e => `'${e}'`).join(', ');
  const sql = `INSERT INTO user_groups (user_id, group_id) SELECT u.id, g.id FROM users u CROSS JOIN groups g WHERE u.email IN (${emailList}) AND g.name = 'Users' ON CONFLICT DO NOTHING;`;

  execSync(`psql -h ${host} -p ${port} -U ${user} -d ${database} -c "${sql}"`, {
    env: { ...process.env, PGPASSWORD: password },
    stdio: 'pipe',
  });
}

export default async function globalSetup() {
  const users = Object.values(TEST_USERS);

  // 1. Register test users (idempotent)
  for (const { email, password } of users) {
    await registerUser(email, password);
  }

  // 2. Assign to Users group (idempotent ON CONFLICT DO NOTHING)
  assignUsersGroup(users.map(u => u.email));

  // 3. Pre-login and save tokens so tests don't hit the auth rate limiter
  const tokens: Record<string, string> = {};
  for (const [key, { email, password }] of Object.entries(TEST_USERS)) {
    tokens[key] = await loginAndGetToken(email, password);
  }
  writeFileSync(AUTH_FILE, JSON.stringify(tokens));

  console.log('[globalSetup] Test users bootstrapped and tokens saved');
}
