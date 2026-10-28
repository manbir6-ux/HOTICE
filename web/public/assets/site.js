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
})();
