#!/usr/bin/env node

import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const SECRET_PATHS = [
  '/config.php',
  '/schema.sql',
  '/src/App.php',
  '/bin/install.php',
  '/private-media/',
  '/backend/config.php',
  '/backend/schema.sql',
  '/backend/src/App.php',
  '/backend/bin/install.php',
  '/backend/private-media/',
  '/%2e%2e%2fconfig.php',
  '/%2e%2e%2fbackend%2fconfig.php',
  '/%252e%252e%252fconfig.php',
  '/%2e%2e%5cconfig.php',
  '/..%2fbackend%2fconfig.php',
  '/backend%2fconfig.php',
  '/backend%252fconfig.php',
  '/.env',
  '/.git/config',
  '/.htaccess',
  '/.user.ini',
  '/backend/.env',
  '/backend/.git/config',
  '/backend/.htaccess',
  '/backend/.user.ini',
  '/private-media/.htaccess',
  '/private-media/index.php',
];

function deploymentOrigin(input) {
  let url;
  try {
    url = new URL(input);
  } catch {
    throw new Error('Provide the HTTPS API origin, for example https://api.example.com.');
  }
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password ||
      (url.pathname !== '/' && url.pathname !== '') || url.search || url.hash) {
    throw new Error('The deployment URL must be a plain HTTPS origin without credentials, path, query, or fragment.');
  }
  return url.origin;
}

async function verifyDeployment(input, fetchImpl = fetch) {
  const origin = deploymentOrigin(input);
  const failures = [];
  const request = async (path, headers = {}) => {
    try {
      return await fetchImpl(`${origin}${path}`, {
        method: 'GET',
        redirect: 'manual',
        cache: 'no-store',
        signal: AbortSignal.timeout(10_000),
        headers: { Accept: 'application/json', ...headers },
      });
    } catch {
      failures.push(`${path}: request failed`);
      return null;
    }
  };

  const health = await request('/health');
  if (health) {
    if (health.status !== 200) failures.push(`/health: expected HTTP 200, received ${health.status}`);
    const contentType = health.headers.get('content-type') || '';
    if (!contentType.toLowerCase().includes('application/json')) failures.push('/health: response is not JSON');
    const requiredHeaders = [
      ['x-content-type-options', 'nosniff'],
      ['referrer-policy', 'no-referrer'],
      ['x-frame-options', 'DENY'],
    ];
    for (const [name, expected] of requiredHeaders) {
      if ((health.headers.get(name) || '').toLowerCase() !== expected.toLowerCase()) {
        failures.push(`/health: missing or invalid ${name} security header`);
      }
    }
    if (!/\bno-store\b/i.test(health.headers.get('cache-control') || '')) {
      failures.push('/health: cache-control must include no-store');
    }
    const csp = health.headers.get('content-security-policy') || '';
    if (!/\bdefault-src\s+'none'(?=;|$)/i.test(csp) || !/\bframe-ancestors\s+'none'(?=;|$)/i.test(csp)) {
      failures.push('/health: CSP must deny all default sources and framing');
    }
    const hsts = health.headers.get('strict-transport-security') || '';
    const maxAge = Number(hsts.match(/(?:^|;)\s*max-age=(\d+)/i)?.[1] || 0);
    if (maxAge < 31536000) failures.push('/health: HSTS max-age must be at least one year');
    if (!/^[a-f0-9]{16}$/i.test(health.headers.get('x-request-id') || '')) {
      failures.push('/health: request ID header is missing or malformed');
    }
    try {
      const body = await health.json();
      if (body?.service !== 'HOTICE API' || body?.status !== 'ok') {
        failures.push('/health: response does not identify a healthy HOTICE API');
      }
    } catch {
      failures.push('/health: response body is not valid JSON');
    }
  }

  const foreignOrigin = await request('/health', { Origin: 'https://hotice-probe.invalid' });
  if (foreignOrigin && foreignOrigin.status !== 403) {
    failures.push(`/health: unlisted browser origin must receive HTTP 403, received ${foreignOrigin.status}`);
  }
  if (foreignOrigin && foreignOrigin.headers.get('access-control-allow-origin')) {
    failures.push('/health: unlisted browser origin received an Access-Control-Allow-Origin header');
  }

  for (const path of SECRET_PATHS) {
    const response = await request(path);
    if (response && ![401, 403, 404, 410].includes(response.status)) {
      failures.push(`${path}: expected a blocked response (401/403/404/410), received ${response.status}`);
    }
  }

  return { ok: failures.length === 0, checkedPaths: SECRET_PATHS.length, failures };
}

export { deploymentOrigin, verifyDeployment };

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const input = process.argv[2];
  if (!input || process.argv.length !== 3) {
    console.error('Usage: node tools/verify_cpanel_deployment.mjs https://api.example.com');
    process.exitCode = 2;
  } else {
    try {
      const result = await verifyDeployment(input);
      if (result.ok) {
        console.log(`PASS: HTTPS health, foreign-origin denial and ${result.checkedPaths} protected-path checks passed.`);
      } else {
        for (const failure of result.failures) console.error(`FAIL: ${failure}`);
        process.exitCode = 1;
      }
    } catch (error) {
      console.error(`FAIL: ${error.message}`);
      process.exitCode = 2;
    }
  }
}
