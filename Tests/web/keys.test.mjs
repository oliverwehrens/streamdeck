import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { record, NAMED, CHARACTERS } from '../../Sources/CWebAssets/web/keys.js';

const fixture = JSON.parse(readFileSync(new URL('./fixtures/key-names.json', import.meta.url)));

function press(code, key, mods = {}) {
  return record({ code, key, metaKey: false, ctrlKey: false, altKey: false, shiftKey: false, ...mods });
}

test('ctrl+shift+m', () => {
  assert.deepEqual(press('KeyM', 'M', { ctrlKey: true, shiftKey: true }), { combo: 'ctrl+shift+m' });
});

test('meta is cmd', () => {
  assert.deepEqual(press('Space', ' ', { metaKey: true }), { combo: 'cmd+space' });
});

test('named key with modifiers', () => {
  assert.deepEqual(press('ArrowLeft', 'ArrowLeft', { ctrlKey: true, altKey: true }), { combo: 'ctrl+alt+left' });
});

test('German layout records the typed letter', () => {
  assert.deepEqual(press('KeyY', 'z', { ctrlKey: true }), { combo: 'ctrl+z' });
});

test('shifted digit records the digit', () => {
  assert.deepEqual(press('Digit1', '!', { shiftKey: true }), { combo: 'shift+1' });
});

test('German shifted digit typing a config character records the digit', () => {
  assert.deepEqual(press('Digit7', '/', { shiftKey: true }), { combo: 'shift+7' });
});

test('alt changing the character uses the US key', () => {
  assert.deepEqual(press('KeyO', 'ø', { altKey: true }), { combo: 'alt+o' });
});

test('f12', () => {
  assert.deepEqual(press('F12', 'F12'), { combo: 'f12' });
});

test('escape alone cancels', () => {
  assert.deepEqual(press('Escape', 'Escape'), { cancel: true });
});

test('escape with a modifier is recorded', () => {
  assert.deepEqual(press('Escape', 'Escape', { ctrlKey: true }), { combo: 'ctrl+esc' });
});

test('numpad is unsupported', () => {
  assert.deepEqual(press('Numpad5', '5'), { unsupported: 'Numpad5' });
});

test('letter without a config name is unsupported', () => {
  assert.deepEqual(press('Semicolon', 'ö'), { unsupported: 'Semicolon' });
});

test('a lone modifier is ignored and reported as held', () => {
  assert.deepEqual(press('ShiftLeft', 'Shift', { shiftKey: true }), { ignore: true, held: ['shift'] });
  assert.deepEqual(press('MetaLeft', 'Meta', { metaKey: true, ctrlKey: true }), { ignore: true, held: ['cmd', 'ctrl'] });
});

test('composition and dead keys are unsupported', () => {
  assert.ok(press('KeyA', 'Process').unsupported);
  assert.ok(press('BracketLeft', 'Dead').unsupported);
});

test('every named key in the config can be recorded', () => {
  const produced = new Set(Object.values(NAMED));
  for (const name of fixture.names) assert.ok(produced.has(name), `no browser key records ${name}`);
  for (const name of produced) assert.ok(fixture.names.includes(name), `${name} is not a config key name`);
});

test('the character set matches the config', () => {
  assert.deepEqual([...CHARACTERS].sort(), [...fixture.characters].sort());
});

test('every config character can be recorded on a US layout', () => {
  const codes = {
    '-': 'Minus', '=': 'Equal', '[': 'BracketLeft', ']': 'BracketRight', '\\': 'Backslash', ';': 'Semicolon',
    "'": 'Quote', ',': 'Comma', '.': 'Period', '/': 'Slash', '`': 'Backquote',
  };
  for (const character of fixture.characters) {
    const code = codes[character] ?? (/[0-9]/.test(character) ? `Digit${character}` : `Key${character.toUpperCase()}`);
    assert.deepEqual(press(code, character, { ctrlKey: true }), { combo: `ctrl+${character}` });
  }
});
