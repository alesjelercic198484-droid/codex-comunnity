const body = document.body;

const els = {
    agency: document.getElementById('agency'),
    division: document.getElementById('division'),
    firstName: document.getElementById('firstName'),
    lastName: document.getElementById('lastName'),
    job: document.getElementById('job'),
    grade: document.getElementById('grade'),
    gradeField: document.getElementById('gradeField'),
    idNumber: document.getElementById('idNumber'),
    footerText: document.getElementById('footerText'),
    closeBtn: document.getElementById('closeBtn')
};

let autoCloseTimer = null;

function resourceName() {
    if (typeof GetParentResourceName === 'function') {
        return GetParentResourceName();
    }
    return 'codex_dos_id';
}

async function postNui(eventName, payload) {
    try {
        const response = await fetch(`https://${resourceName()}/${eventName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload || {})
        });
        return await response.json();
    } catch (error) {
        return { ok: false };
    }
}

function escapeHtml(value) {
    return String(value == null ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function makeIdNumber(identifier) {
    if (!identifier) {
        return 'DOS-' + Math.floor(Math.random() * 900000 + 100000);
    }
    const digits = String(identifier).replace(/\D/g, '').slice(-6).padStart(6, '0');
    return `DOS-${digits}`;
}

function renderCard(card) {
    card = card || {};
    els.agency.textContent = card.agency || 'DEPARTMENT OF DEFENSE';
    els.division.textContent = card.division || 'SECRET SERVICES';
    els.firstName.textContent = card.firstName || '—';
    els.lastName.textContent = card.lastName || '—';
    els.job.textContent = card.job || 'Federal Agent';

    if (card.grade && String(card.grade).trim() !== '') {
        els.grade.textContent = card.grade;
        els.gradeField.style.display = '';
    } else {
        els.gradeField.style.display = 'none';
    }

    els.idNumber.textContent = makeIdNumber(card.identifier);
    els.footerText.textContent = card.footer ||
        'This credential certifies that the bearer is an active federal agent authorized under national security statutes.';
}

function closeUI() {
    body.classList.add('hidden');
    body.classList.remove('mode-presented');
    if (autoCloseTimer) {
        clearTimeout(autoCloseTimer);
        autoCloseTimer = null;
    }
    postNui('close', {});
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'open') {
        renderCard(data.card);
        body.classList.remove('hidden');

        if (data.mode === 'presented') {
            body.classList.add('mode-presented');
            if (autoCloseTimer) {
                clearTimeout(autoCloseTimer);
            }
            const delay = Number(data.autoCloseMs) > 0 ? Number(data.autoCloseMs) : 12000;
            autoCloseTimer = setTimeout(closeUI, delay);
        } else {
            body.classList.remove('mode-presented');
        }
    } else if (data.action === 'close') {
        closeUI();
    }
});

els.closeBtn.addEventListener('click', closeUI);

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !body.classList.contains('mode-presented')) {
        closeUI();
    }
});
