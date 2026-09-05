#!/usr/bin/env node
'use strict';

/**
 * CodeX Community – WL (whitelist) strežnik
 * Čisti Node.js, brez zunanjih odvisnosti.
 *
 * Funkcije:
 *  - registracija/prijava uporabnikov (gesla hashirana s scrypt)
 *  - vloge: igralec / moderator / administrator (preko staff kode ob registraciji)
 *  - WL prijavnice: igralec vidi SAMO svoje, moderator/admin vidijo VSE
 *  - pregled prijav (odobri/zavrni z opombo), admin upravlja vloge uporabnikov
 *  - podatki se shranjujejo v data/db.json
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = Number(process.env.PORT) || 8000;
const HOST = process.env.HOST || '0.0.0.0';
const ROOT = __dirname;
const DATA_DIR = path.join(ROOT, 'data');
const DB_FILE = path.join(DATA_DIR, 'db.json');

// ============================================================
// STAFF KODE – spremeni jih po želji (le-te vnesejo novi
// moderatorji/administratorji v polje "Staff koda" ob registraciji):
//   CODEX-MOD-2026   -> moderator
//   CODEX-ADMIN-2026 -> administrator
// ============================================================
const MODERATOR_CODE = 'CODEX-MOD-2026';
const ADMIN_CODE = 'CODEX-ADMIN-2026';

const SESSION_COOKIE = 'wl_session';
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 dni
const ROLES = ['player', 'moderator', 'administrator'];
const ROLE_SL = { player: 'Igralec', moderator: 'Moderator', administrator: 'Administrator' };

// ---------------- Shramba (data/db.json) ----------------
let db = null;

function emptyDb() {
  return { users: [], sessions: {}, applications: [], counters: { user: 0, application: 0 } };
}

function loadDb() {
  try {
    db = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
  } catch {
    db = emptyDb();
  }
  if (!Array.isArray(db.users)) db.users = [];
  if (typeof db.sessions !== 'object' || db.sessions === null) db.sessions = {};
  if (!Array.isArray(db.applications)) db.applications = [];
  if (!db.counters) db.counters = { user: 0, application: 0 };
  // počisti potekle seje
  const now = Date.now();
  for (const [token, s] of Object.entries(db.sessions)) {
    if (!s || typeof s.expiresAt !== 'number' || s.expiresAt < now) delete db.sessions[token];
  }
  saveDb();
}

function saveDb() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const tmp = DB_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(db, null, 2));
  fs.renameSync(tmp, DB_FILE);
}

// ---------------- Pomožne funkcije ----------------
function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return salt + ':' + hash;
}

function verifyPassword(password, stored) {
  try {
    const [salt, hash] = String(stored).split(':');
    const test = crypto.scryptSync(password, salt, 64);
    return crypto.timingSafeEqual(Buffer.from(hash, 'hex'), test);
  } catch {
    return false;
  }
}

function publicUser(u) {
  return { id: u.id, username: u.username, role: u.role, createdAt: u.createdAt };
}

function json(res, code, obj) {
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(obj));
}

function fail(res, code, message) {
  json(res, code, { error: message });
}

function httpError(code, message) {
  const e = new Error(message);
  e.statusCode = code;
  return e;
}

function parseCookies(req) {
  const out = {};
  const header = req.headers.cookie;
  if (!header) return out;
  for (const part of header.split(';')) {
    const i = part.indexOf('=');
    if (i > -1) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

function currentUser(req) {
  const token = parseCookies(req)[SESSION_COOKIE];
  if (!token) return null;
  const s = db.sessions[token];
  if (!s || s.expiresAt < Date.now()) return null;
  return db.users.find((u) => u.id === s.userId) || null;
}

function readBody(req, limit = 100 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(httpError(413, 'Prevelika zahteva.'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(httpError(400, 'Neveljaven JSON.'));
      }
    });
    req.on('error', reject);
  });
}

function requireAuth(req, res) {
  const user = currentUser(req);
  if (!user) throw httpError(401, 'Niste prijavljeni.');
  return user;
}

function requireStaff(req, res) {
  const user = requireAuth(req, res);
  if (user.role !== 'moderator' && user.role !== 'administrator') {
    throw httpError(403, 'Nimate dovoljenj za ta ukrep (potrebna je vloga moderatorja/administratorja).');
  }
  return user;
}

function requireAdmin(req, res) {
  const user = requireAuth(req, res);
  if (user.role !== 'administrator') {
    throw httpError(403, 'Nimate dovoljenj za ta ukrep (potrebna je vloga administratorja).');
  }
  return user;
}

function setSessionCookie(res, token) {
  res.setHeader(
    'Set-Cookie',
    `${SESSION_COOKIE}=${token}; HttpOnly; Path=/; SameSite=Lax; Max-Age=${Math.floor(SESSION_TTL_MS / 1000)}`
  );
}

function clearSessionCookie(res) {
  res.setHeader('Set-Cookie', `${SESSION_COOKIE}=; HttpOnly; Path=/; SameSite=Lax; Max-Age=0`);
}

function createSession(res, userId) {
  const token = crypto.randomBytes(32).toString('hex');
  db.sessions[token] = { userId, expiresAt: Date.now() + SESSION_TTL_MS };
  saveDb();
  setSessionCookie(res, token);
}

// ---------------- API ----------------
async function handleApi(req, res, pathname) {
  const method = req.method;

  // ----Registracija----
  if (method === 'POST' && pathname === '/api/register') {
    const body = await readBody(req);
    const username = String(body.username || '').trim();
    const password = String(body.password || '');
    const staffCode = String(body.staffCode || '').trim();

    if (!/^[a-zA-Z0-9_]{3,24}$/.test(username)) {
      throw httpError(400, 'Uporabniško ime naj ima 3–24 znakov (crke, številke, _).');
    }
    if (password.length < 6) throw httpError(400, 'Geslo mora imeti vsaj 6 znakov.');
    if (staffCode && staffCode !== MODERATOR_CODE && staffCode !== ADMIN_CODE) {
      throw httpError(400, 'Neveljavna staff koda.');
    }

    let role = 'player';
    if (staffCode === ADMIN_CODE) role = 'administrator';
    else if (staffCode === MODERATOR_CODE) role = 'moderator';

    if (db.users.some((u) => u.username.toLowerCase() === username.toLowerCase())) {
      throw httpError(409, 'Uporabniško ime je že zasedeno.');
    }

    const user = {
      id: ++db.counters.user,
      username,
      passwordHash: hashPassword(password),
      role,
      createdAt: new Date().toISOString(),
    };
    db.users.push(user);
    saveDb();
    createSession(res, user.id);
    return json(res, 200, { user: publicUser(user) });
  }

  // ----Prijava----
  if (method === 'POST' && pathname === '/api/login') {
    const body = await readBody(req);
    const username = String(body.username || '').trim();
    const password = String(body.password || '');
    const user = db.users.find((u) => u.username.toLowerCase() === username.toLowerCase());
    if (!user || !verifyPassword(password, user.passwordHash)) {
      throw httpError(401, 'Napačno uporabniško ime ali geslo.');
    }
    createSession(res, user.id);
    return json(res, 200, { user: publicUser(user) });
  }

  // ----Odjava----
  if (method === 'POST' && pathname === '/api/logout') {
    const token = parseCookies(req)[SESSION_COOKIE];
    if (token && db.sessions[token]) {
      delete db.sessions[token];
      saveDb();
    }
    clearSessionCookie(res);
    return json(res, 200, { ok: true });
  }

  // ----Trenutni uporabnik----
  if (method === 'GET' && pathname === '/api/me') {
    const user = requireAuth(req, res);
    return json(res, 200, { user: publicUser(user) });
  }

  // ----Seznam prijav (igralec: samo svoje; staff: vse)----
  if (method === 'GET' && pathname === '/api/applications') {
    const user = requireAuth(req, res);
    const isStaff = user.role === 'moderator' || user.role === 'administrator';
    const list = isStaff
      ? db.applications
      : db.applications.filter((a) => a.userId === user.id);
    const sorted = [...list].sort((a, b) => b.id - a.id).map((a) => {
      const out = {
        id: a.id,
        userId: a.userId,
        rpName: a.rpName,
        age: a.age,
        discordTag: a.discordTag,
        steamHex: a.steamHex,
        rpExperience: a.rpExperience,
        motivation: a.motivation,
        status: a.status,
        reviewNote: a.reviewNote || '',
        reviewedBy: a.reviewedBy || null,
        createdAt: a.createdAt,
        reviewedAt: a.reviewedAt || null,
      };
      if (isStaff) out.username = a.username;
      return out;
    });
    return json(res, 200, { scope: isStaff ? 'all' : 'own', applications: sorted });
  }

  // ----Oddaja prijave----
  if (method === 'POST' && pathname === '/api/applications') {
    const user = requireAuth(req, res);
    const body = await readBody(req);
    const rpName = String(body.rpName || '').trim();
    const age = Number(body.age);
    const discordTag = String(body.discordTag || '').trim();
    const steamHex = String(body.steamHex || '').trim();
    const rpExperience = String(body.rpExperience || '').trim();
    const motivation = String(body.motivation || '').trim();

    if (rpName.length < 3 || rpName.length > 64) throw httpError(400, 'RP ime in priimek naj imata 3–64 znakov.');
    if (!Number.isInteger(age) || age < 13 || age > 99) throw httpError(400, 'Starost naj bo med 13 in 99 leti.');
    if (discordTag.length < 2 || discordTag.length > 64) throw httpError(400, 'Discord tag naj ima 2–64 znakov.');
    if (steamHex.length < 4 || steamHex.length > 64) throw httpError(400, 'Steam HEX naj ima 4–64 znakov.');
    if (rpExperience.length < 10 || rpExperience.length > 2000) throw httpError(400, 'Izkušnje naj imajo 10–2000 znakov.');
    if (motivation.length < 20 || motivation.length > 4000) throw httpError(400, 'Motivacija naj ima 20–4000 znakov.');

    if (db.applications.some((a) => a.userId === user.id && a.status === 'pending')) {
      throw httpError(409, 'Že imate prijavo v obdelavi. Počakajte na odločitev moderatorjev.');
    }

    const app = {
      id: ++db.counters.application,
      userId: user.id,
      username: user.username,
      rpName,
      age,
      discordTag,
      steamHex,
      rpExperience,
      motivation,
      status: 'pending',
      reviewNote: '',
      reviewedBy: null,
      createdAt: new Date().toISOString(),
      reviewedAt: null,
    };
    db.applications.push(app);
    saveDb();
    return json(res, 200, { application: app });
  }

  // ----Pregled prijave (moderator/admin)----
  if (method === 'POST' && pathname === '/api/applications/review') {
    const user = requireStaff(req, res);
    const body = await readBody(req);
    const id = Number(body.id);
    const status = String(body.status || '');
    const note = String(body.note || '').trim();

    if (status !== 'approved' && status !== 'denied') throw httpError(400, 'Status mora biti "approved" ali "denied".');
    if (note.length > 500) throw httpError(400, 'Opomba naj ima največ 500 znakov.');

    const app = db.applications.find((a) => a.id === id);
    if (!app) throw httpError(404, 'Prijave ni mogoče najti.');
    if (app.userId === user.id) throw httpError(403, 'Svoje prijave ne morete pregledovati.');

    app.status = status;
    app.reviewNote = note;
    app.reviewedBy = user.username;
    app.reviewedAt = new Date().toISOString();
    saveDb();
    return json(res, 200, { application: app });
  }

  // ----Admin: seznam uporabnikov----
  if (method === 'GET' && pathname === '/api/users') {
    requireAdmin(req, res);
    return json(res, 200, { users: db.users.map(publicUser) });
  }

  // ----Admin: sprememba vloge----
  if (method === 'POST' && pathname === '/api/users/role') {
    const admin = requireAdmin(req, res);
    const body = await readBody(req);
    const id = Number(body.id);
    const role = String(body.role || '');

    if (!ROLES.includes(role)) throw httpError(400, 'Neveljavna vloga.');
    if (id === admin.id) throw httpError(400, 'Svoje vloge ne morete spremeniti.');

    const user = db.users.find((u) => u.id === id);
    if (!user) throw httpError(404, 'Uporabnika ni mogoče najti.');

    user.role = role;
    saveDb();
    return json(res, 200, { user: publicUser(user) });
  }

  throw httpError(404, 'Neznan API klic.');
}

// ----Statične datoteke----
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
};

function serveStatic(req, res, pathname) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return fail(res, 405, 'Metoda ni dovoljena.');
  }
  const rel = pathname === '/' ? '/index.html' : pathname;
  const filePath = path.normalize(path.join(ROOT, rel));
  if (!filePath.startsWith(ROOT)) return fail(res, 403, 'Zavrnjeno.');

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end('<h1>404 – stran ne obstaja</h1><p><a href="/">Nazaj na domačo stran</a></p>');
      return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
    });
    res.end(data);
  });
}

// ----Strežnik----
loadDb();

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const pathname = decodeURIComponent(url.pathname);
    if (pathname.startsWith('/api/')) {
      await handleApi(req, res, pathname);
    } else {
      serveStatic(req, res, pathname);
    }
  } catch (e) {
    if (!res.headersSent) fail(res, e.statusCode || 500, e.message || 'Napaka strežnika.');
  }
});

server.listen(PORT, HOST, () => {
  console.log('CodeX Community WL strežnik teče na http://' + HOST + ':' + PORT);
  console.log('  Staff koda za MODERATORJA:    ' + MODERATOR_CODE);
  console.log('  Staff koda za ADMINISTRATORJA: ' + ADMIN_CODE);
  console.log('  Podatki: ' + DB_FILE);
});
