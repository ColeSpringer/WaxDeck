// A loopback ListenBrainz for the scenarios that need a *connected*
// scrobbler rather than a delivered listen. Connecting validates the
// token against the service, so an account with a live connection
// cannot be seeded through the API alone.
//
// Deliberately not the JSON sink beside it: that one captures bodies
// and answers 200 to everything, and what makes this a ListenBrainz is
// the one route it answers with a shape - `/1/validate-token`, whose
// `valid` field is what the connect path reads. Nothing here records
// what was submitted; a spec that wants to assert a delivery wants the
// sink.
//
// The e2e server is a host process, so 127.0.0.1 is reachable, and the
// stack runs with WAXDECK_ALLOW_PRIVATE_SCROBBLE_HOSTS so the
// write-time guard takes an apiUrl pointing here.

export async function startListenBrainzStub(username = 'e2e-listener'): Promise<{
  url: string;
  close: () => Promise<void>;
}> {
  const { createServer } = await import('node:http');
  const server = createServer((req, res) => {
    // Drained either way: a request body left unread keeps the socket
    // busy and the close below waiting on it.
    req.resume();
    req.on('end', () => {
      if ((req.url ?? '').startsWith('/1/validate-token')) {
        res
          .writeHead(200, { 'content-type': 'application/json' })
          .end(JSON.stringify({ valid: true, user_name: username }));
        return;
      }
      res.writeHead(200, { 'content-type': 'application/json' }).end('{"status":"ok"}');
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('listenbrainz stub did not bind a port');
  }
  return {
    url: `http://127.0.0.1:${address.port}`,
    // closeAllConnections first: the server keeps delivery sockets
    // alive, and `close` alone waits for every one of them to go idle -
    // which is a hung teardown rather than a finished test.
    close: () =>
      new Promise((resolve) => {
        server.closeAllConnections();
        server.close(() => resolve());
      }),
  };
}
