'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

let chromium;
try {
  ({chromium} = require('playwright'));
} catch (_) {
  ({chromium} = require(path.join(__dirname, '..', 'web', 'node_modules', 'playwright')));
}

const apiOrigin = process.env.HOTICE_TEST_API_ORIGIN;
const email = process.env.HOTICE_E2E_EMAIL;
const password = process.env.HOTICE_E2E_PASSWORD;
const publicRoot = path.resolve(__dirname, '..', 'web', 'public');
const port = Number(process.env.HOTICE_E2E_WEB_PORT || 4173);
assert(apiOrigin && email && password, 'Set API origin and synthetic CI account credentials.');
const apiUrl = new URL(apiOrigin);
assert(['localhost', '127.0.0.1'].includes(apiUrl.hostname), 'Real API browser dry run must target loopback.');

const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
};

const web = http.createServer((req, res) => {
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, `http://127.0.0.1:${port}`).pathname); } catch (_) {
    res.writeHead(400).end();
    return;
  }
  if (pathname.endsWith('/')) pathname += 'index.html';
  const filename = path.resolve(publicRoot, '.' + pathname);
  if (!filename.startsWith(publicRoot + path.sep) || !fs.existsSync(filename) || fs.statSync(filename).isDirectory()) {
    res.writeHead(404).end();
    return;
  }
  let data = fs.readFileSync(filename);
  if (filename === path.join(publicRoot, 'index.html')) {
    data = Buffer.from(data.toString('utf8').replace(
      /<meta name="hotice-api-origin" content="[^"]*">/,
      `<meta name="hotice-api-origin" content="${apiOrigin}">`,
    ));
    res.setHeader('Content-Security-Policy', `default-src 'self'; base-uri 'self'; object-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; connect-src 'self' ${apiOrigin}; media-src 'self' blob:; font-src 'self'; form-action 'self'; frame-ancestors 'none'`);
  }
  res.writeHead(200, {
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Content-Type': contentTypes[path.extname(filename)] || 'application/octet-stream',
  });
  res.end(data);
});

async function main() {
  await new Promise((resolve, reject) => {
    web.once('error', reject);
    web.listen(port, '127.0.0.1', () => { web.removeListener('error', reject); resolve(); });
  });
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(10000);
    const errors = [];
    const apiRequests = [];
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('request', (request) => {
      if (request.url().startsWith(apiOrigin)) {
        let body = null;
        try { body = request.postDataJSON(); } catch (_) { /* Requests without JSON have no body. */ }
        apiRequests.push({method: request.method(), path: new URL(request.url()).pathname, body});
      }
    });
    await page.goto(`http://127.0.0.1:${port}`, {waitUntil: 'networkidle'});
    await page.locator('#scenePrompt').fill('A blue sailboat glides across a calm lake at sunrise.');
    assert.equal(await page.locator('#quoteMockJob').isDisabled(), true, 'job actions require an authenticated account');
    await page.locator('#accountEmail').fill(email);
    await page.locator('#accountPassword').fill(password);
    await page.locator('#accountSignIn').click();
    await page.getByText('Signed in and verified with the HOTICE server.').waitFor();
    assert.equal(await page.locator('#quoteMockJob').isDisabled(), false, 'server mock flag enables the authenticated workflow');
    await page.locator('#quoteMockJob').click();
    await page.getByText(/Mock dry run quote: .* simulated credits/).waitFor();
    await page.evaluate(() => { window.confirm = () => true; });
    await page.locator('#submitMockJob').click();
    await page.getByText(/Mock job queued/).waitFor();
    await page.locator('#refreshMockJobs').click();
    await page.getByText('Job list refreshed. Results are mock metadata only; no video was created.').waitFor();
    assert.match(await page.locator('#mockJobs').innerText(), /Mock job · queued/);

    const quote = apiRequests.find((request) => request.path === '/v1/jobs/quote' && request.method === 'POST');
    const create = apiRequests.find((request) => request.path === '/v1/jobs' && request.method === 'POST');
    assert(quote && create, 'Browser must call the real API quote and create endpoints.');
    assert.deepEqual(Object.keys(quote.body), ['request']);
    assert.deepEqual(Object.keys(quote.body.request).sort(), ['modelId', 'prompt']);
    assert.deepEqual(Object.keys(create.body).sort(), ['quoteToken', 'request']);
    assert.deepEqual(Object.keys(create.body.request).sort(), ['modelId', 'prompt']);
    assert(apiRequests.some((request) => request.method === 'OPTIONS' && request.path === '/v1/jobs'),
      'Browser must successfully preflight the idempotency-key request against the server CORS policy.');
    assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0,
      'Browser credentials must not be persisted in web storage.');
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({result: 'PASS', scenarios: [
      'real browser authentication against loopback PHP/MySQL API',
      'exact-origin CORS preflight for authenticated idempotent job creation',
      'signed simulated-credit quote, explicit mock job submission and status refresh',
      'prompt-only request shape with no media, actor references or preview-model routing',
      'bearer token absent from browser storage',
    ], apiOrigin, realProviderCalls: 0}));
  } finally {
    await browser.close();
    await new Promise((resolve) => web.close(resolve));
  }
}

main().catch((error) => {
  console.error(error.message);
  web.close();
  process.exitCode = 1;
});

