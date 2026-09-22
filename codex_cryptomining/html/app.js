/*
 * CodeX CryptoMining - NUI controller.
 * Pure vanilla JS, no external dependency, so it works offline on any server.
 */
(function () {
    'use strict';

    var RESOURCE = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName()
        : 'codex_cryptomining';

    var state = {
        warehouse: null,
        market: null,
        shop: null,
        broker: null,
        selectedRig: null,
        view: null,
        busy: false
    };

    // ---------------------------------------------------------------- helpers
    function $(selector) {
        return document.querySelector(selector);
    }

    function $all(selector) {
        return Array.prototype.slice.call(document.querySelectorAll(selector));
    }

    function money(value) {
        var number = Number(value) || 0;
        var sign = number < 0 ? '-' : '';
        return sign + '$' + Math.abs(Math.round(number)).toLocaleString('en-US');
    }

    function btc(value) {
        return (Number(value) || 0).toFixed(6);
    }

    function hash(value) {
        var number = Number(value) || 0;
        if (number >= 1000) {
            return (number / 1000).toFixed(2) + ' GH/s';
        }
        return number.toFixed(1) + ' MH/s';
    }

    function text(selector, value) {
        var element = $(selector);
        if (element) {
            element.textContent = value;
        }
    }

    function post(endpoint, payload) {
        return fetch('https://' + RESOURCE + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload || {})
        }).then(function (response) {
            return response.json();
        }).catch(function () {
            return { ok: false };
        });
    }

    // ------------------------------------------------------------ visibility
    function showView(view) {
        state.view = view;

        $('#app').classList.toggle('hidden', view === null);
        $('#panel').classList.toggle('hidden', view !== 'panel');
        $('#shop').classList.toggle('hidden', view !== 'shop');
        $('#broker').classList.toggle('hidden', view !== 'broker');
    }

    function close() {
        showView(null);
        state.selectedRig = null;
        post('close', {});
    }

    // --------------------------------------------------------------- panel UI
    function renderMarket(market) {
        if (!market) {
            return;
        }

        state.market = market;

        text('#ticker-price', money(market.price));
        text('#market-price', money(market.price));
        text('#market-fee', ((Number(market.fee) || 0) * 100).toFixed(1) + '%');

        var trend = Number(market.trend) || 0;
        var label = (trend > 0 ? '+' : '') + trend.toFixed(2) + '%';

        var tickerTrend = $('#ticker-trend');
        var marketTrend = $('#market-trend');

        [tickerTrend, marketTrend].forEach(function (element) {
            if (!element) {
                return;
            }
            element.textContent = label;
            element.classList.remove('up', 'down');
            element.classList.add(trend >= 0 ? 'up' : 'down');
        });

        drawChart(market.history || []);
    }

    function drawChart(history) {
        var canvas = $('#market-chart');
        if (!canvas || !canvas.getContext) {
            return;
        }

        var ctx = canvas.getContext('2d');
        var width = canvas.width;
        var height = canvas.height;

        ctx.clearRect(0, 0, width, height);

        var points = (history || []).map(Number).filter(function (value) {
            return isFinite(value);
        });

        if (points.length < 2) {
            ctx.fillStyle = '#8a99ad';
            ctx.font = '13px Segoe UI, sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('Not enough data yet', width / 2, height / 2);
            return;
        }

        var min = Math.min.apply(null, points);
        var max = Math.max.apply(null, points);
        var range = (max - min) || 1;
        var padding = 24;
        var stepX = (width - padding * 2) / (points.length - 1);

        function pointY(value) {
            return height - padding - ((value - min) / range) * (height - padding * 2);
        }

        // Grid
        ctx.strokeStyle = 'rgba(255,255,255,0.06)';
        ctx.lineWidth = 1;
        for (var line = 0; line <= 4; line += 1) {
            var y = padding + ((height - padding * 2) / 4) * line;
            ctx.beginPath();
            ctx.moveTo(padding, y);
            ctx.lineTo(width - padding, y);
            ctx.stroke();
        }

        // Area
        var gradient = ctx.createLinearGradient(0, padding, 0, height - padding);
        gradient.addColorStop(0, 'rgba(247,147,26,0.35)');
        gradient.addColorStop(1, 'rgba(247,147,26,0)');

        ctx.beginPath();
        ctx.moveTo(padding, height - padding);
        points.forEach(function (value, index) {
            ctx.lineTo(padding + stepX * index, pointY(value));
        });
        ctx.lineTo(padding + stepX * (points.length - 1), height - padding);
        ctx.closePath();
        ctx.fillStyle = gradient;
        ctx.fill();

        // Line
        ctx.beginPath();
        points.forEach(function (value, index) {
            var x = padding + stepX * index;
            var y = pointY(value);
            if (index === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        });
        ctx.strokeStyle = '#f7931a';
        ctx.lineWidth = 2;
        ctx.stroke();

        // Last point
        var lastX = padding + stepX * (points.length - 1);
        var lastY = pointY(points[points.length - 1]);
        ctx.beginPath();
        ctx.arc(lastX, lastY, 4, 0, Math.PI * 2);
        ctx.fillStyle = '#f7931a';
        ctx.fill();

        // Bounds
        ctx.fillStyle = '#8a99ad';
        ctx.font = '11px Segoe UI, sans-serif';
        ctx.textAlign = 'left';
        ctx.fillText(money(max), padding, padding - 8);
        ctx.fillText(money(min), padding, height - 6);
    }

    function rigCard(rig, warehouse) {
        var maxGpus = Number(warehouse.maxGpus) || 8;
        var durability = Number(rig.durability) || 0;
        var isMining = !rig.broken && rig.gpus > 0 && warehouse.powered;

        var badge = rig.broken
            ? '<span class="badge bad">Broken</span>'
            : (isMining ? '<span class="badge ok">Mining</span>' : '<span class="badge idle">Idle</span>');

        var card = document.createElement('div');
        card.className = 'rig' + (rig.broken ? ' broken' : '') + (state.selectedRig === rig.id ? ' selected' : '');
        card.dataset.rigId = String(rig.id);

        card.innerHTML =
            '<div class="rig-head">' +
                '<span class="rig-name">Rig #' + rig.slot + '</span>' + badge +
            '</div>' +
            '<div class="rig-stats">' +
                '<div><span>GPU</span><strong>' + rig.gpus + '/' + maxGpus + '</strong></div>' +
                '<div><span>Hash</span><strong>' + hash(rig.hashrate) + '</strong></div>' +
                '<div><span>CPU</span><strong>Lv ' + rig.cpu + '</strong></div>' +
                '<div><span>Cooler</span><strong>Lv ' + rig.cooler + '</strong></div>' +
            '</div>' +
            '<div class="bar' + (durability < 35 ? ' low' : '') + '"><div style="width:' + Math.max(0, Math.min(100, durability)) + '%"></div></div>' +
            '<div class="rig-actions">' +
                '<button class="btn small" data-rig-action="installGpu">+ GPU</button>' +
                '<button class="btn small" data-rig-action="removeGpu">- GPU</button>' +
                '<button class="btn small" data-rig-action="repairRig">Repair</button>' +
                '<button class="btn small" data-rig-action="upgradeCpu">CPU</button>' +
                '<button class="btn small" data-rig-action="upgradeCooler">Cooler</button>' +
                '<button class="btn small danger" data-rig-action="removeRig">Remove</button>' +
            '</div>';

        return card;
    }

    function renderRigs(warehouse) {
        var grid = $('#rig-grid');
        if (!grid) {
            return;
        }

        grid.innerHTML = '';

        var rigs = warehouse.rigs || [];

        if (rigs.length === 0) {
            grid.innerHTML = '<div class="empty">No mining rig installed yet. Buy one to start producing bitcoins.</div>';
            return;
        }

        rigs.forEach(function (rig) {
            grid.appendChild(rigCard(rig, warehouse));
        });
    }

    function renderKeys(warehouse) {
        var list = $('#key-list');
        if (!list) {
            return;
        }

        list.innerHTML = '';

        var keys = warehouse.keys || [];

        if (keys.length === 0) {
            list.innerHTML = '<div class="empty">Nobody else has the keys.</div>';
            return;
        }

        keys.forEach(function (entry) {
            var row = document.createElement('div');
            row.className = 'key-row';
            row.innerHTML = '<span>' + escapeHtml(entry.name || 'Unknown') + '</span>' +
                '<button class="btn small danger" data-remove-key="' + escapeHtml(entry.identifier) + '">Remove</button>';
            list.appendChild(row);
        });
    }

    function escapeHtml(value) {
        return String(value === undefined || value === null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function renderPanel(warehouse) {
        if (!warehouse) {
            return;
        }

        state.warehouse = warehouse;

        text('#panel-subtitle', warehouse.label || '');
        text('#stat-btc', btc(warehouse.btc));
        text('#stat-btc-value', money(warehouse.value));
        text('#stat-hash', hash(warehouse.hashrate));
        text('#stat-perhour', btc(warehouse.perHour) + ' BTC/h');

        var rigs = warehouse.rigs || [];
        var gpus = rigs.reduce(function (total, rig) {
            return total + (Number(rig.gpus) || 0);
        }, 0);

        text('#stat-rigs', rigs.length + ' / ' + warehouse.maxRigs);
        text('#stat-gpus', gpus + ' GPU');
        text('#stat-load', (Number(warehouse.load) || 0).toFixed(2) + ' kW');
        text('#stat-power', warehouse.powered ? 'Online' : 'Power cut');

        text('#info-owner', warehouse.ownerName || '-');
        text('#info-type', warehouse.type === 'large' ? 'Large facility' : 'Small facility');
        text('#info-storage', Number(warehouse.storageLimit) > 0 ? btc(warehouse.storageLimit) + ' BTC' : 'Unlimited');
        text('#info-mined', btc(warehouse.totalMined) + ' BTC');
        text('#info-earned', money(warehouse.totalEarned));
        text('#info-bill', money(warehouse.bill));

        text('#power-status', warehouse.powered ? 'Online' : 'Power cut');
        text('#power-load', (Number(warehouse.load) || 0).toFixed(2) + ' kW');
        text('#power-bill', money(warehouse.bill));

        text('#sell-preview', 'Available: ' + btc(warehouse.btc) + ' BTC  ·  ' + money(warehouse.value) + ' after fees');

        renderRigs(warehouse);
        renderKeys(warehouse);
        renderMarket(warehouse.market || state.market);

        // Owner only controls.
        $all('[data-action="installRig"], [data-action="payBill"], [data-action="togglePower"], [data-action="giveKeys"], [data-action="sellAll"], [data-action="sellAmount"]')
            .forEach(function (button) {
                button.disabled = warehouse.isOwner === false;
            });
    }

    // ---------------------------------------------------------------- actions
    function sendAction(payload) {
        if (state.busy) {
            return Promise.resolve({ ok: false });
        }

        state.busy = true;

        return post('action', payload).then(function (result) {
            state.busy = false;
            return post('refresh', {}).then(function () {
                return result;
            });
        }).catch(function () {
            state.busy = false;
            return { ok: false };
        });
    }

    function selectedRigId() {
        if (state.selectedRig) {
            return state.selectedRig;
        }

        var rigs = (state.warehouse && state.warehouse.rigs) || [];
        return rigs.length > 0 ? rigs[0].id : null;
    }

    function refreshPlayers() {
        post('nearbyPlayers', {}).then(function (result) {
            var select = $('#nearby-players');
            if (!select) {
                return;
            }

            select.innerHTML = '';
            var players = (result && result.players) || [];

            if (players.length === 0) {
                var option = document.createElement('option');
                option.value = '';
                option.textContent = 'No player nearby';
                select.appendChild(option);
                return;
            }

            players.forEach(function (player) {
                var option = document.createElement('option');
                option.value = String(player.id);
                option.textContent = player.name + ' (' + player.distance + 'm)';
                select.appendChild(option);
            });
        });
    }

    // ------------------------------------------------------------------ shop
    function renderShop(shop) {
        state.shop = shop;

        text('#shop-title', shop.shop === 'blackmarket' ? 'Black market' : 'TechShop');
        text('#shop-subtitle', shop.shop === 'blackmarket' ? 'No questions asked' : 'Hardware and upgrades');

        var list = $('#shop-list');
        list.innerHTML = '';

        (shop.entries || []).forEach(function (entry) {
            var row = document.createElement('div');
            row.className = 'shop-item';

            var sellButton = shop.canSell
                ? '<button class="btn small" data-shop-sell="' + entry.index + '">Sell ' + money(entry.sellPrice) + '</button>'
                : '';

            row.innerHTML =
                '<div>' +
                    '<h3>' + escapeHtml(entry.label) + '</h3>' +
                    '<p>' + money(entry.price) + ' · owned: ' + entry.owned + '</p>' +
                '</div>' +
                '<div class="shop-controls">' +
                    '<input type="number" min="1" max="' + (shop.maxQuantity || 10) + '" value="1" data-shop-qty="' + entry.index + '" />' +
                    '<button class="btn primary small" data-shop-buy="' + entry.index + '">Buy</button>' +
                    sellButton +
                '</div>';

            list.appendChild(row);
        });
    }

    function renderBroker(broker) {
        state.broker = broker;

        text('#broker-subtitle', 'You own ' + broker.owned + ' / ' + broker.max + ' warehouses');

        var list = $('#broker-list');
        list.innerHTML = '';

        (broker.list || []).forEach(function (entry) {
            var row = document.createElement('div');
            row.className = 'broker-item';

            var tag = entry.isMine
                ? '<span class="tag mine">Yours</span>'
                : (entry.owned ? '<span class="tag sold">Sold</span>' : '<span class="tag">Available</span>');

            var button = entry.isMine
                ? '<button class="btn small danger" data-broker-sell="' + escapeHtml(entry.id) + '">Sell ' + money(entry.sellPrice) + '</button>'
                : (entry.owned
                    ? '<button class="btn small" disabled>Unavailable</button>'
                    : '<button class="btn primary small" data-broker-buy="' + escapeHtml(entry.id) + '">Buy ' + money(entry.price) + '</button>');

            row.innerHTML =
                '<div>' +
                    '<h3>' + escapeHtml(entry.label) + ' ' + tag + '</h3>' +
                    '<p>' + escapeHtml(entry.typeLabel) + ' · up to ' + entry.maxRigs + ' rigs</p>' +
                '</div>' +
                '<div class="shop-controls">' + button + '</div>';

            list.appendChild(row);
        });
    }

    // ---------------------------------------------------------------- events
    document.addEventListener('click', function (event) {
        var target = event.target;

        if (target.closest('[data-close]')) {
            close();
            return;
        }

        var tab = target.closest('.tab');
        if (tab) {
            var name = tab.dataset.tab;
            $all('.tab').forEach(function (element) {
                element.classList.toggle('active', element === tab);
            });
            $all('.tab-page').forEach(function (page) {
                page.classList.toggle('active', page.dataset.page === name);
            });

            if (name === 'keys') {
                refreshPlayers();
            }
            if (name === 'market') {
                drawChart((state.market && state.market.history) || []);
            }
            return;
        }

        // Rig card selection.
        var card = target.closest('.rig');
        if (card && !target.closest('[data-rig-action]')) {
            state.selectedRig = Number(card.dataset.rigId);
            $all('.rig').forEach(function (element) {
                element.classList.toggle('selected', element === card);
            });
            return;
        }

        var rigAction = target.closest('[data-rig-action]');
        if (rigAction) {
            var rigCardElement = rigAction.closest('.rig');
            var rigId = rigCardElement ? Number(rigCardElement.dataset.rigId) : selectedRigId();

            if (rigId) {
                state.selectedRig = rigId;
                sendAction({ action: rigAction.dataset.rigAction, rigId: rigId, quantity: 1 });
            }
            return;
        }

        var action = target.closest('[data-action]');
        if (action) {
            var name2 = action.dataset.action;

            if (name2 === 'sellAll') {
                sendAction({ action: 'sellBtc', all: true });
            } else if (name2 === 'sellAmount') {
                var input = $('#sell-amount');
                var amount = Number(input && input.value) || 0;

                if (amount > 0) {
                    sendAction({ action: 'sellBtc', amount: amount }).then(function () {
                        if (input) {
                            input.value = '';
                        }
                    });
                }
            } else if (name2 === 'refreshPlayers') {
                refreshPlayers();
            } else if (name2 === 'giveKeys') {
                var select = $('#nearby-players');
                var targetId = Number(select && select.value) || 0;

                if (targetId > 0) {
                    sendAction({ action: 'giveKeys', target: targetId });
                }
            } else {
                sendAction({ action: name2 });
            }
            return;
        }

        var removeKey = target.closest('[data-remove-key]');
        if (removeKey) {
            sendAction({ action: 'removeKeys', identifier: removeKey.dataset.removeKey });
            return;
        }

        var buy = target.closest('[data-shop-buy]');
        if (buy) {
            var buyIndex = Number(buy.dataset.shopBuy);
            var qtyInput = document.querySelector('[data-shop-qty="' + buyIndex + '"]');
            var quantity = Math.max(1, Number(qtyInput && qtyInput.value) || 1);

            post('shopAction', {
                action: 'buy',
                shop: state.shop ? state.shop.shop : 'techshop',
                index: buyIndex,
                quantity: quantity
            });
            return;
        }

        var sell = target.closest('[data-shop-sell]');
        if (sell) {
            var sellIndex = Number(sell.dataset.shopSell);
            var sellQtyInput = document.querySelector('[data-shop-qty="' + sellIndex + '"]');
            var sellQuantity = Math.max(1, Number(sellQtyInput && sellQtyInput.value) || 1);

            post('shopAction', {
                action: 'sell',
                shop: 'techshop',
                index: sellIndex,
                quantity: sellQuantity
            });
            return;
        }

        var brokerBuy = target.closest('[data-broker-buy]');
        if (brokerBuy) {
            post('brokerAction', { action: 'buyWarehouse', warehouseId: brokerBuy.dataset.brokerBuy });
            return;
        }

        var brokerSell = target.closest('[data-broker-sell]');
        if (brokerSell) {
            post('brokerAction', { action: 'sellWarehouse', warehouseId: brokerSell.dataset.brokerSell });
        }
    });

    document.addEventListener('keyup', function (event) {
        if (event.key === 'Escape' && state.view) {
            close();
        }
    });

    // ------------------------------------------------------- built-in toast
    function notify(payload) {
        var container = $('#toasts');
        if (!container) {
            return;
        }

        var position = (payload && payload.position) || 'top-right';
        container.className = 'toasts'
            + (position.indexOf('left') !== -1 ? ' left' : '')
            + (position.indexOf('bottom') !== -1 ? ' bottom' : '');

        var type = (payload && payload.type) || 'inform';
        var duration = Number(payload && payload.duration) || 5000;

        var toast = document.createElement('div');
        toast.className = 'toast ' + type;

        var title = document.createElement('span');
        title.className = 'toast-title';
        title.textContent = (payload && payload.title) || 'Crypto Mining';

        var body = document.createElement('span');
        body.textContent = (payload && payload.message) || '';

        toast.appendChild(title);
        toast.appendChild(body);
        container.appendChild(toast);

        window.setTimeout(function () {
            toast.classList.add('out');
            window.setTimeout(function () {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
            }, 260);
        }, duration);
    }

    // ---------------------------------------------------- built-in progress
    var progressTimer = null;

    function startProgress(payload) {
        var wrap = $('#progress');
        var fill = $('#progress-fill');
        var label = $('#progress-label');
        if (!wrap || !fill || !label) {
            return;
        }

        if (progressTimer) {
            window.clearInterval(progressTimer);
            progressTimer = null;
        }

        var duration = Math.max(100, Number(payload && payload.duration) || 3000);
        label.textContent = (payload && payload.label) || 'Working...';
        fill.style.transition = 'none';
        fill.style.width = '0%';
        wrap.classList.remove('hidden');

        var start = Date.now();
        // Force a reflow so the reset width applies before we animate.
        void fill.offsetWidth;
        fill.style.transition = 'width 0.1s linear';

        progressTimer = window.setInterval(function () {
            var ratio = Math.min(1, (Date.now() - start) / duration);
            fill.style.width = (ratio * 100).toFixed(1) + '%';

            if (ratio >= 1) {
                window.clearInterval(progressTimer);
                progressTimer = null;
                wrap.classList.add('hidden');
                post('progressDone', { ok: true });
            }
        }, 60);
    }

    function cancelProgress() {
        if (progressTimer) {
            window.clearInterval(progressTimer);
            progressTimer = null;
        }
        var wrap = $('#progress');
        if (wrap) {
            wrap.classList.add('hidden');
        }
    }

    // -------------------------------------------------- built-in skillcheck
    var skill = null;

    var SKILL_PRESETS = {
        easy: { speed: 0.85, zone: 26 },
        medium: { speed: 1.35, zone: 19 },
        hard: { speed: 1.95, zone: 13 }
    };

    function endSkill(success) {
        if (!skill) {
            return;
        }

        if (skill.raf) {
            window.cancelAnimationFrame(skill.raf);
        }

        var wrap = $('#skillcheck');
        if (wrap) {
            wrap.classList.add('hidden');
        }

        document.removeEventListener('keydown', skill.onKey);
        skill = null;
        post('skillcheckDone', { ok: success === true });
    }

    function nextRound() {
        if (!skill) {
            return;
        }

        if (skill.round >= skill.rounds.length) {
            endSkill(true);
            return;
        }

        var preset = SKILL_PRESETS[skill.rounds[skill.round]] || SKILL_PRESETS.easy;
        var zoneWidth = preset.zone;
        // Random zone position keeping it fully inside the track.
        var zoneStart = 8 + Math.random() * (100 - zoneWidth - 16);

        skill.zoneStart = zoneStart;
        skill.zoneWidth = zoneWidth;
        skill.pos = 0;
        skill.dir = 1;
        skill.speed = preset.speed;

        var zone = $('#skill-zone');
        var track = $('#skill-track') || $('.skill-track');
        if (track) {
            track.classList.remove('hit', 'miss');
        }
        if (zone) {
            zone.style.left = zoneStart + '%';
            zone.style.width = zoneWidth + '%';
        }

        renderSkillDots();

        var last = null;
        function frame(now) {
            if (!skill) {
                return;
            }
            if (last === null) {
                last = now;
            }
            var dt = (now - last) / 16.6667;
            last = now;

            skill.pos += skill.dir * skill.speed * dt;
            if (skill.pos >= 100) {
                skill.pos = 100;
                skill.dir = -1;
            } else if (skill.pos <= 0) {
                skill.pos = 0;
                skill.dir = 1;
            }

            var cursor = $('#skill-cursor');
            if (cursor) {
                cursor.style.left = skill.pos + '%';
            }

            skill.raf = window.requestAnimationFrame(frame);
        }

        skill.raf = window.requestAnimationFrame(frame);
    }

    function renderSkillDots() {
        var container = $('#skill-rounds');
        if (!container || !skill) {
            return;
        }
        container.innerHTML = '';
        for (var i = 0; i < skill.rounds.length; i += 1) {
            var dot = document.createElement('span');
            dot.className = 'skill-dot'
                + (i < skill.round ? ' done' : '')
                + (i === skill.round ? ' active' : '');
            container.appendChild(dot);
        }
    }

    function attemptSkill() {
        if (!skill) {
            return;
        }

        var track = $('.skill-track');
        var inside = skill.pos >= skill.zoneStart && skill.pos <= (skill.zoneStart + skill.zoneWidth);

        if (skill.raf) {
            window.cancelAnimationFrame(skill.raf);
            skill.raf = null;
        }

        if (inside) {
            if (track) {
                track.classList.add('hit');
            }
            skill.round += 1;
            renderSkillDots();
            window.setTimeout(nextRound, 180);
        } else {
            if (track) {
                track.classList.add('miss');
            }
            window.setTimeout(function () {
                endSkill(false);
            }, 220);
        }
    }

    function startSkillcheck(payload) {
        var wrap = $('#skillcheck');
        if (!wrap) {
            post('skillcheckDone', { ok: false });
            return;
        }

        var rounds = (payload && payload.rounds) || ['easy'];
        if (!Array.isArray(rounds) || rounds.length === 0) {
            rounds = ['easy'];
        }

        var keyLabel = (payload && payload.key) || 'E';
        text('#skill-title', (payload && payload.title) || 'Bypass security');
        text('#skill-key', keyLabel);

        skill = {
            rounds: rounds,
            round: 0,
            raf: null,
            onKey: function (event) {
                var pressed = String(event.key || '').toUpperCase();
                if (pressed === keyLabel.toUpperCase() || event.code === 'Space' && keyLabel === 'E') {
                    event.preventDefault();
                    attemptSkill();
                } else if (pressed === 'ESCAPE') {
                    endSkill(false);
                }
            }
        };

        document.addEventListener('keydown', skill.onKey);
        wrap.classList.remove('hidden');
        nextRound();
    }

    window.addEventListener('message', function (event) {
        var data = event.data || {};

        switch (data.action) {
            case 'notify':
                notify(data);
                break;

            case 'progress':
                startProgress(data);
                break;

            case 'progressCancel':
                cancelProgress();
                break;

            case 'skillcheck':
                startSkillcheck(data);
                break;

            case 'open':
                renderPanel(data.warehouse);
                if (data.market) {
                    renderMarket(data.market);
                }
                showView('panel');
                break;

            case 'update':
                if (data.warehouse) {
                    renderPanel(data.warehouse);
                }
                if (data.market) {
                    renderMarket(data.market);
                }
                break;

            case 'market':
                renderMarket(data.market);
                break;

            case 'openShop':
                renderShop(data.shop);
                showView('shop');
                break;

            case 'updateShop':
                renderShop(data.shop);
                break;

            case 'openBroker':
                renderBroker(data.broker);
                showView('broker');
                break;

            case 'updateBroker':
                renderBroker(data.broker);
                break;

            case 'tab':
                var tabButton = document.querySelector('.tab[data-tab="' + data.tab + '"]');
                if (tabButton) {
                    tabButton.click();
                }
                break;

            case 'selectRig':
                state.selectedRig = Number(data.rigId);
                var rigsTab = document.querySelector('.tab[data-tab="rigs"]');
                if (rigsTab) {
                    rigsTab.click();
                }
                $all('.rig').forEach(function (element) {
                    element.classList.toggle('selected', Number(element.dataset.rigId) === state.selectedRig);
                });
                break;

            case 'close':
                showView(null);
                break;

            default:
                break;
        }
    });

    // Expose a few helpers for the automated test harness (no effect in game).
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = { money: money, btc: btc, hash: hash, escapeHtml: escapeHtml };
    }
}());
