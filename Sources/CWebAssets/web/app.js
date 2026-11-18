// The web config editor. The draft lives in the daemon; this page shows it, sends edits, and follows
// server-sent events. Config strings go into the DOM only as text and attribute values, never as HTML.

import { record, heldText } from './keys.js';
import { showPairing } from './pairing.js';
import { openPicker, loadSymbols, isKnownSymbol } from './picker.js';

const KEY_COUNT = 15;
const DEBOUNCE_MS = 300;
const MEDIA = ['playpause', 'next', 'previous', 'volumeup', 'volumedown', 'mute', 'brightnessup', 'brightnessdown'];
const ACTIONS = [['', 'None'], ['run', 'Run command'], ['open', 'Open'], ['keys', 'Keystroke'], ['media', 'Media key'], ['page', 'Page']];
const ICON_KINDS = [['none', 'None'], ['material', 'Material Symbol'], ['sf', 'SF Symbol'], ['file', 'Image file']];

const $ = (id) => document.getElementById(id);

// Builds an element. `props` sets properties (text, className, onclick, …); children are nodes or strings.
function h(tag, props = {}, ...children) {
  const element = document.createElement(tag);
  for (const [name, value] of Object.entries(props)) {
    if (value === undefined || value === null) continue;
    if (name === 'text') element.textContent = value;
    else if (name.startsWith('aria-') || name === 'role' || name === 'for') element.setAttribute(name, value);
    else element[name] = value;
  }
  element.append(...children.flat().filter((child) => child !== null && child !== undefined && child !== false));
  return element;
}

// A stable ID for this tab, kept across reloads so the deck stays with it.
const tab = (() => {
  try {
    let id = sessionStorage.getItem('streamdeck-tab');
    if (!id) {
      id = crypto.randomUUID?.() ?? String(Math.random()).slice(2);
      sessionStorage.setItem('streamdeck-tab', id);
    }
    return id;
  } catch {
    return String(Math.random()).slice(2);
  }
})();

let state = null;
const images = {};
let selectedPage = null;
let selectedKey = null;
let showSettings = false;
let events = null;
let connectionLost = false;
let lastError = null;

// MARK: - API

class Unpaired extends Error {}

async function api(method, path, body) {
  const options = { method, headers: {} };
  if (method !== 'GET') {
    options.headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body ?? {});
  }
  const response = await fetch(path, options);
  if (response.status === 401) {
    unpaired();
    throw new Unpaired();
  }
  let data = null;
  try { data = await response.json(); } catch { /* no body */ }
  return { status: response.status, ok: response.ok, data };
}

// Sends a change; a full state comes back and is applied. Other answers go to `handle`.
async function change(method, path, body, handle) {
  try {
    const result = await api(method, path, body);
    if (result.ok && result.data && 'revision' in result.data) applyState(result.data);
    else if (!result.ok) {
      if (handle && handle(result)) return result;
      showError(result.data?.error ? `${result.status}: ${result.data.error}` : `Request failed (${result.status})`);
    }
    return result;
  } catch (error) {
    if (!(error instanceof Unpaired)) showError(`Cannot reach the daemon: ${error.message}`);
    return { ok: false };
  }
}

function showError(message) {
  lastError = message;
  renderBanners();
}

function unpaired() {
  events?.close();
  events = null;
  $('editor').hidden = true;
  $('loading').hidden = true;
  showPairing(start);
}

// MARK: - Start and events

async function start() {
  let result;
  try {
    result = await api('GET', '/api/state');
  } catch (error) {
    if (!(error instanceof Unpaired)) $('loading').textContent = `Cannot reach the daemon: ${error.message}`;
    return;
  }
  $('loading').hidden = true;
  $('editor').hidden = false;
  buildGrid();
  applyState(result.data);
  loadSymbols().then(() => render()).catch(() => {});
  connect();
}

function connect() {
  events?.close();
  events = new EventSource(`/api/events?tab=${encodeURIComponent(tab)}`);
  events.addEventListener('open', () => {
    if (connectionLost) {
      connectionLost = false;
      renderBanners();
    }
    reportPresence();
  });
  events.addEventListener('state', (event) => applyState(JSON.parse(event.data)));
  events.addEventListener('key', (event) => {
    const { index, jpeg } = JSON.parse(event.data);
    images[index] = `data:image/jpeg;base64,${jpeg}`;
    const img = document.querySelector(`.key[data-index="${index}"] img`);
    if (img) img.src = images[index];
  });
  events.addEventListener('deckKey', (event) => {
    const { index } = JSON.parse(event.data);
    showSettings = false;
    selectKey(index);
  });
  events.addEventListener('error', async () => {
    connectionLost = true;
    renderBanners();
    if (events.readyState === EventSource.CLOSED) {
      // Closed for good, e.g. 401 after this browser was revoked; check, then retry.
      try {
        await api('GET', '/api/state');
        setTimeout(connect, 2000);
      } catch { /* unpaired() took over */ }
    }
  });
}

function reportPresence() {
  if (!state) return;
  api('POST', '/api/presence', { tab, visible: document.visibilityState === 'visible', page: selectedPage })
    .then((result) => { if (result.ok) applyState(result.data); })
    .catch(() => {});
}

document.addEventListener('visibilitychange', reportPresence);
window.addEventListener('focus', reportPresence);
window.addEventListener('beforeunload', (event) => {
  if (state?.isDirty) event.preventDefault();
});

function applyState(next) {
  if (!next) return;
  state = next;
  const names = pages().map((page) => page.name);
  if (!names.includes(selectedPage)) {
    selectedPage = names.includes(state.draft.defaultPage) ? state.draft.defaultPage : names[0] ?? null;
    reportPresence();
  }
  render();
}

// MARK: - Draft helpers

const pages = () => state?.draft.pages ?? [];
const page = (name) => pages().find((p) => p.name === name);
const keyDoc = (pageName, index) => page(pageName)?.keys?.[String(index)] ?? null;
const keyErrors = (pageName, index) => state.errors.filter((e) => e.page === pageName && e.key === index);
const pageErrors = (pageName) => state.errors.filter((e) => e.page === pageName && (e.key === null || e.key === undefined || e.key < 0 || e.key >= KEY_COUNT));
const settingsErrors = () => state.errors.filter((e) => e.page === null || e.page === undefined);
const describe = (error) => (error.line ? `line ${error.line}: ` : '') + error.message;

function selectPage(name) {
  flushKey();
  selectedPage = name;
  showSettings = false;
  stopRecording();
  reportPresence();
  render();
}

function selectKey(index) {
  flushKey();
  stopRecording();
  selectedKey = index;
  render();
}

// MARK: - Key edits (debounced, so typing sends one request per pause)

let pending = null;
let pendingTimer = null;

function clean(key) {
  const result = {};
  for (const field of ['icon', 'image', 'label', 'background']) {
    if (key[field] !== undefined && key[field] !== null && key[field] !== '') result[field] = key[field];
  }
  if (key.action?.kind) result.action = { kind: key.action.kind, value: key.action.value ?? '' };
  if (key.dynamic) result.dynamic = { run: key.dynamic.run ?? '', every: key.dynamic.every ?? '' };
  return result;
}

// Changes the selected key. `mutate` edits a copy; text fields pass `debounce`.
function editKey(mutate, { debounce = false } = {}) {
  if (selectedPage === null || selectedKey === null) return;
  if (!pending || pending.page !== selectedPage || pending.index !== selectedKey) {
    flushKey();
    pending = { page: selectedPage, index: selectedKey, key: structuredClone(keyDoc(selectedPage, selectedKey) ?? {}) };
  }
  mutate(pending.key);
  clearTimeout(pendingTimer);
  if (debounce) pendingTimer = setTimeout(flushKey, DEBOUNCE_MS);
  else flushKey();
}

function flushKey() {
  clearTimeout(pendingTimer);
  if (!pending) return Promise.resolve();
  const { page: pageName, index, key } = pending;
  pending = null;
  const cleaned = clean(key);
  const body = Object.keys(cleaned).length ? cleaned : null;
  return change('PUT', `/api/draft/pages/${encodeURIComponent(pageName)}/keys/${index}`, body);
}

let settingsDraft = null;
let settingsTimer = null;

function editSettings(mutate, { debounce = false } = {}) {
  if (!settingsDraft) {
    settingsDraft = {
      brightness: state.draft.brightness ?? null,
      defaultPage: state.draft.defaultPage,
      appPages: structuredClone(state.draft.appPages),
    };
  }
  mutate(settingsDraft);
  clearTimeout(settingsTimer);
  if (debounce) settingsTimer = setTimeout(flushSettings, DEBOUNCE_MS);
  else flushSettings();
}

function flushSettings() {
  clearTimeout(settingsTimer);
  if (!settingsDraft) return Promise.resolve();
  const body = settingsDraft;
  settingsDraft = null;
  if (body.brightness === '') body.brightness = null;
  return change('PUT', '/api/draft/settings', body);
}

// MARK: - Rendering

function render() {
  if (!state) return;
  renderTopbar();
  renderBanners();
  renderPages();
  renderPageHeader();
  renderGrid();
  renderDeck();
  renderInspector();
}

function renderTopbar() {
  $('dirty').hidden = !state.isDirty;
  $('save').disabled = !state.canSave || !state.isDirty;
  $('save').title = state.canSave ? '' : 'Fix the errors first';
}

function errorList(errors) {
  return h('ul', { className: 'errors' }, errors.map((error) => h('li', { text: describe(error) })));
}

function renderBanners() {
  const banners = [];
  if (connectionLost) banners.push(h('div', { className: 'banner bad' }, 'Connection to the daemon lost. Reconnecting…'));
  if (state?.unreadable) {
    banners.push(h('div', { className: 'banner bad' },
      h('div', { className: 'grow' }, "config.yaml can't be opened in the editor. Fix it over ssh; the editor loads it once it's valid.",
        errorList(state.unreadable))));
  }
  if (state?.pendingDisk) {
    banners.push(h('div', { className: 'banner' },
      h('span', { className: 'grow', text: 'config.yaml changed on disk, and you have unsaved changes.' }),
      h('button', { text: 'Load the file', onclick: () => change('POST', '/api/disk-change', { reload: true }) }),
      h('button', { text: 'Keep my draft', onclick: () => change('POST', '/api/disk-change', { reload: false }) })));
  }
  if (state?.diskErrors) {
    banners.push(h('div', { className: 'banner bad' },
      h('div', { className: 'grow' }, 'The file on disk has errors. Your draft is kept.', errorList(state.diskErrors))));
  }
  if (lastError) {
    banners.push(h('div', { className: 'banner bad' },
      h('span', { className: 'grow', text: lastError }),
      h('button', { text: 'Dismiss', onclick: () => { lastError = null; renderBanners(); } })));
  }
  $('banners').replaceChildren(...banners);
}

function renderPages() {
  const list = $('page-list');
  list.replaceChildren(...pages().map((p) => {
    const hasErrors = state.errors.some((e) => e.page === p.name);
    const button = h('button', {
      className: p.name === selectedPage && !showSettings ? 'selected' : '',
      onclick: () => selectPage(p.name),
    }, h('span', { text: p.name }), hasErrors ? h('span', { className: 'mark', text: '●', title: 'Has errors' }) : null);
    return h('li', {}, button);
  }));
  const select = $('page-select');
  select.replaceChildren(...pages().map((p) => h('option', { value: p.name, text: p.name, selected: p.name === selectedPage })));
  select.onchange = () => selectPage(select.value);
  $('settings-button').classList.toggle('primary', showSettings);
}

function renderPageHeader() {
  const header = $('page-header');
  if (selectedPage === null) {
    header.replaceChildren(h('span', { className: 'hint', text: 'No pages yet. Add one.' }));
    return;
  }
  const isDefault = state.draft.defaultPage === selectedPage;
  header.replaceChildren(...[
    h('span', { className: 'name', text: selectedPage }),
    isDefault ? h('span', { className: 'hint', text: '(default page)' }) : null,
    h('button', { className: 'link', text: 'Rename', onclick: renamePage }),
    h('button', { className: 'link danger', text: 'Delete', onclick: deletePage }),
    pageErrors(selectedPage).length ? errorList(pageErrors(selectedPage)) : null,
  ].filter(Boolean));
}

function buildGrid() {
  const grid = $('grid');
  grid.replaceChildren(...Array.from({ length: KEY_COUNT }, (_, index) => h('button', {
    className: 'key',
    onclick: () => { showSettings = false; selectKey(index); },
    'aria-label': `Key ${index}`,
  }, h('img', { alt: '' }), h('span', { className: 'index', text: String(index) }))));
  grid.querySelectorAll('.key').forEach((button, index) => { button.dataset.index = String(index); });
}

function renderGrid() {
  const holder = state.holder;
  const elsewhere = holder && holder.tab !== tab;
  const note = $('holder-note');
  note.hidden = !elsewhere;
  if (elsewhere) {
    note.replaceChildren(
      `The deck is showing page “${holder.page ?? '?'}” for another editor. `,
      h('button', { className: 'link', text: 'Show this page', onclick: reportPresence }));
  }
  $('grid').classList.toggle('elsewhere', Boolean(elsewhere));
  document.querySelectorAll('.key').forEach((button) => {
    const index = Number(button.dataset.index);
    button.classList.toggle('selected', !showSettings && index === selectedKey);
    button.classList.toggle('invalid', selectedPage !== null && keyErrors(selectedPage, index).length > 0);
    const img = button.querySelector('img');
    if (images[index] && img.src !== images[index]) img.src = images[index];
  });
}

function renderDeck() {
  const status = state.status;
  $('device').textContent = status.connected
    ? `Connected (serial ${status.device?.serial ?? '?'}), showing page “${status.page ?? '–'}”.`
    : 'No deck connected.';
  $('problems').replaceChildren(...status.problems.map((problem) => h('li', { text: problem.message })));
}

// MARK: - Inspector

// The inspector is rebuilt only when what it shows changes shape, so typing keeps focus.
let inspectorShape = null;
let refreshers = [];

function bind(element, read) {
  refreshers.push(() => {
    if (document.activeElement === element) return;
    const value = read();
    if (element.type === 'checkbox') element.checked = Boolean(value);
    else if (element.value !== (value ?? '')) element.value = value ?? '';
  });
  return element;
}

function iconKind(icon) {
  if (icon === null || icon === undefined) return 'none';
  if (icon.startsWith('ms:')) return 'material';
  if (icon.startsWith('sf:')) return 'sf';
  return 'file';
}

function material(icon) {
  const rest = (icon ?? '').slice(3);
  const filled = rest.endsWith('.fill');
  return { name: filled ? rest.slice(0, -5) : rest, filled };
}

function renderInspector() {
  const key = selectedKey === null ? null : keyDoc(selectedPage, selectedKey);
  const shape = showSettings ? `settings|${pages().length}|${state.draft.appPages.length}`
    : selectedKey === null ? 'none'
    : [selectedPage, selectedKey, Boolean(key), iconKind(key?.icon), key?.action?.kind ?? '', Boolean(key?.dynamic), Boolean(key?.image), pages().length].join('|');
  if (shape !== inspectorShape) {
    inspectorShape = shape;
    refreshers = [];
    const inspector = $('inspector');
    if (showSettings) inspector.replaceChildren(...settingsInspector());
    else if (selectedKey === null) inspector.replaceChildren(h('p', { className: 'hint', text: 'Select a key in the grid, or press one on the deck.' }));
    else inspector.replaceChildren(...keyInspector());
  }
  refreshers.forEach((refresh) => refresh());
  updateDynamicParts();
}

// Parts that change without a rebuild: error lists and the unknown-symbol mark.
let dynamicParts = [];
function updateDynamicParts() {
  dynamicParts.forEach((update) => update());
}

function keyInspector() {
  dynamicParts = [];
  const current = () => keyDoc(selectedPage, selectedKey) ?? {};
  const key = current();
  const sections = [];

  const errors = h('div');
  dynamicParts.push(() => {
    const list = keyErrors(selectedPage, selectedKey);
    errors.replaceChildren(list.length ? errorList(list) : '');
  });
  sections.push(h('div', { className: 'section' },
    h('div', { className: 'row' },
      h('h3', { className: 'grow', text: `Key ${selectedKey}` }),
      h('button', { className: 'danger', text: 'Clear key', disabled: !keyDoc(selectedPage, selectedKey), onclick: () => editKey((k) => { for (const f of Object.keys(k)) delete k[f]; }) })),
    errors));

  // Icon
  const kind = iconKind(key.icon);
  const kindSelect = h('select', {
    // Each kind starts with a prefix, so an unfinished value keeps its kind.
    onchange: () => editKey((k) => {
      k.icon = { none: null, material: 'ms:', sf: 'sf:', file: 'icons/' }[kindSelect.value];
    }),
  }, ICON_KINDS.map(([value, text]) => h('option', { value, text, selected: value === kind })));
  const iconSection = h('div', { className: 'section' }, h('label', {}, 'Icon', kindSelect));
  if (kind === 'material') {
    const name = bind(h('input', {
      placeholder: 'home',
      oninput: () => editKey((k) => { k.icon = `ms:${name.value.trim()}${material(k.icon).filled ? '.fill' : ''}`; }, { debounce: true }),
    }), () => material(current().icon).name);
    const filled = bind(h('input', {
      type: 'checkbox',
      onchange: () => editKey((k) => { k.icon = `ms:${material(k.icon).name}${filled.checked ? '.fill' : ''}`; }),
    }), () => material(current().icon).filled);
    const unknown = h('span', { className: 'error' });
    dynamicParts.push(() => {
      const symbol = material(current().icon).name;
      unknown.textContent = symbol && !isKnownSymbol(symbol) ? 'Unknown Material Symbol' : '';
    });
    const browse = h('button', {
      text: 'Browse…',
      onclick: () => openPicker($('picker'), material(current().icon), (symbol, isFilled) => {
        editKey((k) => { k.icon = `ms:${symbol}${isFilled ? '.fill' : ''}`; });
      }),
    });
    iconSection.append(
      h('div', { className: 'row' }, h('label', { className: 'grow' }, 'Name', name), browse),
      h('div', { className: 'row' }, h('label', { className: 'inline' }, filled, 'Filled'), unknown));
  } else if (kind === 'sf') {
    const name = bind(h('input', {
      placeholder: 'play.fill',
      oninput: () => editKey((k) => { k.icon = `sf:${name.value.trim()}`; }, { debounce: true }),
    }), () => (current().icon ?? '').slice(3));
    iconSection.append(h('label', {}, 'SF Symbol name', name),
      h('p', { className: 'hint', text: 'SF Symbols draw only on macOS. On Linux the key shows a placeholder; use a Material Symbol for a shared config.' }));
  } else if (kind === 'file') {
    const path = bind(h('input', {
      placeholder: 'icons/terminal.png',
      oninput: () => editKey((k) => { k.icon = path.value; }, { debounce: true }),
    }), () => current().icon);
    iconSection.append(h('label', {}, 'Image path', path),
      h('p', { className: 'hint', text: 'PNG or JPEG on the daemon’s machine, relative to the config directory or absolute.' }));
  }
  sections.push(iconSection);

  // Label and background
  const label = bind(h('input', { oninput: () => editKey((k) => { k.label = label.value; }, { debounce: true }) }), () => current().label);
  const backgroundText = bind(h('input', {
    className: 'grow mono', placeholder: '#000000',
    oninput: () => editKey((k) => { k.background = backgroundText.value.trim(); }, { debounce: true }),
  }), () => current().background);
  const color = h('input', { type: 'color', onchange: () => editKey((k) => { k.background = color.value.toUpperCase(); }) });
  refreshers.push(() => {
    const value = current().background ?? '';
    color.value = /^#[0-9a-fA-F]{6}$/.test(value) ? value.toLowerCase() : '#000000';
  });
  sections.push(h('div', { className: 'section' },
    h('label', {}, 'Label', label),
    h('label', {}, 'Background', h('div', { className: 'row field' }, color, backgroundText,
      h('button', { className: 'link', text: 'Clear', onclick: () => editKey((k) => { k.background = null; }) })))));

  // Full-key image
  const image = bind(h('input', {
    className: 'grow', placeholder: 'art/cover.jpg',
    oninput: () => editKey((k) => { k.image = image.value; }, { debounce: true }),
  }), () => current().image);
  sections.push(h('div', { className: 'section' },
    h('label', {}, 'Full-key image', h('div', { className: 'row field' }, image,
      key.image ? h('button', { className: 'link', text: 'Remove', onclick: () => editKey((k) => { k.image = null; }) }) : null)),
    h('p', { className: 'hint', text: 'Drawn across the whole key, under the icon and label. A path on the daemon’s machine.' })));

  sections.push(actionSection(current));
  sections.push(dynamicSection(current));
  return sections;
}

function actionSection(current) {
  const action = current().action;
  const kind = action?.kind ?? '';
  const typeSelect = h('select', {
    onchange: () => editKey((k) => {
      const next = typeSelect.value;
      if (!next) delete k.action;
      else k.action = { kind: next, value: next === 'media' ? 'playpause' : next === 'page' ? (pages()[0]?.name ?? '') : '' };
    }),
  }, ACTIONS.map(([value, text]) => h('option', { value, text, selected: value === kind })));
  const section = h('div', { className: 'section' }, h('label', {}, 'Action', typeSelect));
  const setValue = (value, debounce = false) => editKey((k) => { k.action = { kind, value }; }, { debounce });

  if (kind === 'run' || kind === 'open') {
    const input = bind(h('input', {
      className: kind === 'run' ? 'mono' : '',
      placeholder: kind === 'run' ? 'notify-send hello' : 'steam://rungameid/570',
      oninput: () => setValue(input.value, true),
    }), () => current().action?.value);
    section.append(h('label', {}, kind === 'run' ? 'Command' : 'URL, file or folder', input));
  } else if (kind === 'keys') {
    section.append(recorderField(() => current().action?.value ?? '', (value, debounce) => setValue(value, debounce)));
  } else if (kind === 'media') {
    const select = bind(h('select', { onchange: () => setValue(select.value) },
      MEDIA.map((name) => h('option', { value: name, text: name }))), () => current().action?.value);
    section.append(h('label', {}, 'Media key', select));
  } else if (kind === 'page') {
    const select = bind(h('select', { onchange: () => setValue(select.value) },
      [...pages().map((p) => h('option', { value: p.name, text: p.name })), h('option', { value: 'back', text: 'back (previous page)' })]),
    () => current().action?.value);
    section.append(h('label', {}, 'Page', select));
  }
  return section;
}

function dynamicSection(current) {
  const enabled = Boolean(current().dynamic);
  const toggle = h('input', {
    type: 'checkbox', checked: enabled,
    onchange: () => editKey((k) => { k.dynamic = toggle.checked ? { run: '', every: '30s' } : null; }),
  });
  const section = h('div', { className: 'section' }, h('label', { className: 'inline' }, toggle, 'Dynamic (a command sets the label)'));
  if (enabled) {
    const run = bind(h('input', {
      className: 'mono', placeholder: 'date +%H:%M',
      oninput: () => editKey((k) => { k.dynamic = { ...k.dynamic, run: run.value }; }, { debounce: true }),
    }), () => current().dynamic?.run);
    const every = bind(h('input', {
      placeholder: '30s',
      oninput: () => editKey((k) => { k.dynamic = { ...k.dynamic, every: every.value.trim() }; }, { debounce: true }),
    }), () => current().dynamic?.every);
    section.append(h('label', {}, 'Command', run), h('label', {}, 'Every', every),
      h('p', { className: 'hint', text: 'Plain output becomes the label. JSON can also set "icon", "image" and "background".' }));
  }
  return section;
}

// MARK: - Keystroke recording

let recording = null;

function stopRecording() {
  if (!recording) return;
  const { onKey, onMouse, onBlur, finish } = recording;
  window.removeEventListener('keydown', onKey, true);
  window.removeEventListener('keyup', swallow, true);
  document.removeEventListener('mousedown', onMouse, true);
  window.removeEventListener('blur', onBlur);
  recording = null;
  finish();
}

function swallow(event) {
  event.preventDefault();
  event.stopPropagation();
}

function recorderField(read, write) {
  const container = h('div');
  const message = h('p', { className: 'error' });
  let textMode = false;

  const draw = () => {
    if (textMode) {
      const input = bind(h('input', { className: 'mono grow', placeholder: 'ctrl+shift+m', oninput: () => write(input.value, true) }), read);
      input.value = read();
      container.replaceChildren(h('label', {}, 'Keys', h('div', { className: 'row field' }, input,
        h('button', { text: 'Done', onclick: () => { textMode = false; draw(); } }))));
      input.focus();
      return;
    }
    const value = read();
    const button = h('button', { className: value ? 'recorder mono' : 'recorder empty', text: value || 'Click to record' });
    button.onclick = () => start(button);
    container.replaceChildren(
      h('label', {}, 'Keys', h('div', { className: 'row field' }, button,
        value ? h('button', { className: 'link', text: 'Clear', title: 'Clear the keystroke', onclick: () => write('', false) }) : null,
        h('button', { className: 'link', text: 'Edit as text', onclick: () => { stopRecording(); textMode = true; draw(); } }))),
      message,
      h('p', { className: 'hint', text: 'Shortcuts the browser keeps for itself (such as Ctrl-W or Ctrl-T) and fn can’t be recorded. Use Edit as text for those.' }));
  };

  const start = (button) => {
    stopRecording();
    message.textContent = '';
    button.classList.add('recording');
    button.classList.remove('empty');
    button.textContent = heldText([]);
    const onKey = (event) => {
      swallow(event);
      const result = record(event);
      if (result.ignore) {
        button.textContent = heldText(result.held);
      } else if (result.cancel) {
        stopRecording();
      } else if (result.unsupported) {
        message.textContent = `This key (${result.unsupported}) has no name in the config. Use a letter, digit, punctuation, F-key or named key.`;
      } else {
        stopRecording();
        write(result.combo, false);
      }
    };
    const onMouse = (event) => { if (event.target !== button) stopRecording(); };
    const onBlur = () => stopRecording();
    recording = { onKey, onMouse, onBlur, finish: () => { message.textContent = ''; draw(); } };
    window.addEventListener('keydown', onKey, true);
    window.addEventListener('keyup', swallow, true);
    document.addEventListener('mousedown', onMouse, true);
    window.addEventListener('blur', onBlur);
  };

  // Redraw when the value changes elsewhere, unless recording or typing.
  refreshers.push(() => { if (!recording && !textMode) draw(); });
  draw();
  return container;
}

// MARK: - Settings

function settingsInspector() {
  dynamicParts = [];
  const current = () => settingsDraft ?? { brightness: state.draft.brightness, defaultPage: state.draft.defaultPage, appPages: state.draft.appPages };
  const errors = h('div');
  dynamicParts.push(() => {
    const list = settingsErrors();
    errors.replaceChildren(list.length ? errorList(list) : '');
  });

  const brightness = bind(h('input', {
    inputMode: 'numeric', placeholder: '70',
    oninput: () => editSettings((s) => { s.brightness = brightness.value.trim(); }, { debounce: true }),
  }), () => current().brightness);
  const defaultPage = bind(h('select', { onchange: () => editSettings((s) => { s.defaultPage = defaultPage.value; }) },
    pages().map((p) => h('option', { value: p.name, text: p.name }))), () => current().defaultPage);

  const appRows = state.draft.appPages.map((entry, index) => {
    const app = bind(h('input', {
      placeholder: 'com.apple.Safari', 'aria-label': 'Application',
      oninput: () => editSettings((s) => { s.appPages[index].app = app.value.trim(); }, { debounce: true }),
    }), () => current().appPages[index]?.app);
    const target = bind(h('select', { 'aria-label': 'Page', onchange: () => editSettings((s) => { s.appPages[index].page = target.value; }) },
      pages().map((p) => h('option', { value: p.name, text: p.name }))), () => current().appPages[index]?.page);
    const remove = h('button', { className: 'link danger', text: 'Remove', onclick: () => editSettings((s) => { s.appPages.splice(index, 1); }) });
    return h('div', { className: 'app-page' }, app, target, remove);
  });

  const clients = h('ul', { className: 'clients' });
  loadClients(clients);

  return [
    h('div', { className: 'section' }, h('h3', { text: 'Settings' }), errors),
    h('div', { className: 'section' },
      h('label', {}, 'Brightness (0–100)', brightness),
      h('label', {}, 'Default page', defaultPage)),
    h('div', { className: 'section' },
      h('h3', { text: 'App pages' }),
      h('p', { className: 'hint', text: 'Show a page when an app is in front: a macOS bundle ID such as com.apple.Safari.' }),
      ...appRows,
      h('button', { text: 'Add app page', onclick: () => editSettings((s) => { s.appPages.push({ app: '', page: pages()[0]?.name ?? '' }); }) })),
    h('div', { className: 'section' },
      h('h3', { text: 'Paired browsers' }),
      clients,
      h('button', { text: 'Unpair this browser', onclick: unpairSelf })),
  ];
}

async function loadClients(list) {
  try {
    const result = await api('GET', '/api/clients');
    if (!result.ok) return;
    list.replaceChildren(...result.data.map((client) => h('li', {},
      h('span', { className: 'grow' }, h('strong', { text: client.name }), client.current ? ' (this browser)' : '',
        h('br'), h('span', { className: 'hint', text: `paired ${new Date(client.created).toLocaleDateString()}, last used ${new Date(client.lastUsed).toLocaleString()}` })),
      h('button', {
        className: 'danger', text: 'Revoke',
        onclick: async () => {
          if (!await confirmDialog('Revoke this browser?', `“${client.name}” will have to pair again.`, 'Revoke')) return;
          await api('DELETE', `/api/clients/${encodeURIComponent(client.id)}`);
          if (client.current) location.reload();
          else loadClients(list);
        },
      }))));
  } catch { /* unpaired */ }
}

async function unpairSelf() {
  if (!await confirmDialog('Unpair this browser?', 'You will need the deck to pair it again.', 'Unpair')) return;
  try { await api('POST', '/api/logout', {}); } catch { /* already unpaired */ }
  location.reload();
}

// MARK: - Pages

async function addPage() {
  const name = await promptDialog('Add page', 'Name', '');
  if (name === null) return;
  const before = new Set(pages().map((p) => p.name));
  const result = await change('POST', '/api/draft/pages', { name }, pageNameProblem(name));
  if (result.ok) {
    const added = pages().find((p) => !before.has(p.name));
    if (added) selectPage(added.name);
  }
}

async function renamePage() {
  const old = selectedPage;
  const name = await promptDialog(`Rename “${old}”`, 'New name', old);
  if (name === null || name === old) return;
  const result = await change('POST', `/api/draft/pages/${encodeURIComponent(old)}/rename`, { name }, pageNameProblem(name));
  if (result.ok) selectPage(name.trim());
}

function pageNameProblem(name) {
  return (result) => {
    const text = {
      empty: 'Enter a name for the page.',
      reserved: '“back” is reserved: it is the page action that returns to the previous page.',
      taken: `A page named “${name.trim()}” already exists.`,
    }[result.data?.error];
    if (!text) return false;
    alertDialog('Cannot use that name', text);
    return true;
  };
}

async function deletePage() {
  const name = selectedPage;
  if (!await confirmDialog(`Delete page “${name}”?`, 'Its keys are removed from the draft.', 'Delete')) return;
  await change('DELETE', `/api/draft/pages/${encodeURIComponent(name)}`, {}, (result) => {
    if (result.status !== 409) return false;
    alertDialog(`“${name}” is still in use`, `Change these first:\n${result.data.references.map((r) => `• ${r}`).join('\n')}`);
    return true;
  });
}

// MARK: - Save and revert

async function save() {
  await flushKey();
  await flushSettings();
  const handle = (result) => {
    if (result.status === 422) {
      alertDialog('The config has errors', result.data.errors.map((e) => `• ${describe(e)}`).join('\n'));
      return true;
    }
    return false;
  };
  const result = await change('POST', '/api/save', { confirmOverwrite: false }, (response) => {
    if (response.status === 409 && response.data?.needsOverwriteConfirmation) return true;
    return handle(response);
  });
  if (result.status !== 409) return;
  const confirmed = await confirmDialog('Replace the hand-edited config?',
    'Saving rewrites config.yaml in the editor’s format. Comments and formatting in the file are lost. The current file is copied to config.yaml.bak first.',
    'Save');
  if (confirmed) await change('POST', '/api/save', { confirmOverwrite: true }, handle);
}

async function revert() {
  if (state.isDirty && !await confirmDialog('Discard unsaved changes?', 'The editor and the deck return to config.yaml.', 'Discard')) return;
  pending = null;
  settingsDraft = null;
  await change('POST', '/api/revert', {});
}

// MARK: - Dialogs

function openDialog(title, body, buttons) {
  const dialog = $('dialog');
  return new Promise((resolve) => {
    const finish = (value) => { dialog.close(); resolve(value); };
    dialog.replaceChildren(
      h('h3', { text: title }),
      ...body,
      h('div', { className: 'buttons' }, buttons.map(([text, value, className]) => h('button', { text, className, onclick: () => finish(value()) }))));
    dialog.oncancel = () => resolve(null);
    dialog.showModal();
    dialog.querySelector('input')?.focus();
  });
}

function promptDialog(title, label, value) {
  const input = h('input', { value });
  input.onkeydown = (event) => { if (event.key === 'Enter') $('dialog').querySelector('.primary').click(); };
  return openDialog(title, [h('label', {}, label, input)], [['Cancel', () => null, ''], ['OK', () => input.value, 'primary']]);
}

async function confirmDialog(title, text, okLabel) {
  return (await openDialog(title, [h('p', { text })], [['Cancel', () => false, ''], [okLabel, () => true, 'primary']])) === true;
}

function alertDialog(title, text) {
  return openDialog(title, [h('p', { text })], [['OK', () => true, 'primary']]);
}

// MARK: - Wiring

$('save').onclick = save;
$('revert').onclick = revert;
$('add-page').onclick = addPage;
$('settings-button').onclick = () => {
  flushKey();
  stopRecording();
  showSettings = !showSettings;
  render();
};

start();
