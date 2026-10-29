import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => { page.on('pageerror', error => console.error('Browser error:', error.message)); });

test('preview browsing, book detail, mobile layout and explicit sample mode', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/?demo=1');
  await expect(page.getByText('Local preview', { exact: false })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Loved by readers' })).toBeVisible();
  await expect(page.locator('.book-card')).toHaveCount(4);
  await page.screenshot({ path: '../.local/frontend-desktop.png', fullPage: true });
  await page.getByRole('button', { name: /The Art of Paying Attention/ }).click();
  await expect(page.getByRole('heading', { name: 'Reader reviews' })).toBeVisible();
  await expect(page.getByText('The kind of book that makes you close')).toBeVisible();
  await page.getByRole('button', { name: /Back to Discover/ }).click();
  await page.getByRole('button', { name: 'The library', exact: true }).click();
  await page.getByRole('searchbox').fill('Samir');
  await expect(page.locator('.book-card')).toHaveCount(1);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: 'Discover', exact: true }).click();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: '../.local/frontend-mobile.png', fullPage: true });
  expect(errors).toEqual([]);
});

test('unconfigured app shows setup, not fake connected data', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Your next chapter starts here.' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign in' })).toBeDisabled();
});

test('configured UI has distinct signup roles and confirmation flow', async ({ page }) => {
  await page.route('**/config.json', route => route.fulfill({ json: { region: 'us-west-2', apiBase: '', pools: {
    author: { poolId: 'us-west-2_Authors', clientId: 'authorclient' }, reader: { poolId: 'us-west-2_Readers', clientId: 'readerclient' },
  } } }));
  await page.route('**/discover', route => route.fulfill({ json: { items: [] } }));
  await page.route('https://cognito-idp.us-west-2.amazonaws.com/', route => route.fulfill({ json: { UserConfirmed: false, UserSub: 'test-user' } }));
  await page.goto('/');
  await page.getByRole('button', { name: 'Sign in', exact: false }).first().click();
  await page.getByRole('button', { name: 'Author', exact: true }).click();
  await page.getByRole('button', { name: 'New here? Create an account' }).click();
  await page.getByLabel('Email address').fill('author@example.test');
  await page.getByLabel('Password', { exact: true }).fill('Testing-only-123!');
  await page.getByRole('button', { name: 'Create account', exact: false }).click();
  await expect(page.getByLabel('Confirmation code')).toBeVisible();
});
