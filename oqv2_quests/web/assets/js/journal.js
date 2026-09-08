/* OQV2 QUESTS — Player journal view
   Made with CodeX Dev. */
(function (w) {
    'use strict';

    var O = w.OQ, I = w.OQIcon, S = w.OQ.State;

    var FILTERS = [
        { id: 'all',       label: 'All' },
        { id: 'available', label: 'Available' },
        { id: 'locked',    label: 'Locked' },
        { id: 'completed', label: 'Completed' }
    ];

    var state = { filter: 'all', selected: null };

    function nav() {
        var html = '';
        [
            { id: 'quests', label: 'Missions', icon: 'scroll' },
            { id: 'map', label: 'Discovered', icon: 'map' },
            { id: 'stats', label: 'Progress', icon: 'star' }
        ].forEach(function (p) {
            html += '<button class="nav__item' + (S.page === p.id ? ' is-active' : '') +
                '" data-action="page" data-page="' + p.id + '">' + I(p.icon) + '<span>' + p.label + '</span></button>';
        });
        O.$('#nav').innerHTML = html;
    }

    function hero() {
        var p = O.getPath(S.journal, 'player', {}) || {};
        return '<div class="hero">' +
            '<div class="hero__lvl"><span>' + (p.level || 1) + '</span></div>' +
            '<div class="hero__info">' +
            '<div class="hero__name">' + O.esc(p.name || 'Adventurer') + '</div>' +
            '<div class="hero__sub">' + O.num(p.xp || 0) + ' / ' + O.num(p.need || 0) + ' XP to level ' + ((p.level || 1) + 1) +
                (p.maxLevel ? ' · max level reached' : '') + '</div>' +
            '<div class="bar" style="max-width:420px"><div class="bar__fill" style="width:' + (p.percent || 0) + '%"></div></div>' +
            '</div>' +
            '<div class="hero__stats">' +
            '<div class="hero__stat"><span class="hero__stat-val">' + O.num(p.completed || 0) + '</span><span class="hero__stat-lbl">Completed</span></div>' +
            '<div class="hero__stat"><span class="hero__stat-val">' + O.num(p.totalXP || 0) + '</span><span class="hero__stat-lbl">Total XP</span></div>' +
            '<div class="hero__stat"><span class="hero__stat-val">' + ((S.journal.locations || []).filter(function (l) { return l.discovered; }).length) +
                '</span><span class="hero__stat-lbl">Discovered</span></div>' +
            '</div></div>';
    }

    function classify(m) {
        if (m.completions > 0 && (m.locked || m.cooldownLeft > 0)) return 'completed';
        if (m.available) return 'available';
        if (m.completions > 0) return 'completed';
        return 'locked';
    }

    function pageQuests() {
        var missions = S.journal.missions || [];
        var html = hero();

        html += '<div class="chips" style="margin-bottom:14px">';
        FILTERS.forEach(function (f) {
            var count = f.id === 'all' ? missions.length : missions.filter(function (m) { return classify(m) === f.id; }).length;
            html += '<button class="chip' + (state.filter === f.id ? ' is-on' : '') + '" data-action="jfilter" data-filter="' + f.id + '">' +
                O.esc(f.label) + ' <b style="opacity:.6">' + count + '</b></button>';
        });
        html += '</div>';

        var list = missions.filter(function (m) { return state.filter === 'all' || classify(m) === state.filter; });

        if (!list.length) {
            return html + w.OQAdmin.emptyState('scroll', 'Nothing here yet', 'Explore the map and talk to people — missions show up as you discover them.');
        }

        if (!state.selected || !list.some(function (m) { return m.uid === state.selected; })) {
            state.selected = list[0].uid;
        }

        html += '<div class="journal" style="height:calc(100% - 190px)"><div class="journal__list">';
        list.forEach(function (m) {
            var cls = classify(m);
            html += '<div class="jcard' + (m.uid === state.selected ? ' is-active' : '') + (cls === 'locked' ? ' is-locked' : '') +
                '" data-action="jselect" data-uid="' + O.esc(m.uid) + '">' +
                '<div class="jcard__icon">' + I(m.icon || m.category || 'scroll') + '</div>' +
                '<div class="jcard__main"><div class="jcard__name">' + O.esc(m.name) + '</div>' +
                '<div class="jcard__desc">' + O.esc(m.description || '') + '</div></div>' +
                (cls === 'available' ? '<span class="tag tag--ok">Ready</span>' :
                 cls === 'completed' ? '<span class="tag tag--info">' + (m.completions || 1) + 'x done</span>' :
                 '<span class="tag tag--muted">' + I('lock') + '</span>') +
                '</div>';
        });
        html += '</div>';

        html += '<div class="jdetail">' + detail(list) + '</div></div>';
        return html;
    }

    function detail(list) {
        var m = null;
        for (var i = 0; i < list.length; i++) if (list[i].uid === state.selected) m = list[i];
        if (!m) return '<div class="card__sub">Select a mission.</div>';

        var html = '<div class="jdetail__title">' + O.esc(m.name) + '</div>' +
            '<div class="jdetail__desc">' + O.esc(m.description || 'No briefing available.') + '</div>';

        html += '<div class="row__meta" style="margin-top:14px">' +
            '<span class="tag tag--accent">' + I('sparkle') + '+' + O.num(m.xpReward || 0) + ' XP</span>' +
            (m.requiredLevel ? '<span class="tag tag--info">' + I('shield') + 'Level ' + m.requiredLevel + '</span>' : '') +
            (m.completions ? '<span class="tag">' + I('check') + m.completions + 'x completed</span>' : '') +
            (m.cooldownLeft ? '<span class="tag tag--warn">' + I('clock') + O.duration(m.cooldownLeft) + '</span>' : '') +
            '</div>';

        if (!m.available && m.reason) {
            html += '<div class="jdetail__block"><h4>Locked</h4>' +
                '<div class="tag tag--err" style="white-space:normal;line-height:1.5">' + I('lock') + O.esc(m.reason) + '</div></div>';
        }

        if ((m.objectives || []).length) {
            html += '<div class="jdetail__block"><h4>Objectives</h4>';
            m.objectives.forEach(function (o) {
                html += '<div class="jobj"><span class="jobj__dot"></span><span>' + O.esc(o.label) + '</span></div>';
            });
            html += '</div>';
        }

        var r = m.rewards || {};
        var rewards = [];
        if (r.money) rewards.push({ icon: 'money', text: O.money(r.money) });
        if (r.bank) rewards.push({ icon: 'money', text: O.money(r.bank) + ' bank' });
        if (r.black) rewards.push({ icon: 'money', text: O.money(r.black) + ' dirty' });
        (r.items || []).forEach(function (it) {
            rewards.push({ icon: 'box', text: it.count + 'x ' + it.name + (it.chance < 100 ? ' (' + it.chance + '%)' : '') });
        });
        if (rewards.length) {
            html += '<div class="jdetail__block"><h4>Rewards</h4><div class="row__meta">';
            rewards.forEach(function (x) { html += '<span class="tag tag--ok">' + I(x.icon) + O.esc(x.text) + '</span>'; });
            html += '</div></div>';
        }

        var active = O.getPath(S.journal, 'player.active', null);
        if (active && active.uid === m.uid) {
            html += '<div class="jdetail__block"><button class="btn btn--danger" data-action="jabandon">' +
                I('stop') + 'Abandon this mission</button></div>';
        }

        return html;
    }

    function pageMap() {
        var locs = (S.journal.locations || []);
        var found = locs.filter(function (l) { return l.discovered; });
        var html = hero();

        html += '<div class="grid grid--3">' +
            '<div class="card"><div class="stat"><div class="stat__icon">' + I('map') + '</div><div>' +
            '<div class="stat__val">' + found.length + ' / ' + locs.length + '</div>' +
            '<div class="stat__lbl">Locations discovered</div></div></div></div>' +
            '<div class="card"><div class="stat stat--alt"><div class="stat__icon">' + I('scroll') + '</div><div>' +
            '<div class="stat__val">' + (S.journal.missions || []).filter(function (m) { return m.available; }).length + '</div>' +
            '<div class="stat__lbl">Missions ready</div></div></div></div>' +
            '<div class="card"><div class="stat stat--ok"><div class="stat__icon">' + I('check') + '</div><div>' +
            '<div class="stat__val">' + (S.journal.missions || []).filter(function (m) { return m.completions > 0; }).length + '</div>' +
            '<div class="stat__lbl">Missions cleared</div></div></div></div>' +
            '</div>';

        html += '<div class="section-title">Discovered locations</div>';
        if (!found.length) {
            return html + w.OQAdmin.emptyState('map', 'Nothing discovered', 'Locations get added here automatically when you walk near a quest giver.');
        }

        html += '<div class="list">';
        found.forEach(function (l) {
            var pt = (l.points || [])[0];
            html += '<div class="row"><div class="row__icon">' + I('pin') + '</div><div class="row__main">' +
                '<div class="row__title">' + O.esc(l.name) + '</div>' +
                '<div class="row__desc">' + O.esc(O.coordText(pt)) + '</div></div>' +
                (pt ? '<button class="btn btn--sm" data-action="jroute" data-coords=\'' + O.esc(JSON.stringify(pt)) + '\'>' +
                    I('route') + 'Set waypoint</button>' : '') +
                '</div>';
        });
        return html + '</div>';
    }

    function pageStats() {
        var missions = S.journal.missions || [];
        var html = hero();

        var byCategory = {};
        missions.forEach(function (m) {
            var c = m.category || 'general';
            byCategory[c] = byCategory[c] || { total: 0, done: 0 };
            byCategory[c].total++;
            if (m.completions > 0) byCategory[c].done++;
        });

        html += '<div class="section-title">Completion by category</div><div class="grid grid--2">';
        Object.keys(byCategory).forEach(function (c) {
            var v = byCategory[c];
            var pct = v.total ? Math.round((v.done / v.total) * 100) : 0;
            html += '<div class="card"><div class="card__head"><div>' +
                '<div class="card__title">' + O.esc(O.titleCase(c)) + '</div>' +
                '<div class="card__sub">' + v.done + ' of ' + v.total + ' completed</div></div>' +
                '<span class="tag tag--accent">' + pct + '%</span></div>' +
                '<div class="bar"><div class="bar__fill" style="width:' + pct + '%"></div></div></div>';
        });
        html += '</div>';

        html += '<div class="section-title">Next up</div>';
        var next = missions.filter(function (m) { return m.available && !m.completions; }).slice(0, 6);
        if (!next.length) {
            html += '<div class="card"><div class="card__sub">No new missions available right now — check back later or explore the map.</div></div>';
        } else {
            html += '<div class="list">';
            next.forEach(function (m) {
                html += '<div class="row"><div class="row__icon">' + I(m.icon || 'scroll') + '</div>' +
                    '<div class="row__main"><div class="row__title">' + O.esc(m.name) + '</div>' +
                    '<div class="row__desc">' + O.esc(m.description || '') + '</div></div>' +
                    '<span class="tag tag--accent">+' + O.num(m.xpReward || 0) + ' XP</span></div>';
            });
            html += '</div>';
        }
        return html;
    }

    var TITLES = {
        quests: { title: 'Mission Journal', sub: 'Everything you have found so far' },
        map:    { title: 'Discovered World', sub: 'Locations you already know about' },
        stats:  { title: 'Your Progress', sub: 'Levels, categories and what comes next' }
    };

    function render() {
        if (!S.journal) return;
        if (['quests', 'map', 'stats'].indexOf(S.page) === -1) S.page = 'quests';

        var meta = TITLES[S.page];
        O.$('#page-title').textContent = meta.title;
        O.$('#page-sub').textContent = meta.sub;
        O.$('#page-tools').innerHTML = '<button class="btn" data-action="refresh">' + I('refresh') + 'Refresh</button>';
        nav();

        var html = S.page === 'map' ? pageMap() : S.page === 'stats' ? pageStats() : pageQuests();
        O.$('#content').innerHTML = html;
    }

    var Actions = {
        'jfilter': function (el) { state.filter = el.getAttribute('data-filter'); render(); },
        'jselect': function (el) { state.selected = el.getAttribute('data-uid'); render(); },
        'jabandon': function () {
            O.confirmBox('Abandon mission?', 'All progress on the current mission will be lost.').then(function (yes) {
                if (!yes) return;
                O.post('journal:abandon').then(function () {
                    O.toast('Mission abandoned', 'warn');
                    w.OQApp.refresh();
                });
            });
        },
        'jroute': function (el) {
            var c = JSON.parse(el.getAttribute('data-coords') || '{}');
            O.post('journal:route', { coords: c });
        }
    };

    w.OQJournal = { render: render, Actions: Actions, state: state };
})(window);
