let state = null;
let ui = {};
let visible = false;
let activeMode = 'mdt';
let armoryFilter = 'weapons';
let searchText = '';
let toastTimer;

const body = document.body;
const title = document.getElementById('title');
const subtitle = document.getElementById('subtitle');
const stats = document.getElementById('stats');
const directory = document.getElementById('directory');
const officialCard = document.getElementById('officialCard');
const updated = document.getElementById('updated');
const map = document.getElementById('map');
const markers = document.getElementById('markers');
const contactList = document.getElementById('contactList');
const armoryGrid = document.getElementById('armoryGrid');
const armorySearch = document.getElementById('armorySearch');
const toast = document.getElementById('toast');

function resourceName() {
    return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'codex_gouv';
}

async function postNui(eventName, payload = {}) {
    try {
        const response = await fetch(`https://${resourceName()}/${eventName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload)
        });
        return await response.json();
    } catch (error) {
        return { ok: false, error: 'The tablet connection was interrupted.' };
    }
}

function escapeHtml(value) {
    return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

function number(value, fallback = 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
}

function jobLabel(player) {
    return player.jobLabel || player.job || 'Civilian';
}

function colorLabel(color) {
    if (color === 'police') return 'POLICE';
    if (color === 'ambulance') return 'AMBULANCE';
    return 'PLAYER';
}

function iconFor(color) {
    if (color === 'police') return '✚';
    if (color === 'ambulance') return '✚';
    return '•';
}

function showToast(message, type = 'info') {
    if (!message) return;
    toast.textContent = message;
    toast.className = `toast ${type === 'error' ? 'error' : type === 'success' ? 'success' : ''}`;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.add('hidden'), 3300);
}

function renderOfficial() {
    const me = state?.me;
    if (!me) {
        officialCard.innerHTML = '';
        return;
    }
    const job = me.job || {};
    officialCard.innerHTML = `<span class="official-icon">✦</span><div><strong>${escapeHtml(me.name)}</strong><small>${escapeHtml(job.gradeLabel || 'Government official')}</small></div><b>#${escapeHtml(me.id)}</b>`;
}

function renderStats() {
    const counts = state?.counts || {};
    const cards = [
        ['ONLINE', number(counts.total)],
        ['POLICE', number(counts.police)],
        ['AMBULANCE', number(counts.ambulance)],
        ['CIVILIANS', number(counts.civilian)]
    ];
    stats.innerHTML = cards.map(([label, value]) => `<article class="stat-card"><span>${label}</span><strong>${value}</strong><i></i></article>`).join('');
}

function renderDirectory() {
    const players = [...(state?.players || [])].sort((a, b) => String(a.name).localeCompare(String(b.name)));
    if (!players.length) {
        directory.innerHTML = '<div class="empty"><span>⌁</span><h3>No active contacts</h3><p>The server has not returned any player records.</p></div>';
        return;
    }
    directory.innerHTML = `<div class="directory-head"><span>IDENTITY</span><span>CLASSIFICATION</span><span>POSITION</span><span>STATUS</span></div>${players.map((player) => {
        const coords = player.coords || {};
        return `<div class="directory-row"><div class="identity"><span class="avatar ${escapeHtml(player.color)}">${iconFor(player.color)}</span><div><strong>${escapeHtml(player.name)}</strong><small>SERVER ID ${escapeHtml(player.id)}</small></div></div><span class="classification ${escapeHtml(player.color)}">${colorLabel(player.color)}</span><span class="position">${number(coords.x).toFixed(1)}, ${number(coords.y).toFixed(1)}</span><span class="online"><i></i> ONLINE</span></div>`;
    }).join('')}`;
}

function mapPosition(player) {
    const bounds = state?.map?.bounds || { minX: -4000, maxX: 4500, minY: -5000, maxY: 8500 };
    const coords = player.coords || {};
    const x = Math.max(0, Math.min(100, ((number(coords.x) - number(bounds.minX)) / (number(bounds.maxX) - number(bounds.minX))) * 100));
    const y = Math.max(0, Math.min(100, (1 - ((number(coords.y) - number(bounds.minY)) / (number(bounds.maxY) - number(bounds.minY)))) * 100));
    return { x, y };
}

function renderSatellite() {
    const players = state?.players || [];
    markers.innerHTML = players.map((player) => {
        const position = mapPosition(player);
        const coords = player.coords || {};
        const mine = state?.me?.id === player.id;
        const label = state?.map?.showNames === false ? '' : `<b>${escapeHtml(player.name)}</b>`;
        return `<button class="marker ${escapeHtml(player.color)} ${mine ? 'mine' : ''}" style="left:${position.x}%;top:${position.y}%" title="${escapeHtml(player.name)} — ${escapeHtml(jobLabel(player))}"><span>${iconFor(player.color)}</span>${label}</button>`;
    }).join('');

    const sorted = [...players].sort((a, b) => String(a.name).localeCompare(String(b.name)));
    contactList.innerHTML = sorted.length ? sorted.map((player) => {
        const coords = player.coords || {};
        return `<div class="contact"><span class="avatar ${escapeHtml(player.color)}">${iconFor(player.color)}</span><div><strong>${escapeHtml(player.name)}</strong><small>${escapeHtml(jobLabel(player))}</small></div><em>${number(coords.x).toFixed(0)}<br>${number(coords.y).toFixed(0)}</em></div>`;
    }).join('') : '<div class="empty small"><span>⌁</span><p>No contacts in range.</p></div>';

    document.getElementById('mapCount').textContent = `${players.length} CONTACT${players.length === 1 ? '' : 'S'}`;
    const mine = players.find((player) => state?.me?.id === player.id);
    if (mine && state.map?.showCoordinates !== false) {
        const c = mine.coords || {};
        document.getElementById('coordinates').textContent = `YOUR POSITION // ${number(c.x).toFixed(1)} , ${number(c.y).toFixed(1)} , ${number(c.z).toFixed(1)}`;
    } else {
        document.getElementById('coordinates').textContent = 'POSITION DATA ENCRYPTED';
    }
}

function renderArmory() {
    const source = armoryFilter === 'items' ? (state?.armory?.items || []) : (state?.armory?.weapons || []);
    const query = searchText.trim().toLowerCase();
    const list = source.filter((entry) => `${entry.name} ${entry.label}`.toLowerCase().includes(query));
    if (!list.length) {
        armoryGrid.innerHTML = '<div class="empty"><span>◈</span><h3>No authorized equipment found</h3><p>Check the search term or your ox_inventory item definitions.</p></div>';
        return;
    }
    armoryGrid.innerHTML = list.map((entry) => `<article class="armory-card"><span class="equipment-icon">${escapeHtml(entry.icon)}</span><div class="equipment-copy"><strong>${escapeHtml(entry.label)}</strong><small>${escapeHtml(entry.name)}</small></div><button class="issue" data-kind="${armoryFilter === 'items' ? 'item' : 'weapon'}" data-name="${escapeHtml(entry.name)}">ISSUE <span>+</span></button></article>`).join('');
}

function setMode(mode, send = false) {
    activeMode = mode || 'mdt';
    document.querySelectorAll('.nav-btn').forEach((button) => button.classList.toggle('active', button.dataset.mode === activeMode));
    document.getElementById('mdtView').classList.toggle('hidden', activeMode !== 'mdt');
    document.getElementById('satelliteView').classList.toggle('hidden', activeMode !== 'satellite');
    document.getElementById('armoryView').classList.toggle('hidden', activeMode !== 'armory');
    if (send && visible) postNui('mode', { mode: activeMode });
}

function render() {
    if (!state) return;
    document.documentElement.style.setProperty('--accent', ui.accent || state.accent || '#80f7bc');
    title.textContent = ui.title || state.title || 'GOUV // COMMAND TABLET';
    subtitle.textContent = ui.subtitle || state.subtitle || '';
    document.getElementById('externalMdt').classList.toggle('hidden', state.bridgeEnabled !== true);
    updated.textContent = `UPLINK ${escapeHtml(state.serverTime || '--:--:--')}`;
    renderOfficial();
    renderStats();
    renderDirectory();
    renderSatellite();
    renderArmory();
    setMode(activeMode);
}

function openPanel(payload) {
    state = payload.state || {};
    ui = payload.ui || {};
    activeMode = state.mode || 'mdt';
    visible = true;
    body.classList.remove('hidden');
    render();
}

function updatePanel(nextState) {
    if (!nextState) return;
    state = nextState;
    render();
}

function closePanel() {
    visible = false;
    body.classList.add('hidden');
}

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    if (payload.action === 'open') openPanel(payload);
    if (payload.action === 'update') updatePanel(payload.state);
    if (payload.action === 'mode') setMode(payload.mode);
    if (payload.action === 'close') closePanel();
});

document.getElementById('close').addEventListener('click', () => {
    postNui('close');
    closePanel();
});

document.getElementById('refresh').addEventListener('click', async () => {
    const result = await postNui('refresh', { mode: activeMode });
    if (result?.state) updatePanel(result.state);
    if (result?.error) showToast(result.error, 'error');
});

document.querySelectorAll('.nav-btn').forEach((button) => {
    button.addEventListener('click', () => {
        setMode(button.dataset.mode, true);
    });
});

document.querySelectorAll('.filter').forEach((button) => {
    button.addEventListener('click', () => {
        armoryFilter = button.dataset.filter;
        document.querySelectorAll('.filter').forEach((item) => item.classList.toggle('active', item === button));
        renderArmory();
    });
});

armorySearch.addEventListener('input', () => {
    searchText = armorySearch.value;
    renderArmory();
});

document.addEventListener('click', async (event) => {
    const issue = event.target.closest('.issue');
    if (!issue || issue.disabled) return;
    issue.disabled = true;
    issue.innerHTML = '...';
    const result = await postNui('armoryGive', { kind: issue.dataset.kind, name: issue.dataset.name });
    issue.disabled = false;
    issue.innerHTML = 'ISSUE <span>+</span>';
    if (result?.error) showToast(result.error, 'error');
    if (result?.message) showToast(result.message, 'success');
});

document.getElementById('externalMdt').addEventListener('click', async () => {
    const result = await postNui('externalMdt');
    if (result?.error) showToast(result.error, 'error');
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        postNui('close');
        closePanel();
    }
});
