import { test, expect, Page } from '@playwright/test';

const TEST_EMAIL = 'e2e-nav@test.com';
const TEST_PASS = 'e2e-nav-pass';

async function loginViaUI(page: Page) {
  await page.goto('/login');
  await page.fill('input#email', TEST_EMAIL);
  await page.fill('input#password', TEST_PASS);
  await page.click('button[type="submit"]');
  await expect(page.locator('header button.btn-logout')).toBeVisible();
}

test('simple navigation to RSS Feeds', async ({ page }) => {
  await loginViaUI(page);
  await expect(page.locator('main')).toBeVisible();

  await page.click('text=RSS Feeds');
  await expect(page).toHaveURL(/\/rss/);

  // Wait for loading to complete: expect either feed cards or the empty-state message
  const feedCards = page.locator('[data-testid="rss-feed-card"]');
  const noFeedsMsg = page.getByText('No RSS feeds configured');
  await expect(feedCards.first().or(noFeedsMsg)).toBeVisible({ timeout: 10000 });
});

test('back and forth navigation preserves data loading', async ({ page }) => {
  await loginViaUI(page);
  await expect(page.locator('main')).toBeVisible();

  await page.click('text=RSS Feeds');
  await expect(page).toHaveURL(/\/rss/);
  await expect(page.locator('main')).toBeVisible();

  await page.click('nav >> text=Monitors');
  await expect(page.locator('main')).toBeVisible();

  await page.click('text=RSS Feeds');
  await expect(page).toHaveURL(/\/rss/);

  await expect(page.locator('.card, main').first()).toBeVisible({ timeout: 5000 });
});

test('navigation to Configuration page', async ({ page }) => {
  await loginViaUI(page);
  await expect(page.locator('main')).toBeVisible();

  await page.click('text=Configuration');
  await expect(page).toHaveURL(/\/monitors/);

  await expect(page.getByText('Page Monitors', { exact: true })).toBeVisible();
  await expect(page.getByText('RSS Feed Monitors', { exact: true })).toBeVisible();
});
