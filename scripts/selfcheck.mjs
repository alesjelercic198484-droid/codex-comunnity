/**
 * Samopreveritev namestitve: zazene aplikacijo v CASNI zacetni mapi, obiskuje vse
 * strani in izvede vse kljucne akcije (prijavnica -> odobritev -> whitelist -> dnevnik).
 * Podatkov na VPS-u NE spremenja (dela v osvezni zacasni mapi).
 *   node scripts/selfcheck.mjs        (ali: npm run selfcheck)
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { hashPassword } from '../src/auth.js';

const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-self-'));
const config = loadConfig({
  dataDir, port: 0, host: '127.0.0.1',
  admin: { username: 'admin', password: 'SelfCheck12345!' },
  backup: { enabled: true, everyHours: 6, keepDays: 3, dir: path.join(dataDir, 'backups') },
  whitelist: { exportFile: 'fivem-whitelist.json', copyTo: [] },
  api: { enabled: true, token: 'selfcheck-token-123' },
});
const app = createApp(config);
const ac = await app.listen();
const base = `http://127.0.0.1:${ac.port}`;

/* vzorčni podatki */
const store = app.store;
await store.insert('players', { ingame: 'Test_Igralec', name: 'Test Test', discord: 'test.t', steam: 'STEAM_0:1:123456', license: 'license:' + 'c'.repeat(40), status: 'active', job: 'Mehanik', notes: '', wlExpires: null });
await store.insert('applications', { code: 'CDX-TEST1', name: 'Miha Demo', ingame: 'Miha_Demo', discord: 'miha.demo', steam: 'STEAM_0:1:654321', license: 'license:' + 'd'.repeat(40), age: 20, message: 'Dolg opis prijave, da je validno besedilo za test. Dolg opis prijave, da je validno besedilo za test. Dolg opis prijave.', status: 'pending', ip: '127.0.0.1', submittedAt: new Date().toISOString(), reviewNote: '', reviewedAt: null, reviewedBy: null });
await store.insert('applications', { code: 'CDX-TEST2', name: '<Tudi/XSS>', ingame: 'Slike_Test', discord: 'slike.test', steam: '', license: '', age: 18, message: '<img src=x onerror=alert(1)> dolg opis, dolg opis, dolg opis, dolg opis, dolg opis, dolg opis, dolg opis!!', status: 'pending', ip: '127.0.0.1', submittedAt: new Date().toISOString(), reviewNote: '', reviewedAt: null, reviewedBy: null });
await store.insert('users', { username: 'mod', passhash: hashPassword('ModGeslo123456'), role: 'moderator', logins: 0, lastLoginAt: null, mustChangePassword: false });

class Jar {
  constructor() { this.c = new Map(); }
  header() { return [...this.c].map(([k, v]) => `${k}=${v}`).join('; '); }
  absorb(sc) { for (const line of sc || []) { const [pair] = line.split(';'); const i = pair.indexOf('='); this.c.set(pair.slice(0, i).trim(), pair.slice(i + 1).trim()); } }
  async req(p, { method = 'GET', form } = {}) {
    const h = { cookie: this.header() };
    let body;
    if (form) { body = new URLSearchParams(form).toString(); h['content-type'] = 'application/x-www-form-urlencoded'; }
    const res = await fetch(base + p, { method, headers: h, body, redirect: 'manual' });
    this.absorb(res.headers.getSetCookie());
    res.text = await res.text();
    return res;
  }
}
const csrf = (t) => /name="_csrf" value="([^"]+)"/.exec(t)?.[1] || '';
let fails = 0;
const check = (name, cond, extra = '') => {
  if (cond) console.log(`  ok   ${name}`);
  else { fails += 1; console.log(`  FAIL ${name} ${extra}`); }
};
const clean = (t) => !t.includes('[object Object]') && !t.includes('&lt;object') && !/\$\{/.test(t);

const publicJar = new Jar();
for (const p of ['/', '/prijava', '/status', '/pravila', '/robots.txt', '/sitemap.xml', '/assets/site.css', '/assets/site.js', '/assets/favicon.svg', '/api/health']) {
  const r = await publicJar.req(p);
  check(`GET ${p}`, r.status === 200 && clean(r.text), `status=${r.status}`);
}

const jar = new Jar();
await jar.req('/admin');
const login = await jar.req('/admin/prijava', { method: 'POST', form: { username: 'admin', password: 'SelfCheck12345!', _csrf: csrf((await jar.req('/admin')).text) } });
check('admin login', login.status === 302, `status=${login.status}`);

const pages = ['/admin', '/admin/prijave', '/admin/prijave?status=pending&sort=oldest_pending', '/admin/prijave?q=Miha',
  '/admin/prijave?id=' + store.list('applications')[0].id, '/admin/igralci', '/admin/igralci?status=active',
  '/admin/igralci?id=' + store.list('players')[0].id, '/admin/whitelist', '/admin/whitelist?q=lic',
  '/admin/logi', '/admin/logi?level=info&type=app&limit=500', '/admin/podatki', '/admin/nastavitve',
  '/admin/geslo', '/admin/logi/prenesi.txt', '/admin/logi/prenesi.jsonl', '/admin/igralci/export.csv',
  '/admin/prijave/export', '/admin/whitelist/export.json', '/admin/whitelist/export.csv',
  '/admin/podatki/izvozi/all.json', '/admin/podatki/izvozi/players.csv', '/admin/podatki/izvozi/sessions.json'];
const expect400 = true;
for (const p of pages) {
  const r = await jar.req(p);
  const want400 = p.includes('sessions');   // seje namerno niso izvozljive
  check(`GET ${p}`, (want400 ? r.status === 400 : r.status === 200) && clean(r.text), `status=${r.status}`);
}
const noauth = await new Jar().req('/admin/igralci');
check('brez seje -> preusmeritev', noauth.status === 302);
check('neobstoč zapis -> 404/302', [302, 404].includes((await jar.req('/admin/igralci?id=neki')).status));

/* akcije */
const token = csrf((await jar.req('/admin/igralci')).text);
const addP = await jar.req('/admin/igralci/shrani', { method: 'POST', form: { _csrf: token, ingame: 'Nov_Igralec', name: 'Novi Test', discord: 'novi.test', steam: 'STEAM_0:1:111111', license: 'license:' + 'e'.repeat(40), status: 'trial', job: 'Policija', notes: 'opomba z <b>html</b>', wlExpires: '' } });
check('dodaj igralca', addP.status === 302 && store.list('players').some((p) => p.ingame === 'Nov_Igralec'));

const wt = csrf((await jar.req('/admin/whitelist')).text);
const addW = await jar.req('/admin/whitelist/dodaj', { method: 'POST', form: { _csrf: wt, identifier: 'license:' + 'f'.repeat(40), ingame: 'Rocen_vnos', discord: 'rocni.vnos', note: 'test', expires: '', forever: 'on' } });
check('dodaj na whitelist', addW.status === 302 && store.count('whitelist') === 1);
check('izvoz zapisan', fs.existsSync(path.join(dataDir, 'fivem-whitelist.json')) && fs.existsSync(path.join(dataDir, 'fivem-whitelist.txt')) && fs.existsSync(path.join(dataDir, 'fivem-whitelist.array.json')));

const approve = await jar.req('/admin/prijave/odloci', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/prijave')).text), id: store.list('applications')[0].id, decision: 'approved', note: 'Sprejet, prijetno igranje.' } });
check('odobri prijavo', approve.status === 302 && store.list('applications')[0].status === 'approved');
const deny = await jar.req('/admin/prijave/odloci', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/prijave')).text), id: store.list('applications')[1].id, decision: 'denied', note: 'Manjka identifier.' } });
check('zavrnitev prijave brez identifierja', deny.status === 302 && store.list('applications')[1].status === 'denied');

const vis = new Jar();
const visPage = await vis.req('/status');
const st = await vis.req('/status', { method: 'POST', form: { _csrf: csrf(visPage.text), code: 'CDX-TEST1', discord: 'miha.demo' } });
check('status: odobre + opomba', st.status === 200 && /Odobreno/.test(st.text) && /Sprejet, prijetno/.test(st.text));
check('XSS v admin seznamu je varen', !/<img src=x/.test((await jar.req('/admin/prijave?q=Slike')).text) && /&lt;img src=x/.test((await jar.req('/admin/prijave?q=Slike')).text));

const setSave = await jar.req('/admin/nastavitve', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/nastavitve')).text), siteName: 'CodeX Community', siteTagline: 'Testni podnaslov', discordInvite: 'discord.gg/test', serverConnect: 'connect test.si', applicationsOpen: 'on', minAge: '17', maxPerIpPerDay: '4' } });
check('shrani nastavitve', setSave.status === 302 && app.store.getSetting('minAge') === 17);
const tok = await jar.req('/admin/nastavitve/token', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/nastavitve')).text) } });
check('nov API token', tok.status === 302 && (app.store.getSetting('apiToken') || '').length > 20);

const staff = await jar.req('/admin/osebje/dodaj', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/nastavitve')).text), username: 'novi_mod', password: 'ZajetoGeslo1234', role: 'viewer' } });
check('dodaj osebje', staff.status === 302 && !!app.auth.findUser('novi_mod'));
const modJar = new Jar();
await modJar.req('/admin');
const modLogin = await modJar.req('/admin/prijava', { method: 'POST', form: { username: 'mod', password: 'ModGeslo123456' } });
check('moderator prijava', modLogin.status === 302);
const modTry = await modJar.req('/admin/nastavitve', { method: 'POST', form: { _csrf: csrf((await modJar.req('/admin/nastavitve')).text), siteName: 'Hack' } });
check('moderator ne sme pisati nastavitev', modTry.status === 303);
const modWhitelist = await modJar.req('/admin/whitelist/dodaj', { method: 'POST', form: { _csrf: csrf((await modJar.req('/admin/whitelist')).text), identifier: 'license:' + '1'.repeat(40), forever: 'on' } });
check('moderator sme urejati whitelist', modWhitelist.status === 302 && store.count('whitelist') === 3);

const backup = await jar.req('/admin/podatki/kopija', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/podatki')).text) } });
check('rocna kopija', backup.status === 302 && fs.readdirSync(path.join(dataDir, 'backups')).length >= 1);
const purge = await jar.req('/admin/logi/pocisti', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/logi')).text), days: '900' } });
check('ciscenje dnevnikov', purge.status === 302);
const rmWl = await jar.req('/admin/whitelist/odstrani', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/whitelist')).text), id: store.list('whitelist')[0].id } });
check('odstrani z whitelist', rmWl.status === 302 && store.count('whitelist') === 2);
const expo = await jar.req('/admin/whitelist/izvozi', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin/whitelist')).text) } });
check('ročni izvoz', expo.status === 302);
const pw = await jar.req('/admin/geslo', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin')).text), current: 'SelfCheck12345!', password: 'NovoGeslo123456', password2: 'NovoGeslo123456' } });
check('sprememba gesla', pw.status === 302);
const relogin = await new Jar().req('/admin/prijava', { method: 'POST', form: { username: 'admin', password: 'NovoGeslo123456' } });
check('prijava z novim geslom', relogin.status === 302);
const out = await jar.req('/admin/odjava', { method: 'POST', form: { _csrf: csrf((await jar.req('/admin')).text) } });
check('odjava', out.status === 302);

const approvedLic = store.list('applications')[0].license;
const api = await new Jar().req(`/api/whitelist/check?token=${app.store.getSetting('apiToken')}&license=${encodeURIComponent(approvedLic)}`);
check('API check (veljaven token)', api.status === 200 && JSON.parse(api.text).allowed === true, api.text);
const touch = await new Jar().req(`/api/whitelist/touch?token=${app.store.getSetting('apiToken')}`, { method: 'POST', form: { license: approvedLic } });
check('API touch', touch.status === 200 && /allowed/.test(touch.text));

const errs = app.logger.entries.filter((e) => e.level === 'error');
check('brez napak v dnevniku', errs.length === 0, errs.map((e) => e.message).join(' | '));

await app.close();
console.log(`\n${fails === 0 ? 'VSE V REDU' : fails + ' NAPAK'} (temp: ${dataDir})`);
process.exit(fails ? 1 : 0);
