// The Material Symbols picker: every symbol the daemon can draw, from the font it serves.

const LIMIT = 400;
let symbols = null;

// Loads `[[name, codepoint], …]` once. Returns the list.
export async function loadSymbols() {
  if (!symbols) {
    const response = await fetch('/api/symbols');
    if (!response.ok) throw new Error(`cannot load symbols: ${response.status}`);
    symbols = await response.json();
  }
  return symbols;
}

// Whether `name` is a known symbol; true while the list isn't loaded yet.
export function isKnownSymbol(name) {
  return !symbols || symbols.some(([known]) => known === name);
}

// Names containing every word of `query`, in font order.
export function matching(list, query) {
  const words = query.toLowerCase().split(/[\s_]+/).filter(Boolean);
  return list.filter(([name]) => words.every((word) => name.includes(word)));
}

// Opens the picker in `dialog`. `choose(name, filled)` is called with the pick.
export async function openPicker(dialog, { name = '', filled = false }, choose) {
  const list = await loadSymbols();
  dialog.replaceChildren();

  const search = document.createElement('input');
  search.type = 'search';
  search.placeholder = 'Search symbols, e.g. play or home';
  search.value = name;
  search.className = 'grow';
  const fill = document.createElement('input');
  fill.type = 'checkbox';
  fill.checked = filled;
  const fillLabel = document.createElement('label');
  fillLabel.className = 'inline';
  fillLabel.append(fill, 'Filled');
  const top = document.createElement('div');
  top.className = 'row';
  top.append(search, fillLabel);

  const grid = document.createElement('div');
  grid.className = 'symbols';
  const count = document.createElement('p');
  count.className = 'hint';
  const close = document.createElement('button');
  close.textContent = 'Cancel';
  close.onclick = () => dialog.close();
  const buttons = document.createElement('div');
  buttons.className = 'buttons';
  buttons.append(close);

  const render = () => {
    const found = matching(list, search.value);
    grid.replaceChildren(...found.slice(0, LIMIT).map(([symbol, codepoint]) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.title = symbol;
      button.setAttribute('aria-label', symbol);
      if (symbol === name) button.classList.add('current');
      const glyph = document.createElement('span');
      glyph.className = fill.checked ? 'glyph filled' : 'glyph';
      glyph.textContent = String.fromCodePoint(codepoint);
      button.append(glyph);
      button.onclick = () => {
        dialog.close();
        choose(symbol, fill.checked);
      };
      return button;
    }));
    count.textContent = found.length === 0 ? 'No matching symbols'
      : found.length > LIMIT ? `${found.length} symbols, showing the first ${LIMIT}. Type to narrow down. Hover for the name.`
      : `${found.length} symbols. Hover for the name.`;
  };
  search.oninput = render;
  fill.onchange = render;
  render();

  dialog.append(top, count, grid, buttons);
  dialog.showModal();
  search.focus();
  search.select();
}
