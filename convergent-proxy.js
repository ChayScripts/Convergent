#!/usr/bin/env node
/**
 * convergent-proxy.js
 * ───────────────────
 * Lightweight CORS proxy for Convergent — lets the browser reach NVIDIA NIM
 * (and any other CORS-blocked API) from a local file:// or localhost origin.
 *
 * Usage
 *   node convergent-proxy.js [--port 3030]
 *   npx convergent-proxy [--port 3030]         ← if published to npm
 *
 * How it works
 *   The browser sends requests to http://localhost:<port>/proxy?url=<encoded-target>
 *   The proxy forwards them server-side (no CORS restriction) and streams
 *   the response back with the appropriate CORS headers.
 *
 * The proxy also exposes GET /health for the "Test Proxy Connection" button.
 *
 * Security note
 *   This proxy only accepts requests from localhost and only forwards to HTTPS
 *   targets. It is NOT intended for production use — run it locally only.
 */

'use strict';

const http  = require('http');
const https = require('https');
const url   = require('url');

// ── Config ────────────────────────────────────────────────────────────────────
const DEFAULT_PORT = 3030;
const VERSION      = '1.0.0';

// Only forward to these hosts (whitelist to prevent open-proxy abuse)
const ALLOWED_HOSTS = [
  'integrate.api.nvidia.com',
  'api.openai.com',
  'generativelanguage.googleapis.com',
  'api.groq.com',
  'api.together.xyz',
  'api.mistral.ai',
  'api.anthropic.com',
  // Add more as needed
];

// ── Argument parsing ──────────────────────────────────────────────────────────
const args = process.argv.slice(2);
let port = DEFAULT_PORT;
for (let i = 0; i < args.length; i++) {
  if ((args[i] === '--port' || args[i] === '-p') && args[i + 1]) {
    port = parseInt(args[i + 1], 10);
    if (isNaN(port) || port < 1 || port > 65535) {
      console.error('Invalid port:', args[i + 1]);
      process.exit(1);
    }
  }
}

// ── CORS headers sent on every response ──────────────────────────────────────
function corsHeaders() {
  return {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS, DELETE, PUT, PATCH',
    'Access-Control-Allow-Headers': [
      'Authorization', 'Content-Type', 'Accept',
      'X-Api-Key', 'X-Target-Auth',          // Convergent custom headers
    ].join(', '),
    'Access-Control-Max-Age': '86400',
  };
}

// ── Request handler ───────────────────────────────────────────────────────────
function handler(req, res) {
  const parsed = url.parse(req.url, true);

  // ── Preflight ──
  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders());
    res.end();
    return;
  }

  // ── Health check ──
  if (parsed.pathname === '/health') {
    res.writeHead(200, { ...corsHeaders(), 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: VERSION, port }));
    return;
  }

  // ── Proxy route ──
  if (parsed.pathname === '/proxy') {
    const rawTarget = parsed.query.url;
    if (!rawTarget) {
      res.writeHead(400, corsHeaders());
      res.end('Missing ?url= parameter');
      return;
    }

    let target;
    try {
      target = new URL(decodeURIComponent(rawTarget));
    } catch (_) {
      res.writeHead(400, corsHeaders());
      res.end('Invalid target URL');
      return;
    }

    // Only allow HTTPS targets
    if (target.protocol !== 'https:') {
      res.writeHead(403, corsHeaders());
      res.end('Only HTTPS targets are allowed');
      return;
    }

    // Whitelist check
    if (!ALLOWED_HOSTS.some(h => target.hostname === h || target.hostname.endsWith('.' + h))) {
      console.warn('[proxy] Blocked request to:', target.hostname);
      res.writeHead(403, corsHeaders());
      res.end('Target host not in allowed list: ' + target.hostname);
      return;
    }

    // Build forwarded headers — strip hop-by-hop, map Convergent's custom headers
    const fwdHeaders = {
      'Content-Type':  req.headers['content-type']  || 'application/json',
      'Accept':        req.headers['accept']         || 'application/json',
      'User-Agent':    'convergent-proxy/' + VERSION,
    };

    // Map custom auth header → Authorization (Convergent sends X-Target-Auth)
    const targetAuth = req.headers['x-target-auth'];
    const apiKey     = req.headers['x-api-key'];
    if (targetAuth) {
      fwdHeaders['Authorization'] = targetAuth;
    } else if (apiKey) {
      fwdHeaders['Authorization'] = 'Bearer ' + apiKey;
    } else if (req.headers['authorization']) {
      fwdHeaders['Authorization'] = req.headers['authorization'];
    }

    // Stream request body
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      const body = chunks.length ? Buffer.concat(chunks) : null;
      if (body && body.length) fwdHeaders['Content-Length'] = body.length;

      const options = {
        hostname: target.hostname,
        port:     target.port || 443,
        path:     target.pathname + (target.search || ''),
        method:   req.method === 'GET' ? 'GET' : 'POST',
        headers:  fwdHeaders,
      };

      console.log(`[proxy] ${options.method} ${target.href.slice(0, 120)}`);

      const proxyReq = https.request(options, proxyRes => {
        const status  = proxyRes.statusCode || 500;
        const outHdrs = { ...corsHeaders() };
        // Forward content-type so browser can parse JSON/SSE correctly
        if (proxyRes.headers['content-type']) {
          outHdrs['Content-Type'] = proxyRes.headers['content-type'];
        }
        // Stream mode (SSE) — disable buffering
        if ((proxyRes.headers['content-type'] || '').includes('text/event-stream')) {
          outHdrs['Cache-Control']       = 'no-cache';
          outHdrs['X-Accel-Buffering']   = 'no';
          outHdrs['Transfer-Encoding']   = 'chunked';
        } else if (proxyRes.headers['content-length']) {
          outHdrs['Content-Length'] = proxyRes.headers['content-length'];
        }

        res.writeHead(status, outHdrs);
        proxyRes.pipe(res);
        proxyRes.on('error', err => {
          console.error('[proxy] upstream error:', err.message);
          res.end();
        });
      });

      proxyReq.on('error', err => {
        console.error('[proxy] request error:', err.message);
        if (!res.headersSent) {
          res.writeHead(502, corsHeaders());
        }
        res.end('Proxy error: ' + err.message);
      });

      if (body && body.length) proxyReq.write(body);
      proxyReq.end();
    });

    return;
  }

  // ── Unknown route ──
  res.writeHead(404, corsHeaders());
  res.end('Not found. Valid routes: /health  /proxy?url=<encoded-target>');
}

// ── Start server ──────────────────────────────────────────────────────────────
const server = http.createServer(handler);

server.listen(port, '127.0.0.1', () => {
  console.log('');
  console.log('  ┌─────────────────────────────────────────────┐');
  console.log('  │        Convergent CORS Proxy  v' + VERSION + '         │');
  console.log('  ├─────────────────────────────────────────────┤');
  console.log('  │  Listening on  http://127.0.0.1:' + port + '         │');
  console.log('  │  Health check  http://127.0.0.1:' + port + '/health  │');
  console.log('  │                                             │');
  console.log('  │  In Convergent → Settings → Endpoints      │');
  console.log('  │  CORS Proxy section → enter URL above      │');
  console.log('  │  and click "Test Proxy Connection"         │');
  console.log('  │                                             │');
  console.log('  │  Press Ctrl+C to stop                      │');
  console.log('  └─────────────────────────────────────────────┘');
  console.log('');
});

server.on('error', err => {
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${port} is already in use. Try: node convergent-proxy.js --port 3031`);
  } else {
    console.error('Server error:', err.message);
  }
  process.exit(1);
});

// Graceful shutdown
process.on('SIGINT',  () => { console.log('\nProxy stopped.'); server.close(); process.exit(0); });
process.on('SIGTERM', () => { server.close(); process.exit(0); });
