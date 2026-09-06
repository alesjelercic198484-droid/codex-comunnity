import crypto from 'node:crypto';
import { nowIso, safeEqual } from './util.js';

/* ---------------------------- gesla (scrypt) ---------------------------- */
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };

export function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = crypto.scryptSync(String(password), salt, SCRYPT.keylen, {
    N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p, maxmem: 64 * 1024 * 1024,
  });
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString('base64')}$${key.toString('base64')}`;
}

export function verifyPassword(password, stored) {
  if (typeof stored !== 'string') return false;
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, N, r, p, saltB64, keyB64] = parts;
  let key;
  try {
    key = crypto.scryptSync(String(password), Buffer.from(saltB64, 'base64'), Buffer.from(keyB64, 'base64').length, {
      N: Number(N), r: Number(r), p: Number(p), maxmem: 256 * 1024 * 1024,
    });
  } catch {
    return false;
  }
  return safeEqual(key.toString('base64'), keyB64);
}

/* ------------------------------ omejevanje ------------------------------ */
/** Preprost ventil za IP: omeji število poskusov v oknu. */
export function createThrottle({ windowMs = 15 * 60 * 1000, max = 10, logger } = {}) {
  const hits = new Map();
  const timer = setInterval(() => {
    const now = Date.now();
    for (const [k, v] of hits) if (now - v.start > windowMs) hits.delete(k);
  }, windowMs);
  timer.unref?.();
  return {
    check(key) {
      const now = Date.now();
      const rec = hits.get(key);
      if (!rec || now - rec.start > windowMs) {
        hits.set(key, { start: now, count: 1 });
        return { allowed: true, remaining: max - 1, retryInMs: 0 };
      }
      rec.count += 1;
      const retryInMs = Math.max(0, rec.start + windowMs - now);
      if (rec.count > max) {
        logger?.warn?.('auth.throttle', `prevec poskusov z ${key}`, { ip: key });
        return { allowed: false, remaining: 0, retryInMs };
      }
      return { allowed: true, remaining: max - rec.count, retryInMs };
    },
    reset(key) { hits.delete(key); },
    stop() { clearInterval(timer); },
  };
}

/* ------------------------------- seje / CSRF ----------------------------- */
export class AuthService {
  constructor({ store, logger, config }) {
    this.store = store;
    this.logger = logger;
    this.config = config;
    this.secret = config.csrfSecret;
    this.sessionHours = Number(config.sessionHours || 12);
  }

  /* --- uporabniki (skrbniki) --- */
  /**
   * Ob prvem zagonu ustvari prvega skrbnika.
   * Vrne { user, initialPassword, fresh }. Če gesla ni v configu, se ustvari
   * naključno in ga zapiso v data/ADMIN-START.txt (samo tam, nikoli v GitHub).
   */
  async ensureAdmin({ username, password }) {
    const users = this.store.list('users');
    if (users.length) return { user: users[0], fresh: false };
    const given = String(password || '').trim();
    const weak = given.length < 8;
    const initial = weak ? `Codex-${crypto.randomBytes(6).toString('base64url')}` : given;
    const user = await this.store.insert('users', {
      username: String(username || 'admin').trim().toLowerCase() || 'admin',
      passhash: hashPassword(initial),
      role: 'owner',
      generated: weak,
      mustChangePassword: weak,
      logins: 0,
      lastLoginAt: null,
    });
    this.logger.info('system', `ustvarjen skrbniški račun "${user.username}" (${weak ? 'naključno začetno geslo - preberi data/ADMIN-START.txt' : 'geslo iz nastavitev, menjavo priporočamo v Nastavitve'})`);
    return { user, initialPassword: initial, fresh: true };
  }

  findUser(username) {
    const u = String(username || '').trim().toLowerCase();
    return this.store.list('users').find((x) => x.username === u) || null;
  }

  async verifyLogin(username, password) {
    const user = this.findUser(username);
    if (!user) {
      verifyPassword(password || 'x', hashPassword('x')); // enaka cena časa kot ob obstoječem uporabniku
      return { ok: false, reason: 'napačno geslo ali uporabnik' };
    }
    if (!user.passhash || !verifyPassword(password || '', user.passhash)) {
      return { ok: false, reason: 'napačno geslo ali uporabnik', user };
    }
    return { ok: true, user };
  }

  async setPassword(userId, newPassword) {
    const passhash = hashPassword(newPassword);
    return this.store.update('users', userId, { passhash, mustChangePassword: false, passwordChangedAt: nowIso() });
  }

  /* --- seje --- */
  createSession(user, meta = {}) {
    const token = crypto.randomBytes(32).toString('base64url');
    const csrf = crypto.randomBytes(24).toString('base64url');
    const session = {
      id: crypto.randomUUID(),
      token,
      csrf,
      userId: user.id,
      username: user.username,
      role: user.role,
      ip: meta.ip || '',
      userAgent: meta.userAgent || '',
      createdAt: nowIso(),
      lastSeenAt: nowIso(),
      expiresAt: new Date(Date.now() + this.sessionHours * 3600000).toISOString(),
    };
    this.store.list('sessions').push(session);
    this.store.persist('sessions');
    return session;
  }

  getSession(token) {
    if (!token) return null;
    const sessions = this.store.list('sessions');
    const s = sessions.find((x) => safeEqual(x.token, token));
    if (!s) return null;
    if (Date.parse(s.expiresAt) < Date.now()) {
      this.destroySession(s.id);
      return null;
    }
    s.lastSeenAt = nowIso();
    return s;
  }

  destroySession(id) {
    const sessions = this.store.list('sessions');
    const i = sessions.findIndex((s) => s.id === id);
    if (i !== -1) {
      sessions.splice(i, 1);
      this.store.persist('sessions');
      return true;
    }
    return false;
  }

  pruneSessions() {
    const sessions = this.store.list('sessions');
    const keepRows = sessions.filter((s) => Date.parse(s.expiresAt) > Date.now());
    if (keepRows.length !== sessions.length) this.store.replaceAll('sessions', keepRows);
    return sessions.length - keepRows.length;
  }

  /** Podpisan, a kratek žeton za API dostop (FiveM skripta). */
  makeApiToken(seed) {
    return crypto.createHmac('sha256', this.secret).update(String(seed)).digest('base64url').slice(0, 43);
  }

  checkApiToken(candidate) {
    const expected = this.config.api?.token || '';
    if (!expected) return false;
    return safeEqual(candidate || '', expected);
  }

  csrfFor(session) {
    return session?.csrf || '';
  }

  verifyCsrf(session, provided) {
    if (!session?.csrf) return false;
    return safeEqual(session.csrf, provided || '');
  }
}
