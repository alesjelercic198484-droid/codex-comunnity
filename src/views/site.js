import { html, raw, fmtDate, relTime } from '../util.js';
import { layout, field, icon, appStatus } from './layout.js';

export function siteLayout(cfg, opts) {
  return layout(cfg, { ...opts, admin: false });
}

/* ------------------------------- DOMOV ---------------------------------- */
export function homePage(cfg, { stats, flash, user, recent = [] }) {
  const cards = [
    ['Zasebni skripti', 'V lastni režiji napisani sistemi: službe, gospodarska bilanca, banke, telefoni in lasten anti-cheat ključ. Ni kopiranih "free" skriptov.', 'gear'],
    ['Ekskluzivna vozila', 'Mafijski paketi, tuning in redka vozila, ki jih na drugih strežnikih ne dobiš. Vsa vozila so testirana pred izdajo.', 'shield'],
    ['Lastni MLO', 'Nadgrajene stavbe, notranjosti in lokacije, ki so narejene za to mapo in ne za "univerzalno" uporabo.', 'file'],
    ['Pošteni whitelist', 'Prijavnice bere ekipa - ne bot. Vsaka odločitev je zabeležena v dnevniku, zato veš, zakaj si bil sprejet ali zavrnjen.', 'users'],
  ];
  const steps = [
    ['1', 'Izpolni prijavnico', 'Povestaš kdo si, kaj iščeš v vlogi in katere ure lahko igraš. Traja 5 minut.'],
    ['2', 'Ekipa pregleda', 'Odgovor dobiš običajno v 24 do 48 urah. Do takrat lahko stanje spremljaš s kodo prijave.'],
    ['3', 'Dobiš whitelist', 'Ob odobritvi je tvoj FiveM identifier takoj v whitelisti na strežniku in dobiš Discord vlogo.'],
    ['4', 'Vstopiš na strežnik', 'Vpišeš connect naslov, igraš. Ekipa spremlja obnašanje in ne krši pravil - sicer WL mirno umaknemo.'],
  ];
  const children = html`
  <section class="hero">
    <div class="hero__glow" aria-hidden="true"></div>
    <p class="eyebrow">${cfg.serverConnect ? raw(`<code>${cfg.serverConnect}</code> · `) : ''} whitelist odprt: <b class="${cfg.applications.open ? 'ok' : 'bad'}">${cfg.applications.open ? 'DA' : 'NE'}</b></p>
    <h1>${cfg.siteName}</h1>
    <p class="lede">${cfg.siteTagline}. Igraš lahko samo, če si na whitelisti - zato je tukaj resna prijava, pregled in dnevnik odločitev.</p>
    <div class="hero__cta">
      <a class="btn btn--primary" href="/prijava">Oddaj prijavnico ${icon('file')}</a>
      <a class="btn" href="${cfg.discordInvite}" target="_blank" rel="noopener">${icon('discord')} Discord</a>
      <a class="btn btn--ghost" href="/status">Preveri status prijave</a>
    </div>
    <dl class="stats">
      <div><dt>Igralcev v bazi</dt><dd>${stats.players}</dd></div>
      <div><dt>Na whitelisti</dt><dd>${stats.whitelist}</dd></div>
      <div><dt>Odprtih prijav</dt><dd>${stats.pending}</dd></div>
      <div><dt>Zadnja odobritev</dt><dd>${stats.lastApproved ? relTime(stats.lastApproved) : 'še ni'}</dd></div>
    </dl>
  </section>

  <section class="grid2">
    ${cards.map(([t, d, ic]) => html`
      <article class="card">
        <span class="card__ico">${icon(ic)}</span>
        <h3>${t}</h3>
        <p>${d}</p>
      </article>`)}
  </section>

  <section class="steps">
    <h2>Kako do whiteliste</h2>
    <ol>
      ${steps.map(([n, t, d]) => html`
        <li class="step"><span class="step__n">${n}</span><div><h4>${t}</h4><p>${d}</p></div></li>`)}
    </ol>
  </section>

  ${recent.length ? html`
  <section class="recent">
    <h2>Zadnje odločitve</h2>
    <p class="muted">Javno so objavljene samo odobrene prijave, brez osebnih podatkov.</p>
    <table class="table table--light">
      <thead><tr><th>Igralec</th><th>Status</th><th>Odločeno</th></tr></thead>
      <tbody>
        ${recent.map((r) => html`<tr><td>${r.ingame}</td><td>${appStatus(r.status)}</td><td>${fmtDate(r.reviewedAt || r.updatedAt)}</td></tr>`)}
      </tbody>
    </table>
  </section>` : ''}

  <section class="cta">
    <h2>Si pripravljen na resen roleplay?</h2>
    <p>Prijavnica te ne zavezuje. V primeru zavračanja lahko čez 30 dni poskusiš znova.</p>
    <a class="btn btn--primary" href="/prijava">Oddaj prijavnico</a>
  </section>`;
  return siteLayout(cfg, { title: '', children, flash, user, active: 'home' });
}

/* ---------------------------- PRIJAVNICA -------------------------------- */
export function applyPage(cfg, { form = {}, errors = {}, flash, user, values = {} }) {
  const open = cfg.applications.open;
  const children = html`
  <section class="page">
    <header class="page__head">
      <h1>Prijava za whitelist</h1>
      <p class="muted">Vsi podatki se shranijo v bazo na tem VPS-u in so vidni samo ekipi. Z njimi ne trgujeva in jih ne deliva naprej.</p>
    </header>
    ${!open ? html`
      <div class="flash flash--warn">Prijave so trenutno <b>zaprte</b>. Spremljaj Discord za odprtje novih terminov.</div>` : html`
    <form class="panel" method="post" action="/prijava" novalidate>
      <input type="hidden" name="_csrf" value="${form.csrf}">
      <input class="hp" type="text" name="website" value="" tabindex="-1" autocomplete="off" aria-hidden="true">
      <div class="grid2">
        ${field({ name: 'name', label: 'Ime in priimek', value: values.name, required: true, maxlength: 80, placeholder: 'Janez Novak', error: errors.name, help: 'Za preverjanje istovetnosti ob morebitni pritožbi.' })}
        ${field({ name: 'ingame', label: 'Ingame ime', value: values.ingame, required: true, maxlength: 32, placeholder: 'Jane_Novak', error: errors.ingame, help: 'Tako te bodo videli na strežniku.' })}
        ${field({ name: 'discord', label: 'Discord uporabniško ime', value: values.discord, required: true, maxlength: 40, placeholder: 'codex.janez', error: errors.discord, help: 'Brez @, npr. ime ali ime#1234.' })}
        ${field({ name: 'steam', label: 'Steam ID', value: values.steam, required: !!cfg.applications.requireSteamId, maxlength: 40, placeholder: 'STEAM_0:1:12345678', error: errors.steam, help: 'Steam → Nastavitve → Naslov (Kopiraj).' })}
        ${field({ name: 'license', label: 'FiveM license ključ', value: values.license, required: !!cfg.applications.requireLicenseKey, maxlength: 120, placeholder: 'steam:110000112345678', error: errors.license, help: 'Vpiši /license v peti in kopiraj vrednost.' })}
        ${field({ name: 'age', label: 'Starost', value: values.age, type: 'number', required: true, maxlength: 3, attrs: raw('min="13" max="100" step="1"'), error: errors.age, help: `Najmanj ${cfg.applications.minAge} let.` })}
      </div>
      ${field({
    name: 'message',
    label: 'Zakaj baš CodeX in kaj prinašaš?',
    type: 'textarea',
    value: values.message,
    required: true,
    maxlength: cfg.applications.maxCharsMessage,
    rows: 9,
    error: errors.message,
    help: 'Napiši kaj si želiš igrati (zdravnik, mehanik, mafija...), koliko ur tedensko igraš in ali imaš izkušnje z RP. Najmanj 120 znakov.',
  })}
      <label class="check ${errors.rules ? 'has-error' : ''}">
        <input type="checkbox" name="rules" ${values.rules ? 'checked' : ''}>
        <span>Strinjam se s <a href="/pravila">pravili skupnosti</a> in dovoljujem, da se moji podatki hranijo na VPS-u zaradi preverjanja whiteliste.</span>
      </label>
      ${errors.rules ? html`<span class="fld__err">${errors.rules}</span>` : ''}
      <div class="form__foot">
        <button class="btn btn--primary" type="submit">Pošlji prijavnico</button>
        <span class="muted">Po pošiljanju dobiš kodo za spremljanje.</span>
      </div>
    </form>`}
  </section>`;
  return siteLayout(cfg, { title: 'Prijava za whitelist', children, flash, user, active: 'apply' });
}

/* ---------------------------- KODA PRIJAVE ------------------------------ */
export function submittedPage(cfg, { app }) {
  const children = html`
  <section class="page page--narrow">
    <div class="panel panel--center">
      <span class="tick">${icon('check')}</span>
      <h1>Prijava je shranjena</h1>
      <p>Tvoja prijava je v čakalni vrsti. Shrani si kodo - z njo lahko kadarkoli preveriš stanje:</p>
      <p class="code">${app.code}</p>
      <p class="muted">Kodo pošlji samo ekipi, če jo morajo ročno poiskati. Dnevnik dogodka je bil zapisan ob ${fmtDate(app.submittedAt)}.</p>
      <div class="hero__cta">
        <a class="btn btn--primary" href="/status">Preveri status</a>
        <a class="btn" href="${cfg.discordInvite}" target="_blank" rel="noopener">Discord</a>
      </div>
    </div>
  </section>`;
  return siteLayout(cfg, { title: 'Prijava oddana', children, active: 'apply' });
}

/* ------------------------------- STATUS --------------------------------- */
export function statusPage(cfg, { values = {}, errors = {}, result, app }) {
  const children = html`
  <section class="page page--narrow">
    <header class="page__head">
      <h1>Status prijave</h1>
      <p class="muted">Vnesi kodo, ki si jo dobil ob oddaji, in svoj Discord.</p>
    </header>
    <form class="panel" method="post" action="/status">
      <input type="hidden" name="_csrf" value="${values.csrf}">
      <div class="grid2">
        ${field({ name: 'code', label: 'Koda prijave', value: values.code, required: true, placeholder: 'CDX-4F7K2A', error: errors.code })}
        ${field({ name: 'discord', label: 'Discord', value: values.discord, required: true, placeholder: 'codex.janez', error: errors.discord })}
      </div>
      <div class="form__foot"><button class="btn btn--primary" type="submit">Prikaži stanje</button></div>
    </form>
    ${result === 'found' && app ? html`
      <div class="panel">
        <div class="row">
          <h3>Prijava ${app.code}</h3>${appStatus(app.status)}
        </div>
        <ol class="timeline">
          <li class="${app.submittedAt ? 'done' : ''}"><span>Oddana</span><b>${fmtDate(app.submittedAt)}</b></li>
          <li class="${app.status !== 'pending' ? 'done' : app.submittedAt ? 'now' : ''}">
            <span>${app.status === 'pending' ? 'V obdelavi pri ekipi' : 'Pregledana'}</span><b>${app.reviewedAt ? fmtDate(app.reviewedAt) : 'čaka'}</b>
          </li>
          <li class="${app.status === 'approved' ? 'done' : ''}"><span>Whitelist na strežniku</span><b>${app.status === 'approved' ? 'aktivna' : '-'}</b></li>
        </ol>
        ${app.reviewNote ? html`<p class="note"><b>Opomba ekipe:</b> ${app.reviewNote}</p>` : ''}
        ${app.status === 'approved' ? html`<p class="note note--ok">Dobiš Discord vlogo in se lahko takoj povežeš. ${cfg.serverConnect ? raw(`Vpiši: <code>${cfg.serverConnect}</code>`) : ''}</p>` : ''}
        ${app.status === 'denied' ? html`<p class="note note--bad">Čez 30 dni lahko oddaš novo prijavo in upoštevaj opombo ekipe.</p>` : ''}
      </div>` : ''}
    ${result === 'notfound' ? html`<div class="flash flash--warn">Prijave s to kodo ni. Preveri, ali si prav prepisal kodo in Discord.</div>` : ''}
  </section>`;
  return siteLayout(cfg, { title: 'Status prijave', children, active: 'status' });
}

/* ------------------------------- PRAVILA -------------------------------- */
export function rulesPage(cfg) {
  const rules = [
    ['Spoštovanje je osnova', 'Ni sovražnega govora, ni žalitev na račun narodnosti, vere, spola ali usmerjenosti. En prekršek in whitelist je zunaj.'],
    ['Ni varypanja, ni prevare', 'Prerender, aim, auto-clickerji, prodaja predmetov za pravi denar in zloraba hroščev - takšna in podobna - so prepovedani.'],
    ['RP ostaja RP', 'Valhalla / RDM in metagaming so prepovedani. Metagaming pomeni informacije, ki jih nisi dobil v igri.'],
    ['Ni napadov na osebje', 'Odločitve ekipe lahko pritožiš na Discordu, ne pa z napadi na strežnik ali stran.'],
    ['Podatki', 'Prijavnico lahko kadar koli umakneš s prošnjo na Discordu; podatke izbrišemo v 48 urah. Hranimo ime, Discord, Steam ID in FiveM licenco.'],
    ['Glasovno', 'Uporabljaj mikrofon, ki deluje. Ni glasbe, ni push-to-talk zvočnih efektov, ki ovirajo RP.'],
  ];
  const children = html`
  <section class="page">
    <header class="page__head"><h1>Pravila</h1><p class="muted">Kratka, a jih drži. Ob prijavi potrdiš, da se strinjaš z njimi.</p></header>
    ${rules.map(([t, d], i) => html`
      <article class="rule"><h3>${i + 1}. ${t}</h3><p>${d}</p></article>`)}
  </section>`;
  return siteLayout(cfg, { title: 'Pravila', children, active: 'rules' });
}

/* -------------------------------- ERPORI -------------------------------- */
export function errorPage(cfg, { code = 404, title = 'Ne najdem te strani', text = '', user = null }) {
  const children = html`
  <section class="page page--narrow">
    <div class="panel panel--center">
      <p class="code code--big">${code}</p>
      <h1>${title}</h1>
      <p class="muted">${text || 'Stran ne obstaja ali je bila odstranjena.'}</p>
      <div class="hero__cta"><a class="btn btn--primary" href="/">Nazaj domov</a><a class="btn" href="/prijava">Prijava za WL</a></div>
    </div>
  </section>`;
  return siteLayout(cfg, { title: `${code}`, children, user, active: '' });
}
