/* ==========================================================================
   CodeX Roleplay Inventory - UI
   ========================================================================== */
(function () {
    'use strict';

    /* ------------------------------------------------------------------ */
    /*  Environment                                                        */
    /* ------------------------------------------------------------------ */
    // In game the page is served from nui:// (or the cfx-nui- host). Anything
    // else - a normal browser, a phone, the preview server - falls back to the
    // built in mock data so the UI can be looked at without a running server.
    var IS_NUI = (window.location.protocol === 'nui:') ||
                 (/(^|\.)cfx-nui-/i.test(window.location.hostname)) ||
                 (typeof window.GetParentResourceName === 'function');

    var PREVIEW = new URLSearchParams(window.location.search).has('preview') || !IS_NUI;
    var RESOURCE = 'qb-inventory';

    var STATE = {
        ready: false,
        open: false,
        config: {},
        defaults: {},
        settings: {},
        texts: {},          // custom texts from the live editor
        hidden: {},         // keys the player chose to hide
        locked: false,
        player: {},
        inventory: [],
        other: null,
        maxSlots: 40,
        maxWeight: 120000,
        search: '',
        drag: null,
        context: null
    };

    function $(id) { return document.getElementById(id); }
    function el(tag, cls) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        return n;
    }

    /* ------------------------------------------------------------------ */
    /*  NUI bridge                                                         */
    /* ------------------------------------------------------------------ */
    function nui(name, data) {
        if (PREVIEW) { return Promise.resolve({ ok: true }); }

        return fetch('https://' + RESOURCE + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (r) { return r.json(); })
          .catch(function () { return null; });
    }

    window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data || typeof data !== 'object') return;

        switch (data.action) {
            case 'setup':        onSetup(data);      break;
            case 'open':         onOpen(data);       break;
            case 'refresh':      onRefresh(data);    break;
            case 'close':        onClose();          break;
            case 'toast':        onToast(data);      break;
            case 'playerData':   onPlayerData(data); break;
            case 'rejectMove':   flashSlot(data.slot); break;
            case 'applySettings':onApplySettings(data); break;
            default: break;
        }
    });

    /* ------------------------------------------------------------------ */
    /*  Settings                                                           */
    /* ------------------------------------------------------------------ */
    var STORE_KEY = 'codex_inventory_settings_v1';

    function loadSettings() {
        var saved = {};

        try {
            var raw = window.localStorage.getItem(STORE_KEY);
            if (raw) saved = JSON.parse(raw) || {};
        } catch (e) { saved = {}; }

        STATE.settings = Object.assign({}, STATE.defaults, saved.settings || saved);
        STATE.texts = saved.texts || {};
        STATE.hidden = saved.hidden || {};
    }

    function saveSettings() {
        try {
            window.localStorage.setItem(STORE_KEY, JSON.stringify({
                settings: STATE.settings,
                texts: STATE.texts,
                hidden: STATE.hidden
            }));
        } catch (e) { /* storage may be unavailable - not fatal */ }

        nui('SaveSettings', { settings: STATE.settings });
    }

    function defaults() {
        return {
            Layout: 'showcase', Theme: 'glass', Accent: 'emerald', CustomAccent: '',
            SlotStyle: 'rounded', IconShape: 'squircle', Font: 'modern',
            BadgeLayout: 'stack', WeightBar: 'segment', Reveal: 'rise',
            RarityStyle: 'wash', Animations: true, ReducedMotion: false,
            Sounds: true, PedPreview: true, CursorTrail: true, Language: 'en'
        };
    }

    /* ------------------------------------------------------------------ */
    /*  Translations                                                       */
    /* ------------------------------------------------------------------ */
    function lang() { return STATE.settings.Language || 'en'; }

    function t(key) {
        if (STATE.texts && STATE.texts[key] !== undefined) return STATE.texts[key];
        var pack = window.LOCALES[lang()] || window.LOCALES.en;
        if (pack && pack[key] !== undefined) return pack[key];
        return (window.LOCALES.en && window.LOCALES.en[key]) || key;
    }

    function applyTranslations() {
        document.querySelectorAll('[data-text]').forEach(function (node) {
            var key = node.getAttribute('data-text');
            node.textContent = t(key);
            node.style.display = STATE.hidden[key] ? 'none' : '';
        });

        var search = $('search');
        if (search) search.placeholder = t('search');
    }

    /* ------------------------------------------------------------------ */
    /*  Settings -> DOM                                                    */
    /* ------------------------------------------------------------------ */
    function applySettings() {
        var s = STATE.settings;
        var b = document.body;

        b.className = [
            'theme-' + s.Theme,
            'layout-' + s.Layout,
            'slot-' + s.SlotStyle,
            'icon-' + s.IconShape,
            'font-' + s.Font,
            'badge-' + s.BadgeLayout,
            'weight-' + s.WeightBar,
            'reveal-' + s.Reveal,
            'rarity-' + s.RarityStyle,
            s.Animations ? '' : 'reduced-motion',
            s.ReducedMotion ? 'reduced-motion' : '',
            s.CursorTrail ? '' : 'no-trail',
            PREVIEW ? 'preview' : ''
        ].filter(Boolean).join(' ');

        b.setAttribute('data-accent', s.Accent || 'emerald');

        if (s.CustomAccent) {
            b.style.setProperty('--accent', s.CustomAccent);
            b.style.setProperty('--accent-2', s.CustomAccent);
            b.style.setProperty('--accent-soft', hexToRgba(s.CustomAccent, 0.16));
            b.style.setProperty('--accent-line', hexToRgba(s.CustomAccent, 0.45));
        } else {
            b.style.removeProperty('--accent');
            b.style.removeProperty('--accent-2');
            b.style.removeProperty('--accent-soft');
            b.style.removeProperty('--accent-line');
        }

        document.querySelectorAll('.layout-btn').forEach(function (btn) {
            btn.classList.toggle('active', btn.dataset.layout === s.Layout);
        });

        // The trail caches the accent colour, so drop it when the theme moves.
        Trail.accent = null;

        applyTranslations();
        renderAll();
    }

    function hexToRgba(hex, alpha) {
        var h = String(hex).replace('#', '');
        if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
        var num = parseInt(h, 16);
        if (isNaN(num)) return 'rgba(16,185,129,' + alpha + ')';
        return 'rgba(' + ((num >> 16) & 255) + ',' + ((num >> 8) & 255) + ',' + (num & 255) + ',' + alpha + ')';
    }

    /* ------------------------------------------------------------------ */
    /*  Item helpers                                                       */
    /* ------------------------------------------------------------------ */
    function imagePath(item) {
        if (!item) return '';
        var img = item.image || (item.name + '.png');
        if (/\.(png|jpe?g|svg|webp)$/i.test(img)) return 'images/' + img;
        return 'images/' + img + '.png';
    }

    function itemWeight(item) {
        var each = Number(item.weight) || 0;
        return each * (Number(item.amount) || 1);
    }

    function totalWeight(items) {
        var sum = 0;
        (items || []).forEach(function (i) { if (i) sum += itemWeight(i); });
        return sum;
    }

    function usedSlots(items) {
        var n = 0;
        (items || []).forEach(function (i) { if (i && i.name) n++; });
        return n;
    }

    function matchesSearch(item) {
        if (!STATE.search) return true;
        var q = STATE.search.toLowerCase();
        return String(item.name || '').toLowerCase().indexOf(q) > -1 ||
               String(item.label || '').toLowerCase().indexOf(q) > -1;
    }

    function initials(item) {
        var src = String(item.label || item.name || '?').trim();
        var parts = src.split(/[\s_-]+/).filter(Boolean);
        if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
        return src.slice(0, 2).toUpperCase();
    }

    var RARITY_COLORS = {
        common:    ['#64748b', '#3f4a5a'],
        uncommon:  ['#22c55e', '#15803d'],
        rare:      ['#0ea5e9', '#0369a1'],
        epic:      ['#a855f7', '#7e22ce'],
        legendary: ['#f59e0b', '#b45309'],
        mythic:    ['#f43f5e', '#be123c']
    };

    function xmlEscape(value) {
        return String(value).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }

    /**
     * Procedural item tile used when an item has no image in html/images/.
     * Keeps the inventory looking finished even on a fresh install, and lets
     * servers add their own PNGs at any time (the real image always wins).
     */
    function fallbackIcon(item) {
        var rarity = (item && item.rarity) || 'common';
        var colors = RARITY_COLORS[rarity] || RARITY_COLORS.common;

        var svg =
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' +
            '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">' +
            '<stop offset="0" stop-color="' + colors[0] + '"/>' +
            '<stop offset="1" stop-color="' + colors[1] + '"/>' +
            '</linearGradient></defs>' +
            '<rect x="5" y="5" width="90" height="90" rx="22" fill="url(#g)"/>' +
            '<path d="M5 27 A22 22 0 0 1 27 5 H73 A22 22 0 0 1 95 27 V40 H5 Z" fill="#ffffff" opacity="0.12"/>' +
            '<rect x="5" y="5" width="90" height="90" rx="22" fill="none" stroke="#ffffff" stroke-opacity="0.18" stroke-width="2"/>' +
            '<text x="50" y="52" font-family="Segoe UI, Arial, sans-serif" font-size="34" ' +
            'font-weight="700" fill="#ffffff" fill-opacity="0.95" text-anchor="middle" ' +
            'dominant-baseline="central">' + xmlEscape(initials(item)) + '</text>' +
            '</svg>';

        return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    }

    /** Attaches an image that gracefully degrades to the procedural tile. */
    function iconImage(item, className) {
        var img = el('img', className || '');
        img.alt = '';
        img.src = imagePath(item);
        img.onerror = function () {
            if (img.dataset.fallbackApplied) return;
            img.dataset.fallbackApplied = '1';
            img.onerror = null;
            img.src = fallbackIcon(item);
        };
        return img;
    }

    /* ------------------------------------------------------------------ */
    /*  Render                                                             */
    /* ------------------------------------------------------------------ */
    function makeSlot(item, index, invName) {
        var slot = el('div', 'slot');

        if (!item || !item.name) {
            slot.classList.add('empty');
            slot.dataset.slot = index;
            slot.dataset.inv = invName;
            return slot;
        }

        var rarity = item.rarity || 'common';

        slot.classList.add('rar-' + rarity);
        slot.classList.add('filled');
        slot.dataset.slot = index;
        slot.dataset.inv = invName;
        slot.dataset.rarity = rarity;
        slot.title = item.label || item.name;

        var mask = el('div', 'icon-mask');

        mask.appendChild(iconImage(item, 'slot-icon'));
        slot.appendChild(mask);

        var label = el('div', 'slot-label');
        label.textContent = item.label || item.name;
        slot.appendChild(label);

        var badges = el('div', 'badges');

        if (Number(item.amount) > 1) {
            var amt = el('span', 'badge-amount');
            amt.textContent = 'x' + item.amount;
            badges.appendChild(amt);
        }

        if (item.price !== undefined && item.price !== null) {
            var price = el('span', 'badge-price');
            price.textContent = '$' + Number(item.price).toLocaleString();
            badges.appendChild(price);
        } else if (itemWeight(item) > 0 && STATE.settings.BadgeLayout !== 'minimal') {
            var w = el('span', 'badge-weight');
            w.textContent = (itemWeight(item) / 1000).toFixed(1) + 'kg';
            badges.appendChild(w);
        }

        if (item.info && item.info.quality !== undefined && item.info.quality !== null) {
            var q = el('span', 'badge-quality');
            q.textContent = Number(item.info.quality) + '%';
            badges.appendChild(q);
        }

        slot.appendChild(badges);

        var dot = el('div', 'rarity-dot');
        slot.appendChild(dot);

        if (invName === 'player' && index <= (STATE.config.hotbarSlots || 5)) {
            var key = el('div', 'hotbar-key');
            key.textContent = index;
            slot.appendChild(key);
        }

        return slot;
    }

    function renderGrid(container, items, invName) {
        if (!container) return;

        container.innerHTML = '';
        var slots = (invName === 'player')
            ? (STATE.maxSlots || 40)
            : (STATE.other ? (STATE.other.slots || items.length || 10) : items.length);

        for (var i = 1; i <= slots; i++) {
            var item = items[i];
            var node = makeSlot(item, i, invName);

            if (item && item.name && !matchesSearch(item)) {
                node.classList.add('dimmed');
            }

            container.appendChild(node);
        }
    }

    function renderPlayerCard() {
        var p = STATE.player || {};

        var name = $('pedName');
        if (name) name.textContent = p.name || 'Citizen';

        var job = $('pedJob');
        if (job) job.textContent = p.job || '';

        var cid = $('pedCid');
        if (cid) cid.textContent = p.citizenid ? ('#' + p.citizenid) : '';

        var avatar = $('pedAvatar');
        if (avatar) avatar.textContent = (p.firstname || p.name || '?').trim().charAt(0).toUpperCase();

        var cash = $('walletCash');
        if (cash) cash.textContent = Number(p.cash || 0).toLocaleString();

        var bank = $('walletBank');
        if (bank) bank.textContent = Number(p.bank || 0).toLocaleString();

        var sid = $('brandServerId');
        if (sid) sid.textContent = p.serverId || '-';

        var brand = document.querySelector('.brand-name');
        if (brand) brand.textContent = t('brand');

        var sub = document.querySelector('.brand-sub');
        if (sub) sub.textContent = t('brandSub');

        var logo = $('brandLogo');
        if (logo && STATE.config.brand && STATE.config.brand.Logo) {
            logo.src = 'images/' + STATE.config.brand.Logo;
            logo.classList.add('loaded');
        }
    }

    function renderHotbar() {
        var container = $('hotbar');
        if (!container) return;

        container.innerHTML = '';
        var count = STATE.config.hotbarSlots || 5;

        for (var i = 1; i <= count; i++) {
            var item = STATE.inventory[i];
            var cell = el('div', 'hb');

            var key = el('div', 'hb-key');
            key.textContent = i;
            cell.appendChild(key);

            if (item && item.name) {
                cell.classList.add('filled');
                cell.appendChild(iconImage(item));

                if (Number(item.amount) > 1) {
                    var a = el('div', 'hb-amt');
                    a.textContent = 'x' + item.amount;
                    cell.appendChild(a);
                }
                cell.title = item.label || item.name;
            } else {
                var fb = el('div', 'hb-fallback');
                fb.textContent = '';
                cell.appendChild(fb);
            }

            container.appendChild(cell);
        }
    }

    function renderWeight() {
        var total = totalWeight(STATE.inventory);
        var max = STATE.maxWeight || 120000;
        var pct = max > 0 ? Math.min(100, (total / max) * 100) : 0;

        var text = $('weightText');
        if (text) {
            text.textContent = (total / 1000).toFixed(1) + ' / ' + (max / 1000).toFixed(0) + ' kg';
        }

        var fill = $('weightFill');
        if (fill) {
            fill.style.width = pct + '%';
            fill.classList.toggle('warn', pct >= 75 && pct < 92);
            fill.classList.toggle('full', pct >= 92);
        }

        var wrap = $('weightWrap');
        if (wrap) wrap.style.setProperty('--pct', pct.toFixed(1));

        var count = $('playerSlotCount');
        if (count) count.textContent = usedSlots(STATE.inventory) + '/' + (STATE.maxSlots || 40);
    }

    function renderOther() {
        var panel = $('otherPanel');
        if (!panel) return;

        if (!STATE.other) {
            panel.classList.add('hidden');
            return;
        }

        panel.classList.remove('hidden');

        var label = $('otherLabel');
        if (label) label.textContent = STATE.other.label || t('container');

        var items = STATE.other.inventory || [];

        var count = $('otherSlotCount');
        if (count) count.textContent = usedSlots(items) + '/' + (STATE.other.slots || items.length || 0);

        var ow = $('otherWeight');
        if (ow) {
            ow.textContent = (totalWeight(items) / 1000).toFixed(1) + ' / ' +
                             ((STATE.other.maxweight || 0) / 1000).toFixed(0) + ' kg';
        }

        renderGrid($('otherGrid'), items, STATE.other.name || 'other');
    }

    function renderAll() {
        renderPlayerCard();
        renderHotbar();
        renderWeight();
        renderGrid($('playerGrid'), STATE.inventory, 'player');
        renderOther();
    }

    /* ------------------------------------------------------------------ */
    /*  Messages from Lua                                                  */
    /* ------------------------------------------------------------------ */
    function onSetup(data) {
        STATE.config = data.config || {};
        STATE.defaults = Object.assign(defaults(), data.defaults || {});
        STATE.player = data.player || {};
        STATE.maxSlots = STATE.config.maxSlots || 40;
        STATE.maxWeight = STATE.config.maxWeight || 120000;

        loadSettings();
        applySettings();
        STATE.ready = true;
    }

    function onOpen(data) {
        STATE.maxSlots = data.slots || STATE.maxSlots || 40;
        STATE.maxWeight = data.maxweight || STATE.maxWeight || 120000;
        STATE.inventory = data.inventory || [];
        STATE.other = data.other || null;
        STATE.player = data.player || STATE.player;
        STATE.open = true;

        $('app').classList.remove('hidden');
        renderAll();

        Sound.play('open');
    }

    function onRefresh(data) {
        if (typeof data.inventory !== 'undefined') STATE.inventory = data.inventory || [];
        if (typeof data.other !== 'undefined') STATE.other = data.other || null;
        if (data.player) STATE.player = data.player;

        renderAll();
    }

    function onClose() {
        STATE.open = false;
        $('app').classList.add('hidden');
        hideContextMenu();
        Sound.play('close');
    }

    function flashSlot(slotIndex) {
        if (!slotIndex) return;

        var node = document.querySelector('.slot[data-inv="player"][data-slot="' + slotIndex + '"]') ||
                   document.querySelector('.slot[data-slot="' + slotIndex + '"]');

        if (!node) return;

        node.classList.remove('flash-error');
        // force a reflow so the animation can be replayed
        void node.offsetWidth;
        node.classList.add('flash-error');

        window.setTimeout(function () { node.classList.remove('flash-error'); }, 400);
        Sound.play('error');
    }

    function onPlayerData(data) {
        STATE.player = data.player || STATE.player;
        renderPlayerCard();
    }

    function onApplySettings(data) {
        if (data.settings) STATE.settings = Object.assign({}, STATE.settings, data.settings);
        STATE.locked = data.locked === true;
        applySettings();

        var badge = $('lockedBadge');
        if (badge) badge.classList.toggle('hidden', !STATE.locked);
    }

    function onToast(data) {
        Toast.show(data.kind || 'use', data.title || '', data.image || '', data.amount || 1);
        Sound.play(data.kind === 'pickup' ? 'pickup' : (data.kind === 'drop' ? 'drop' : 'use'));
    }

    /* ------------------------------------------------------------------ */
    /*  Sounds (synthesised, no audio files)                               */
    /* ------------------------------------------------------------------ */
    var Sound = {
        ctx: null,
        enabled: function () {
            return STATE.settings.Sounds !== false &&
                   (!STATE.config.sounds || STATE.config.sounds.Enabled !== false);
        },
        context: function () {
            if (this.ctx) return this.ctx;
            try {
                var Ctx = window.AudioContext || window.webkitAudioContext;
                if (!Ctx) return null;
                this.ctx = new Ctx();
            } catch (e) { this.ctx = null; }
            return this.ctx;
        },
        play: function (name) {
            if (!this.enabled()) return;
            if (STATE.settings.ReducedMotion && name === 'move') return;

            var ctx = this.context();
            if (!ctx) return;

            if (ctx.state === 'suspended') { try { ctx.resume(); } catch (e) {} }

            var volume = (STATE.config.sounds && STATE.config.sounds.Volume) || 0.35;
            var presets = {
                open:   { f: 520,  to: 880,  d: 0.14, type: 'sine' },
                close:  { f: 720,  to: 320,  d: 0.13, type: 'sine' },
                pickup: { f: 660,  to: 990,  d: 0.10, type: 'triangle' },
                drop:   { f: 420,  to: 220,  d: 0.12, type: 'triangle' },
                use:    { f: 880,  to: 1180, d: 0.09, type: 'square' },
                move:   { f: 300,  to: 340,  d: 0.05, type: 'sine' },
                error:  { f: 220,  to: 150,  d: 0.18, type: 'sawtooth' }
            };

            var p = presets[name] || presets.use;

            try {
                var osc = ctx.createOscillator();
                var gain = ctx.createGain();

                osc.type = p.type;
                osc.frequency.setValueAtTime(p.f, ctx.currentTime);
                osc.frequency.exponentialRampToValueAtTime(Math.max(40, p.to), ctx.currentTime + p.d);

                gain.gain.setValueAtTime(0.0001, ctx.currentTime);
                gain.gain.exponentialRampToValueAtTime(volume, ctx.currentTime + 0.012);
                gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + p.d);

                osc.connect(gain);
                gain.connect(ctx.destination);

                osc.start();
                osc.stop(ctx.currentTime + p.d + 0.02);
            } catch (e) { /* audio is optional */ }
        }
    };

    /* ------------------------------------------------------------------ */
    /*  Toasts                                                             */
    /* ------------------------------------------------------------------ */
    var Toast = {
        show: function (kind, title, image, amount) {
            if (!STATE.config.toasts || STATE.config.toasts.Enabled === false) return;

            var container = $('toasts');
            if (!container) return;

            var max = (STATE.config.toasts && STATE.config.toasts.Max) || 4;
            while (container.children.length >= max) container.removeChild(container.firstChild);

            var node = el('div', 'toast ' + kind);

            var icon = el('div', 't-icon');
            if (image) {
                icon.appendChild(iconImage({ name: title, label: title, rarity: 'common' }));
            }
            node.appendChild(icon);

            var body = el('div', 't-body');
            var titleNode = el('div', 't-title');
            titleNode.textContent = title;
            body.appendChild(titleNode);

            var sub = el('div', 't-sub');
            var verbs = { pickup: t('pickUp'), drop: t('dropped'), use: t('used'), equip: t('equipped') };
            sub.textContent = (verbs[kind] || kind) + (amount > 1 ? ('  x' + amount) : '');
            body.appendChild(sub);

            node.appendChild(body);
            container.appendChild(node);

            var life = (STATE.config.toasts && STATE.config.toasts.Duration) || 2600;

            window.setTimeout(function () {
                node.classList.add('out');
                window.setTimeout(function () {
                    if (node.parentNode) node.parentNode.removeChild(node);
                }, 220);
            }, life);
        }
    };

    /* ------------------------------------------------------------------ */
    /*  Drag & drop                                                        */
    /* ------------------------------------------------------------------ */
    var Drag = {
        init: function () {
            document.addEventListener('mousedown', this.onDown.bind(this));
            document.addEventListener('mousemove', this.onMove.bind(this));
            document.addEventListener('mouseup', this.onUp.bind(this));
        },

        findSlot: function (target) {
            var node = target;
            while (node && node !== document.body) {
                if (node.classList && node.classList.contains('slot')) return node;
                node = node.parentNode;
            }
            return null;
        },

        onDown: function (e) {
            if (e.button !== 0) return;

            var slot = this.findSlot(e.target);
            if (!slot) return;

            var inv = slot.dataset.inv;
            var index = parseInt(slot.dataset.slot, 10);
            var items = (inv === 'player') ? STATE.inventory : (STATE.other ? STATE.other.inventory : []);
            var item = items[index];

            if (!item || !item.name) return;

            STATE.drag = {
                from: inv,
                fromSlot: index,
                item: item,
                started: false,
                startX: e.clientX,
                startY: e.clientY,
                node: slot
            };
        },

        onMove: function (e) {
            var d = STATE.drag;
            if (!d) return;

            if (!d.started) {
                var dx = e.clientX - d.startX;
                var dy = e.clientY - d.startY;
                if (Math.sqrt(dx * dx + dy * dy) < 5) return;

                d.started = true;
                d.node.classList.add('dragging');

                var ghost = $('dragGhost');
                if (ghost) {
                    var img = $('dragGhostImg');
                    if (img) {
                        img.src = imagePath(d.item);
                        img.onerror = function () {
                            if (img.dataset.fallbackApplied) return;
                            img.dataset.fallbackApplied = '1';
                            img.onerror = null;
                            img.src = fallbackIcon(d.item);
                        };
                        img.style.display = '';
                    }
                    $('dragGhostAmount').textContent = (Number(d.item.amount) > 1) ? ('x' + d.item.amount) : '';
                    ghost.classList.remove('hidden');
                }
            }

            var ghost = $('dragGhost');
            if (ghost) {
                ghost.style.left = e.clientX + 'px';
                ghost.style.top = e.clientY + 'px';
            }

            document.querySelectorAll('.slot.drop-target').forEach(function (n) {
                n.classList.remove('drop-target');
            });

            var over = this.findSlot(e.target);
            if (over) over.classList.add('drop-target');
        },

        onUp: function (e) {
            var d = STATE.drag;
            STATE.drag = null;

            var ghost = $('dragGhost');
            if (ghost) ghost.classList.add('hidden');

            document.querySelectorAll('.slot.drop-target').forEach(function (n) {
                n.classList.remove('drop-target');
            });

            if (!d || !d.started) {
                if (d) d.node.classList.remove('dragging');
                return;
            }

            d.node.classList.remove('dragging');

            var target = this.findSlot(e.target);
            if (!target || target === d.node) return;

            var toInv = target.dataset.inv;
            var toSlot = parseInt(target.dataset.slot, 10);

            // The browser fires a click right after mouseup. Without this the
            // click handler would run a SECOND action on the same slot.
            STATE.suppressClick = true;
            window.setTimeout(function () { STATE.suppressClick = false; }, 60);

            this.move(d.from, d.fromSlot, toInv, toSlot, Number(d.item.amount) || 1);
        },

        move: function (fromInv, fromSlot, toInv, toSlot, amount) {
            var fromName = (fromInv === 'player') ? 'player' : (STATE.other ? STATE.other.name : 'player');
            var toName = (toInv === 'player') ? 'player' : (STATE.other ? STATE.other.name : 'player');

            Sound.play('move');

            if (PREVIEW) {
                // Local preview: move the item inside the mock data.
                var src = (fromInv === 'player') ? STATE.inventory : (STATE.other ? STATE.other.inventory : []);
                var dst = (toInv === 'player') ? STATE.inventory : (STATE.other ? STATE.other.inventory : []);
                var item = src[fromSlot];
                var target = dst[toSlot];

                if (target && target.name === item.name && !target.unique) {
                    target.amount = (Number(target.amount) || 0) + (Number(item.amount) || 1);
                    src[fromSlot] = null;
                } else if (target) {
                    src[fromSlot] = target;
                    dst[toSlot] = item;
                } else {
                    src[fromSlot] = null;
                    dst[toSlot] = item;
                }

                if (dst[toSlot]) dst[toSlot].slot = toSlot;
                renderAll();
                return;
            }

            nui('SetInventoryData', {
                fromInventory: fromName,
                toInventory: toName,
                fromSlot: fromSlot,
                toSlot: toSlot,
                fromAmount: amount,
                toAmount: amount
            });
        }
    };

    /* ------------------------------------------------------------------ */
    /*  Context menu                                                       */
    /* ------------------------------------------------------------------ */
    function hideContextMenu() {
        var menu = $('contextMenu');
        if (menu) menu.classList.add('hidden');
        STATE.context = null;
    }

    function showContextMenu(x, y, invName, slotIndex, item) {
        var menu = $('contextMenu');
        if (!menu) return;

        STATE.context = { inv: invName, slot: slotIndex, item: item };

        $('cmHead').textContent = item.label || item.name;

        var list = $('cmItems');
        list.innerHTML = '';

        function add(label, cls, handler) {
            var btn = el('button', 'cm-item ' + (cls || ''));
            btn.textContent = label;
            btn.addEventListener('click', function () {
                hideContextMenu();
                handler();
            });
            list.appendChild(btn);
        }

        var isShop = STATE.other && STATE.other.type === 'shop' && invName !== 'player';

        if (isShop) {
            add(t('use') + ' (buy)', '', function () {
                Quantity.ask(t('amount'), 1, 100, function (amount) { buy(item, amount); });
            });
        } else {
            if (item.useable) add(t('use'), '', function () { useItem(invName, slotIndex); });

            if (invName === 'player') {
                add(t('give'), '', function () { giveItem(slotIndex); });
                add(t('drop'), 'danger', function () {
                    Quantity.ask(t('dropQuestion'), 1, Number(item.amount) || 1, function (amount) {
                        nui('DropItem', { slot: slotIndex, amount: amount, item: item.name });
                        Sound.play('drop');
                        if (PREVIEW) { STATE.inventory[slotIndex] = null; renderAll(); }
                    });
                });
            }

            if ((Number(item.amount) || 1) > 1) {
                add(t('split'), '', function () {
                    Quantity.ask(t('splitQuestion'), 1, (Number(item.amount) || 1) - 1, function (amount) {
                        var free = firstFreeSlot(invName);
                        if (!free) return;
                        Drag.move(invName, slotIndex, invName, free, amount);
                    });
                });
            }
        }

        list.appendChild(el('div', 'cm-sep'));
        add(t('close'), '', function () {});

        menu.classList.remove('hidden');

        var rect = menu.getBoundingClientRect();
        var left = Math.min(x, window.innerWidth - rect.width - 8);
        var top = Math.min(y, window.innerHeight - rect.height - 8);

        menu.style.left = Math.max(8, left) + 'px';
        menu.style.top = Math.max(8, top) + 'px';
    }

    function firstFreeSlot(invName) {
        var items = (invName === 'player') ? STATE.inventory : (STATE.other ? STATE.other.inventory : []);
        var limit = (invName === 'player') ? (STATE.maxSlots || 40) : (STATE.other ? (STATE.other.slots || 50) : 50);
        for (var i = 1; i <= limit; i++) { if (!items[i]) return i; }
        return null;
    }

    function useItem(invName, slotIndex) {
        nui('UseItem', { slot: slotIndex, name: STATE.inventory[slotIndex] ? STATE.inventory[slotIndex].name : '' });
        Sound.play('use');
    }

    function buy(item, amount) {
        nui('AttemptPurchase', { item: item, amount: amount, shop: STATE.other.name })
            .then(function (res) {
                if (res && res.ok) Sound.play('pickup');
                else Sound.play('error');
            });
    }

    function giveItem(slotIndex) {
        if (PREVIEW) { Toast.show('error', t('noPlayersNearby'), '', 1); return; }

        nui('GetNearbyPlayers', {}).then(function (players) {
            if (!players || !players.length) {
                Toast.show('error', t('noPlayersNearby'), '', 1);
                return;
            }

            var item = STATE.inventory[slotIndex];

            Quantity.ask(t('giveQuestion'), 1, Number(item.amount) || 1, function (amount) {
                var menu = $('contextMenu');
                menu.classList.remove('hidden');
                $('cmHead').textContent = t('giveTo');
                var list = $('cmItems');
                list.innerHTML = '';

                players.forEach(function (p) {
                    var btn = el('button', 'cm-item');
                    btn.textContent = p.name + '  (' + p.distance + 'm)';
                    btn.addEventListener('click', function () {
                        hideContextMenu();
                        nui('GiveItem', {
                            target: p.id,
                            slot: slotIndex,
                            amount: amount,
                            name: item.name
                        }).then(function (res) {
                            Sound.play(res && res.ok ? 'pickup' : 'error');
                        });
                    });
                    list.appendChild(btn);
                });

                var rect = menu.getBoundingClientRect();
                menu.style.left = Math.max(8, (window.innerWidth / 2) - (rect.width / 2)) + 'px';
                menu.style.top = Math.max(8, (window.innerHeight / 2) - (rect.height / 2)) + 'px';
            });
        });
    }

    /* ------------------------------------------------------------------ */
    /*  Quantity modal                                                     */
    /* ------------------------------------------------------------------ */
    var Quantity = {
        callback: null,

        ask: function (title, min, max, cb) {
            var modal = $('quantityModal');
            if (!modal) return;

            var titleNode = modal.querySelector('.modal-title');
            if (titleNode) titleNode.textContent = title;

            var input = $('qtyInput');
            input.min = min;
            input.max = max;
            input.value = max;

            this.callback = cb;
            modal.classList.remove('hidden');
            input.focus();
            input.select();
        },

        close: function () {
            var modal = $('quantityModal');
            if (modal) modal.classList.add('hidden');
            this.callback = null;
        },

        confirm: function () {
            var input = $('qtyInput');
            var value = parseInt(input.value, 10);
            var min = parseInt(input.min, 10) || 1;
            var max = parseInt(input.max, 10) || 1;

            if (isNaN(value) || value < min) value = min;
            if (value > max) value = max;

            var cb = this.callback;
            this.close();

            if (cb) cb(value);
        }
    };

    /* ------------------------------------------------------------------ */
    /*  Settings studio                                                    */
    /* ------------------------------------------------------------------ */
    var Studio = {
        tab: 'layout',

        options: function () {
            return {
                Layout:      ['showcase', 'classic', 'grid', 'tarkov'],
                Theme:       ['glass', 'tactical', 'neon', 'minimal', 'luxe'],
                SlotStyle:   ['rounded', 'sharp', 'soft', 'outline', 'float'],
                IconShape:   ['squircle', 'square', 'circle', 'hexagon', 'diamond', 'leaf', 'shield', 'blob'],
                Font:        ['modern', 'condensed', 'mono', 'display'],
                BadgeLayout: ['stack', 'inline', 'corner', 'pill', 'minimal'],
                WeightBar:   ['bar', 'segment', 'ring', 'minimal'],
                Reveal:      ['rise', 'fade', 'scale', 'none'],
                RarityStyle: ['wash', 'outline', 'both', 'off']
            };
        },

        accents: [
            'emerald', 'cyan', 'azure', 'violet', 'magenta', 'rose', 'amber', 'lime',
            'teal', 'indigo', 'ruby', 'gold', 'mint', 'slate', 'coral', 'sky', 'plum'
        ],

        swatch: {
            emerald: '#10b981', cyan: '#06b6d4', azure: '#3b82f6', violet: '#8b5cf6',
            magenta: '#d946ef', rose: '#f43f5e', amber: '#f59e0b', lime: '#84cc16',
            teal: '#14b8a6', indigo: '#6366f1', ruby: '#e11d48', gold: '#d4a373',
            mint: '#4ade80', slate: '#94a3b8', coral: '#fb7185', sky: '#0ea5e9', plum: '#a855f7'
        },

        open: function () {
            $('settings').classList.remove('hidden');
            this.render();
        },

        close: function () {
            $('settings').classList.add('hidden');
        },

        group: function (labelKey, values, current, onPick) {
            var wrap = el('div', 'opt-group');

            var label = el('div', 'opt-label');
            label.textContent = t(labelKey);
            wrap.appendChild(label);

            var row = el('div', 'opt-row');
            values.forEach(function (value) {
                var btn = el('button', 'opt' + (value === current ? ' active' : ''));
                btn.textContent = value.charAt(0).toUpperCase() + value.slice(1);
                btn.addEventListener('click', onPick.bind(null, value));
                row.appendChild(btn);
            });

            wrap.appendChild(row);
            return wrap;
        },

        render: function () {
            var body = $('settingsBody');
            body.innerHTML = '';

            var s = STATE.settings;
            var self = this;

            function pick(key, value) {
                STATE.settings[key] = value;
                if (key === 'Layout' && value !== 'showcase') STATE.settings.PedPreview = false;
                if (key === 'Layout' && value === 'showcase') STATE.settings.PedPreview = true;
                applySettings();
                self.render();
            }

            if (this.tab === 'layout') {
                body.appendChild(this.group('layout', this.options().Layout, s.Layout, function (v) { pick('Layout', v); }));

                var pedRow = this.switch('pedPreview', s.PedPreview, function (v) {
                    STATE.settings.PedPreview = v;
                    applySettings();
                    self.render();
                });
                body.appendChild(pedRow);
            }

            if (this.tab === 'theme') {
                body.appendChild(this.group('theme', this.options().Theme, s.Theme, function (v) { pick('Theme', v); }));

                var accentGroup = el('div', 'opt-group');
                var accentLabel = el('div', 'opt-label');
                accentLabel.textContent = t('accent');
                accentGroup.appendChild(accentLabel);

                var accentRow = el('div', 'opt-row');
                this.accents.forEach(function (name) {
                    var btn = el('button', 'opt swatch' + (name === s.Accent && !s.CustomAccent ? ' active' : ''));
                    btn.style.background = self.swatch[name];
                    btn.title = name;
                    btn.addEventListener('click', function () {
                        STATE.settings.Accent = name;
                        STATE.settings.CustomAccent = '';
                        applySettings();
                        self.render();
                    });
                    accentRow.appendChild(btn);
                });
                accentGroup.appendChild(accentRow);
                body.appendChild(accentGroup);

                var colorRow = el('div', 'opt-group');
                var colorLabel = el('div', 'opt-label');
                colorLabel.textContent = t('customColor');
                colorRow.appendChild(colorLabel);

                var picker = el('div', 'color-row');
                var input = el('input');
                input.type = 'color';
                input.value = s.CustomAccent || this.swatch[s.Accent] || '#10b981';
                input.addEventListener('input', function () {
                    STATE.settings.CustomAccent = input.value;
                    applySettings();
                });
                picker.appendChild(input);

                var clear = el('button', 'btn ghost');
                clear.textContent = t('reset');
                clear.addEventListener('click', function () {
                    STATE.settings.CustomAccent = '';
                    applySettings();
                    self.render();
                });
                picker.appendChild(clear);

                colorRow.appendChild(picker);
                body.appendChild(colorRow);
            }

            if (this.tab === 'slots') {
                ['SlotStyle', 'IconShape', 'Font', 'BadgeLayout', 'WeightBar'].forEach(function (key) {
                    var labelKey = key.charAt(0).toLowerCase() + key.slice(1);
                    body.appendChild(self.group(labelKey, self.options()[key], s[key], function (v) { pick(key, v); }));
                });
            }

            if (this.tab === 'rarity') {
                body.appendChild(this.group('rarityStyle', this.options().RarityStyle, s.RarityStyle, function (v) { pick('RarityStyle', v); }));
            }

            if (this.tab === 'motion') {
                body.appendChild(this.group('reveal', this.options().Reveal, s.Reveal, function (v) { pick('Reveal', v); }));
                body.appendChild(this.switch('animations', s.Animations, function (v) { STATE.settings.Animations = v; applySettings(); self.render(); }));
                body.appendChild(this.switch('reducedMotion', s.ReducedMotion, function (v) { STATE.settings.ReducedMotion = v; applySettings(); self.render(); }));
                body.appendChild(this.switch('sounds', s.Sounds, function (v) { STATE.settings.Sounds = v; applySettings(); self.render(); }));
                body.appendChild(this.switch('cursorTrail', s.CursorTrail, function (v) { STATE.settings.CursorTrail = v; applySettings(); self.render(); }));
                body.appendChild(this.group('language', window.LOCALE_ORDER, s.Language, function (v) { pick('Language', v); }));
            }

            if (this.tab === 'texts') {
                var hint = el('div', 'opt-label');
                hint.textContent = t('textEditorHint');
                body.appendChild(hint);

                var editor = el('div', 'text-editor');
                var keys = Object.keys(window.LOCALES.en || {});

                keys.forEach(function (key) {
                    var row = el('div', 'te-row');

                    var label = el('label');
                    label.textContent = key;
                    row.appendChild(label);

                    var input = el('input');
                    input.type = 'text';
                    input.value = (STATE.texts[key] !== undefined) ? STATE.texts[key] : (window.LOCALES[lang()] || {})[key] || '';
                    input.addEventListener('input', function () {
                        STATE.texts[key] = input.value;
                        applyTranslations();
                    });
                    row.appendChild(input);

                    var hide = el('button', 'te-hide' + (STATE.hidden[key] ? ' on' : ''));
                    hide.textContent = t('hideText');
                    hide.addEventListener('click', function () {
                        STATE.hidden[key] = !STATE.hidden[key];
                        hide.classList.toggle('on', !!STATE.hidden[key]);
                        applyTranslations();
                    });
                    row.appendChild(hide);

                    editor.appendChild(row);
                });

                body.appendChild(editor);
            }

            if (this.tab === 'admin') {
                var hint2 = el('div', 'opt-label');
                hint2.textContent = t('adminPushHint');
                body.appendChild(hint2);

                var push = el('button', 'btn primary');
                push.textContent = t('adminPush');
                push.addEventListener('click', function () {
                    nui('AdminPush', { settings: STATE.settings, texts: STATE.texts, hidden: STATE.hidden })
                        .then(function () { Toast.show('use', t('pushed'), '', 1); });
                });
                body.appendChild(push);
            }
        },

        switch: function (labelKey, value, onChange) {
            var row = el('div', 'switch-row');
            var span = el('span');
            span.textContent = t(labelKey);
            row.appendChild(span);

            var btn = el('button', 'switch' + (value ? ' on' : ''));
            btn.addEventListener('click', function () {
                btn.classList.toggle('on');
                onChange(btn.classList.contains('on'));
            });
            row.appendChild(btn);

            return row;
        }
    };

    /* ------------------------------------------------------------------ */
    /*  Cursor trail                                                       */
    /* ------------------------------------------------------------------ */
    var Trail = {
        parts: [],
        canvas: null,
        ctx: null,

        init: function () {
            this.canvas = $('cursorTrail');
            if (!this.canvas) return;

            this.ctx = this.canvas.getContext('2d');
            this.resize();

            window.addEventListener('resize', this.resize.bind(this));
            window.addEventListener('mousemove', this.push.bind(this));

            this.loop();
        },

        resize: function () {
            if (!this.canvas) return;
            this.canvas.width = window.innerWidth;
            this.canvas.height = window.innerHeight;
        },

        push: function (e) {
            if (!STATE.settings.CursorTrail || STATE.settings.ReducedMotion) return;

            this.parts.push({ x: e.clientX, y: e.clientY, life: 1 });
            if (this.parts.length > 40) this.parts.shift();
        },

        loop: function () {
            var self = this;
            window.requestAnimationFrame(function () { self.loop(); });

            if (!this.ctx) return;

            this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
            if (!STATE.settings.CursorTrail || STATE.settings.ReducedMotion) return;

            if (!this.accent) {
                this.accent = getComputedStyle(document.body).getPropertyValue('--accent').trim() || '#10b981';
            }
            var accent = this.accent;

            for (var i = this.parts.length - 1; i >= 0; i--) {
                var p = this.parts[i];
                p.life -= 0.035;

                if (p.life <= 0) { this.parts.splice(i, 1); continue; }

                this.ctx.globalAlpha = Math.max(0, p.life) * 0.5;
                this.ctx.fillStyle = accent;
                this.ctx.beginPath();
                this.ctx.arc(p.x, p.y, 4 * p.life, 0, Math.PI * 2);
                this.ctx.fill();
            }

            this.ctx.globalAlpha = 1;
        }
    };

    /* ------------------------------------------------------------------ */
    /*  Wiring                                                             */
    /* ------------------------------------------------------------------ */
    function wire() {
        Drag.init();
        Trail.init();

        // Right click on a filled slot opens the context menu.
        document.addEventListener('contextmenu', function (e) {
            e.preventDefault();

            var slot = Drag.findSlot(e.target);
            if (!slot) return;

            var inv = slot.dataset.inv;
            var index = parseInt(slot.dataset.slot, 10);
            var items = (inv === 'player') ? STATE.inventory : (STATE.other ? STATE.other.inventory : []);
            var item = items[index];

            if (!item || !item.name) return;

            showContextMenu(e.clientX, e.clientY, inv, index, item);
        });

        document.addEventListener('mousedown', function (e) {
            var menu = $('contextMenu');
            if (menu && !menu.classList.contains('hidden') && !menu.contains(e.target)) {
                hideContextMenu();
            }
        });

        // Left click on a slot: use (player) or take/buy (other inventory).
        document.addEventListener('click', function (e) {
            if (STATE.suppressClick) { STATE.suppressClick = false; return; }

            var slot = Drag.findSlot(e.target);
            if (!slot || STATE.drag) return;

            var inv = slot.dataset.inv;
            var index = parseInt(slot.dataset.slot, 10);
            var items = (inv === 'player') ? STATE.inventory : (STATE.other ? STATE.other.inventory : []);
            var item = items[index];

            if (!item || !item.name) return;

            if (inv === 'player') { return; }

            var isShop = STATE.other && STATE.other.type === 'shop';

            if (isShop) {
                Quantity.ask(t('amount'), 1, 100, function (amount) { buy(item, amount); });
            } else {
                var free = firstFreeSlot('player');
                if (!free) { Sound.play('error'); return; }
                Drag.move(STATE.other.name, index, 'player', free, Number(item.amount) || 1);
            }
        });

        // Double click on a player slot uses the item.
        document.addEventListener('dblclick', function (e) {
            var slot = Drag.findSlot(e.target);
            if (!slot) return;

            var inv = slot.dataset.inv;
            var index = parseInt(slot.dataset.slot, 10);
            var items = (inv === 'player') ? STATE.inventory : (STATE.other ? STATE.other.inventory : []);
            var item = items[index];

            if (!item || !item.name) return;

            if (inv === 'player') useItem('player', index);
        });

        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') {
                hideContextMenu();

                var modal = $('quantityModal');
                if (modal && !modal.classList.contains('hidden')) { Quantity.close(); return; }

                var settings = $('settings');
                if (settings && !settings.classList.contains('hidden')) { Studio.close(); return; }

                if (STATE.open) nui('CloseInventory', {});
            }
        });

        var search = $('search');
        if (search) {
            search.addEventListener('input', function () {
                STATE.search = search.value.trim();
                renderAll();
            });
        }

        var clear = $('searchClear');
        if (clear) {
            clear.addEventListener('click', function () {
                search.value = '';
                STATE.search = '';
                renderAll();
                search.focus();
            });
        }

        document.querySelectorAll('.layout-btn').forEach(function (btn) {
            btn.addEventListener('click', function () {
                STATE.settings.Layout = btn.dataset.layout;
                STATE.settings.PedPreview = (btn.dataset.layout === 'showcase');
                applySettings();
                saveSettings();
            });
        });

        $('btnSettings').addEventListener('click', function () { Studio.open(); });
        $('settingsClose').addEventListener('click', function () { Studio.close(); });
        $('btnClose').addEventListener('click', function () { nui('CloseInventory', {}); });

        $('settingsSave').addEventListener('click', function () {
            saveSettings();
            Studio.close();
            Toast.show('use', t('saved'), '', 1);
        });

        $('settingsReset').addEventListener('click', function () {
            STATE.settings = Object.assign({}, STATE.defaults);
            STATE.texts = {};
            STATE.hidden = {};
            applySettings();
            saveSettings();
            nui('ResetSettings', {});
            Studio.render();
            Toast.show('use', t('settingsReset'), '', 1);
        });

        document.querySelectorAll('.stab').forEach(function (tab) {
            tab.addEventListener('click', function () {
                document.querySelectorAll('.stab').forEach(function (n) { n.classList.remove('active'); });
                tab.classList.add('active');
                Studio.tab = tab.dataset.tab;
                Studio.render();
            });
        });

        $('qtyCancel').addEventListener('click', function () { Quantity.close(); });
        $('qtyConfirm').addEventListener('click', function () { Quantity.confirm(); });

        document.querySelectorAll('.qty-btn').forEach(function (btn) {
            btn.addEventListener('click', function () {
                var input = $('qtyInput');
                if (btn.dataset.qty === 'min') input.value = input.min;
                if (btn.dataset.qty === 'max') input.value = input.max;
            });
        });

        $('qtyInput').addEventListener('keydown', function (e) {
            if (e.key === 'Enter') Quantity.confirm();
        });
    }

    /* ------------------------------------------------------------------ */
    /*  Browser preview (mock data) - only with ?preview=1                 */
    /* ------------------------------------------------------------------ */
    var MOCK = {
        player: {
            name: 'Alex Novak', firstname: 'Alex', lastname: 'Novak',
            citizenid: 'XKR48291', job: 'Police Officer', cash: 48250, bank: 1284000, serverId: 12
        },
        inventory: [],
        other: {
            name: 'stash-apartment-12',
            label: 'Apartment 12 - Wardrobe',
            type: 'stash',
            slots: 20,
            maxweight: 200000,
            inventory: []
        }
    };

    function mockItems() {
        var items = [
            { name: 'weapon_pistol',  label: 'Pistol',        amount: 1,  type: 'weapon', image: 'weapon_pistol.png',  weight: 1500, rarity: 'rare',      unique: true, useable: true, info: { quality: 87, serie: 'PZ9281' } },
            { name: 'phone',          label: 'Phone',          amount: 1,  image: 'phone.png',          weight: 300,  rarity: 'common',    useable: true, info: {} },
            { name: 'lockpick',       label: 'Lockpick',       amount: 12, image: 'lockpick.png',       weight: 100,  rarity: 'uncommon',  useable: true, info: {} },
            { name: 'water_bottle',   label: 'Water Bottle',   amount: 6,  image: 'water_bottle.png',   weight: 500,  rarity: 'common',    useable: true, info: {} },
            { name: 'sandwich',       label: 'Sandwich',       amount: 3,  image: 'sandwich.png',       weight: 400,  rarity: 'common',    useable: true, info: {} },
            { name: 'id_card',        label: 'ID Card',        amount: 1,  image: 'id_card.png',        weight: 100,  rarity: 'common',    useable: true, info: {} },
            { name: 'money',          label: 'Cash',           amount: 4200, image: 'money.png',        weight: 0,    rarity: 'uncommon',  info: {} },
            { name: 'bandage',        label: 'Bandage',        amount: 8,  image: 'bandage.png',        weight: 200,  rarity: 'common',    useable: true, info: {} },
            { name: 'weapon_knife',   label: 'Knife',          amount: 1,  type: 'weapon', image: 'weapon_knife.png',   weight: 600,  rarity: 'uncommon',  unique: true, useable: true, info: { quality: 100 } },
            { name: 'goldbar',        label: 'Gold Bar',       amount: 2,  image: 'goldbar.png',        weight: 5000, rarity: 'legendary', info: {} },
            { name: 'markedbills',    label: 'Marked Bills',   amount: 1,  image: 'markedbills.png',    weight: 100,  rarity: 'epic',      info: { worth: 42000 } },
            { name: 'radio',          label: 'Radio',          amount: 1,  image: 'radio.png',          weight: 800,  rarity: 'rare',      useable: true, info: {} },
            { name: 'armor',          label: 'Body Armor',     amount: 1,  image: 'armor.png',          weight: 4000, rarity: 'epic',      useable: true, info: {} },
            { name: 'repairkit',      label: 'Repair Kit',     amount: 4,  image: 'repairkit.png',      weight: 1500, rarity: 'rare',      useable: true, info: {} },
            { name: 'keychain',       label: 'Keychain',       amount: 1,  image: 'keychain.png',       weight: 100,  rarity: 'common',    info: {} },
            { name: 'oxy',            label: 'Oxygen Tank',    amount: 2,  image: 'oxy.png',            weight: 1200, rarity: 'uncommon',  useable: true, info: {} },
            { name: 'joint',          label: 'Joint',          amount: 14, image: 'joint.png',          weight: 50,   rarity: 'common',    useable: true, info: {} },
            { name: 'driver_license', label: 'Drivers License',amount: 1,  image: 'driver_license.png', weight: 100,  rarity: 'common',    useable: true, info: {} }
        ];

        var map = [];
        items.forEach(function (item, i) {
            item.slot = i + 1;
            map[i + 1] = item;
        });
        return map;
    }

    function bootPreview() {
        document.body.classList.add('preview');

        STATE.config = {
            brand: { Text: 'CodeX Roleplay', SubText: 'Inventory', Logo: '', ShowPlayerChip: true },
            maxSlots: 40, maxWeight: 120000, hotbarSlots: 5,
            images: { Path: 'images/', Extension: '.png', Fallback: true },
            rarity: { Enabled: true, Default: 'common' },
            sounds: { Enabled: true, Volume: 0.35 },
            toasts: { Enabled: true, Duration: 2600, Max: 4 },
            permissions: { SettingsStudio: true },
            drops: { Enabled: true },
            locale: 'en'
        };

        STATE.defaults = defaults();
        STATE.player = MOCK.player;
        STATE.maxSlots = 40;
        STATE.maxWeight = 120000;

        loadSettings();
        applySettings();

        var items = mockItems();
        STATE.inventory = items;

        MOCK.other.inventory = [];
        MOCK.other.inventory[1] = { name: 'goldbar', label: 'Gold Bar', amount: 3, image: 'goldbar.png', weight: 5000, rarity: 'legendary', slot: 1, info: {} };
        MOCK.other.inventory[2] = { name: 'weapon_pistol', label: 'Pistol', amount: 1, type: 'weapon', image: 'weapon_pistol.png', weight: 1500, rarity: 'rare', slot: 2, unique: true, useable: true, info: { quality: 62 } };
        MOCK.other.inventory[3] = { name: 'money', label: 'Cash', amount: 15000, image: 'money.png', weight: 0, rarity: 'uncommon', slot: 3, info: {} };
        MOCK.other.inventory[7] = { name: 'armor', label: 'Body Armor', amount: 2, image: 'armor.png', weight: 4000, rarity: 'epic', slot: 7, useable: true, info: {} };
        STATE.other = MOCK.other;

        STATE.open = true;
        $('app').classList.remove('hidden');
        $('previewNote').classList.remove('hidden');
        $('previewNote').textContent = t('previewNote');

        renderAll();
    }

    /* ------------------------------------------------------------------ */
    /*  Boot                                                               */
    /* ------------------------------------------------------------------ */
    if (PREVIEW) {
        wire();
        bootPreview();
    } else {
        STATE.defaults = defaults();
        loadSettings();
        wire();
        // In game the Lua side sends `setup` as soon as the resource starts.
    }
})();
