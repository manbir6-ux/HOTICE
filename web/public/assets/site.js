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

  function make(tag, className, label) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (label !== undefined) node.textContent = label;
    return node;
  }

  const search = get('librarySearch');
  const category = get('libraryCategory');
  const gallery = get('libraryCards');
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
        ' · Actor roles: ' + item.actorSlots.length);
      const button = make('button', 'button tiny', 'Use this prompt');
      button.type = 'button';
      button.addEventListener('click', () => {
        selectedTemplate = item;
        get('scenePrompt').value = item.prompt;
        get('sceneModel').value = item.modelId;
        get('sceneActors').value = '';
        status('sceneStatus', item.actorSlots.length
          ? 'Add ' + item.actorSlots.length + ' scene actor name(s) to replace template roles.'
          : 'Prompt and model filled. Edit freely before saving.');
        get('studio').scrollIntoView({behavior: 'smooth', block: 'start'});
        get('scenePrompt').focus({preventScroll: true});
      });
      card.append(cat, title, description, footer, button);
      gallery.append(card);
    }
  }

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
    const actors = get('sceneActors').value.split(',').map((x) => x.trim())
      .filter(Boolean);
    const unique = new Set(actors.map((name) => name.toLowerCase()));
    if (!prompt) return status('sceneStatus', 'Describe your scene first.');
    if (unique.size !== actors.length) {
      return status('sceneStatus', 'Actor names must be unique.');
    }
    if (actors.length > modelLimits[model]) {
      return status('sceneStatus',
        'Selected model preview allows only ' + modelLimits[model] + ' actors.');
    }
    const matches = [...prompt.matchAll(/\{\{Actor(\d+)\}\}/g)];
    const required = Math.max(0, ...matches.map((m) => Number(m[1])));
    if (required > actors.length || required > modelLimits[model]) {
      return status('sceneStatus',
        'Add ' + required + ' actor name(s) or remove unused actor placeholders.');
    }
    prompt = prompt.replace(/\{\{Actor(\d+)\}\}/g,
      (_, number) => actors[Number(number) - 1]);
    sceneDrafts.unshift({
      prompt, model, actors, sourceId: selectedTemplate?.id || null,
      createdAt: new Date().toISOString(),
    });
    selectedTemplate = null;
    status('sceneStatus', 'Saved in this browser session (' +
      sceneDrafts.length + ' ideas). No video was generated.');
  });

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
