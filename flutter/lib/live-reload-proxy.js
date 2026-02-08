#!/usr/bin/env node
// Lightweight live-reload proxy for Flutter web development in Docker.
//
// Sits between the browser and `flutter run -d web-server`:
//   Browser  -->  Proxy (WEB_PORT)  -->  Flutter (FLUTTER_PORT)
//
// Features:
//   - Proxies all HTTP traffic to the Flutter dev server
//   - Injects a tiny SSE-based live-reload script into HTML responses
//   - POST /__trigger_reload  -> tells all connected browsers to reload
//   - GET  /__live_reload_events -> SSE stream for browser reload signals
//
// No external dependencies - uses only Node.js built-ins.

const http = require('http');

const FLUTTER_PORT = parseInt(process.env.FLUTTER_PORT || '8081', 10);
const PROXY_PORT = parseInt(process.env.PROXY_PORT || '8080', 10);
const LOG_PREFIX = '[live-reload]';

// Connected SSE clients
const clients = new Set();

// Script injected into HTML responses
const LIVE_RELOAD_SCRIPT = `
<script>
(function() {
  function connect() {
    var es = new EventSource('/__live_reload_events');
    es.onmessage = function(e) {
      if (e.data === 'reload') {
        console.log('[live-reload] Reloading page...');
        window.location.reload();
      }
    };
    es.onerror = function() {
      es.close();
      setTimeout(connect, 2000);
    };
  }
  connect();
})();
</script>
`;

const server = http.createServer((req, res) => {
  // SSE endpoint - browsers connect here to listen for reload signals
  if (req.url === '/__live_reload_events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });
    res.write('data: connected\n\n');
    clients.add(res);
    req.on('close', () => clients.delete(res));
    return;
  }

  // Trigger endpoint - file watcher POSTs here after hot restart completes
  if (req.url === '/__trigger_reload' && req.method === 'POST') {
    console.log(`${LOG_PREFIX} Triggering browser reload (${clients.size} client(s))`);
    for (const client of clients) {
      client.write('data: reload\n\n');
    }
    res.writeHead(200);
    res.end('OK');
    return;
  }

  // Proxy everything else to the Flutter web server
  const proxyHeaders = { ...req.headers };
  // Request uncompressed responses so we can inject the reload script into HTML
  delete proxyHeaders['accept-encoding'];

  const options = {
    hostname: '127.0.0.1',
    port: FLUTTER_PORT,
    path: req.url,
    method: req.method,
    headers: proxyHeaders,
  };

  const proxyReq = http.request(options, (proxyRes) => {
    const contentType = proxyRes.headers['content-type'] || '';

    if (contentType.includes('text/html')) {
      // Buffer HTML response so we can inject the live-reload script
      const chunks = [];
      proxyRes.on('data', (chunk) => chunks.push(chunk));
      proxyRes.on('end', () => {
        let body = Buffer.concat(chunks).toString();
        if (body.includes('</body>')) {
          body = body.replace('</body>', LIVE_RELOAD_SCRIPT + '</body>');
        } else {
          body += LIVE_RELOAD_SCRIPT;
        }
        const headers = { ...proxyRes.headers };
        headers['content-length'] = Buffer.byteLength(body);
        delete headers['content-encoding'];
        res.writeHead(proxyRes.statusCode, headers);
        res.end(body);
      });
    } else {
      // Stream non-HTML responses directly
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    }
  });

  proxyReq.on('error', (err) => {
    if (err.code === 'ECONNREFUSED') {
      res.writeHead(502);
      res.end('Flutter dev server not ready yet. Retrying...');
    } else {
      console.error(`${LOG_PREFIX} Proxy error: ${err.message}`);
      res.writeHead(502);
      res.end('Proxy error');
    }
  });

  req.pipe(proxyReq);
});

server.listen(PROXY_PORT, '0.0.0.0', () => {
  console.log(`${LOG_PREFIX} Proxy on :${PROXY_PORT} -> Flutter on :${FLUTTER_PORT}`);
});
