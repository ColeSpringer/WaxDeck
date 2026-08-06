// A loopback JSON sink for notification-delivery scenarios: captures
// every POSTed body so a spec can assert the server actually delivered.
// The e2e server is a host process, so 127.0.0.1 is reachable, and
// server-scope targets are deliberately unguarded, so no stack or
// environment change is needed.
export async function startJsonSink(): Promise<{
  url: string;
  received: () => unknown[];
  close: () => Promise<void>;
}> {
  const { createServer } = await import('node:http');
  const received: unknown[] = [];
  const server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      try {
        received.push(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        received.push(Buffer.concat(chunks).toString('utf8'));
      }
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
    received: () => [...received],
    close: () => new Promise((resolve) => server.close(() => resolve())),
  };
}
