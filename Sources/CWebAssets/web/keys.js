// Turns a browser key press into config text for a `keys:` action. Pure, so Node can test it
// (Tests/web/keys.test.mjs). See design "Keystroke recording in the browser".

// Named keys by KeyboardEvent.code, using the config's canonical names.
export const NAMED = {
  Enter: 'return', Tab: 'tab', Space: 'space', Backspace: 'delete', Delete: 'forwarddelete', Escape: 'esc',
  Home: 'home', End: 'end', PageUp: 'pageup', PageDown: 'pagedown',
  ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down',
};
for (let n = 1; n <= 20; n++) NAMED[`F${n}`] = `f${n}`;

// Characters the config accepts as keys.
export const CHARACTERS = new Set("abcdefghijklmnopqrstuvwxyz0123456789-=[]\\;',./`");

// The character each key types on a US layout, for keys whose typed character is shifted or unknown.
const US = {
  Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\', Semicolon: ';',
  Quote: "'", Comma: ',', Period: '.', Slash: '/', Backquote: '`',
};
for (const letter of 'abcdefghijklmnopqrstuvwxyz') US[`Key${letter.toUpperCase()}`] = letter;
for (let digit = 0; digit <= 9; digit++) US[`Digit${digit}`] = String(digit);

const MODIFIER_CODES = new Set([
  'MetaLeft', 'MetaRight', 'OSLeft', 'OSRight', 'ControlLeft', 'ControlRight',
  'AltLeft', 'AltRight', 'ShiftLeft', 'ShiftRight', 'CapsLock', 'Fn', 'FnLock',
]);
const MODIFIER_KEYS = new Set(['Meta', 'OS', 'Control', 'Alt', 'AltGraph', 'Shift', 'CapsLock', 'Fn', 'Super', 'Hyper']);

// The held modifiers in config order: cmd (Meta/Windows/Super), ctrl, alt, shift.
export function modifiersOf(event) {
  const held = [];
  if (event.metaKey) held.push('cmd');
  if (event.ctrlKey) held.push('ctrl');
  if (event.altKey) held.push('alt');
  if (event.shiftKey) held.push('shift');
  return held;
}

// Returns one of:
//   { combo: 'ctrl+shift+m' }   the recording
//   { ignore: true, held }      a modifier alone; keep recording and show `held`
//   { cancel: true }            Esc without modifiers
//   { unsupported: code }       a key with no config name; keep recording
export function record(event) {
  const held = modifiersOf(event);
  if (MODIFIER_CODES.has(event.code) || MODIFIER_KEYS.has(event.key)) return { ignore: true, held };
  if (event.isComposing || event.key === 'Dead' || event.key === 'Process' || event.key === 'Unidentified') {
    return { unsupported: event.code || event.key };
  }
  if (event.code === 'Escape' && held.length === 0) return { cancel: true };
  if (event.code?.startsWith('Numpad') || event.code === 'IntlBackslash') return { unsupported: event.code };

  let key = NAMED[event.code];
  if (!key) {
    const typed = typeof event.key === 'string' && [...event.key].length === 1 ? event.key.toLowerCase() : null;
    const isLetter = typed !== null && typed >= 'a' && typed <= 'z';
    if (typed !== null && CHARACTERS.has(typed) && (isLetter || (!event.shiftKey && !event.altKey))) {
      // The character on the user's own layout, so German Ctrl-Z gives `z`.
      key = typed;
    } else if (event.shiftKey || event.altKey) {
      // Shift or Alt changed what the key types; use the key's US character (Shift-1 gives `1`).
      key = US[event.code];
    }
  }
  if (!key) return { unsupported: event.code || event.key };
  return { combo: [...held, key].join('+') };
}

// What the field shows while recording: the held modifiers, or a prompt.
export function heldText(held) {
  return held.length ? held.join('+') + '+…' : 'Type shortcut…';
}
