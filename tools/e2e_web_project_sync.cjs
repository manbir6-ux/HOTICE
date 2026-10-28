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

const publicRoot = path.resolve(__dirname, '..', 'web', 'public');
const token = 'a'.repeat(64);
const cloudProjects = new Map();
const mockJobs = new Map();
const mockJobRequests = [];
const mockQuoteRequests = [];
const projectRequests = [];
const apiEvents = [];
let pageOrigin;
let conflictProjectId = null;

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.removeListener('error', reject);
      resolve(server.address().port);
    });
  });
}

function json(res, status, body) {
  res.writeHead(status, {
    'Access-Control-Allow-Origin': pageOrigin,
    'Vary': 'Origin',
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json',
  });
  res.end(JSON.stringify(body));
}

const api = http.createServer((req, res) => {
  apiEvents.push({method: req.method, path: req.url, origin: req.headers.origin || null});
  res.setHeader('Access-Control-Allow-Origin', pageOrigin);
  res.setHeader('Vary', 'Origin');
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type, Idempotency-Key',
      'Access-Control-Max-Age': '600',
    });
    return res.end();
  }
  if (req.headers.origin !== pageOrigin) return res.writeHead(403).end();

  let raw = '';
  req.on('data', (chunk) => { raw += chunk; });
  req.on('end', () => {
    const url = new URL(req.url, 'http://127.0.0.1');
    let body = null;
    try { body = raw ? JSON.parse(raw) : null; } catch (_) { return json(res, 400, {error: 'Invalid JSON'}); }

    if (url.pathname === '/v1/auth/login' && req.method === 'POST') {
      return json(res, 200, {accessToken: token, tokenType: 'Bearer'});
    }
    if (req.headers.authorization !== 'Bearer ' + token) {
      return json(res, 401, {error: 'Authentication required.'});
    }
    if (url.pathname === '/v1/auth/logout' && req.method === 'POST') return json(res, 200, {ok: true});
    if (url.pathname === '/v1/me' && req.method === 'GET') {
      return json(res, 200, {
        user: {id: '00000000-0000-4000-8000-000000000001', email: 'browser-test@example.test'},
        cloud: {active: true, readable: true, quotaBytes: 10485760, usedBytes: 0},
        mockGeneration: {enabled: true, credits: 10, unit: 'simulated_credits', moneyValue: 0},
      });
    }

    if (url.pathname === '/v1/jobs/quote' && req.method === 'POST') {
      mockQuoteRequests.push(body);
      return json(res, 200, {quoteToken: 'synthetic-quote', modelId: 'hotice.mock.video.v1', credits: 3, expiresAt: '2026-10-29T00:00:00Z'});
    }
    if (url.pathname === '/v1/jobs' && req.method === 'POST') {
      const idempotencyKey = req.headers['idempotency-key'];
      mockJobRequests.push({body, idempotencyKey});
      if (!idempotencyKey || !/^[A-Za-z0-9._~:-]{16,128}$/.test(idempotencyKey)) return json(res, 400, {error: 'Missing idempotency key'});
      const job = {id: '00000000-0000-4000-8000-000000000123', modelId: 'hotice.mock.video.v1', status: 'queued', reservedCredits: 3, result: null};
      mockJobs.set(job.id, job);
      return json(res, 201, {job, idempotentReplay: false});
    }
    if (url.pathname === '/v1/jobs' && req.method === 'GET') return json(res, 200, {jobs: [...mockJobs.values()]});

    if (url.pathname === '/v1/projects' && req.method === 'GET') {
      projectRequests.push({method: req.method, path: url.pathname, authorized: true});
      const projects = [...cloudProjects.values()].map(({id, title, revision, updated_at}) => ({id, title, revision, updated_at}));
      return json(res, 200, {projects});
    }
    const match = url.pathname.match(/^\/v1\/projects\/([0-9a-f-]+)$/i);
    if (match && req.method === 'GET') {
      projectRequests.push({method: req.method, path: url.pathname, authorized: true});
      const project = cloudProjects.get(match[1]);
      return project ? json(res, 200, {project}) : json(res, 404, {error: 'Not found'});
    }
    if (match && req.method === 'PUT') {
      projectRequests.push({method: req.method, path: url.pathname, authorized: true, body});
      const id = match[1];
      const existing = cloudProjects.get(id);
      if (id === conflictProjectId && existing) {
        conflictProjectId = null;
        existing.revision += 1;
        return json(res, 409, {error: 'Cloud version conflict'});
      }
      if (body?.document?.mediaData || body?.document?.filePath) {
        return json(res, 422, {error: 'Media is not accepted in a project document'});
      }
      if ((existing && body.expectedRevision !== existing.revision) || (!existing && body.expectedRevision !== 0)) {
        return json(res, 409, {error: 'Cloud version conflict'});
      }
      const project = {
        id,
        title: body.title,
        revision: (existing?.revision || 0) + 1,
        document: body.document,
        updated_at: new Date().toISOString(),
      };
      cloudProjects.set(id, project);
      if (!existing && cloudProjects.size === 1) conflictProjectId = id;
      return json(res, 200, {id, revision: project.revision});
    }
    return json(res, 405, {error: 'Method not allowed'});
  });
});

const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
};

const web = http.createServer((req, res) => {
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, pageOrigin).pathname); } catch (_) {
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
    const html = data.toString('utf8').replace(
      /<meta name="hotice-api-origin" content="[^"]*">/,
      `<meta name="hotice-api-origin" content="http://127.0.0.1:${api.address().port}">`,
    );
    data = Buffer.from(html);
  }
  res.writeHead(200, {'Cache-Control': 'no-store', 'Content-Type': contentTypes[path.extname(filename)] || 'application/octet-stream'});
  res.end(data);
});

function updateLocalDocument(page, mutate) {
  return page.evaluate(async (operation) => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('hotice.browser-projects.v1', 1);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    await new Promise((resolve, reject) => {
      const transaction = db.transaction('projects', 'readwrite');
      const store = transaction.objectStore('projects');
      const request = store.getAll();
      request.onsuccess = () => {
        const project = request.result[0];
        if (!project) return reject(new Error('No local project to update.'));
        if (operation === 'add-media') project.document.mediaData = 'data:image/jpeg;base64,synthetic';
        else delete project.document.mediaData;
        store.put(project);
      };
      request.onerror = () => reject(request.error);
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error);
    });
    db.close();
  }, mutate);
}

async function main() {
  const apiPort = await listen(api);
  const webPort = await listen(web);
  pageOrigin = `http://127.0.0.1:${webPort}`;
  const apiOrigin = `http://127.0.0.1:${apiPort}`;
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.PLAYWRIGHT_EXECUTABLE_PATH ? {executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH} : {}),
  });

  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(8000);
    const pageErrors = [];
    page.on('pageerror', (error) => pageErrors.push(error.message));
    await page.goto(pageOrigin, {waitUntil: 'networkidle'});

    assert.match(await page.locator('#accountStatus').textContent(), /service configured/i);
    assert.equal(await page.locator('#cloudSyncConsent').isChecked(), false);
    assert.equal(await page.locator('#loadCloudProjects').isDisabled(), true);
    await page.locator('#scenePrompt').fill('A synthetic scene follows a red paper kite across a quiet harbour at sunrise.');
    await page.locator('#sceneModel').selectOption('storyboard_demo');
    await page.locator('#actorNameInput').fill('Avery');
    await page.locator('#addActor').click();
    await page.locator('#saveSceneDraft').click();
    assert.match(await page.locator('#sceneStatus').textContent(), /Saved in this browser session/);
    await page.locator('#projectTitle').fill('Local sync dry run');
    await page.locator('#saveLocalProject').click();
    await page.waitForFunction(() => document.querySelector('#projectStatus').textContent.includes('Project saved on this device'));
    await page.locator('#localProjects .project-card').getByRole('button', {name: 'Open'}).waitFor();
    await page.reload({waitUntil: 'networkidle'});
    await page.locator('#localProjects .project-card').getByRole('button', {name: 'Open'}).click();
    await page.waitForFunction(() => document.querySelector('#projectStatus').textContent.includes('Opened locally'));
    assert.match(await page.locator('#scenePrompt').inputValue(), /red paper kite/);
    assert.equal(await page.locator('#sceneModel').inputValue(), 'storyboard_demo');
    assert.match(await page.locator('#actorList').innerText(), /Avery/);

    // Seed a local-only media field and prove it is rejected before network transfer.
    await updateLocalDocument(page, 'add-media');
    assert.equal(await page.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open('hotice.browser-projects.v1', 1);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      const value = await new Promise((resolve, reject) => {
        const request = db.transaction('projects').objectStore('projects').getAll();
        request.onsuccess = () => resolve(request.result[0]?.document?.mediaData);
        request.onerror = () => reject(request.error);
      });
      db.close();
      return value;
    }), 'data:image/jpeg;base64,synthetic');
    await page.reload({waitUntil: 'networkidle'});
    await page.locator('#accountEmail').fill('browser-test@example.test');
    await page.locator('#accountPassword').fill('synthetic-only-password');
    await page.locator('#accountSignIn').click();
    await page.getByText('Signed in and verified with the HOTICE server.').waitFor();
    await page.locator('#scenePrompt').fill('A synthetic scene follows a red paper kite across a quiet harbour at sunrise.');
    assert.equal(await page.locator('#quoteMockJob').isDisabled(), false);
    assert.equal(mockQuoteRequests.length, 0, 'sign-in alone does not submit the scene prompt');
    await page.locator('#quoteMockJob').click();
    await page.getByText(/Mock dry run quote: 3 simulated credits/).waitFor();
    assert.equal(mockQuoteRequests.length, 1);
    assert.equal(mockQuoteRequests[0].request.modelId, 'hotice.mock.video.v1');
    assert.match(mockQuoteRequests[0].request.prompt, /red paper kite/);
    await page.evaluate(() => { window.confirm = () => true; });
    await page.locator('#submitMockJob').click();
    await page.getByText(/Mock job queued/).waitFor();
    assert.equal(mockJobRequests.length, 1);
    assert.match(mockJobRequests[0].idempotencyKey, /^web-[0-9a-f-]{36}$/i);
    assert.equal(mockJobRequests[0].body.request.modelId, 'hotice.mock.video.v1');
    assert.equal(mockJobRequests[0].body.request.prompt, mockQuoteRequests[0].request.prompt);
    await page.locator('#refreshMockJobs').click();
    await page.getByText('Job list refreshed. Results are mock metadata only; no video was created.').waitFor();
    assert.match(await page.locator('#mockJobs').innerText(), /Mock job · queued/);
    assert.equal(await page.locator('#loadCloudProjects').isDisabled(), true, 'cloud list stays disabled without consent');
    assert.equal(projectRequests.length, 0, 'sign-in alone does not load cloud project data');
    await page.locator('#cloudSyncConsent').check();
    await page.locator('#cloudSyncConsent').uncheck();
    assert.equal(await page.locator('#loadCloudProjects').isDisabled(), true, 'revoking consent disables cloud reads');
    assert.equal(projectRequests.length, 0, 'revoking consent prevents cloud requests');
    await page.locator('#cloudSyncConsent').check();
    await page.locator('#localProjects .project-card').getByRole('button', {name: 'Sync to cloud'}).click();
    const unsafeSyncStatus = await page.locator('#cloudProjectStatus').textContent();
    assert.match(unsafeSyncStatus, /Inline media is not included/, `unexpected media sync result: ${unsafeSyncStatus}; requests=${JSON.stringify(apiEvents)}; uploads=${JSON.stringify(projectRequests.map(({method, path, body}) => ({method, path, mediaIncluded: Boolean(body?.document?.mediaData)})))}`);
    assert.equal(projectRequests.filter((request) => request.method === 'PUT').length, 0, 'local media is rejected before upload');

    await updateLocalDocument(page, 'remove-media');
    await page.reload({waitUntil: 'networkidle'});
    await page.locator('#accountEmail').fill('browser-test@example.test');
    await page.locator('#accountPassword').fill('synthetic-only-password');
    await page.locator('#accountSignIn').click();
    await page.getByText('Signed in and verified with the HOTICE server.').waitFor();
    assert.equal(await page.locator('#loadCloudProjects').isDisabled(), true, 'consent resets after page reload');
    await page.locator('#cloudSyncConsent').check();
    await page.locator('#loadCloudProjects').click();
    await page.getByText('No cloud projects are saved to this account yet.').waitFor();
    await page.locator('#localProjects .project-card').getByRole('button', {name: 'Sync to cloud'}).click();
    await page.getByText(/Cloud copy saved at revision 1/).waitFor();
    assert.equal(cloudProjects.size, 1);
    assert.match(cloudProjects.values().next().value.document.scenes[0].prompt, /red paper kite/);

    await page.locator('#scenePrompt').fill('This local edit must survive an optimistic-lock conflict.');
    await page.locator('#saveSceneDraft').click();
    await page.locator('#saveLocalProject').click();
    await page.locator('#localProjects .project-card').getByRole('button', {name: 'Sync updates'}).click();
    await page.getByText(/cloud copy changed elsewhere/i).waitFor();
    await page.locator('#localProjects .project-card').getByRole('button', {name: 'Open'}).click();
    assert.match(await page.locator('#scenePrompt').inputValue(), /must survive an optimistic-lock conflict/);
    await page.locator('#localProjects .project-card').getByRole('button', {name: 'Upload as separate cloud copy'}).click();
    await page.getByText(/Cloud copy saved at revision 1/).waitFor();
    assert.equal(cloudProjects.size, 2, 'separate copy keeps the conflicting cloud version intact');
    assert.notEqual([...cloudProjects.keys()][0], [...cloudProjects.keys()][1]);
    assert(projectRequests.length >= 3 && projectRequests.every((request) => request.authorized));
    assert(projectRequests.filter((request) => request.method === 'PUT').every((request) =>
      request.body && !request.body.document.mediaData && !request.body.document.filePath));
    assert.deepEqual(pageErrors, []);

    const secondContext = await browser.newContext();
    try {
      const secondPage = await secondContext.newPage();
      secondPage.setDefaultTimeout(8000);
      await secondPage.goto(pageOrigin, {waitUntil: 'networkidle'});
      await secondPage.locator('#accountEmail').fill('browser-test@example.test');
      await secondPage.locator('#accountPassword').fill('synthetic-only-password');
      await secondPage.locator('#accountSignIn').click();
      await secondPage.getByText('Signed in and verified with the HOTICE server.').waitFor();
      await secondPage.locator('#cloudSyncConsent').check();
      await secondPage.locator('#loadCloudProjects').click();
      await secondPage.getByRole('button', {name: 'Save cloud copy on this device'}).first().click();
      await secondPage.locator('#localProjects .project-card').getByRole('button', {name: 'Open'}).waitFor();
      await secondPage.locator('#localProjects .project-card').getByRole('button', {name: 'Open'}).click();
      await secondPage.waitForFunction(() => document.querySelector('#projectStatus').textContent.includes('Opened locally'));
      assert.match(await secondPage.locator('#scenePrompt').inputValue(), /optimistic-lock conflict|red paper kite/);
    } finally {
      await secondContext.close();
    }

    console.log(JSON.stringify({
      result: 'PASS',
      scenarios: [
        'local project save, reload and reopen',
        'media data rejected before upload',
        'authenticated mock generation quote, explicit submit, idempotency and status refresh',
        'cloud controls disabled until login and consent',
        'entitled account loads cloud list',
        'first cloud upload is authenticated',
        'revision conflict preserves local project',
        'separate cloud copy preserves both versions',
        'a second device downloads a cloud project into its own local storage',
      ],
      mockCloudProjectCount: cloudProjects.size,
      mockJobCount: mockJobs.size,
      realProviderCalls: 0,
    }));
  } finally {
    await browser.close();
    api.close();
    web.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  api.close();
  web.close();
  process.exitCode = 1;
});
