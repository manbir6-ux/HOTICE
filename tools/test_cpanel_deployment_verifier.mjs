import assert from 'node:assert/strict';
import test from 'node:test';
import { deploymentOrigin, verifyDeployment } from './verify_cpanel_deployment.mjs';

const secureHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store, max-age=0',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
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
    return url.endsWith('/health')
      ? mockResponse(200, { service: 'HOTICE API', status: 'ok', version: '0.1' })
      : mockResponse(404, { error: 'Not found' }, { 'content-type': 'application/json' });
  });
  assert.equal(result.ok, true, result.failures.join('\n'));
  assert.equal(requests.length, result.checkedPaths);
  assert.ok(requests.every(({ options }) => options.method === 'GET' && options.redirect === 'manual'));
  assert.ok(requests.some(({ url }) => url.includes('/%2e%2e%2fconfig.php')));
});

test('fails closed when a secret-bearing path is publicly served', async () => {
  const result = await verifyDeployment('https://api.example.com', async (url) =>
    url.endsWith('/health')
      ? mockResponse(200, { service: 'HOTICE API', status: 'ok' })
      : mockResponse(200, { exposed: true }, { 'content-type': 'application/octet-stream' }));
  assert.equal(result.ok, false);
  assert.ok(result.failures.some((failure) => failure.includes('/config.php')));
});

test('fails on weak health headers and invalid service response', async () => {
  const weak = { ...secureHeaders, 'strict-transport-security': 'max-age=60', 'x-frame-options': '' };
  const result = await verifyDeployment('https://api.example.com', async (url) =>
    url.endsWith('/health')
      ? mockResponse(200, { service: 'Other API', status: 'ok' }, weak)
      : mockResponse(404, {}, { 'content-type': 'application/json' }));
  assert.equal(result.ok, false);
  assert.ok(result.failures.some((failure) => failure.includes('HSTS')));
  assert.ok(result.failures.some((failure) => failure.includes('x-frame-options')));
  assert.ok(result.failures.some((failure) => failure.includes('healthy HOTICE API')));
});

test('fails on redirects and unexpected protected-path response codes', async () => {
  const result = await verifyDeployment('https://api.example.com', async (url) =>
    url.endsWith('/health')
      ? mockResponse(302, {}, secureHeaders)
      : mockResponse(200, {}, { 'content-type': 'application/json' }));
  assert.equal(result.ok, false);
  assert.ok(result.failures.some((failure) => failure.includes('expected HTTP 200')));
  assert.ok(result.failures.some((failure) => failure.includes('expected a blocked response')));
});
