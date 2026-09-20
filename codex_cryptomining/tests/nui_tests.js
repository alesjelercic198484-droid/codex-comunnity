/*
 * NUI test suite.
 * Loads the real index.html + app.js inside jsdom, pushes the same messages
 * the client sends in game and asserts that the interface reacts correctly.
 *
 *   node tests/nui_tests.js     (from the resource folder)
 */
'use strict';

const fs = require('fs');
const path = require('path');

let JSDOM;
try {
    JSDOM = require('jsdom').JSDOM;
} catch (error) {
    console.log('\x1b[33mjsdom is not installed, skipping the NUI tests.\x1b[0m');
    console.log('Install it with:  npm install --no-save jsdom');
    process.exit(0);
}

const root = path.join(__dirname, '..');
let passed = 0;
let failed = 0;
const failures = [];
let currentGroup = '';

function group(name) {
    currentGroup = name;
    console.log(`\n\x1b[1;36m== ${name}\x1b[0m`);
}

function ok(condition, name, detail) {
    if (condition) {
        passed += 1;
        console.log(`  \x1b[32mPASS\x1b[0m ${name}`);
    } else {
        failed += 1;
        failures.push(`[${currentGroup}] ${name}${detail ? ' -> ' + detail : ''}`);
        console.log(`  \x1b[31mFAIL\x1b[0m ${name}${detail ? ' -> ' + detail : ''}`);
    }
}

function equals(actual, expected, name) {
    ok(actual === expected, name, `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

// ---------------------------------------------------------------------------
// ENVIRONMENT
// ---------------------------------------------------------------------------
const html = fs.readFileSync(path.join(root, 'html', 'index.html'), 'utf8');
const appJs = fs.readFileSync(path.join(root, 'html', 'app.js'), 'utf8');

const dom = new JSDOM(html, { runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;

// Capture every fetch the UI performs so we can assert on the payloads.
const sentRequests = [];

window.GetParentResourceName = () => 'codex_cryptomining';
window.fetch = (url, options) => {
    const endpoint = String(url).split('/').pop();
    let body = {};

    try {
        body = JSON.parse(options && options.body ? options.body : '{}');
    } catch (error) {
        body = {};
    }

    sentRequests.push({ endpoint, body });

    return Promise.resolve({
        json: () => Promise.resolve({ ok: true })
    });
};

// Canvas is not implemented by jsdom: stub just enough for the chart code.
const canvasCalls = { strokeCount: 0, fillTextCount: 0 };
window.HTMLCanvasElement.prototype.getContext = function () {
    return {
        clearRect() {}, beginPath() {}, moveTo() {}, lineTo() {}, closePath() {},
        stroke() { canvasCalls.strokeCount += 1; }, fill() {}, arc() {},
        fillText() { canvasCalls.fillTextCount += 1; },
        createLinearGradient() { return { addColorStop() {} }; },
        set fillStyle(v) {}, get fillStyle() { return ''; },
        set strokeStyle(v) {}, get strokeStyle() { return ''; },
        set lineWidth(v) {}, get lineWidth() { return 0; },
        set font(v) {}, get font() { return ''; },
        set textAlign(v) {}, get textAlign() { return ''; }
    };
};

window.eval(appJs);

const document = window.document;
const $ = (selector) => document.querySelector(selector);

function send(message) {
    window.dispatchEvent(new window.MessageEvent('message', { data: message }));
}

function click(element) {
    if (!element) {
        return false;
    }
    element.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    return true;
}

function flush() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// ---------------------------------------------------------------------------
// FIXTURES
// ---------------------------------------------------------------------------
const market = {
    price: 42000,
    trend: 2.5,
    history: [40000, 41000, 40500, 42000],
    fee: 0.02,
    min: 18000,
    max: 92000
};

function makeWarehouse(overrides) {
    return Object.assign({
        id: 'elysian',
        label: 'Elysian Island Depot',
        type: 'small',
        owner: 'char1:owner',
        ownerName: 'John Miner',
        isOwner: true,
        btc: 1.5,
        bill: 2400,
        powered: true,
        locked: true,
        maxRigs: 12,
        maxGpus: 8,
        hashrate: 250.5,
        perHour: 0.001127,
        load: 4.25,
        value: 61740,
        totalMined: 12.5,
        totalEarned: 450000,
        storageLimit: 25,
        rigs: [
            { id: 1, slot: 1, gpus: 8, cpu: 2, cooler: 1, durability: 87.5, broken: false, hashrate: 260 },
            { id: 2, slot: 2, gpus: 3, cpu: 0, cooler: 0, durability: 22.0, broken: true, hashrate: 0 }
        ],
        keys: [{ identifier: 'char1:friend', name: 'Jane Friend' }],
        prices: { rig: 9000, cpu: 4500, cooler: 3800 },
        market
    }, overrides || {});
}

// ---------------------------------------------------------------------------
(async function run() {
    group('Panel rendering');

    ok($('#app').classList.contains('hidden'), 'the UI starts hidden');

    send({ action: 'open', warehouse: makeWarehouse(), market });
    await flush();

    ok(!$('#app').classList.contains('hidden'), 'the UI becomes visible');
    ok(!$('#panel').classList.contains('hidden'), 'the panel is shown');
    equals($('#panel-subtitle').textContent, 'Elysian Island Depot', 'warehouse label rendered');
    equals($('#stat-btc').textContent, '1.500000', 'BTC balance rendered');
    equals($('#stat-btc-value').textContent, '$61,740', 'BTC value rendered with separators');
    equals($('#stat-rigs').textContent, '2 / 12', 'rig count rendered');
    equals($('#stat-gpus').textContent, '11 GPU', 'total GPUs computed from the rigs');
    equals($('#stat-load').textContent, '4.25 kW', 'power draw rendered');
    equals($('#info-bill').textContent, '$2,400', 'bill rendered');
    equals($('#ticker-price').textContent, '$42,000', 'ticker price rendered');

    group('Rig cards');

    const cards = document.querySelectorAll('.rig');
    equals(cards.length, 2, 'one card per rig');
    ok(cards[1].classList.contains('broken'), 'the broken rig is flagged');
    ok(cards[0].textContent.includes('8/8'), 'GPU count shown on the card');
    ok(cards[0].textContent.includes('Mining'), 'a running rig shows the mining badge');
    ok(cards[1].textContent.includes('Broken'), 'a broken rig shows the broken badge');

    // An idle rig (no GPU) must not claim to be mining.
    send({ action: 'update', warehouse: makeWarehouse({ rigs: [{ id: 3, slot: 1, gpus: 0, cpu: 0, cooler: 0, durability: 100, broken: false, hashrate: 0 }] }) });
    await flush();
    ok(document.querySelector('.rig').textContent.includes('Idle'), 'a rig without GPU shows the idle badge');

    // Empty state.
    send({ action: 'update', warehouse: makeWarehouse({ rigs: [] }) });
    await flush();
    ok($('#rig-grid').textContent.includes('No mining rig'), 'empty state shown when there is no rig');

    send({ action: 'update', warehouse: makeWarehouse() });
    await flush();

    group('Actions');

    sentRequests.length = 0;
    click(document.querySelector('[data-action="installRig"]'));
    await flush();

    const installRequest = sentRequests.find((request) => request.endpoint === 'action');
    ok(installRequest !== undefined, 'installRig sends an action');
    equals(installRequest.body.action, 'installRig', 'correct action name sent');

    sentRequests.length = 0;
    click(document.querySelector('[data-rig-action="installGpu"]'));
    await flush();

    const gpuRequest = sentRequests.find((request) => request.endpoint === 'action');
    ok(gpuRequest !== undefined, 'the GPU button sends an action');
    equals(gpuRequest.body.action, 'installGpu', 'installGpu action sent');
    equals(gpuRequest.body.rigId, 1, 'the rig id of the clicked card is sent');

    // Sell a specific amount.
    sentRequests.length = 0;
    $('#sell-amount').value = '0.75';
    click(document.querySelector('[data-action="sellAmount"]'));
    await flush();

    const sellRequest = sentRequests.find((request) => request.endpoint === 'action');
    ok(sellRequest !== undefined, 'sellAmount sends an action');
    equals(sellRequest.body.amount, 0.75, 'the typed amount is forwarded');

    // An empty or zero amount must not send anything.
    sentRequests.length = 0;
    $('#sell-amount').value = '';
    click(document.querySelector('[data-action="sellAmount"]'));
    await flush();
    equals(sentRequests.filter((request) => request.endpoint === 'action').length, 0, 'an empty amount sends nothing');

    sentRequests.length = 0;
    $('#sell-amount').value = '0';
    click(document.querySelector('[data-action="sellAmount"]'));
    await flush();
    equals(sentRequests.filter((request) => request.endpoint === 'action').length, 0, 'a zero amount sends nothing');

    group('Owner restrictions');

    send({ action: 'update', warehouse: makeWarehouse({ isOwner: false }) });
    await flush();

    ok(document.querySelector('[data-action="installRig"]').disabled, 'a key holder cannot install a rig');
    ok(document.querySelector('[data-action="sellAll"]').disabled, 'a key holder cannot sell the BTC');
    ok(document.querySelector('[data-action="payBill"]').disabled, 'a key holder cannot pay the bill');

    send({ action: 'update', warehouse: makeWarehouse() });
    await flush();
    ok(!document.querySelector('[data-action="installRig"]').disabled, 'the owner keeps every control');

    group('Tabs & market');

    click(document.querySelector('.tab[data-tab="market"]'));
    await flush();
    ok(document.querySelector('[data-page="market"]').classList.contains('active'), 'market tab opens');
    equals($('#market-price').textContent, '$42,000', 'market price rendered');
    equals($('#market-fee').textContent, '2.0%', 'exchange fee rendered');
    ok($('#market-trend').classList.contains('up'), 'a positive trend is green');

    send({ action: 'market', market: Object.assign({}, market, { trend: -3.1, price: 39000 }) });
    await flush();
    ok($('#market-trend').classList.contains('down'), 'a negative trend is red');
    equals($('#ticker-price').textContent, '$39,000', 'ticker follows the live price');

    // A market with a single point must not crash the chart.
    const chartSafe = (() => {
        try {
            send({ action: 'market', market: Object.assign({}, market, { history: [42000] }) });
            return true;
        } catch (error) {
            return false;
        }
    })();
    ok(chartSafe, 'a one point history does not crash the chart');

    const emptyChartSafe = (() => {
        try {
            send({ action: 'market', market: Object.assign({}, market, { history: [] }) });
            return true;
        } catch (error) {
            return false;
        }
    })();
    ok(emptyChartSafe, 'an empty history does not crash the chart');

    send({ action: 'market', market });
    await flush();

    group('Keys tab');

    click(document.querySelector('.tab[data-tab="keys"]'));
    await flush();
    ok($('#key-list').textContent.includes('Jane Friend'), 'key holders are listed');

    sentRequests.length = 0;
    click(document.querySelector('[data-remove-key]'));
    await flush();
    const removeRequest = sentRequests.find((request) => request.endpoint === 'action');
    equals(removeRequest.body.action, 'removeKeys', 'removeKeys action sent');
    equals(removeRequest.body.identifier, 'char1:friend', 'the right identifier is sent');

    send({ action: 'update', warehouse: makeWarehouse({ keys: [] }) });
    await flush();
    ok($('#key-list').textContent.includes('Nobody else'), 'empty state when nobody has the keys');

    group('XSS safety');

    send({
        action: 'update',
        warehouse: makeWarehouse({
            ownerName: '<img src=x onerror="window.__pwned=true">',
            keys: [{ identifier: '"><script>window.__pwned=true</script>', name: '<b>evil</b>' }]
        })
    });
    await flush();

    ok(window.__pwned === undefined, 'injected markup never executes');
    equals($('#info-owner').querySelector('img'), null, 'owner name is not parsed as HTML');
    ok($('#key-list').querySelector('script') === null, 'key identifier is not parsed as HTML');
    ok($('#key-list').textContent.includes('<b>evil</b>'), 'the raw text is displayed escaped');

    group('Shop');

    send({
        action: 'openShop',
        shop: {
            shop: 'techshop',
            canSell: true,
            maxQuantity: 25,
            entries: [
                { index: 1, item: 'gpu', label: 'Mining GPU', price: 6500, sellPrice: 2925, owned: 3 },
                { index: 2, item: 'crypto_cpu', label: 'CPU upgrade kit', price: 4500, sellPrice: 2025, owned: 0 }
            ]
        }
    });
    await flush();

    ok(!$('#shop').classList.contains('hidden'), 'the shop window opens');
    ok($('#panel').classList.contains('hidden'), 'the panel is hidden while the shop is open');
    equals(document.querySelectorAll('.shop-item').length, 2, 'every catalog entry is rendered');
    ok($('#shop-list').textContent.includes('$6,500'), 'prices are formatted');
    ok($('#shop-list').textContent.includes('owned: 3'), 'owned quantity is displayed');

    sentRequests.length = 0;
    document.querySelector('[data-shop-qty="1"]').value = '4';
    click(document.querySelector('[data-shop-buy="1"]'));
    await flush();

    const buyRequest = sentRequests.find((request) => request.endpoint === 'shopAction');
    ok(buyRequest !== undefined, 'the buy button calls shopAction');
    equals(buyRequest.body.quantity, 4, 'the chosen quantity is forwarded');
    equals(buyRequest.body.index, 1, 'the catalog index is forwarded');
    equals(buyRequest.body.shop, 'techshop', 'the shop name is forwarded');

    sentRequests.length = 0;
    click(document.querySelector('[data-shop-sell="1"]'));
    await flush();
    const sellShopRequest = sentRequests.find((request) => request.endpoint === 'shopAction');
    equals(sellShopRequest.body.action, 'sell', 'the sell button sends a sell action');

    // The black market must not offer a sell button.
    send({
        action: 'openShop',
        shop: {
            shop: 'blackmarket',
            canSell: false,
            maxQuantity: 10,
            entries: [{ index: 1, item: 'lockpick', label: 'Reinforced lockpick', price: 2500, owned: 0 }]
        }
    });
    await flush();
    equals(document.querySelector('[data-shop-sell="1"]'), null, 'the black market has no sell button');
    equals($('#shop-title').textContent, 'Black market', 'the shop title adapts');

    group('Broker');

    send({
        action: 'openBroker',
        broker: {
            owned: 1,
            max: 2,
            list: [
                { id: 'elysian', label: 'Elysian Island Depot', type: 'small', typeLabel: 'Small facility', price: 185000, sellPrice: 101750, maxRigs: 12, owned: true, isMine: true },
                { id: 'paleto', label: 'Paleto Bay Cold Store', type: 'small', typeLabel: 'Small facility', price: 160000, sellPrice: 88000, maxRigs: 12, owned: false, isMine: false },
                { id: 'lamesa', label: 'La Mesa Storage Unit', type: 'small', typeLabel: 'Small facility', price: 210000, sellPrice: 115500, maxRigs: 12, owned: true, isMine: false }
            ]
        }
    });
    await flush();

    ok(!$('#broker').classList.contains('hidden'), 'the broker window opens');
    equals(document.querySelectorAll('.broker-item').length, 3, 'every warehouse is listed');
    ok($('#broker-subtitle').textContent.includes('1 / 2'), 'ownership counter displayed');
    ok(document.querySelector('[data-broker-sell="elysian"]') !== null, 'your own warehouse can be sold');
    ok(document.querySelector('[data-broker-buy="paleto"]') !== null, 'a free warehouse can be bought');
    equals(document.querySelector('[data-broker-buy="lamesa"]'), null, 'a warehouse owned by someone else cannot be bought');

    sentRequests.length = 0;
    click(document.querySelector('[data-broker-buy="paleto"]'));
    await flush();
    const brokerRequest = sentRequests.find((request) => request.endpoint === 'brokerAction');
    equals(brokerRequest.body.action, 'buyWarehouse', 'buyWarehouse action sent');
    equals(brokerRequest.body.warehouseId, 'paleto', 'the right warehouse id is sent');

    group('Closing');

    sentRequests.length = 0;
    click(document.querySelector('#broker [data-close]'));
    await flush();

    ok($('#app').classList.contains('hidden'), 'the UI hides on close');
    ok(sentRequests.some((request) => request.endpoint === 'close'), 'the close callback is sent');

    // Escape key.
    send({ action: 'open', warehouse: makeWarehouse(), market });
    await flush();
    ok(!$('#app').classList.contains('hidden'), 'the UI is open again');

    sentRequests.length = 0;
    document.dispatchEvent(new window.KeyboardEvent('keyup', { key: 'Escape', bubbles: true }));
    await flush();
    ok($('#app').classList.contains('hidden'), 'escape closes the UI');

    group('Malformed messages');

    const malformed = [
        { action: 'open' },
        { action: 'open', warehouse: null },
        { action: 'update' },
        { action: 'update', warehouse: makeWarehouse({ rigs: null, keys: null }) },
        { action: 'market' },
        { action: 'openShop', shop: { shop: 'techshop', entries: null } },
        { action: 'openBroker', broker: { list: null, owned: 0, max: 2 } },
        { action: 'selectRig', rigId: 'abc' },
        { action: 'tab', tab: 'does_not_exist' },
        { action: 'unknown_action_from_the_future' },
        {}
    ];

    let crashed = false;
    for (const message of malformed) {
        try {
            send(message);
            await flush();
        } catch (error) {
            crashed = true;
            console.log(`     crash on ${JSON.stringify(message)}: ${error.message}`);
        }
    }
    ok(!crashed, 'malformed NUI messages never crash the interface');

    // The UI must still work after all that.
    send({ action: 'open', warehouse: makeWarehouse(), market });
    await flush();
    equals($('#stat-btc').textContent, '1.500000', 'the UI still renders after malformed messages');

    // -----------------------------------------------------------------------
    console.log('\n\x1b[1m================ RESULT ================\x1b[0m');
    console.log(`  passed: \x1b[32m${passed}\x1b[0m`);
    console.log(`  failed: ${failed > 0 ? '\x1b[31m' : '\x1b[32m'}${failed}\x1b[0m`);

    if (failed > 0) {
        console.log('\n\x1b[31mFailures:\x1b[0m');
        failures.forEach((failure) => console.log('  - ' + failure));
        process.exit(1);
    }

    console.log('\n\x1b[32mAll NUI tests passed.\x1b[0m');
    process.exit(0);
}());
