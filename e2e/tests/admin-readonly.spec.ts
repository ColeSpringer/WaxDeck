import { test, expect } from './fixtures';

// Server-wide read-only, which is the one switch in this suite that
// nothing else can run beside.
//
// It lived in admin-ops.spec.ts and cost that project its parallelism:
// read-only refuses every write on the stack with a 409, so while this
// test holds it on, the trash round trip, the uploads and the runtime
// library all fail - and the file's answer was one worker in order for
// all seven of its tests. A project of its own, after that one, is the
// same guarantee at a quarter of the cost: the switch is still alone on
// the stack, and the six tests that were serialized for its sake are
// parallel again.

test('read-only mode refuses uploads and releases', async ({ app }) => {
  const settings = await app.api.get('/admin/settings');

  await app.api.put('/admin/settings', { data: { ...settings, readOnly: true } });
  try {
    const refused = await app.api.raw.post('/uploads', {
      data: { fileName: 'nope.mp3', sizeBytes: 1024, mediaType: 'music' },
    });
    expect(refused.status()).toBe(409);
    expect((await refused.json()).code).toBe('read-only');
  } finally {
    await app.api.put('/admin/settings', { data: { ...settings, readOnly: false } });
  }
});
