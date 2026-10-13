/* codex_policecreator - department terminal UI (vanilla JS, no build step) */

const RES = 'codex_policecreator';

let mode = 'menu';
let data = null;          // boss menu payload
let creatorData = null;   // creator payload
let activeTab = 'dashboard';
let calls = [];
let evidencePoint = null;
let lastError = null;

const $ = (id) => document.getElementById(id);
const app = $('app');
const sidebar = $('sidebar');
const content = $('content');

/* ------------------------------------------------------------------ utils */

function money(value) {
  const n = Math.floor(Number(value) || 0);
  return (n < 0 ? '-$' : '$') + Math.abs(n).toLocaleString('en-US');
}

function esc(value) {
  return String(value === null || value === undefined ? '' : value)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function status(message, kind) {
  $('statusText').textContent = message || '';
  $('statusText').className = kind || '';
}

async function act(name, payload) {
  try {
    const response = await fetch(`https://${RES}/action`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: name, data: payload || {} })
    });
    const body = await response.json().catch(() => ({}));
    if (body && body.ok === false) {
      lastError = body.error || 'action failed';
      status('Error: ' + lastError, 'muted');
    }
    return body;
  } catch (error) {
    status('NUI error: ' + error.message, 'muted');
    return null;
  }
}

async function readPosition() {
  try {
    const response = await fetch(`https://${RES}/position`, { method: 'POST', body: '{}' });
    return await response.json();
  } catch (error) {
    return null;
  }
}

function close() {
  app.classList.add('hidden');
  fetch(`https://${RES}/close`, { method: 'POST', body: '{}' }).catch(() => {});
}

function pill(value, kind) {
  return `<span class="pill ${kind || value}">${esc(value)}</span>`;
}

function empty(message) {
  return `<div class="empty">${esc(message)}</div>`;
}

function notice() {
  if (!lastError) return '';
  const html = `<div class="notice error">${esc(lastError)}</div>`;
  lastError = null;
  return html;
}

/* ------------------------------------------------------------------ header */

function renderHeader() {
  if (mode === 'creator') {
    $('deptBadge').textContent = 'ADM';
    $('deptLabel').textContent = 'Department Creator';
    $('deptSub').textContent = 'Create departments and place nodes in the world';
    $('statFunds').textContent = '-';
    $('statMembers').textContent = String((creatorData && creatorData.departments) ? Object.keys(creatorData.departments).length : 0);
    $('statCalls').textContent = '-';
    $('dutyBtn').classList.add('hidden');
    return;
  }

  const dept = data && data.dept;
  const member = data && data.member;
  const rank = data && data.rank;

  $('deptBadge').textContent = (dept && dept.label ? dept.label : 'PD').split(' ').map(w => w[0]).join('').slice(0, 3).toUpperCase();
  $('deptBadge').style.background = (dept && dept.color) || '#2f6df6';
  $('deptLabel').textContent = dept ? dept.label : 'No department';
  $('deptSub').textContent = member
    ? `${member.firstName} ${member.lastName} - ${rank ? rank.label : 'Unknown rank'}`
    : 'Not a member';

  $('statFunds').textContent = money(dept ? dept.funds : 0);
  $('statMembers').textContent = String(data && data.members ? data.members.length : 0);
  $('statCalls').textContent = String(calls.filter(c => c.status !== 'closed').length);

  const dutyBtn = $('dutyBtn');
  dutyBtn.classList.remove('hidden');
  dutyBtn.textContent = member && member.onDuty ? 'Go off duty' : 'Go on duty';
  dutyBtn.className = 'btn ' + (member && member.onDuty ? 'danger' : 'ok');
}

/* ------------------------------------------------------------------ tabs */

function tabList() {
  if (mode === 'creator') {
    return [
      { id: 'departments', label: 'Departments' },
      { id: 'newdept', label: 'New department' },
      { id: 'nodes', label: 'Nodes' }
    ];
  }

  if (mode === 'armory') return [{ id: 'armory', label: 'Armory' }];
  if (mode === 'garage') return [{ id: 'garage', label: 'Garage' }];
  if (mode === 'evidence') return [{ id: 'evidenceForm', label: 'Bag evidence' }];
  if (mode === 'k9') return [{ id: 'k9', label: 'K9 Unit' }];

  const perms = (data && data.perms) || {};
  const tabs = [
    { id: 'dashboard', label: 'Dashboard' },
    { id: 'members', label: 'Members', perm: 'manage' },
    { id: 'dispatch', label: 'Dispatch', perm: 'dispatch' },
    { id: 'evidence', label: 'Evidence', perm: 'evidence' },
    { id: 'garage', label: 'Vehicles', perm: 'garage' },
    { id: 'armory', label: 'Armory', perm: 'armory' },
    { id: 'bolo', label: 'BOLO / ALPR', perm: 'bolo' },
    { id: 'cameras', label: 'Cameras', perm: 'cameras' },
    { id: 'trackers', label: 'GPS trackers', perm: 'trackers' },
    { id: 'finance', label: 'Finances', perm: 'finance' },
    { id: 'ranks', label: 'Ranks', perm: 'ranks' },
    { id: 'divisions', label: 'Divisions', perm: 'divisions' },
    { id: 'applications', label: 'Applications', perm: 'applications' },
    { id: 'dutylogs', label: 'Duty logs' },
    { id: 'anims', label: 'Animations' }
  ];

  return tabs.filter(tab => !tab.perm || perms[tab.perm]);
}

function renderSidebar() {
  const tabs = tabList();
  if (!tabs.some(tab => tab.id === activeTab)) activeTab = tabs.length ? tabs[0].id : 'dashboard';

  sidebar.innerHTML = tabs.map(tab =>
    `<button data-tab="${tab.id}" class="${tab.id === activeTab ? 'active' : ''}">${esc(tab.label)}</button>`
  ).join('');

  sidebar.querySelectorAll('button').forEach(button => {
    button.addEventListener('click', () => {
      activeTab = button.dataset.tab;
      render();
    });
  });
}

/* ------------------------------------------------------------------ views */

function viewDashboard() {
  const dept = data.dept || {};
  const member = data.member || {};
  const rank = data.rank || {};
  const perms = data.perms || {};

  const online = (data.members || []).filter(m => m.online).length;
  const onDuty = (data.members || []).filter(m => m.onDuty).length;

  const permChips = Object.keys(perms).filter(k => perms[k]).join(', ') || 'none';

  return `
    ${notice()}
    <div class="card">
      <h2>${esc(dept.label || '')}</h2>
      <div class="row">
        <div class="grow">
          <p class="muted">Type: ${esc(dept.type)} &middot; Internal name: <strong>${esc(dept.name)}</strong></p>
          <p class="muted">Your rank: <strong>${esc(rank.label || '-')}</strong> (grade ${rank.grade})</p>
          <p class="muted">Permissions: ${esc(permChips)}</p>
        </div>
        <div>
          <div class="stat"><span>Online</span><strong>${online}</strong></div>
          <div class="stat"><span>On duty</span><strong>${onDuty}</strong></div>
          <div class="stat"><span>Funds</span><strong>${money(dept.funds)}</strong></div>
        </div>
      </div>
    </div>

    <div class="card">
      <h3>Quick actions</h3>
      <div class="row">
        <button class="btn" id="quickDuty">${member.onDuty ? 'Go off duty' : 'Go on duty'}</button>
        <button class="btn ghost" id="quickCall">Create a dispatch call</button>
        <button class="btn ghost" id="quickRefresh">Reload data</button>
      </div>
    </div>

    <div class="card">
      <h3>Recent transactions</h3>
      ${(data.finance || []).length ? `<table><thead><tr><th>Date</th><th>Type</th><th>By</th><th class="right">Amount</th><th class="right">Balance</th></tr></thead><tbody>
        ${data.finance.slice(0, 8).map(row => `<tr>
          <td class="muted">${esc(row.date)}</td>
          <td>${esc(row.type)}</td>
          <td>${esc(row.name)}</td>
          <td class="right">${money(row.amount)}</td>
          <td class="right muted">${money(row.balance)}</td>
        </tr>`).join('')}
      </tbody></table>` : empty('No transactions yet')}
    </div>
  `;
}

function viewMembers() {
  const ranks = data.dept.ranks || [];
  const divisions = data.dept.divisions || [];

  return `
    ${notice()}
    <div class="card">
      <h3>Hire</h3>
      <div class="row">
        <input id="hireCitizen" placeholder="Citizen ID" />
        <input id="hireFirst" placeholder="First name" />
        <input id="hireLast" placeholder="Last name" />
        <select id="hireRank">
          ${ranks.map(r => `<option value="${r.id}">${esc(r.label)} (${r.grade})</option>`).join('')}
        </select>
        <button class="btn" id="hireBtn">Hire by ID</button>
        <button class="btn ghost" id="hireNearbyBtn">Hire player next to me</button>
      </div>
      <p class="muted">Promotions are limited to ranks below your own unless you are the boss.</p>
    </div>

    <div class="card">
      <h3>Members (${(data.members || []).length})</h3>
      ${(data.members || []).length ? `<table>
        <thead><tr><th>Name</th><th>Rank</th><th>Division</th><th class="right">Salary</th><th>Status</th><th class="right">Duty time</th><th class="right">Actions</th></tr></thead>
        <tbody>
        ${data.members.map(m => `<tr>
          <td>${esc(m.name)}<br><span class="muted">${esc(m.citizenid)}</span></td>
          <td>${esc(m.rank)}</td>
          <td>
            <select data-division="${esc(m.citizenid)}">
              <option value="0">-</option>
              ${divisions.map(d => `<option value="${d.id}" ${d.id === m.divisionId ? 'selected' : ''}>${esc(d.label)}</option>`).join('')}
            </select>
          </td>
          <td class="right">${money(m.salary)}</td>
          <td>${m.online ? pill('online') : pill('offline')} ${m.onDuty ? pill('on duty', 'duty') : ''}</td>
          <td class="right muted">${m.dutySeconds ? Math.floor(m.dutySeconds / 3600) + 'h' : '-'}</td>
          <td class="right">
            <select data-rank="${esc(m.citizenid)}">
              ${ranks.map(r => `<option value="${r.id}" ${r.id === m.rankId ? 'selected' : ''}>${esc(r.label)}</option>`).join('')}
            </select>
            <input data-salary="${esc(m.citizenid)}" type="number" value="${m.salary}" style="min-width:80px" />
            <button class="btn small" data-bonus="${esc(m.citizenid)}">Bonus</button>
            <button class="btn small danger" data-fire="${esc(m.citizenid)}">Fire</button>
          </td>
        </tr>`).join('')}
        </tbody></table>` : empty('No members yet')}
    </div>
  `;
}

function viewFinance() {
  return `
    ${notice()}
    <div class="card">
      <h3>Society funds: ${money(data.dept.funds)}</h3>
      <div class="row">
        <input id="finAmount" type="number" placeholder="Amount" value="1000" />
        <button class="btn ok" id="depositBtn">Deposit (your bank)</button>
        <button class="btn danger" id="withdrawBtn">Withdraw to your bank</button>
      </div>
    </div>
    <div class="card">
      <h3>Transactions</h3>
      ${(data.finance || []).length ? `<table>
        <thead><tr><th>Date</th><th>Type</th><th>By</th><th class="right">Amount</th><th class="right">Balance after</th></tr></thead>
        <tbody>${data.finance.map(row => `<tr>
          <td class="muted">${esc(row.date)}</td>
          <td>${esc(row.type)}</td>
          <td>${esc(row.name)}</td>
          <td class="right">${money(row.amount)}</td>
          <td class="right muted">${money(row.balance)}</td>
        </tr>`).join('')}</tbody>
      </table>` : empty('Nothing recorded yet')}
    </div>
  `;
}

function viewRanks() {
  const ranks = (data.dept.ranks || []).slice().sort((a, b) => a.grade - b.grade);

  return `
    ${notice()}
    <div class="card">
      <h3>New rank</h3>
      <div class="row">
        <input id="rankLabel" placeholder="Rank label" />
        <input id="rankGrade" type="number" placeholder="Grade (auto)" />
        <input id="rankSalary" type="number" placeholder="Salary" value="250" />
        <label style="display:flex;align-items:center;gap:6px;margin:0"><input type="checkbox" id="rankBoss" /> Boss rank</label>
        <button class="btn" id="rankCreateBtn">Create rank</button>
      </div>
    </div>
    <div class="card">
      <h3>Ranks</h3>
      ${ranks.length ? `<table><thead><tr><th>Grade</th><th>Label</th><th class="right">Salary</th><th>Permissions</th><th class="right">Actions</th></tr></thead>
      <tbody>${ranks.map(r => `<tr>
        <td>${r.grade}</td>
        <td><input data-ranklabel="${r.id}" value="${esc(r.label)}" /></td>
        <td class="right"><input data-ranksalary="${r.id}" type="number" value="${r.salary}" style="min-width:90px" /></td>
        <td>
          <div class="perms">
            ${['dispatch', 'evidence', 'garage', 'armory', 'bolo', 'cameras', 'trackers', 'manage', 'applications', 'finance', 'divisions', 'ranks']
              .map(p => `<label><input type="checkbox" data-perm="${r.id}" data-permname="${p}" ${String(r.perms || '').split(',').includes(p) ? 'checked' : ''} />${p}</label>`).join('')}
          </div>
        </td>
        <td class="right">
          <button class="btn small" data-ranksave="${r.id}">Save</button>
          <button class="btn small danger" data-rankdelete="${r.id}">Delete</button>
        </td>
      </tr>`).join('')}</tbody></table>` : empty('No ranks defined')}
    </div>
  `;
}

function viewDivisions() {
  const divisions = data.dept.divisions || [];
  return `
    ${notice()}
    <div class="card">
      <h3>New division</h3>
      <div class="row">
        <input id="divName" placeholder="Internal name (k9)" />
        <input id="divLabel" placeholder="Display label (K9 Unit)" />
        <button class="btn" id="divCreateBtn">Create division</button>
      </div>
    </div>
    <div class="card">
      <h3>Divisions (${divisions.length})</h3>
      ${divisions.length ? `<table><thead><tr><th>Name</th><th>Label</th><th class="right">Actions</th></tr></thead>
      <tbody>${divisions.map(d => `<tr>
        <td>${esc(d.name)}</td><td>${esc(d.label)}</td>
        <td class="right"><button class="btn small danger" data-divdelete="${d.id}">Delete</button></td>
      </tr>`).join('')}</tbody></table>` : empty('No divisions yet')}
    </div>
  `;
}

function viewApplications() {
  const list = data.applications || [];
  return `
    ${notice()}
    <div class="card">
      <h3>Applications (${list.length})</h3>
      ${list.length ? `<table><thead><tr><th>Name</th><th>Message</th><th>Status</th><th class="right">Actions</th></tr></thead>
      <tbody>${list.map(a => `<tr>
        <td>${esc(a.first_name)} ${esc(a.last_name)}<br><span class="muted">${esc(a.citizenid)}</span></td>
        <td>${esc(a.message)}</td>
        <td>${pill(a.status)}</td>
        <td class="right">
          ${a.status === 'pending' ? `
            <button class="btn small ok" data-appaccept="${a.id}">Accept</button>
            <button class="btn small danger" data-appdeny="${a.id}">Deny</button>` : ''}
        </td>
      </tr>`).join('')}</tbody></table>` : empty('No applications')}
    </div>
  `;
}

function viewDispatch() {
  const codes = data.codes || [];
  return `
    ${notice()}
    <div class="card">
      <h3>New call</h3>
      <div class="row">
        <select id="callCode">
          ${codes.map(c => `<option value="${esc(c.code)}">${esc(c.code)} - ${esc(c.label)}</option>`).join('')}
        </select>
        <input id="callDescription" class="grow" placeholder="Description" />
        <button class="btn" id="callCreateBtn">Send to dispatch</button>
      </div>
      <p class="muted">Calls are sent to your current position and to every department of the matching type.</p>
    </div>
    <div class="card">
      <h3>Calls</h3>
      ${calls.length ? `<table><thead><tr><th>Code</th><th>Description</th><th>Caller</th><th>Status</th><th>Unit</th><th>Time</th><th class="right">Actions</th></tr></thead>
      <tbody>${calls.map(c => `<tr>
        <td><strong>${esc(c.code)}</strong><br><span class="muted">${esc(c.label)}</span></td>
        <td>${esc(c.description || '-')}</td>
        <td>${esc(c.callerName || c.caller_name || 'Anonymous')}</td>
        <td>${pill(c.status)}</td>
        <td>${esc(c.assignedName || c.assigned_name || '-')}</td>
        <td class="muted">${esc(c.date || '')}</td>
        <td class="right">
          ${c.status === 'pending' ? `<button class="btn small ok" data-callaccept="${c.id}">Accept</button>` : ''}
          ${c.status === 'active' ? `<button class="btn small ghost" data-callrelease="${c.id}">Release</button>` : ''}
          ${c.status !== 'closed' ? `<button class="btn small danger" data-callclose="${c.id}">Close</button>` : ''}
        </td>
      </tr>`).join('')}</tbody></table>` : empty('No calls recorded')}
    </div>
  `;
}

function viewBolo() {
  const types = data.boloTypes || [];
  const list = data.bolos || [];
  return `
    ${notice()}
    <div class="card">
      <h3>New BOLO</h3>
      <div class="row">
        <select id="boloType">
          ${types.map(t => `<option value="${esc(t.type)}">${esc(t.label)}</option>`).join('')}
        </select>
        <input id="boloValue" placeholder="Plate / name / model" />
        <input id="boloDescription" class="grow" placeholder="Description" />
        <button class="btn" id="boloCreateBtn">Publish BOLO</button>
      </div>
      <p class="muted">Plate BOLOs are shared with every department and are matched by the ALPR.</p>
    </div>
    <div class="card">
      <h3>BOLOs (${list.length})</h3>
      ${list.length ? `<table><thead><tr><th>Type</th><th>Value</th><th>Description</th><th>By</th><th>Status</th><th class="right">Actions</th></tr></thead>
      <tbody>${list.map(b => `<tr>
        <td>${esc(b.type)}</td>
        <td><strong>${esc(b.value)}</strong></td>
        <td>${esc(b.description)}</td>
        <td class="muted">${esc(b.createdBy)}</td>
        <td>${b.active ? pill('active') : pill('inactive', 'closed')}</td>
        <td class="right">
          <button class="btn small ghost" data-bolotoggle="${b.id}" data-active="${b.active ? 0 : 1}">${b.active ? 'Deactivate' : 'Activate'}</button>
          <button class="btn small danger" data-bolodelete="${b.id}">Delete</button>
        </td>
      </tr>`).join('')}</tbody></table>` : empty('No BOLOs')}
    </div>
  `;
}

function viewEvidence() {
  const list = data.evidence || [];
  const grades = {};
  return `
    ${notice()}
    <div class="card">
      <h3>Evidence board (${list.length})</h3>
      ${list.length ? `<table><thead><tr><th>#</th><th>Label</th><th>Grade</th><th>Officer</th><th>Owner</th><th>Date</th><th class="right">Actions</th></tr></thead>
      <tbody>${list.map(e => `<tr>
        <td class="muted">${e.id}</td>
        <td><strong>${esc(e.label)}</strong><br><span class="muted">${esc(e.description)}</span></td>
        <td>${e.grade}</td>
        <td>${esc(e.officer)}</td>
        <td>${esc(e.owner || '-')}</td>
        <td class="muted">${esc(e.date)}</td>
        <td class="right">
          ${e.takenBy ? pill('checked out', 'closed') : `<button class="btn small" data-evidencetake="${e.id}">Check out</button>`}
          <button class="btn small danger" data-evidencedelete="${e.id}">Destroy</button>
        </td>
      </tr>`).join('')}</tbody></table>` : empty('No evidence stored')}
    </div>
    <p class="muted">Use an evidence bag from your inventory to add a new item to this board.</p>
    ${grades}
  `;
}

function viewEvidenceForm() {
  const grades = (data && data.grades) || [
    { level: 1, label: 'Low' }, { level: 2, label: 'Medium' }, { level: 3, label: 'High' }, { level: 4, label: 'Critical' }
  ];

  return `
    <div class="card">
      <h3>Bag this evidence</h3>
      <div class="field"><label>Item label</label><input id="evLabel" style="width:100%" placeholder="Bloody knife" /></div>
      <div class="field"><label>Description</label><textarea id="evDescription" placeholder="Found next to the victim, 21cm blade"></textarea></div>
      <div class="field"><label>Suspect / owner</label><input id="evOwner" style="width:100%" placeholder="John Doe (optional)" /></div>
      <div class="field"><label>Severity</label>
        <select id="evGrade" style="width:100%">
          ${grades.map(g => `<option value="${g.level}">${g.level} - ${esc(g.label)}</option>`).join('')}
        </select>
      </div>
      <p class="muted">Position: ${evidencePoint ? `${evidencePoint.x.toFixed(1)}, ${evidencePoint.y.toFixed(1)}, ${evidencePoint.z.toFixed(1)}` : 'unknown'}</p>
      <div class="row">
        <button class="btn ok" id="evSubmit">Store evidence</button>
        <button class="btn ghost" id="evCancel">Cancel</button>
      </div>
    </div>
  `;
}

function viewGarage() {
  const vehicles = data.vehicles || [];
  const grade = data.rank ? data.rank.grade : -1;
  const nodeId = data.nodeId || (data.dept && (data.dept.nodes || []).filter(n => n.type === 'garage')[0] || {}).id;

  return `
    ${notice()}
    <div class="card">
      <h3>Department vehicles</h3>
      ${vehicles.length ? `<table><thead><tr><th>Label</th><th>Model</th><th>Plate</th><th class="right">Min grade</th><th>Fuel</th><th>Status</th><th class="right">Actions</th></tr></thead>
      <tbody>${vehicles.map(v => `<tr>
        <td><strong>${esc(v.label)}</strong></td>
        <td>${esc(v.model)}</td>
        <td>${esc(v.plate)}</td>
        <td class="right">${v.rankMin}</td>
        <td>${v.fuel}%</td>
        <td>${v.impounded ? pill('impounded', 'pending') : (v.stored ? pill('stored', 'online') : pill('out', 'duty'))}</td>
        <td class="right">
          <button class="btn small ok" data-spawn="${v.id}" ${(!v.stored || v.impounded || grade < v.rankMin) ? 'disabled' : ''}>Take out</button>
          <button class="btn small ghost" data-impound="${v.id}" data-impounded="${v.impounded ? 0 : 1}">${v.impounded ? 'Release' : 'Impound'}</button>
          <button class="btn small danger" data-garageremove="${v.id}">Delete</button>
        </td>
      </tr>`).join('')}</tbody></table>` : empty('No vehicles configured')}
      <p class="muted">Selected garage node: ${nodeId || 'none - place a garage node with /deptcreator'}</p>
    </div>
    <div class="card">
      <h3>Add vehicle</h3>
      <div class="row">
        <input id="vehModel" placeholder="Model (police3)" />
        <input id="vehLabel" placeholder="Label" />
        <input id="vehRank" type="number" placeholder="Min grade" value="0" style="min-width:90px" />
        <input id="vehLivery" type="number" placeholder="Livery (-1)" value="-1" style="min-width:90px" />
        <button class="btn" id="vehAddBtn">Add vehicle</button>
      </div>
    </div>
  `;
}

function viewArmory() {
  const items = data.armory || [];
  return `
    ${notice()}
    <div class="card">
      <h3>Armory</h3>
      <div class="grid">
        ${items.map(item => `
          <div class="tile">
            <h4>${esc(item.label)}</h4>
            <p>${esc(item.item)} &middot; min grade ${item.rank}${item.ammo ? ' &middot; ' + item.ammo + ' rounds' : ''}</p>
            <div class="row">
              <button class="btn small ok" data-armorytake="${item.index}" ${item.allowed ? '' : 'disabled'}>Take</button>
              <button class="btn small ghost" data-armorystore="${item.index}">Return</button>
            </div>
          </div>
        `).join('')}
      </div>
      ${items.length ? '' : empty('Armory is empty - edit Config.Armory.Items')}
    </div>
  `;
}

function viewCameras() {
  const list = data.cameras || [];
  return `
    ${notice()}
    <div class="card">
      <h3>Cameras (${list.length})</h3>
      ${list.length ? `<div class="grid">${list.map(c => `
        <div class="tile">
          <h4>${esc(c.label)}</h4>
          <p>${c.x.toFixed(1)}, ${c.y.toFixed(1)}, ${c.z.toFixed(1)} &middot; min grade ${c.rankMin}</p>
          <div class="row">
            <button class="btn small" data-viewcamera="${c.id}">View feed</button>
            <button class="btn small danger" data-cameraremove="${c.id}">Delete</button>
          </div>
        </div>`).join('')}</div>` : empty('No cameras placed')}
    </div>
    <div class="card">
      <h3>Add camera here</h3>
      <div class="row">
        <input id="camLabel" placeholder="Label" />
        <input id="camRank" type="number" value="0" placeholder="Min grade" style="min-width:90px" />
        <button class="btn" id="camAddBtn">Place camera at my position</button>
      </div>
    </div>
  `;
}

function viewTrackers() {
  const list = data.trackers || [];
  return `
    ${notice()}
    <div class="card">
      <h3>Active GPS trackers (${list.length})</h3>
      ${list.length ? `<table><thead><tr><th>Plate</th><th>Placed by</th><th>Position</th><th>Since</th><th class="right">Actions</th></tr></thead>
      <tbody>${list.map(t => `<tr>
        <td><strong>${esc(t.plate)}</strong></td>
        <td>${esc(t.placedBy)}</td>
        <td>${t.x.toFixed(1)}, ${t.y.toFixed(1)}</td>
        <td class="muted">${esc(t.date)}</td>
        <td class="right">
          <button class="btn small" data-trackrecover="${t.id}">Recover</button>
          <button class="btn small danger" data-trackremove="${t.id}">Deactivate</button>
        </td>
      </tr>`).join('')}</tbody></table>` : empty('No active trackers')}
      <p class="muted">Use the tracker item on a vehicle to attach one. Positions update while the placing officer is online.</p>
    </div>
  `;
}

function viewDutyLogs() {
  const list = data.dutyLogs || [];
  return `
    <div class="card">
      <h3>Duty logs</h3>
      ${list.length ? `<table><thead><tr><th>Officer</th><th>On</th><th>Off</th><th class="right">Duration</th></tr></thead>
      <tbody>${list.map(l => `<tr>
        <td>${esc(l.name)}</td>
        <td class="muted">${esc(l.date)}</td>
        <td class="muted">${l.wentOff ? new Date(l.wentOff * 1000).toLocaleString() : '-'}</td>
        <td class="right">${esc(l.clock)}</td>
      </tr>`).join('')}</tbody></table>` : empty('No duty logs yet')}
    </div>
  `;
}

function viewAnims() {
  const list = data.animations || [];
  const grouped = {};
  list.forEach((entry, index) => {
    grouped[entry.category] = grouped[entry.category] || [];
    grouped[entry.category].push(Object.assign({ index: index + 1 }, entry));
  });

  return `
    <div class="card">
      <h3>Roleplay animations (${list.length})</h3>
      ${Object.keys(grouped).map(category => `
        <h3>${esc(category)}</h3>
        <div class="grid">
          ${grouped[category].map(entry => `<div class="tile">
            <h4>${esc(entry.label)}</h4>
            <p class="muted">${esc(entry.dict)} / ${esc(entry.clip)}</p>
            <button class="btn small" data-anim="${entry.index}">Play</button>
          </div>`).join('')}
        </div>
      `).join('')}
    </div>
  `;
}

function viewK9() {
  return `
    <div class="card">
      <h3>K9 Unit</h3>
      <div class="row">
        <button class="btn" data-k9="deploy">Deploy / dismiss</button>
        <button class="btn ghost" data-k9="follow">Follow</button>
        <button class="btn ghost" data-k9="sit">Sit</button>
        <button class="btn ghost" data-k9="attack">Attack target</button>
        <button class="btn ghost" data-k9="search">Search for contraband</button>
      </div>
      <p class="muted">Commands also work from chat: /k9 follow, /k9 sit, /k9 attack, /k9 search, /k9 dismiss.</p>
    </div>
  `;
}

/* ------------------------------------------------------------------ creator */

function viewCreatorDepartments() {
  const departments = (creatorData && creatorData.departments) || {};
  const list = Object.keys(departments).map(id => departments[id]);

  return `
    ${notice()}
    <div class="card">
      <h3>Departments (${list.length})</h3>
      ${list.length ? `<table><thead><tr><th>Label</th><th>Name</th><th>Type</th><th class="right">Funds</th><th class="right">Nodes</th><th class="right">Actions</th></tr></thead>
      <tbody>${list.map(d => `<tr>
        <td><input data-deptlabel="${d.id}" value="${esc(d.label)}" /></td>
        <td>${esc(d.name)}</td>
        <td>${esc(d.type)}</td>
        <td class="right">${money(d.funds)}</td>
        <td class="right">${(d.nodes || []).length}</td>
        <td class="right">
          <button class="btn small" data-deptsave="${d.id}">Save</button>
          <button class="btn small" data-deptnodes="${d.id}">Nodes</button>
          <button class="btn small danger" data-deptdelete="${d.id}">Delete</button>
        </td>
      </tr>`).join('')}</tbody></table>` : empty('No departments yet')}
    </div>
  `;
}

function viewCreatorNew() {
  const templates = (creatorData && creatorData.templates) || {};
  return `
    <div class="card">
      <h3>Create a department</h3>
      <div class="field"><label>Internal name (letters/numbers only)</label><input id="newName" placeholder="bcso" /></div>
      <div class="field"><label>Display label</label><input id="newLabel" placeholder="Blaine County Sheriff" /></div>
      <div class="field"><label>Template</label>
        <select id="newTemplate" style="width:100%">
          ${Object.keys(templates).map(key => `<option value="${esc(key)}">${esc(templates[key].Label || key)}</option>`).join('')}
        </select>
      </div>
      <div class="field"><label>Colour</label><input id="newColor" value="#2f6df6" /></div>
      <div class="field"><label>Starting funds</label><input id="newFunds" type="number" value="25000" /></div>
      <button class="btn" id="newCreateBtn">Create department</button>
      <p class="muted">Ranks are copied from the template and can be edited afterwards from the boss menu.</p>
    </div>
  `;
}

function viewCreatorNodes() {
  const departments = (creatorData && creatorData.departments) || {};
  const nodeTypes = (creatorData && creatorData.nodeTypes) || {};
  const list = Object.keys(departments).map(id => departments[id]);

  return `
    ${notice()}
    <div class="card">
      <h3>Place a node</h3>
      <div class="row">
        <select id="nodeDept">
          ${list.map(d => `<option value="${d.id}">${esc(d.label)}</option>`).join('')}
        </select>
        <select id="nodeType">
          ${Object.keys(nodeTypes).map(key => `<option value="${esc(key)}">${esc(nodeTypes[key].label || key)}</option>`).join('')}
        </select>
        <input id="nodeLabel" placeholder="Label (optional)" />
        <button class="btn" id="nodePlaceBtn">Place at my position</button>
      </div>
      <p class="muted">Stand where the node should be. Nodes of the same department must be at least 3m apart. Press <strong>X</strong> while standing on a node to delete it.</p>
    </div>
    <div class="card">
      <h3>All nodes</h3>
      ${list.map(d => `
        <h3>${esc(d.label)}</h3>
        ${(d.nodes || []).length ? `<table><thead><tr><th>Type</th><th>Label</th><th>Position</th><th class="right">Actions</th></tr></thead>
        <tbody>${d.nodes.map(n => `<tr>
          <td>${esc(n.type)}</td>
          <td>${esc(n.label)}</td>
          <td class="muted">${Number(n.x).toFixed(1)}, ${Number(n.y).toFixed(1)}, ${Number(n.z).toFixed(1)}</td>
          <td class="right"><button class="btn small danger" data-creatornodeDelete="${n.id}">Delete</button></td>
        </tr>`).join('')}</tbody></table>` : empty('No nodes')}
      `).join('')}
    </div>
  `;
}

/* ------------------------------------------------------------------ render */

function renderContent() {
  if (mode === 'creator') {
    content.innerHTML = activeTab === 'newdept' ? viewCreatorNew()
      : activeTab === 'nodes' ? viewCreatorNodes()
        : viewCreatorDepartments();
    bindCreator();
    return;
  }

  if (!data || data.error) {
    content.innerHTML = `<div class="notice error">${esc((data && data.error) || 'No data')}</div>`;
    return;
  }

  switch (activeTab) {
    case 'members': content.innerHTML = viewMembers(); break;
    case 'finance': content.innerHTML = viewFinance(); break;
    case 'ranks': content.innerHTML = viewRanks(); break;
    case 'divisions': content.innerHTML = viewDivisions(); break;
    case 'applications': content.innerHTML = viewApplications(); break;
    case 'dispatch': content.innerHTML = viewDispatch(); break;
    case 'bolo': content.innerHTML = viewBolo(); break;
    case 'evidence': content.innerHTML = viewEvidence(); break;
    case 'evidenceForm': content.innerHTML = viewEvidenceForm(); break;
    case 'garage': content.innerHTML = viewGarage(); break;
    case 'armory': content.innerHTML = viewArmory(); break;
    case 'cameras': content.innerHTML = viewCameras(); break;
    case 'trackers': content.innerHTML = viewTrackers(); break;
    case 'dutylogs': content.innerHTML = viewDutyLogs(); break;
    case 'anims': content.innerHTML = viewAnims(); break;
    case 'k9': content.innerHTML = viewK9(); break;
    default: content.innerHTML = viewDashboard();
  }

  bind();
}

function render() {
  renderHeader();
  renderSidebar();
  renderContent();
}

/* ------------------------------------------------------------------ events */

function bindButtons(map) {
  Object.keys(map).forEach(selector => {
    content.querySelectorAll(`[${selector}]`).forEach(element => {
      element.addEventListener('click', () => map[selector](element.getAttribute(selector), element));
    });
  });
}

function bind() {
  bindButtons({
    'data-fire': (id) => act('fire', { citizenid: id }),
    'data-bonus': (id) => {
      const amount = Number(prompt('Bonus amount', '500'));
      if (amount > 0) act('bonus', { citizenid: id, amount: amount });
    },
    'data-ranksave': (id) => {
      const perms = [];
      content.querySelectorAll(`[data-perm="${id}"]`).forEach(box => { if (box.checked) perms.push(box.dataset.permname); });
      act('updateRank', {
        rankId: Number(id),
        label: content.querySelector(`[data-ranklabel="${id}"]`).value,
        salary: Number(content.querySelector(`[data-ranksalary="${id}"]`).value),
        perms: perms.join(',')
      });
    },
    'data-rankdelete': (id) => act('deleteRank', { rankId: Number(id) }),
    'data-divdelete': (id) => act('deleteDivision', { divisionId: Number(id) }),
    'data-appaccept': (id) => act('resolveApplication', { applicationId: Number(id), decision: 'accepted' }),
    'data-appdeny': (id) => act('resolveApplication', { applicationId: Number(id), decision: 'denied' }),
    'data-callaccept': (id) => act('acceptCall', { callId: Number(id) }),
    'data-callrelease': (id) => act('releaseCall', { callId: Number(id) }),
    'data-callclose': (id) => act('closeCall', { callId: Number(id) }),
    'data-bolotoggle': (id, el) => act('boloToggle', { boloId: Number(id), active: el.dataset.active === '1' }),
    'data-bolodelete': (id) => act('boloDelete', { boloId: Number(id) }),
    'data-evidencetake': (id) => act('evidenceTake', { evidenceId: Number(id) }),
    'data-evidencedelete': (id) => act('evidenceDelete', { evidenceId: Number(id) }),
    'data-spawn': (id) => act('garageSpawn', { vehicleId: Number(id), nodeId: data.nodeId }),
    'data-impound': (id, el) => act('garageImpound', { vehicleId: Number(id), impounded: el.dataset.impounded === '1' }),
    'data-garageremove': (id) => act('garageRemove', { vehicleId: Number(id) }),
    'data-armorytake': (index) => act('armoryTake', { index: Number(index) }),
    'data-armorystore': (index) => act('armoryStore', { index: Number(index) }),
    'data-viewcamera': (id) => act('viewCamera', { cameraId: Number(id) }),
    'data-cameraremove': (id) => act('cameraRemove', { cameraId: Number(id) }),
    'data-trackrecover': (id) => act('trackerRecover', { trackerId: Number(id) }),
    'data-trackremove': (id) => act('trackerRemove', { trackerId: Number(id) }),
    'data-anim': (index) => act('playAnim', { index: Number(index) }),
    'data-k9': (name) => act('k9Command', { name: name })
  });

  content.querySelectorAll('[data-rank]').forEach(select => {
    select.addEventListener('change', () => act('setRank', { citizenid: select.dataset.rank, rankId: Number(select.value) }));
  });

  content.querySelectorAll('[data-division]').forEach(select => {
    select.addEventListener('change', () => act('setDivision', { citizenid: select.dataset.division, divisionId: Number(select.value) }));
  });

  content.querySelectorAll('[data-salary]').forEach(input => {
    input.addEventListener('change', () => act('setSalary', { citizenid: input.dataset.salary, salary: Number(input.value) }));
  });

  const on = (id, event, handler) => {
    const element = $(id) || content.querySelector('#' + id);
    if (element) element.addEventListener(event, handler);
  };

  on('quickDuty', 'click', () => act('toggleDuty'));
  on('quickRefresh', 'click', () => act('refresh'));
  on('quickCall', 'click', () => { activeTab = 'dispatch'; render(); });

  on('hireBtn', 'click', () => act('hire', {
    citizenid: $('hireCitizen').value.trim(),
    firstName: $('hireFirst').value.trim(),
    lastName: $('hireLast').value.trim(),
    rankId: Number($('hireRank').value)
  }));
  on('hireNearbyBtn', 'click', () => act('hireNearby', { rankId: Number($('hireRank').value) }));

  on('depositBtn', 'click', () => act('deposit', { amount: Number($('finAmount').value) }));
  on('withdrawBtn', 'click', () => act('withdraw', { amount: Number($('finAmount').value) }));

  on('rankCreateBtn', 'click', () => act('createRank', {
    label: $('rankLabel').value.trim(),
    grade: $('rankGrade').value === '' ? null : Number($('rankGrade').value),
    salary: Number($('rankSalary').value),
    boss: $('rankBoss').checked,
    perms: 'dispatch,evidence'
  }));

  on('divCreateBtn', 'click', () => act('createDivision', { name: $('divName').value.trim(), label: $('divLabel').value.trim() }));

  on('callCreateBtn', 'click', () => act('createCall', {
    code: $('callCode').value,
    description: $('callDescription').value.trim()
  }));

  on('boloCreateBtn', 'click', () => act('boloCreate', {
    type: $('boloType').value,
    value: $('boloValue').value.trim(),
    description: $('boloDescription').value.trim()
  }));

  on('vehAddBtn', 'click', () => act('garageAdd', {
    model: $('vehModel').value.trim(),
    label: $('vehLabel').value.trim(),
    rankMin: Number($('vehRank').value),
    livery: Number($('vehLivery').value),
    spawnNode: data.nodeId
  }));

  on('camAddBtn', 'click', async () => {
    const position = await readPosition();
    if (!position) return;
    act('cameraAdd', {
      label: $('camLabel').value.trim(),
      rankMin: Number($('camRank').value),
      x: position.x, y: position.y, z: position.z, heading: position.heading
    });
  });

  on('evSubmit', 'click', () => act('evidenceCreate', {
    label: $('evLabel').value.trim(),
    description: $('evDescription').value.trim(),
    owner: $('evOwner').value.trim(),
    grade: Number($('evGrade').value),
    x: evidencePoint ? evidencePoint.x : 0,
    y: evidencePoint ? evidencePoint.y : 0,
    z: evidencePoint ? evidencePoint.z : 0
  }));
  on('evCancel', 'click', close);
}

function bindCreator() {
  bindButtons({
    'data-deptsave': (id) => act('creatorUpdate', { deptId: Number(id), label: content.querySelector(`[data-deptlabel="${id}"]`).value }),
    'data-deptdelete': (id) => { if (confirm('Delete this department and all its data?')) act('creatorDelete', { deptId: Number(id) }); },
    'data-deptnodes': () => { activeTab = 'nodes'; render(); },
    'data-creatornodeDelete': (id) => act('creatorDeleteNode', { nodeId: Number(id) })
  });

  const on = (id, event, handler) => {
    const element = content.querySelector('#' + id);
    if (element) element.addEventListener(event, handler);
  };

  on('newCreateBtn', 'click', () => act('creatorCreate', {
    name: $('newName').value.trim(),
    label: $('newLabel').value.trim(),
    template: $('newTemplate').value,
    color: $('newColor').value.trim(),
    funds: Number($('newFunds').value)
  }));

  on('nodePlaceBtn', 'click', async () => {
    const position = await readPosition();
    if (!position) return;
    act('creatorAddNode', {
      deptId: Number($('nodeDept').value),
      type: $('nodeType').value,
      label: $('nodeLabel').value.trim(),
      x: position.x, y: position.y, z: position.z, heading: position.heading,
      blip: true
    });
  });
}

/* ------------------------------------------------------------------ bridge */

window.addEventListener('message', (event) => {
  const message = event.data || {};

  switch (message.action) {
    case 'open':
      mode = message.data.mode || 'menu';
      if (mode === 'creator') {
        creatorData = message.data.payload || {};
      } else {
        data = message.data.payload || {};
        if (mode === 'evidence') {
          evidencePoint = data;
        }
        calls = ((data && data.calls) || []).slice();
      }
      activeTab = mode === 'creator' ? 'departments'
        : mode === 'evidence' ? 'evidenceForm' : 'dashboard';
      app.classList.remove('hidden');
      render();
      break;

    case 'update':
      data = message.data || {};
      calls = ((data && data.calls) || []).slice();
      render();
      break;

    case 'callAdded':
      calls.unshift(message.data);
      if (app.classList.contains('hidden') === false && activeTab === 'dispatch') render();
      renderHeader();
      break;

    case 'callUpdated': {
      const index = calls.findIndex(c => c.id === message.data.id);
      if (index >= 0) calls[index] = message.data; else calls.unshift(message.data);
      if (activeTab === 'dispatch') renderContent();
      renderHeader();
      break;
    }

    case 'callClosed': {
      const idx = calls.findIndex(c => c.id === message.data.id);
      if (idx >= 0) calls[idx].status = 'closed';
      if (activeTab === 'dispatch') renderContent();
      renderHeader();
      break;
    }

    case 'animStopped':
      break;

    case 'close':
      app.classList.add('hidden');
      break;

    default:
      break;
  }
});

$('closeBtn').addEventListener('click', close);
$('refreshBtn').addEventListener('click', () => act('refresh'));
$('dutyBtn').addEventListener('click', () => act('toggleDuty'));

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !app.classList.contains('hidden')) close();
});
