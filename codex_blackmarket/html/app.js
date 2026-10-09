(() => {
    'use strict';

    const root = document.getElementById('app');
    const content = document.getElementById('content');
    const nav = document.getElementById('nav');
    const toastNode = document.getElementById('toast');
    const state = {
        mode: 'market',
        data: null,
        adminData: null,
        page: 'market',
        category: null,
        cart: {},
        payment: 'cash',
        warehouseId: null,
        busy: false,
        toastTimer: null
    };

    const navItems = [
        { id: 'market', label: 'Exchange', icon: '⌖' },
        { id: 'runs', label: 'Cargo Runs', icon: '↗' },
        { id: 'sell', label: 'Sell Goods', icon: '⇄' },
        { id: 'warehouses', label: 'Warehouses', icon: '▦' },
        { id: 'profile', label: 'Your Profile', icon: '⌬' }
    ];
    const pageMeta = {
        market: ['Black Market', 'Unmarked goods. Discreet transactions.', 'EXCHANGE'],
        runs: ['Cargo Contracts', 'Earn respect. Unlock access. Get paid.', 'CONTRACTS'],
        sell: ['Sell Contraband', 'Quietly move recovered goods through the network.', 'BUYER'],
        warehouses: ['Secure Warehouses', 'Private storage. Individual passcodes.', 'STORAGE'],
        profile: ['Your Standing', 'Trust is earned one run at a time.', 'PROFILE'],
        admin: ['Market Control', 'Live stock and price controls.', 'ADMIN']
    };

    function getResourceName() {
        return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'codex_blackmarket';
    }

    async function post(endpoint, payload = {}) {
        try {
            const response = await fetch(`https://${getResourceName()}/${endpoint}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(payload)
            });
            return await response.json();
        } catch (error) {
            return { ok: false, message: 'The secure connection could not be reached.' };
        }
    }

    function escapeHtml(value) {
        return String(value ?? '').replace(/[&<>"']/g, (character) => ({
            '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
        }[character]));
    }

    function money(value) {
        const amount = Number(value) || 0;
        return '$' + Math.round(amount).toLocaleString('en-US');
    }

    function notify(message, isError = false) {
        if (!message) return;
        toastNode.textContent = message;
        toastNode.className = `toast show${isError ? ' error' : ''}`;
        clearTimeout(state.toastTimer);
        state.toastTimer = setTimeout(() => { toastNode.className = 'toast'; }, 2800);
    }

    function hide() {
        root.classList.add('hidden');
        root.setAttribute('aria-hidden', 'true');
        state.busy = false;
    }

    function close() {
        post('close');
        hide();
    }

    function currentProfile() {
        return state.data?.profile || { name: 'Unknown', level: 1, xp: 0, respect: 0, progressPercent: 0, completedRuns: 0 };
    }

    function currentPageList() {
        if (state.mode === 'admin') return [{ id: 'admin', label: 'Market Control', icon: '⚙' }];
        if (state.mode === 'warehouse') return [navItems[3], navItems[4]];
        return navItems;
    }

    function renderNav() {
        const pages = currentPageList();
        if (!pages.some((item) => item.id === state.page)) state.page = pages[0]?.id || 'market';
        nav.innerHTML = pages.map((item) => `
            <button class="nav-button ${state.page === item.id ? 'active' : ''}" data-page="${escapeHtml(item.id)}">
                <span class="nav-icon">${escapeHtml(item.icon)}</span><span class="nav-label">${escapeHtml(item.label)}</span>
            </button>
        `).join('');
    }

    function renderHeader() {
        const profile = currentProfile();
        const meta = pageMeta[state.page] || pageMeta.market;
        document.getElementById('pageTitle').textContent = meta[0];
        document.getElementById('pageSubtitle').textContent = meta[1];
        document.getElementById('crumbCurrent').textContent = meta[2];
        document.getElementById('playerName').textContent = profile.name || 'Unknown';
        document.getElementById('playerRank').textContent = `Level ${Number(profile.level) || 1} Operative`;
        document.getElementById('playerInitial').textContent = (profile.name || '?').trim().charAt(0).toUpperCase() || '?';
        document.getElementById('sidebarLevel').textContent = String(Number(profile.level) || 1).padStart(2, '0');
        document.getElementById('sidebarRespect').textContent = Number(profile.respect || 0).toLocaleString('en-US');
        const hours = state.data?.hours;
        const status = document.getElementById('openStatus');
        const pill = status.closest('.market-open-pill');
        if (hours?.enabled) {
            status.textContent = 'CONTACT ONLINE';
            pill.classList.remove('closed');
            document.getElementById('footerTime').textContent = `LOCAL NODE · ${String(hours.open).padStart(2, '0')}:00—${String(hours.close).padStart(2, '0')}:00`;
        } else {
            status.textContent = 'NETWORK AVAILABLE';
            pill.classList.remove('closed');
            document.getElementById('footerTime').textContent = 'LOCAL NODE · PRIVATE';
        }
    }

    function render() {
        if (!state.data && state.mode !== 'admin') return;
        renderNav();
        renderHeader();
        if (state.mode === 'admin') {
            content.innerHTML = renderAdmin();
            return;
        }
        switch (state.page) {
            case 'runs': content.innerHTML = renderRuns(); break;
            case 'sell': content.innerHTML = renderSell(); break;
            case 'warehouses': content.innerHTML = renderWarehouses(); break;
            case 'profile': content.innerHTML = renderProfile(); break;
            default: content.innerHTML = renderMarket(); break;
        }
    }

    function renderMarket() {
        const data = state.data || {};
        const profile = currentProfile();
        const categories = data.categories || [];
        if (!state.category || !categories.some((category) => category.id === state.category)) {
            state.category = categories[0]?.id || null;
        }
        const activeCategory = categories.find((category) => category.id === state.category);
        const products = (data.products || []).filter((product) => product.category === state.category);
        const categoryButtons = categories.map((category) => `
            <button class="category-button ${state.category === category.id ? 'active' : ''} ${category.locked ? 'locked' : ''}" data-category="${escapeHtml(category.id)}">
                <span class="cat-icon">${escapeHtml(category.icon || '◈')}</span>
                <span>${escapeHtml(category.label)}</span>
                ${category.locked ? `<small>LVL ${Number(category.minLevel) || 1}</small>` : ''}
            </button>
        `).join('');
        const productCards = products.length ? products.map((product) => {
            const locked = product.locked === true;
            const soldOut = Number(product.stock) <= 0;
            return `
                <article class="product-card ${locked ? 'is-locked' : ''}">
                    <div class="product-top">
                        <div class="item-glyph">${escapeHtml(product.icon || '◈')}</div>
                        <span class="stock-pill ${Number(product.stock) <= 5 ? 'low' : ''}">${soldOut ? 'OUT OF STOCK' : `${Number(product.stock)} IN STOCK`}</span>
                    </div>
                    <h3>${escapeHtml(product.label)}</h3>
                    <p class="description">${escapeHtml(product.description)}</p>
                    <div class="product-bottom">
                        ${locked ? `<span class="locked-label">LOCKED · LEVEL ${Number(product.requiredLevel) || 1}</span>` : `<span class="price"><small>USD</small>${money(product.price)}</span>`}
                        <div class="product-actions">
                            ${locked ? '' : `<input class="qty-input" type="number" min="1" max="${Number(product.maxQuantity) || 25}" value="1" aria-label="Quantity for ${escapeHtml(product.label)}" data-quantity="${escapeHtml(product.item)}">`}
                            <button class="primary-button" data-add="${escapeHtml(product.item)}" ${locked || soldOut ? 'disabled' : ''}>${locked ? 'Locked' : soldOut ? 'Sold out' : 'Add +'}</button>
                        </div>
                    </div>
                </article>
            `;
        }).join('') : '<div class="empty-products">No registered items in this category.</div>';
        const cartRows = renderCartLines();
        const cartSubtotal = getCartTotal();
        const cartCount = Object.values(state.cart).reduce((sum, amount) => sum + (Number(amount) || 0), 0);

        return `
            <div class="market-layout">
                <div class="market-main">
                    <section class="hero-strip">
                        <div>
                            <p class="eyebrow">TRADE ON YOUR REPUTATION</p>
                            <h2>Welcome to the network, ${escapeHtml(profile.name || 'operative')}.</h2>
                            <p>Restricted inventory unlocks as your access level rises. Stock and pricing update with demand.</p>
                        </div>
                        <div class="hero-stat"><span>YOUR ACCESS</span><strong>LVL ${String(Number(profile.level) || 1).padStart(2, '0')}</strong></div>
                    </section>
                    <div class="section-head"><div><h2>${escapeHtml(activeCategory?.label || 'Catalog')}</h2><p>${escapeHtml(activeCategory?.description || 'Select a category to browse.')}</p></div><span class="section-kicker">${products.length} LISTED ITEMS</span></div>
                    <div class="category-row">${categoryButtons}</div>
                    <div class="product-grid">${productCards}</div>
                </div>
                <aside class="panel cart-panel">
                    <div class="cart-heading"><h2>Encrypted Basket</h2><span class="cart-count">${cartCount}</span></div>
                    <div class="cart-lines">${cartRows}</div>
                    <div class="cart-summary">
                        <div class="summary-row"><span>Items</span><span>${cartCount}</span></div>
                        <div class="summary-row"><span>Market adjustment</span><span>Included</span></div>
                        <div class="summary-row total"><span>Due now</span><strong>${money(cartSubtotal)}</strong></div>
                    </div>
                    <div class="payment-choice">
                        <button class="payment-button ${state.payment === 'cash' ? 'active' : ''}" data-payment="cash">CASH</button>
                        <button class="payment-button ${state.payment === 'bank' ? 'active' : ''}" data-payment="bank">BANK</button>
                    </div>
                    <button class="primary-button checkout-button" data-checkout ${cartCount <= 0 || state.busy ? 'disabled' : ''}>${state.busy ? 'Processing…' : 'Confirm Purchase'} <span>→</span></button>
                    <p class="cart-note">Every order is re-priced and validated by the server at checkout.</p>
                </aside>
            </div>
        `;
    }

    function getCartTotal() {
        const priceByItem = new Map((state.data?.products || []).map((product) => [product.item, Number(product.price) || 0]));
        return Object.entries(state.cart).reduce((sum, [item, amount]) => sum + (priceByItem.get(item) || 0) * (Number(amount) || 0), 0);
    }

    function renderCartLines() {
        const entries = Object.entries(state.cart).filter(([, amount]) => Number(amount) > 0);
        if (!entries.length) return '<div class="cart-empty"><div><span>Your basket is empty</span>Add a catalog item to begin.</div></div>';
        const labels = new Map((state.data?.products || []).map((product) => [product.item, product]));
        return entries.map(([item, amount]) => {
            const product = labels.get(item);
            const price = Number(product?.price) || 0;
            return `
                <div class="cart-line">
                    <div><strong>${escapeHtml(product?.label || item)}</strong><small>${Number(amount)} × ${money(price)}</small></div>
                    <div class="cart-line-right"><b>${money(price * Number(amount))}</b><button class="remove-line" data-remove="${escapeHtml(item)}" aria-label="Remove item">×</button></div>
                </div>
            `;
        }).join('');
    }

    function renderRuns() {
        const missions = state.data?.missions || [];
        const cards = missions.map((mission) => `
            <article class="run-card ${mission.available ? '' : 'locked'}">
                <div class="run-card-top"><span class="run-tier">CONTRACT TIER 0${Number(mission.id)}</span><span class="card-level ${mission.available ? '' : 'locked'}">${mission.available ? `ACCESS ${Number(mission.minLevel)}` : `LOCKED · LVL ${Number(mission.minLevel)}`}</span></div>
                <h3>${escapeHtml(mission.label)}</h3>
                <p>${escapeHtml(mission.description)}</p>
                <div class="run-stats">
                    <div class="run-stat"><span>REWARD</span><b class="green">${money(mission.reward)}</b></div>
                    <div class="run-stat"><span>STOPS</span><b>${Number(mission.drops)}</b></div>
                    <div class="run-stat"><span>DEPOSIT</span><b>${money(mission.deposit)}</b></div>
                </div>
                <button class="primary-button" data-start-run="${Number(mission.id)}" ${mission.available ? '' : 'disabled'}>${mission.available ? 'Accept Contract →' : 'Access Restricted'}</button>
                ${mission.available ? '<small class="run-warning">Deposit is returned with payout after all handoffs.</small>' : ''}
            </article>
        `).join('');
        return `
            <section class="hero-strip"><div><p class="eyebrow">WORK BUILDS TRUST</p><h2>Prove you can deliver.</h2><p>Pick up the cargo at the contact, follow the GPS route, and confirm each handoff from the driver's seat.</p></div><div class="hero-stat"><span>RUNS CLEARED</span><strong>${Number(currentProfile().completedRuns || 0)}</strong></div></section>
            <div class="section-head"><div><h2>Available Contracts</h2><p>Higher tiers pay more and raise your standing faster.</p></div><span class="section-kicker">SERVER-VERIFIED DROPS</span></div>
            <div class="data-grid">${cards || '<div class="empty-products">No delivery contracts are configured.</div>'}</div>
        `;
    }

    function renderSell() {
        const offers = state.data?.sellOffers || [];
        const cards = offers.map((offer) => `
            <article class="info-card">
                <div class="product-top"><div class="item-glyph">${escapeHtml(offer.icon || '◈')}</div><span class="stock-pill">${Number(offer.owned)} OWNED</span></div>
                <h3>${escapeHtml(offer.label)}</h3>
                <p>${escapeHtml(offer.description)}</p>
                <div class="detail-row"><span>Offer per item</span><b>${money(offer.price)}</b></div>
                <div class="detail-row"><span>Estimated maximum</span><b>${money(Number(offer.price) * Number(offer.owned))}</b></div>
                <div class="product-bottom"><input class="qty-input" type="number" min="1" max="100" value="1" aria-label="Sell quantity for ${escapeHtml(offer.label)}" data-sell-quantity="${escapeHtml(offer.item)}"><button class="secondary-button" data-sell="${escapeHtml(offer.item)}" ${Number(offer.owned) <= 0 ? 'disabled' : ''}>Sell Goods</button></div>
            </article>
        `).join('');
        return `
            <section class="hero-strip"><div><p class="eyebrow">THE BUYER IS LISTENING</p><h2>Move your recovered goods.</h2><p>Offers are fixed per item. The server checks your inventory before paying out.</p></div><div class="hero-stat"><span>SETTLEMENT</span><strong>CASH / BANK</strong></div></section>
            <div class="section-head"><div><h2>Current Offers</h2><p>Items not installed in your QBCore inventory are hidden.</p></div><span class="section-kicker">NO CONSIGNMENT FEES</span></div>
            <div class="data-grid">${cards || '<div class="empty-products">No sell offers are currently configured.</div>'}</div>
            <div class="payment-choice" style="max-width:220px;margin-top:12px;padding-left:0"><button class="payment-button ${state.payment === 'cash' ? 'active' : ''}" data-payment="cash">CASH</button><button class="payment-button ${state.payment === 'bank' ? 'active' : ''}" data-payment="bank">BANK</button></div>
        `;
    }

    function renderWarehouses() {
        const warehouses = state.data?.warehouses || [];
        const cards = warehouses.map((warehouse) => {
            const unlocked = warehouse.unlocked === true;
            const code = escapeHtml(warehouse.pin || '------');
            return `
                <article class="info-card ${unlocked ? '' : 'is-locked'}">
                    <div class="product-top"><div class="item-glyph">▦</div><span class="card-level ${unlocked ? '' : 'locked'}">${unlocked ? 'PRIVATE UNIT' : `ACCESS LVL ${Number(warehouse.minLevel)}`}</span></div>
                    <h3>${escapeHtml(warehouse.label)}</h3>
                    <p>${unlocked ? 'Dedicated storage space, unique to your character. Never share your PIN.' : 'Increase your access level to unlock this location.'}</p>
                    <div class="detail-row"><span>Storage slots</span><b>${Number(warehouse.slots)}</b></div>
                    <div class="detail-row"><span>Capacity</span><b>${Math.round(Number(warehouse.maxWeight) / 1000)} kg</b></div>
                    ${unlocked ? `
                        <div class="pin-wrap"><div class="pin-code">${code}</div><input class="pin-input" type="text" maxlength="6" inputmode="numeric" value="${code}" aria-label="Warehouse PIN" data-pin="${escapeHtml(warehouse.id)}"></div>
                        <div class="warehouse-actions"><button class="primary-button" data-open-warehouse="${escapeHtml(warehouse.id)}">Unlock storage →</button></div>
                    ` : '<div class="pin-wrap"><div class="pin-code" style="color:#5f6c63">••••••</div></div>'}
                </article>
            `;
        }).join('');
        return `
            <section class="hero-strip"><div><p class="eyebrow">PRIVATE PROPERTY NETWORK</p><h2>Your own space off the books.</h2><p>Each eligible operative has a personal PIN and a separate persistent qb-inventory stash.</p></div><div class="hero-stat"><span>ACTIVE UNITS</span><strong>${warehouses.filter((item) => item.unlocked).length} / ${warehouses.length}</strong></div></section>
            <div class="section-head"><div><h2>Secure Locations</h2><p>Enter the assigned code at the terminal to open your storage.</p></div><span class="section-kicker">CITIZEN-LOCKED</span></div>
            <div class="data-grid">${cards}</div>
        `;
    }

    function renderProfile() {
        const profile = currentProfile();
        const percent = Math.max(0, Math.min(100, Number(profile.progressPercent) || 0));
        const next = profile.nextThreshold == null ? 'MAX' : Number(profile.nextThreshold).toLocaleString('en-US');
        return `
            <div class="profile-layout">
                <section class="profile-card">
                    <div class="profile-identity"><div class="big-avatar">${escapeHtml((profile.name || '?').trim().charAt(0).toUpperCase())}</div><div><p class="eyebrow">NETWORK MEMBER</p><h2>${escapeHtml(profile.name || 'Unknown Operative')}</h2><p>Trusted access level ${Number(profile.level) || 1}</p></div></div>
                    <div class="xp-block"><div class="xp-label"><span>ACCESS PROGRESS</span><strong>${Number(profile.xp || 0).toLocaleString('en-US')} XP ${profile.nextThreshold == null ? '· MAX LEVEL' : `· NEXT ${next}`}</strong></div><div class="xp-track"><div class="xp-fill" style="width:${percent}%"></div></div></div>
                    <div class="profile-stats">
                        <div class="profile-stat"><span>ACCESS LEVEL</span><strong>${String(Number(profile.level) || 1).padStart(2, '0')}</strong></div>
                        <div class="profile-stat"><span>RESPECT</span><strong>${Number(profile.respect || 0).toLocaleString('en-US')}</strong></div>
                        <div class="profile-stat"><span>RUNS CLEARED</span><strong>${Number(profile.completedRuns || 0).toLocaleString('en-US')}</strong></div>
                    </div>
                </section>
                <aside class="profile-note"><p class="eyebrow">HOW TRUST WORKS</p><h3>Earn your way up.</h3><p>Complete cargo contracts to gain XP and respect. Each new access level unlocks more inventory, contracts, and warehouse locations. Your progress is saved to your character and survives restarts.</p></aside>
            </div>
        `;
    }

    function renderAdmin() {
        const rows = state.adminData?.items || [];
        return `
            <section class="hero-strip"><div><p class="eyebrow">AUTHORIZED PERSONNEL ONLY</p><h2>Market Control</h2><p>Changes are saved immediately and persist in the database. Set price to zero to use config.lua pricing.</p></div><div class="hero-stat"><span>CATALOG</span><strong>${rows.length} ITEMS</strong></div></section>
            <p class="admin-help">Stock is clamped to each item's configured maximum. Price overrides still use the live scarcity multiplier.</p>
            <div class="admin-list">${rows.map((item) => `
                <div class="admin-row">
                    <div class="admin-product"><strong>${escapeHtml(item.label)}</strong><small>${escapeHtml(item.item)} · ${item.hasOverride ? 'CUSTOM PRICE' : 'CONFIG PRICE'}</small></div>
                    <label class="admin-field"><span>BASE PRICE · 0 = CONFIG</span><input class="admin-input" type="number" min="0" max="1000000" value="${item.hasOverride ? Number(item.price) : 0}" data-admin-price="${escapeHtml(item.item)}"></label>
                    <label class="admin-field"><span>LIVE STOCK</span><input class="admin-input" type="number" min="0" max="${Number(item.maxStock)}" value="${Number(item.stock)}" data-admin-stock="${escapeHtml(item.item)}"></label>
                    <button class="secondary-button" data-admin-save="${escapeHtml(item.item)}">Save</button>
                </div>
            `).join('') || '<div class="empty-products">No registered market items found.</div>'}</div>
        `;
    }

    function openMessage(message) {
        state.mode = message.mode || 'market';
        state.data = message.data || null;
        state.adminData = state.mode === 'admin' ? (message.data || { items: [] }) : null;
        state.warehouseId = message.warehouseId || null;
        state.cart = {};
        state.payment = 'cash';
        state.category = null;
        state.page = state.mode === 'admin' ? 'admin' : state.mode === 'warehouse' ? 'warehouses' : 'market';
        root.classList.remove('hidden');
        root.setAttribute('aria-hidden', 'false');
        render();
    }

    window.addEventListener('message', (event) => {
        const message = event.data || {};
        if (message.action === 'open') openMessage(message);
        if (message.action === 'show') { root.classList.remove('hidden'); root.setAttribute('aria-hidden', 'false'); }
        if (message.action === 'hide' || message.action === 'close') hide();
        if (message.action === 'updateData' && message.data) {
            state.data = message.data;
            render();
        }
        if (message.action === 'updateAdminData' && message.data) {
            state.adminData = message.data;
            render();
        }
    });

    document.addEventListener('click', async (event) => {
        const button = event.target.closest('button');
        if (!button) return;

        if (button.id === 'closeButton') { close(); return; }
        if (button.dataset.page) {
            state.page = button.dataset.page;
            render();
            return;
        }
        if (button.dataset.category) {
            state.category = button.dataset.category;
            render();
            return;
        }
        if (button.dataset.payment) {
            state.payment = button.dataset.payment;
            render();
            return;
        }
        if (button.dataset.add) {
            if (button.disabled) return;
            const item = button.dataset.add;
            const input = document.querySelector(`[data-quantity="${CSS.escape(item)}"]`);
            const product = (state.data?.products || []).find((row) => row.item === item);
            const maxQuantity = Math.max(1, Number(product?.maxQuantity) || 25);
            const amount = Math.max(1, Math.min(maxQuantity, Math.floor(Number(input?.value) || 1)));
            state.cart[item] = Math.min(maxQuantity, (Number(state.cart[item]) || 0) + amount);
            render();
            return;
        }
        if (button.dataset.remove) {
            delete state.cart[button.dataset.remove];
            render();
            return;
        }
        if (button.hasAttribute('data-checkout')) {
            if (state.busy) return;
            const items = Object.entries(state.cart).map(([item, amount]) => ({ item, amount: Number(amount) }));
            if (!items.length) return;
            state.busy = true;
            render();
            const result = await post('checkout', { items, account: state.payment });
            state.busy = false;
            if (result?.ok) {
                state.cart = {};
                if (result.data) state.data = result.data;
                notify(result.message || 'Purchase complete.');
            } else {
                notify(result?.message || 'Checkout failed.', true);
            }
            render();
            return;
        }
        if (button.dataset.sell) {
            if (button.disabled || state.busy) return;
            const item = button.dataset.sell;
            const input = document.querySelector(`[data-sell-quantity="${CSS.escape(item)}"]`);
            const amount = Math.max(1, Math.min(100, Math.floor(Number(input?.value) || 1)));
            state.busy = true;
            const result = await post('sell', { item, amount, account: state.payment });
            state.busy = false;
            if (result?.ok) {
                if (result.data) state.data = result.data;
                notify(result.message || 'Goods sold.');
            } else {
                notify(result?.message || 'Sale failed.', true);
            }
            render();
            return;
        }
        if (button.dataset.startRun) {
            if (button.disabled || state.busy) return;
            state.busy = true;
            render();
            const result = await post('startMission', { tier: Number(button.dataset.startRun) });
            state.busy = false;
            if (!result?.ok) {
                notify(result?.message || 'Contract could not be accepted.', true);
                render();
            }
            return;
        }
        if (button.dataset.openWarehouse) {
            if (state.busy) return;
            const id = button.dataset.openWarehouse;
            const input = document.querySelector(`[data-pin="${CSS.escape(id)}"]`);
            const pin = String(input?.value || '').trim();
            state.busy = true;
            const result = await post('openWarehouse', { id, pin });
            state.busy = false;
            if (!result?.ok) notify(result?.message || 'Access denied.', true);
            else notify(result.message || 'Storage unlocked.');
            return;
        }
        if (button.dataset.adminSave) {
            const item = button.dataset.adminSave;
            const priceInput = document.querySelector(`[data-admin-price="${CSS.escape(item)}"]`);
            const stockInput = document.querySelector(`[data-admin-stock="${CSS.escape(item)}"]`);
            state.busy = true;
            button.disabled = true;
            const result = await post('adminUpdate', { item, price: Number(priceInput?.value) || 0, stock: Number(stockInput?.value) || 0 });
            state.busy = false;
            if (result?.ok) {
                if (result.data) state.adminData = result.data;
                notify(result.message || 'Settings saved.');
            } else {
                notify(result?.message || 'Could not save settings.', true);
            }
            render();
        }
    });

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && !root.classList.contains('hidden')) {
            event.preventDefault();
            close();
        }
    });

    document.addEventListener('input', (event) => {
        const target = event.target;
        if (target.matches('[data-pin]')) target.value = target.value.replace(/\D/g, '').slice(0, 6);
        if (target.matches('.qty-input')) {
            const maximum = Number(target.max) || 100;
            const value = Number(target.value);
            if (Number.isFinite(value) && value > maximum) target.value = String(maximum);
        }
    });
})();
