import { html, raw, esc, isRaw } from '../util.js';

export const ICONS = {
  users: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  log: '<path d="M4 4h16v16H4z"/><path d="M8 9h8M8 13h8M8 17h5"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-2.7 1.1V21a2 2 0 1 1-4 0v-.1A1.6 1.6 0 0 0 7.5 19.4l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.6 1.6 0 0 0 3 14.6H3a2 2 0 1 1 0-4h.1A1.6 1.6 0 0 0 4.6 8.5l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.6 1.6 0 0 0 10 4.6V4a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1.8 1.5h.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0 .9 2.5h.2a2 2 0 1 1 0 4H21a1.6 1.6 0 0 0-1.6 1z"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  discord: '<path d="M20 5a18 18 0 0 0-4.5-1.4l-.3.6A16 16 0 0 1 19 6c-2.6-1.3-5.3-1.9-8-1.9S5.6 4.7 3 6a16 16 0 0 1 3.8-1.8L6.5 3.6A18 18 0 0 0 2 5 20 20 0 0 0 2 18a18 18 0 0 0 5.5 2l1-1.7-1.9-.9.5-.8 3.9 1.7 3.9-1.7.5.8-1.9.9 1 1.7a18 18 0 0 0 5.5-2 20 20 0 0 0 0-13ZM9 14a1.7 1.7 0 1 1 0-3.4A1.7 1.7 0 0 1 9 14Zm6 0a1.7 1.7 0 1 1 0-3.4A1.7 1.7 0 0 1 15 14Z"/>',
};

export const icon = (name, cls = '') =>
  raw(`<svg class="ico ${esc(cls)}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`);

export function badge(status, label) {
  return html`<span class="badge badge--${status}">${label || status}</span>`;
}

export const APP_STATUS = {
  pending: { label: 'V obdelavi', cls: 'pending' },
  approved: { label: 'Odobreno', cls: 'ok' },
  denied: { label: 'Zavrnjeno', cls: 'bad' },
  more_info: { label: 'Potrebno dodatno', cls: 'warn' },
};
export const appStatus = (s) => badge(APP_STATUS[s]?.cls || 'pending', APP_STATUS[s]?.label || s);

const unwrap = (v) => (isRaw(v) ? v.__raw : v === null || v === undefined ? '' : String(v));

export function layout(cfg, { title, active = '', user = null, flash = null, children, wide = false, admin = false, csrf = '' }) {
  const nav = [
    ['home', '/', 'Domov'],
    ['apply', '/prijava', 'Prijava na WL'],
    ['status', '/status', 'Status prijave'],
    ['rules', '/pravila', 'Pravila'],
  ];
  return raw(`<!doctype html>
<html lang="sl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title ? `${title} · ${cfg.siteName}` : cfg.siteName)}</title>
<meta name="description" content="${esc(`${cfg.siteName} - ${cfg.siteTagline}. Oddaj prijavnico za whitelist, preveri status in pridruži se skupnosti.`)}">
<meta name="robots" content="${admin ? 'noindex,nofollow' : 'index,follow'}">
<link rel="stylesheet" href="/assets/site.css">
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
<script src="/assets/site.js" defer></script>
</head>
<body class="${admin ? 'admin-body' : ''}">
<a class="skip" href="#glavna">Na vsebino</a>
${unwrap(admin ? adminShell(cfg, { user, active, csrf, children, wide }) : siteShell(cfg, { nav, active, user, flash, children, wide }))}
</body>
</html>`);
}

function siteShell(cfg, { nav, active, user, flash, children, wide }) {
  return html`
  <header class="topbar">
    <div class="wrap topbar__in">
      <a class="brand" href="/">
        <span class="brand__mark">CX</span>
        <span class="brand__txt"><b>${cfg.siteName}</b><small>${cfg.siteTagline}</small></span>
      </a>
      <nav class="nav" aria-label="Glavna navigacija">
        ${nav.map(([key, href, label]) => html`<a class="${key === active ? 'is-active' : ''}" href="${href}">${label}</a>`)}
      </nav>
      <div class="topbar__cta">
        <a class="btn btn--ghost" href="/admin">${user ? 'Admin plošča' : 'Prijava osebja'}</a>
      </div>
    </div>
  </header>
  <main id="glavna" class="wrap ${wide ? 'wrap--wide' : ''}">
    ${flash ? flashBox(flash) : ''}
    ${children}
  </main>
  <footer class="footer">
    <div class="wrap footer__in">
      <div>
        <b>${cfg.siteName}</b>
        <p>${cfg.siteTagline}</p>
      </div>
      <div class="footer__links">
        <a href="${cfg.discordInvite}" rel="noopener" target="_blank">Discord</a>
        <a href="/pravila">Pravila</a>
        <a href="/status">Status prijave</a>
        <a href="/api/health">Status strani</a>
      </div>
      <p class="footer__note">© ${new Date().getFullYear()} ${cfg.siteName} · vsi podatki se hranijo lokalno na VPS strežniku</p>
    </div>
  </footer>`;
}

function adminShell(cfg, { user, active, csrf, children, wide }) {
  const links = [
    ['dashboard', '/admin', 'Nadzorna plošča', 'gear'],
    ['applications', '/admin/prijave', 'Prijavnice', 'file'],
    ['players', '/admin/igralci', 'Igralci', 'users'],
    ['whitelist', '/admin/whitelist', 'Whitelist', 'shield'],
    ['logs', '/admin/logi', 'Dnevnik (logi)', 'log'],
    ['data', '/admin/podatki', 'Podatki & izvoz', 'download'],
    ['settings', '/admin/nastavitve', 'Nastavitve', 'gear'],
  ];
  return html`
  <div class="shell">
    <aside class="side">
      <a class="brand brand--side" href="/">
        <span class="brand__mark">CX</span>
        <span class="brand__txt"><b>CodeX</b><small>admin</small></span>
      </a>
      <nav class="side__nav">
        ${links.map(([key, href, label, ic]) => html`
          <a class="${key === active ? 'is-active' : ''}" href="${href}">${icon(ic)}<span>${label}</span></a>`)}
      </nav>
      <div class="side__foot">
        ${user ? html`
          <p class="who"><b>${user.username}</b><small>${user.role === 'owner' ? 'skrbnik' : user.role}</small></p>
          <form method="post" action="/admin/odjava">
            <input type="hidden" name="_csrf" value="${csrf}">
            <button class="btn btn--ghost btn--sm" type="submit">Odjava</button>
          </form>` : ''}
      </div>
    </aside>
    <main id="glavna" class="main ${wide ? 'main--wide' : ''}">${children}</main>
  </div>`;
}

export function flashBox(flash) {
  const cls = { ok: 'flash--ok', bad: 'flash--bad', warn: 'flash--warn', info: 'flash--info' }[flash.kind] || 'flash--info';
  return html`<div class="flash ${cls}" role="status">${flash.text}</div>`;
}

/**
 * Oblika polja. `attrs` je varen HTML in ga sestavi klicatelj (npr. raw('required')).
 */
export function field({ name, label, value = '', type = 'text', placeholder = '', help = '', error = '', required = false, maxlength = 0, rows = 7, attrs = '' }) {
  const extra = raw([required ? 'required' : '', maxlength ? `maxlength="${Number(maxlength)}"` : '', isRaw(attrs) ? attrs.__raw : ''].filter(Boolean).join(' '));
  return html`
    <label class="fld ${error ? 'has-error' : ''}">
      <span class="fld__label">${label}${required ? html`<i title="obvezno">*</i>` : ''}</span>
      ${type === 'textarea'
        ? html`<textarea name="${name}" rows="${rows}" placeholder="${placeholder}" ${extra}>${value}</textarea>`
        : html`<input name="${name}" type="${type}" value="${value}" placeholder="${placeholder}" ${extra}>`}
      ${error ? html`<span class="fld__err">${error}</span>` : (help ? html`<span class="fld__help">${help}</span>` : '')}
    </label>`;
}
