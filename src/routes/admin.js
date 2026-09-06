import crypto from 'node:crypto';
import zlib from 'node:zlib';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { nowIso, normalizeIdentifier, clampText } from '../util.js';
import { validatePlayer, validateWhitelist, validateStaff } from '../validate.js';
import { hashPassword, verifyPassword } from '../auth.js';
import {
  loginPage, mustChangePasswordPage, dashboardPage, applicationsPage, playersPage,
  whitelistPage, logsPage, dataPage, settingsPage, STATUS_LABEL,
} from '../views/admin.js';
import { liveConfig, statsFor, systemInfo, applyLiveSettings } from '../services.js';

const PER_PAGE = 25;
const num = (v, d) => Math.max(1, Number(v) || d);
const str = (v, max = 200) => clampText(v, max);
const LABELS = { players: 'Igralci', applications: 'Prijavnice', whitelist: 'Whitelist', users: 'Osebje', sessions: 'Seje' };

function base(ctx, extra = {}) {
  return { user: ctx.user, csrf: ctx.csrfToken(), flash: ctx.takeFlash(), ...extra };
}
const ok = (ctx, text) => ctx.setFlash('ok', text);

export const adminRoutes = [
  /* ----------------------- PRIJAVA / ODJAVA / GESLO ---------------------- */
  {
    method: 'GET',
    path: '/admin',
    public: true,
    handler: async (ctx) => {
      if (!ctx.user) return ctx.html(loginPage(ctx.config, { csrf: ctx.csrfToken(), flash: ctx.takeFlash() }));
      const { store, wl, logger } = ctx.s;
      const apps = store.list('applications').slice()
        .sort((a, b) => String(b.submittedAt || b.createdAt).localeCompare(String(a.submittedAt || a.createdAt)))
        .slice(0, 8);
      const players = store.list('players').slice()
        .sort((a, b) => String(b.updatedAt || '').localeCompare(String(a.updatedAt || '')))
        .slice(0, 8);
      const st = logger.stats(24);
      return ctx.html(dashboardPage(ctx.config, base(ctx, {
        stats: { ...statsFor(store), logEvents: Object.values(st.by).reduce((a, b) => a + b, 0) },
        apps,
        players,
        logs: logger.query({ limit: 8 }).rows,
        wlStats: wl.stats(),
        system: { ...systemInfo({ store, startedAt: ctx.startedAt, config: ctx.baseConfig }), lastBackup: store.getSetting('lastBackupAt', null) },
      })));
    },
  },
  {
    method: 'POST',
    path: '/admin/prijava',
    public: true,
    csrfSkip: true,
    handler: async (ctx) => {
      const { auth, logger } = ctx.s;
      const key = `login:${ctx.ip}`;
      const limit = ctx.throttle(key, 8, 10 * 60 * 1000);
      if (!limit.allowed) {
        const mins = Math.ceil(limit.retryInMs / 60000);
        logger.warn('auth.throttle', `blokada prijav z IP naslova (počakaj ${mins} min)`, { ip: ctx.ip });
        return ctx.html(loginPage(ctx.config, { error: `Preveč poskusov. Počakaj ${mins} minut in poskusi znova.`, csrf: ctx.csrfToken() }), 429);
      }
      const username = str(ctx.body.username, 40);
      const password = String(ctx.body.password || '');
      const res = await auth.verifyLogin(username, password);
      if (!res.ok) {
        logger.warn('auth.login_failed', `neuspela prijava za "${username || '(prazno)'}"`, { ip: ctx.ip });
        return ctx.html(loginPage(ctx.config, { error: 'Napačno uporabniško ime ali geslo.', csrf: ctx.csrfToken() }), 401);
      }
      ctx.throttleReset(key);
      const session = auth.createSession(res.user, { ip: ctx.ip, userAgent: ctx.ua });
      await ctx.store.update('users', res.user.id, { logins: (res.user.logins || 0) + 1, lastLoginAt: nowIso() });
      ctx.login(session);
      logger.info('auth.login', `prijava uspešna (${res.user.username})`, { actor: res.user.username, ip: ctx.ip });
      if (res.user.mustChangePassword) return ctx.redirect('/admin/geslo', 'Prijava uspešna. Zdaj nastavi svoje geslo.');
      return ctx.redirect('/admin', 'Prijava uspešna.');
    },
  },
  {
    method: 'POST',
    path: '/admin/odjava',
    handler: async (ctx) => {
      const name = ctx.user.username;
      ctx.s.auth.destroySession(ctx.session.id);
      ctx.logout();
      ctx.s.logger.info('auth.logout', `odjava (${name})`, { actor: name, ip: ctx.ip });
      return ctx.redirect('/admin', 'Odjava uspešna.');
    },
  },
  {
    method: 'GET',
    path: '/admin/geslo',
    handler: (ctx) => ctx.html(mustChangePasswordPage(ctx.config, { csrf: ctx.csrfToken() })),
  },
  {
    method: 'POST',
    path: '/admin/geslo',
    handler: async (ctx) => {
      const { auth, logger } = ctx.s;
      const p1 = String(ctx.body.password || '');
      const p2 = String(ctx.body.password2 || '');
      const firstRun = !!ctx.user.mustChangePassword;
      if (p1.length < 12 || p1 !== p2) {
        ctx.setFlash('bad', p1.length < 12 ? 'Geslo mora imeti vsaj 12 znakov.' : 'Gesli se ne ujemata.');
        return ctx.redirect(firstRun ? '/admin/geslo' : '/admin/nastavitve');
      }
      if (!firstRun) {
        const me = auth.findUser(ctx.user.username);
        if (!me || !verifyPassword(String(ctx.body.current || ''), me.passhash)) {
          logger.warn('auth.password_change', 'sprememba gesla zavrnjena (napačno trenutno geslo)', { actor: ctx.user.username, ip: ctx.ip });
          ctx.setFlash('bad', 'Trenutno geslo ni pravilno.');
          return ctx.redirect('/admin/nastavitve');
        }
      }
      await auth.setPassword(ctx.user.id, p1);
      for (const s of [...ctx.store.list('sessions')]) {
        if (s.userId === ctx.user.id && s.id !== ctx.session.id) auth.destroySession(s.id);
      }
      logger.info('auth.password_change', `geslo uporabnika ${ctx.user.username} je bilo spremenjeno`, { actor: ctx.user.username, ip: ctx.ip });
      ok(ctx, 'Geslo je shranjeno.');
      return ctx.redirect('/admin');
    },
  },

  /* ------------------------------- PRIJAVE ------------------------------- */
  {
    method: 'GET',
    path: '/admin/prijave',
    handler: async (ctx) => {
      const store = ctx.store;
      const status = str(ctx.query.get('status'), 20);
      const q = str(ctx.query.get('q'), 60).toLowerCase();
      const sort = str(ctx.query.get('sort'), 20) || 'newest';
      const page = num(ctx.query.get('page'), 1);
      let rows = store.list('applications');
      if (STATUS_LABEL[status]) rows = rows.filter((a) => a.status === status);
      if (q) {
        rows = rows.filter((a) => [a.code, a.name, a.ingame, a.discord, a.steam, a.license, a.message, a.ip]
          .some((v) => String(v || '').toLowerCase().includes(q)));
      }
      const newest = (a, b) => String(b.submittedAt || b.createdAt).localeCompare(String(a.submittedAt || a.createdAt));
      if (sort === 'oldest') rows = rows.slice().sort((a, b) => -newest(a, b));
      else if (sort === 'oldest_pending') {
        rows = rows.slice().sort((a, b) => {
          const rank = (x) => (x.status === 'pending' ? 0 : x.status === 'more_info' ? 1 : 2);
          return rank(a) - rank(b) || -newest(a, b);
        });
      } else rows = rows.slice().sort(newest);
      const total = rows.length;
      const pages = Math.max(1, Math.ceil(total / PER_PAGE));
      const p = Math.min(page, pages);
      return ctx.html(applicationsPage(ctx.config, base(ctx, {
        rows: rows.slice((p - 1) * PER_PAGE, p * PER_PAGE),
        total, page: p, pages, status, q, sort,
        open: str(ctx.query.get('id'), 40) || null,
      })));
    },
  },
  {
    method: 'POST',
    path: '/admin/prijave/odloci',
    role: 'write',
    handler: async (ctx) => {
      const { store, wl, logger } = ctx.s;
      const app = store.find('applications', str(ctx.body.id, 40));
      if (!app) { ctx.setFlash('bad', 'Te prijave ni več (je bila morda že izbrisana).'); return ctx.redirect('/admin/prijave'); }
      const decision = str(ctx.body.decision, 20);
      const note = str(ctx.body.note, 1000);
      if (!['approved', 'denied', 'more_info'].includes(decision)) {
        ctx.setFlash('bad', 'Neveljna odločitev.');
        return ctx.redirect(`/admin/prijave?id=${app.id}`);
      }
      const prevStatus = app.status;
      const prevWl = app.license ? wl.find(app.license) : null;

      if (decision === 'approved') {
        if (!app.license) {
          ctx.setFlash('bad', 'Prijava nima FiveM identifierja. Dodaj ga v Igralci (ali najprej vpiši v Discordu) in poskusi znova.');
          return ctx.redirect(`/admin/prijave?id=${app.id}`);
        }
        const rawExp = str(ctx.body.expires, 20);
        const expires = rawExp && !Number.isNaN(Date.parse(rawExp)) ? new Date(`${rawExp}T23:59:59`).toISOString() : null;
        const { row, created } = await wl.add({
          identifier: app.license,
          ingame: app.ingame,
          discord: app.discord,
          expires,
          note: note.slice(0, 300) || `prijava ${app.code}`,
          addedBy: ctx.user.username,
          source: 'application',
          applicationId: app.id,
        });
        await store.update('applications', app.id, { status: 'approved', reviewNote: note, reviewedAt: nowIso(), reviewedBy: ctx.user.username });
        const lic = normalizeIdentifier(app.license);
        const existing = store.list('players').find((p) => normalizeIdentifier(p.license) === lic || (p.ingame || '').toLowerCase() === String(app.ingame).toLowerCase());
        const pdata = {
          ingame: app.ingame, name: app.name, discord: app.discord, steam: app.steam, license: app.license,
          status: 'active', notes: note.slice(0, 500), wlExpires: row.expires || null, applicationId: app.id,
        };
        if (existing) await store.update('players', existing.id, pdata);
        else await store.insert('players', { ...pdata, job: '' });
        const info = await wl.export({ actor: ctx.user.username });
        logger.info('app.approve', `prijava ${app.code} odobrena - ${app.ingame} je na whitelisti (${created ? 'dodano' : 'posodobljeno'})`, {
          actor: ctx.user.username, ip: ctx.ip, meta: { identifier: app.license, expires: row.expires, note },
        });
        ok(ctx, `Prijava ${app.code} odobrena, ${app.ingame} je na whitelisti (izvoz: ${info.count} zapisov).`);
        return ctx.redirect('/admin/prijave');
      }

      await store.update('applications', app.id, { status: decision, reviewNote: note, reviewedAt: nowIso(), reviewedBy: ctx.user.username });
      if (prevStatus === 'approved') {
        if (prevWl) await wl.remove(prevWl.id);
        const player = store.list('players').find((p) => normalizeIdentifier(p.license) === normalizeIdentifier(app.license));
        if (player) await store.update('players', player.id, { status: 'inactive', wlExpires: null });
        await wl.export({ actor: ctx.user.username });
        logger.warn('wl.remove', `whitelist umaknjen (${app.ingame || app.code}) - ${decision === 'denied' ? 'zavrnjeno po odobritvi' : 'potrebno dodatno preverjanje'}`, {
          actor: ctx.user.username, ip: ctx.ip, meta: { identifier: app.license },
        });
      }
      logger.info(decision === 'denied' ? 'app.deny' : 'app.update', `prijava ${app.code} → ${STATUS_LABEL[decision]}`, {
        actor: ctx.user.username, ip: ctx.ip, meta: { note },
      });
      ok(ctx, `Prijava ${app.code}: ${STATUS_LABEL[decision]}. Igralec je o tem obveščen na strani Status.`);
      return ctx.redirect('/admin/prijave');
    },
  },
  {
    method: 'POST',
    path: '/admin/prijave/izbrisi',
    role: 'owner',
    handler: async (ctx) => {
      const { store, logger } = ctx.s;
      const app = store.find('applications', str(ctx.body.id, 40));
      if (!app) { ctx.setFlash('bad', 'Zapisa ni.'); return ctx.redirect('/admin/prijave'); }
      await store.remove('applications', app.id);
      logger.warn('app.delete', `prijava ${app.code} (${app.ingame}) izbrisana (npr. na zahtevo igralca)`, { actor: ctx.user.username, ip: ctx.ip });
      ok(ctx, `Prijava ${app.code} je izbrisana.`);
      return ctx.redirect('/admin/prijave');
    },
  },
  { method: 'GET', path: '/admin/prijave/export', handler: (ctx) => ctx.download('prijavnice.csv', 'text/csv; charset=utf-8', ctx.store.exportCsv('applications')) },

  /* ------------------------------- IGRALCI ------------------------------ */
  {
    method: 'GET',
    path: '/admin/igralci',
    handler: async (ctx) => {
      const store = ctx.store;
      const q = str(ctx.query.get('q'), 60).toLowerCase();
      const status = str(ctx.query.get('status'), 20);
      const page = num(ctx.query.get('page'), 1);
      let rows = store.list('players');
      if (status) rows = rows.filter((p) => p.status === status);
      if (q) rows = rows.filter((p) => [p.ingame, p.name, p.discord, p.license, p.steam, p.job, p.notes].some((v) => String(v || '').toLowerCase().includes(q)));
      rows = rows.slice().sort((a, b) => String(b.updatedAt || '').localeCompare(String(a.updatedAt || '')));
      const total = rows.length;
      const pages = Math.max(1, Math.ceil(total / PER_PAGE));
      const p = Math.min(page, pages);
      const editId = str(ctx.query.get('id'), 40);
      const form = editId ? store.find('players', editId) : null;
      if (editId && !form) { ctx.setFlash('bad', 'Igralca ni v bazi.'); return ctx.redirect('/admin/igralci'); }
      return ctx.html(playersPage(ctx.config, base(ctx, {
        rows: rows.slice((p - 1) * PER_PAGE, p * PER_PAGE),
        total, page: p, pages, q, status, form: form || {}, errors: {},
      })));
    },
  },
  {
    method: 'POST',
    path: '/admin/igralci/shrani',
    role: 'write',
    handler: async (ctx) => {
      const { store, logger } = ctx.s;
      const id = str(ctx.body.id, 40);
      const existing = id ? store.find('players', id) : null;
      const { ok: valid, errors, values } = validatePlayer(ctx.body, existing || {});
      const dup = store.list('players').find((p) => p.id !== existing?.id && p.ingame && p.ingame.toLowerCase() === values.ingame.toLowerCase());
      if (dup && !existing) errors.ingame = `Igralec "${dup.ingame}" je že v bazi.`;
      if (!valid || (dup && !existing)) {
        return ctx.html(playersPage(ctx.config, base(ctx, {
          rows: [], total: store.count('players'), page: 1, pages: 1, q: '', status: '',
          form: { ...values, ...ctx.body, id: id || '', ingame: values.ingame, notes: values.notes },
          errors, flash: { kind: 'bad', text: 'Preveri označena polja - nič ni shranjeno.' },
        })), 422);
      }
      if (existing) {
        const licenseChanged = values.license && normalizeIdentifier(existing.license) !== normalizeIdentifier(values.license);
        await store.update('players', existing.id, values);
        logger.info('player.update', `igralec ${values.ingame} posodobljen`, { actor: ctx.user.username, ip: ctx.ip, meta: licenseChanged ? { license: `${existing.license} → ${values.license}` } : undefined });
        ok(ctx, `Igralec ${values.ingame} je shranjen.`);
      } else {
        await store.insert('players', values);
        logger.info('player.create', `nov igralec ${values.ingame} ročno dodan`, { actor: ctx.user.username, ip: ctx.ip });
        ok(ctx, `Igralec ${values.ingame} je dodan.`);
      }
      return ctx.redirect('/admin/igralci');
    },
  },
  {
    method: 'POST',
    path: '/admin/igralci/izbrisi',
    role: 'owner',
    handler: async (ctx) => {
      const { store, logger } = ctx.s;
      const p = store.find('players', str(ctx.body.id, 40));
      if (!p) { ctx.setFlash('bad', 'Zapisa ni.'); return ctx.redirect('/admin/igralci'); }
      await store.remove('players', p.id);
      logger.warn('player.delete', `igralec ${p.ingame} izbrisan iz baze`, { actor: ctx.user.username, ip: ctx.ip, meta: { license: p.license } });
      ok(ctx, 'Igralec je izbrisan. Whitelist ni bila spremenjena - uredi jo posebej, če mora biti.');
      return ctx.redirect('/admin/igralci');
    },
  },
  { method: 'GET', path: '/admin/igralci/export.csv', handler: (ctx) => ctx.download('igralci.csv', 'text/csv; charset=utf-8', ctx.store.exportCsv('players')) },

  /* ------------------------------ WHITELIST ------------------------------ */
  {
    method: 'GET',
    path: '/admin/whitelist',
    handler: async (ctx) => {
      const { store, wl } = ctx.s;
      const cfg = ctx.config;
      const q = str(ctx.query.get('q'), 60).toLowerCase();
      let rows = store.list('whitelist').slice().sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
      if (q) rows = rows.filter((w) => [w.identifier, w.ingame, w.discord, w.note].some((v) => String(v || '').toLowerCase().includes(q)));
      const stats = wl.stats();
      return ctx.html(whitelistPage(cfg, base(ctx, {
        rows: rows.slice(0, 300),
        total: stats.total,
        q,
        errors: {},
        exportInfo: {
          file: cfg.whitelist.exportFile,
          exists: stats.fileExists,
          count: stats.active,
          copyTo: cfg.whitelist.copyTo || [],
        },
      })));
    },
  },
  {
    method: 'POST',
    path: '/admin/whitelist/dodaj',
    role: 'write',
    handler: async (ctx) => {
      const { wl, logger } = ctx.s;
      const { ok: valid, errors, values } = validateWhitelist(ctx.body);
      if (!valid) {
        ctx.setFlash('bad', Object.values(errors).join(' '));
        return ctx.redirect('/admin/whitelist');
      }
      const expires = values.forever || !values.expires ? null : new Date(`${values.expires}T23:59:59`).toISOString();
      const { created } = await wl.add({ ...values, expires, addedBy: ctx.user.username, source: 'admin' });
      const info = await wl.export({ actor: ctx.user.username });
      logger.info('wl.add', `${created ? 'dodano' : 'posodobljeno'} na whitelist: ${values.identifier}${values.ingame ? ` (${values.ingame})` : ''}`, {
        actor: ctx.user.username, ip: ctx.ip, meta: { expires, note: values.note },
      });
      ok(ctx, `${values.identifier} je ${created ? 'dodana' : 'posodobljena'} na whitelist. Izvoz: ${info.count} zapisov${info.errors.length ? ` (napaka pri kopiranju: ${info.errors.join('; ')})` : ''}.`);
      return ctx.redirect('/admin/whitelist');
    },
  },
  {
    method: 'POST',
    path: '/admin/whitelist/odstrani',
    role: 'write',
    handler: async (ctx) => {
      const { wl, store, logger } = ctx.s;
      const row = await wl.remove(str(ctx.body.id, 40));
      if (!row) { ctx.setFlash('bad', 'Zapisa ni.'); return ctx.redirect('/admin/whitelist'); }
      await wl.export({ actor: ctx.user.username });
      const player = store.list('players').find((p) => normalizeIdentifier(p.license) === normalizeIdentifier(row.identifier));
      if (player) await store.update('players', player.id, { status: 'inactive', wlExpires: null });
      logger.warn('wl.remove', `whitelist odstranjen: ${row.identifier}${row.ingame ? ` (${row.ingame})` : ''}`, { actor: ctx.user.username, ip: ctx.ip });
      ok(ctx, `${row.identifier} je odstranjen s whiteliste.`);
      return ctx.redirect('/admin/whitelist');
    },
  },
  {
    method: 'POST',
    path: '/admin/whitelist/izvozi',
    role: 'write',
    handler: async (ctx) => {
      const info = await ctx.s.wl.export({ actor: ctx.user.username });
      ok(ctx, `Izvoz zapisan (${info.count} aktivnih zapisov)${info.errors.length ? ` - napake: ${info.errors.join('; ')}` : ''}.`);
      return ctx.redirect('/admin/whitelist');
    },
  },
  {
    method: 'GET',
    path: '/admin/whitelist/export.json',
    handler: (ctx) => ctx.download('whitelist.json', 'application/json; charset=utf-8', JSON.stringify({
      generatedAt: nowIso(), count: ctx.s.wl.active.length, whitelist: ctx.s.wl.active,
    }, null, 2)),
  },
  { method: 'GET', path: '/admin/whitelist/export.csv', handler: (ctx) => ctx.download('whitelist.csv', 'text/csv; charset=utf-8', ctx.store.exportCsv('whitelist')) },

  /* --------------------------------- LOGI -------------------------------- */
  {
    method: 'GET',
    path: '/admin/logi',
    handler: async (ctx) => {
      const logger = ctx.s.logger;
      const limit = Math.min(2000, num(ctx.query.get('limit'), 200));
      const level = str(ctx.query.get('level'), 10);
      const type = str(ctx.query.get('type'), 30);
      const q = str(ctx.query.get('q'), 80);
      const data = logger.query({ level, type, q, limit });
      return ctx.html(logsPage(ctx.config, base(ctx, {
        data,
        level: ['debug', 'info', 'warn', 'error'].includes(level) ? level : '',
        type,
        q,
        limit,
        allTypes: [...new Set(logger.entries.map((e) => e.type))],
      })));
    },
  },
  {
    method: 'GET',
    path: '/admin/logi/prenesi.txt',
    handler: async (ctx) => ctx.download(`logi-${new Date().toISOString().slice(0, 10)}.txt`, 'text/plain; charset=utf-8', await ctx.s.logger.readableText()),
  },
  {
    method: 'GET',
    path: '/admin/logi/prenesi.jsonl',
    handler: async (ctx) => ctx.download(`logi-${new Date().toISOString().slice(0, 10)}.jsonl`, 'application/x-ndjson; charset=utf-8', await ctx.s.logger.rawText()),
  },
  {
    method: 'POST',
    path: '/admin/logi/pocisti',
    role: 'owner',
    handler: async (ctx) => {
      const days = Math.max(1, Number(ctx.body.days) || ctx.config.logs.retentionDays);
      const n = await ctx.s.logger.purgeOlderThan(days);
      ctx.s.logger.warn('logs.purge', `izbrisanih ${n} starih zapisov (dnevniki, starejši od ${days} dni)`, { actor: ctx.user.username, ip: ctx.ip });
      ok(ctx, `Počiščeno ${n} zapisov, starejših od ${days} dni.`);
      return ctx.redirect('/admin/logi');
    },
  },

  /* ---------------------------- PODATKI & IZVOZ -------------------------- */
  {
    method: 'GET',
    path: '/admin/podatki',
    handler: async (ctx) => {
      const { store } = ctx.s;
      const cfg = ctx.baseConfig;
      const sizes = ['players', 'applications', 'whitelist', 'users'].map((key) => {
        const file = store.file(key);
        let bytes = 0;
        try { bytes = fs.statSync(file).size; } catch { /* datoteka še ni napisana */ }
        return { key, name: LABELS[key] || key, file: cfg.dataDir + '/' + key + '.json', kb: Math.max(1, Math.round(bytes / 1024)), count: store.count(key) };
      });
      let backups = [];
      try {
        const days = (await fsp.readdir(cfg.backup.dirAbs)).filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d)).sort().reverse();
        backups = days.slice(0, 10).map(async (day) => ({ day, files: (await fsp.readdir(path.join(cfg.backup.dirAbs, day))).length }));
        backups = await Promise.all(backups);
      } catch { /* še ni varnostnih kopij */ }
      return ctx.html(dataPage(ctx.config, base(ctx, {
        sizes, backups,
        apps: store.list('applications').filter((a) => a.status === 'pending').slice(0, 5),
      })));
    },
  },
  {
    method: 'GET',
    path: '/admin/podatki/izvozi/all.json',
    handler: (ctx) => ctx.download('codex-izvoz.json', 'application/json; charset=utf-8', ctx.store.exportDump()),
  },
  {
    method: 'GET',
    path: '/admin/podatki/izvozi/:file',
    handler: async (ctx) => {
      const [key, ext] = String(ctx.params.file).split('.');
      const allowed = ['players', 'applications', 'whitelist', 'users'];
      if (!allowed.includes(key) || !['json', 'csv'].includes(ext)) return ctx.badRequest('Izvoz ni mogoč.');
      if (ext === 'csv') return ctx.download(`${key}.csv`, 'text/csv; charset=utf-8', ctx.store.exportCsv(key));
      return ctx.download(`${key}.json`, 'application/json; charset=utf-8', JSON.stringify({ exportedAt: nowIso(), collection: key, rows: ctx.store.list(key) }, null, 2));
    },
  },
  {
    method: 'POST',
    path: '/admin/podatki/kopija',
    role: 'write',
    handler: async (ctx) => {
      const res = await ctx.store.snapshot('manual');
      await ctx.store.setSetting('lastBackupAt', nowIso());
      await ctx.store.pruneBackups(ctx.config.backup.keepDays);
      ctx.s.logger.info('backup', `ročna varnostna kopija shranjena v ${res.dir}`, { actor: ctx.user.username, ip: ctx.ip });
      ok(ctx, 'Varnostna kopija je narejena.');
      return ctx.redirect('/admin/podatki');
    },
  },
  {
    method: 'POST',
    path: '/admin/podatki/obnovi',
    role: 'owner',
    handler: async (ctx) => {
      const day = str(ctx.body.day, 12);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) { ctx.setFlash('bad', 'Neveljaven dan kopije.'); return ctx.redirect('/admin/podatki'); }
      const root = path.join(ctx.baseConfig.backup.dirAbs, day);
      const done = [];
      for (const name of ['players', 'applications', 'whitelist', 'users']) {
        try {
          const rows = JSON.parse(zlib.gunzipSync(await fsp.readFile(path.join(root, `${name}.json.gz`))).toString('utf8'));
          if (Array.isArray(rows)) { await ctx.store.replaceAll(name, rows); done.push(`${name}: ${rows.length}`); }
        } catch (err) {
          ctx.setFlash('bad', `Obnovitev ${name} ni uspela: ${err.message}`);
          ctx.s.logger.error('backup.restore', `napaka pri obnovitvi ${name} iz ${day}`, { actor: ctx.user.username, meta: { error: err.message } });
        }
      }
      ctx.s.logger.warn('backup.restore', `podatki obnovljeni iz kopije ${day} (${done.join(', ') || 'nič'})`, { actor: ctx.user.username, ip: ctx.ip });
      await ctx.s.wl.export({ actor: ctx.user.username, quiet: true });
      if (done.length) ok(ctx, `Obnovljeno: ${done.join(', ')}.`);
      return ctx.redirect('/admin/podatki');
    },
  },

  /* ------------------------------ NASTAVITVE ----------------------------- */
  {
    method: 'GET',
    path: '/admin/nastavitve',
    handler: async (ctx) => {
      const { store } = ctx.s;
      const live = liveConfig(ctx.baseConfig, store);
      return ctx.html(settingsPage(live, base(ctx, {
        live: { ...live, publicUrl: live.publicUrl || ctx.origin() },
        staff: store.list('users').map(({ passhash, generated, ...u }) => u),
        token: live.api.token || '',
        errors: {},
      })));
    },
  },
  {
    method: 'POST',
    path: '/admin/nastavitve',
    role: 'owner',
    handler: async (ctx) => {
      const { store, logger } = ctx.s;
      await applyLiveSettings(store, ctx.body);
      const open = ctx.body.applicationsOpen === 'on';
      ok(ctx, 'Nastavitve so shranjene.');
      logger.info('settings.update', `nastavitve shranjene (prijavnice: ${open ? 'ODPRA' : 'ZAPRTE'})`, {
        actor: ctx.user.username,
        ip: ctx.ip,
        meta: { siteName: store.getSetting('siteName'), minAge: store.getSetting('minAge'), maxPerIpPerDay: store.getSetting('maxPerIpPerDay') },
      });
      return ctx.redirect('/admin/nastavitve');
    },
  },
  {
    method: 'POST',
    path: '/admin/nastavitve/token',
    role: 'owner',
    handler: async (ctx) => {
      const token = crypto.randomBytes(24).toString('base64url');
      await ctx.store.setSetting('apiToken', token);
      ctx.s.logger.info('settings.update', 'API token za FiveM je bil zamenjan', { actor: ctx.user.username, ip: ctx.ip });
      ok(ctx, 'Nov API token je ustvarjen. Prepiši ga v nastavitve FiveM strežnika; prejšnji je takoj neveljaven.');
      return ctx.redirect('/admin/nastavitve');
    },
  },
  {
    method: 'POST',
    path: '/admin/osebje/dodaj',
    role: 'owner',
    handler: async (ctx) => {
      const { store, auth, logger } = ctx.s;
      const { ok: valid, errors, values } = validateStaff(ctx.body);
      if (!valid) {
        ctx.setFlash('bad', Object.values(errors).join(' '));
        return ctx.redirect('/admin/nastavitve');
      }
      if (auth.findUser(values.username)) { ctx.setFlash('bad', 'Uporabnik s tem imenom že obstaja.'); return ctx.redirect('/admin/nastavitve'); }
      await store.insert('users', {
        username: values.username,
        passhash: hashPassword(values.password),
        role: values.role,
        mustChangePassword: true,
        created: nowIso(),
        createdBy: ctx.user.username,
        logins: 0,
        lastLoginAt: null,
      });
      logger.info('admin.create', `dodan ${values.role === 'viewer' ? 'pregledovalec' : 'moderator'}: ${values.username}`, { actor: ctx.user.username, ip: ctx.ip });
      ok(ctx, `Uporabnik ${values.username} je dodan. Ob prvi prijavi mora nastaviti svoje geslo.`);
      return ctx.redirect('/admin/nastavitve');
    },
  },
  {
    method: 'POST',
    path: '/admin/osebje/izbrisi',
    role: 'owner',
    handler: async (ctx) => {
      const { store, auth, logger } = ctx.s;
      const u = store.find('users', str(ctx.body.id, 40));
      if (!u) { ctx.setFlash('bad', 'Uporabnika ni.'); return ctx.redirect('/admin/nastavitve'); }
      if (u.id === ctx.user.id) { ctx.setFlash('bad', 'Svojega računa ne moreš izbrisati.'); return ctx.redirect('/admin/nastavitve'); }
      if (u.role === 'owner' && store.list('users').filter((x) => x.role === 'owner').length <= 1) {
        ctx.setFlash('bad', 'Edinega skrbnika (owner) ni mogoče izbrisati.');
        return ctx.redirect('/admin/nastavitve');
      }
      for (const s of [...store.list('sessions')]) if (s.userId === u.id) auth.destroySession(s.id);
      await store.remove('users', u.id);
      logger.warn('admin.delete', `uporabnik ${u.username} odstranjen, vse njegove seje uničene`, { actor: ctx.user.username, ip: ctx.ip });
      ok(ctx, `Uporabnik ${u.username} je odstranjen.`);
      return ctx.redirect('/admin/nastavitve');
    },
  },
  {
    method: 'POST',
    path: '/admin/osebje/geslo',
    role: 'owner',
    handler: async (ctx) => {
      const { store, logger } = ctx.s;
      const u = store.find('users', str(ctx.body.id, 40));
      if (!u) { ctx.setFlash('bad', 'Uporabnika ni.'); return ctx.redirect('/admin/nastavitve'); }
      const pass = `Codex-${crypto.randomBytes(6).toString('base64url')}`;
      await store.update('users', u.id, { passhash: hashPassword(pass), mustChangePassword: true });
      logger.warn('auth.password_change', `geslo uporabnika ${u.username} ponastavljeno na začasno`, { actor: ctx.user.username, ip: ctx.ip });
      ctx.setFlash('warn', `Začasno geslo za ${u.username}: ${pass}. Pošlji ga po varnem kanalu; ob prijavi ga bo moral spremeniti.`);
      return ctx.redirect('/admin/nastavitve');
    },
  },
];

