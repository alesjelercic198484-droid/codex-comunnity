import { html, raw, esc, fmtDate, relTime } from '../util.js';
import { layout, field, icon, appStatus, APP_STATUS } from './layout.js';

const adminLayout = (cfg, opts) => layout(cfg, { ...opts, admin: true, wide: true });

const STATUS_LABEL = { pending: 'v obdelavi', approved: 'odobreno', denied: 'zavrnjeno', more_info: 'dodatno' };

/* -------------------------------- PRIJAVA -------------------------------- */
export function loginPage(cfg, { error = '', flash, csrf = '' }) {
  const children = html`
  <section class="login">
    <form class="panel" method="post" action="/admin/prijava">
      <input type="hidden" name="_csrf" value="${csrf}">
      <h1>${cfg.siteName}</h1>
      <p class="muted">Samo za osebje. Poskusi se beležijo v dnevnik.</p>
      ${error ? html`<div class="flash flash--bad">${error}</div>` : ''}
      ${flash ? html`<div class="flash flash--ok">${flash.text}</div>` : ''}
      ${field({ name: 'username', label: 'Uporabnik', value: '', required: true, attrs: raw('autocomplete="username" autofocus') })}
      ${field({ name: 'password', label: 'Geslo', type: 'password', required: true, attrs: raw('autocomplete="current-password"') })}
      <button class="btn btn--primary btn--block" type="submit">Prijava</button>
      <p class="tiny muted"><a href="/">← Nazaj na stran</a></p>
    </form>
  </section>`;
  return adminLayout(cfg, { title: 'Prijava', children, active: '', csrf });
}

export function mustChangePasswordPage(cfg, { csrf = '' }) {
  const children = html`
  <section class="login">
    <form class="panel" method="post" action="/admin/geslo">
      <input type="hidden" name="_csrf" value="${csrf}">
      <h1>Nastavi geslo skrbnika</h1>
      <p class="muted">Prva prijava. Nastavi svoje geslo (vsaj 12 znakov).</p>
      ${field({ name: 'password', label: 'Novo geslo', type: 'password', required: true, attrs: raw('autocomplete="new-password" autofocus minlength="12"') })}
      ${field({ name: 'password2', label: 'Ponovi geslo', type: 'password', required: true, attrs: raw('autocomplete="new-password" minlength="12"') })}
      <button class="btn btn--primary btn--block" type="submit">Shrani in nadaljuj</button>
    </form>
  </section>`;
  return adminLayout(cfg, { title: 'Novo geslo', children, csrf });
}

/* ---------------------------- NADZORNA PLOŠČA ---------------------------- */
export function dashboardPage(cfg, { user, csrf, stats, apps, players, logs, wlStats, system, flash }) {
  const kpi = [
    ['Odprte prijave', stats.pending, 'file'],
    ['Odobreno (30 dni)', stats.approved30, 'check'],
    ['Zavrnjeno (30 dni)', stats.denied30, 'x'],
    ['Igralci v bazi', stats.players, 'users'],
    ['Whitelist zapisi', stats.whitelist, 'shield'],
    ['Dnevniki (24 h)', stats.logEvents, 'log'],
  ];
  const children = html`
  ${flash ? html`<div class="flash flash--${flash.kind}">${flash.text}</div>` : ''}
  <header class="head">
    <div><h1>Nadzorna plošča</h1><p class="muted">Živjo ${user.username}. Vsebina spodaj je shranjena v <code>${cfg.dataDir}</code> na tem VPS-u.</p></div>
    <a class="btn btn--primary" href="/admin/prijave?status=pending">Preglej prijave</a>
  </header>

  <div class="kpis">
    ${kpi.map(([label, value, ic]) => html`
      <div class="kpi">${icon(ic)}<b>${value}</b><span>${label}</span></div>`)}
  </div>

  <div class="cols">
    <div>
      <section class="panel">
        <div class="row"><h2>Zadnje prijave</h2><a class="btn btn--ghost btn--sm" href="/admin/prijave">Vse</a></div>
        <table class="table">
          <thead><tr><th>Koda</th><th>Igralec</th><th>Discord</th><th>Status</th><th>Oddano</th></tr></thead>
          <tbody>
            ${apps.length ? apps.map((a) => html`
              <tr>
                <td><code>${a.code}</code></td>
                <td>${a.ingame}</td>
                <td>${a.discord}</td>
                <td>${appStatus(a.status)}</td>
                <td title="${fmtDate(a.submittedAt)}">${relTime(a.submittedAt)}</td>
              </tr>`) : html`<tr><td colspan="5" class="muted">Ni prijav.</td></tr>`}
          </tbody>
        </table>
      </section>

      <section class="panel">
        <div class="row"><h2>Igralci (nazadnje spreminjani)</h2><a class="btn btn--ghost btn--sm" href="/admin/igralci">Vsi igralci</a></div>
        <table class="table">
          <thead><tr><th>Ingame</th><th>Status</th><th>Whitelist do</th><th>Posodobljeno</th></tr></thead>
          <tbody>
            ${players.length ? players.map((p) => html`
              <tr>
                <td>${p.ingame}</td>
                <td><span class="badge badge--${p.status === 'banned' ? 'bad' : p.status === 'active' ? 'ok' : 'pending'}">${p.status}</span></td>
                <td>${p.wlExpires ? fmtDate(p.wlExpires, false) : 'brez omejitve'}</td>
                <td title="${fmtDate(p.updatedAt)}">${relTime(p.updatedAt)}</td>
              </tr>`) : html`<tr><td colspan="4" class="muted">Baza igralcev je še prazna.</td></tr>`}
          </tbody>
        </table>
      </section>
    </div>

    <div class="side">
      <section class="panel">
        <h2>Whitelist izvoz</h2>
        <p class="muted tiny">Datoteko lahko FiveM osebje bere neposredno.</p>
        <dl class="kv">
          <dt>Datoteka</dt><dd><code>${cfg.whitelist.exportFile}</code></dd>
          <dt>Zapisi</dt><dd>${wlStats.total}</dd>
          <dt>Potekajoči</dt><dd>${wlStats.expiring.length}</dd>
          <dt>Zadnji izvoz</dt><dd>${wlStats.lastExport ? relTime(wlStats.lastExport) : 'še ni'}</dd>
        </dl>
        <form method="post" action="/admin/whitelist/izvozi">
          <input type="hidden" name="_csrf" value="${csrf}">
          <button class="btn btn--sm" type="submit">Zapiši / osveži izvoz</button>
        </form>
      </section>

      <section class="panel">
        <h2>Zadnji dogodki</h2>
        <ul class="mini-log">
          ${logs.map((l) => html`
            <li class="lv--${l.level}"><code>${l.type}</code> ${l.message}<small>${l.actor} · ${relTime(l.ts)}</small></li>`)}
        </ul>
        <a class="btn btn--ghost btn--sm" href="/admin/logi">Celoten dnevnik</a>
      </section>

      <section class="panel">
        <h2>Strežnik</h2>
        <dl class="kv">
          <dt>Node</dt><dd>${system.node}</dd>
          <dt>Platforma</dt><dd>${system.platform}</dd>
          <dt>Uptime</dt><dd>${system.uptime}</dd>
          <dt>Pomnilnik</dt><dd>${system.memUsed} / ${system.memTotal} MB</dd>
          <dt>Velikost baze</dt><dd>${system.dataSize} KB</dd>
          <dt>Zadnja kopija</dt><dd>${system.lastBackup ? relTime(system.lastBackup) : 'še ni - naredi jo v Podatki & izvoz'}</dd>
        </dl>
      </section>
    </div>
  </div>`;
  return adminLayout(cfg, { title: 'Nadzorna plošča', children, user, active: 'dashboard', csrf });
}

/* ------------------------------- PRIJAVE --------------------------------- */
export function applicationsPage(cfg, { user, csrf, rows, total, page, pages, status, q, sort = 'newest', flash, errors = {}, open = null }) {
  const children = html`
  ${flash ? html`<div class="flash flash--${flash.kind}">${flash.text}</div>` : ''}
  <header class="head">
    <div><h1>Prijavnice</h1><p class="muted">${total} zapisov · filtrirano po "${status || 'vse'}"</p></div>
    <div class="row">
      <a class="btn btn--ghost" href="/admin/prijave/export">Izvozi CSV</a>
      <a class="btn ${cfg.applications.open ? 'btn--danger' : 'btn--primary'}" href="/admin/nastavitve">
        ${cfg.applications.open ? 'Zapri prijave' : 'Odpri prijave'}
      </a>
    </div>
  </header>

  <form class="filter" method="get" action="/admin/prijave">
    <input type="search" name="q" value="${q}" placeholder="išči: ime, discord, koda, license...">
    <select name="status">
      ${['', 'pending', 'more_info', 'approved', 'denied'].map((s) => html`<option value="${s}" ${s === status ? raw('selected') : ''}>${s ? STATUS_LABEL[s] : 'vsi statusi'}</option>`)}
    </select>
    <select name="sort">
      ${[['newest', 'najnovejše'], ['oldest', 'najstarejše'], ['oldest_pending', 'čaka najdlje']].map(([v, l]) => html`<option value="${v}" ${v === sort ? raw('selected') : ''}>${l}</option>`)}
    </select>
    <button class="btn btn--sm" type="submit">Filtriraj</button>
  </form>

  <div class="acc">
    ${rows.length ? rows.map((a) => appCard({ a, csrf, errors, open })) : html`<div class="panel muted">Ni zadetkov.</div>`}
  </div>
  ${pager(page, pages, status, q)}`;
  return adminLayout(cfg, { title: 'Prijavnice', children, user, active: 'applications', csrf });
}

function appCard({ a, csrf, errors, open }) {
  const isOpen = open === a.id;
  return html`
  <article class="panel acc__item ${a.status === 'pending' ? 'is-new' : ''}">
    <div class="acc__head">
      <div>
        <b>${a.ingame}</b> <code class="code--sm">${a.code}</code> ${appStatus(a.status)}
        <p class="muted tiny">${a.discord} · starost ${a.age} · oddano ${fmtDate(a.submittedAt)} (${relTime(a.submittedAt)})${a.ip ? html` · IP ${a.ip}` : ''}</p>
      </div>
      <a class="btn btn--ghost btn--sm" href="/admin/prijave?id=${a.id}${isOpen ? '' : '#otok'}">${isOpen ? 'Skrij' : 'Odpri'}</a>
    </div>
    <div class="acc__body">
      <dl class="kv kv--3">
        <dt>Ime</dt><dd>${a.name}</dd>
        <dt>Steam</dt><dd><code>${a.steam || '-'}</code></dd>
        <dt>FiveM</dt><dd><code>${a.license || '-'}</code></dd>
      </dl>
      <p class="prose">${a.message}</p>
      ${a.reviewNote ? html`<p class="note"><b>Odločitev (${a.reviewedBy || 'ekipa'}, ${fmtDate(a.reviewedAt)}):</b> ${a.reviewNote}</p>` : ''}
      ${isOpen || a.status === 'pending' || a.status === 'more_info' ? html`
      <div class="acts">
        <form method="post" action="/admin/prijave/odloci">
          <input type="hidden" name="_csrf" value="${csrf}">
          <input type="hidden" name="id" value="${a.id}">
          <textarea name="note" rows="3" placeholder="Obrazložitev (vidna igralcu na strani Status)...">${a.reviewNote || ''}</textarea>
          <div class="row">
            <button class="btn btn--primary btn--sm" name="decision" value="approved" type="submit">${icon('check')} Sprejmi in dodaj na WL</button>
            <button class="btn btn--warn btn--sm" name="decision" value="more_info" type="submit">Prosim za dodatno</button>
            <button class="btn btn--danger btn--sm" name="decision" value="denied" type="submit">${icon('x')} Zavrni</button>
          </div>
          ${errors[a.id] ? html`<span class="fld__err">${errors[a.id]}</span>` : ''}
        </form>
        <form method="post" action="/admin/prijave/izbrisi" data-confirm="Res izbrišem prijavnico? To je nepovratno (dnevnik ostane).">
          <input type="hidden" name="_csrf" value="${csrf}">
          <input type="hidden" name="id" value="${a.id}">
          <button class="btn btn--ghost btn--sm" type="submit">Izbriši prijavnico</button>
        </form>
      </div>` : ''}
    </div>
  </article>`;
}

function pager(page, pages, status, q) {
  if (pages <= 1) return raw('');
  const link = (p, label, disabled = false) =>
    disabled ? html`<span class="pg pg--off">${label}</span>` : html`<a class="pg" href="/admin/prijave?page=${p}&status=${status}&q=${q}">${label}</a>`;
  return html`
  <div class="pager">
    ${link(page - 1, '←', page <= 1)}
    <span class="muted tiny">stran ${page} / ${pages}</span>
    ${link(page + 1, '→', page >= pages)}
  </div>`;
}

/* ------------------------------- IGRALCI --------------------------------- */
export function playersPage(cfg, { user, csrf, rows, total, page, pages, q, status, flash, errors = {}, form = null }) {
  const children = html`
  ${flash ? html`<div class="flash flash--${flash.kind}">${flash.text}</div>` : ''}
  <header class="head">
    <div><h1>Igralci</h1><p class="muted">${total} zapisov. To je vaša baza - podatki so v <code>data/players.json</code>.</p></div>
    <div class="row">
      <a class="btn btn--ghost" href="/admin/igralci/export.csv">CSV</a>
      <button class="btn btn--primary" form="player-form" type="submit">Shrani</button>
    </div>
  </header>

  <form class="panel" id="player-form" method="post" action="/admin/igralci/shrani">
    <input type="hidden" name="_csrf" value="${csrf}">
    <input type="hidden" name="id" value="${form?.id || ''}">
    <div class="row row--tight"><h3>${form?.id ? 'Uredi igralca' : 'Nov igralec'}</h3>
      ${form?.id ? html`<span class="muted tiny">ustvarjen ${fmtDate(form.createdAt)}</span>` : ''}</div>
    <div class="grid3">
      ${field({ name: 'ingame', label: 'Ingame ime', value: form?.ingame, required: true, error: errors.ingame })}
      ${field({ name: 'name', label: 'Ime in priimek', value: form?.name })}
      ${field({ name: 'discord', label: 'Discord', value: form?.discord, error: errors.discord })}
      ${field({ name: 'steam', label: 'Steam ID', value: form?.steam, error: errors.steam })}
      ${field({ name: 'license', label: 'FiveM identifier', value: form?.license, help: 'license:... / steam:...' })}
      ${field({ name: 'job', label: 'Služba / frakcija', value: form?.job })}
      <label class="fld"><span class="fld__label">Status</span>
        <select name="status">
          ${['active', 'trial', 'inactive', 'banned'].map((s) => html`<option value="${s}" ${form?.status === s ? raw('selected') : ''}>${s}</option>`)}
        </select>
      </label>
      ${field({ name: 'wlExpires', label: 'WL velja do', type: 'date', value: (form?.wlExpires || '').slice(0, 10), error: errors.wlExpires, help: 'Prazno = brez poteka' })}
    </div>
    ${field({ name: 'notes', label: 'Opombe (samo za osebje)', type: 'textarea', rows: 4, value: form?.notes })}
    <div class="row">
      <button class="btn btn--primary" type="submit">Shrani igralca</button>
      ${form?.id ? html`<a class="btn btn--ghost" href="/admin/igralci">Prekliči</a>` : ''}
    </div>
  </form>

  <form class="filter" method="get" action="/admin/igralci">
    <input type="search" name="q" value="${q}" placeholder="išči po imenu, discordu, licenci...">
    <select name="status">
      ${['', 'active', 'trial', 'inactive', 'banned'].map((s) => html`<option value="${s}" ${s === status ? raw('selected') : ''}>${s || 'vsi statusi'}</option>`)}
    </select>
    <button class="btn btn--sm" type="submit">Filtriraj</button>
  </form>

  <table class="table">
    <thead><tr><th>Ingame</th><th>Discord</th><th>Identifier</th><th>Status</th><th>WL do</th><th></th></tr></thead>
    <tbody>
      ${rows.length ? rows.map((p) => html`
        <tr>
          <td><b>${p.ingame}</b><br><span class="muted tiny">${p.name || ''}</span></td>
          <td>${p.discord || '-'}</td>
          <td><code>${p.license || '-'}</code></td>
          <td><span class="badge badge--${p.status === 'banned' ? 'bad' : p.status === 'active' ? 'ok' : 'pending'}">${p.status}</span></td>
          <td>${p.wlExpires ? fmtDate(p.wlExpires, false) : '-'}</td>
          <td class="row row--tight">
            <a class="btn btn--ghost btn--sm" href="/admin/igralci/${p.id}">Uredi</a>
            <form method="post" action="/admin/igralci/izbrisi" data-confirm="Izbrišem tega igralca?">
              <input type="hidden" name="_csrf" value="${csrf}"><input type="hidden" name="id" value="${p.id}">
              <button class="btn btn--danger btn--sm" type="submit">Izbriši</button>
            </form>
          </td>
        </tr>`) : html`<tr><td colspan="6" class="muted">Ni igralcev. Dodaj prvega zgoraj ali počakaj na odobrene prijave (te samodejno ustvarijo zapis).</td></tr>`}
    </tbody>
  </table>
  ${pager(page, pages, status, q)}`;
  return adminLayout(cfg, { title: 'Igralci', children, user, active: 'players', csrf });
}

/* ------------------------------ WHITELIST -------------------------------- */
export function whitelistPage(cfg, { user, csrf, rows, total, q, flash, errors = {}, exportInfo }) {
  const children = html`
  ${flash ? html`<div class="flash flash--${flash.kind}">${flash.text}</div>` : ''}
  <header class="head">
    <div><h1>Whitelist</h1><p class="muted">${total} zapisov. FiveM skripta lahko bere prek <code>/api/whitelist/check</code> ali izvožene datoteke.</p></div>
    <div class="row">
      <a class="btn btn--ghost" href="/admin/whitelist/export.json">Izvozi (JSON)</a>
      <a class="btn btn--ghost" href="/admin/whitelist/export.csv">CSV</a>
    </div>
  </header>

  <form class="panel" method="post" action="/admin/whitelist/dodaj">
    <input type="hidden" name="_csrf" value="${csrf}">
    <div class="grid3">
      ${field({ name: 'identifier', label: 'FiveM identifier', value: '', required: true, placeholder: 'license:abc... / steam:110000...', error: errors.identifier })}
      ${field({ name: 'ingame', label: 'Ingame ime', value: '' })}
      ${field({ name: 'discord', label: 'Discord', value: '' })}
      ${field({ name: 'expires', label: 'Velja do', type: 'date', value: '', error: errors.expires, help: 'Prazno = večno' })}
      ${field({ name: 'note', label: 'Opomba', value: '' })}
      <label class="check"><input type="checkbox" name="forever" checked><span>Brez poteka</span></label>
    </div>
    <button class="btn btn--primary" type="submit">Dodaj na whitelist</button>
  </form>

  <form class="filter" method="get" action="/admin/whitelist">
    <input type="search" name="q" value="${q}" placeholder="išči identifier / ime">
    <button class="btn btn--sm" type="submit">Išči</button>
  </form>

  <table class="table">
    <thead><tr><th>Identifier</th><th>Igralec</th><th>Dodano</th><th>Velja do</th><th>Dodao</th><th></th></tr></thead>
    <tbody>
      ${rows.length ? rows.map((w) => {
    const expired = w.expires && Date.parse(w.expires) < Date.now();
    return html`
        <tr>
          <td><code>${w.identifier}</code></td>
          <td>${w.ingame || '-'}<br><span class="muted tiny">${w.discord || ''}</span></td>
          <td title="${fmtDate(w.createdAt)}">${relTime(w.createdAt)}</td>
          <td>${w.expires ? html`<span class="${expired ? 'bad' : ''}">${fmtDate(w.expires, false)}</span>` : 'večno'}</td>
          <td>${w.addedBy || '-'}</td>
          <td>
            <form method="post" action="/admin/whitelist/odstrani" data-confirm="Odstranim ta zapis s whiteliste?">
              <input type="hidden" name="_csrf" value="${csrf}"><input type="hidden" name="id" value="${w.id}">
              <button class="btn btn--danger btn--sm" type="submit">Odstrani</button>
            </form>
          </td>
        </tr>`;
  }) : html`<tr><td colspan="6" class="muted">Whitelist je prazna.</td></tr>`}
    </tbody>
  </table>

  <section class="panel">
    <h3>Stanje izvoza</h3>
    <dl class="kv">
      <dt>Datoteka</dt><dd><code>${exportInfo.file}</code> ${exportInfo.exists ? html`${icon('check')}` : html`<span class="bad">(še ni zapisana)</span>`}</dd>
      <dt>Zapisi</dt><dd>${exportInfo.count}</dd>
      <dt>Kopije</dt><dd>${exportInfo.copyTo.length ? exportInfo.copyTo.map((c) => html`<code>${c}</code>`).join(raw(' ')) : 'brez (nastavi config.whitelist.copyTo)'}</dd>
    </dl>
    <p class="tiny muted">Ob vsaki spremembi se izvoz osveži samodejno. Ročno: <code>POST /admin/whitelist/izvozi</code> ali gumb na nadzorni plošči.</p>
  </section>`;
  return adminLayout(cfg, { title: 'Whitelist', children, user, active: 'whitelist', csrf });
}

/* -------------------------------- LOGI ---------------------------------- */
export function logsPage(cfg, { user, csrf, data, level, type, q, flash, limit, allTypes = [] }) {
  const types = [...new Set(allTypes)].sort();
  const children = html`
  ${flash ? html`<div class="flash flash--${flash.kind}">${flash.text}</div>` : ''}
  <header class="head">
    <div><h1>Dnevnik dogodkov</h1><p class="muted">${data.total} zapisov ustreza filtru. Shranjeno v <code>data/logs/events.jsonl</code> - preživi znovni zagon strežnika in posodobitve.</p></div>
    <div class="row">
      <a class="btn btn--ghost" href="/admin/logi/prenesi.txt">Prenesi (.txt)</a>
      <a class="btn btn--ghost" href="/admin/logi/prenesi.jsonl">Prenesi (.jsonl)</a>
    </div>
  </header>
  ${user?.role === 'owner' ? html`
  <form class="panel panel--inline" method="post" action="/admin/logi/pocisti" data-confirm="Res počistim starejše dnevnike? To se ne da razveljaviti.">
    <input type="hidden" name="_csrf" value="${csrf}">
    <span class="muted tiny">GDPR / čiščenje: izbriši zapise, starejše od</span>
    <input type="number" name="days" value="${cfg.logs.retentionDays}" min="1" max="3650">
    <span class="muted tiny">dni</span>
    <button class="btn btn--sm" type="submit">Počisti</button>
  </form>` : ''}

  <form class="filter" method="get" action="/admin/logi">
    <input type="search" name="q" value="${q}" placeholder="išči po sporočilu, akterju, IP...">
    <select name="level">
      ${['', ...['debug', 'info', 'warn', 'error']].map((l) => html`<option value="${l}" ${l === level ? raw('selected') : ''}>${l || 'vse ravni'}</option>`)}
    </select>
    <select name="type">
      ${['', ...types].map((t) => html`<option value="${t}" ${t === type ? raw('selected') : ''}>${t || 'vse vrste'}</option>`)}
    </select>
    <select name="limit">
      ${[100, 200, 500, 1000].map((n) => html`<option value="${n}" ${n === limit ? raw('selected') : ''}>${n} zapisov</option>`)}
    </select>
    <button class="btn btn--sm" type="submit">Filtriraj</button>
    <a class="btn btn--ghost btn--sm" href="/admin/logi">Ponastavi</a>
  </form>

  <table class="table table--log">
    <thead><tr><th>Čas</th><th>Raven</th><th>Dogodek</th><th>Akter</th><th>IP</th><th>Sporočilo</th></tr></thead>
    <tbody>
      ${data.rows.length ? data.rows.map((l) => html`
        <tr class="lv--${l.level}">
          <td class="nowrap" title="${l.ts}">${fmtDate(l.ts)}</td>
          <td><span class="pill pill--${l.level}">${l.level}</span></td>
          <td><code>${l.type}</code></td>
          <td>${l.actor}</td>
          <td class="muted">${l.ip || '-'}</td>
          <td>${l.message}${l.meta ? html`<br><span class="muted tiny">${JSON.stringify(l.meta)}</span>` : ''}</td>
        </tr>`) : html`<tr><td colspan="6" class="muted">Ni zadetkov.</td></tr>`}
    </tbody>
  </table>
  ${data.rows.length >= limit ? html`<p class="tiny muted">Prikazanih je zadnjih ${limit} zapisov. Za več povečaj limit ali prenesi celotno datoteko.</p>` : ''}`;
  return adminLayout(cfg, { title: 'Dnevnik', children, user, active: 'logs', csrf });
}

/* ---------------------------- PODATKI & IZVOZ ----------------------------- */
export function dataPage(cfg, { user, csrf, sizes, flash, backups, apps }) {
  const children = html`
  ${flash ? html`<div class="flash flash--${flash.kind}">${flash.text}</div>` : ''}
  <header class="head"><div><h1>Podatki & izvoz</h1><p class="muted">Vse je na tem VPS-u. Redno kopiraj mapo <code>${cfg.dataDir}</code>.</p></div></header>

  <div class="cols">
    <div>
      <section class="panel">
        <h2>Prenesi</h2>
        <table class="table">
          <thead><tr><th>Zbirka</th><th>Zapisi</th><th></th></tr></thead>
          <tbody>
            ${sizes.map((s) => html`
            <tr>
              <td><b>${s.name}</b><br><span class="muted tiny">${s.file} · ${s.kb} KB</span></td>
              <td>${s.count}</td>
              <td class="row row--tight">
                <a class="btn btn--ghost btn--sm" href="/admin/podatki/izvozi/${s.key}.json">JSON</a>
                <a class="btn btn--ghost btn--sm" href="/admin/podatki/izvozi/${s.key}.csv">CSV</a>
              </td>
            </tr>`)}
            <tr>
              <td><b>Vse skupaj</b><br><span class="muted tiny">vse zbirke v eni datoteki</span></td>
              <td>${sizes.reduce((n, s) => n + s.count, 0)}</td>
              <td><a class="btn btn--primary btn--sm" href="/admin/podatki/izvozi/all.json">Izvozi vse</a></td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="panel">
        <h2>Varnostna kopija</h2>
        <p class="muted tiny">Stisnjene (.gz) kopije vseh zbirk v <code>${cfg.backup.dir}</code>. Samodejno vsakih ${cfg.backup.everyHours} ur, hrani se ${cfg.backup.keepDays} dni.</p>
        <form method="post" action="/admin/podatki/kopija">
          <input type="hidden" name="_csrf" value="${csrf}">
          <div class="row">
            <button class="btn btn--primary btn--sm" type="submit">Naredi kopijo zdaj</button>
            ${backups.length ? html`
              <select name="day">
                ${backups.map((b) => html`<option value="${b.day}">${b.day} (${b.files} datotek)</option>`)}
              </select>
              <button class="btn btn--ghost btn--sm" type="submit" formaction="/admin/podatki/obnovi">Obnovi iz izbrane kopije</button>` : ''}
          </div>
        </form>
        <p class="tiny bad">${backups.length ? '' : 'Še ni nobene kopije - naredi prvo zdaj.'}</p>
      </section>
    </div>

    <div class="side">
      <section class="panel">
        <h2>Zasebnost</h2>
        <ul class="bullets">
          <li>Igralci in prijave <b>niso</b> javno dostopni - samo prijava in status s kodo.</li>
          <li>Gesla v <code>config.json</code> se ob prvem zagonu zhaširajo, original ne ostane na disku.</li>
          <li>Mapa <code>data/</code> je v <code>.gitignore</code> - nikoli na GitHub.</li>
          <li>Dnevniki ne vsebujejo gesel; IP naslovi se hranijo zaradi preprečevanja zlorab.</li>
        </ul>
      </section>
      <section class="panel">
        <h2>Prijave za brisanje</h2>
        <p class="muted tiny">Igralec lahko preko Discordja zahteva izbris. Poišči ga po kodi in izbriši.</p>
        <table class="table">
          <tbody>${apps.length ? apps.map((a) => html`<tr><td><code>${a.code}</code></td><td>${a.ingame}</td><td class="muted tiny">${fmtDate(a.submittedAt, false)}</td></tr>`) : html`<tr><td class="muted">ni</td></tr>`}</tbody>
        </table>
      </section>
    </div>
  </div>`;
  return adminLayout(cfg, { title: 'Podatki', children, user, active: 'data', csrf });
}

/* ------------------------------ NASTAVITVE ------------------------------- */
export function settingsPage(cfg, { user, csrf, flash, errors = {}, live, staff, token }) {
  const children = html`
  ${flash ? html`<div class="flash flash--${flash.kind}">${flash.text}</div>` : ''}
  <header class="head"><div><h1>Nastavitve</h1><p class="muted">Spremembe so takoj aktivne (shranjeno v <code>data/settings.json</code> in preglašajo <code>config.json</code>).</p></div></header>

  <div class="cols">
    <div>
      <form class="panel" method="post" action="/admin/nastavitve">
        <input type="hidden" name="_csrf" value="${csrf}">
        <h2>Podatki o strani</h2>
        <div class="grid2">
          ${field({ name: 'siteName', label: 'Ime strani', value: live.siteName, required: true })}
          ${field({ name: 'siteTagline', label: 'Podnaslov', value: live.siteTagline, required: true })}
          ${field({ name: 'discordInvite', label: 'Discord povabilo', value: live.discordInvite })}
          ${field({ name: 'serverConnect', label: 'Connect naslov', value: live.serverConnect, placeholder: 'connect play.example.si' })}
        </div>
        <h2>Prijave</h2>
        <div class="grid3">
          <label class="check"><input type="checkbox" name="applicationsOpen" ${live.applications.open ? raw('checked') : ''}><span>Prijavnice so odprte</span></label>
          ${field({ name: 'minAge', label: 'Najnižja starost (leta)', type: 'number', value: live.applications.minAge, attrs: raw('min="13" max="99"') })}
          ${field({ name: 'maxPerIpPerDay', label: 'Največ prijav / IP / dan', type: 'number', value: live.applications.maxPerIpPerDay, attrs: raw('min="1" max="50"') })}
        </div>
        <div class="row">
          <button class="btn btn--primary" type="submit">Shrani nastavitve</button>
        </div>
      </form>

      <section class="panel">
        <h2>API za FiveM</h2>
        <p class="muted tiny">Skripta na strežniku preverja whitelist brez obiska strani.</p>
        <pre class="snippet">GET ${live.publicUrl || 'https://tvoja-domena.si'}/api/whitelist/check?token=${token || '(ni nastavljen)'}&license=steam:110000xxxxx</pre>
        <form class="row" method="post" action="/admin/nastavitve/token">
          <input type="hidden" name="_csrf" value="${csrf}">
          <button class="btn btn--sm" type="submit">${token ? 'Zamenjaj API token' : 'Ustvari API token'}</button>
          ${token ? html`<span class="muted tiny">trenutni: <code>${token.slice(0, 6)}…${token.slice(-4)}</code></span>` : ''}
        </form>
        ${errors.token ? html`<p class="fld__err">${errors.token}</p>` : ''}
      </section>

      <form class="panel" method="post" action="/admin/geslo">
        <input type="hidden" name="_csrf" value="${csrf}">
        <h2>Geslo (moj račun)</h2>
        <div class="grid2">
          ${field({ name: 'current', label: 'Trenutno geslo', type: 'password', required: true, error: errors.current, attrs: raw('autocomplete="current-password"') })}
          ${field({ name: 'password', label: 'Novo geslo (12+ znakov)', type: 'password', required: true, attrs: raw('autocomplete="new-password" minlength="12"') })}
          ${field({ name: 'password2', label: 'Ponovi', type: 'password', required: true, attrs: raw('autocomplete="new-password" minlength="12"') })}
        </div>
        <button class="btn btn--primary" type="submit">Spremeni geslo</button>
      </form>
    </div>

    <div class="side">
      <section class="panel">
        <div class="row"><h2>Osebje</h2></div>
        <table class="table">
          <tbody>
            ${staff.map((s) => html`
              <tr>
                <td><b>${s.username}</b><br><span class="muted tiny">${s.role} · prijav ${s.logins || 0}×</span></td>
                <td>${s.lastLoginAt ? relTime(s.lastLoginAt) : html`<span class="muted">nikoli</span>`}</td>
                <td class="row row--tight">
                  ${s.mustChangePassword ? html`<span class="badge badge--warn">čaka geslo</span>` : ''}
                  ${s.id !== user.id ? html`
                    <form method="post" action="/admin/osebje/geslo">
                      <input type="hidden" name="_csrf" value="${csrf}"><input type="hidden" name="id" value="${s.id}">
                      <button class="btn btn--ghost btn--sm" type="submit" title="Ponastavi geslo na naključno">Novo geslo</button>
                    </form>
                    <form method="post" action="/admin/osebje/izbrisi" data-confirm="Odstranim uporabnika?">
                      <input type="hidden" name="_csrf" value="${csrf}"><input type="hidden" name="id" value="${s.id}">
                      <button class="btn btn--danger btn--sm" type="submit">Izbriši</button>
                    </form>` : ''}
                </td>
              </tr>`)}
          </tbody>
        </table>
        <form class="panel panel--inset" method="post" action="/admin/osebje/dodaj">
          <input type="hidden" name="_csrf" value="${csrf}">
          <h3>Nov uporabnik</h3>
          <div class="grid2">
            ${field({ name: 'username', label: 'Uporabnik', error: errors.username })}
            ${field({ name: 'password', label: 'Začetno geslo', type: 'password', error: errors.password, attrs: raw('minlength="12"') })}
            <label class="fld"><span class="fld__label">Vloga</span>
              <select name="role"><option value="moderator">moderator</option><option value="viewer">pregledovalec</option></select>
            </label>
          </div>
          <button class="btn btn--primary btn--sm" type="submit">Dodaj</button>
        </form>
      </section>
    </div>
  </div>`;
  return adminLayout(cfg, { title: 'Nastavitve', children, user, active: 'settings', csrf });
}

export { STATUS_LABEL, APP_STATUS };
