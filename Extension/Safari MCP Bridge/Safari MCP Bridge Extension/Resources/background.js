// Safari CLI Bridge: connects to the local safari-mcp servers (one per Claude Code session)
// and carries out their requests. A server and this page each prove they know the token in
// ~/.config/safari-mcp/token before any request runs.
'use strict';
const PORTS = [47391, 47392, 47393, 47394, 47395, 47396, 47397, 47398, 47399];
const enc = new TextEncoder();
let token = null;

async function getToken() {
  if (token) return token;
  try {
    const r = await browser.runtime.sendNativeMessage('com.sadopc.safari-mcp', { op: 'token' });
    token = (r && r.token) || null;
  } catch (e) { token = null; }
  return token;
}
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
const nonce = () => hex(crypto.getRandomValues(new Uint8Array(16)));
async function hmac(msg) {
  const k = await crypto.subtle.importKey('raw', enc.encode(token), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return hex(await crypto.subtle.sign('HMAC', k, enc.encode(msg)));
}

// Per-tab facts the page cannot report itself.
const status = new Map();   // tab id -> HTTP status of the last top-level load
const reqs = new Map();     // tab id -> recent requests, as log lines
const started = new Map();  // request id -> start time
browser.webRequest.onBeforeRequest.addListener((d) => {
  if (d.tabId < 0) return;
  // Safari can label iframe loads main_frame too; only frame 0 is the tab's document.
  if (d.type === 'main_frame' && d.frameId === 0) reqs.set(d.tabId, []);
  started.set(d.requestId, d.timeStamp);
}, { urls: ['<all_urls>'] });
function done(d, st) {
  if (d.tabId < 0) return;
  if (d.type === 'main_frame' && d.frameId === 0) status.set(d.tabId, st);
  const t0 = started.get(d.requestId); started.delete(d.requestId);
  const list = reqs.get(d.tabId) || []; reqs.set(d.tabId, list);
  list.push(`${d.type} ${st || 'ERR'} ${d.url} ${t0 ? Math.round(d.timeStamp - t0) : 0}ms`);
  if (list.length > 300) list.shift();
}
browser.webRequest.onCompleted.addListener((d) => done(d, d.statusCode), { urls: ['<all_urls>'] });
browser.webRequest.onErrorOccurred.addListener((d) => done(d, 0), { urls: ['<all_urls>'] });
const blockRules = new Map(); // tab id -> session rule ids
let nextRule = 1;
browser.tabs.onRemoved.addListener((id) => {
  status.delete(id); reqs.delete(id);
  const ids = blockRules.get(id);
  if (ids && browser.declarativeNetRequest) { blockRules.delete(id); browser.declarativeNetRequest.updateSessionRules({ removeRuleIds: ids }).catch(() => {}); }
});

// Tabs are addressed like Apple Events does: window id + 1-based index, plus what the server
// expects there (tab count of the window, URL). A mismatch answers "stale" and nothing runs.
async function tabAt(m) {
  const ts = (await browser.tabs.query({ windowId: m.w })).sort((a, b) => a.index - b.index);
  if (m.n >= 0 && ts.length !== m.n) return null;
  const t = ts[m.i - 1];
  if (!t) return null;
  if (m.u && m.u !== '*' && (t.url || '') !== m.u) return null;
  return t;
}

const ops = {
  async tabs() {
    const wins = await browser.windows.getAll({ populate: true, windowTypes: ['normal'] });
    wins.sort((a, b) => (b.focused ? 1 : 0) - (a.focused ? 1 : 0));
    const out = [];
    for (const w of wins) for (const t of w.tabs.sort((a, b) => a.index - b.index)) {
      out.push({ id: t.id, w: w.id, i: t.index + 1, cur: t.active, ...(w.incognito ? { p: 1 } : {}), title: t.title || '', url: t.url || '' });
    }
    return { ok: out };
  },
  async run(m) {
    const t = await tabAt(m);
    if (!t) return { stale: 1 };
    let r;
    try {
      r = await browser.tabs.executeScript(t.id, { code: m.code, frameId: m.frame || 0, matchAboutBlank: true });
    } catch (e) {
      const msg = String((e && e.message) || e);
      if (/permission|not allowed|access/i.test(msg)) {
        return { err: 'The Safari CLI Bridge extension has no access to this site. In Safari > Settings > Extensions, allow it on every website.' };
      }
      r = null; // like Apple Events: a script that fails gives no value
    }
    const v = r && r[0];
    const after = await browser.tabs.get(t.id).catch(() => t);
    return { ok: v == null ? '' : typeof v === 'string' ? v : JSON.stringify(v), url: after.url || '' };
  },
  async seturl(m) { const t = await tabAt(m); if (!t) return { stale: 1 }; await browser.tabs.update(t.id, { url: m.url }); return { ok: 1 }; },
  async close(m) { const t = await tabAt(m); if (!t) return { stale: 1 }; await browser.tabs.remove(t.id); return { ok: 1 }; },
  async select(m) { const t = await tabAt(m); if (!t) return { stale: 1 }; await browser.tabs.update(t.id, { active: true }); return { ok: 1 }; },
  async raise(m) {
    const t = await tabAt(m); if (!t) return { stale: 1 };
    await browser.tabs.update(t.id, { active: true });
    await browser.windows.update(t.windowId, { focused: true });
    return { ok: 1 };
  },
  async newtab(m) {
    if (m.w != null) {
      try { const t = await browser.tabs.create({ windowId: m.w, url: m.url, active: false }); return { tab: t.id, w: t.windowId, i: t.index + 1 }; } catch (e) { /* window gone */ }
    }
    const w = await browser.windows.create({ url: m.url, focused: false });
    return { tab: w.tabs && w.tabs[0] && w.tabs[0].id, w: w.id, i: 1 };
  },
  // Safari may ignore incognito; open blank, check, and only then load the URL so a normal
  // window never sends the page the user's cookies.
  async newpriv(m) {
    const w = await browser.windows.create({ incognito: true, focused: false });
    const t = w.tabs && w.tabs[0];
    if (!w.incognito || !t) { await browser.windows.remove(w.id).catch(() => {}); return { no: 1 }; }
    if (m.url) await browser.tabs.update(t.id, { url: m.url });
    return { tab: t.id, w: w.id };
  },
  async status(m) { const t = await tabAt({ w: m.w, i: m.i, n: -1 }); return { ok: (t && status.get(t.id)) || 0 }; },
  async reqs(m) { const t = await tabAt({ w: m.w, i: m.i, n: -1 }); return { ok: (t && reqs.get(t.id)) || [] }; },
  async frames(m) {
    const t = await tabAt(m); if (!t) return { stale: 1 };
    const fs = (await browser.webNavigation.getAllFrames({ tabId: t.id })) || [];
    return { ok: fs.filter((f) => f.frameId !== 0).map((f) => ({ id: f.frameId, parent: f.parentFrameId, url: f.url })) };
  },
  async win(m) { const w = await browser.windows.get(m.w); return { x: w.left, y: w.top, width: w.width, height: w.height, focused: w.focused }; },
  // Blocks every request of one tab that matches a route pattern (safari route --block).
  async block(m) {
    const dnr = browser.declarativeNetRequest;
    if (!dnr || !dnr.updateSessionRules) return { no: 1 };
    const t = await tabAt(m); if (!t) return { stale: 1 };
    const old = blockRules.get(t.id) || [];
    const rules = m.pats.map((p) => {
      const c = { tabIds: [t.id], resourceTypes: ['sub_frame', 'stylesheet', 'script', 'image', 'font', 'object', 'xmlhttprequest', 'ping', 'media', 'websocket', 'other'] };
      if (p.startsWith('re:')) c.regexFilter = p.slice(3); else c.urlFilter = p;
      return { id: nextRule++, priority: 1, action: { type: 'block' }, condition: c };
    });
    await dnr.updateSessionRules({ removeRuleIds: old, addRules: rules });
    if (rules.length) blockRules.set(t.id, rules.map((r) => r.id)); else blockRules.delete(t.id);
    return { ok: rules.length };
  },
  // Cookies of the tab's site (safari cookies, safari state). Reply items: name, value, domain,
  // path, secure, httpOnly, sameSite, exp (seconds; absent for session cookies).
  async cookies(m) {
    const api = browser.cookies;
    if (!api || !api.getAll) return { no: 1 };
    const t = await tabAt(m); if (!t) return { stale: 1 };
    if (!/^https?:/.test(t.url || '')) return { err: 'cookies need an http(s) page' };
    const store = t.cookieStoreId ? { storeId: t.cookieStoreId } : {};
    const all = async () => {
      const q = m.domain ? { domain: m.domain } : { url: t.url };
      return (await api.getAll(Object.assign(q, store))).filter((c) => !m.name || c.name === m.name);
    };
    const out = (c) => ({ name: c.name, value: c.value, domain: c.domain, path: c.path, secure: c.secure, httpOnly: c.httpOnly, sameSite: c.sameSite, ...(c.session || c.expirationDate == null ? {} : { exp: c.expirationDate }) });
    const urlOf = (c) => (c.secure ? 'https://' : 'http://') + String(c.domain || new URL(t.url).hostname).replace(/^\./, '') + (c.path || '/');
    const put = (c) => {
      const d = { url: c.domain ? urlOf(c) : t.url, name: c.name, value: String(c.value), path: c.path || '/', ...store };
      if (c.domain && c.domain.startsWith('.')) d.domain = c.domain;
      for (const k of ['secure', 'httpOnly', 'sameSite']) if (c[k] != null) d[k] = c[k];
      if (c.exp != null) d.expirationDate = c.exp;
      return api.set(d);
    };
    if (m.act === 'set') {
      const old = (await all())[0];
      const c = await put(Object.assign(old ? out(old) : {}, { name: m.name, value: m.value }));
      return { ok: c ? [out(c)] : [] };
    }
    if (m.act === 'load') {
      let n = 0;
      for (const c of m.list || []) { try { if (await put(c)) n++; } catch (e) { /* skip */ } }
      return { ok: n };
    }
    const list = await all();
    if (m.act === 'del' || m.act === 'clear') {
      for (const c of list) await api.remove({ url: urlOf(c), name: c.name, ...store });
    }
    return { ok: list.map(out) };
  },
  async resize(m) { await browser.windows.update(m.w, { width: m.width, height: m.height }); return { ok: 1 }; },
  async shot(m) { return { ok: await browser.tabs.captureVisibleTab(m.w, { format: 'jpeg', quality: 85 }) }; },
};

const socks = new Map();
function connect(port) {
  if (socks.has(port)) return;
  let ws;
  try { ws = new WebSocket(`ws://127.0.0.1:${port}`); } catch (e) { return; }
  const st = { ok: false, expect: null };
  socks.set(port, ws);
  const drop = () => { if (socks.get(port) === ws) socks.delete(port); };
  ws.onclose = drop;
  ws.onerror = drop;
  ws.onmessage = async (ev) => {
    let m;
    try { m = JSON.parse(ev.data); } catch (e) { return; }
    if (!st.ok) {
      if (m.hello) {
        if (!(await getToken())) { ws.close(); return; }
        const mine = nonce();
        st.expect = await hmac('srv:' + mine);
        ws.send(JSON.stringify({ auth: await hmac('ext:' + m.n), n: mine }));
      } else if (m.auth && st.expect) {
        if (m.auth === st.expect) st.ok = true;
        else { token = null; ws.close(); }
      }
      return;
    }
    const reply = (o) => { try { ws.send(JSON.stringify(Object.assign({}, o, { id: m.id }))); } catch (e) { /* closed */ } };
    const f = ops[m.op];
    if (!f) { reply({ err: 'unknown op ' + m.op }); return; }
    try { reply(await f(m)); } catch (e) { reply({ err: String((e && e.message) || e) }); }
  };
}
function tick() { PORTS.forEach(connect); }
setInterval(tick, 2000);
tick();
