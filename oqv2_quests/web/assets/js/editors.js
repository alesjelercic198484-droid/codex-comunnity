/* OQV2 QUESTS — Entity editors (mission / location / evil npc)
   Made with CodeX Dev. */
(function (w) {
    'use strict';

    var O = w.OQ, I = w.OQIcon, S = w.OQ.State;

    var TABS = {
        mission:  ['General', 'Objectives', 'Requirements', 'Rewards', 'Access', 'Progression', 'Alert'],
        location: ['General', 'Entity', 'Positions', 'Interaction', 'Map & Time', 'Missions'],
        npc:      ['General', 'Combat', 'Spawn', 'Loot']
    };

    var TITLES = {
        mission:  { icon: 'scroll', label: 'Mission' },
        location: { icon: 'pin',    label: 'Location' },
        npc:      { icon: 'skull',  label: 'Hostile group' }
    };

    /* ─────────────────────────── DRAFT HELPERS ─────────────────────── */
    function defaults(kind) {
        var d = O.getPath(S.data, 'schema.defaults', {});
        var base = kind === 'mission' ? d.mission : kind === 'location' ? d.location : d.npc;
        var draft = O.clone(base || {});
        draft.uid = '';
        draft.meta = { createdBy: '', createdAt: 0, updatedAt: 0 };
        if (kind === 'mission') {
            draft.objectives = [];
            draft.prerequisites = [];
            draft.requirements = draft.requirements || { items: [], money: 0 };
            draft.requirements.items = [];
            draft.rewards = draft.rewards || {};
            draft.rewards.items = [];
        }
        if (kind === 'location') { draft.points = []; draft.missions = []; }
        if (kind === 'npc') { draft.loot = []; draft.weapons = ['WEAPON_PISTOL']; }
        return draft;
    }

    function findEntity(kind, uid) {
        var list = kind === 'mission' ? S.data.missions : kind === 'location' ? S.data.locations : S.data.npcs;
        for (var i = 0; i < (list || []).length; i++) if (list[i].uid === uid) return list[i];
        return null;
    }

    /** Push the current form values into the draft (called before any re-render). */
    function commit() {
        var body = O.$('#modal-body');
        if (!body || !S.draft) return;
        O.$$('[data-key]', body).forEach(function (el) {
            var path = el.getAttribute('data-key');
            var val;
            if (el.type === 'checkbox') val = el.checked;
            else if (el.type === 'number') val = el.value === '' ? 0 : Number(el.value);
            else val = el.value;
            O.setPath(S.draft, path, val);
        });
    }

    /* ─────────────────────────── OPEN / RENDER ─────────────────────── */
    function open(kind, uid) {
        if (!TABS[kind]) return;
        S.draftKind = kind;
        S.draftTab = 0;
        S.draft = uid ? O.clone(findEntity(kind, uid) || defaults(kind)) : defaults(kind);
        if (!S.draft.uid && uid) S.draft.uid = uid;
        renderModal();
    }

    function renderModal() {
        var kind = S.draftKind, t = TITLES[kind];
        var isNew = !S.draft.uid;

        O.Modal.open({
            title: (isNew ? 'New ' : 'Edit ') + t.label,
            subtitle: isNew ? 'Fill in the tabs below — everything can be changed later.'
                            : 'uid: ' + S.draft.uid,
            tabs: tabsHtml(),
            body: bodyHtml(),
            foot: footHtml(isNew)
        });
    }

    function tabsHtml() {
        return TABS[S.draftKind].map(function (label, i) {
            return '<button class="tab' + (i === S.draftTab ? ' is-active' : '') +
                '" data-action="tab" data-tab="' + i + '">' + O.esc(label) + '</button>';
        }).join('');
    }

    function footHtml(isNew) {
        return '<button class="btn btn--ghost" data-action="modal-close">Cancel</button>' +
            '<div class="spacer"></div>' +
            (isNew ? '' : '<button class="btn btn--danger" data-action="delete" data-kind="' + S.draftKind +
                '" data-uid="' + O.esc(S.draft.uid) + '">' + I('trash') + 'Delete</button>') +
            '<button class="btn btn--primary" data-action="save">' + I('save') + (isNew ? 'Create' : 'Save changes') + '</button>';
    }

    function setTab(i) {
        commit();
        S.draftTab = Number(i) || 0;
        O.Modal.setTabs(tabsHtml());
        O.Modal.setBody(bodyHtml());
    }

    function refresh() {
        commit();
        O.Modal.setBody(bodyHtml());
    }

    /* ─────────────────────────────── BODY ──────────────────────────── */
    function bodyHtml() {
        var k = S.draftKind;
        if (k === 'mission')  return missionTab(S.draftTab);
        if (k === 'location') return locationTab(S.draftTab);
        return npcTab(S.draftTab);
    }

    function opts(list) {
        return (list || []).map(function (o) {
            return { value: o.value !== undefined ? o.value : o, label: o.label !== undefined ? o.label : O.titleCase(o) };
        });
    }

    function schema(key) { return O.getPath(S.data, 'schema.' + key, []); }

    /* ══════════════════════════ MISSION TABS ═══════════════════════════ */
    function missionTab(tab) {
        var m = S.draft;

        /* 0 — GENERAL */
        if (tab === 0) {
            return '<div class="form-grid">' +
                O.field('Mission name', O.input('name', m.name, { placeholder: 'Scrap Trade' }), null, 'span-2') +
                O.field('Description', O.textarea('description', m.description, 'What the player is told about this job…'), null, 'span-2') +
                O.field('Category', O.select('category', m.category, opts(schema('categories')))) +
                O.field('Icon', O.select('icon', m.icon, opts(['scroll', 'box', 'truck', 'money', 'skull', 'shield', 'star', 'bolt', 'crosshair', 'recycle', 'hand', 'gift', 'flag']))) +
                O.field('Sort order', O.input('order', m.order, { type: 'number' }), 'Lower shows first in lists') +
                '<div class="field">' + O.toggle('enabled', m.enabled, 'Mission enabled') + '</div>' +
                '</div>';
        }

        /* 1 — OBJECTIVES */
        if (tab === 1) {
            var html = '<div class="subcard__head" style="margin-bottom:12px">' +
                '<div class="subcard__title">' + I('list') + 'Objectives (' + (m.objectives || []).length + ')</div>' +
                '<button class="btn btn--sm btn--primary" data-action="obj-add">' + I('plus') + 'Add objective</button></div>';

            if (!(m.objectives || []).length) {
                return html + '<div class="empty" style="padding:40px">' + I('list') +
                    '<h3>No objectives</h3><p>Every mission needs at least one objective. Add a hand-over, a delivery, a kill target or a timed task.</p></div>';
            }

            (m.objectives || []).forEach(function (obj, i) {
                var type = obj.type || 'goto';
                var needsItem = ['give_item', 'collect', 'deliver'].indexOf(type) > -1;
                var needsCoords = ['goto', 'deliver', 'interact', 'wait'].indexOf(type) > -1;
                var needsTimer = ['interact', 'wait'].indexOf(type) > -1;

                html += '<div class="subcard"><div class="subcard__head">' +
                    '<div class="subcard__title"><span class="subcard__num">' + (i + 1) + '</span>' +
                    O.titleCase(type) + '</div>' +
                    '<div class="row__actions">' +
                    (i > 0 ? '<button class="icon-btn" title="Move up" data-action="obj-move" data-index="' + i + '" data-dir="-1">' + I('chevron') + '</button>' : '') +
                    '<button class="icon-btn" title="Remove" data-action="obj-del" data-index="' + i + '">' + I('trash') + '</button>' +
                    '</div></div>' +
                    '<div class="form-grid form-grid--3">' +
                    O.field('Type', O.select('objectives.' + i + '.type', type, opts(schema('objectiveTypes')))) +
                    O.field('Label shown to the player', O.input('objectives.' + i + '.label', obj.label), null, 'span-2') +
                    (needsItem ? O.field('Item name', O.input('objectives.' + i + '.item', obj.item, { placeholder: 'scrapmetal' })) : '') +
                    (needsItem ? O.field('Amount', O.input('objectives.' + i + '.count', obj.count, { type: 'number', min: 1 })) : '') +
                    (type === 'kill' ? O.field('Kills required', O.input('objectives.' + i + '.amount', obj.amount, { type: 'number', min: 1 })) : '') +
                    (type === 'kill' ? O.field('Ped model / group uid', O.input('objectives.' + i + '.model', obj.model, { placeholder: 'g_m_y_ballasout_01' })) : '') +
                    (type === 'pay' ? O.field('Amount to pay', O.input('objectives.' + i + '.money', obj.money, { type: 'number', min: 1 })) : '') +
                    (needsTimer ? O.field('Duration (ms)', O.input('objectives.' + i + '.duration', obj.duration, { type: 'number', min: 500, step: 500 })) : '') +
                    (needsCoords ? O.field('Radius (m)', O.input('objectives.' + i + '.radius', obj.radius, { type: 'number', min: 0.5, step: 0.5 })) : '') +
                    '</div>';

                if (needsCoords) {
                    html += '<div class="form-grid form-grid--3" style="margin-top:12px">' +
                        O.field('X', O.input('objectives.' + i + '.coords.x', O.getPath(obj, 'coords.x', 0), { type: 'number', step: 0.01 })) +
                        O.field('Y', O.input('objectives.' + i + '.coords.y', O.getPath(obj, 'coords.y', 0), { type: 'number', step: 0.01 })) +
                        O.field('Z', O.input('objectives.' + i + '.coords.z', O.getPath(obj, 'coords.z', 0), { type: 'number', step: 0.01 })) +
                        '</div>' +
                        '<div style="display:flex;gap:8px;margin-top:10px;flex-wrap:wrap">' +
                        '<button class="btn btn--sm" data-action="coords-here" data-target="objectives.' + i + '.coords">' + I('pin') + 'Use my position</button>' +
                        '<button class="btn btn--sm" data-action="coords-pick" data-target="objectives.' + i + '.coords">' + I('target') + 'Pick in game</button>' +
                        '<button class="btn btn--sm" data-action="coords-waypoint" data-target="objectives.' + i + '.coords">' + I('map') + 'Use map waypoint</button>' +
                        '</div>';
                }

                if (needsTimer) {
                    html += '<div class="form-grid form-grid--3" style="margin-top:12px">' +
                        O.field('Anim dictionary', O.input('objectives.' + i + '.anim.dict', O.getPath(obj, 'anim.dict', ''), { placeholder: 'anim@heists@box_carry@' })) +
                        O.field('Anim clip', O.input('objectives.' + i + '.anim.clip', O.getPath(obj, 'anim.clip', ''), { placeholder: 'idle' })) +
                        O.field('Anim flag', O.input('objectives.' + i + '.anim.flag', O.getPath(obj, 'anim.flag', 49), { type: 'number' })) +
                        '</div>';
                }

                html += '<div style="display:flex;gap:18px;margin-top:12px;flex-wrap:wrap">' +
                    O.toggle('objectives.' + i + '.optional', obj.optional, 'Optional') +
                    O.toggle('objectives.' + i + '.marker', obj.marker !== false, 'Show marker') +
                    O.toggle('objectives.' + i + '.blip', obj.blip !== false, 'Show blip & route') +
                    '</div></div>';
            });

            return html;
        }

        /* 2 — REQUIREMENTS */
        if (tab === 2) {
            var req = m.requirements || {};
            var h = '<div class="card__sub" style="margin-bottom:14px;line-height:1.6">Consumed when the mission <b>starts</b>. Leave empty for a free mission.</div>';
            h += '<div class="form-grid">' +
                O.field('Cash required', O.input('requirements.money', req.money || 0, { type: 'number', min: 0 }), 'Removed from the player on start') +
                '</div>';

            h += '<div class="section-title">Required items</div>' +
                '<button class="btn btn--sm" data-action="reqitem-add">' + I('plus') + 'Add required item</button>';

            (req.items || []).forEach(function (it, i) {
                h += '<div class="subcard" style="margin-top:10px"><div class="form-grid form-grid--3">' +
                    O.field('Item', O.input('requirements.items.' + i + '.name', it.name, { placeholder: 'water' })) +
                    O.field('Amount', O.input('requirements.items.' + i + '.count', it.count, { type: 'number', min: 1 })) +
                    '<div class="field" style="justify-content:flex-end">' +
                        O.toggle('requirements.items.' + i + '.remove', it.remove !== false, 'Consume on start') +
                    '</div></div>' +
                    '<button class="btn btn--sm btn--danger" style="margin-top:10px" data-action="reqitem-del" data-index="' + i + '">' +
                    I('trash') + 'Remove</button></div>';
            });

            return h;
        }

        /* 3 — REWARDS */
        if (tab === 3) {
            var rw = m.rewards || {};
            var h = '<div class="form-grid form-grid--3">' +
                O.field('Cash', O.input('rewards.money', rw.money || 0, { type: 'number', min: 0 })) +
                O.field('Bank', O.input('rewards.bank', rw.bank || 0, { type: 'number', min: 0 })) +
                O.field('Dirty money', O.input('rewards.black', rw.black || 0, { type: 'number', min: 0 })) +
                '</div>';

            h += '<div class="section-title">Item rewards</div>' +
                '<button class="btn btn--sm" data-action="rwitem-add">' + I('plus') + 'Add item reward</button>';

            (rw.items || []).forEach(function (it, i) {
                h += '<div class="subcard" style="margin-top:10px"><div class="form-grid form-grid--3">' +
                    O.field('Item', O.input('rewards.items.' + i + '.name', it.name, { placeholder: 'bandage' })) +
                    O.field('Amount', O.input('rewards.items.' + i + '.count', it.count, { type: 'number', min: 1 })) +
                    O.field('Chance %', O.input('rewards.items.' + i + '.chance', it.chance === undefined ? 100 : it.chance, { type: 'number', min: 1, max: 100 })) +
                    '</div><button class="btn btn--sm btn--danger" style="margin-top:10px" data-action="rwitem-del" data-index="' + i + '">' +
                    I('trash') + 'Remove</button></div>';
            });

            return h;
        }

        /* 4 — ACCESS */
        if (tab === 4) {
            var rs = m.restriction || {}, cd = m.cooldown || {}, sc = m.schedule || {};
            var presets = O.getPath(S.data, 'schema.cooldownPresets', {});
            return '<div class="form-grid">' +
                O.field('Who can take it', O.select('restriction.type', rs.type, opts(schema('restrictionTypes')))) +
                O.field('Job / gang / business name', O.input('restriction.job', rs.job || '', { placeholder: 'police' }), 'Used for job, gang and business restrictions') +
                O.field('Minimum grade', O.input('restriction.grade', rs.grade || 0, { type: 'number', min: 0 })) +
                O.field('Minimum level (level restriction)', O.input('restriction.level', rs.level || 0, { type: 'number', min: 0 })) +
                '</div>' +
                '<div class="section-title">Repetition</div>' +
                '<div class="form-grid">' +
                O.field('Repeat', O.select('cooldown.type', cd.type, opts(schema('repeatTypes')))) +
                O.field('Custom cooldown (seconds)', O.input('cooldown.seconds', cd.seconds || 0, { type: 'number', min: 0 }),
                    'Only used when repeat = custom. Presets: ' + Object.keys(presets).join(', ')) +
                '</div>' +
                '<div class="section-title">Time window (in-game hours)</div>' +
                '<div class="form-grid form-grid--3">' +
                '<div class="field">' + O.toggle('schedule.enabled', sc.enabled, 'Only available at certain hours') + '</div>' +
                O.field('From', O.input('schedule.from', sc.from || 0, { type: 'number', min: 0, max: 24 })) +
                O.field('To', O.input('schedule.to', sc.to === undefined ? 24 : sc.to, { type: 'number', min: 0, max: 24 })) +
                '</div>';
        }

        /* 5 — PROGRESSION */
        if (tab === 5) {
            var h = '<div class="form-grid">' +
                O.field('XP reward', O.input('xpReward', m.xpReward || 0, { type: 'number', min: 0 })) +
                O.field('Required level', O.input('requiredLevel', m.requiredLevel || 0, { type: 'number', min: 0 })) +
                '</div>';

            h += '<div class="section-title">Prerequisites — chain your missions</div>' +
                '<div class="card__sub" style="margin-bottom:12px;line-height:1.6">Click a mission to require it. Players only unlock this one once every selected mission has been completed.</div>' +
                '<div class="chips">';

            var others = (S.data.missions || []).filter(function (x) { return x.uid !== m.uid; });
            if (!others.length) {
                h += '<span class="card__sub">No other missions to chain yet.</span>';
            }
            others.forEach(function (x) {
                var on = (m.prerequisites || []).indexOf(x.uid) > -1;
                h += '<button class="chip' + (on ? ' is-on' : '') + '" data-action="prereq" data-uid="' + O.esc(x.uid) + '">' +
                    (on ? I('check') : I('plus')) + O.esc(x.name) + '</button>';
            });
            h += '</div>';
            return h;
        }

        /* 6 — ALERT */
        var al = m.alert || {};
        return '<div class="card__sub" style="margin-bottom:14px;line-height:1.6">Shown on screen the moment the player accepts the mission.</div>' +
            '<div class="form-grid">' +
            O.field('Alert title', O.input('alert.title', al.title, { placeholder: m.name }), null, 'span-2') +
            O.field('Alert description', O.textarea('alert.description', al.description, 'Short punchy line…'), null, 'span-2') +
            O.field('Sound', O.select('alert.sound', al.sound, opts([
                { value: 'none', label: 'No sound' },
                { value: 'quest_start', label: 'Quest start' },
                { value: 'quest_alert', label: 'Danger alert' }
            ]))) +
            O.field('Duration (ms)', O.input('alert.duration', al.duration || 6000, { type: 'number', min: 1000, step: 500 })) +
            '</div>';
    }

    /* ══════════════════════════ LOCATION TABS ══════════════════════════ */
    function locationTab(tab) {
        var l = S.draft;

        if (tab === 0) {
            return '<div class="form-grid">' +
                O.field('Location name', O.input('name', l.name, { placeholder: 'Old Marco' }), null, 'span-2') +
                O.field('Internal notes', O.textarea('description', l.description, 'Only visible in this panel'), null, 'span-2') +
                '<div class="field">' + O.toggle('enabled', l.enabled, 'Location enabled') + '</div>' +
                '</div>';
        }

        if (tab === 1) {
            var e = l.entity || {};
            return '<div class="form-grid">' +
                O.field('Type', O.select('entity.type', e.type, opts(schema('entityTypes')))) +
                O.field('Model', O.input('entity.model', e.model, { placeholder: 'a_m_m_business_01' }),
                    'Ped model, prop name — ignored for marker type') +
                O.field('Scenario (peds)', O.input('entity.scenario', e.scenario || '', { placeholder: 'WORLD_HUMAN_CLIPBOARD' })) +
                O.field('Anim dictionary', O.input('entity.anim.dict', O.getPath(e, 'anim.dict', ''), { placeholder: 'amb@world_human_bum_standing@twitchy@idle_a' })) +
                O.field('Anim clip', O.input('entity.anim.clip', O.getPath(e, 'anim.clip', ''), { placeholder: 'idle_a' })) +
                '<div class="field" style="gap:12px;justify-content:center">' +
                    O.toggle('entity.freeze', e.freeze !== false, 'Freeze in place') +
                    O.toggle('entity.invincible', e.invincible !== false, 'Invincible') +
                    O.toggle('entity.ignore', e.ignore !== false, 'Ignore events (never flees)') +
                '</div>' +
                '<div class="field span-2"><button class="btn btn--sm" data-action="preview-model">' + I('eye') +
                    'Preview this model in game</button></div>' +
                '</div>';
        }

        if (tab === 2) {
            var h = '<div class="subcard__head" style="margin-bottom:12px">' +
                '<div class="subcard__title">' + I('pin') + 'Spawn points (' + (l.points || []).length + ')</div>' +
                '<div style="display:flex;gap:8px">' +
                '<button class="btn btn--sm" data-action="point-here">' + I('pin') + 'Add my position</button>' +
                '<button class="btn btn--sm btn--primary" data-action="point-pick">' + I('target') + 'Pick in game</button>' +
                '</div></div>';

            if (!(l.points || []).length) {
                h += '<div class="empty" style="padding:38px">' + I('pin') + '<h3>No positions</h3>' +
                    '<p>Add at least one spawn point. Add several and enable rotation to make the giver move around.</p></div>';
            }

            (l.points || []).forEach(function (p, i) {
                h += '<div class="subcard"><div class="subcard__head">' +
                    '<div class="subcard__title"><span class="subcard__num">' + (i + 1) + '</span>Position</div>' +
                    '<div class="row__actions">' +
                    '<button class="icon-btn" title="Teleport here" data-action="tp" data-coords=\'' + O.esc(JSON.stringify(p)) + '\'>' + I('route') + '</button>' +
                    '<button class="icon-btn" title="Remove" data-action="point-del" data-index="' + i + '">' + I('trash') + '</button>' +
                    '</div></div>' +
                    '<div class="form-grid form-grid--3">' +
                    O.field('X', O.input('points.' + i + '.x', p.x, { type: 'number', step: 0.01 })) +
                    O.field('Y', O.input('points.' + i + '.y', p.y, { type: 'number', step: 0.01 })) +
                    O.field('Z', O.input('points.' + i + '.z', p.z, { type: 'number', step: 0.01 })) +
                    O.field('Heading', O.input('points.' + i + '.w', p.w, { type: 'number', step: 0.01 })) +
                    '</div></div>';
            });

            h += '<div class="section-title">Rotation</div><div class="form-grid">' +
                '<div class="field">' + O.toggle('rotate.enabled', O.getPath(l, 'rotate.enabled', false), 'Rotate between positions') + '</div>' +
                O.field('Interval (seconds)', O.input('rotate.interval', O.getPath(l, 'rotate.interval', 1800), { type: 'number', min: 30 }),
                    'Every client picks the same position from the server clock') +
                '</div>';
            return h;
        }

        if (tab === 3) {
            var t = l.target || {}, dg = l.dialogue || {};
            return '<div class="form-grid">' +
                O.field('Target label', O.input('target.label', t.label, { placeholder: 'Talk to Marco' })) +
                O.field('Target icon (Font Awesome)', O.input('target.icon', t.icon, { placeholder: 'fa-solid fa-comments' })) +
                O.field('Interaction distance', O.input('target.distance', t.distance, { type: 'number', min: 0.5, max: 8, step: 0.1 })) +
                '</div>' +
                '<div class="section-title">Dialogue</div>' +
                '<div class="form-grid">' +
                O.field('Menu title', O.input('dialogue.title', dg.title, { placeholder: 'Old Marco' }), null, 'span-2') +
                O.field('Intro text', O.textarea('dialogue.text', dg.text, 'What the NPC says before showing the missions…'), null, 'span-2') +
                O.field('Accept label', O.input('dialogue.accept', dg.accept, { placeholder: 'What do you need?' })) +
                O.field('Decline label', O.input('dialogue.decline', dg.decline, { placeholder: 'Not today' })) +
                '</div>';
        }

        if (tab === 4) {
            var b = l.blip || {}, sc = l.schedule || {};
            return '<div class="form-grid">' +
                '<div class="field">' + O.toggle('blip.enabled', b.enabled !== false, 'Show a map blip') + '</div>' +
                O.field('Blip label', O.input('blip.label', b.label || '', { placeholder: l.name })) +
                O.field('Sprite id', O.input('blip.sprite', b.sprite, { type: 'number', min: 1 })) +
                O.field('Colour id', O.input('blip.color', b.color, { type: 'number', min: 0 })) +
                O.field('Scale', O.input('blip.scale', b.scale, { type: 'number', min: 0.2, max: 2, step: 0.1 })) +
                '<div class="field">' + O.toggle('blip.shortRange', b.shortRange !== false, 'Short range') + '</div>' +
                '</div>' +
                '<div class="section-title">Availability (in-game hours)</div>' +
                '<div class="form-grid form-grid--3">' +
                '<div class="field">' + O.toggle('schedule.enabled', sc.enabled, 'Only spawn at certain hours') + '</div>' +
                O.field('From', O.input('schedule.from', sc.from || 0, { type: 'number', min: 0, max: 24 })) +
                O.field('To', O.input('schedule.to', sc.to === undefined ? 24 : sc.to, { type: 'number', min: 0, max: 24 })) +
                '</div>';
        }

        /* 5 — MISSIONS */
        var h2 = '<div class="card__sub" style="margin-bottom:12px;line-height:1.6">Pick every mission this giver should offer. Players see them in order, locked ones show the reason why.</div><div class="chips">';
        var all = S.data.missions || [];
        if (!all.length) h2 += '<span class="card__sub">Create a mission first.</span>';
        all.forEach(function (x) {
            var on = (l.missions || []).indexOf(x.uid) > -1;
            h2 += '<button class="chip' + (on ? ' is-on' : '') + '" data-action="linkmission" data-uid="' + O.esc(x.uid) + '">' +
                (on ? I('check') : I('plus')) + O.esc(x.name) + '</button>';
        });
        return h2 + '</div>';
    }

    /* ════════════════════════════ NPC TABS ═════════════════════════════ */
    function npcTab(tab) {
        var n = S.draft;

        if (tab === 0) {
            return '<div class="form-grid">' +
                O.field('Group name', O.input('name', n.name, { placeholder: 'Block Crew' }), null, 'span-2') +
                O.field('Ped model', O.input('model', n.model, { placeholder: 'g_m_y_ballasout_01' })) +
                O.field('Linked mission (optional)', O.select('linkedMission', n.linkedMission || '',
                    [{ value: '', label: 'Always spawn' }].concat((S.data.missions || []).map(function (m) {
                        return { value: m.uid, label: m.name };
                    }))), 'When set, the group only spawns while that mission is active') +
                O.field('Main units', O.input('count', n.count, { type: 'number', min: 1, max: 12 })) +
                O.field('Companions', O.input('companions', n.companions, { type: 'number', min: 0, max: 8 })) +
                '<div class="field">' + O.toggle('enabled', n.enabled, 'Group enabled') + '</div>' +
                '<div class="field"><button class="btn btn--sm" data-action="preview-model">' + I('eye') + 'Preview model in game</button></div>' +
                '</div>';
        }

        if (tab === 1) {
            var h = '<div class="form-grid">' +
                O.field('Difficulty', O.select('difficulty', n.difficulty, opts(schema('difficulties')))) +
                O.field('Aggression %', O.input('aggression', n.aggression, { type: 'number', min: 0, max: 100 })) +
                O.field('XP per kill', O.input('xp', n.xp, { type: 'number', min: 0 })) +
                O.field('Respawn (seconds)', O.input('respawn', n.respawn, { type: 'number', min: 0 })) +
                '<div class="field">' + O.toggle('alertPolice', n.alertPolice, 'Alert the police when engaged') + '</div>' +
                '</div>';

            h += '<div class="section-title">Weapons</div>' +
                '<div class="chips">';
            var pool = ['WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_SNSPISTOL', 'WEAPON_MICROSMG', 'WEAPON_SMG',
                        'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_MACHETE', 'WEAPON_BAT'];
            var current = n.weapons || [];
            current.forEach(function (wp) { if (pool.indexOf(wp) === -1) pool.push(wp); });
            pool.forEach(function (wp) {
                var on = current.indexOf(wp) > -1;
                h += '<button class="chip' + (on ? ' is-on' : '') + '" data-action="weapon" data-weapon="' + O.esc(wp) + '">' +
                    (on ? I('check') : I('plus')) + O.esc(wp.replace('WEAPON_', '')) + '</button>';
            });
            h += '</div>';
            return h;
        }

        if (tab === 2) {
            return '<div class="form-grid form-grid--3">' +
                O.field('X', O.input('coords.x', O.getPath(n, 'coords.x', 0), { type: 'number', step: 0.01 })) +
                O.field('Y', O.input('coords.y', O.getPath(n, 'coords.y', 0), { type: 'number', step: 0.01 })) +
                O.field('Z', O.input('coords.z', O.getPath(n, 'coords.z', 0), { type: 'number', step: 0.01 })) +
                '</div>' +
                '<div style="display:flex;gap:8px;margin-top:12px;flex-wrap:wrap">' +
                '<button class="btn btn--sm" data-action="coords-here" data-target="coords">' + I('pin') + 'Use my position</button>' +
                '<button class="btn btn--sm" data-action="coords-pick" data-target="coords">' + I('target') + 'Pick in game</button>' +
                '<button class="btn btn--sm" data-action="coords-waypoint" data-target="coords">' + I('map') + 'Use map waypoint</button>' +
                '<button class="btn btn--sm" data-action="tp" data-coords=\'' + O.esc(JSON.stringify(n.coords || {})) + '\'>' + I('route') + 'Teleport there</button>' +
                '</div>' +
                '<div class="section-title">Spawn behaviour</div>' +
                '<div class="form-grid">' +
                O.field('Patrol radius (m)', O.input('radius', n.radius, { type: 'number', min: 2, max: 200, step: 1 })) +
                O.field('Trigger distance (m)', O.input('trigger.distance', O.getPath(n, 'trigger.distance', 90), { type: 'number', min: 10, max: 400 }),
                    'How close a player must get before the group spawns') +
                '</div>';
        }

        /* 3 — LOOT */
        var lh = '<div class="form-grid form-grid--3">' +
            O.field('Min cash drop', O.input('money.min', O.getPath(n, 'money.min', 0), { type: 'number', min: 0 })) +
            O.field('Max cash drop', O.input('money.max', O.getPath(n, 'money.max', 0), { type: 'number', min: 0 })) +
            '</div>';

        lh += '<div class="section-title">Loot table</div>' +
            '<button class="btn btn--sm" data-action="loot-add">' + I('plus') + 'Add loot item</button>';

        (n.loot || []).forEach(function (it, i) {
            lh += '<div class="subcard" style="margin-top:10px"><div class="form-grid form-grid--3">' +
                O.field('Item', O.input('loot.' + i + '.name', it.name, { placeholder: 'weapon_ammo' })) +
                O.field('Amount', O.input('loot.' + i + '.count', it.count, { type: 'number', min: 1 })) +
                O.field('Chance %', O.input('loot.' + i + '.chance', it.chance, { type: 'number', min: 1, max: 100 })) +
                '</div><button class="btn btn--sm btn--danger" style="margin-top:10px" data-action="loot-del" data-index="' + i + '">' +
                I('trash') + 'Remove</button></div>';
        });

        return lh;
    }

    /* ═══════════════════════════ MUTATIONS ═════════════════════════════ */
    var Actions = {
        'tab': function (el) { setTab(el.getAttribute('data-tab')); },

        'obj-add': function () {
            commit();
            var def = O.clone(O.getPath(S.data, 'schema.defaults.objective', {}));
            def.id = O.uid('obj');
            def.type = 'goto';
            def.label = 'Objective #' + ((S.draft.objectives || []).length + 1);
            def.coords = { x: 0, y: 0, z: 0 };
            S.draft.objectives = S.draft.objectives || [];
            S.draft.objectives.push(def);
            O.Modal.setBody(bodyHtml());
        },
        'obj-del': function (el) {
            commit();
            S.draft.objectives.splice(Number(el.getAttribute('data-index')), 1);
            O.Modal.setBody(bodyHtml());
        },
        'obj-move': function (el) {
            commit();
            var i = Number(el.getAttribute('data-index')), dir = Number(el.getAttribute('data-dir'));
            var j = i + dir;
            if (j < 0 || j >= S.draft.objectives.length) return;
            var tmp = S.draft.objectives[i];
            S.draft.objectives[i] = S.draft.objectives[j];
            S.draft.objectives[j] = tmp;
            O.Modal.setBody(bodyHtml());
        },

        'reqitem-add': function () {
            commit();
            S.draft.requirements = S.draft.requirements || {};
            S.draft.requirements.items = S.draft.requirements.items || [];
            S.draft.requirements.items.push({ name: '', count: 1, remove: true });
            O.Modal.setBody(bodyHtml());
        },
        'reqitem-del': function (el) {
            commit();
            S.draft.requirements.items.splice(Number(el.getAttribute('data-index')), 1);
            O.Modal.setBody(bodyHtml());
        },

        'rwitem-add': function () {
            commit();
            S.draft.rewards = S.draft.rewards || {};
            S.draft.rewards.items = S.draft.rewards.items || [];
            S.draft.rewards.items.push({ name: '', count: 1, chance: 100 });
            O.Modal.setBody(bodyHtml());
        },
        'rwitem-del': function (el) {
            commit();
            S.draft.rewards.items.splice(Number(el.getAttribute('data-index')), 1);
            O.Modal.setBody(bodyHtml());
        },

        'loot-add': function () {
            commit();
            S.draft.loot = S.draft.loot || [];
            S.draft.loot.push({ name: '', count: 1, chance: 50 });
            O.Modal.setBody(bodyHtml());
        },
        'loot-del': function (el) {
            commit();
            S.draft.loot.splice(Number(el.getAttribute('data-index')), 1);
            O.Modal.setBody(bodyHtml());
        },

        'prereq': function (el) {
            commit();
            var uid = el.getAttribute('data-uid');
            S.draft.prerequisites = S.draft.prerequisites || [];
            var i = S.draft.prerequisites.indexOf(uid);
            if (i > -1) S.draft.prerequisites.splice(i, 1); else S.draft.prerequisites.push(uid);
            O.Modal.setBody(bodyHtml());
        },

        'linkmission': function (el) {
            commit();
            var uid = el.getAttribute('data-uid');
            S.draft.missions = S.draft.missions || [];
            var i = S.draft.missions.indexOf(uid);
            if (i > -1) S.draft.missions.splice(i, 1); else S.draft.missions.push(uid);
            O.Modal.setBody(bodyHtml());
        },

        'weapon': function (el) {
            commit();
            var wp = el.getAttribute('data-weapon');
            S.draft.weapons = S.draft.weapons || [];
            var i = S.draft.weapons.indexOf(wp);
            if (i > -1) { if (S.draft.weapons.length > 1) S.draft.weapons.splice(i, 1); }
            else S.draft.weapons.push(wp);
            O.Modal.setBody(bodyHtml());
        },

        'point-here': function () {
            commit();
            O.post('editor:currentCoords').then(function (c) {
                S.draft.points = S.draft.points || [];
                S.draft.points.push({ x: c.x || 0, y: c.y || 0, z: c.z || 0, w: c.w || 0 });
                O.Modal.setBody(bodyHtml());
                O.toast('Position added', 'ok');
            });
        },
        'point-pick': function () {
            commit();
            O.post('editor:pickCoords').then(function (c) {
                if (!c || c.cancelled) return;
                S.draft.points = S.draft.points || [];
                S.draft.points.push({ x: c.x, y: c.y, z: c.z, w: c.w });
                O.Modal.setBody(bodyHtml());
                O.toast('Position captured', 'ok');
            });
        },
        'point-del': function (el) {
            commit();
            S.draft.points.splice(Number(el.getAttribute('data-index')), 1);
            O.Modal.setBody(bodyHtml());
        },

        'coords-here': function (el) {
            commit();
            var target = el.getAttribute('data-target');
            O.post('editor:currentCoords').then(function (c) {
                O.setPath(S.draft, target, { x: c.x, y: c.y, z: c.z, w: c.w });
                O.Modal.setBody(bodyHtml());
                O.toast('Coordinates set', 'ok');
            });
        },
        'coords-pick': function (el) {
            commit();
            var target = el.getAttribute('data-target');
            O.post('editor:pickCoords').then(function (c) {
                if (!c || c.cancelled) return;
                O.setPath(S.draft, target, { x: c.x, y: c.y, z: c.z, w: c.w });
                O.Modal.setBody(bodyHtml());
                O.toast('Coordinates captured', 'ok');
            });
        },
        'coords-waypoint': function (el) {
            commit();
            var target = el.getAttribute('data-target');
            O.post('editor:waypoint').then(function (c) {
                if (!c || !c.ok) return O.toast(c && c.message || 'No waypoint set', 'warn');
                O.setPath(S.draft, target, { x: c.x, y: c.y, z: c.z, w: c.w });
                O.Modal.setBody(bodyHtml());
                O.toast('Waypoint coordinates used', 'ok');
            });
        },

        'preview-model': function () {
            commit();
            var model = S.draftKind === 'npc' ? S.draft.model : O.getPath(S.draft, 'entity.model', '');
            var kind = S.draftKind === 'location' ? O.getPath(S.draft, 'entity.type', 'ped') : 'ped';
            if (!model) return O.toast('Set a model first', 'warn');
            O.post('editor:previewModel', { model: model, kind: kind });
        }
    };

    function save() {
        commit();
        var kind = S.draftKind;
        var payload = O.clone(S.draft);

        O.post('admin:save', { kind: kind, payload: payload }).then(function (res) {
            if (res && res.success) {
                O.toast((kind === 'mission' ? 'Mission' : kind === 'location' ? 'Location' : 'Group') + ' saved', 'ok');
                O.Modal.close();
                w.OQApp.refresh();
            } else {
                var errs = (res && res.errors) || ['Unknown error'];
                O.toast(errs[0], 'err', 5000);
                if (errs.length > 1) console.warn('[OQV2] validation:', errs);
            }
        });
    }

    w.OQEditors = {
        open: open,
        commit: commit,
        refresh: refresh,
        save: save,
        Actions: Actions
    };
})(window);
