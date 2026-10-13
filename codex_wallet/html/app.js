/* ==========================================================================
   CodeX Wallet - NUI logic
   The NUI only sends intents; every action is validated server-side.
   ========================================================================== */

(function () {
    'use strict';

    const walletApp = document.getElementById('wallet-app');
    const cardOverlay = document.getElementById('card-overlay');

    let state = {
        wallet: null,
        player: null,
        inventory: [],
        limits: {}
    };

    // -- helpers -----------------------------------------------------------
    function resourceName() {
        if (typeof GetParentResourceName === 'function') {
            return GetParentResourceName();
        }
        return 'codex_wallet';
    }

    function post(action, data) {
        return fetch(`https://${resourceName()}/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).catch(function () { /* the game closing can abort requests */ });
    }

    function formatMoney(value) {
        return String(Math.floor(Number(value) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    function esc(value) {
        const div = document.createElement('div');
        div.textContent = value == null ? '' : String(value);
        return div.innerHTML;
    }

    function el(tag, className, text) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (text != null) node.textContent = String(text);
        return node;
    }

    const ICONS = {
        id_card: '🪪',
        driver_license: '🚗',
        weaponlicense: '🛡️',
        government_id: '🏛️',
        dos_id_card: '🕵️',
        default: '📄'
    };

    function iconFor(name) {
        return ICONS[name] || ICONS.default;
    }

    function holderNameFrom(meta, fallback) {
        meta = meta || {};
        const first = meta.firstname || meta.firstName || '';
        const last = meta.lastname || meta.lastName || '';
        const combined = (first + ' ' + last).trim();
        return combined || fallback || 'Unknown';
    }

    // -- render ------------------------------------------------------------
    function render() {
        const wallet = state.wallet || {};
        const player = state.player || {};
        const limits = state.limits || {};

        document.getElementById('serial-chip').textContent = wallet.serial || 'CXW-••••';
        document.getElementById('hero-name').textContent = player.name || '—';
        document.getElementById('hero-job').textContent = player.job || '—';
        document.getElementById('hero-cash').textContent = formatMoney(wallet.cash);
        document.getElementById('hero-slots').textContent =
            `${wallet.slotsUsed || 0} / ${wallet.slotsMax || 0} slots`;
        document.getElementById('hero-weight').textContent =
            `${Math.floor(wallet.weightUsed || 0)} g / ${Math.floor(wallet.weightMax || 0)} g`;
        document.getElementById('hero-citizenid').textContent = player.citizenid || '—';

        document.getElementById('cards-count').textContent =
            `${wallet.slotsUsed || 0} / ${wallet.slotsMax || 0}`;

        if (limits.moneyEnabled === false) {
            document.getElementById('panel-cash').classList.add('hidden');
        }

        renderCash(limits, wallet);
        renderCards(wallet.items || []);
        renderStore(state.inventory || []);
    }

    function renderCash(limits, wallet) {
        const mode = limits.moneyMode === 'account' ? 'account' : 'item';
        const invCash = Math.floor(Number(limits.inventoryCash) || 0);
        const walletCash = Math.floor(Number(wallet.cash) || 0);

        document.getElementById('inv-cash').textContent = '$' + formatMoney(invCash);
        document.getElementById('wallet-cash').textContent = '$' + formatMoney(walletCash);

        const hint = document.getElementById('cash-hint');
        if (mode === 'item') {
            hint.textContent =
                `Cash items (${limits.cashItemLabel || 'Cash'}) move between your inventory and the wallet. Nothing is created or destroyed.`;
        } else {
            hint.textContent =
                'Money moves between your pocket (cash account) and the wallet. Nothing is created or destroyed.';
        }
    }

    function maxDeposit(limits, wallet) {
        const invCash = Math.floor(Number(limits.inventoryCash) || 0);
        const walletCash = Math.floor(Number(wallet.cash) || 0);
        const maxAmount = Math.floor(Number(limits.maxAmount) || 0);
        const maxBalance = Math.floor(Number(limits.maxBalance) || 0);
        return Math.max(0, Math.min(invCash, maxAmount, maxBalance - walletCash));
    }

    function maxWithdraw(wallet) {
        const walletCash = Math.floor(Number(wallet.cash) || 0);
        const maxAmount = Math.floor(Number(state.limits.maxAmount) || 0);
        return Math.max(0, Math.min(walletCash, maxAmount));
    }

    function renderCards(items) {
        const grid = document.getElementById('cards-grid');
        const empty = document.getElementById('cards-empty');
        grid.innerHTML = '';

        if (!items.length) {
            grid.classList.add('hidden');
            empty.classList.remove('hidden');
            return;
        }

        grid.classList.remove('hidden');
        empty.classList.add('hidden');

        items.forEach(function (item) {
            const card = el('div', 'doc-card');

            const top = el('div', 'doc-top');
            const icon = el('div', 'doc-icon', iconFor(item.name));
            const nameWrap = el('div');
            nameWrap.appendChild(el('div', 'doc-name', item.label || item.name));
            nameWrap.appendChild(el('span', 'doc-type', item.name));
            top.appendChild(icon);
            top.appendChild(nameWrap);
            card.appendChild(top);

            card.appendChild(el('div', 'doc-holder',
                '👤 ' + holderNameFrom(item.metadata, state.player && state.player.name)));

            const actions = el('div', 'doc-actions');

            const showBtn = el('button', 'btn btn-small btn-gold', 'Show ID');
            showBtn.addEventListener('click', function (event) {
                event.stopPropagation();
                post('action', { action: 'showItem', data: { index: item.index } });
            });

            const removeBtn = el('button', 'btn btn-small btn-outline btn-danger', 'Remove');
            removeBtn.addEventListener('click', function (event) {
                event.stopPropagation();
                post('action', { action: 'removeItem', data: { index: item.index } });
            });

            actions.appendChild(showBtn);
            actions.appendChild(removeBtn);
            card.appendChild(actions);

            grid.appendChild(card);
        });
    }

    function renderStore(items) {
        const list = document.getElementById('store-list');
        const empty = document.getElementById('store-empty');
        list.innerHTML = '';

        if (!items.length) {
            list.classList.add('hidden');
            empty.classList.remove('hidden');
            return;
        }

        list.classList.remove('hidden');
        empty.classList.add('hidden');

        items.forEach(function (item) {
            const row = el('div', 'store-row');

            row.appendChild(el('div', 'doc-icon', iconFor(item.name)));

            const info = el('div', 'store-info');
            info.appendChild(el('div', 'store-label', item.label || item.name));
            info.appendChild(el('span', 'store-desc', item.description || item.name));
            row.appendChild(info);

            const storeBtn = el('button', 'btn btn-small btn-outline', 'Store');
            storeBtn.addEventListener('click', function () {
                post('action', { action: 'storeItem', data: { slot: item.slot } });
            });
            row.appendChild(storeBtn);

            list.appendChild(row);
        });
    }

    // -- presented ID card -------------------------------------------------
    function showCard(card, presenterName) {
        card = card || {};

        document.getElementById('pc-label').textContent = card.label || card.cardType || 'ID Card';
        document.getElementById('pc-firstname').textContent = card.firstName || '—';
        document.getElementById('pc-lastname').textContent = card.lastName || '—';
        document.getElementById('pc-birthdate').textContent = card.birthdate || '—';
        document.getElementById('pc-gender').textContent =
            card.gender === 0 || card.gender === '0' ? 'Male' :
            (card.gender === 1 || card.gender === '1' ? 'Female' : (card.gender || '—'));
        document.getElementById('pc-nationality').textContent = card.nationality || '—';
        document.getElementById('pc-serial').textContent = card.serial || card.citizenid || '—';
        document.getElementById('pc-type').textContent = card.licenseType || card.label || 'Identification Card';
        document.getElementById('pc-presenter').textContent = presenterName || '—';

        const initials = ((card.firstName || '?').charAt(0) + (card.lastName || '').charAt(0)).toUpperCase();
        document.getElementById('pc-initials').textContent = initials || '?';

        cardOverlay.classList.remove('hidden');
    }

    function closeCard() {
        cardOverlay.classList.add('hidden');
    }

    // -- open / close ------------------------------------------------------
    function openWallet(payload) {
        state.wallet = (payload && payload.wallet) || {};
        state.player = (payload && payload.player) || {};
        state.inventory = (payload && payload.inventory) || [];
        state.limits = (payload && payload.limits) || {};
        render();
        walletApp.classList.remove('hidden');
    }

    function closeWallet() {
        walletApp.classList.add('hidden');
        post('close', {});
    }

    // -- events ------------------------------------------------------------
    window.addEventListener('message', function (event) {
        const data = event.data || {};

        if (data.action === 'open') {
            openWallet(data.payload);
        } else if (data.action === 'close') {
            walletApp.classList.add('hidden');
        } else if (data.action === 'showCard') {
            showCard(data.card, data.presenterName);
        } else if (data.action === 'closeCard') {
            closeCard();
        }
    });

    document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') {
            if (!cardOverlay.classList.contains('hidden')) {
                closeCard();
                return;
            }
            if (!walletApp.classList.contains('hidden')) {
                closeWallet();
            }
        }
    });

    // -- static bindings ---------------------------------------------------
    document.getElementById('btn-close').addEventListener('click', closeWallet);
    document.getElementById('btn-card-close').addEventListener('click', closeCard);

    document.getElementById('btn-deposit').addEventListener('click', function () {
        const input = document.getElementById('cash-amount');
        const value = (input.value || '').trim();
        // empty amount = deposit everything possible (inventory -> wallet)
        const amount = value === ''
            ? maxDeposit(state.limits || {}, state.wallet || {})
            : value;
        post('action', { action: 'deposit', data: { amount: amount } });
    });

    document.getElementById('btn-withdraw').addEventListener('click', function () {
        const input = document.getElementById('cash-amount');
        const value = (input.value || '').trim();
        // empty amount = withdraw everything possible (wallet -> inventory)
        const amount = value === ''
            ? maxWithdraw(state.wallet || {})
            : value;
        post('action', { action: 'withdraw', data: { amount: amount } });
    });

    document.querySelectorAll('.quick-amount').forEach(function (button) {
        button.addEventListener('click', function () {
            const input = document.getElementById('cash-amount');
            const amount = button.getAttribute('data-amount');

            if (amount === 'all') {
                input.value = String(maxDeposit(state.limits || {}, state.wallet || {}));
            } else {
                input.value = amount;
            }
        });
    });
})();
