import { test, expect, Page } from '@playwright/test';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const TEST_EMAIL = 'e2e-test@test.com';
const TEST_PASS = 'e2e-test-pass';

/** Read the pre-saved token from globalSetup — avoids hitting the auth rate limiter. */
function getSavedToken(): string {
  const tokens = JSON.parse(readFileSync(join(__dirname, '.auth.json'), 'utf-8'));
  return tokens.smoke;
}

async function loginViaUI(page: Page) {
  for (let attempt = 0; attempt < 3; attempt++) {
    await page.goto('/login');
    await page.fill('input#email', TEST_EMAIL);
    await page.fill('input#password', TEST_PASS);
    await page.click('button[type="submit"]');
    try {
      await expect(page.locator('header button.btn-logout')).toBeVisible({ timeout: 10000 });
      return;
    } catch {
      // Rate limited or slow — wait and retry
      await page.waitForTimeout(2000);
    }
  }
  throw new Error('Login failed after 3 attempts');
}

test.describe('Smoke Tests', () => {
  let token: string;

  test.beforeAll(() => {
    token = getSavedToken();
  });

  test('homepage redirects to login when not authenticated', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveURL(/\/login/);
  });

  test('login page loads', async ({ page }) => {
    await page.goto('/login');
    await expect(page.locator('h2')).toContainText('Login');
  });

  test('can login via UI', async ({ page }) => {
    await loginViaUI(page);
    await expect(page.locator('main')).toBeVisible();
  });

  test('dashboard displays after login', async ({ page }) => {
    await loginViaUI(page);
    await expect(page.locator('main')).toBeVisible();
  });

  test('API health endpoint is accessible without auth', async ({ request }) => {
    const response = await request.get('/api/actuator/health');
    expect(response.ok()).toBeTruthy();

    const body = await response.json();
    expect(body.status).toBe('UP');
  });

  test('pages API endpoint responds with auth', async ({ request }) => {
    const response = await request.get('/api/monitor/pages', {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(response.ok()).toBeTruthy();

    const body = await response.json();
    expect(Array.isArray(body)).toBeTruthy();
  });

  test('pages API endpoint rejects without auth', async ({ request }) => {
    const response = await request.get('/api/monitor/pages');
    expect(response.status()).toBe(401);
  });
});

test.describe('RSS Feed Tests', () => {
  let token: string;

  test.beforeAll(() => {
    token = getSavedToken();
  });

  test('RSS dashboard loads after login', async ({ page }) => {
    await loginViaUI(page);

    await page.click('text=RSS Feeds');
    await expect(page).toHaveURL(/\/rss/);
    await expect(page.locator('main')).toBeVisible();
  });

  test('RSS feeds API endpoint responds with auth', async ({ request }) => {
    const response = await request.get('/api/rss/feeds', {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(response.ok()).toBeTruthy();

    const body = await response.json();
    expect(Array.isArray(body)).toBeTruthy();
  });

  test('RSS config API endpoint responds with auth', async ({ request }) => {
    const response = await request.get('/api/rss/config', {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(response.ok()).toBeTruthy();

    const body = await response.json();
    expect(Array.isArray(body)).toBeTruthy();
  });
});

test.describe('Navigation', () => {
  test('can navigate between Monitors, RSS Feeds, and Configuration', async ({ page }) => {
    await loginViaUI(page);

    await expect(page.locator('a[href="/"]').filter({ hasText: 'Monitors' })).toBeVisible();
    await expect(page.locator('a[href="/rss"]')).toBeVisible();
    await expect(page.locator('a[href="/monitors"]').filter({ hasText: 'Configuration' })).toBeVisible();

    await page.click('text=RSS Feeds');
    await expect(page).toHaveURL(/\/rss/);

    await page.click('text=Configuration');
    await expect(page).toHaveURL(/\/monitors/);

    await page.click('nav >> text=Monitors');
    await expect(page).toHaveURL(/\/$/);
  });

  test('can navigate to page details if pages exist', async ({ page }) => {
    await loginViaUI(page);

    const pageCard = page.locator('[data-testid="page-card"]').first();
    if (await pageCard.isVisible({ timeout: 3000 }).catch(() => false)) {
      await pageCard.click();
      await expect(page).toHaveURL(/\/page\//);
    }
  });

  test('can navigate to RSS feed details if feeds exist', async ({ page }) => {
    await loginViaUI(page);

    await page.click('text=RSS Feeds');
    await expect(page).toHaveURL(/\/rss/);

    const feedLink = page.locator('[data-testid="rss-feed-card"] .card-title').first();
    if (await feedLink.isVisible({ timeout: 3000 }).catch(() => false)) {
      await feedLink.click();
      await expect(page).toHaveURL(/\/rss\/.+/);
    }
  });
});

test.describe('Configuration Page', () => {
  test('configuration page loads and shows sections', async ({ page }) => {
    await loginViaUI(page);

    await page.click('text=Configuration');
    await expect(page).toHaveURL(/\/monitors/);

    await expect(page.getByText('Page Monitors', { exact: true })).toBeVisible();
    await expect(page.getByText('RSS Feed Monitors', { exact: true })).toBeVisible();
  });

  test('can open add page monitor form', async ({ page }) => {
    await loginViaUI(page);

    await page.click('text=Configuration');
    await page.click('text=+ Add Page Monitor');

    await expect(page.locator('.config-form')).toBeVisible();
    await expect(page.locator('button:has-text("Save")')).toBeVisible();
    await expect(page.locator('button:has-text("Cancel")')).toBeVisible();
    await expect(page.locator('.config-form button:has-text("Test")')).toBeVisible();
  });

  test('can open add RSS feed form', async ({ page }) => {
    await loginViaUI(page);

    await page.click('text=Configuration');
    await page.click('text=+ Add RSS Feed');

    await expect(page.locator('.config-form')).toBeVisible();
    await expect(page.locator('button:has-text("Save")')).toBeVisible();
    await expect(page.locator('.config-form button:has-text("Test")')).toBeVisible();
  });

  test('cancel closes the form', async ({ page }) => {
    await loginViaUI(page);

    await page.click('text=Configuration');
    await page.click('text=+ Add Page Monitor');
    await expect(page.locator('.config-form')).toBeVisible();

    await page.click('button:has-text("Cancel")');
    await expect(page.locator('.config-form')).not.toBeVisible();
  });
});

test.describe('Auth Flow', () => {
  test('logout redirects to login', async ({ page }) => {
    await loginViaUI(page);

    await page.click('header button.btn-logout');
    await expect(page).toHaveURL(/\/login/);
  });

  test('register page loads and has link to login', async ({ page }) => {
    await page.goto('/register');
    await expect(page.locator('h2')).toContainText('Register');
    await expect(page.locator('a[href="/login"]')).toBeVisible();
  });

  test('login page has link to register', async ({ page }) => {
    await page.goto('/login');
    await expect(page.locator('a[href="/register"]')).toBeVisible();
  });
});

test.describe('Rate Limiting', () => {
  let token: string;

  test.beforeAll(() => {
    token = getSavedToken();
  });

  test('API returns rate limit headers', async ({ request }) => {
    const response = await request.get('/api/monitor/pages', {
      headers: { Authorization: `Bearer ${token}` },
    });

    const headers = response.headers();
    expect(headers['x-ratelimit-limit']).toBeDefined();
    expect(headers['x-ratelimit-remaining']).toBeDefined();
  });

  test('health endpoint bypasses rate limiting', async ({ request }) => {
    for (let i = 0; i < 10; i++) {
      const response = await request.get('/api/actuator/health');
      expect(response.ok()).toBeTruthy();
    }
  });
});
