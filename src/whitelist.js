import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { nowIso, normalizeIdentifier } from './util.js';

/**
 * Whitelist: enoten vir resnice je zbirka `whitelist` (data/whitelist.json).
 * Izvoz zapiše datoteko, ki jo lahko FiveM skripta bere, in jo po želji
 * kopira na dodatne poti (config.whitelist.copyTo).
 */
export class WhitelistService {
  constructor({ store, logger, config }) {
    this.store = store;
    this.logger = logger;
    this.config = config;
  }

  get all() {
    return this.store.list('whitelist');
  }

  get active() {
    const now = Date.now();
    return this.all.filter((w) => !w.disabled && (!w.expires || Date.parse(w.expires) >= now));
  }

  find(identifier) {
    const idn = normalizeIdentifier(identifier);
    if (!idn) return null;
    return this.all.find((w) => normalizeIdentifier(w.identifier) === idn) || null;
  }

  /** Doda ali posodobi zapis (dedup po identifierju). */
  async add({ identifier, ingame = '', discord = '', expires = null, note = '', addedBy = 'system', source = 'admin', applicationId = null }) {
    const idn = normalizeIdentifier(identifier);
    if (!idn) throw Object.assign(new Error('manjka identifier'), { status: 400 });
    const existing = this.find(idn);
    const payload = {
      identifier: idn, ingame, discord, expires: expires || null, note, addedBy, source, applicationId, disabled: false,
    };
    if (existing) {
      const row = await this.store.update('whitelist', existing.id, payload);
      return { row, created: false };
    }
    const row = await this.store.insert('whitelist', payload);
    return { row, created: true };
  }

  async remove(id) {
    const row = this.store.find('whitelist', id);
    if (!row) return null;
    await this.store.remove('whitelist', id);
    return row;
  }

  /** Preveri, ali sme identifier na strežnik. */
  check(identifier) {
    const row = this.find(identifier);
    if (!row) return { allowed: false, reason: 'ni na whitelisti' };
    if (row.disabled) return { allowed: false, reason: 'odstranjen iz whiteliste', row };
    if (row.expires && Date.parse(row.expires) < Date.now()) return { allowed: false, reason: 'whitelist je potekla', row };
    return { allowed: true, row };
  }

  /** Zapiši izvoz in ga po potrebi skopiraj na dodatne poti. Vrne {file, count, copied, errors}. */
  async export({ actor = 'system', quiet = false } = {}) {
    const cfg = this.config;
    const rows = this.active.map((w) => ({
      identifier: w.identifier,
      name: w.ingame || w.discord || '',
      discord: w.discord || '',
      addedAt: w.createdAt,
      expires: w.expires || null,
      note: w.note || '',
    }));
    const json = `${JSON.stringify({ generatedAt: nowIso(), server: cfg.serverName || cfg.siteName, count: rows.length, whitelist: rows }, null, 2)}\n`;
    const txt = `${rows.map((r) => r.identifier).join('\n')}\n`;
    const plain = `${JSON.stringify(rows, null, 2)}\n`;
    const out = cfg.exportFileAbs;
    await fsp.mkdir(path.dirname(out), { recursive: true });
    await fsp.writeFile(out, json, 'utf8');
    await fsp.writeFile(out.replace(/\.json$/i, '.txt'), txt, 'utf8');
    await fsp.writeFile(out.replace(/\.json$/i, '.array.json'), plain, 'utf8');

    const copied = [];
    const errors = [];
    for (const dest of cfg.whitelist.copyTo || []) {
      try {
        await fsp.mkdir(path.dirname(dest), { recursive: true });
        await fsp.copyFile(out, dest);
        copied.push(dest);
      } catch (err) {
        errors.push(`${dest}: ${err.message}`);
      }
    }
    await this.store.setSetting('whitelistExportedAt', nowIso());
    if (!quiet) {
      this.logger.info('wl.export', `whitelist izvožena: ${rows.length} aktivnih zapisov v 3 datoteke`, {
        actor, meta: { file: out, copied, errors: errors.length ? errors : undefined },
      });
    }
    return { file: out, count: rows.length, copied, errors };
  }

  stats() {
    const now = Date.now();
    const soon = now + 7 * 86400000;
    return {
      total: this.all.length,
      active: this.active.length,
      expiring: this.all.filter((w) => w.expires && Date.parse(w.expires) > now && Date.parse(w.expires) < soon),
      expired: this.all.filter((w) => w.expires && Date.parse(w.expires) <= now),
      lastExport: this.store.getSetting('whitelistExportedAt', null),
      fileExists: fs.existsSync(this.config.exportFileAbs),
    };
  }
}
