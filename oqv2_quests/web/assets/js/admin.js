/* OQV2 QUESTS — Admin panel pages
   Made with CodeX Dev. */
(function (w) {
    'use strict';

    var O = w.OQ, I = w.OQIcon, S = w.OQ.State;

    var PAGES = [
        { id: 'dashboard', label: 'Dashboard', icon: 'dashboard', title: 'Dashboard', sub: 'Live overview of your mission network' },
        { id: 'missions',  label: 'Missions',  icon: 'scroll',    title: 'Missions',  sub: 'Create, edit and chain unlimited missions' },
        { id: 'locations', label: 'Locations', icon: 'pin',       title: 'Locations', sub: 'NPCs, props and markers that give out missions' },
        { id: 'hostiles',  label: 'Evil NPCs', icon: 'skull',     title: 'Evil NPCs', sub: 'Hostile groups, loot tables and police alerts' },
        { id: 'tree',      label: 'Quest Tree',icon: 'tree',      title: 'Quest Tree','sub': 'Visual progression and unlock chain' },
        { id: 'players',   label: 'Players',   icon: 'users',     title: 'Players',   sub: 'Online players, levels and live runs' },
        { id: 'logs',      label: 'Logs',      icon: 'logs',      title: 'Activity Logs', sub: 'Everything that happens, recorded' },
        { id: 'settings',  label: 'Settings',  icon: 'gear',      title: 'Settings & Tools', sub: 'Import, export and runtime info' }
    ];

    /* ═══════════════════════════════ NAV ═══════════════════════════════ */
    function renderNav() {
        var d = S.data || {};
        var counts = {
            missions: (d.missions || []).length,
            locations: (d.locations || []).length,
            hostiles: (d.npcs || []).length,
            players: (d.players || []).length
        };
        var html = '';
        PAGES.forEach(function (p, i) {
            if (i === 5) html += '<div class="nav__sep"></div>';
            var badge = counts[p.id] !== undefined ? '<span class="nav__badge">' + counts[p.id] + '</span>' : '';
            html += '<button class="nav__item' + (S.page === p.id ? ' is-active' : '') +
                '" data-action="page" data-page="' + p.id + '">' + I(p.icon) +
                '<span>' + p.label + '</span>' + badge + '</button>';
        });
        O.$('#nav').innerHTML = html;
    }

    function pageMeta(id) {
        for (var i = 0; i < PAGES.length; i++) if (PAGES[i].id === id) return PAGES[i];
        return PAGES[0];
    }

    /* ═════════════════════════════ TOOLBARS ════════════════════════════ */
    function searchBox(placeholder) {
        return '<div class="search">' + I('search') +
            '<input class="input" id="search-input" type="text" placeholder="' + O.esc(placeholder) +
            '" value="' + O.esc(S.search) + '" /></div>';
    }

    function tools(page) {
        switch (page) {
            case 'missions':
                return searchBox('Search missions…') +
                    '<button class="btn btn--primary" data-action="new" data-kind="mission">' + I('plus') + 'New mission</button>';
            case 'locations':
                return searchBox('Search locations…') +
                    '<button class="btn btn--primary" data-action="new" data-kind="location">' + I('plus') + 'New location</button>';
            case 'hostiles':
                return searchBox('Search groups…') +
                    '<button class="btn btn--primary" data-action="new" data-kind="npc">' + I('plus') + 'New group</button>';
            case 'players':
                return searchBox('Search players…') +
                    '<button class="btn" data-action="refresh">' + I('refresh') + 'Refresh</button>';
            case 'logs':
                return '<button class="btn" data-action="refresh">' + I('refresh') + 'Refresh</button>';
            case 'dashboard':
                return '<button class="btn" data-action="refresh">' + I('refresh') + 'Refresh</button>';
            default:
                return '';
        }
    }

    /* ════════════════════════════ DASHBOARD ═══════════════════════════ */
    function stat(iconName, value, label, mod) {
        return '<div class="card"><div class="stat ' + (mod || '') + '">' +
            '<div class="stat__icon">' + I(iconName) + '</div>' +
            '<div><div class="stat__val">' + O.esc(value) + '</div>' +
            '<div class="stat__lbl">' + O.esc(label) + '</div></div></div></div>';
    }

    function pageDashboard() {
        var d = S.data || {}, st = d.stats || {};
        var html = '<div class="grid grid--4">' +
            stat('scroll', st.missionsEnabled + ' / ' + st.missions, 'Missions active') +
            stat('pin', st.locationsEnabled + ' / ' + st.locations, 'Locations live', 'stat--alt') +
            stat('skull', st.npcsEnabled + ' / ' + st.npcs, 'Hostile groups', 'stat--warn') +
            stat('users', st.online || 0, 'Players online', 'stat--ok') +
            '</div>';

        html += '<div class="grid grid--4" style="margin-top:14px">' +
            stat('check', O.num(st.completions || 0), 'Total completions', 'stat--ok') +
            stat('bolt', O.num(st.activeRuns || 0), 'Missions in progress') +
            stat('user', O.num(st.playersTracked || 0), 'Tracked profiles', 'stat--alt') +
            stat('db', st.dbReady ? 'Connected' : 'Offline', 'Database', st.dbReady ? 'stat--ok' : 'stat--warn') +
            '</div>';

        /* leaderboard + recent activity */
        html += '<div class="grid grid--2" style="margin-top:18px">';

        html += '<div class="card"><div class="card__head"><div>' +
            '<div class="card__title">Top adventurers</div>' +
            '<div class="card__sub">Ranked by total experience</div></div>' + I('star') + '</div>';
        var lb = d.leaderboard || [];
        if (!lb.length) {
            html += '<div style="font-size:12px;color:var(--txt-3);padding:8px 0">No progression recorded yet.</div>';
        } else {
            html += '<table class="table"><thead><tr><th>#</th><th>Player</th><th>Level</th><th>XP</th><th>Done</th></tr></thead><tbody>';
            lb.slice(0, 8).forEach(function (r, i) {
                html += '<tr><td class="mono">' + (i + 1) + '</td><td>' + O.esc(r.name || r.identifier) +
                    '</td><td><span class="tag tag--accent">Lv ' + r.level + '</span></td><td class="mono">' +
                    O.num(r.xp) + '</td><td>' + O.num(r.completed) + '</td></tr>';
            });
            html += '</tbody></table>';
        }
        html += '</div>';

        html += '<div class="card"><div class="card__head"><div>' +
            '<div class="card__title">Recent activity</div>' +
            '<div class="card__sub">Latest 8 recorded events</div></div>' + I('bolt') + '</div>';
        var logs = (d.logs || []).slice(0, 8);
        if (!logs.length) {
            html += '<div style="font-size:12px;color:var(--txt-3);padding:8px 0">Nothing logged yet.</div>';
        } else {
            html += '<div class="list">';
            logs.forEach(function (l) {
                html += '<div style="display:flex;gap:10px;align-items:center;padding:7px 0;border-bottom:1px solid var(--line-soft)">' +
                    '<span class="tag ' + logTag(l.action) + '">' + O.esc(l.action) + '</span>' +
                    '<span style="font-size:12px;color:var(--txt-1);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' +
                    O.esc(l.name || l.identifier || 'system') + '</span>' +
                    '<span style="font-size:10.5px;color:var(--txt-3)">' + O.timeAgo(l.created_at) + '</span></div>';
            });
            html += '</div>';
        }
        html += '</div></div>';

        /* getting started */
        html += '<div class="section-title">Quick start</div>' +
            '<div class="grid grid--3">' +
            quickCard('scroll', '1 · Create a mission', 'Define objectives, rewards, requirements and cooldowns.', 'new', 'mission') +
            quickCard('pin', '2 · Place a giver', 'Spawn an NPC or prop, link the mission and set the dialogue.', 'new', 'location') +
            quickCard('skull', '3 · Add some heat', 'Configure hostile groups with loot, weapons and police alerts.', 'new', 'npc') +
            '</div>';

        return html;
    }

    function quickCard(iconName, title, text, action, kind) {
        return '<div class="card" style="cursor:pointer" data-action="' + action + '" data-kind="' + kind + '">' +
            '<div class="stat"><div class="stat__icon">' + I(iconName) + '</div><div>' +
            '<div class="card__title">' + O.esc(title) + '</div>' +
            '<div class="card__sub" style="line-height:1.5;margin-top:5px">' + O.esc(text) + '</div>' +
            '</div></div></div>';
    }

    function logTag(action) {
        if (!action) return 'tag--muted';
        if (action.indexOf('complete') > -1 || action.indexOf('level') > -1) return 'tag--ok';
        if (action.indexOf('denied') > -1 || action.indexOf('abuse') > -1) return 'tag--err';
        if (action.indexOf('admin') > -1) return 'tag--info';
        return 'tag--muted';
    }

    /* ════════════════════════════ MISSIONS ════════════════════════════ */
    function matchSearch(text) {
        if (!S.search) return true;
        return String(text || '').toLowerCase().indexOf(S.search.toLowerCase()) > -1;
    }

    function pageMissions() {
        var list = (S.data.missions || []).filter(function (m) {
            return matchSearch(m.name + ' ' + m.description + ' ' + m.category + ' ' + m.uid);
        });

        if (!list.length) {
            return emptyState('scroll', 'No missions yet',
                'Missions are the heart of OQV2. Create your first one and link it to a location so players can pick it up.',
                '<button class="btn btn--primary" data-action="new" data-kind="mission">' + I('plus') + 'Create the first mission</button>');
        }

        var html = '<div class="list">';
        list.forEach(function (m) {
            var reward = [];
            if (m.rewards && m.rewards.money) reward.push(O.money(m.rewards.money));
            if (m.rewards && m.rewards.bank) reward.push(O.money(m.rewards.bank) + ' bank');
            if (m.rewards && m.rewards.black) reward.push(O.money(m.rewards.black) + ' dirty');
            if (m.rewards && (m.rewards.items || []).length) reward.push((m.rewards.items || []).length + ' item(s)');

            html += '<div class="row' + (m.enabled ? '' : ' is-off') + '">' +
                '<div class="row__icon">' + I(m.icon || m.category || 'scroll') + '</div>' +
                '<div class="row__main">' +
                '<div class="row__title">' + O.esc(m.name) +
                    (m.enabled ? '' : '<span class="tag tag--muted">disabled</span>') + '</div>' +
                '<div class="row__desc">' + O.esc(m.description || 'No description') + '</div>' +
                '<div class="row__meta">' +
                    '<span class="tag">' + I('list') + O.esc((m.objectives || []).length) + ' objective(s)</span>' +
                    '<span class="tag tag--accent">' + I('sparkle') + '+' + O.num(m.xpReward || 0) + ' XP</span>' +
                    (m.requiredLevel ? '<span class="tag tag--info">' + I('shield') + 'Lv ' + m.requiredLevel + '</span>' : '') +
                    (reward.length ? '<span class="tag tag--ok">' + I('gift') + O.esc(reward.join(' · ')) + '</span>' : '') +
                    '<span class="tag">' + I('clock') + O.esc(O.titleCase(m.cooldown ? m.cooldown.type : 'none')) + '</span>' +
                    ((m.prerequisites || []).length ? '<span class="tag tag--warn">' + I('link') + O.esc((m.prerequisites || []).length) + ' prereq</span>' : '') +
                    '<span class="tag tag--muted">' + O.esc(m.category) + '</span>' +
                '</div></div>' +
                rowActions('mission', m) + '</div>';
        });
        return html + '</div>';
    }

    /* ════════════════════════════ LOCATIONS ═══════════════════════════ */
    function pageLocations() {
        var list = (S.data.locations || []).filter(function (l) {
            return matchSearch(l.name + ' ' + (l.entity && l.entity.model) + ' ' + l.uid);
        });

        if (!list.length) {
            return emptyState('pin', 'No locations yet',
                'A location is where players meet a quest giver — an NPC, a prop or just a marker.',
                '<button class="btn btn--primary" data-action="new" data-kind="location">' + I('plus') + 'Create a location</button>');
        }

        var missionNames = {};
        (S.data.missions || []).forEach(function (m) { missionNames[m.uid] = m.name; });

        var html = '<div class="list">';
        list.forEach(function (l) {
            var linked = (l.missions || []).map(function (uid) { return missionNames[uid] || uid; });
            html += '<div class="row' + (l.enabled ? '' : ' is-off') + '">' +
                '<div class="row__icon">' + I(l.entity && l.entity.type === 'object' ? 'box' : (l.entity && l.entity.type === 'marker' ? 'flag' : 'user')) + '</div>' +
                '<div class="row__main">' +
                '<div class="row__title">' + O.esc(l.name) +
                    (l.enabled ? '' : '<span class="tag tag--muted">disabled</span>') +
                    (l.rotate && l.rotate.enabled ? '<span class="tag tag--info">' + I('route') + 'rotating</span>' : '') + '</div>' +
                '<div class="row__desc">' + O.esc((l.entity && l.entity.model) || '—') + ' · ' +
                    O.esc(O.coordText((l.points || [])[0])) + '</div>' +
                '<div class="row__meta">' +
                    '<span class="tag">' + I('pin') + O.esc((l.points || []).length) + ' point(s)</span>' +
                    '<span class="tag tag--accent">' + I('scroll') + O.esc(linked.length) + ' mission(s)</span>' +
                    (l.blip && l.blip.enabled ? '<span class="tag tag--info">' + I('map') + 'blip</span>' : '') +
                    (l.schedule && l.schedule.enabled ? '<span class="tag tag--warn">' + I('clock') + l.schedule.from + 'h–' + l.schedule.to + 'h</span>' : '') +
                    (linked.length ? '<span class="tag tag--muted">' + O.esc(linked.slice(0, 2).join(', ')) + (linked.length > 2 ? ' +' + (linked.length - 2) : '') + '</span>' : '<span class="tag tag--err">not linked</span>') +
                '</div></div>' +
                rowActions('location', l, (l.points || [])[0]) + '</div>';
        });
        return html + '</div>';
    }

    /* ═════════════════════════════ HOSTILES ═══════════════════════════ */
    function pageHostiles() {
        var list = (S.data.npcs || []).filter(function (n) {
            return matchSearch(n.name + ' ' + n.model + ' ' + n.uid);
        });

        if (!list.length) {
            return emptyState('skull', 'No hostile groups',
                'Evil NPCs spawn when a player gets close, fight back and drop loot when defeated.',
                '<button class="btn btn--primary" data-action="new" data-kind="npc">' + I('plus') + 'Create a group</button>');
        }

        var missionNames = {};
        (S.data.missions || []).forEach(function (m) { missionNames[m.uid] = m.name; });

        var html = '<div class="list">';
        list.forEach(function (n) {
            html += '<div class="row' + (n.enabled ? '' : ' is-off') + '">' +
                '<div class="row__icon">' + I('skull') + '</div>' +
                '<div class="row__main">' +
                '<div class="row__title">' + O.esc(n.name) +
                    (n.enabled ? '' : '<span class="tag tag--muted">disabled</span>') + '</div>' +
                '<div class="row__desc">' + O.esc(n.model) + ' · ' + O.esc(O.coordText(n.coords)) + '</div>' +
                '<div class="row__meta">' +
                    '<span class="tag tag--err">' + I('users') + (n.count || 1) + (n.companions ? ' +' + n.companions : '') + ' unit(s)</span>' +
                    '<span class="tag tag--warn">' + I('bolt') + O.esc(O.titleCase(n.difficulty)) + '</span>' +
                    '<span class="tag">' + I('target') + 'aggr ' + (n.aggression || 0) + '%</span>' +
                    '<span class="tag">' + I('clock') + 'respawn ' + O.duration(n.respawn) + '</span>' +
                    (n.alertPolice ? '<span class="tag tag--info">' + I('shield') + 'alerts police</span>' : '') +
                    ((n.loot || []).length ? '<span class="tag tag--ok">' + I('gift') + (n.loot || []).length + ' loot</span>' : '') +
                    (n.linkedMission ? '<span class="tag tag--accent">' + I('link') + O.esc(missionNames[n.linkedMission] || n.linkedMission) + '</span>' : '') +
                '</div></div>' +
                rowActions('npc', n, n.coords) + '</div>';
        });
        return html + '</div>';
    }

    /* ═══════════════════════════ ROW ACTIONS ══════════════════════════ */
    function rowActions(kind, entity, tpCoords) {
        var html = '<div class="row__actions">';
        if (tpCoords) {
            html += '<button class="icon-btn" title="Teleport here" data-action="tp" data-coords=\'' +
                O.esc(JSON.stringify(tpCoords)) + '\'>' + I('route') + '</button>';
        }
        html += '<button class="icon-btn" title="' + (entity.enabled ? 'Disable' : 'Enable') + '" data-action="toggle" data-kind="' +
            kind + '" data-uid="' + O.esc(entity.uid) + '" data-enabled="' + (entity.enabled ? '0' : '1') + '">' +
            I(entity.enabled ? 'power' : 'unlock') + '</button>';
        html += '<button class="icon-btn" title="Duplicate" data-action="duplicate" data-kind="' + kind +
            '" data-uid="' + O.esc(entity.uid) + '">' + I('copy') + '</button>';
        html += '<button class="icon-btn" title="Edit" data-action="edit" data-kind="' + kind +
            '" data-uid="' + O.esc(entity.uid) + '">' + I('edit') + '</button>';
        html += '<button class="icon-btn" title="Delete" data-action="delete" data-kind="' + kind +
            '" data-uid="' + O.esc(entity.uid) + '">' + I('trash') + '</button>';
        return html + '</div>';
    }

    function emptyState(iconName, title, text, action) {
        return '<div class="empty">' + I(iconName) + '<h3>' + O.esc(title) + '</h3><p>' + O.esc(text) + '</p>' +
            (action || '') + '</div>';
    }

    /* ══════════════════════════════ TREE ══════════════════════════════ */
    function pageTree() {
        var missions = S.data.missions || [];
        if (!missions.length) {
            return emptyState('tree', 'Nothing to chain yet', 'Create at least two missions and link them with prerequisites to build a progression tree.');
        }

        var byUid = {};
        missions.forEach(function (m) { byUid[m.uid] = m; });

        /* compute depth (tier) for every mission */
        var depth = {};
        function tierOf(uid, guard) {
            if (depth[uid] !== undefined) return depth[uid];
            guard = guard || {};
            if (guard[uid]) return 0;
            guard[uid] = true;
            var m = byUid[uid];
            if (!m || !(m.prerequisites || []).length) { depth[uid] = 0; return 0; }
            var max = 0;
            (m.prerequisites || []).forEach(function (dep) {
                if (byUid[dep]) max = Math.max(max, tierOf(dep, guard) + 1);
            });
            depth[uid] = max;
            return max;
        }
        missions.forEach(function (m) { tierOf(m.uid); });

        var tiers = {};
        missions.forEach(function (m) {
            var t = depth[m.uid] || 0;
            (tiers[t] = tiers[t] || []).push(m);
        });

        var keys = Object.keys(tiers).map(Number).sort(function (a, b) { return a - b; });
        var html = '<div class="tree">';
        keys.forEach(function (t) {
            html += '<div class="tree__tier"><div class="tree__tier-label">Tier ' + (t + 1) + '</div><div class="tree__nodes">';
            tiers[t].forEach(function (m) {
                var deps = (m.prerequisites || []).map(function (u) {
                    return byUid[u] ? byUid[u].name : u;
                });
                html += '<div class="node' + (m.enabled ? '' : ' is-off') + '" data-action="edit" data-kind="mission" data-uid="' +
                    O.esc(m.uid) + '">' +
                    '<div class="node__name">' + O.esc(m.name) + '</div>' +
                    '<div class="node__meta">' +
                        '<span class="tag tag--accent">+' + O.num(m.xpReward || 0) + ' XP</span>' +
                        (m.requiredLevel ? '<span class="tag tag--info">Lv ' + m.requiredLevel + '</span>' : '') +
                    '</div>' +
                    (deps.length ? '<div class="node__deps">Requires <b>' + O.esc(deps.join(', ')) + '</b></div>' : '') +
                    '</div>';
            });
            html += '</div></div>';
        });
        html += '</div>';

        html += '<div class="card" style="margin-top:10px"><div class="stat"><div class="stat__icon">' + I('info') + '</div><div>' +
            '<div class="card__title">How chaining works</div>' +
            '<div class="card__sub" style="line-height:1.6;margin-top:5px">Open a mission and add prerequisites on the <b>Progression</b> tab. ' +
            'A player only sees a mission once every prerequisite has been completed at least once. Circular chains are rejected on save.</div>' +
            '</div></div></div>';

        return html;
    }

    /* ════════════════════════════ PLAYERS ═════════════════════════════ */
    function pagePlayers() {
        var list = (S.data.players || []).filter(function (p) {
            return matchSearch(p.name + ' ' + p.identifier + ' ' + p.job);
        });

        if (!list.length) {
            return emptyState('users', 'No players online', 'Player levels, active runs and admin actions appear here as soon as somebody connects.');
        }

        var html = '<table class="table"><thead><tr>' +
            '<th>ID</th><th>Player</th><th>Job</th><th>Level</th><th>Progress</th><th>Active mission</th><th>Done</th><th style="text-align:right">Actions</th>' +
            '</tr></thead><tbody>';

        list.forEach(function (p) {
            html += '<tr>' +
                '<td class="mono">' + p.source + '</td>' +
                '<td><div style="font-weight:600;color:#fff">' + O.esc(p.name) + '</div>' +
                    '<div class="mono" style="font-size:10px">' + O.esc(p.identifier) + '</div></td>' +
                '<td><span class="tag">' + O.esc(p.job) + ' · ' + p.grade + '</span></td>' +
                '<td><span class="tag tag--accent">Lv ' + p.level + '</span></td>' +
                '<td style="min-width:130px"><div class="bar"><div class="bar__fill" style="width:' + (p.percent || 0) + '%"></div></div>' +
                    '<div class="mono" style="font-size:10px;margin-top:4px">' + O.num(p.xp) + ' XP</div></td>' +
                '<td>' + (p.active ? '<span class="tag tag--ok">' + O.esc(p.active) + '</span>' : '<span class="tag tag--muted">idle</span>') + '</td>' +
                '<td>' + O.num(p.completed) + '</td>' +
                '<td style="text-align:right"><div class="row__actions" style="justify-content:flex-end">' +
                    '<button class="icon-btn" title="Give 500 XP" data-action="player" data-pa="addxp" data-target="' + p.source + '" data-value="500">' + I('sparkle') + '</button>' +
                    '<button class="icon-btn" title="Set level" data-action="player-level" data-target="' + p.source + '">' + I('star') + '</button>' +
                    '<button class="icon-btn" title="Cancel active mission" data-action="player" data-pa="cancelmission" data-target="' + p.source + '">' + I('stop') + '</button>' +
                    '<button class="icon-btn" title="Reset all progress" data-action="player-reset" data-target="' + p.source + '">' + I('trash') + '</button>' +
                '</div></td></tr>';
        });

        return html + '</tbody></table>';
    }

    /* ══════════════════════════════ LOGS ══════════════════════════════ */
    function pageLogs() {
        var logs = S.data.logs || [];
        if (!logs.length) return emptyState('logs', 'No activity yet', 'Mission starts, completions, admin edits and denied access attempts all land here.');

        var html = '<table class="table"><thead><tr><th>When</th><th>Action</th><th>Player</th><th>Detail</th></tr></thead><tbody>';
        logs.forEach(function (l) {
            var detail = l.detail || '';
            if (detail.length > 110) detail = detail.slice(0, 110) + '…';
            html += '<tr><td class="mono" style="white-space:nowrap">' + O.timeAgo(l.created_at) + '</td>' +
                '<td><span class="tag ' + logTag(l.action) + '">' + O.esc(l.action) + '</span></td>' +
                '<td>' + O.esc(l.name || '—') + '</td>' +
                '<td class="mono">' + O.esc(detail) + '</td></tr>';
        });
        return html + '</tbody></table>';
    }

    /* ════════════════════════════ SETTINGS ════════════════════════════ */
    function pageSettings() {
        var d = S.data || {}, c = d.config || {}, b = d.branding || {};

        var html = '<div class="grid grid--2">';

        html += '<div class="card"><div class="card__head"><div><div class="card__title">Runtime</div>' +
            '<div class="card__sub">Values come from config.lua on the server</div></div>' + I('gear') + '</div>' +
            kv('Locale', c.locale) +
            kv('Progression', c.progression ? 'Enabled (max level ' + c.maxLevel + ')' : 'Disabled') +
            kv('Evil NPC system', c.evilNpc ? 'Enabled' : 'Disabled') +
            kv('Player journal', c.journal ? 'Enabled' : 'Disabled') +
            kv('Persistence', c.useDatabase ? 'MySQL (oxmysql)' : 'Config only (memory)') +
            kv('Database', (d.stats || {}).dbReady ? 'Connected' : 'Not connected') +
            '</div>';

        html += '<div class="card"><div class="card__head"><div><div class="card__title">Data tools</div>' +
            '<div class="card__sub">Back up or move your whole quest network</div></div>' + I('db') + '</div>' +
            '<div style="display:flex;flex-direction:column;gap:9px">' +
            '<button class="btn" data-action="export">' + I('download') + 'Export everything to JSON</button>' +
            '<button class="btn" data-action="import">' + I('upload') + 'Import from JSON</button>' +
            '<button class="btn" data-action="reload">' + I('refresh') + 'Reload data from database</button>' +
            '</div>' +
            '<div class="card__sub" style="margin-top:12px;line-height:1.6">Exports include every mission, location and hostile group. ' +
            'Import merges by <span class="mono">uid</span> — existing entries are overwritten.</div>' +
            '</div>';

        html += '</div>';

        html += '<div class="section-title">About</div>' +
            '<div class="card"><div class="stat"><div class="stat__icon">' + I('sparkle') + '</div><div>' +
            '<div class="stat__val" style="font-size:18px">' + O.esc(b.brand || 'OQV2 QUESTS') + ' <span style="font-size:12px;color:var(--txt-3)">v' + O.esc(b.version || '2.0.0') + '</span></div>' +
            '<div class="card__sub" style="margin-top:6px;line-height:1.7">' + O.esc(b.subtitle || '') + '<br>' +
            'Author: <b style="color:var(--txt-1)">' + O.esc(b.author || '') + '</b><br>' +
            '<span style="background:linear-gradient(90deg,var(--accent),var(--accent-alt));-webkit-background-clip:text;background-clip:text;color:transparent;font-weight:700">' +
            O.esc(b.footer || 'Made with CodeX Dev.') + '</span></div>' +
            '</div></div>' +
            '<div class="card__sub" style="margin-top:14px;line-height:1.7">Requirements: es_extended · ox_lib · ox_inventory · ox_target · oxmysql<br>' +
            'Admin command: <span class="mono">/oqv2</span> — restricted to the groups, ACE permission and identifiers set in <span class="mono">config.lua</span>.</div>' +
            '</div>';

        return html;
    }

    function kv(label, value) {
        return '<div style="display:flex;justify-content:space-between;gap:14px;padding:8px 0;border-bottom:1px solid var(--line-soft)">' +
            '<span style="font-size:12px;color:var(--txt-3)">' + O.esc(label) + '</span>' +
            '<span style="font-size:12px;color:var(--txt-1);font-weight:600">' + O.esc(value) + '</span></div>';
    }

    /* ═══════════════════════════ RENDERER ═════════════════════════════ */
    var RENDERERS = {
        dashboard: pageDashboard,
        missions: pageMissions,
        locations: pageLocations,
        hostiles: pageHostiles,
        tree: pageTree,
        players: pagePlayers,
        logs: pageLogs,
        settings: pageSettings
    };

    function render() {
        if (!S.data) return;
        var meta = pageMeta(S.page);
        O.$('#page-title').textContent = meta.title;
        O.$('#page-sub').textContent = meta.sub;
        O.$('#page-tools').innerHTML = tools(S.page);
        renderNav();

        var fn = RENDERERS[S.page] || pageDashboard;
        var html = '';
        try {
            html = fn();
        } catch (err) {
            console.error('[OQV2] page render failed', err);
            html = emptyState('warn', 'Render error', String(err && err.message || err));
        }
        O.$('#content').innerHTML = html;
        O.$('#content').scrollTop = 0;

        var si = O.$('#search-input');
        if (si) {
            si.addEventListener('input', function () {
                S.search = si.value;
                var pos = si.selectionStart;
                render();
                var again = O.$('#search-input');
                if (again) { again.focus(); again.setSelectionRange(pos, pos); }
            });
        }
    }

    function goto(page) {
        if (S.page === page) return;
        S.page = page;
        S.search = '';
        render();
    }

    w.OQAdmin = {
        PAGES: PAGES,
        render: render,
        goto: goto,
        renderNav: renderNav,
        emptyState: emptyState
    };
})(window);
