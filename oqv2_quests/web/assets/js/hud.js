/* OQV2 QUESTS — HUD layer: tracker, mission alert, completion, level up
   Made with CodeX Dev. */
(function (w) {
    'use strict';

    var O = w.OQ, I = w.OQIcon;
    var timers = {};

    function clearTimer(key) {
        if (timers[key]) { clearTimeout(timers[key]); timers[key] = null; }
    }

    /* ──────────────────────────── TRACKER ───────────────────────────── */
    var Tracker = {
        hidden: false,
        data: null,

        render: function (data) {
            if (data) Tracker.data = data;
            var d = Tracker.data;
            var root = O.$('#tracker');
            if (!root) return;

            if (!d || !d.visible) {
                root.classList.remove('is-visible');
                root.setAttribute('aria-hidden', 'true');
                return;
            }

            var p = d.player || {};
            O.$('#tracker-level').textContent = p.level || 1;
            var pct = Math.max(0, Math.min(100, Number(p.percent) || 0));
            O.$('#tracker-xp-fill').style.width = pct + '%';
            O.$('#tracker-xp-text').textContent = O.num(p.xp || 0) + ' / ' + O.num(p.need || 0) + ' XP';

            var card = O.$('#tracker-card');
            if (d.mission) {
                card.hidden = false;
                O.$('#tracker-icon').innerHTML = I(d.mission.icon || 'scroll');
                O.$('#tracker-title').textContent = d.mission.name || 'Mission';

                var html = '';
                (d.mission.objectives || []).forEach(function (obj) {
                    var counter = (obj.need > 1 && obj.type !== 'goto')
                        ? '<span class="tracker__count">' + (obj.have || 0) + '/' + obj.need + '</span>' : '';
                    html += '<li class="tracker__obj' + (obj.done ? ' is-done' : '') + '">' +
                        '<i></i><span>' + O.esc(obj.label) +
                        (obj.optional ? ' <em style="opacity:.6;font-style:normal">(optional)</em>' : '') +
                        '</span>' + counter + '</li>';
                });
                O.$('#tracker-objectives').innerHTML = html;
            } else {
                card.hidden = true;
            }

            if (!Tracker.hidden) {
                root.classList.add('is-visible');
                root.setAttribute('aria-hidden', 'false');
            }
        },

        setHidden: function (hidden) {
            Tracker.hidden = !!hidden;
            var root = O.$('#tracker');
            if (!root) return;
            root.classList.toggle('is-hidden', Tracker.hidden);
        },

        xp: function (data) {
            if (!Tracker.data) Tracker.data = { visible: true, player: {} };
            Tracker.data.player = {
                level: data.level, percent: data.percent, xp: data.xp, need: data.need
            };
            Tracker.data.visible = true;
            Tracker.render();
        }
    };

    /* ───────────────────────── MISSION ALERT ────────────────────────── */
    function missionAlert(d) {
        var el = O.$('#alert');
        O.$('#alert-kicker').textContent = d.kicker || 'NEW MISSION';
        O.$('#alert-title').textContent = d.title || '';
        O.$('#alert-desc').textContent = d.description || '';
        O.show(el, true);
        clearTimer('alert');
        timers.alert = setTimeout(function () { O.show(el, false); }, d.duration || 6000);
    }

    /* ──────────────────────── MISSION COMPLETE ──────────────────────── */
    function missionComplete(d) {
        var el = O.$('#complete');
        O.$('#complete-title').textContent = d.name || '';

        var r = d.rewards || {}, html = '';
        if (r.money) html += '<span class="complete__reward is-money">' + I('money') + O.money(r.money) + '</span>';
        if (r.bank) html += '<span class="complete__reward is-money">' + I('money') + O.money(r.bank) + ' bank</span>';
        if (r.black) html += '<span class="complete__reward">' + I('money') + O.money(r.black) + ' dirty</span>';
        (r.items || []).forEach(function (it) {
            html += '<span class="complete__reward">' + I('box') + O.esc(it.count + 'x ' + it.name) + '</span>';
        });
        if (r.xp) html += '<span class="complete__reward is-xp">' + I('sparkle') + '+' + O.num(r.xp) + ' XP</span>';
        O.$('#complete-rewards').innerHTML = html;

        O.show(el, true);
        clearTimer('complete');
        timers.complete = setTimeout(function () { O.show(el, false); }, 6000);
    }

    /* ─────────────────────────── LEVEL UP ───────────────────────────── */
    function levelUp(d) {
        var el = O.$('#levelup');
        O.$('#levelup-num').textContent = d.level || '?';
        O.show(el, true);
        clearTimer('levelup');
        timers.levelup = setTimeout(function () { O.show(el, false); }, 3200);
    }

    w.OQHud = {
        Tracker: Tracker,
        missionAlert: missionAlert,
        missionComplete: missionComplete,
        levelUp: levelUp
    };
})(window);
