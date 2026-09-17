let state = null;
let ui = {};
let visible = false;
let activeTab = 'current';
let receivedAt = Date.now();
let toastTimer = null;

const body = document.body;
const title = document.getElementById('title');
const subtitle = document.getElementById('subtitle');
const stats = document.getElementById('stats');
const grid = document.getElementById('missionGrid');
const emptyState = document.getElementById('emptyState');
const todayBadge = document.getElementById('todayBadge');
const legacyBadge = document.getElementById('legacyBadge');
const toast = document.getElementById('toast');

const iconMap = {
    clock: '⏱️',
    box: '📦',
    wallet: '💳',
    star: '⭐',
    crown: '👑',
    gift: '🎁',
    car: '🚗',
    weapon: '🛡️'
};

function resourceName() {
    if (typeof GetParentResourceName === 'function') {
        return GetParentResourceName();
    }
    return 'codex_daily_missions';
}

async function postNui(eventName, payload) {
    const response = await fetch(`https://${resourceName()}/${eventName}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8'
        },
        body: JSON.stringify(payload || {})
    });

    try {
        return await response.json();
    } catch (error) {
        return { ok: false, error: 'Invalid UI response.' };
    }
}

function escapeHtml(value) {
    return String(value == null ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function number(value, fallback) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : (fallback || 0);
}

function formatTime(totalSeconds) {
    totalSeconds = Math.max(0, Math.floor(number(totalSeconds, 0)));

    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    if (hours > 0) {
        return `${hours}h ${String(minutes).padStart(2, '0')}m`;
    }

    if (minutes > 0) {
        return `${minutes}m ${String(seconds).padStart(2, '0')}s`;
    }

    return `${seconds}s`;
}

function formatMoney(amount) {
    return `$${Math.floor(number(amount, 0)).toLocaleString('en-US')}`;
}

function rewardLabel(reward) {
    if (!reward) {
        return 'Reward';
    }

    if (reward.label) {
        return reward.label;
    }

    const type = String(reward.type || '').toLowerCase();
    const amount = number(reward.amount || reward.count, 0);

    if (type === 'money' || type === 'cash') {
        return `${formatMoney(amount)} Cash`;
    }

    if (type === 'bank') {
        return `${formatMoney(amount)} Bank`;
    }

    if (type === 'account') {
        return `${formatMoney(amount)} ${reward.account || 'Account'}`;
    }

    if (type === 'item') {
        return `${reward.name || 'Item'} x${number(reward.count || reward.amount, 1)}`;
    }

    if (type === 'weapon') {
        return reward.name || 'Weapon';
    }

    if (type === 'vehicle') {
        return reward.model || reward.name || 'Vehicle';
    }

    return 'Custom Reward';
}

function elapsedSinceState() {
    return Math.max(0, Math.floor((Date.now() - receivedAt) / 1000));
}

function computedProgress(mission) {
    const required = Math.max(0, number(mission.requiredSeconds, 0));
    let progress = Math.max(0, number(mission.progress, 0));

    if (mission.isCounting && !mission.completed && !mission.claimed) {
        progress += elapsedSinceState();
    }

    if (required > 0) {
        return Math.min(progress, required);
    }

    return progress;
}

function missionStatus(mission) {
    if (mission.claimed) {
        return { className: 'claimed', label: 'Claimed' };
    }

    if (mission.completed) {
        return { className: 'ready', label: 'Ready' };
    }

    if (mission.isCounting) {
        return { className: 'active', label: 'Active' };
    }

    return { className: '', label: 'Pending' };
}

function statCard(label, value) {
    return `<article class="stat"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></article>`;
}

function renderStats() {
    const counts = state && state.counts ? state.counts : {};
    const resetSeconds = Math.max(0, number(state && state.resetInSeconds, 0) - elapsedSinceState());
    const mode = String((state && state.progressMode) || 'all');
    const modeLabel = mode === 'sequential' ? 'Sequential' : 'All Active';

    stats.innerHTML = [
        statCard('Completed', `${number(counts.completed, 0)} / ${number(counts.total, 0)}`),
        statCard('Ready to claim', number(counts.claimable, 0) + number(counts.oldClaimable, 0)),
        statCard('Daily reset', formatTime(resetSeconds)),
        statCard('Progress mode', modeLabel)
    ].join('');
}

function renderMissionCard(mission) {
    const required = Math.max(0, number(mission.requiredSeconds, 0));
    const progress = computedProgress(mission);
    const percent = required > 0 ? Math.min(100, Math.floor((progress / required) * 100)) : 100;
    const remaining = Math.max(0, required - progress);
    const status = missionStatus(mission);
    const rewards = Array.isArray(mission.rewards) ? mission.rewards : [];
    const canClaim = mission.canClaim === true;
    const icon = iconMap[mission.icon] || iconMap.gift;

    let buttonText = 'Keep Playing';
    if (mission.claimed) {
        buttonText = 'Claimed';
    } else if (canClaim) {
        buttonText = 'Claim Reward';
    } else if (mission.completed) {
        buttonText = 'Syncing';
    }

    return `
        <article class="mission-card ${mission.claimed ? 'claimed' : ''}">
            <div class="card-top">
                <div class="icon">${icon}</div>
                <div class="status ${status.className}">${escapeHtml(status.label)}</div>
            </div>
            <h2>${escapeHtml(mission.label)}</h2>
            <p class="description">${escapeHtml(mission.description)}</p>
            <div class="progress-meta">
                <span>${formatTime(progress)} / ${formatTime(required)}</span>
                <span>${percent}%</span>
            </div>
            <div class="progress" aria-label="Progress">
                <div style="width: ${percent}%"></div>
            </div>
            <div class="progress-meta">
                <span>${remaining > 0 ? `${formatTime(remaining)} remaining` : 'Completed'}</span>
                <span>${escapeHtml(mission.dayKey || '')}</span>
            </div>
            <div class="rewards">
                ${rewards.map((reward) => `<span class="reward">${escapeHtml(rewardLabel(reward))}</span>`).join('') || '<span class="reward">No reward configured</span>'}
            </div>
            <button class="claim-button" data-action="claim" data-day="${escapeHtml(mission.dayKey)}" data-key="${escapeHtml(mission.key)}" ${canClaim ? '' : 'disabled'}>${escapeHtml(buttonText)}</button>
        </article>
    `;
}

function renderMissions() {
    const current = state && Array.isArray(state.missions) ? state.missions : [];
    const legacy = state && Array.isArray(state.unclaimed) ? state.unclaimed : [];
    const list = activeTab === 'legacy' ? legacy : current;

    todayBadge.textContent = String(current.filter((mission) => mission.canClaim).length);
    legacyBadge.textContent = String(legacy.filter((mission) => mission.canClaim).length);

    document.querySelectorAll('.tab').forEach((tab) => {
        tab.classList.toggle('active', tab.dataset.tab === activeTab);
    });

    if (!list.length) {
        grid.innerHTML = '';
        emptyState.classList.remove('hidden');
        return;
    }

    emptyState.classList.add('hidden');
    grid.innerHTML = list.map(renderMissionCard).join('');
}

function render() {
    if (!visible || !state) {
        return;
    }

    const accent = (ui && ui.accentColor) || state.accentColor || '#26f3c9';
    const softAccent = /^#[0-9a-fA-F]{6}$/.test(accent) ? `${accent}2a` : 'rgba(38, 243, 201, 0.16)';
    document.documentElement.style.setProperty('--accent', accent);
    document.documentElement.style.setProperty('--accent-soft', softAccent);

    title.textContent = (ui && ui.title) || state.title || 'Daily Missions';
    subtitle.textContent = (ui && ui.subtitle) || state.subtitle || '';

    renderStats();
    renderMissions();
}

function showToast(message) {
    if (!message) {
        return;
    }

    toast.textContent = message;
    toast.classList.remove('hidden');

    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
        toast.classList.add('hidden');
    }, 3200);
}

function openPanel(payload) {
    state = payload.state;
    ui = payload.ui || {};
    visible = true;
    receivedAt = Date.now();
    body.classList.remove('hidden');
    render();
}

function updatePanel(nextState) {
    state = nextState;
    receivedAt = Date.now();
    render();
}

function closePanel() {
    visible = false;
    body.classList.add('hidden');
}

window.addEventListener('message', (event) => {
    const payload = event.data || {};

    if (payload.action === 'open') {
        openPanel(payload);
    } else if (payload.action === 'update') {
        updatePanel(payload.state);
    } else if (payload.action === 'close') {
        closePanel();
    }
});

document.getElementById('close').addEventListener('click', () => {
    postNui('close');
    closePanel();
});

document.getElementById('refresh').addEventListener('click', async () => {
    const result = await postNui('refresh');
    if (result && result.state) {
        updatePanel(result.state);
    }
    if (result && result.error) {
        showToast(result.error);
    }
});

document.querySelectorAll('.tab').forEach((tab) => {
    tab.addEventListener('click', () => {
        activeTab = tab.dataset.tab || 'current';
        render();
    });
});

document.addEventListener('click', async (event) => {
    const button = event.target.closest('[data-action="claim"]');
    if (!button || button.disabled) {
        return;
    }

    button.disabled = true;
    button.textContent = 'Claiming...';

    const result = await postNui('claim', {
        dayKey: button.dataset.day,
        missionKey: button.dataset.key
    });

    if (result && result.state) {
        updatePanel(result.state);
    } else {
        render();
    }

    if (result && result.error) {
        showToast(result.error);
    } else if (result && result.message) {
        showToast(result.message);
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        postNui('close');
        closePanel();
    }
});

setInterval(() => {
    render();
}, 1000);
