/* HOTICE client-side prototype. No network call except same-origin JSON catalog.
   No media uploads, provider APIs, billing or hidden key access. */
(() => {
  'use strict';
  const get = (id) => document.getElementById(id);
  const status = (id, message) => { if (get(id)) get(id).textContent = message; };
  const modelLimits = {
    cinematic_demo: 2, character_demo: 4,
    storyboard_demo: 1, multimodal_demo: 6,
  };
  let catalog = [];
  let selectedTemplate = null;
  let clips = [];
  let activeClip = -1;
  let serial = 0;
  let sequence = false;
  let sceneDrafts = [];
  const actorStorageKey = 'hotice.preview.actors.v1';
  let actorNames = [];
  try {
    const saved = JSON.parse(localStorage.getItem(actorStorageKey) || '[]');
    if (Array.isArray(saved)) {
      actorNames = [...new Map(saved.filter((name) =>
        typeof name === 'string' && name.trim() && name.trim().length <= 60)
        .map((name) => name.trim())
        .map((name) => [name.toLowerCase(), name])).values()];
    }
  } catch (_) {
    // Browser storage can be disabled; Actors remain available for this session.
  }

  function make(tag, className, label) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (label !== undefined) node.textContent = label;
    return node;
  }

  const search = get('librarySearch');
  const category = get('libraryCategory');
  const gallery = get('libraryCards');
  function saveActorNames() {
    try {
      localStorage.setItem(actorStorageKey, JSON.stringify(actorNames));
    } catch (_) {
      status('sceneStatus', 'Actor list is available for this session only.');
    }
  }

  function renderActors() {
    const list = get('actorList');
    if (!list) return;
    list.replaceChildren();
    if (!actorNames.length) list.append(make('span', 'editor-note', 'No Actors saved yet.'));
    actorNames.forEach((name, index) => {
      const row = make('span', 'actor-chip');
      row.append(make('span', '', name));
      const remove = make('button', 'actor-remove', 'Remove');
      remove.type = 'button';
      remove.setAttribute('aria-label', 'Remove Actor ' + name);
      remove.addEventListener('click', () => {
        actorNames.splice(index, 1);
        saveActorNames();
        renderActors();
        renderActorAssignments();
      });
      row.append(remove);
      list.append(row);
    });
  }

  function renderActorAssignments() {
    const root = get('actorAssignments');
    if (!root) return;
    root.replaceChildren();
    const roles = selectedTemplate?.actorSlots || [];
    if (!roles.length) return;
    root.append(make('strong', '', 'Assign your Actors to this prompt'));
    if (!actorNames.length) {
      root.append(make('p', 'editor-note', 'Add named Actors above to fill the template roles.'));
    }
    roles.forEach((role, index) => {
      const label = make('label', 'actor-role', 'Actor role ' + (index + 1));
      const select = document.createElement('select');
      select.dataset.role = role;
      const empty = make('option', '', 'Choose a saved Actor');
      empty.value = '';
      select.append(empty);
      actorNames.forEach((name) => {
        const option = make('option', '', name);
        option.value = name;
        select.append(option);
      });
      label.append(select);
      root.append(label);
    });
  }

  get('addActor')?.addEventListener('click', () => {
    const input = get('actorNameInput');
    const name = input.value.trim();
    if (!name) return status('sceneStatus', 'Enter an Actor name first.');
    if (actorNames.some((item) => item.toLowerCase() === name.toLowerCase())) {
      return status('sceneStatus', 'That Actor name is already saved.');
    }
    actorNames.push(name);
    input.value = '';
    saveActorNames();
    renderActors();
    renderActorAssignments();
    status('sceneStatus', 'Actor saved on this device only.');
  });

  get('actorNameInput')?.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      get('addActor').click();
    }
  });
  renderActors();

  function libraryFilter() {
    if (!gallery) return;
    gallery.replaceChildren();
    const query = (search.value || '').trim().toLowerCase();
    const matching = catalog.filter((item) =>
      (category.value === 'All' || item.category === category.value) &&
      [item.title, item.category, item.prompt, ...(item.tags || [])]
        .join(' ').toLowerCase().includes(query));
    if (!matching.length) {
      gallery.append(make('p', 'editor-note', 'No matching ideas found.'));
      return;
    }
    for (const item of matching) {
      const card = make('article', 'library-card');
      const cat = make('small', 'mini', item.category.toUpperCase());
      const title = make('h3', '', item.title);
      const description = make('p', '', item.prompt);
      const footer = make('p', 'editor-note',
        'Illustrative model: ' + item.modelId.replaceAll('_', ' ') +
        ' · Actor roles: ' + item.actorSlots.length +
        ' · ' + item.provenance.creator + ' · ' + item.provenance.promptLicense +
        (item.provenance.attributionRequired
          ? ' · ' + item.provenance.attributionText
          : ''));
      const button = make('button', 'button tiny', 'Use this prompt');
      button.type = 'button';
      button.addEventListener('click', () => {
        selectedTemplate = item;
        get('scenePrompt').value = item.prompt;
        get('sceneModel').value = item.modelId;
        renderActorAssignments();
        status('sceneStatus', item.actorSlots.length
          ? 'Choose ' + item.actorSlots.length + ' saved Actor(s) for this scene.'
          : 'Prompt and model filled. Edit freely before saving.');
        get('studio').scrollIntoView({behavior: 'smooth', block: 'start'});
        get('scenePrompt').focus({preventScroll: true});
      });
      card.append(cat, title, description, footer, button);
      gallery.append(card);
    }
  }

  get('sceneModel')?.addEventListener('change', () => {
    const limit = modelLimits[get('sceneModel').value];
    if (selectedTemplate && selectedTemplate.actorSlots.length > limit) {
      status('sceneStatus', 'This model preview has too few Actor slots for that prompt.');
    } else {
      status('sceneStatus', 'Model preview selected. No AI request is sent.');
    }
  });

  async function loadCatalog() {
    if (!gallery) return;
    try {
      const response = await fetch('assets/inspiration.json',
        {cache: 'no-store', credentials:'same-origin'});
      if (!response.ok) throw new Error('Catalog unavailable');
      const body = await response.json();
      if (body.schemaVersion !== 1 || !Array.isArray(body.templates)) {
        throw new Error('Unsupported catalog format');
      }
      // Only explicitly approved editorial or licensed records become public.
      catalog = body.templates.filter((item) =>
        item.publicationStatus === 'approved' &&
        ['hotice_original', 'licensed'].includes(item.origin) &&
        typeof item.id === 'string' &&
        typeof item.prompt === 'string' &&
        item.prompt.length > 0 &&
        item.provenance &&
        typeof item.provenance.creator === 'string' &&
        typeof item.provenance.promptOrigin === 'string' &&
        typeof item.provenance.promptLicense === 'string' &&
        typeof item.provenance.licenseEvidence === 'string' &&
        typeof item.provenance.attributionRequired === 'boolean' &&
        (!item.provenance.attributionRequired ||
          typeof item.provenance.attributionText === 'string') &&
        typeof item.provenance.embedAllowed === 'boolean' &&
        typeof item.provenance.lastVerified === 'string' &&
        (!item.provenance.sourceUrl ||
          item.provenance.sourceUrl.startsWith('https://')) &&
        (item.previewUrl === null ||
          (item.origin === 'licensed' && item.provenance.embedAllowed &&
            typeof item.provenance.mediaLicense === 'string' &&
            Boolean(item.provenance.sourceUrl))) &&
        Object.hasOwn(modelLimits, item.modelId) &&
        Array.isArray(item.actorSlots));
      const categories = [...new Set(catalog.map((item) => item.category))];
      for (const name of categories) {
        const option = make('option', '', name);
        option.value = name;
        category.append(option);
      }
      libraryFilter();
    } catch (_) {
      status('libraryCards',
        'The inspiration catalog could not load. Open this site on an HTTPS web server, not directly from a local file.');
    }
  }
  if (search) {
    search.addEventListener('input', libraryFilter);
    category.addEventListener('change', libraryFilter);
    loadCatalog();
  }

  get('saveSceneDraft')?.addEventListener('click', () => {
    let prompt = get('scenePrompt').value.trim();
    const model = get('sceneModel').value;
    const actors = [...get('actorAssignments').querySelectorAll('select[data-role]')]
      .map((select) => select.value);
    if (!prompt) return status('sceneStatus', 'Describe your scene first.');
    if (actors.some((name) => !name)) {
      return status('sceneStatus', 'Choose a saved Actor for each template role.');
    }
    if (actors.length > modelLimits[model]) {
      return status('sceneStatus',
        'Selected model preview allows only ' + modelLimits[model] + ' actors.');
    }
    if (selectedTemplate && selectedTemplate.modelId !== model) {
      return status('sceneStatus', 'Choose the template model preview to continue.');
    }
    if (selectedTemplate && selectedTemplate.prompt === prompt) {
      selectedTemplate.actorSlots.forEach((role, index) => {
        prompt = prompt.replaceAll('{{' + role + '}}', actors[index]);
      });
    }
    if (/\{\{Actor\d+\}\}/.test(prompt)) {
      return status('sceneStatus', 'Choose a prompt template or remove unresolved Actor roles.');
    }
    sceneDrafts.unshift({
      prompt, model, actors, sourceId: selectedTemplate?.id || null,
      createdAt: new Date().toISOString(),
    });
    selectedTemplate = null;
    renderActorAssignments();
    status('sceneStatus', 'Saved in this browser session (' +
      sceneDrafts.length + ' ideas). No video was generated.');
  });

  renderActorAssignments();

  // Local media timeline: imports, selection, preview, trims and ordering.
  // Not a production render/export encoder.
  const video = get('previewVideo');
  const list = get('clipTimeline');
  const emptyStage = get('stageEmpty');
  const inspector = get('inspectorFields');
  const inspectorEmpty = get('inspectorEmpty');
  function currentClip() { return clips[activeClip] || null; }
  function resetVideo() {
    if (!video) return;
    video.pause();
    video.removeAttribute('src');
    video.load();
    video.classList.remove('has-video');
    emptyStage.hidden = false;
  }
  function selectClip(index) {
    if (!clips[index]) return;
    sequence = false;
    activeClip = index;
    resetVideo();
    const clip = currentClip();
    inspector.hidden = !clip.url;
    inspectorEmpty.hidden = !!clip.url;
    if (clip.url) {
      get('clipName').textContent = clip.name;
      get('trimStart').value = clip.start.toFixed(1);
      get('trimEnd').value = clip.end.toFixed(1);
      get('clipSpeed').value = String(clip.speed);
      video.src = clip.url;
      video.classList.add('has-video');
      emptyStage.hidden = true;
      video.addEventListener('loadedmetadata', function seekOnce() {
        video.removeEventListener('loadedmetadata', seekOnce);
        if (clips[activeClip] === clip) video.currentTime = clip.start;
      });
    } else {
      inspectorEmpty.hidden = false;
      inspectorEmpty.textContent = 'This is a scene placeholder; generate or import a video later.';
    }
    renderClips();
  }
  function renderClips() {
    if (!list) return;
    list.replaceChildren();
    if (!clips.length) {
      list.append(make('div', 'empty-timeline',
        'No clips yet · Imports stay on your device.'));
    }
    clips.forEach((clip, index) => {
      const box = make('div', 'clip' + (activeClip === index ? ' active' : ''));
      box.append(make('strong', '', clip.name));
      box.append(make('small', '', clip.url
        ? (clip.end - clip.start).toFixed(1) + ' seconds' : 'Scene placeholder'));
      const controls = make('div', 'clip-controls');
      const open = make('button', '', 'Select');
      open.addEventListener('click', () => selectClip(index));
      const earlier = make('button', '', '←');
      earlier.disabled = index === 0;
      earlier.setAttribute('aria-label', 'Move clip earlier');
      earlier.addEventListener('click', () => shift(index, -1));
      const later = make('button', '', '→');
      later.disabled = index === clips.length - 1;
      later.setAttribute('aria-label', 'Move clip later');
      later.addEventListener('click', () => shift(index, 1));
      controls.append(open, earlier, later);
      box.append(controls);
      list.append(box);
    });
  }
  function shift(from, distance) {
    const to = from + distance;
    if (to < 0 || to >= clips.length) return;
    const [clip] = clips.splice(from, 1);
    clips.splice(to, 0, clip);
    activeClip = to;
    renderClips();
  }
  const report = (message) => status('editorStatus', message);
  get('clipsInput')?.addEventListener('change', (event) => {
    const files = [...event.target.files];
    for (const file of files) {
      if (!file.type.startsWith('video/')) {
        report('Please choose a video file.');
        continue;
      }
      if (file.size > 300 * 1024 * 1024) {
        report('For this preview, choose clips below 300 MB.');
        continue;
      }
      const url = URL.createObjectURL(file);
      const clip = {id:++serial, name:file.name, url,
        start:0, end:0, duration:0, speed:1};
      clips.push(clip);
      // Probe duration without uploading the video anywhere.
      const probe = document.createElement('video');
      probe.preload = 'metadata';
      probe.src = url;
      probe.onloadedmetadata = () => {
        if (!clips.includes(clip)) return;
        clip.duration = Number.isFinite(probe.duration) ? probe.duration : 0;
        clip.end = clip.duration;
        if (currentClip() === clip) get('trimEnd').value = String(clip.end);
        renderClips();
        probe.removeAttribute('src');
        probe.load();
      };
      probe.onerror = () => report('This video codec could not be read in the browser.');
    }
    if (clips.length && activeClip === -1) selectClip(0);
    renderClips();
    event.target.value = '';
  });
  get('addSample')?.addEventListener('click', () => {
    clips.push({id:++serial, name:'Scene placeholder ' + serial,
      url:null, start:0, end:0, duration:0, speed:1});
    if (activeClip < 0) selectClip(0);
    renderClips();
  });
  get('applyTrim')?.addEventListener('click', () => {
    const clip = currentClip();
    if (!clip || !clip.url || !clip.duration) return report('Select a playable clip first.');
    const start = Number(get('trimStart').value);
    const end = Number(get('trimEnd').value);
    const speed = Number(get('clipSpeed').value);
    if (![start,end,speed].every(Number.isFinite) ||
        start < 0 || end > clip.duration || end <= start ||
        speed < 0.5 || speed > 2) {
      return report('Enter a valid start/end time within your clip.');
    }
    clip.start = start; clip.end = end; clip.speed = speed;
    video.playbackRate = speed;
    video.currentTime = start;
    renderClips();
    report('Preview trim updated. Export is not enabled in this version.');
  });
  get('deleteClip')?.addEventListener('click', () => {
    const clip = currentClip();
    if (!clip) return;
    if (clip.url) URL.revokeObjectURL(clip.url);
    clips.splice(activeClip,1);
    activeClip = -1;
    resetVideo();
    inspector.hidden = true;
    inspectorEmpty.hidden = false;
    if (clips.length) selectClip(0); else renderClips();
    report('Clip removed.');
  });
  get('clearTimeline')?.addEventListener('click', () => {
    for (const clip of clips) if (clip.url) URL.revokeObjectURL(clip.url);
    clips = []; activeClip = -1; sequence = false;
    resetVideo(); inspector.hidden = true; inspectorEmpty.hidden = false;
    renderClips(); report('Local timeline cleared.');
  });
  get('playSequence')?.addEventListener('click', async () => {
    const first = clips.findIndex((clip) => clip.url && clip.end > clip.start);
    if (first < 0) return report('Import at least one playable video.');
    selectClip(first);
    sequence = true;
    try {
      video.currentTime = clips[first].start;
      await video.play();
    } catch (_) {
      sequence = false;
      report('Playback was blocked or this codec is unsupported.');
    }
  });
  video?.addEventListener('timeupdate', async () => {
    const clip = currentClip();
    if (!clip || !clip.url || !clip.end) return;
    if (video.currentTime < clip.end - 0.05) return;
    video.pause();
    if (!sequence) return;
    const next = clips.findIndex((candidate, index) =>
      index > activeClip && candidate.url && candidate.end > candidate.start);
    if (next < 0) {
      sequence = false;
      report('Sequence preview finished.');
      return;
    }
    selectClip(next);
    sequence = true;
    try { await video.play(); } catch (_) { sequence = false; }
  });
  renderClips();

  // Browser sign-in uses the same HTTPS API and bearer sessions as native
  // clients. The token stays in memory only; it is never written to web storage.
  const accountForm = get('accountLogin');
  const registerForm = get('accountRegister');
  const resendForm = get('accountResend');
  const resetRequestForm = get('accountResetRequest');
  const resetCompleteForm = get('accountResetComplete');
  const accountEntryActions = get('accountEntryActions');
  const accountSignIn = get('accountSignIn');
  const accountSignedIn = get('accountSignedIn');
  const apiOriginMeta = document.querySelector('meta[name="hotice-api-origin"]');
  let accountToken = null;
  let accountApiOrigin = null;
  let accountCanWriteCloud = false;
  let accountCanReadCloud = false;
  try {
    const configured = (apiOriginMeta?.content || '').trim();
    const parsed = new URL(configured);
    const localPage = ['localhost', '127.0.0.1'].includes(window.location.hostname);
    const secureApiOrigin = parsed.protocol === 'https:' ||
      (parsed.protocol === 'http:' && localPage && ['localhost', '127.0.0.1'].includes(parsed.hostname));
    if (secureApiOrigin && parsed.origin === configured &&
        !parsed.username && !parsed.password && !parsed.search && !parsed.hash) {
      accountApiOrigin = parsed.origin;
    }
  } catch (_) {
    // Unconfigured or malformed origins fail closed. Do not send credentials.
  }

  if (!accountApiOrigin) {
    status('accountStatus',
      'Account sign-in is unavailable: configure the exact HTTPS HOTICE API origin (loopback HTTP is only for local development).');
    accountForm?.querySelectorAll('input, button').forEach((control) => {
      control.disabled = true;
    });
    for (const form of [registerForm, resendForm, resetRequestForm, resetCompleteForm]) {
      form?.querySelectorAll('input, button').forEach((control) => { control.disabled = true; });
    }
    get('showRegister').disabled = true;
    get('showPasswordReset').disabled = true;
  } else {
    status('accountStatus',
      'Secure account service configured. Sign in to verify your account; this preview does not sync project data.');
  }

  async function accountApi(path, {method = 'GET', token = null, body = null, extraHeaders = {}} = {}) {
    const headers = {Accept: 'application/json'};
    if (token) headers.Authorization = 'Bearer ' + token;
    if (body !== null) headers['Content-Type'] = 'application/json';
    Object.assign(headers, extraHeaders);
    const response = await fetch(accountApiOrigin + path, {
      method,
      mode: 'cors',
      credentials: 'omit',
      cache: 'no-store',
      redirect: 'error',
      headers,
      ...(body === null ? {} : {body: JSON.stringify(body)}),
    });
    let result = null;
    try { result = await response.json(); } catch (_) { /* Treat as an invalid API response. */ }
    if (!response.ok || !result || typeof result !== 'object') {
      const error = new Error('HOTICE account request failed.');
      error.status = response.status;
      throw error;
    }
    return result;
  }

  function selectAccountForm(mode) {
    accountForm.hidden = mode !== 'login';
    registerForm.hidden = mode !== 'register';
    resendForm.hidden = mode !== 'resend';
    resetRequestForm.hidden = mode !== 'reset-request';
    resetCompleteForm.hidden = mode !== 'reset-complete';
    accountEntryActions.hidden = mode !== 'login';
  }

  get('showRegister')?.addEventListener('click', () => selectAccountForm('register'));
  get('showPasswordReset')?.addEventListener('click', () => selectAccountForm('reset-request'));
  document.querySelectorAll('[data-account-view="login"]').forEach((button) =>
    button.addEventListener('click', () => selectAccountForm('login')));

  registerForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = get('registerEmail').value.trim();
    const password = get('registerPassword').value;
    const confirm = get('registerPasswordConfirm').value;
    const submit = get('accountCreate');
    if (password !== confirm) return status('accountStatus', 'Those passwords do not match.');
    const passwordBytes = new TextEncoder().encode(password).length;
    if (passwordBytes < 12 || passwordBytes > 256) return status('accountStatus', 'Use a password between 12 and 256 bytes.');
    submit.disabled = true;
    status('accountStatus', 'Creating your account and sending a verification link…');
    try {
      await accountApi('/v1/auth/register', {method: 'POST', body: {email, password}});
      get('registerPassword').value = '';
      get('registerPasswordConfirm').value = '';
      get('resendEmail').value = email;
      selectAccountForm('resend');
      status('accountStatus', 'If registration is available, a verification link will be sent. Verify your email before signing in.');
    } catch (error) {
      status('accountStatus', error.status === 403
        ? 'Account creation is not enabled on this HOTICE service yet.'
        : error.status === 429
          ? 'Too many account requests. Try again later.'
          : 'The account service could not complete registration. Try again later.');
    } finally { submit.disabled = false; }
  });

  resendForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = get('resendEmail').value.trim();
    const submit = resendForm.querySelector('button[type="submit"]');
    submit.disabled = true;
    try {
      await accountApi('/v1/auth/verification/resend', {method: 'POST', body: {email}});
      status('accountStatus', 'If this account needs verification, a fresh link will be sent.');
    } catch (error) {
      status('accountStatus', error.status === 429 ? 'Too many requests. Try again later.' : 'The account service could not process that request. Try again later.');
    } finally { submit.disabled = false; }
  });

  resetRequestForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const email = get('resetRequestEmail').value.trim();
    const submit = resetRequestForm.querySelector('button[type="submit"]');
    submit.disabled = true;
    try {
      await accountApi('/v1/auth/password-reset/request', {method: 'POST', body: {email}});
      status('accountStatus', 'If an eligible account exists, a password reset link will be sent.');
    } catch (error) {
      status('accountStatus', error.status === 429 ? 'Too many requests. Try again later.' : 'The account service could not process that request.');
    } finally { submit.disabled = false; }
  });

  let resetToken = null;
  resetCompleteForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const password = get('resetNewPassword').value;
    const confirm = get('resetConfirmPassword').value;
    if (password !== confirm) return status('accountStatus', 'Those passwords do not match.');
    const passwordBytes = new TextEncoder().encode(password).length;
    if (passwordBytes < 12 || passwordBytes > 256) return status('accountStatus', 'Use a password between 12 and 256 bytes.');
    const submit = resetCompleteForm.querySelector('button[type="submit"]');
    submit.disabled = true;
    try {
      await accountApi('/v1/auth/password-reset/complete', {method: 'POST', body: {token: resetToken, password}});
      resetToken = null;
      get('resetNewPassword').value = '';
      get('resetConfirmPassword').value = '';
      selectAccountForm('login');
      status('accountStatus', 'Password updated and existing sessions revoked. Sign in with your new password.');
    } catch (_) {
      status('accountStatus', 'The password reset link is invalid or expired. Request a new link.');
    } finally { submit.disabled = false; }
  });

  // Remove one-time credentials from the address bar before sending them to the API.
  const incomingUrl = new URL(window.location.href);
  const incomingFragment = new URLSearchParams(incomingUrl.hash.replace(/^#/, ''));
  const verificationToken = incomingFragment.get('token') || incomingUrl.searchParams.get('token');
  const incomingResetToken = incomingFragment.get('reset') || incomingUrl.searchParams.get('reset');
  if (verificationToken || incomingResetToken) {
    incomingUrl.searchParams.delete('token');
    incomingUrl.searchParams.delete('reset');
    incomingFragment.delete('token');
    incomingFragment.delete('reset');
    const safeFragment = incomingFragment.toString();
    window.history.replaceState({}, '', incomingUrl.pathname + incomingUrl.search + (safeFragment ? '#' + safeFragment : ''));
    if (incomingResetToken && /^[a-f0-9]{64}$/i.test(incomingResetToken) && accountApiOrigin) {
      resetToken = incomingResetToken;
      selectAccountForm('reset-complete');
      status('accountStatus', 'Choose a new password. This one-time link expires in 30 minutes.');
    } else if (verificationToken && /^[a-f0-9]{64}$/i.test(verificationToken) && accountApiOrigin) {
      status('accountStatus', 'Verifying your email address…');
      accountApi('/v1/auth/verify-email', {method: 'POST', body: {token: verificationToken}})
        .then(() => { selectAccountForm('login'); status('accountStatus', 'Email verified. You can now sign in securely.'); })
        .catch(() => { selectAccountForm('resend'); status('accountStatus', 'This verification link is invalid or expired. Request a fresh link.'); });
    } else {
      selectAccountForm(incomingResetToken ? 'reset-request' : 'resend');
      status('accountStatus', incomingResetToken
        ? 'This password reset link is invalid or the account service is not configured.'
        : 'This verification link is invalid or the account service is not configured.');
    }
  }

  // Browser projects are persisted in IndexedDB on this device. Cloud writes
  // are separate, explicit actions and include project text only, never media.
  const projectDbName = 'hotice.browser-projects.v1';
  const projectConsent = get('cloudSyncConsent');
  let selectedProjectId = null;
  let localProjectCache = [];
  let cloudProjectCache = [];
  let mockGenerationEnabled = false;
  let currentMockQuote = null;

  function projectStatus(message) { status('projectStatus', message); }
  function cloudProjectStatus(message) { status('cloudProjectStatus', message); }

  function mockJobStatus(message) { status('mockGenerationStatus', message); }

  function refreshMockControls() {
    const available = Boolean(accountToken && mockGenerationEnabled);
    for (const id of ['quoteMockJob', 'refreshMockJobs']) {
      const control = get(id);
      if (control) control.disabled = !available;
    }
    const submit = get('submitMockJob');
    if (submit) submit.disabled = !available || !currentMockQuote;
    if (!accountToken) mockJobStatus('Sign in and use an API server with mock generation enabled. No request is sent until you choose an action.');
    else if (!mockGenerationEnabled) mockJobStatus('Mock generation is disabled on this server. Your scene stays on this device.');
  }

  async function quoteMockJob() {
    if (!accountToken || !mockGenerationEnabled) return;
    currentMockQuote = null;
    refreshMockControls();
    const prompt = get('scenePrompt')?.value.trim() || '';
    if (!prompt) return mockJobStatus('Write a scene prompt before requesting a quote.');
    mockJobStatus('Requesting a simulated-credit quote for this prompt…');
    try {
      const response = await accountApi('/v1/jobs/quote', {method: 'POST', token: accountToken,
        body: {request: {modelId: 'hotice.mock.video.v1', prompt}}});
      if (typeof response.quoteToken !== 'string' || !Number.isInteger(response.credits) ||
          response.modelId !== 'hotice.mock.video.v1') throw new Error('Invalid mock quote.');
      currentMockQuote = {token: response.quoteToken, prompt, credits: response.credits};
      refreshMockControls();
      mockJobStatus('Mock dry run quote: ' + response.credits + ' simulated credits. No money is charged. Quote expires ' + response.expiresAt + '.');
    } catch (error) {
      currentMockQuote = null;
      refreshMockControls();
      mockJobStatus(error.status === 503 ? 'Mock generation is disabled on this server.' :
        'Could not get a simulated-credit quote. Check the server and try again.');
    }
  }

  async function submitMockJob() {
    if (!accountToken || !mockGenerationEnabled || !currentMockQuote) return;
    const quote = currentMockQuote;
    const prompt = get('scenePrompt')?.value.trim() || '';
    if (prompt !== quote.prompt) {
      currentMockQuote = null;
      refreshMockControls();
      return mockJobStatus('The prompt changed. Check a new quote before submitting.');
    }
    if (!window.confirm('Start a mock dry run for ' + quote.credits + ' simulated credits? No video is generated and no money is charged.')) return;
    currentMockQuote = null;
    refreshMockControls();
    const submit = get('submitMockJob');
    if (submit) submit.disabled = true;
    mockJobStatus('Submitting the mock dry run…');
    try {
      const response = await accountApi('/v1/jobs', {method: 'POST', token: accountToken,
        extraHeaders: {'Idempotency-Key': 'web-' + crypto.randomUUID()},
        body: {quoteToken: quote.token, request: {modelId: 'hotice.mock.video.v1', prompt}}});
      if (!response.job || typeof response.job.id !== 'string' || typeof response.job.status !== 'string') {
        throw new Error('Invalid mock job response.');
      }
      mockJobStatus('Mock job ' + response.job.status + '. This staging workflow does not produce video. Use Refresh my jobs to check its latest state.');
      await renderMockJobs([response.job]);
    } catch (error) {
      mockJobStatus(error.status === 402 ? 'Not enough simulated credits for this mock job.' :
        'The server could not confirm job submission. Refresh your jobs before trying again.');
    } finally {
      refreshMockControls();
    }
  }

  async function renderMockJobs(jobs) {
    const root = get('mockJobs');
    if (!root) return;
    root.replaceChildren();
    if (!jobs.length) return root.append(make('p', 'editor-note', 'No mock jobs found.'));
    for (const job of jobs) {
      const row = make('article', 'mock-job');
      const title = make('strong', '', 'Mock job · ' + job.status);
      const meta = make('small', '', 'ID ' + job.id + ' · simulated credits reserved: ' + job.reservedCredits);
      row.append(title, meta);
      if (job.result) row.append(make('p', 'editor-note', 'Mock adapter result recorded. No media was created.'));
      if (job.errorCode === 'provider_outcome_unknown') row.append(make('p', 'editor-note', 'Provider outcome is unknown; credits remain reserved pending reconciliation.'));
      root.append(row);
    }
  }

  async function refreshMockJobs() {
    if (!accountToken || !mockGenerationEnabled) return;
    mockJobStatus('Loading your mock job status…');
    try {
      const response = await accountApi('/v1/jobs', {token: accountToken});
      if (!Array.isArray(response.jobs)) throw new Error('Invalid jobs response.');
      await renderMockJobs(response.jobs);
      mockJobStatus('Job list refreshed. Results are mock metadata only; no video was created.');
    } catch (_) {
      mockJobStatus('Could not load mock job status. Your local scene remains available.');
    }
  }

  get('quoteMockJob')?.addEventListener('click', quoteMockJob);
  get('submitMockJob')?.addEventListener('click', submitMockJob);
  get('refreshMockJobs')?.addEventListener('click', refreshMockJobs);
  get('scenePrompt')?.addEventListener('input', () => {
    if (currentMockQuote && get('scenePrompt').value.trim() !== currentMockQuote.prompt) {
      currentMockQuote = null;
      refreshMockControls();
      mockJobStatus('Prompt changed. Check a new quote before submitting.');
    }
  });

  function openProjectDb() {
    return new Promise((resolve, reject) => {
      if (!('indexedDB' in window)) return reject(new Error('IndexedDB is unavailable.'));
      const request = indexedDB.open(projectDbName, 1);
      request.onupgradeneeded = () => {
        if (!request.result.objectStoreNames.contains('projects')) {
          request.result.createObjectStore('projects', {keyPath: 'id'});
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error('Local project storage failed.'));
      request.onblocked = () => reject(new Error('Local project storage is busy in another tab.'));
    });
  }

  async function projectStore(mode, method, value = null) {
    const db = await openProjectDb();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('projects', mode);
      const store = transaction.objectStore('projects');
      const request = method === 'all' ? store.getAll()
        : method === 'get' ? store.get(value)
          : method === 'put' ? store.put(value) : store.delete(value);
      let result;
      request.onsuccess = () => { result = request.result; };
      transaction.oncomplete = () => { db.close(); resolve(result); };
      transaction.onerror = () => { db.close(); reject(transaction.error || request.error); };
      transaction.onabort = () => { db.close(); reject(transaction.error || new Error('Local project update was cancelled.')); };
    });
  }

  function makeProjectId() {
    if (crypto.randomUUID) return crypto.randomUUID();
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
    return hex.slice(0, 8) + '-' + hex.slice(8, 12) + '-' + hex.slice(12, 16) + '-' +
      hex.slice(16, 20) + '-' + hex.slice(20);
  }

  function safeProjectDocument(document) {
    if (!document || typeof document !== 'object' || Array.isArray(document)) {
      throw new Error('Project data could not be read.');
    }
    let encoded;
    let clone;
    try {
      encoded = JSON.stringify(document);
      if (!encoded || new Blob([encoded]).size > 110000) {
        throw new Error('Project is too large for this browser sync flow.');
      }
      clone = JSON.parse(encoded);
    } catch (error) {
      throw new Error(error.message || 'Project data is not valid JSON.');
    }
    const inspect = (value, key = '') => {
      if (/(?:file|media|image|photo|video|audio).*(?:path|uri|url|data|bytes|base64)|(?:base64|bytes|rawdata)$/i.test(key)) {
        return true;
      }
      if (typeof value === 'string') {
        const text = value.trim();
        return /^(?:data:(?:image|video|audio)\/|blob:|file:|filesystem:)/i.test(text) ||
          /^[A-Za-z]:\\/.test(text) || /^\/(?:tmp|home|Users|private|var)\//.test(text);
      }
      if (Array.isArray(value)) return value.some((item) => inspect(item));
      if (value && typeof value === 'object') {
        return Object.entries(value).some(([name, item]) => inspect(item, name));
      }
      return false;
    };
    if (inspect(clone)) throw new Error('Inline media is not included in browser project sync.');
    return clone;
  }

  function editorScenes(document) {
    return Array.isArray(document?.scenes) ? document.scenes.filter((scene) =>
      scene && typeof scene === 'object' && typeof scene.prompt === 'string' &&
      typeof scene.model === 'string' && scene.prompt.length <= 30000)
      .slice(0, 100) : [];
  }

  function editorActors(document) {
    return Array.isArray(document?.actors) ? document.actors
      .filter((name) => typeof name === 'string' && name.trim() && name.trim().length <= 60)
      .slice(0, 100) : [];
  }

  async function refreshLocalProjects() {
    const root = get('localProjects');
    if (!root) return;
    try {
      localProjectCache = (await projectStore('readonly', 'all'))
        .filter((item) => item && typeof item.id === 'string' && typeof item.title === 'string')
        .sort((a, b) => String(b.updatedAt || '').localeCompare(String(a.updatedAt || '')));
      root.replaceChildren();
      if (!localProjectCache.length) {
        root.append(make('p', 'editor-note', 'No saved projects on this device yet.'));
        return;
      }
      for (const project of localProjectCache) {
        const card = make('article', 'project-card');
        const heading = make('strong', '', project.title);
        const detail = make('small', 'editor-note',
          (Array.isArray(project.document?.scenes) ? project.document.scenes.length : 0) +
          ' saved scene ideas · ' + (project.cloudId ? 'linked to a cloud copy' : 'device only'));
        const actions = make('div', 'project-actions');
        const open = make('button', 'tool', 'Open');
        open.type = 'button';
        open.addEventListener('click', () => openLocalProject(project.id));
        const sync = make('button', 'tool', project.cloudId ? 'Sync updates' : 'Sync to cloud');
        sync.type = 'button';
        sync.disabled = !cloudActionAllowed(true);
        sync.addEventListener('click', () => syncLocalProject(project.id));
        const remove = make('button', 'tool', 'Delete on this device');
        remove.type = 'button';
        remove.addEventListener('click', () => deleteLocalProject(project.id));
        actions.append(open, sync, remove);
        if (project.cloudConflict) {
          const copy = make('button', 'tool', 'Upload as separate cloud copy');
          copy.type = 'button';
          copy.disabled = !cloudActionAllowed(true);
          copy.addEventListener('click', () => syncLocalProject(project.id, {asNewCopy: true}));
          actions.append(copy);
        }
        card.append(heading, detail, actions);
        root.append(card);
      }
    } catch (_) {
      root.replaceChildren(make('p', 'editor-note',
        'This browser could not open local project storage. Your current scene remains available in this page.'));
    }
  }

  async function openLocalProject(id) {
    try {
      const project = await projectStore('readonly', 'get', id);
      if (!project) throw new Error('Project not found on this device.');
      selectedProjectId = project.id;
      get('projectTitle').value = project.title;
      const document = safeProjectDocument(project.document);
      sceneDrafts = editorScenes(document);
      actorNames = editorActors(document);
      saveActorNames();
      renderActors();
      renderActorAssignments();
      if (sceneDrafts[0]) {
        get('scenePrompt').value = sceneDrafts[0].prompt;
        if (Object.hasOwn(modelLimits, sceneDrafts[0].model)) get('sceneModel').value = sceneDrafts[0].model;
      }
      projectStatus('Opened locally. Changes remain on this device until you save again.');
    } catch (error) {
      projectStatus(error.message || 'Could not open this local project.');
    }
  }

  async function saveLocalProject() {
    const title = get('projectTitle').value.trim();
    if (!title || title.length > 120) return projectStatus('Enter a project name of 1–120 characters.');
    try {
      const existing = selectedProjectId ? await projectStore('readonly', 'get', selectedProjectId) : null;
      const document = safeProjectDocument({
        ...(existing?.document || {}), version: 1, scenes: sceneDrafts, actors: actorNames,
      });
      if (!document.scenes.length) return projectStatus('Save at least one scene idea before saving this project.');
      const project = {
        ...(existing || {}), id: existing?.id || makeProjectId(), title,
        document, updatedAt: new Date().toISOString(),
      };
      await projectStore('readwrite', 'put', project);
      selectedProjectId = project.id;
      await refreshLocalProjects();
      projectStatus('Project saved on this device. Cloud sync remains off until you consent and choose Sync.');
    } catch (error) {
      projectStatus(error.message || 'Could not save this project on this device.');
    }
  }

  async function deleteLocalProject(id) {
    const project = localProjectCache.find((item) => item.id === id);
    if (!project || !window.confirm('Delete “' + project.title + '” from this device? Its cloud copy will not be deleted.')) return;
    try {
      await projectStore('readwrite', 'delete', id);
      if (selectedProjectId === id) selectedProjectId = null;
      await refreshLocalProjects();
      projectStatus('Local project deleted. Any cloud copy remains in your HOTICE account.');
    } catch (_) {
      projectStatus('Could not delete this local project.');
    }
  }

  function cloudActionAllowed(write) {
    return Boolean(accountToken && projectConsent?.checked &&
      (write ? accountCanWriteCloud : accountCanReadCloud));
  }

  function refreshCloudControls() {
    const canRead = cloudActionAllowed(false);
    const canWrite = cloudActionAllowed(true);
    const load = get('loadCloudProjects');
    if (load) load.disabled = !canRead;
    get('localProjects')?.querySelectorAll('button').forEach((button) => {
      if (button.textContent === 'Sync to cloud' || button.textContent === 'Sync updates' ||
          button.textContent === 'Upload as separate cloud copy') button.disabled = !canWrite;
    });
    if (!accountToken) cloudProjectStatus('Sign in and confirm consent to load or sync cloud projects.');
    else if (!projectConsent?.checked) cloudProjectStatus('Check the consent box before loading or syncing project data.');
    else if (!accountCanReadCloud) cloudProjectStatus('This account has no readable cloud entitlement. Local projects remain available.');
    else if (!accountCanWriteCloud) cloudProjectStatus('Cloud projects are read-only for this account. You can load copies but cannot sync changes.');
    else cloudProjectStatus('Cloud sync is available. Choose a specific project action; no background sync runs.');
  }

  async function syncLocalProject(id, {asNewCopy = false} = {}) {
    if (!cloudActionAllowed(true)) return cloudProjectStatus('Sign in, confirm consent and check that cloud access is active.');
    let project = localProjectCache.find((item) => item.id === id);
    if (!project) return cloudProjectStatus('Save this project on the device before syncing it.');
    try {
      project = {...project, document: safeProjectDocument(project.document)};
      if (asNewCopy) {
        project.id = makeProjectId();
        project.cloudId = null;
        project.cloudRevision = null;
        project.cloudConflict = false;
        project.title = project.title.slice(0, 110) + ' (copy)';
        await projectStore('readwrite', 'put', project);
        selectedProjectId = project.id;
      }
      const cloudId = project.cloudId || project.id;
      const expectedRevision = Number.isInteger(project.cloudRevision) ? project.cloudRevision : 0;
      const body = {title: project.title, expectedRevision, document: project.document};
      if (new Blob([JSON.stringify(body)]).size > 120000) {
        return cloudProjectStatus('Project is larger than the server limit. Shorten prompts before syncing.');
      }
      const response = await accountApi('/v1/projects/' + encodeURIComponent(cloudId), {
        method: 'PUT', token: accountToken, body,
      });
      if (!Number.isInteger(response.revision) || typeof response.id !== 'string') {
        throw new Error('The HOTICE server returned an invalid project revision.');
      }
      project.cloudId = cloudId;
      project.cloudRevision = response.revision;
      project.cloudConflict = false;
      project.updatedAt = new Date().toISOString();
      await projectStore('readwrite', 'put', project);
      await refreshLocalProjects();
      cloudProjectStatus('Cloud copy saved at revision ' + response.revision + '. Your local copy remains available on this device.');
    } catch (error) {
      if (error.status === 409) {
        project.cloudConflict = true;
        await projectStore('readwrite', 'put', project).catch(() => {});
        await refreshLocalProjects();
        cloudProjectStatus('The cloud copy changed elsewhere. Your local project was kept; use “Upload as separate cloud copy” to preserve both versions.');
      } else if (error.status === 403) {
        cloudProjectStatus('Cloud writing is unavailable or the entitlement expired. Your local project is unchanged.');
      } else if (error.status === 413 || error.status === 422) {
        cloudProjectStatus('The server rejected this project size or format. Your local project is unchanged.');
      } else if (error.message === 'Inline media is not included in browser project sync.' ||
          error.message === 'Project is too large for this browser sync flow.') {
        cloudProjectStatus(error.message);
      } else {
        cloudProjectStatus('Cloud sync could not be confirmed. Your local project remains on this device; check the cloud list before retrying.');
      }
    }
  }

  async function loadCloudProjectList() {
    if (!cloudActionAllowed(false)) return cloudProjectStatus('Sign in, confirm consent and check cloud access before loading projects.');
    const root = get('cloudProjects');
    root.replaceChildren(make('p', 'editor-note', 'Loading your HOTICE cloud project list…'));
    try {
      const response = await accountApi('/v1/projects', {token: accountToken});
      cloudProjectCache = Array.isArray(response.projects) ? response.projects : [];
      root.replaceChildren();
      if (!cloudProjectCache.length) root.append(make('p', 'editor-note', 'No cloud projects are saved to this account yet.'));
      for (const remote of cloudProjectCache) {
        if (!remote || typeof remote.id !== 'string' || typeof remote.title !== 'string') continue;
        const linked = localProjectCache.find((item) => item.cloudId === remote.id);
        const card = make('article', 'project-card');
        card.append(make('strong', '', remote.title));
        card.append(make('small', 'editor-note', 'Cloud revision ' + Number(remote.revision || 0) + ' · project data only'));
        const action = make('button', 'tool', linked ? 'Open saved local copy' : 'Save cloud copy on this device');
        action.type = 'button';
        action.addEventListener('click', () => linked
          ? openLocalProject(linked.id)
          : downloadCloudProject(remote.id));
        card.append(action);
        root.append(card);
      }
      cloudProjectStatus('Cloud project list loaded. Media and Actor photos were not downloaded.');
    } catch (error) {
      cloudProjectStatus(error.status === 403
        ? 'Cloud project list is not available for this account.'
        : 'Could not load the cloud project list. Local projects are unchanged.');
    }
  }

  async function downloadCloudProject(id) {
    if (!cloudActionAllowed(false)) return cloudProjectStatus('Confirm consent before downloading cloud project data.');
    try {
      const response = await accountApi('/v1/projects/' + encodeURIComponent(id), {token: accountToken});
      const remote = response.project;
      if (!remote || remote.id !== id || !Number.isInteger(remote.revision)) {
        throw new Error('Invalid cloud project response.');
      }
      if (localProjectCache.some((item) => item.cloudId === id)) {
        return cloudProjectStatus('A local copy of this cloud project already exists. Open it from the device list.');
      }
      const project = {
        id: makeProjectId(), cloudId: remote.id, cloudRevision: remote.revision,
        title: String(remote.title || 'Untitled project').slice(0, 120),
        document: safeProjectDocument(remote.document), updatedAt: new Date().toISOString(),
      };
      await projectStore('readwrite', 'put', project);
      await refreshLocalProjects();
      cloudProjectStatus('Cloud project copied to this device. Media and Actor photos were not downloaded.');
    } catch (_) {
      cloudProjectStatus('Could not save this cloud project to the device. Existing local projects were kept.');
    }
  }

  get('saveLocalProject')?.addEventListener('click', saveLocalProject);
  projectConsent?.addEventListener('change', () => {
    refreshCloudControls();
    refreshLocalProjects();
  });
  get('loadCloudProjects')?.addEventListener('click', loadCloudProjectList);
  refreshLocalProjects();
  refreshCloudControls();

  function showAccountForm(message) {
    accountToken = null;
    mockGenerationEnabled = false;
    currentMockQuote = null;
    accountSignedIn.hidden = true;
    selectAccountForm('login');
    status('accountStatus', message);
    get('mockJobs')?.replaceChildren();
    refreshMockControls();
  }

  accountForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!accountApiOrigin || !accountSignIn || accountSignIn.disabled) return;
    const emailField = get('accountEmail');
    const passwordField = get('accountPassword');
    const email = emailField.value.trim();
    const password = passwordField.value;
    accountSignIn.disabled = true;
    status('accountStatus', 'Signing in and verifying your server session…');
    let issuedToken = null;
    try {
      const login = await accountApi('/v1/auth/login', {
        method: 'POST', body: {email, password},
      });
      issuedToken = login.accessToken;
      if (typeof issuedToken !== 'string' || !/^[a-f0-9]{64}$/i.test(issuedToken)) {
        throw new Error('Invalid HOTICE session response.');
      }
      const profile = await accountApi('/v1/me', {token: issuedToken});
      const returnedEmail = profile.user?.email;
      if (typeof returnedEmail !== 'string' ||
          returnedEmail.toLowerCase() !== email.toLowerCase()) {
        throw new Error('HOTICE account identity could not be verified.');
      }
      accountToken = issuedToken;
      accountCanWriteCloud = profile.cloud?.active === true;
      accountCanReadCloud = profile.cloud?.readable === true;
      mockGenerationEnabled = profile.mockGeneration?.enabled === true;
      get('accountIdentity').textContent = returnedEmail;
      get('accountCloudStatus').textContent = accountCanWriteCloud
        ? 'Cloud access is active. Project sync still requires your consent and a project-specific action.'
        : accountCanReadCloud
          ? 'Cloud projects are readable, but this account cannot currently upload changes.'
          : 'Cloud access is inactive. Device-only projects remain available.';
      accountForm.hidden = true;
      accountSignedIn.hidden = false;
      status('accountStatus', 'Signed in and verified with the HOTICE server.');
      refreshCloudControls();
      refreshMockControls();
      await refreshLocalProjects();
    } catch (error) {
      if (issuedToken && accountApiOrigin) {
        accountApi('/v1/auth/logout', {method: 'POST', token: issuedToken}).catch(() => {});
      }
      accountToken = null;
      status('accountStatus', error.status === 401
        ? 'Sign-in was not accepted. Check the email and password.'
        : error.status === 403
          ? 'Verify your email and use an enabled HOTICE website origin before signing in.'
          : 'The account service could not be reached or verified. Try again later.');
    } finally {
      passwordField.value = '';
      accountSignIn.disabled = false;
    }
  });

  get('accountSignOut')?.addEventListener('click', async () => {
    const token = accountToken;
    accountToken = null;
    mockGenerationEnabled = false;
    currentMockQuote = null;
    accountCanWriteCloud = false;
    accountCanReadCloud = false;
    accountSignedIn.hidden = true;
    selectAccountForm('login');
    if (projectConsent) projectConsent.checked = false;
    cloudProjectCache = [];
    get('cloudProjects')?.replaceChildren();
    get('mockJobs')?.replaceChildren();
    refreshCloudControls();
    refreshMockControls();
    refreshLocalProjects();
    status('accountStatus', 'Signing out and revoking this server session…');
    try {
      if (token) await accountApi('/v1/auth/logout', {method: 'POST', token});
      status('accountStatus', 'Signed out. The server session was revoked.');
    } catch (_) {
      status('accountStatus',
        'Signed out in this browser, but server revocation could not be confirmed. The session may remain valid until it expires.');
    }
  });

  window.addEventListener('pagehide', () => {
    const token = accountToken;
    accountToken = null;
    mockGenerationEnabled = false;
    currentMockQuote = null;
    accountCanWriteCloud = false;
    accountCanReadCloud = false;
    if (projectConsent) projectConsent.checked = false;
    accountSignedIn.hidden = true;
    selectAccountForm('login');
    cloudProjectCache = [];
    get('cloudProjects')?.replaceChildren();
    get('mockJobs')?.replaceChildren();
    refreshCloudControls();
    refreshMockControls();
    if (token && accountApiOrigin) {
      fetch(accountApiOrigin + '/v1/auth/logout', {
        method: 'POST', mode: 'cors', credentials: 'omit', cache: 'no-store',
        redirect: 'error', keepalive: true,
        headers: {Authorization: 'Bearer ' + token},
      }).catch(() => {});
    }
  });
})();


