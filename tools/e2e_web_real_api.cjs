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
const registerEmail = process.env.HOTICE_REGISTER_EMAIL;
const registerPassword = process.env.HOTICE_REGISTER_PASSWORD;
const mailCapture = process.env.HOTICE_TEST_MAIL_CAPTURE;
const publicRoot = path.resolve(__dirname, '..', 'web', 'public');
const port = Number(process.env.HOTICE_E2E_WEB_PORT || 4173);
assert(apiOrigin && email && password && registerEmail && registerPassword && mailCapture,
  'Set API origin, synthetic account credentials and CI-only mail capture settings.');
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
    const apiResponses = [];
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('request', (request) => {
      if (request.url().startsWith(apiOrigin)) {
        let body = null;
        try { body = request.postDataJSON(); } catch (_) { /* Requests without JSON have no body. */ }
        apiRequests.push({method: request.method(), path: new URL(request.url()).pathname,
          body, headers: request.headers()});
      }
    });
    page.on('response', (response) => {
      if (response.url().startsWith(apiOrigin)) {
        apiResponses.push({method: response.request().method(), path: new URL(response.url()).pathname,
          headers: response.headers(), status: response.status()});
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
    assert(create.headers['idempotency-key'], 'Job creation must include its idempotency key.');
    const createResponse = apiResponses.find((response) => response.method === 'POST' && response.path === '/v1/jobs');
    assert.equal(createResponse?.headers['access-control-allow-origin'], `http://127.0.0.1:${port}`,
      'The PHP API must return its exact CORS origin on the real job response.');
    assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0,
      'Browser credentials must not be persisted in web storage.');

    // Exercise the public account lifecycle in the actual browser/API pair.
    await page.locator('#accountSignOut').click();
    await page.getByText('Signed out. The server session was revoked.').waitFor();
    await page.locator('#showRegister').click();
    await page.locator('#registerEmail').fill(registerEmail);
    await page.locator('#registerPassword').fill(registerPassword);
    await page.locator('#registerPasswordConfirm').fill(registerPassword);
    await page.locator('#accountCreate').click();
    await page.getByText(/If registration is available, a verification link will be sent/).waitFor();
    const registerRequest = apiRequests.find((request) => request.path === '/v1/auth/register' && request.method === 'POST');
    assert(registerRequest && registerRequest.body.email === registerEmail,
      'Browser registration must use the shared account API.');
    assert.equal(apiResponses.find((response) => response.path === '/v1/auth/register')?.status, 202,
      'Registration response must preserve the anti-enumeration accepted status.');

    await page.locator('[data-account-view="login"]').click();
    await page.locator('#accountEmail').fill(registerEmail);
    await page.locator('#accountPassword').fill(registerPassword);
    await page.locator('#accountSignIn').click();
    await page.getByText(/Verify your email and use an enabled HOTICE website origin/).waitFor();
    assert.equal(apiResponses.find((response) => response.path === '/v1/auth/login' && response.status === 403)?.status, 403,
      'A pending account must not receive a session.');

    const deliverMail = () => {
      const {execFileSync} = require('node:child_process');
      execFileSync('php', [path.resolve(__dirname, '../backend/bin/send-email-outbox.php'), '100'], {
        cwd: path.resolve(__dirname, '..'), stdio: 'ignore',
      });
      const messages = fs.readFileSync(mailCapture, 'utf8').split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
      return messages.filter((message) => message.to === registerEmail).at(-1)?.body || '';
    };
    const verificationBody = deliverMail();
    const verificationToken = verificationBody.match(/#token=([a-f0-9]{64})/i)?.[1];
    assert(verificationToken, 'CI mail capture must contain the one-time verification URL.');
    await page.goto(`http://127.0.0.1:${port}/#token=${verificationToken}`, {waitUntil: 'networkidle'});
    await page.getByText('Email verified. You can now sign in securely.').waitFor();

    await page.locator('#accountEmail').fill(registerEmail);
    await page.locator('#accountPassword').fill(registerPassword);
    await page.locator('#accountSignIn').click();
    await page.getByText('Signed in and verified with the HOTICE server.').waitFor();
    await page.locator('#accountSignOut').click();
    await page.getByText('Signed out. The server session was revoked.').waitFor();

    await page.locator('#showPasswordReset').click();
    await page.locator('#resetRequestEmail').fill(registerEmail);
    await page.locator('#accountResetRequest button[type="submit"]').click();
    await page.getByText('If an eligible account exists, a password reset link will be sent.').waitFor();
    const resetBody = deliverMail();
    const resetToken = resetBody.match(/#reset=([a-f0-9]{64})/i)?.[1];
    assert(resetToken, 'CI mail capture must contain the one-time password reset URL.');
    await page.goto(`http://127.0.0.1:${port}/#reset=${resetToken}`, {waitUntil: 'networkidle'});
    const rotatedPassword = registerPassword + 'Rotate1';
    await page.locator('#resetNewPassword').fill(rotatedPassword);
    await page.locator('#resetConfirmPassword').fill(rotatedPassword);
    await page.locator('#accountResetComplete button[type="submit"]').click();
    await page.getByText('Password updated and existing sessions revoked. Sign in with your new password.').waitFor();
    await page.locator('#accountEmail').fill(registerEmail);
    await page.locator('#accountPassword').fill(registerPassword);
    await page.locator('#accountSignIn').click();
    await page.getByText('Sign-in was not accepted. Check the email and password.').waitFor();
    await page.locator('#accountEmail').fill(registerEmail);
    await page.locator('#accountPassword').fill(rotatedPassword);
    await page.locator('#accountSignIn').click();
    await page.getByText('Signed in and verified with the HOTICE server.').waitFor();
    assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0,
      'Browser credentials must stay out of web storage after all account workflows.');
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({result: 'PASS', scenarios: [
      'real browser authentication against loopback PHP/MySQL API',
      'exact-origin CORS for authenticated idempotent job creation',
      'signed simulated-credit quote, explicit mock job submission and status refresh',
      'prompt-only request shape with no media, actor references or preview-model routing',
      'bearer token absent from browser storage',
      'browser registration, pending-account sign-in denial and email verification',
      'browser password reset, session revocation and old-password rejection',
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
});\n