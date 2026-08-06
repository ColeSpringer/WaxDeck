import { test, expect } from './fixtures';

// Walking-skeleton smoke: the embedded web UI is served and the API answers.

test('serves the web UI at /', async ({ request }) => {
  // Fetched rather than navigated to. What is under test is what the
  // binary serves - a document, of the right type, carrying the app's
  // own title - and every other spec in the suite already proves the
  // page boots from it. A `goto` here would spend a wasm boot restating
  // that.
  const response = await request.get('/');
  expect(response.ok(), 'GET / should respond').toBeTruthy();
  expect(response.headers()['content-type']).toContain('text/html');
  expect(await response.text()).toMatch(/<title>[^<]*WaxDeck/);
});

test('health endpoint reports ok', async ({ app }) => {
  const health = await app.api.get('/health');
  expect(health.status).toBe('ok');
  // The contract's own shape, checked at runtime as well as at compile
  // time: the generated types say what the server promised, and this
  // says what it sent.
  expect(typeof health.version).toBe('string');
  expect(typeof health.apiVersion).toBe('number');
});
