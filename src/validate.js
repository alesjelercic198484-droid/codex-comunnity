import { clampText } from './util.js';

const strip = (v) => String(v ?? '')
  .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
  .trim();

export const PAT = {
  // STEAM_0:1:23456789 ali samo 76561198xxxxxxxxx
  steam: /^(STEAM_[0-5]:[01]:\d{6,}|7656119[0-9]{10})$/i,
  // FiveM identifiers: steam:1:..., license:<40 hex>, license2:..., xbl:..., discord:...
  fivem: /^(steam:|license2?:|xbl:|discord:|fivem:|ip:|[a-f0-9]{40}$)/i,
  hex40: /^[a-f0-9]{40}$/i,
  // Discord: star.stars / star.stars#1234 / ime#0000
  discord: /^[a-z0-9._]{2,31}(#\d{2,4})?$/i,
  // Ingame ime: črkovno-število, pikica, presledek, do 32
  ingame: /^[A-Za-z0-9ÄČŠŽĐčšž. _-]{2,32}$/,
  code: /^[A-Z]{3}-[A-Z0-9]{4,10}$/i,
};

/** Preveri, da je izpolnjen "FiveM" identifikator (lahko hex licenca ali steam:...). */
export function normalizeLicense(value) {
  const v = strip(value).toLowerCase();
  if (!v) return '';
  if (PAT.hex40.test(v)) return `license:${v}`;
  if (v.startsWith('steam:') && /^\d{6,}$/.test(v.slice(6))) return v;
  if (PAT.steam.test(v)) {
    // STEAM_0:1:123456 -> 64-bitni SteamID (poenostavljeno, samo za prikaz)
    const parts = v.toUpperCase().split(':');
    const account = Number(parts[2]);
    if (Number.isFinite(account)) return `steamid64:${76561197960265728 + account * 2 + Number(parts[1])}`;
  }
  if (PAT.fivem.test(v)) return v;
  return v;
}

/**
 * Validacija javne prijavnice.
 * @returns {{ok:boolean, values:object, errors:object, honeypotHit:boolean}}
 */
export function validateApplication(body, cfg) {
  const a = cfg.applications;
  const errors = {};
  const values = {
    name: clampText(strip(body.name), 80),
    ingame: clampText(strip(body.ingame), 32),
    discord: clampText(strip(body.discord), 40),
    steam: clampText(strip(body.steam), 40),
    license: clampText(strip(body.license), 120),
    age: strip(body.age),
    message: clampText(strip(body.message), Number(a.maxCharsMessage || 4000)),
    rules: body.rules === 'on' || body.rules === true || body.rules === '1',
    website: strip(body.website), // honeypot - moral biti prazen
  };

  if (values.website) return { ok: false, errors: {}, values, honeypotHit: true };

  if (values.name.length < 3) errors.name = 'Vnesi ime in priimek (vsaj 3 znaki).';
  if (values.name.length > 80) errors.name = 'Ime je predolgo (največ 80 znakov).';
  if (!PAT.ingame.test(values.ingame)) errors.ingame = 'Ingame ime: 2-32 znakov (črke, številke, presledek, . _ -).';
  if (!PAT.discord.test(values.discord)) errors.discord = 'Discord: 2-31 znakov (npr. codex.player), lahko tudi s številko.';
  if (values.ingame.split(/[ _.-]/).some((w) => w.length > 16) || /^\s|\s$/.test(values.ingame)) errors.ingame = 'Ingame ime je neveljavno (največ 16 znakov na besedo).';

  if (a.requireSteamId && !PAT.steam.test(values.steam)) errors.steam = 'Steam ID v obliki STEAM_0:1:12345678 ali 76561198xxxxxxxxx.';
  if (a.requireLicenseKey) {
    const lic = normalizeLicense(values.license);
    if (!lic) errors.license = 'FiveM license ključ je obvezen (ukaz /license v igri ali steam:...).';
    else values.licenseNorm = lic;
  } else {
    values.licenseNorm = normalizeLicense(values.license);
  }

  const age = Number(values.age);
  if (!Number.isInteger(age)) errors.age = 'Starost mora biti številka.';
  else if (age < Number(a.minAge || 16)) errors.age = `Za prijavo moraš imeti vsaj ${a.minAge} let.`;
  else if (age > 100) errors.age = 'Vidi se, da to ni resnično.';

  const len = values.message.length;
  if (len < 120) errors.message = `Opiši se vsaj v 120 znakih (trenutno ${len}).`;
  else if (len > Number(a.maxCharsMessage || 4000)) errors.message = 'Opis je predolg.';
  if (!values.rules) errors.rules = 'Potrditi moraš pravila.';

  return { ok: Object.keys(errors).length === 0, errors, values, honeypotHit: false };
}

export function validatePlayer(body, existing = {}) {
  const errors = {};
  const values = {
    ingame: clampText(strip(body.ingame), 32),
    name: clampText(strip(body.name), 80),
    discord: clampText(strip(body.discord), 40),
    steam: clampText(strip(body.steam), 40),
    license: normalizeLicense(body.license),
    status: ['active', 'inactive', 'banned', 'trial'].includes(body.status) ? body.status : 'active',
    job: clampText(strip(body.job), 40),
    notes: clampText(strip(body.notes), 2000),
    wlExpires: strip(body.wlExpires) || null,
  };
  if (!PAT.ingame.test(values.ingame)) errors.ingame = 'Ingame ime: 2-32 znakov.';
  if (values.discord && !PAT.discord.test(values.discord)) errors.discord = 'Neveljaven Discord.';
  if (values.steam && !PAT.steam.test(values.steam)) errors.steam = 'Neveljaven Steam ID (pusti prazno, če ne veš).';
  if (values.wlExpires && Number.isNaN(Date.parse(values.wlExpires))) errors.wlExpires = 'Datum veljavnosti ni veljaven.';
  return { ok: Object.keys(errors).length === 0, errors, values, existing };
}

export function validateWhitelist(body) {
  const errors = {};
  const identifier = normalizeLicense(body.identifier);
  const values = {
    identifier,
    ingame: clampText(strip(body.ingame), 32),
    discord: clampText(strip(body.discord), 40),
    note: clampText(strip(body.note), 300),
    expires: strip(body.expires) || null,
    forever: body.forever === 'on',
  };
  if (!identifier) errors.identifier = 'Vnesi FiveM identifier (license / steamid64 / steam:...).';
  if (values.expires && Number.isNaN(Date.parse(values.expires))) errors.expires = 'Neveljaven datum.';
  return { ok: Object.keys(errors).length === 0, errors, values };
}

export function validateStaff(body) {
  const errors = {};
  const username = strip(body.username).toLowerCase();
  const password = String(body.password ?? '');
  if (!/^[a-z0-9._-]{3,32}$/.test(username)) errors.username = 'Uporabniško ime: 3-32 znakov (a-z, 0-9, . _ -).';
  if (password.length < 12) errors.password = 'Geslo mora imeti vsaj 12 znakov (priporočen frazni zapis).';
  if (password.length > 200) errors.password = 'Geslo je predolgo.';
  const role = ['moderator', 'viewer'].includes(body.role) ? body.role : 'moderator';
  return { ok: Object.keys(errors).length === 0, errors, values: { username, password, role } };
}

export function validateStatusQuery(body) {
  const code = strip(body.code).toUpperCase();
  const discord = strip(body.discord);
  const errors = {};
  if (!PAT.code.test(code)) errors.code = 'Koda je v obliki CDX-XXXXXX (brez presledkov).';
  if (!PAT.discord.test(discord)) errors.discord = 'Vnesi svoj Discord uporabniško ime (brez @).';
  return { ok: Object.keys(errors).length === 0, errors, values: { code, discord: discord.toLowerCase() } };
}
