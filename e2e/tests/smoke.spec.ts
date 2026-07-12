import { test, expect } from '@playwright/test';

// Walking-skeleton smoke: the embedded web UI is served and the API answers.

test('serves the web UI at /', async ({ page }) => {
  const response = await page.goto('/');
  expect(response, 'GET / should respond').toBeTruthy();
  expect(response!.ok()).toBeTruthy();
  expect(response!.headers()['content-type']).toContain('text/html');
  await expect(page).toHaveTitle(/WaxDeck/);
});

test('health endpoint reports ok', async ({ request }) => {
  const response = await request.get('/api/v1/health');
  expect(response.ok()).toBeTruthy();
  expect(response.headers()['content-type']).toContain('application/json');
  const body = await response.json();
  expect(body.status).toBe('ok');
  // Shape per the Health schema in api/openapi.yaml.
  expect(typeof body.version).toBe('string');
  expect(typeof body.apiVersion).toBe('number');
});
