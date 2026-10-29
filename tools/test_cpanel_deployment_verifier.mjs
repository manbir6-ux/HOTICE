import assert from 'node:assert/strict';
import test from 'node:test';
import { deploymentOrigin, verifyDeployment } from './verify_cpanel_deployment.mjs';

const secureHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store, max-age=0',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
  'content-security-policy': "default-src 'none'; frame-ancestors 'none'",
  'strict-transport-security': 'max-age=31536000',
  'x-request-id': '0123456789abcdef',
};

function mockResponse(status, body = {}, headers = secureHeaders) {
  return new Response(JSON.stringify(body), { status, headers });
}

test('accepts only a plain HTTPS origin', () => {
  assert.equal(deploymentOrigin('https://api.example.com'), 'https://api.example.com');
  for (const input of [
    'http://api.example.com',
    'https://user:pass@api.example.com',
    'https://api.example.com/path',
    'https://api.example.com/?token=secret',
  ]) assert.throws(() => deploymentOrigin(input));
});

test('passes healthy API and denies every protected path probe', async () => {
  const requests = [];
  const result = await verifyDeployment('https://api.example.com', async (url, options) => {
    requests.push({ url, options });
    if (options.headers.Origin) return mockResponse(403, { error: 'Browser origin is not allowed.' }, { 'content-type': 'application/json' });
    return url.endsWith('/health')
      ? mockResponse(200, { service: 'HOTICE API', status: 'ok', version: '0.1' })
      : mockResponse(404, { error: 'Not found' }, { 'content-type': 'application/json' });
  });
  assert.equal(result.ok, true, result.failures.join('\n'));
  assert.equal(requests.length, result.checkedPaths + 2);
  assert.ok(requests.every(({ options }) =>
    options.method === 'GET' && options.redirect === 'manual' && options.signal instanceof AbortSignal));
  for (const protectedAlias of [
    '/%2e%2e%2fconfig.php',
    '/%2e%2e%2fbackend%2fconfig.php',
    '/%252e%252e%252fconfig.php',
    '/backend%2fconfig.php',
    '/.env',
    '/.git/config',
    '/backend/.user.ini',
    '/private-media/.htaccess',
  ]) assert.ok(requests.some(({ url }) => url.endsWith(protectedAlias)), `missing probe: ${protectedAlias}`);
});

test('fails closed when a secret-bearing path is publicly served', async () => {
  const result = await verifyDeployment('https://api.example.com', async (url, options) =>
    options.headers.Origin ? mockResponse(403, {}, { 'content-type': 'application/json' }) : url.endsWith('/health')
      ? mockResponse(200, { service: 'HOTICE API', status: 'ok' })
      : mockResponse(200, { exposed: true }, { 'content-type': 'application/octet-stream' }));
  assert.equal(result.ok, false);
  assert.ok(result.failures.some((failure) => failure.includes('/config.php')));
});

test('fails on weak health headers and invalid service response', async () => {
  const weak = { ...secureHeaders, 'strict-transport-security': 'max-age=60', 'x-frame-options': '',
    'content-security-policy': "default-src 'self'" };
  const result = await verifyDeployment('https://api.example.com', async (url, options) =>
    options.headers.Origin ? mockResponse(403, {}, { 'content-type': 'application/json' }) : url.endsWith('/health')
      ? mockResponse(200, { service: 'Other API', status: 'ok' }, weak)
      : mockResponse(404, {}, { 'content-type': 'application/json' }));
  assert.equal(result.ok, false);
  assert.ok(result.failures.some((failure) => failure.includes('HSTS')));
  assert.ok(result.failures.some((failure) => failure.includes('CSP')));
  assert.ok(result.failures.some((failure) => failure.includes('x-frame-options')));
  assert.ok(result.failures.some((failure) => failure.includes('healthy HOTICE API')));
});

test('fails on redirects and unexpected protected-path response codes', async () => {
  const result = await verifyDeployment('https://api.example.com', async (url, options) =>
    options.headers.Origin ? mockResponse(403, {}, { 'content-type': 'application/json' }) : url.endsWith('/health')
      ? mockResponse(302, {}, secureHeaders)
      : mockResponse(200, {}, { 'content-type': 'application/json' }));
  assert.equal(result.ok, false);
  assert.ok(result.failures.some((failure) => failure.includes('expected HTTP 200')));
  assert.ok(result.failures.some((failure) => failure.includes('expected a blocked response')));
});

test('fails if an unlisted origin is accepted or receives wildcard CORS access', async () => {
  const result = await verifyDeployment('https://api.example.com', async (url, options) => {
    if (options.headers.Origin) {
      return mockResponse(200, { service: 'HOTICE API', status: 'ok' }, {
        ...secureHeaders,
        'access-control-allow-origin': '*',
      });
    }
    return url.endsWith('/health')
      ? mockResponse(200, { service: 'HOTICE API', status: 'ok' })
      : mockResponse(404, {}, { 'content-type': 'application/json' });
  });
  assert.equal(result.ok, false);
  assert.ok(result.failures.some((failure) => failure.includes('HTTP 403')));
  assert.ok(result.failures.some((failure) => failure.includes('Access-Control-Allow-Origin')));
});
