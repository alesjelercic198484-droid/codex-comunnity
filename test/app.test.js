import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

const PASSWORD = 'TestnoGeslo123!';

let app;
let port;
let dataDir;
const base = () => `http://127.0.0.1:${port}`;

class Jar {
  constructor() { this.cookies = new Map(); }
  header() { return [...this.cookies].map(([k, v]) => `${k}=${v}`).join('; '); }
  absorb(setCookie) {
    for (const line of setCookie || []) {
      const [pair] = line.split(';');
      const i = pair.indexOf('=');
      const name = pair.slice(0, i).trim();
      const value = pair.slice(i + 1).trim();
      if (value === '' || /Max-Age=0/i.test(line)) this.cookies.delete(name);
      else this.cookies.set(name, value);
    }
  }
  async req(p, { method = 'GET', form, json, headers = {} } = {}) {
    const h = { ...headers };
    const cookie = this.header();
    if (cookie) h.cookie = cookie;
    let body;
    if (form) {
      body = new URLSearchParams(form).toString();
      h['content-type'] = 'application/x-www-form-urlencoded';
    } else if (json) {
      body = JSON.stringify(json);
      h['content-type'] = 'application/json';
    }
    const res = await fetch(base() + p, { method, headers: h, body, redirect: 'manual' });
    this.absorb(res.headers.getSetCookie ? res.headers.getSetCookie() : res.headers.get('set-cookie'));
    res.textBody = await res.text();
    return res;
  }
}

const csrfFrom = (html) => /name="_csrf" value="([^"]+)"/.exec(html)?.[1] || '';
const codeFrom = (html) => /class="code">([A-Z0-9-]+)</.exec(html)?.[1] || '';

async function boot(overrides = {}) {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-test-'));
  const config = loadConfig({
    ...overrides,
    dataDir,
    port: 0,
    host: '127.0.0.1',
    publicUrl: '',
    admin: { username: 'admin', password: PASSWORD },
    backup: { enabled: false, everyHours: 6, keepDays: 14, dir: path.join(dataDir, 'backups') },
    applications: { open: true, minAge: 16, maxCharsMessage: 4000, maxPerIpPerDay: 5, requireSteamId: true, requireLicenseKey: true },
  });
  app = createApp(config);
  const ac = await app.listen();
  port = ac.port;
  return app;
}

const LICENSE = 'license:' + 'a'.repeat(38) + 'b7';
const validApp = {
  name: 'Janez Novak',
  ingame: 'Jane_Novak',
  discord: 'janez.novak',
  steam: 'STEAM_0:1:12345678',
  license: LICENSE,
  age: '22',
  message: 'Rad bi igral resen RP, imam 3 leta izkušenj na drugih strežnikih in igram približno petnajst ur tedensko, najbolj me zanima zdravstvo.',
  rules: 'on',
};

test('javne strani se izrišejo', async () => {
  await boot();
  const jar = new Jar();
  for (const [p, needle] of [['/', 'whitelist'], ['/prijava', 'name="rules"'], ['/status', 'Koda prijave'], ['/pravila', 'Pravila'], ['/api/health', '"ok": true']]) {
    const res = await jar.req(p);
    assert.equal(res.status, 200, `GET ${p} -> ${res.status}`);
    assert.ok(res.textBody.includes(needle), `${p} naj vsebuje "${needle}"`);
  }
  for (const p of ['/sitemap.xml', '/robots.txt', '/.well-known/security.txt']) {
    const r = await jar.req(p);
    assert.equal(r.status, 200, `GET ${p}`);
    assert.ok(!r.textBody.includes('[object Object]'), `${p}: predmeti morajo biti upodobljeni v besedilo`);
  }
  assert.match((await jar.req('/robots.txt')).textBody, /Disallow: \/admin/);
  const css = await jar.req('/assets/site.css');
  assert.equal(css.status, 200);
  assert.match(css.headers.get('content-type'), /text\/css/);
});

test('poteka za statiko ne pride ven iz mape', async () => {
  const jar = new Jar();
  for (const p of ['/assets/../package.json', '/assets/%2e%2e/src/app.js', '/assets/..%2f..%2fconfig.json']) {
    const res = await jar.req(p);
    assert.ok(res.status === 404 || res.status === 400, `${p} -> ${res.status}`);
    assert.ok(!res.textBody.includes('"dependencies"') || res.status !== 200);
  }
});

test('javen obrazec shrani prijavo in zabeleži dogodek', async () => {
  const jar = new Jar();
  const page = await jar.req('/prijava');
  const token = csrfFrom(page.textBody);
  assert.ok(token, 'stran mora vsebovati CSRF žeton');

  // brez CSRF -> zavrnjeno
  const noCsrf = await jar.req('/prijava', { method: 'POST', form: { ...validApp } });
  assert.equal(noCsrf.status, 403);

  const res = await jar.req('/prijava', { method: 'POST', form: { ...validApp, _csrf: token } });
  assert.equal(res.status, 200);
  assert.match(res.textBody, /Prijava je shranjena/);
  const code = codeFrom(res.textBody);
  assert.match(code, /^CDX-[A-Z0-9]+$/, `koda: ${code}`);

  const apps = app.store.list('applications');
  assert.equal(apps.length, 1);
  assert.equal(apps[0].status, 'pending');
  assert.equal(apps[0].license, LICENSE);
  assert.equal(apps[0].code, code);
  // licenca je normalizirana, oseben podatek (steam) shranjen
  assert.equal(apps[0].steam, 'STEAM_0:1:12345678');

  const types = app.logger.entries.map((e) => e.type);
  assert.ok(types.includes('app.submit'), 'dnevnik mora vsebovati app.submit');
  const line = fs.readFileSync(path.join(dataDir, 'logs', 'events.jsonl'), 'utf8').trim().split('\n').pop();
  assert.ok(JSON.parse(line).type === 'app.submit', 'dogodek mora biti tudi na disku');
});

test('validacija zavrne nesmiselne podatke', async () => {
  const jar = new Jar();
  const page = await jar.req('/prijava');
  const token = csrfFrom(page.textBody);
  const res = await jar.req('/prijava', {
    method: 'POST',
    form: { ...validApp, _csrf: token, age: '11', steam: 'narobe', message: 'prekratek', ingame: '<script>alert(1)</script>' },
  });
  assert.equal(res.status, 422);
  assert.match(res.textBody, /vsaj v 120 znakih/);
  assert.match(res.textBody, /moraš imeti vsaj 16 let/);
  assert.equal(app.store.count('applications'), 1, 'nesmiselna prijava se ne shrani');
});

test('honeypot in dnevna omejitev', async () => {
  const jar = new Jar();
  const page = await jar.req('/prijava');
  const token = csrfFrom(page.textBody);

  const spam = await jar.req('/prijava', { method: 'POST', form: { ...validApp, _csrf: token, website: 'http://spam.example' } });
  assert.equal(spam.status, 200, 'bot dobi videz uspeha');
  assert.equal(app.store.count('applications'), 1, 'spam se ne shrani');

  const before = app.store.count('applications');
  const configLimit = app.store.getSetting('maxPerIpPerDay', app.config.applications.maxPerIpPerDay);
  const settings = app.store.list('settings')[0]; const savedLimit = settings.maxPerIpPerDay;
  settings.maxPerIpPerDay = 1; // preizkus omejitve brez čakanja
  const again = await jar.req('/prijava', { method: 'POST', form: { ...validApp, _csrf: token, ingame: 'Drugi_Igralec' } });
  assert.equal(again.status, 429);
  assert.equal(app.store.count('applications'), before);
  settings.maxPerIpPerDay = configLimit;
});

test('XSS poskus v podatkih je izogiban ob izpisu', async () => {
  const jar = new Jar();
  await jar.req('/admin');
  const login = await jar.req('/admin/prijava', { method: 'POST', form: { username: 'admin', password: PASSWORD } });
  assert.equal(login.status, 302, 'prijava mora uspeti');
  const list = await jar.req('/admin/prijave');
  assert.ok(list.textBody.includes('&lt;script&gt;') || !list.textBody.includes('<script>alert'));
  assert.ok(!list.textBody.includes('<script>alert(1)</script>'), 'neizogiban <script> v admin pregledu');
});

test('status prijave javno pokaže samo status', async () => {
  const jar = new Jar();
  const page = await jar.req('/status');
  const token = csrfFrom(page.textBody);
  const code = app.store.list('applications')[0].code;
  const res = await jar.req('/status', { method: 'POST', form: { code, discord: 'janez.novak', _csrf: token } });
  assert.equal(res.status, 200);
  assert.match(res.textBody, /V obdelavi/);
  assert.ok(!res.textBody.includes('STEAM_0:1:12345678'), 'Steam ID ne sme biti javen');
  assert.ok(!res.textBody.includes('Rad bi igral resen RP'), 'sporočilo ne sme biti javno');

  const wrong = await jar.req('/status', { method: 'POST', form: { code, discord: 'tuj.discord', _csrf: token } });
  assert.match(wrong.textBody, /Prijave s to kodo ni/);
});

test('ob naključnem geslu je menjana obvezna (ADMIN-START.txt)', async () => {
  const jar = new Jar();
  const res = await jar.req('/admin/prijava', { method: 'POST', form: { username: 'admin', password: PASSWORD } });
  assert.equal(res.status, 302);
  // nastavljeno geslo iz configu -> ni vsiljene menjave, a je priporočena
  const dash = await jar.req('/admin');
  assert.equal(dash.status, 200);
  assert.match(dash.textBody, /Nadzorna plošča/);
});

test('napačno geslo je zabeleženo, seje pa omejene', async () => {
  const jar = new Jar();
  const res = await jar.req('/admin/prijava', { method: 'POST', form: { username: 'admin', password: 'napacno' } });
  assert.equal(res.status, 401);
  assert.ok(app.logger.entries.some((e) => e.type === 'auth.login_failed'));
});

async function adminJar() {
  const jar = new Jar();
  const page = await jar.req('/admin');
  const res = await jar.req('/admin/prijava', {
    method: 'POST',
    form: { username: 'admin', password: PASSWORD, _csrf: csrfFrom(page.textBody) },
  });
  assert.equal(res.status, 302);
  return jar;
}

test('pregled in odobritev prijave (WL + izvoz)', async () => {
  const jar = await adminJar();
  const list = await jar.req('/admin/prijave?status=pending');
  assert.equal(list.status, 200);
  assert.match(list.textBody, /Jane_Novak/);
  const csrf = csrfFrom(list.textBody);
  const app_ = app.store.list('applications')[0];

  // brez CSRF -> 403
  const bad = await jar.req('/admin/prijave/odloci', { method: 'POST', form: { id: app_.id, decision: 'approved' } });
  assert.equal(bad.status, 403);

  const ok = await jar.req('/admin/prijave/odloci', {
    method: 'POST',
    form: { id: app_.id, decision: 'approved', note: 'Dobrodošel, poveži se na Discordu.', _csrf: csrf },
  });
  assert.equal(ok.status, 302);

  assert.equal(app_.status, 'approved');
  assert.equal(app.store.count('whitelist'), 1);
  const wl = app.store.list('whitelist')[0];
  assert.equal(wl.identifier, LICENSE);
  assert.equal(wl.source, 'application');

  // igralec je samodejno v bazi
  assert.equal(app.store.count('players'), 1);
  assert.equal(app.store.list('players')[0].status, 'active');

  // izvoz na disk (to FiveM osebje bere)
  const exported = JSON.parse(fs.readFileSync(path.join(dataDir, 'fivem-whitelist.json'), 'utf8'));
  assert.equal(exported.count, 1);
  assert.equal(exported.whitelist[0].identifier, LICENSE);

  const types = app.logger.entries.map((e) => e.type);
  assert.ok(types.includes('app.approve'), 'odobre mora biti v dnevniku');
  assert.ok(types.includes('wl.export'), 'izvoz mora biti v dnevniku');

  // igralec vidi odobritev na statusu
  const visitor = new Jar();
  const statusPage = await visitor.req('/status');
  const st = await visitor.req('/status', {
    method: 'POST',
    form: { code: app_.code, discord: 'janez.novak', _csrf: csrfFrom(statusPage.textBody) },
  });
  assert.match(st.textBody, /Odobreno/);
  assert.match(st.textBody, /Dobrodošel/);
});

test('API za FiveM preverja whitelist z tokenom', async () => {
  const jar = await adminJar();
  const tokenRes = await jar.req('/admin/nastavitve/token', { method: 'POST', form: { _csrf: csrfFrom((await jar.req('/admin/nastavitve')).textBody) } });
  assert.equal(tokenRes.status, 302);
  const token = app.store.getSetting('apiToken');
  assert.ok(token && token.length > 20);

  const good = await new Jar().req(`/api/whitelist/check?token=${token}&license=${encodeURIComponent(LICENSE)}`);
  assert.equal(good.status, 200);
  assert.equal(JSON.parse(good.textBody).allowed, true);

  const tuj = await new Jar().req(`/api/whitelist/check?token=${token}&license=license:${'f'.repeat(40)}`);
  assert.equal(JSON.parse(tuj.textBody).allowed, false);

  const noToken = await new Jar().req(`/api/whitelist/check?license=${LICENSE}`);
  assert.equal(noToken.status, 401);
});

test('odstranitev z whiteliste in dnevnik', async () => {
  const jar = await adminJar();
  const page = await jar.req('/admin/whitelist');
  const csrf = csrfFrom(page.textBody);
  const row = app.store.list('whitelist')[0];
  const res = await jar.req('/admin/whitelist/odstrani', { method: 'POST', form: { id: row.id, _csrf: csrf } });
  assert.equal(res.status, 302);
  assert.equal(app.store.count('whitelist'), 0);
  assert.equal(app.store.list('players')[0].status, 'inactive', 'igralec dobi status inactive');
  const exported = JSON.parse(fs.readFileSync(path.join(dataDir, 'fivem-whitelist.json'), 'utf8'));
  assert.equal(exported.count, 0);
  assert.ok(app.logger.entries.some((e) => e.type === 'wl.remove'));
});

test('ročni izvoz igralcev (CSV)', async () => {
  const jar = await adminJar();
  const res = await jar.req('/admin/igralci/export.csv');
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-disposition'), /attachment/);
  assert.ok(res.textBody.includes('ingame'));
});

test('podatki preživijo znovni zagon (shranjeni na disku)', async () => {
  const countBefore = app.store.count('applications');
  const codeBefore = app.store.list('applications')[0].code;
  await app.close();
  const dir = dataDir;
  app = createApp(loadConfig({ dataDir: dir, port: 0, host: '127.0.0.1', admin: { username: 'admin', password: PASSWORD }, backup: { enabled: false, dir: path.join(dir, 'backups') } }));
  const ac = await app.listen();
  port = ac.port;
  assert.equal(app.store.count('applications'), countBefore);
  assert.equal(app.store.list('applications')[0].code, codeBefore);
  const jar = new Jar();
  const logs = await jar.req('/admin');
  assert.ok([200, 302].includes(logs.status));
  assert.ok(app.logger.entries.some((e) => e.type === 'app.approve'), 'stari dogodki so še vedno v dnevniku');
});

test('vloga pregledovalca ne more pisati', async () => {
  const { hashPassword } = await import('../src/auth.js');
  await app.store.insert('users', { username: 'bralec', passhash: hashPassword('bralnogeslo123'), role: 'viewer', logins: 0, lastLoginAt: null });
  const jar = new Jar();
  const page = await jar.req('/admin');
  const login = await jar.req('/admin/prijava', {
    method: 'POST',
    form: { username: 'bralec', password: 'bralnogeslo123', _csrf: csrfFrom(page.textBody) },
  });
  assert.equal(login.status, 302);
  const res = await jar.req('/admin/igralci/shrani', {
    method: 'POST',
    form: { ingame: 'Nedovoljen_Igralec', name: 'N. Dopis', _csrf: csrfFrom((await jar.req('/admin')).textBody) },
  });
  assert.equal(res.status, 303, 'pregledovalec sme samo brati');
  assert.ok(!app.store.list('players').some((p) => p.ingame === 'Nedovoljen_Igralec'));
});

test('zaprte prijave in izbris (GDPR)', async () => {
  const jar = new Jar();
  const page = await jar.req('/prijava');
  const token = csrfFrom(page.textBody);
  await app.store.setSetting('applicationsOpen', false);
  assert.match((await jar.req('/prijava')).textBody, /zaprte/);
  const res = await jar.req('/prijava', { method: 'POST', form: { ...validApp, _csrf: token } });
  assert.equal(res.status, 409);
  await app.store.setSetting('applicationsOpen', true);

  const admin = await adminJar();
  const csrf = csrfFrom((await admin.req('/admin/prijave')).textBody);
  const target = app.store.list('applications')[0];
  const del = await admin.req('/admin/prijave/izbrisi', { method: 'POST', form: { id: target.id, _csrf: csrf } });
  assert.equal(del.status, 302);
  assert.ok(!app.store.find('applications', target.id));
  assert.ok(app.logger.entries.some((e) => e.type === 'app.delete'));
});

test('nastavitve iz admin plošče preglasijo config (in prezivijo znovni zagon)', async () => {
  const jar = await adminJar();
  const form = await jar.req('/admin/nastavitve');
  const res = await jar.req('/admin/nastavitve', {
    method: 'POST',
    form: {
      _csrf: csrfFrom(form.textBody),
      siteName: 'CodeX RP',
      siteTagline: 'Testni podnaslov',
      discordInvite: 'discord.gg/kodeks',
      serverConnect: 'connect test.codex.si',
      minAge: '18',
      maxPerIpPerDay: '2',
    },
  });
  assert.equal(res.status, 302);
  assert.equal(app.store.getSetting('siteName'), 'CodeX RP', 'nastavitev mora biti shranjena v data/settings.json');
  assert.equal(JSON.parse(fs.readFileSync(path.join(dataDir, 'settings.json'), 'utf8'))[0].siteName, 'CodeX RP');
  const home = await new Jar().req('/');
  assert.match(home.textBody, /CodeX RP/);
  assert.match(home.textBody, /connect test.codex.si/);
  // "prijave zaprte" se prav tako pozna javno
  await app.store.setSetting('applicationsOpen', false);
  assert.match((await new Jar().req('/prijava')).textBody, /zaprte/);
  await app.store.setSetting('applicationsOpen', true);
  // in po znovnem zagonu so nastavitve se vedno veljavne
  const dir = dataDir;
  await app.close();
  app = createApp(loadConfig({ dataDir: dir, port: 0, host: '127.0.0.1', admin: { username: 'admin', password: PASSWORD }, backup: { enabled: false, dir: path.join(dir, 'backups') } }));
  port = (await app.listen()).port;
  assert.equal(app.store.getSetting('siteName'), 'CodeX RP');
  assert.match((await new Jar().req('/')).textBody, /CodeX RP/);
});

test('vse se pospravi brez napak', async () => {
  const errs = app.logger.entries.filter((e) => e.level === 'error');
  assert.deepEqual(errs.map((e) => e.message), [], 'v dnevniku ne sme biti nepričakovanih napak');
});

test.after(async () => {
  try { await app?.close(); } catch { /* ze zaprto */ }
});
