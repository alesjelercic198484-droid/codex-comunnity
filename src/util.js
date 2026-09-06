import crypto from 'node:crypto';

/** HTML/SVG-varen izpis (prepreči XSS v strežniku renderiranih straneh). */
export function esc(value) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Vnaprej označen varen HTML (npr. deli, ki jih je ustvaril naš renderer). */
export const raw = (s) => ({ __raw: String(s) });
export const isRaw = (v) => v && typeof v === 'object' && typeof v.__raw === 'string';

/**
 * Označevalni predlog: VREDNOSTI so samodejno HTML-izogibane.
 * Nizovi, ki jih želiš vstaviti kot HTML, ovij z raw() ali uporabi html() vgnjezdeno.
 * Nizke vrednosti (null, undefined, false, '') se izpustijo - uporabno za pogojne dele.
 */
export function html(strings, ...values) {
  let out = '';
  for (let i = 0; i < strings.length; i += 1) {
    out += strings[i];
    if (i >= values.length) continue;
    const v = values[i];
    if (v === null || v === undefined || v === false || v === true || v === '') continue;
    if (isRaw(v)) out += v.__raw;
    else if (Array.isArray(v)) out += v.map((x) => (isRaw(x) ? x.__raw : esc(x))).join('');
    else out += esc(v);
  }
  return raw(out);
}

export const newId = () => crypto.randomUUID();

export function shortCode(prefix = 'CDX', bytes = 3) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let s = '';
  for (const b of crypto.randomBytes(bytes)) s += alphabet[b % alphabet.length];
  return `${prefix}-${s}${Date.now().toString(36).slice(-4).toUpperCase()}`;
}

export const nowIso = () => new Date().toISOString();

export function isIso(value) {
  return typeof value === 'string' && !Number.isNaN(Date.parse(value));
}

export function daysAgo(n) {
  return new Date(Date.now() - n * 86400000).toISOString();
}

/** Človeški prikaz datuma/časa (brez tuje knjižnice). */
export function fmtDate(iso, withTime = true) {
  if (!isIso(iso)) return iso ? String(iso) : '-';
  const d = new Date(iso);
  const p = (n) => String(n).padStart(2, '0');
  const date = `${p(d.getDate())}.${p(d.getMonth() + 1)}.${d.getFullYear()}`;
  return withTime ? `${date} ${p(d.getHours())}:${p(d.getMinutes())}` : date;
}

export function relTime(iso) {
  if (!isIso(iso)) return '-';
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.round(diff / 60000);
  if (m < 1) return 'pravkar';
  if (m < 60) return `pred ${m} min`;
  const h = Math.round(m / 60);
  if (h < 24) return `pred ${h} ur`;
  return `pred ${Math.round(h / 24)} dni`;
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function titleCase(s) {
  return String(s || '')
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(' ');
}

/** Varen primerjava za tokene / API ključe (enak čas, ne glede na vsebino). */
export function safeEqual(a, b) {
  const ba = Buffer.from(String(a ?? ''), 'utf8');
  const bb = Buffer.from(String(b ?? ''), 'utf8');
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

/** Poenostavi FiveM identifier (steam:x, license:..., license2:...). */
export function normalizeIdentifier(value) {
  return String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '');
}

export function clampText(value, max) {
  return String(value ?? '').replace(/\r\n/g, '\n').trim().slice(0, max);
}
