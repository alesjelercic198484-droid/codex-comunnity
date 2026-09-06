import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { ROOT } from './config.js';
import { Store } from './store.js';
import { Logger } from './logs.js';
import { AuthService, createThrottle } from './auth.js';
import { WhitelistService } from './whitelist.js';
import { liveConfig } from './services.js';
import {
  parseCookies, cookieHeader, parseBody, send, sendHtml, sendJson, redirect,
  securityHeaders, serveStatic, clientIp, isHttps,
} from './http.js';
import { publicRoutes, renderErrorPage } from './routes/public.js';
import { adminRoutes } from './routes/admin.js';
import { apiRoutes } from './routes/api.js';
import { nowIso } from './util.js';

const PUBLIC_DIR = path.join(ROOT, 'public');
const SESSION_COOKIE = 'codex_session';
const CSRF_COOKIE = 'codex_csrf';
const MAX_LOG_LINES_AT_BOOT = 20000;

/* ------------------------------- router ------------------------------- */
function compile(routes) {
  return routes.map((r) => {
    const keys = [];
    const pattern = r.path
      .split('/')
      .map((seg) => {
        if (!seg.startsWith(':')) return seg.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        keys.push(seg.slice(1));
        return '([^/]+)';
      })
      .join('/');
    return { ...r, keys, re: new RegExp(`^${pattern}/?$`) };
  });
}

function match(routes, method, pathname) {
  for (const r of routes) {
    if (r.method !== method) continue;
    const m = pathname.match(r.re);
    if (!m) continue;
    const params = {};
    r.keys.forEach((k, i) => { params[k] = decodeURIComponent(m[i + 1]); });
    return { route: r, params };
  }
  return null;
}

/* ------------------------------- CSRF -------------------------------- */
function csrfPair(secret) {
  const t = crypto.randomBytes(16).toString('base64url');
  const sig = crypto.createHmac('sha256', secret).update(t).digest('base64url').slice(0, 22);
  return { token: t, cookie: `${t}.${sig}` };
}
function csrfCookieValid(secret, cookie) {
  if (!cookie || !cookie.includes('.')) return false;
  const [t, sig] = cookie.split('.');
  const want = crypto.createHmac('sha256', secret).update(t).digest('base64url').slice(0, 22);
  const a = Buffer.from(sig);
  const b = Buffer.from(want);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** Vrne besedilo iz surovega HTML predmeta, niza ali predmeta. */
function strOf(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object' && typeof v.__raw === 'string') return v.__raw;
  if (typeof v === 'string') return v;
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

/* ------------------------------- app -------------------------------- */
export function createApp(config) {
  const startedAt = Date.now();
  const routes = compile([...publicRoutes, ...apiRoutes, ...adminRoutes]);
  let server = null;

  const logger = new Logger(path.join(config.dataDirAbs, 'logs'), {
    maxFileSizeMb: config.logs.maxFileSizeMb,
    keepRotatedFiles: config.logs.keepRotatedFiles,
    retentionDays: config.logs.retentionDays,
    memoryCap: MAX_LOG_LINES_AT_BOOT,
  });
  const store = new Store(config.dataDirAbs, { logger });
  const auth = new AuthService({ store, logger, config });
  const wl = new WhitelistService({ store, logger, config });
  const loginThrottle = createThrottle({ windowMs: 10 * 60 * 1000, max: 8, logger });
  let timers = [];

  async function boot() {
    fs.mkdirSync(config.dataDirAbs, { recursive: true });
    await logger.init();
    await store.init();
    logger.info('system', `storitev se zaganja (node ${process.version}, ${process.platform})`, {
      meta: { port: config.port, dataDir: config.dataDirAbs },
    });

    const setup = await auth.ensureAdmin({ username: config.admin.username, password: config.admin.password });
    if (setup.fresh && setup.user.generated) {
      const f = path.join(config.dataDirAbs, 'ADMIN-START.txt');
      fs.writeFileSync(f, [
        `CodeX Community - začetni dostop do admin plošče`,
        ``,
        `Naslov:  ${config.publicUrl || 'http://localhost:' + config.port}/admin`,
        `Uporabnik: ${setup.user.username}`,
        `Geslo:   ${setup.initialPassword}`,
        ``,
        `Ko se prijaviš, boš moral nastaviti novo geslo. TAKOJ POTEM IZBRIŠI TO DATOTEKO:`,
        `    PowerShell: Remove-Item -Force '${f}'`,
        `    del ${f}`,
        ``,
        `Ustvarjeno: ${nowIso()}`,
      ].join('\r\n'), 'utf8');
      logger.warn('system', `začetno geslo skrbnika je zapisano v ${f} - takoj po pridobivanju jo IZBRIŠI`, { actor: 'sistem' });
    }

    // izvoz whiteliste naj obstaja takoj, da FiveM skripta ne pade na manjkajočo datoteko
    const info = await wl.export({ actor: 'sistem', quiet: true });
    if (info.errors.length) logger.warn('wl.export', `kopiranje izvoza na nekatere poti ni uspelo`, { meta: { errors: info.errors } });
    else logger.info('system', `whitelist preverjena (aktivnih zapisov: ${info.count})`);

    // vzdrževalni cikel: seje, dnevniki, izpraznjen zapis
    timers.push(setInterval(maintenance, 15 * 60 * 1000));
    timers.push(setInterval(() => autoBackup().catch((e) => logger.error('backup', e)), 60 * 60 * 1000));
    timers.forEach((t) => t.unref?.());
    await autoBackup(true);
  }

  async function autoBackup(firstBoot = false) {
    if (!config.backup.enabled) return;
    const every = Math.max(1, Number(config.backup.everyHours) || 6) * 3600000;
    const last = store.getSetting('lastBackupAt', null);
    const age = last ? Date.now() - Date.parse(last) : Infinity;
    if (age < every) return;
    const res = await store.snapshot('avtomatsko');
    await store.setSetting('lastBackupAt', nowIso());
    await store.pruneBackups(config.backup.keepDays);
    logger.info('backup', `avtomatska varnostna kopija: ${res.dir}`, { actor: 'sistem' });
  }

  async function maintenance() {
    try {
      const purged = auth.pruneSessions();
      if (purged) logger.debug('system', `očiščenih ${purged} poteklih sej`);
      if (config.logs.retentionDays) await logger.purgeOlderThan(config.logs.retentionDays);
      await store.flush();
    } catch (err) {
      logger.error('system', err);
    }
  }

  /* ------------------------- obdelava zahteve ------------------------- */
  async function handle(req, res) {
    const t0 = process.hrtime.bigint();
    const base = liveConfig(config, store);
    const ip = clientIp(req, base.trustProxy);
    const ua = req.headers['user-agent'] || '';
    let url;
    try {
      url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    } catch {
      return send(res, 400, 'Neveljaven naslov', { 'Content-Type': 'text/plain; charset=utf-8' });
    }
    const pathname = url.pathname.replace(/\/{2,}/g, '/');

    for (const [k, v] of Object.entries(securityHeaders({
      csp: "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; form-action 'self'; base-uri 'self'; frame-ancestors 'none'; upgrade-insecure-requests",
    }))) res.setHeader(k, v);

    const cookies = parseCookies(req.headers.cookie);
    const token = cookies[SESSION_COOKIE];
    const session = auth.getSession(token);
    const user = session ? (store.find('users', session.userId) || null) : null;

    let body = {};
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      try {
        body = await parseBody(req, req.headers['content-type'] || '');
      } catch (err) {
        return send(res, err.status === 413 ? 413 : 400, 'Telo zahteve ni veljavno', { 'Content-Type': 'text/plain; charset=utf-8' });
      }
    }

    const ctx = {
      req, res, url, pathname, query: url.searchParams, params: {}, body,
      ip, ua, session, user,
      config: base, baseConfig: config,
      s: { store, auth, logger, wl, loginThrottle },
      store, logger, startedAt,
      cookies,
      origin() {
        const fwd = req.headers['x-forwarded-host'];
        const host = (base.trustProxy && fwd) ? String(fwd).split(',')[0] : (req.headers.host || `localhost:${base.port}`);
        const proto = (base.trustProxy && req.headers['x-forwarded-proto']) ? String(req.headers['x-forwarded-proto']).split(',')[0] : (isHttps(req, base) ? 'https' : 'http');
        return `${proto}://${host}`;
      },
      throttle: (k) => loginThrottle.check(k),
      throttleReset: (k) => loginThrottle.reset(k),
      setFlash(kind, text) {
        if (ctx.session) { ctx.session.flash = { kind, text }; } else { ctx._flash = { kind, text }; }
      },
      takeFlash() {
        const f = ctx.session?.flash || ctx._flash || null;
        if (ctx.session) delete ctx.session.flash;
        delete ctx._flash;
        return f;
      },
      csrfToken() {
        if (ctx.session) return ctx.session.csrf;
        const cookie = ctx.cookies[CSRF_COOKIE];
        if (csrfCookieValid(base.csrfSecret, cookie)) return cookie.split('.')[0];
        const pair = csrfPair(base.csrfSecret);
        ctx._setCsrf = pair.cookie;
        return pair.token;
      },
      cookie(name, value, opts = {}) {
        const secure = base.secureCookies === 'auto' ? isHttps(req, base) : String(base.secureCookies) === 'true';
        const parts = res.getHeader('Set-Cookie');
        const arr = parts ? (Array.isArray(parts) ? parts : [parts]) : [];
        arr.push(cookieHeader(name, value, { secure, ...opts }));
        res.setHeader('Set-Cookie', arr);
      },
      html(view, status = 200) {
        if (ctx._setCsrf) ctx.cookie(CSRF_COOKIE, ctx._setCsrf, { httpOnly: false, maxAge: 60 * 60 * 8 });
        return sendHtml(res, strOf(view), status);
      },
      text(bodyStr, headers = {}) {
        return send(res, 200, strOf(bodyStr), { 'Content-Type': 'text/plain; charset=utf-8', ...headers });
      },
      json(obj, status = 200) { return sendJson(res, obj, status); },
      download(name, type, content) {
        return send(res, 200, strOf(content), {
          'Content-Type': type,
          'Content-Disposition': `attachment; filename="${name.replace(/[^\w.\-]/g, '_')}"`,
          'Cache-Control': 'no-store',
        });
      },
      redirect(to, flashText) {
        if (flashText) ctx.setFlash('ok', flashText);
        if (ctx._setCsrf) ctx.cookie(CSRF_COOKIE, ctx._setCsrf, { httpOnly: false, maxAge: 60 * 60 * 8 });
        return redirect(res, to, 302);
      },
      login(s) {
        ctx.cookie(SESSION_COOKIE, s.token, { maxAge: Math.round(base.sessionHours * 3600), sameSite: 'Lax' });
        ctx.session = s;
        ctx.user = store.find('users', s.userId);
      },
      logout() {
        ctx.cookie(SESSION_COOKIE, '', { maxAge: 0 });
        ctx.session = null;
        ctx.user = null;
      },
      notFound(msg) { return ctx.html(renderErrorPage(ctx, { code: 404, title: 'Ne najdem strani', text: msg || '' }), 404); },
      badRequest(msg) { return ctx.html(renderErrorPage(ctx, { code: 400, title: 'Neveljavna zahteva', text: msg || '' }), 400); },
    };

    // statika (/assets/...)
    if (req.method === 'GET' && pathname.startsWith('/assets/')) {
      if (serveStatic(PUBLIC_DIR, pathname.slice('/assets'.length), req, res, { immutable: true })) return;
    }

    const found = match(routes, req.method, pathname);
    if (!found) return ctx.notFound();
    ctx.params = found.params;
    const r = found.route;
    if (process.env.DEBUG_ROUTES) console.log(`[route] ${req.method} ${pathname} -> ${r.method} ${r.path}${r.public ? ' (javno)' : ''}`);

    // zaščita: vse pod /admin zahteva sejo (razen javne rute za prijavo)
    const isAdminRoute = r.path.startsWith('/admin');
    if (isAdminRoute && !r.public) {
      if (!user) {
        logger.warn('auth.login_failed', `poskus dostopa do ${pathname} brez seje`, { ip });
        return redirect(res, '/admin', 302);
      }
      if (user.mustChangePassword && !pathname.startsWith('/admin/geslo')) {
        return redirect(res, '/admin/geslo', 302);
      }
      if (r.role === 'owner' && user.role !== 'owner') {
        logger.warn('auth.denied', `${user.username} nima pravice za ${pathname} (rabi vlogo skrbnika)`, { actor: user.username, ip });
        ctx.setFlash('bad', 'Za to akcijo potrebuješ vlogo skrbnika (owner).');
        return redirect(res, '/admin/nastavitve', 303);
      }
      if (r.role === 'write' && user.role === 'viewer') {
        logger.warn('auth.denied', `pregledovalec ${user.username} je poskusil zapisati (${pathname})`, { actor: user.username, ip });
        ctx.setFlash('bad', 'Ti imaš samo pravice branja (pregledovalec).');
        return redirect(res, '/admin', 303);
      }
    }

    // CSRF: za vse POST (razen API, ki ima svoj token)
    if (req.method === 'POST' && !r.csrfSkip && !pathname.startsWith('/api/')) {
      const provided = String(ctx.body._csrf || req.headers['x-csrf-token'] || '');
      const fromSession = ctx.session ? auth.verifyCsrf(ctx.session, provided) : false;
      const cookie = ctx.cookies[CSRF_COOKIE];
      const fromCookie = csrfCookieValid(base.csrfSecret, cookie) && String(cookie || '').split('.')[0] === provided;
      if (!fromSession && !fromCookie) {
        logger.warn('auth.csrf', `CSRF preverba ni uspela na ${pathname}`, { actor: user?.username, ip });
        return ctx.html(renderErrorPage(ctx, {
          code: 403,
          title: 'Obrazec je potekel',
          text: 'Varnostna oznaka obrazca se ne ujema. Osveži stran in poskusi znova (če imaš izklopljene piškotke, jih vklopi - brez njih oddaja ni mogoča).',
        }), 403);
      }
    }

    try {
      await r.handler(ctx);
    } catch (err) {
      const status = err.status || 500;
      logger.error('http.error', err, { actor: user?.username, ip, meta: { path: pathname, status } });
      if (!res.headersSent) {
        const wantsJson = pathname.startsWith('/api/');
        if (wantsJson) sendJson(res, { error: 'Notranja napaka strežnika.' }, status);
        else ctx.html(renderErrorPage(ctx, {
          code: status,
          title: status === 400 ? 'Neveljaven podatek' : 'Napaka strežnika',
          text: status >= 500 ? 'Dogodilo se je nekaj nepričakovanega. Podrobnosti so v dnevniku (Admin → Dnevnik).' : String(err.message || '').slice(0, 200),
        }), status);
      } else res.end();
      return;
    } finally {
      if (ctx._setCsrf && !res.headersSent) ctx.cookie(CSRF_COOKIE, ctx._setCsrf, { httpOnly: false, maxAge: 3600 * 8 });
    }

    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    if (ms > 1000) logger.debug('http.slow', `počasna zahteva ${ms.toFixed(0)} ms ${req.method} ${pathname}`, { ip });
  }

  async function listen() {
    await boot();
    server = http.createServer((req, res) => {
      handle(req, res).catch((err) => {
        logger.error('http.crash', err, { meta: { url: req.url } });
        if (!res.headersSent) send(res, 500, 'Napaka strežnika', { 'Content-Type': 'text/plain; charset=utf-8' });
      });
    });
    server.headersTimeout = 15000;
    server.requestTimeout = 30000;
    await new Promise((res) => server.listen(config.port, config.host, res));
    return server.address();
  }

  async function close() {
    timers.forEach(clearInterval);
    timers = [];
    if (server) await new Promise((r) => server.close(r));
    await store.flush();
    await store.snapshot('ob zaključku');
    await logger.info('system', 'storitev ustavljena (podatki varno zapisani)');
    await logger.close();
  }

  return { listen, close, handle, boot, logger, store, auth, wl, config };
}
