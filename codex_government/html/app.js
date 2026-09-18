(() => {
    'use strict';

    const overlay = document.getElementById('overlay');
    const credential = document.getElementById('credential');
    const closeButton = document.getElementById('closeButton');
    const elements = {
        authority: document.getElementById('authority'),
        agency: document.getElementById('agency'),
        department: document.getElementById('department'),
        fullName: document.getElementById('fullName'),
        rank: document.getElementById('rank'),
        credential: document.getElementById('credentialNumber'),
        footer: document.getElementById('footerText')
    };

    let autoCloseTimer = null;
    let currentMode = null;

    const resourceName = typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'codex_government';

    function safeText(value, fallback) {
        if (typeof value !== 'string' && typeof value !== 'number') return fallback;
        const text = String(value).trim();
        return text.length ? text : fallback;
    }

    function setText(element, value, fallback) {
        element.textContent = safeText(value, fallback);
    }

    function cancelTimer() {
        if (autoCloseTimer !== null) {
            window.clearTimeout(autoCloseTimer);
            autoCloseTimer = null;
        }
    }

    function hide() {
        cancelTimer();
        currentMode = null;
        overlay.classList.add('is-hidden');
        overlay.setAttribute('aria-hidden', 'true');
        credential.classList.remove('mode-presented');
    }

    async function requestClose() {
        hide();
        try {
            await fetch(`https://${resourceName}/close`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: '{}'
            });
        } catch (_) {
            // NUI may already be closing during a resource stop.
        }
    }

    function open(payload) {
        const card = payload.card || {};
        currentMode = payload.mode === 'presented' ? 'presented' : 'own';

        setText(elements.authority, card.authority, 'CITY OF LOS SANTOS');
        setText(elements.agency, card.agency, 'UNITED STATES GOVERNMENT');
        setText(elements.department, card.department, 'EXECUTIVE & JUDICIAL AUTHORITY');
        setText(elements.fullName, card.fullName, 'UNKNOWN OFFICIAL');
        setText(elements.rank, card.rank, 'GOVERNMENT OFFICIAL');
        setText(elements.credential, card.credential, 'GOV-000000');
        setText(elements.footer, card.footer, 'Official government credential.');

        credential.classList.toggle('mode-presented', currentMode === 'presented');
        overlay.classList.remove('is-hidden');
        overlay.setAttribute('aria-hidden', 'false');

        cancelTimer();
        const duration = Number(payload.autoCloseMs);
        if (currentMode === 'presented' && Number.isFinite(duration) && duration > 0) {
            autoCloseTimer = window.setTimeout(hide, duration);
        }
    }

    window.addEventListener('message', (event) => {
        const payload = event.data;
        if (!payload || typeof payload !== 'object') return;

        if (payload.action === 'open') open(payload);
        if (payload.action === 'close') hide();
    });

    closeButton.addEventListener('click', () => {
        if (currentMode === 'own') requestClose();
    });

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && currentMode === 'own') requestClose();
    });

    hide();
})();
