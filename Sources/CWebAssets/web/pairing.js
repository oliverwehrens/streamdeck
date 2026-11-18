// The pairing screen: ask the deck for a code, then send it back. See the web-pairing spec.

const $ = (id) => document.getElementById(id);

// A short guess at what this browser is, for the paired-browser list.
export function guessName(userAgent) {
  const browser = /Edg\//.test(userAgent) ? 'Edge'
    : /Firefox\//.test(userAgent) ? 'Firefox'
    : /Chrome\//.test(userAgent) ? 'Chrome'
    : /Safari\//.test(userAgent) ? 'Safari' : 'Browser';
  const system = /Android/.test(userAgent) ? 'Android'
    : /iPhone|iPad/.test(userAgent) ? 'iOS'
    : /Mac OS X/.test(userAgent) ? 'macOS'
    : /Windows/.test(userAgent) ? 'Windows'
    : /Linux/.test(userAgent) ? 'Linux' : '';
  return system ? `${browser} on ${system}` : browser;
}

const messages = {
  noDevice: 'Connect the deck first: pairing shows the code on its keys.',
  lockedOut: 'Too many wrong codes. Pairing is locked for 10 minutes.',
  wrongCode: 'That is not the code on the deck. Try again.',
  noCode: 'The code expired or was cancelled. Show a new one.',
};

async function post(path, body) {
  const response = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  let data = {};
  try { data = await response.json(); } catch { /* empty body */ }
  return { ok: response.ok, error: data.error };
}

// Shows the pairing screen; calls `onPaired` once the browser has its token.
export function showPairing(onPaired) {
  $('pairing').hidden = false;
  const name = $('pair-name');
  if (!name.value) name.value = guessName(navigator.userAgent);
  const message = $('pair-message');
  const say = (text) => { message.textContent = text; };

  $('pair-start').onclick = async () => {
    say('');
    const result = await post('/api/pair/start', {});
    if (!result.ok) {
      say(messages[result.error] ?? `Pairing failed: ${result.error ?? 'unknown error'}`);
      return;
    }
    $('pair-entry').hidden = false;
    $('pair-code').value = '';
    $('pair-code').focus();
  };

  const submit = async () => {
    say('');
    const result = await post('/api/pair', { code: $('pair-code').value, name: name.value });
    if (!result.ok) {
      say(messages[result.error] ?? `Pairing failed: ${result.error ?? 'unknown error'}`);
      if (result.error === 'noCode' || result.error === 'lockedOut') $('pair-entry').hidden = true;
      return;
    }
    $('pairing').hidden = true;
    onPaired();
  };
  $('pair-submit').onclick = submit;
  $('pair-code').onkeydown = (event) => { if (event.key === 'Enter') submit(); };
}
