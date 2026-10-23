// The stack's readiness, past what the webServer check sees.
//
// The server answers /health from the moment it listens, and its bridge
// reaches the streaming sidecar in the background a few seconds later:
// the sidecar starts by waiting for the catalog the server creates. The
// specs that play through the engine assume it, so the run starts once
// it has connected rather than each of them waiting for it. A server
// with no engine configured, or too old to say, is ready as it is.

const base = process.env.WAXDECK_BASE_URL ?? 'http://localhost:4420';

/// Long enough for the sidecar's catalog wait and the bridge's backoff
/// together, both of which start with the stack.
const CONNECT_BUDGET_MS = 120_000;

interface Health {
  streaming?: { configured: boolean; connected: boolean };
}

async function connected(): Promise<boolean> {
  try {
    const response = await fetch(`${base}/api/v1/health`);
    if (!response.ok) return false;
    const { streaming } = (await response.json()) as Health;
    return streaming === undefined || !streaming.configured || streaming.connected;
  } catch {
    return false;
  }
}

export default async function engineReady(): Promise<void> {
  const deadline = Date.now() + CONNECT_BUDGET_MS;
  while (!(await connected())) {
    if (Date.now() > deadline) {
      throw new Error(`the streaming engine behind ${base} did not connect within ${CONNECT_BUDGET_MS / 1000}s`);
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}
