import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import zlib from 'node:zlib';
import { newId, nowIso, sleep } from './util.js';

/**
 * Shramba brez zunanjih odvisnosti: vsak zbirka je en JSON file v data/.
 * - zapis je serializiran (per-collection queue) in atomic (tmp + preimenovanje)
 * - odporen na Windows (antivirus drži datoteko -> ponovni poskusi)
 * - enostaven za varnostno kopiranje: prekopiraj mapo data/
 */
export const COLLECTIONS = ['users', 'players', 'applications', 'whitelist', 'sessions', 'settings'];

const EXPORTABLE = ['users', 'players', 'applications', 'whitelist'];

export class Store {
  constructor(dir, { logger = console } = {}) {
    this.dir = dir;
    this.logger = logger;
    this.rows = new Map();
    this.queue = new Map();
    this.writes = 0;
    this.lastBackup = 0;
  }

  file(name) {
    return path.join(this.dir, `${name}.json`);
  }

  async init() {
    await fsp.mkdir(this.dir, { recursive: true });
    for (const name of COLLECTIONS) {
      let rows = [];
      const file = this.file(name);
      if (fs.existsSync(file)) {
        try {
          const parsed = JSON.parse(await fsp.readFile(file, 'utf8'));
          if (Array.isArray(parsed)) rows = parsed.filter((r) => r && typeof r === 'object');
        } catch (err) {
          // Pokvarjena datoteka -> ohrani original in začni znova iz varnostne kopije.
          const corruptFile = `${file}.corrupt-${Date.now()}`;
          await fsp.rename(file, corruptFile).catch(() => {});
          this.logger.error(`[store] ${name}.json pokvarjen (${err.message}); premaknjeno v ${corruptFile}`);
          for (const cand of await this.backupCandidates(name)) {
            try {
              const parsed = JSON.parse(cand.text);
              if (Array.isArray(parsed)) {
                rows = parsed.filter((r) => r && typeof r === 'object');
                this.logger.warn(`[store] ${name}.json obnovljen iz ${cand.from} (${rows.length} zapisov)`);
                break;
              }
            } catch { /* poskusi naslednjo kopijo */ }
          }
        }
      }
      this.rows.set(name, rows);
      this.queue.set(name, Promise.resolve());
    }
  }

  async backupCandidates(name) {
    const out = [];
    if (!fs.existsSync(this.dir)) return out;
    const days = (await fsp.readdir(this.dir)).filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d));
    days.sort().reverse();
    for (const d of days.slice(0, 7)) {
      const f = path.join(this.dir, 'backups', d, `${name}.json.gz`);
      if (!fs.existsSync(f)) continue;
      try {
        out.push({ from: f, text: (await zlib.gunzipSync(fs.readFileSync(f))).toString('utf8') });
      } catch { /* ignore */ }
    }
    return out;
  }

  /* ---------------- branje ---------------- */
  list(name) {
    const rows = this.rows.get(name);
    if (!rows) throw new Error(`neznana zbirka: ${name}`);
    return rows;
  }

  find(name, id) {
    return this.list(name).find((r) => r.id === id) || null;
  }

  filter(name, predicate) {
    return this.list(name).filter(predicate);
  }

  count(name) {
    return this.list(name).length;
  }

  /* ---------------- pisanje ---------------- */
  async insert(name, record) {
    const row = { id: newId(), createdAt: nowIso(), updatedAt: nowIso(), ...record };
    this.list(name).push(row);
    await this.persist(name);
    return row;
  }

  async update(name, id, patch) {
    const row = this.find(name, id);
    if (!row) return null;
    Object.assign(row, patch, { updatedAt: nowIso() });
    await this.persist(name);
    return row;
  }

  async remove(name, id) {
    const rows = this.list(name);
    const i = rows.findIndex((r) => r.id === id);
    if (i === -1) return false;
    rows.splice(i, 1);
    await this.persist(name);
    return true;
  }

  async replaceAll(name, rows) {
    this.rows.set(name, rows);
    await this.persist(name);
  }

  async setSetting(key, value) {
    return this.settingsStore.set(key, value);
  }

  getSetting(key, fallback = undefined) {
    const v = this.list('settings')[0]?.[key];
    return v === undefined ? fallback : v;
  }

  /**
   * Nastavitve, ki jih ureja admin plošča (data/settings.json).
   * Vrne referenco na vrstico + asinhroni set(); prazna vrednost pomeni
   * "vrni na privzeto iz config.json".
   */
  get settingsStore() {
    const rows = this.list('settings');
    if (!rows.length) rows.push({ id: 'settings', createdAt: nowIso() });
    const row = rows[0];
    const self = this;
    return {
      row,
      async set(key, value) {
        if (value === undefined || value === null || value === '') delete row[key];
        else row[key] = value;
        row.updatedAt = nowIso();
        await self.persist('settings');
        return row;
      },
    };
  }

  /**
   * Vrstni red zapisov: počakaj na prejšnji zapis te zbirke, nato zapiši.
   * writeAtomic: tmp -> (zamenjava z majhnimi ponovitvami, ker Windows včasih zaklene datoteko)
   */
  persist(name) {
    const prev = this.queue.get(name) || Promise.resolve();
    const next = prev.then(() => this.writeAtomic(name)).catch((err) => {
      this.logger.error(`[store] pisanje ${name}.json ni uspelo:`, err.message || err);
    });
    this.queue.set(name, next);
    return next;
  }

  async writeAtomic(name) {
    const target = this.file(name);
    const body = `${JSON.stringify(this.list(name), null, 2)}\n`;
    const tmp = `${target}.${process.pid}.tmp`;
    await fsp.writeFile(tmp, body, 'utf8');
    let lastErr;
    for (let attempt = 0; attempt < 6; attempt += 1) {
      try {
        if (fs.existsSync(target)) await fsp.rm(target, { force: true });
        await fsp.rename(tmp, target);
        this.writes += 1;
        return;
      } catch (err) {
        lastErr = err;
        await sleep(25 * (attempt + 1));
      }
    }
    await fsp.rm(tmp, { force: true }).catch(() => {});
    throw lastErr || new Error('rename ni uspel');
  }

  async flush() {
    await Promise.all(COLLECTIONS.map((n) => this.queue.get(n) || Promise.resolve()));
  }

  /* ---------------- izvoz / varnostne kopije ---------------- */
  exportDump() {
    const out = { exportedAt: nowIso(), app: 'codex-community-site', version: 1 };
    for (const name of EXPORTABLE) out[name] = this.list(name);
    return JSON.stringify(out, null, 2);
  }

  exportCsv(name) {
    const rows = this.list(name);
    const cols = [...new Set(rows.flatMap((r) => Object.keys(r)))].filter((c) => c !== '_geslo');
    const cell = (v) => {
      const s = v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v);
      return /[",;\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    return [cols.join(';'), ...rows.map((r) => cols.map((c) => cell(r[c])).join(','))].join('\r\n') + '\r\n';
  }

  /** stisnjena kopija vseh zbirk (uporablja se tudi za obnovitev pokvarjene datoteke) */
  async snapshot(reason = 'manual') {
    const day = new Date().toISOString().slice(0, 10);
    const dir = path.join(this.dir, 'backups', day);
    await fsp.mkdir(dir, { recursive: true });
    const stamp = Date.now();
    for (const name of COLLECTIONS) {
      const gz = zlib.gzipSync(Buffer.from(JSON.stringify(this.list(name), null, 2), 'utf8'));
      await fsp.writeFile(path.join(dir, `${name}.json.gz`), gz);
    }
    await fsp.writeFile(path.join(dir, 'manifest.json'), JSON.stringify({ stamp, reason, collections: COLLECTIONS }, null, 2));
    this.lastBackup = Date.now();
    return { dir, day };
  }

  async pruneBackups(keepDays) {
    if (!fs.existsSync(this.dir)) return;
    const root = path.join(this.dir, 'backups');
    if (!fs.existsSync(root)) return;
    const cutoff = Date.now() - keepDays * 86400000;
    for (const d of await fsp.readdir(root)) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) continue;
      if (new Date(`${d}T23:59:59`).getTime() < cutoff) {
        await fsp.rm(path.join(root, d), { recursive: true, force: true }).catch(() => {});
      }
    }
  }
}
