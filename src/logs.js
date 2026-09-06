import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { nowIso } from './util.js';

/**
 * Dnevnik (log) vseh dogodkov - append-only JSONL na disk + spominski indeks.
 * To je tisto, kar uporabnik kliče "loge": kdaj se je kdo prijavil, kdo je oddal
 * prijavnico, kdo jo je odobril, spremembe whitelist, napake ...
 */
export const LEVELS = ['debug', 'info', 'warn', 'error'];
export const TYPES = [
  'app.submit', 'app.approve', 'app.deny', 'app.delete', 'app.closed',
  'auth.login', 'auth.login_failed', 'auth.logout', 'auth.password_change', 'auth.throttle',
  'player.create', 'player.update', 'player.delete',
  'wl.add', 'wl.remove', 'wl.export',
  'admin.create', 'admin.delete',
  'settings.update', 'backup', 'system', 'http.error',
];

/** Vrnje uporabno besedilo iz stringa ali Error objekta. */
function fmtMsg(v) {
  if (v instanceof Error) {
    const where = v.stack ? v.stack.split('\n').slice(1, 2).join('').trim() : '';
    return `${v.message}${where ? ` (${where})` : ''}`;
  }
  if (v && typeof v === 'object') {
    try { return JSON.stringify(v); } catch { return String(v); }
  }
  return String(v ?? '');
}

export class Logger {
  constructor(dir, opts = {}) {
    this.dir = dir;
    this.file = path.join(dir, 'events.jsonl');
    this.maxBytes = (opts.maxFileSizeMb || 8) * 1024 * 1024;
    this.keep = opts.keepRotatedFiles ?? 6;
    this.retentionDays = opts.retentionDays || 90;
    this.memoryCap = opts.memoryCap || 20000;
    this.entries = [];
    this.seq = 0;
    this.stream = null;
    this.bytes = 0;
  }

  async init() {
    await fsp.mkdir(this.dir, { recursive: true });
    await this.loadFromDisk();
    await this.rotateIfNeeded();
    this.stream = fs.createWriteStream(this.file, { flags: 'a' });
    this.stream.on('error', (err) => console.error('[logs] pisanje ni uspelo:', err.message));
    if (fs.existsSync(this.file)) this.bytes = fs.statSync(this.file).size;
  }

  async loadFromDisk() {
    const files = [this.file];
    for (let i = 1; i <= this.keep; i += 1) files.push(path.join(this.dir, `events.${i}.jsonl`));
    const rows = [];
    for (const f of files) {
      if (!fs.existsSync(f)) continue;
      try {
        const text = await fsp.readFile(f, 'utf8');
        for (const line of text.split('\n')) {
          if (!line.trim()) continue;
          try {
            const obj = JSON.parse(line);
            if (obj && obj.ts) rows.push(obj);
          } catch { /* vrstica iz polovičnega zapisa - ignoriraj */ }
        }
      } catch { /* ignore */ }
      if (rows.length > this.memoryCap) break;
    }
    rows.sort((a, b) => String(a.ts).localeCompare(String(b.ts)));
    this.entries = rows.slice(-this.memoryCap);
    this.seq = this.entries.length;
  }

  rotateIfNeeded() {
    if (!fs.existsSync(this.file)) return Promise.resolve();
    const size = fs.statSync(this.file).size;
    if (size < this.maxBytes) return Promise.resolve();
    return (async () => {
      for (let i = this.keep; i >= 1; i -= 1) {
        const from = i === 1 ? this.file : path.join(this.dir, `events.${i - 1}.jsonl`);
        const to = path.join(this.dir, `events.${i}.jsonl`);
        if (fs.existsSync(from)) await fsp.rename(from, to).catch(() => {});
      }
      this.bytes = 0;
    })();
  }

  /**
   * Zabeleži dogodek.
   * @param {'debug'|'info'|'warn'|'error'} level
   * @param {string} type  npr. 'app.approve'
   * @param {string} message  človeško besedilo (slovensko)
   * @param {{actor?:string, ip?:string, meta?:object}} extra
   */
  log(level, type, message, extra = {}) {
    const entry = {
      seq: (this.seq += 1),
      ts: extra.ts || nowIso(),
      level: LEVELS.includes(level) ? level : 'info',
      type,
      message: String(message ?? ''),
      actor: extra.actor || 'sistem',
      ip: extra.ip || '',
      meta: extra.meta && Object.keys(extra.meta).length ? extra.meta : undefined,
    };
    this.entries.push(entry);
    if (this.entries.length > this.memoryCap) this.entries.splice(0, this.entries.length - this.memoryCap);
    if (this.stream) {
      const line = `${JSON.stringify(entry)}\n`;
      this.stream.write(line);
      this.bytes += Buffer.byteLength(line);
      if (this.bytes >= this.maxBytes) this.rotateStream();
    }
    if (entry.level === 'error') console.error(`[log:error] ${entry.type} ${entry.message}`);
    return entry;
  }

  info(type, msg, extra) {
    if (msg === undefined) return this.log('info', 'system', String(type), extra);
    return this.log('info', type, fmtMsg(msg), extra);
  }

  warn(type, msg, extra) {
    if (msg === undefined) return this.log('warn', 'system', fmtMsg(type), extra);
    return this.log('warn', type, fmtMsg(msg), extra);
  }

  error(type, msg, extra = {}) {
    if (msg === undefined) return this.log('error', 'system', fmtMsg(type), extra);
    return this.log('error', typeof type === 'string' ? type : 'system', fmtMsg(msg ?? type), extra);
  }

  debug(type, msg, extra) {
    if (msg === undefined) return this.log('debug', 'system', fmtMsg(type), extra);
    return this.log('debug', type, fmtMsg(msg), extra);
  }

  async rotateStream() {
    try {
      await new Promise((res) => this.stream.end(res));
    } catch { /* ignore */ }
    await this.rotateIfNeeded();
    this.stream = fs.createWriteStream(this.file, { flags: 'a' });
  }

  /** Iskanje po dnevniku (za admin pregled). */
  query({ q = '', level = '', type = '', limit = 200, offset = 0 } = {}) {
    const needle = String(q).toLowerCase().trim();
    let rows = this.entries.slice().reverse();
    if (level) rows = rows.filter((r) => r.level === level);
    if (type) rows = rows.filter((r) => r.type === type || r.type.startsWith(`${type}.`));
    if (needle) {
      rows = rows.filter((r) =>
        `${r.message} ${r.actor} ${r.type} ${r.ip} ${r.meta ? JSON.stringify(r.meta) : ''}`
          .toLowerCase()
          .includes(needle));
    }
    const total = rows.length;
    return { total, rows: rows.slice(offset, offset + limit) };
  }

  stats(hours = 24) {
    const cutoff = Date.now() - hours * 3600000;
    const by = {};
    let errors = 0;
    for (const r of this.entries) {
      if (Date.parse(r.ts) < cutoff) continue;
      by[r.type] = (by[r.type] || 0) + 1;
      if (r.level === 'error') errors += 1;
    }
    return { by, errors };
  }

  /** Surove vrstice za prenos (vključno z rotiranimi datotekami). */
  async rawText() {
    const files = [this.file];
    for (let i = 1; i <= this.keep; i += 1) files.push(path.join(this.dir, `events.${i}.jsonl`));
    let out = '';
    for (const f of files) {
      if (!fs.existsSync(f)) continue;
      out += await fsp.readFile(f, 'utf8');
    }
    return out;
  }

  /** Človeška različica dnevnika (.txt) - lažje branje v Notepadu. */
  async readableText() {
    const data = this.query({ limit: this.entries.length });
    return data.rows
      .slice()
      .reverse()
      .map((r) => `${r.ts}  [${r.level.toUpperCase().padEnd(5)}] ${r.type.padEnd(18)} ${r.actor}@${r.ip || '-'} | ${r.message}${r.meta ? ` | ${JSON.stringify(r.meta)}` : ''}`)
      .join('\n');
  }

  async purgeOlderThan(days) {
    const cutoff = Date.now() - days * 86400000;
    const before = this.entries.length;
    this.entries = this.entries.filter((r) => Date.parse(r.ts) >= cutoff);
    await this.rewriteFromMemory();
    return before - this.entries.length;
  }

  async rewriteFromMemory() {
    const tmp = `${this.file}.tmp`;
    await fsp.writeFile(tmp, this.entries.map((r) => JSON.stringify(r)).join('\n') + (this.entries.length ? '\n' : ''), 'utf8');
    await new Promise((res) => this.stream.end(res)).catch(() => {});
    await fsp.rm(this.file, { force: true }).catch(() => {});
    await fsp.rename(tmp, this.file).catch(() => {});
    this.stream = fs.createWriteStream(this.file, { flags: 'a' });
    this.bytes = fs.existsSync(this.file) ? fs.statSync(this.file).size : 0;
  }

  async close() {
    if (!this.stream) return;
    await new Promise((res) => this.stream.end(res)).catch(() => {});
    this.stream = null;
  }
}
