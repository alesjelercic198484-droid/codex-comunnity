'use strict';

/* CodeX Community – WL odjemalec */

let me = null;
let staffFilter = 'all';
let cache = { applications: [], users: [] };

const $ = (sel) => document.querySelector(sel);
const STATUS_SL = { pending: 'V obdelavi', approved: 'Odobreno', denied: 'Zavrnjeno' };
const ROLE_SL = { player: 'Igralec', moderator: 'Moderator', administrator: 'Administrator' };

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    method: options.method || 'GET',
    headers: options.body ? { 'Content-Type': 'application/json' } : undefined,
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  let data = {};
  try { data = await res.json(); } catch { /* brez telesa */ }
  if (!res.ok) throw new Error(data.error || 'Napaka ' + res.status);
  return data;
}

function toast(msg, isError = false) {
  const t = document.createElement('div');
  t.id = 'toast';
  if (isError) t.classList.add('error');
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3500);
}

function badge(status) {
  return `<span class="badge ${esc(status)}">${STATUS_SL[status] || esc(status)}</span>`;
}
function roleBadge(role) {
  return `<span class="role-badge role-${esc(role)}">${ROLE_SL[role] || esc(role)}</span>`;
}
function fmtDate(iso) {
  return iso ? new Date(iso).toLocaleString('sl-SI') : '—';
}

/* ---------- Auth pogled ---------- */
function showAuth() {
  $('#auth-view').classList.remove('hidden');
  $('#app-view').classList.add('hidden');
  $('#nav-user').innerHTML = '';
}

function switchTab(which) {
  const login = which === 'login';
  $('#tab-login').classList.toggle('active', login);
  $('#tab-register').classList.toggle('active', !login);
  $('#login-form').classList.toggle('hidden', !login);
  $('#register-form').classList.toggle('hidden', login);
  $('#auth-error').classList.add('hidden');
}

function showAuthError(msg) {
  const el = $('#auth-error');
  el.textContent = msg;
  el.classList.remove('hidden');
}

/* ---------- Glavni pogled ---------- */
function isStaff() { return me && (me.role === 'moderator' || me.role === 'administrator'); }
function isAdmin() { return me && me.role === 'administrator'; }

function showApp() {
  $('#auth-view').classList.add('hidden');
  $('#app-view').classList.remove('hidden');

  $('#nav-user').innerHTML = `
    <span class="who"><b>${esc(me.username)}</b> ${roleBadge(me.role)}</span>
    <button class="btn secondary small" id="logout-btn"><i class="fa-solid fa-right-from-bracket"></i> Odjava</button>
  `;
  $('#logout-btn').addEventListener('click', async () => {
    await api('/api/logout', { method: 'POST' });
    me = null;
    showAuth();
  });

  $('#staff-section').classList.toggle('hidden', !isStaff());
  $('#admin-section').classList.toggle('hidden', !isAdmin());

  refresh();
}

async function refresh() {
  try {
    const [appsRes, usersRes] = await Promise.all([
      api('/api/applications'),
      isAdmin() ? api('/api/users').catch(() => ({ users: cache.users })) : Promise.resolve({ users: cache.users }),
    ]);
    cache.applications = appsRes.applications;
    cache.users = usersRes.users;

    const mine = cache.applications.filter((a) => a.userId === me.id);
    renderNoticeAndForm(mine);
    renderMyApps(mine);
    if (isStaff()) renderStaffApps();
    if (isAdmin()) renderUsers();
  } catch (e) {
    toast(e.message, true);
  }
}

/* ---------- Nova prijava + obvestilo ---------- */
function renderNoticeAndForm(mine) {
  const pending = mine.find((a) => a.status === 'pending');
  const notice = $('#notice');
  const formSection = $('#new-app-section');

  if (pending) {
    notice.className = 'info-box';
    notice.innerHTML = `<i class="fa-solid fa-hourglass-half"></i> Vaša WL prijava (oddana ${esc(fmtDate(pending.createdAt))}) je <b>v obdelavi</b>. Znova lahko oddate, ko bo odločeno.`;
    notice.classList.remove('hidden');
    formSection.classList.add('hidden');
  } else {
    notice.classList.add('hidden');
    formSection.classList.remove('hidden');
  }
}

/* ---------- Moje prijave ---------- */
function appDetailsHtml(a, showUser) {
  return `
    <div class="fields">
      ${showUser ? `<div><span class="k">Igralec:</span> <b>${esc(a.username)}</b></div>` : ''}
      <div><span class="k">RP ime in priimek:</span> ${esc(a.rpName)}</div>
      <div><span class="k">Starost:</span> ${esc(a.age)}</div>
      <div><span class="k">Discord tag:</span> ${esc(a.discordTag)}</div>
      <div><span class="k">Steam HEX:</span> ${esc(a.steamHex)}</div>
      <div><span class="k">Oddano:</span> ${esc(fmtDate(a.createdAt))}</div>
    </div>
    <div class="k muted" style="font-size:.85rem">Izkušnje z RP:</div>
    <div class="long">${esc(a.rpExperience)}</div>
    <div class="k muted" style="font-size:.85rem;margin-top:8px">Motivacija:</div>
    <div class="long">${esc(a.motivation)}</div>
    ${a.status !== 'pending' ? `
      <div class="review-out">
        <b>Odločitev:</b> ${badge(a.status)}
        ${a.reviewedBy ? ` — pregledal <b>${esc(a.reviewedBy)}</b> (${esc(fmtDate(a.reviewedAt))})` : ''}
        ${a.reviewNote ? `<div style="margin-top:6px"><span class="k">Opomba:</span> ${esc(a.reviewNote)}</div>` : ''}
      </div>` : ''}
  `;
}

function renderMyApps(mine) {
  const el = $('#my-apps');
  if (!mine.length) {
    el.innerHTML = '<div class="empty">Še nimate oddanih prijav. Izpolnite obrazec zgoraj. 🎮</div>';
    return;
  }
  el.innerHTML = mine
    .map(
      (a) => `
      <div class="app-item">
        <div class="head">
          <div>
            <div class="title">Prijava #${a.id} — ${esc(a.rpName)}</div>
            <div class="meta">Oddana: ${esc(fmtDate(a.createdAt))}</div>
          </div>
          ${badge(a.status)}
        </div>
        ${a.status !== 'pending' && a.reviewNote ? `<div class="review-out"><span class="k">Opomba moderatorja:</span> ${esc(a.reviewNote)}</div>` : ''}
      </div>`
    )
    .join('');
}

/* ---------- Staff: vse prijave ---------- */
function renderStaffApps() {
  const el = $('#staff-apps');
  const list = cache.applications.filter((a) => staffFilter === 'all' || a.status === staffFilter);

  if (!list.length) {
    el.innerHTML = '<div class="empty">Ni prijav za prikazan filter.</div>';
    return;
  }

  el.innerHTML = list
    .map((a) => {
      const own = a.userId === me.id;
      const reviewControls =
        a.status === 'pending' && !own
          ? `
          <div class="review-row" data-id="${a.id}">
            <textarea rows="2" maxlength="500" placeholder="Opomba igralcu (neobvezno) …" class="review-note"></textarea>
            <button class="btn approve small act-review" data-id="${a.id}" data-status="approved"><i class="fa-solid fa-check"></i> Odobri</button>
            <button class="btn deny small act-review" data-id="${a.id}" data-status="denied"><i class="fa-solid fa-xmark"></i> Zavrni</button>
          </div>`
          : '';

      return `
      <div class="app-item">
        <div class="head">
          <div>
            <div class="title">Prijava #${a.id} — ${esc(a.rpName)} ${own ? '<span class="muted">(vaša)</span>' : ''}</div>
            <div class="meta">Igralec: ${esc(a.username)} · Oddana: ${esc(fmtDate(a.createdAt))}</div>
          </div>
          ${badge(a.status)}
        </div>
        ${appDetailsHtml(a, false)}
        ${reviewControls}
      </div>`;
    })
    .join('');

  el.querySelectorAll('.act-review').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const status = btn.dataset.status;
      const row = el.querySelector(`.review-row[data-id="${id}"]`);
      const note = row ? row.querySelector('.review-note').value.trim() : '';
      try {
        await api('/api/applications/review', { method: 'POST', body: { id, status, note } });
        toast(status === 'approved' ? 'Prijava je odobrena ✅' : 'Prijava je zavrnjena ❌');
        refresh();
      } catch (e) {
        toast(e.message, true);
      }
    });
  });
}

/* ---------- Admin: uporabniki ---------- */
function renderUsers() {
  const el = $('#users-table');
  if (!cache.users.length) {
    el.innerHTML = '<div class="empty">Ni uporabnikov.</div>';
    return;
  }
  const rows = [...cache.users]
    .sort((a, b) => a.id - b.id)
    .map((u) => {
      const self = u.id === me.id;
      const roleCell = self
        ? `${roleBadge(u.role)} <span class="muted">(vi)</span>`
        : `
        <select data-id="${u.id}" class="role-select">
          ${['player', 'moderator', 'administrator']
            .map((r) => `<option value="${r}" ${u.role === r ? 'selected' : ''}>${ROLE_SL[r]}</option>`)
            .join('')}
        </select>`;
      return `
        <tr>
          <td><b>${esc(u.username)}</b></td>
          <td>${roleCell}</td>
          <td>${esc(fmtDate(u.createdAt))}</td>
        </tr>`;
    })
    .join('');

  el.innerHTML = `
    <table class="users">
      <thead><tr><th>Uporabnik</th><th>Vloga</th><th>Registriran</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>`;

  el.querySelectorAll('.role-select').forEach((sel) => {
    sel.addEventListener('change', async () => {
      const id = Number(sel.dataset.id);
      try {
        await api('/api/users/role', { method: 'POST', body: { id, role: sel.value } });
        toast('Vloga je posodobljena.');
        refresh();
      } catch (e) {
        toast(e.message, true);
        refresh();
      }
    });
  });
}

/* ---------- Init ---------- */
function bindForms() {
  $('#tab-login').addEventListener('click', () => switchTab('login'));
  $('#tab-register').addEventListener('click', () => switchTab('register'));

  $('#login-form').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = new FormData(ev.target);
    try {
      const data = await api('/api/login', {
        method: 'POST',
        body: { username: fd.get('username'), password: fd.get('password') },
      });
      me = data.user;
      ev.target.reset();
      showApp();
    } catch (e) {
      showAuthError(e.message);
    }
  });

  $('#register-form').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = new FormData(ev.target);
    try {
      const data = await api('/api/register', {
        method: 'POST',
        body: {
          username: fd.get('username'),
          password: fd.get('password'),
          staffCode: fd.get('staffCode'),
        },
      });
      me = data.user;
      ev.target.reset();
      showApp();
      toast('Račun je ustvarjen. Dobrodošli! 🎉');
    } catch (e) {
      showAuthError(e.message);
    }
  });

  $('#application-form').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = new FormData(ev.target);
    try {
      await api('/api/applications', {
        method: 'POST',
        body: {
          rpName: fd.get('rpName'),
          age: Number(fd.get('age')),
          discordTag: fd.get('discordTag'),
          steamHex: fd.get('steamHex'),
          rpExperience: fd.get('rpExperience'),
          motivation: fd.get('motivation'),
        },
      });
      ev.target.reset();
      toast('Prijava je oddana! 🎉');
      refresh();
    } catch (e) {
      toast(e.message, true);
    }
  });

  $('#staff-filters').addEventListener('click', (ev) => {
    const btn = ev.target.closest('.chip');
    if (!btn) return;
    staffFilter = btn.dataset.f;
    document.querySelectorAll('#staff-filters .chip').forEach((c) => c.classList.toggle('active', c === btn));
    renderStaffApps();
  });
}

document.addEventListener('DOMContentLoaded', async () => {
  $('#year').textContent = new Date().getFullYear();
  bindForms();
  try {
    const data = await api('/api/me');
    me = data.user;
    showApp();
  } catch {
    showAuth();
  }
});
