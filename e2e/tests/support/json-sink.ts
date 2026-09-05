// A loopback JSON sink for notification-delivery scenarios: captures
// every POSTed body so a spec can assert the server actually delivered.
// The e2e server is a host process, so 127.0.0.1 is reachable, and
// server-scope targets are deliberately unguarded, so no stack or
// environment change is needed.

/// One delivery as it arrived: the parsed body (or the raw text where
/// it is not JSON), the headers that carried it, and the bytes the
/// signature was computed over.
export interface SinkDelivery {
  readonly body: unknown;
  readonly headers: Record<string, string>;
  readonly raw: string;
}

export async function startJsonSink(): Promise<{
  url: string;
  received: () => unknown[];
  deliveries: () => SinkDelivery[];
  close: () => Promise<void>;
}> {
  const { createServer } = await import('node:http');
  const deliveries: SinkDelivery[] = [];
  const server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      let body: unknown = raw;
      try {
        body = JSON.parse(raw);
      } catch {
        // Left as text: a sink that threw here would hide the delivery
        // rather than let the spec say what arrived.
      }
      const headers: Record<string, string> = {};
      for (const [name, value] of Object.entries(req.headers)) {
        if (typeof value === 'string') headers[name.toLowerCase()] = value;
      }
      deliveries.push({ body, headers, raw });
      res.writeHead(200).end();
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('sink did not bind a port');
  }
  return {
    url: `http://127.0.0.1:${address.port}`,
    received: () => deliveries.map((d) => d.body),
    deliveries: () => [...deliveries],
    close: () => new Promise((resolve) => server.close(() => resolve())),
  };
}
