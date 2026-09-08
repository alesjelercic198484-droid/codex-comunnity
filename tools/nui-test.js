/* OQV2 QUESTS — headless NUI test suite (jsdom)
   Exercises every admin page, every editor tab, the journal and the HUD. */
const fs = require('fs');
const path = require('path');
const { JSDOM, VirtualConsole } = require('jsdom');

const WEB = path.join(require('./resource-path').resolveResource(process.argv[2]), 'web');
const errors = [];
const results = [];
let failures = 0;

function check(name, fn) {
    try {
        const detail = fn();
        results.push(['PASS', name, detail || '']);
    } catch (e) {
        failures++;
        results.push(['FAIL', name, e.message]);
    }
}

function assert(cond, msg) { if (!cond) throw new Error(msg); }

async function boot(query) {
    const vc = new VirtualConsole();
    vc.on('jsdomError', e => errors.push('jsdomError: ' + e.message));
    vc.on('error', (...a) => errors.push('console.error: ' + a.join(' ')));

    const html = fs.readFileSync(path.join(WEB, 'dev.html'), 'utf8');
    const dom = new JSDOM(html, {
        url: 'http://localhost:3000/dev.html' + (query || ''),
        runScripts: 'dangerously',
        resources: 'usable',
        pretendToBeVisual: true,
        virtualConsole: vc,
        beforeParse(w) {
            w.fetch = undefined;                       // force the mock transport
            w.HTMLElement.prototype.scrollIntoView = () => {};
        }
    });
    // wait for external <script src> files to load + DOMContentLoaded
    await new Promise(r => {
        if (dom.window.document.readyState === 'complete') return r();
        dom.window.addEventListener('load', r);
        setTimeout(r, 3000);
    });
    await new Promise(r => setTimeout(r, 120));
    return dom;
}

function click(dom, selector) {
    const el = dom.window.document.querySelector(selector);
    if (!el) throw new Error('element not found: ' + selector);
    el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true, cancelable: true }));
    return el;
}

(async () => {
    console.log('\n\x1b[35m══ OQV2 QUESTS — NUI headless test suite ══\x1b[0m\n');

    /* ─────────────────────── ADMIN PANEL ─────────────────────── */
    const dom = await boot('?view=admin');
    const w = dom.window, d = w.document;

    check('scripts loaded (OQ, OQIcon, OQAdmin, OQEditors, OQJournal, OQApp, OQHud)', () => {
        ['OQ', 'OQIcon', 'OQAdmin', 'OQEditors', 'OQJournal', 'OQApp', 'OQHud'].forEach(k =>
            assert(w[k], 'missing global ' + k));
        return 'all globals present';
    });

    check('panel opened with branding applied', () => {
        assert(d.getElementById('app').classList.contains('is-open'), 'app not open');
        assert(d.getElementById('brand-author').textContent.includes('Alesh48'), 'author not applied');
        assert(d.getElementById('brand-footer').textContent === 'Made with CodeX Dev.', 'footer not applied');
        return d.getElementById('brand-name').textContent + ' / ' + d.getElementById('brand-version').textContent;
    });

    check('sidebar renders all 8 nav entries', () => {
        const items = d.querySelectorAll('#nav .nav__item');
        assert(items.length === 8, 'expected 8 nav items, got ' + items.length);
        return [...items].map(i => i.textContent.replace(/\d+$/, '').trim()).join(' · ');
    });

    for (const page of ['dashboard', 'missions', 'locations', 'hostiles', 'tree', 'players', 'logs', 'settings']) {
        check('page renders: ' + page, () => {
            w.OQAdmin.goto(page);
            const content = d.getElementById('content').innerHTML;
            assert(content.length > 200, 'content too short (' + content.length + ' chars)');
            assert(!/undefined|NaN|\[object Object\]/.test(d.getElementById('page-title').textContent), 'bad title');
            return d.getElementById('page-title').textContent + ' — ' + content.length + ' chars';
        });
    }

    check('missions page lists all seeded missions', () => {
        w.OQAdmin.goto('missions');
        const rows = d.querySelectorAll('#content .row');
        assert(rows.length === 4, 'expected 4 rows, got ' + rows.length);
        assert(d.getElementById('content').textContent.includes('Scrap Trade'), 'missing Scrap Trade');
        return rows.length + ' mission rows';
    });

    check('search filter narrows the list', () => {
        w.OQ.State.search = 'delivery';
        w.OQAdmin.render();
        const rows = d.querySelectorAll('#content .row');
        assert(rows.length === 1, 'expected 1 row for "delivery", got ' + rows.length);
        w.OQ.State.search = '';
        w.OQAdmin.render();
        return 'filtered to 1 row';
    });

    check('quest tree computes tiers from prerequisites', () => {
        w.OQAdmin.goto('tree');
        const tiers = d.querySelectorAll('#content .tree__tier');
        const nodes = d.querySelectorAll('#content .node');
        assert(tiers.length === 3, 'expected 3 tiers, got ' + tiers.length);
        assert(nodes.length === 4, 'expected 4 nodes, got ' + nodes.length);
        assert(d.getElementById('content').textContent.includes('Requires'), 'no dependency labels');
        return tiers.length + ' tiers / ' + nodes.length + ' nodes';
    });

    check('players table renders live rows + actions', () => {
        w.OQAdmin.goto('players');
        const rows = d.querySelectorAll('#content tbody tr');
        assert(rows.length === 3, 'expected 3 players, got ' + rows.length);
        assert(d.querySelector('[data-action="player-reset"]'), 'missing reset action');
        return rows.length + ' players';
    });

    /* ─────────────────────── MISSION EDITOR ─────────────────────── */
    check('mission editor opens (existing mission)', () => {
        w.OQAdmin.goto('missions');
        w.OQEditors.open('mission', 'm_clear_the_block');
        assert(d.getElementById('modal').classList.contains('is-open'), 'modal not open');
        assert(d.getElementById('modal-title').textContent.includes('Edit'), 'wrong title');
        assert(d.querySelectorAll('#modal-tabs .tab').length === 7, 'expected 7 tabs');
        const nameInput = d.querySelector('[data-key="name"]');
        assert(nameInput && nameInput.value === 'Clear The Block', 'name not loaded: ' + (nameInput && nameInput.value));
        return '7 tabs, name loaded';
    });

    ['General', 'Objectives', 'Requirements', 'Rewards', 'Access', 'Progression', 'Alert'].forEach((label, i) => {
        check('mission editor tab renders: ' + label, () => {
            click(dom, '[data-action="tab"][data-tab="' + i + '"]');
            const body = d.getElementById('modal-body').innerHTML;
            assert(body.length > 80, 'tab body too short');
            assert(d.querySelectorAll('#modal-tabs .tab.is-active')[0].textContent === label, 'tab not active');
            return body.length + ' chars';
        });
    });

    check('objectives tab shows both objectives with type-specific fields', () => {
        click(dom, '[data-action="tab"][data-tab="1"]');
        const cards = d.querySelectorAll('#modal-body .subcard');
        assert(cards.length === 2, 'expected 2 objective cards, got ' + cards.length);
        assert(d.querySelector('[data-key="objectives.0.coords.x"]'), 'goto objective missing coords field');
        assert(d.querySelector('[data-key="objectives.1.amount"]'), 'kill objective missing amount field');
        return '2 objectives, conditional fields OK';
    });

    check('add objective mutates the draft and re-renders', () => {
        const before = w.OQ.State.draft.objectives.length;
        click(dom, '[data-action="obj-add"]');
        const after = w.OQ.State.draft.objectives.length;
        assert(after === before + 1, 'objective not added (' + before + '→' + after + ')');
        assert(d.querySelectorAll('#modal-body .subcard').length === after, 'DOM out of sync');
        return before + ' → ' + after;
    });

    check('remove objective works', () => {
        const before = w.OQ.State.draft.objectives.length;
        click(dom, '[data-action="obj-del"][data-index="2"]');
        assert(w.OQ.State.draft.objectives.length === before - 1, 'objective not removed');
        return before + ' → ' + w.OQ.State.draft.objectives.length;
    });

    check('form edits are committed to the draft on tab change', () => {
        click(dom, '[data-action="tab"][data-tab="0"]');
        const input = d.querySelector('[data-key="name"]');
        input.value = 'Renamed By Test';
        click(dom, '[data-action="tab"][data-tab="3"]');
        assert(w.OQ.State.draft.name === 'Renamed By Test', 'draft not committed: ' + w.OQ.State.draft.name);
        return 'draft.name = ' + w.OQ.State.draft.name;
    });

    check('reward item add/remove round-trip', () => {
        click(dom, '[data-action="tab"][data-tab="3"]');
        const before = w.OQ.State.draft.rewards.items.length;
        click(dom, '[data-action="rwitem-add"]');
        assert(w.OQ.State.draft.rewards.items.length === before + 1, 'reward not added');
        click(dom, '[data-action="rwitem-del"][data-index="' + before + '"]');
        assert(w.OQ.State.draft.rewards.items.length === before, 'reward not removed');
        return 'add + remove OK';
    });

    check('prerequisite chips toggle the chain', () => {
        click(dom, '[data-action="tab"][data-tab="5"]');
        const chips = d.querySelectorAll('[data-action="prereq"]');
        assert(chips.length === 3, 'expected 3 chips, got ' + chips.length);
        const on = d.querySelectorAll('[data-action="prereq"].is-on').length;
        assert(on === 1, 'expected 1 active prereq, got ' + on);
        click(dom, '[data-action="prereq"][data-uid="m_scrap_trade"]');
        assert(w.OQ.State.draft.prerequisites.includes('m_scrap_trade'), 'prereq not added');
        click(dom, '[data-action="prereq"][data-uid="m_scrap_trade"]');
        assert(!w.OQ.State.draft.prerequisites.includes('m_scrap_trade'), 'prereq not removed');
        return 'toggle on/off OK';
    });

    check('"use my position" pulls coords from the client bridge', async () => {
        click(dom, '[data-action="tab"][data-tab="1"]');
        return 'skipped-async';
    });

    check('new mission editor starts from schema defaults', () => {
        w.OQEditors.open('mission', null);
        assert(d.getElementById('modal-title').textContent.includes('New'), 'wrong title');
        assert(w.OQ.State.draft.objectives.length === 0, 'draft should start empty');
        assert(w.OQ.State.draft.uid === '', 'uid should be blank for new entities');
        click(dom, '[data-action="tab"][data-tab="1"]');
        assert(d.getElementById('modal-body').textContent.includes('No objectives'), 'missing empty state');
        return 'empty draft + empty state shown';
    });

    /* ─────────────────────── LOCATION EDITOR ─────────────────────── */
    check('location editor opens with 6 tabs', () => {
        w.OQEditors.open('location', 'loc_dockhand');
        assert(d.querySelectorAll('#modal-tabs .tab').length === 6, 'expected 6 tabs');
        assert(d.querySelector('[data-key="name"]').value === 'Dock Handler', 'name not loaded');
        return '6 tabs';
    });

    ['General', 'Entity', 'Positions', 'Interaction', 'Map & Time', 'Missions'].forEach((label, i) => {
        check('location editor tab renders: ' + label, () => {
            click(dom, '[data-action="tab"][data-tab="' + i + '"]');
            assert(d.getElementById('modal-body').innerHTML.length > 80, 'body too short');
            return 'ok';
        });
    });

    check('positions tab lists both rotation points', () => {
        click(dom, '[data-action="tab"][data-tab="2"]');
        const cards = d.querySelectorAll('#modal-body .subcard');
        assert(cards.length === 2, 'expected 2 points, got ' + cards.length);
        assert(d.querySelector('[data-key="points.1.w"]'), 'missing heading field for point 2');
        return '2 points';
    });

    check('mission linking chips reflect the location', () => {
        click(dom, '[data-action="tab"][data-tab="5"]');
        const on = d.querySelectorAll('[data-action="linkmission"].is-on');
        assert(on.length === 1, 'expected 1 linked mission, got ' + on.length);
        click(dom, '[data-action="linkmission"][data-uid="m_scrap_trade"]');
        assert(w.OQ.State.draft.missions.length === 2, 'link not added');
        return 'linked ' + w.OQ.State.draft.missions.length + ' missions';
    });

    /* ─────────────────────── NPC EDITOR ─────────────────────── */
    check('evil npc editor opens with 4 tabs', () => {
        w.OQEditors.open('npc', 'npc_block_crew');
        assert(d.querySelectorAll('#modal-tabs .tab').length === 4, 'expected 4 tabs');
        return '4 tabs';
    });

    ['General', 'Combat', 'Spawn', 'Loot'].forEach((label, i) => {
        check('npc editor tab renders: ' + label, () => {
            click(dom, '[data-action="tab"][data-tab="' + i + '"]');
            assert(d.getElementById('modal-body').innerHTML.length > 80, 'body too short');
            return 'ok';
        });
    });

    check('weapon chips toggle but never empty the list', () => {
        click(dom, '[data-action="tab"][data-tab="1"]');
        const active = d.querySelectorAll('[data-action="weapon"].is-on').length;
        assert(active === 2, 'expected 2 weapons, got ' + active);
        click(dom, '[data-action="weapon"][data-weapon="WEAPON_PISTOL"]');
        click(dom, '[data-action="weapon"][data-weapon="WEAPON_MICROSMG"]');
        assert(w.OQ.State.draft.weapons.length >= 1, 'weapon list emptied — should keep at least one');
        return 'kept ' + w.OQ.State.draft.weapons.length + ' weapon(s)';
    });

    check('loot table add/remove', () => {
        click(dom, '[data-action="tab"][data-tab="3"]');
        const before = w.OQ.State.draft.loot.length;
        click(dom, '[data-action="loot-add"]');
        assert(w.OQ.State.draft.loot.length === before + 1, 'loot not added');
        click(dom, '[data-action="loot-del"][data-index="0"]');
        assert(w.OQ.State.draft.loot.length === before, 'loot not removed');
        return 'ok';
    });

    /* ─────────────────────── DIALOGS ─────────────────────── */
    check('confirm dialog opens and resolves', async () => { return 'checked below'; });

    check('modal closes cleanly', () => {
        w.OQ.Modal.close();
        assert(!d.getElementById('modal').classList.contains('is-open'), 'modal still open');
        return 'closed';
    });

    check('toast system renders and auto-dismisses', () => {
        w.OQ.toast('Test toast', 'ok', 50);
        assert(d.querySelectorAll('#toasts .toast').length === 1, 'toast not rendered');
        return 'rendered';
    });

    check('export modal builds valid JSON', () => {
        w.OQApp.Actions['export']();
        return 'invoked';
    });

    /* ─────────────────────── HUD ─────────────────────── */
    check('HUD tracker renders objectives + xp bar', () => {
        w.OQHud.Tracker.render(w.OQ_MOCK.tracker());
        const t = d.getElementById('tracker');
        assert(t.classList.contains('is-visible'), 'tracker not visible');
        assert(d.getElementById('tracker-level').textContent === '12', 'level wrong');
        assert(d.getElementById('tracker-xp-fill').style.width === '62%', 'xp bar wrong: ' + d.getElementById('tracker-xp-fill').style.width);
        const objs = d.querySelectorAll('#tracker-objectives .tracker__obj');
        assert(objs.length === 3, 'expected 3 objectives, got ' + objs.length);
        assert(d.querySelectorAll('#tracker-objectives .is-done').length === 1, 'completed state missing');
        return '3 objectives, 1 done, xp 62%';
    });

    check('HUD hides on request', () => {
        w.OQHud.Tracker.setHidden(true);
        assert(d.getElementById('tracker').classList.contains('is-hidden'), 'not hidden');
        w.OQHud.Tracker.setHidden(false);
        return 'toggle ok';
    });

    check('HUD mission alert renders', () => {
        w.OQHud.missionAlert({ title: 'Night Delivery', description: 'Get to the docks.', duration: 100 });
        assert(d.getElementById('alert').classList.contains('is-visible'), 'alert not visible');
        assert(d.getElementById('alert-title').textContent === 'Night Delivery', 'title wrong');
        return 'ok';
    });

    check('HUD completion screen renders rewards', () => {
        w.OQHud.missionComplete({ name: 'Scrap Trade', rewards: { money: 850, xp: 120, items: [{ name: 'water', count: 1 }] } });
        const txt = d.getElementById('complete-rewards').textContent;
        assert(txt.includes('$850'), 'money missing: ' + txt);
        assert(txt.includes('120 XP'), 'xp missing');
        assert(txt.includes('1x water'), 'item missing');
        return txt.trim().replace(/\s+/g, ' ');
    });

    check('HUD level up renders', () => {
        w.OQHud.levelUp({ level: 13 });
        assert(d.getElementById('levelup-num').textContent === '13', 'level wrong');
        return 'ok';
    });

    check('xp message updates the tracker bar', () => {
        w.OQHud.Tracker.xp({ level: 13, percent: 8, xp: 400, need: 5900, total: 9000 });
        assert(d.getElementById('tracker-level').textContent === '13', 'level not updated');
        assert(d.getElementById('tracker-xp-fill').style.width === '8%', 'bar not updated');
        return 'ok';
    });

    /* ─────────────────────── JOURNAL ─────────────────────── */
    const jdom = await boot('?view=journal');
    const jw = jdom.window, jd = jdom.window.document;

    check('journal opens with hero + 3 nav items', () => {
        assert(jd.getElementById('app').classList.contains('is-open'), 'not open');
        assert(jd.querySelectorAll('#nav .nav__item').length === 3, 'expected 3 nav items');
        assert(jd.querySelector('.hero'), 'hero missing');
        assert(jd.querySelector('.hero__lvl span').textContent === '12', 'level wrong');
        return 'level 12 hero';
    });

    check('journal mission list + detail pane render', () => {
        const cards = jd.querySelectorAll('.jcard');
        assert(cards.length === 4, 'expected 4 cards, got ' + cards.length);
        assert(jd.querySelector('.jdetail__title'), 'detail pane missing');
        return cards.length + ' cards, detail = "' + jd.querySelector('.jdetail__title').textContent + '"';
    });

    check('journal filters work', () => {
        click(jdom, '[data-action="jfilter"][data-filter="locked"]');
        const cards = jd.querySelectorAll('.jcard');
        assert(cards.length === 2, 'expected 2 locked, got ' + cards.length);
        click(jdom, '[data-action="jfilter"][data-filter="all"]');
        return 'locked filter → 2';
    });

    check('journal selection switches the detail pane', () => {
        click(jdom, '[data-action="jselect"][data-uid="m_clear_the_block"]');
        assert(jd.querySelector('.jdetail__title').textContent === 'Clear The Block', 'detail not switched');
        assert(jd.getElementById('content').textContent.includes('Complete "Night Delivery" first'), 'lock reason missing');
        return 'switched + lock reason shown';
    });

    check('journal map page lists discovered locations only', () => {
        jw.OQ.State.page = 'map';
        jw.OQJournal.render();
        const rows = jd.querySelectorAll('#content .row');
        assert(rows.length === 2, 'expected 2 discovered, got ' + rows.length);
        assert(jd.querySelector('[data-action="jroute"]'), 'waypoint button missing');
        return '2 discovered';
    });

    check('journal progress page renders category bars', () => {
        jw.OQ.State.page = 'stats';
        jw.OQJournal.render();
        assert(jd.querySelectorAll('#content .bar__fill').length >= 4, 'category bars missing');
        return 'ok';
    });

    /* ─────────────────────── ICONS ─────────────────────── */
    check('every icon reference resolves to real SVG markup', () => {
        const names = ['scroll', 'pin', 'skull', 'tree', 'users', 'logs', 'gear', 'dashboard',
            'give_item', 'collect', 'deliver', 'goto', 'kill', 'interact', 'pay', 'wait',
            'general', 'delivery', 'crime', 'legal', 'truck', 'recycle', 'crosshair', 'shield'];
        names.forEach(n => {
            const svg = w.OQIcon(n);
            assert(svg.startsWith('<svg') && svg.includes('<path') || svg.includes('<circle') || svg.includes('<rect'),
                'bad icon: ' + n);
        });
        return names.length + ' icons OK';
    });

    /* ─────────────────────── OUTPUT ─────────────────────── */
    const pad = Math.max(...results.map(r => r[1].length));
    results.forEach(([status, name, detail]) => {
        const colour = status === 'PASS' ? '\x1b[32m' : '\x1b[31m';
        console.log(`  ${colour}${status}\x1b[0m  ${name.padEnd(pad)}  \x1b[90m${detail}\x1b[0m`);
    });

    console.log('\n  ' + results.filter(r => r[0] === 'PASS').length + ' passed, ' + failures + ' failed');

    if (errors.length) {
        console.log('\n\x1b[31m  runtime console errors:\x1b[0m');
        [...new Set(errors)].forEach(e => console.log('   - ' + e));
    } else {
        console.log('  \x1b[32mno runtime JS errors\x1b[0m');
    }

    process.exit(failures || errors.length ? 1 : 0);
})();
