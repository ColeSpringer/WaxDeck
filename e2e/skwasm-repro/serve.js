// Static server for the repro build with the same cross-origin
// isolation headers WaxDeck's server sends (COOP same-origin + COEP
// credentialless), so skwasm picks the same multi-threaded path.
// /art/<n>.png alternates 404 and a tiny PNG, like the missing
// cover-art burst in the captured trace.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, 'build', 'web');
const port = Number(process.env.PORT || 4499);

const PNG_1PX = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);

const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png',
  '.otf': 'font/otf', '.ttf': 'font/ttf', '.frag': 'application/octet-stream',
};

http.createServer((req, res) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'credentialless');
  const url = new URL(req.url, 'http://x');
  const art = url.pathname.match(/^\/art\/(\d+)\.png$/);
  if (art) {
    if (Number(art[1]) % 2 === 1) {
      res.writeHead(404).end('no art');
    } else {
      res.writeHead(200, { 'Content-Type': 'image/png' }).end(PNG_1PX);
    }
    return;
  }
  let file = path.join(root, decodeURIComponent(url.pathname));
  if (url.pathname === '/') file = path.join(root, 'index.html');
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404).end('not found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': types[path.extname(file)] || 'application/octet-stream',
    });
    res.end(data);
  });
}).listen(port, '127.0.0.1', () => console.log(`repro server on :${port}`));
