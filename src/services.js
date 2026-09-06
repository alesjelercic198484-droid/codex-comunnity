import fsSync from 'node:fs';
import pathMod from 'node:path';

/**
 * Upravljanje živih (spremenljivih) nastavitev: config.json je osnova,
 * data/settings.json (ureja se v admin plošči) ga pregla.
 */
export function liveConfig(base, store) {
  const s = store.list('settings')[0] || {};
  const cfg = {
    ...base,
    siteName: s.siteName || base.siteName,
    siteTagline: s.siteTagline || base.siteTagline,
    discordInvite: s.discordInvite || base.discordInvite,
    serverConnect: s.serverConnect ?? base.serverConnect,
    publicUrl: s.publicUrl || base.publicUrl,
    applications: {
      ...base.applications,
      open: s.applicationsOpen ?? base.applications.open,
      minAge: s.minAge ?? base.applications.minAge,
      maxPerIpPerDay: s.maxPerIpPerDay ?? base.applications.maxPerIpPerDay,
    },
    api: { ...base.api, token: s.apiToken || base.api.token },
  };
  cfg.dataDir = base.dataDir;
  return cfg;
}

export function applyLiveSettings(store, body) {
  const s = store.settingsStore;
  const jobs = [];
  const set = (key, value) => jobs.push(s.set(key, value));
  set('siteName', String(body.siteName || '').trim().slice(0, 60));
  set('siteTagline', String(body.siteTagline || '').trim().slice(0, 90));
  const invite = validUrl(body.discordInvite);
  set('discordInvite', invite === null ? store.getSetting('discordInvite', '') : invite);
  set('serverConnect', String(body.serverConnect || '').trim().slice(0, 90));
  set('applicationsOpen', body.applicationsOpen === 'on');
  set('minAge', clampInt(body.minAge, 13, 99, 16));
  set('maxPerIpPerDay', clampInt(body.maxPerIpPerDay, 1, 50, 5));
  return Promise.all(jobs);
}

function validUrl(v) {
  const s = String(v || '').trim();
  if (!s) return '';
  if (!/^(https?:\/\/|discord\.gg\/)[^\s"'<>]+$/i.test(s)) return null;
  return s.startsWith('http') ? s : `https://${s.replace(/^\/+/, '')}`;
}

function clampInt(v, min, max, dflt) {
  const n = Number(v);
  if (!Number.isFinite(n)) return dflt;
  return Math.min(max, Math.max(min, Math.round(n)));
}

export function statsFor(store) {
  const apps = store.list('applications');
  const since30 = Date.now() - 30 * 86400000;
  const approved = apps.filter((a) => a.status === 'approved');
  return {
    players: store.count('players'),
    whitelist: store.count('whitelist'),
    applications: apps.length,
    pending: apps.filter((a) => a.status === 'pending' || a.status === 'more_info').length,
    approved30: approved.filter((a) => Date.parse(a.reviewedAt || a.updatedAt) > since30).length,
    denied30: apps.filter((a) => a.status === 'denied' && Date.parse(a.reviewedAt || a.updatedAt) > since30).length,
    lastApproved: approved.map((a) => a.reviewedAt || a.updatedAt).sort().slice(-1)[0] || null,
  };
}

/** Javni "recent" seznam: samo odobrene prijave, brez osebnih podatkov. */
export function publicRecent(applications, limit = 5) {
  return applications
    .filter((a) => a.status === 'approved')
    .sort((x, y) => String(y.reviewedAt || '').localeCompare(String(x.reviewedAt || '')))
    .slice(0, limit)
    .map((a) => ({ ingame: a.ingame, status: a.status, reviewedAt: a.reviewedAt, updatedAt: a.updatedAt }));
}

export function fmtBytes(n) {
  if (!Number.isFinite(n)) return '-';
  if (n < 1024) return `${n} B`;
  if (n < 1024 ** 2) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 ** 2).toFixed(1)} MB`;
}

export function systemInfo({ store, startedAt, config }) {
  const up = Math.round((Date.now() - startedAt) / 1000);
  const dir = config.dataDirAbs;
  let dataSize = 0;
  try {
    for (const f of fsReaddirSync(dir)) dataSize += safeSize(path_join(dir, f));
  } catch { /* ignore */ }
  return {
    node: process.version,
    platform: `${process.platform} ${process.arch}`,
    uptime: up < 3600 ? `${Math.round(up / 60)} min` : `${Math.floor(up / 3600)} h ${Math.round((up % 3600) / 60)} min`,
    memUsed: Math.round(process.memoryUsage().rss / 1024 / 1024),
    memTotal: Math.round((process.memoryUsage().heapTotal + process.memoryUsage().external) / 1024 / 1024),
    dataSize: Math.round(dataSize / 1024),
    startedAt: new Date(startedAt).toISOString(),
    pid: process.pid,
    collections: ['users', 'players', 'applications', 'whitelist', 'sessions'].map((name) => ({ name, count: store.count(name) })),
  };
}
const fsReaddirSync = (d) => (fsSync.existsSync(d) ? fsSync.readdirSync(d) : []);
const path_join = (a, b) => pathMod.join(a, b);
const safeSize = (p) => {
  try {
    const st = fsSync.statSync(p);
    return st.isDirectory() ? 0 : st.size;
  } catch {
    return 0;
  }
};
