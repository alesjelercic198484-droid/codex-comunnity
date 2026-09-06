import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const DEFAULTS = {
  siteName: 'CodeX Community',
  siteTagline: 'Premium FiveM Roleplay strežnik',
  discordInvite: 'https://discord.gg/YOUR_DISCORD_LINK',
  serverConnect: '',
  port: 3000,
  host: '0.0.0.0',
  publicUrl: '',
  dataDir: './data',
  admin: { username: 'admin', password: '' },
  sessionHours: 12,
  secureCookies: 'auto',
  trustProxy: true,
  csrfSecret: '',
  applications: {
    open: true,
    minAge: 16,
    maxCharsMessage: 4000,
    maxPerIpPerDay: 5,
    requireSteamId: true,
    requireLicenseKey: true,
  },
  whitelist: { exportFile: './data/fivem-whitelist.json', copyTo: [] },
  api: { enabled: true, token: '' },
  logs: { retentionDays: 90, maxFileSizeMb: 8, keepRotatedFiles: 6 },
  backup: { enabled: true, everyHours: 6, keepDays: 14, dir: './data/backups' },
};

function deepMerge(base, extra) {
  if (!extra || typeof extra !== 'object') return base;
  const out = Array.isArray(base) ? [...base] : { ...base };
  for (const [k, v] of Object.entries(extra)) {
    if (v && typeof v === 'object' && !Array.isArray(v) && out[k] && typeof out[k] === 'object') {
      out[k] = deepMerge(out[k], v);
    } else if (k !== '_opomba' && !k.startsWith('_')) {
      out[k] = v;
    }
  }
  return out;
}

const env = (name) => {
  const v = process.env[name];
  return v === undefined || v === '' ? undefined : v;
};
const bool = (v) => v === '1' || String(v).toLowerCase() === 'true' || v === true;

/**
 * Naloži config.json (+ okoljske spremenljivke, ki imajo prednost).
 * Vrne resolved config z absolutnimi poteh in zagotovljenim skrivnim ključem.
 */
export function loadConfig(overrides = {}) {
  const configPath = env('CONFIG_PATH') || path.join(ROOT, 'config.json');
  let fileConf = {};
  if (fs.existsSync(configPath)) {
    try {
      fileConf = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    } catch (err) {
      console.error(`[config] ${configPath} je pokvarjen, uporabjam privzete vrednosti:`, err.message);
    }
  } else {
    console.warn(`[config] datoteka ${configPath} ne obstaja - uporabljam privzete vrednosti (${path.join(ROOT, 'config.example.json')} za vzorec).`);
  }

  let cfg = deepMerge(deepMerge(DEFAULTS, fileConf), overrides);

  if (env('PORT')) cfg.port = Number(env('PORT'));
  if (env('HOST')) cfg.host = env('HOST');
  if (env('PUBLIC_URL')) cfg.publicUrl = env('PUBLIC_URL');
  if (env('DATA_DIR')) cfg.dataDir = env('DATA_DIR');
  if (env('SITE_NAME')) cfg.siteName = env('SITE_NAME');
  if (env('DISCORD_INVITE')) cfg.discordInvite = env('DISCORD_INVITE');
  if (env('SERVER_CONNECT')) cfg.serverConnect = env('SERVER_CONNECT');
  if (env('SESSION_HOURS')) cfg.sessionHours = Number(env('SESSION_HOURS'));
  if (env('SECURE_COOKIES')) cfg.secureCookies = env('SECURE_COOKIES');
  if (env('TRUST_PROXY')) cfg.trustProxy = bool(env('TRUST_PROXY'));
  if (env('CSRF_SECRET')) cfg.csrfSecret = env('CSRF_SECRET');
  if (env('ADMIN_USER')) cfg.admin.username = env('ADMIN_USER');
  if (env('ADMIN_PASSWORD')) cfg.admin.password = env('ADMIN_PASSWORD');
  if (env('API_TOKEN')) cfg.api.token = env('API_TOKEN');
  if (env('APPS_OPEN')) cfg.applications.open = bool(env('APPS_OPEN'));
  if (env('BACKUP_ENABLED')) cfg.backup.enabled = bool(env('BACKUP_ENABLED'));

  cfg.configPath = configPath;
  cfg.dataDirAbs = path.isAbsolute(cfg.dataDir) ? cfg.dataDir : path.resolve(ROOT, cfg.dataDir);
  // Izvoz whiteliste: relativne poti so glede na MAPO PODATKOV (ne glede na mapo projekta),
  // da se ob selitvi dataDir samodejno seli tudi datoteka za FiveM.
  const expRaw = cfg.whitelist.exportFile || 'fivem-whitelist.json';
  cfg.exportFileAbs = path.isAbsolute(expRaw)
    ? expRaw
    : path.resolve(cfg.dataDirAbs, expRaw.replace(/^\.?\/?(data\/)?/, ''));
  cfg.backup.dirAbs = path.isAbsolute(cfg.backup.dir) ? cfg.backup.dir : path.resolve(ROOT, cfg.backup.dir);
  cfg.publicUrl = (cfg.publicUrl || '').replace(/\/+$/, '');

  // Skrivni ključ za podpis CSRF / žetoni sej: iz config.json ali data/secret.key
  const secretFile = path.join(cfg.dataDirAbs, 'secret.key');
  if (!cfg.csrfSecret) {
    if (fs.existsSync(secretFile)) {
      cfg.csrfSecret = fs.readFileSync(secretFile, 'utf8').trim();
    }
    if (!cfg.csrfSecret || cfg.csrfSecret.length < 32) {
      cfg.csrfSecret = crypto.randomBytes(32).toString('hex');
      fs.mkdirSync(cfg.dataDirAbs, { recursive: true });
      fs.writeFileSync(secretFile, cfg.csrfSecret + '\n', { mode: 0o600 });
      console.warn('[config] nov skrivni ključ je bil ustvarjen v', secretFile);
    }
  }
  return cfg;
}
