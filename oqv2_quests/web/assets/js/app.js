/* OQV2 QUESTS — app bootstrap, NUI message router, global event delegation
   Author: Codex Dev: #Alesh48 5654 · Made with CodeX Dev. */
(function (w) {
    'use strict';

    var O = w.OQ, I = w.OQIcon, S = w.OQ.State;

    /* ══════════════════════════ OPEN / CLOSE ═══════════════════════════ */
    function applyBranding(b, ui) {
        if (b) {
            O.$('#brand-name').textContent = b.brand || 'OQV2 QUESTS';
            O.$('#brand-sub').textContent = b.subtitle || '';
            O.$('#brand-author').textContent = b.author || '';
            O.$('#brand-footer').textContent = b.footer || 'Made with CodeX Dev.';
            O.$('#brand-version').textContent = 'v' + (b.version || '2.0.0');
            var initials = String(b.brand || 'OQ').replace(/[^A-Za-z0-9]/g, '').slice(0, 2).toUpperCase();
            O.$('#brand-mark').textContent = initials || 'OQ';
        }
        if (ui) {
            if (ui.accent) document.documentElement.style.setProperty('--accent', ui.accent);
            if (ui.accentAlt) document.documentElement.style.setProperty('--accent-alt', ui.accentAlt);
            if (ui.accent) {
                document.documentElement.style.setProperty('--accent-soft', hexA(ui.accent, .14));
                document.documentElement.style.setProperty('--accent-line', hexA(ui.accent, .38));
            }
        }
    }

    function hexA(hex, alpha) {
        var h = String(hex).replace('#', '');
        if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
        var n = parseInt(h, 16);
        if (isNaN(n)) return 'rgba(224,27,132,' + alpha + ')';
        return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + alpha + ')';
    }

    function open(view, data) {
        S.view = view;
        if (view === 'admin') {
            S.data = data;
            S.page = 'dashboard';
            S.search = '';
            applyBranding(data.branding, data.ui);
            w.OQAdmin.render();
        } else {
            S.journal = data;
            S.page = 'quests';
            applyBranding(data.branding, data.ui);
            w.OQJournal.render();
        }
        O.$('#app').classList.add('is-open');
        O.$('#app').setAttribute('aria-hidden', 'false');
    }

    function close(silent) {
        if (!S.view) return;
        S.view = null;
        O.Modal.close();
        O.$('#confirm').classList.remove('is-open');
        O.$('#app').classList.remove('is-open');
        O.$('#app').setAttribute('aria-hidden', 'true');
        if (!silent) O.post('close');
    }

    function refresh() {
        return O.post('refresh').then(function (data) {
            if (!data || data.error) return;
            if (S.view === 'admin') {
                S.data = data;
                w.OQAdmin.render();
            } else if (S.view === 'journal') {
                S.journal = data;
                w.OQJournal.render();
            }
            return data;
        });
    }

    /* ══════════════════════════ NUI MESSAGES ═══════════════════════════ */
    w.addEventListener('message', function (ev) {
        var msg = ev.data || {};
        switch (msg.action) {
            case 'open':
                open(msg.view || 'admin', msg.data || {});
                break;
            case 'close':
                close(true);
                break;
            case 'suspend':
                O.$('#suspend').classList.add('is-open');
                break;
            case 'resume':
                O.$('#suspend').classList.remove('is-open');
                break;
            case 'tracker':
                w.OQHud.Tracker.render(msg.data || {});
                break;
            case 'trackerVisibility':
                w.OQHud.Tracker.setHidden(msg.data && msg.data.hidden);
                break;
            case 'missionAlert':
                w.OQHud.missionAlert(msg.data || {});
                break;
            case 'missionComplete':
                w.OQHud.missionComplete(msg.data || {});
                break;
            case 'levelUp':
                w.OQHud.levelUp(msg.data || {});
                break;
            case 'xp':
                w.OQHud.Tracker.xp(msg.data || {});
                break;
        }
    });

    /* ═════════════════════════ GLOBAL ACTIONS ══════════════════════════ */
    var Actions = {
        'close': function () { close(); },

        'page': function (el) {
            var page = el.getAttribute('data-page');
            O.post('sound', { name: 'click' });
            if (S.view === 'admin') w.OQAdmin.goto(page);
            else { S.page = page; w.OQJournal.render(); }
        },

        'refresh': function () {
            refresh().then(function () { O.toast('Refreshed', 'ok', 1600); });
        },

        'new': function (el) {
            w.OQEditors.open(el.getAttribute('data-kind'), null);
        },

        'edit': function (el) {
            w.OQEditors.open(el.getAttribute('data-kind'), el.getAttribute('data-uid'));
        },

        'save': function () { w.OQEditors.save(); },

        'delete': function (el) {
            var kind = el.getAttribute('data-kind'), uid = el.getAttribute('data-uid');
            O.confirmBox('Delete this ' + kind + '?', 'This cannot be undone. Linked references are cleaned up automatically.')
                .then(function (yes) {
                    if (!yes) return;
                    O.post('admin:delete', { kind: kind, uid: uid }).then(function (res) {
                        if (res && res.success) {
                            O.toast('Deleted', 'ok');
                            O.Modal.close();
                            refresh();
                        } else {
                            O.toast((res && res.errors && res.errors[0]) || 'Delete failed', 'err');
                        }
                    });
                });
        },

        'toggle': function (el) {
            O.post('admin:toggle', {
                kind: el.getAttribute('data-kind'),
                uid: el.getAttribute('data-uid'),
                enabled: el.getAttribute('data-enabled') === '1'
            }).then(function (res) {
                if (res && res.success) {
                    O.toast(res.enabled ? 'Enabled' : 'Disabled', 'ok', 1600);
                    refresh();
                } else {
                    O.toast('Could not change state', 'err');
                }
            });
        },

        'duplicate': function (el) {
            O.post('admin:duplicate', {
                kind: el.getAttribute('data-kind'),
                uid: el.getAttribute('data-uid')
            }).then(function (res) {
                if (res && res.success) { O.toast('Duplicated', 'ok'); refresh(); }
                else O.toast((res && res.errors && res.errors[0]) || 'Duplicate failed', 'err');
            });
        },

        'tp': function (el) {
            var coords;
            try { coords = JSON.parse(el.getAttribute('data-coords') || '{}'); } catch (e) { return; }
            if (!coords || (!coords.x && !coords.y)) return O.toast('No coordinates set', 'warn');
            O.post('editor:teleport', { coords: coords });
        },

        'player': function (el) {
            O.post('admin:player', {
                action: el.getAttribute('data-pa'),
                target: Number(el.getAttribute('data-target')),
                value: el.getAttribute('data-value')
            }).then(function (res) {
                if (res && res.success) { O.toast('Done', 'ok', 1600); refresh(); }
                else O.toast((res && res.errors && res.errors[0]) || 'Action failed', 'err');
            });
        },

        'player-level': function (el) {
            var target = Number(el.getAttribute('data-target'));
            O.Modal.open({
                title: 'Set player level',
                subtitle: 'Server id ' + target,
                body: '<div class="form-grid">' +
                    O.field('New level', '<input class="input" id="lvl-input" type="number" min="1" value="10" />') +
                    '</div>',
                foot: '<button class="btn btn--ghost" data-action="modal-close">Cancel</button><div class="spacer"></div>' +
                    '<button class="btn btn--primary" data-action="player-level-apply" data-target="' + target + '">Apply</button>'
            });
        },

        'player-level-apply': function (el) {
            var target = Number(el.getAttribute('data-target'));
            var value = Number((O.$('#lvl-input') || {}).value || 1);
            O.post('admin:player', { action: 'setlevel', target: target, value: value }).then(function (res) {
                if (res && res.success) { O.toast('Level set to ' + value, 'ok'); O.Modal.close(); refresh(); }
                else O.toast((res && res.errors && res.errors[0]) || 'Failed', 'err');
            });
        },

        'player-reset': function (el) {
            var target = Number(el.getAttribute('data-target'));
            O.confirmBox('Reset all progress?', 'Every mission completion and cooldown for this player will be wiped.')
                .then(function (yes) {
                    if (!yes) return;
                    O.post('admin:player', { action: 'resetprogress', target: target }).then(function (res) {
                        if (res && res.success) { O.toast('Progress reset', 'ok'); refresh(); }
                        else O.toast('Failed', 'err');
                    });
                });
        },

        'export': function () {
            O.post('admin:export').then(function (data) {
                if (!data) return O.toast('Export failed', 'err');
                var text = JSON.stringify(data, null, 2);
                O.Modal.open({
                    title: 'Export',
                    subtitle: 'Copy this JSON and keep it safe',
                    body: '<textarea class="textarea" id="export-box" style="min-height:340px;font-family:monospace;font-size:11px">' +
                        O.esc(text) + '</textarea>',
                    foot: '<button class="btn btn--ghost" data-action="modal-close">Close</button><div class="spacer"></div>' +
                        '<button class="btn btn--primary" data-action="copy-export">' + I('copy') + 'Select all</button>'
                });
            });
        },

        'copy-export': function () {
            var box = O.$('#export-box');
            if (!box) return;
            box.focus();
            box.select();
            try { document.execCommand('copy'); O.toast('Copied to clipboard', 'ok'); }
            catch (e) { O.toast('Press Ctrl+C to copy', 'warn'); }
        },

        'import': function () {
            O.Modal.open({
                title: 'Import',
                subtitle: 'Paste a previously exported JSON payload',
                body: '<textarea class="textarea" id="import-box" style="min-height:340px;font-family:monospace;font-size:11px" ' +
                    'placeholder=\'{ "missions": [], "locations": [], "npcs": [] }\'></textarea>',
                foot: '<button class="btn btn--ghost" data-action="modal-close">Cancel</button><div class="spacer"></div>' +
                    '<button class="btn btn--primary" data-action="import-apply">' + I('upload') + 'Import</button>'
            });
        },

        'import-apply': function () {
            var raw = (O.$('#import-box') || {}).value || '';
            var payload;
            try { payload = JSON.parse(raw); }
            catch (e) { return O.toast('Invalid JSON: ' + e.message, 'err', 5000); }
            O.post('admin:import', { payload: payload }).then(function (res) {
                if (res && res.success) {
                    O.toast('Imported ' + res.imported + ' entries' + (res.failed ? ', ' + res.failed + ' failed' : ''), 'ok', 5000);
                    O.Modal.close();
                    refresh();
                } else {
                    O.toast((res && res.errors && res.errors[0]) || 'Import failed', 'err');
                }
            });
        },

        'reload': function () {
            O.post('admin:reload').then(function (res) {
                if (res && res.success) { O.toast(res.message || 'Reloaded', 'ok'); refresh(); }
                else O.toast('Reload failed', 'err');
            });
        },

        'modal-close': function () { O.Modal.close(); },
        'confirm-yes': function () { O.closeConfirm(true); },
        'confirm-no': function () { O.closeConfirm(false); }
    };

    /* ════════════════════════ EVENT DELEGATION ═════════════════════════ */
    document.addEventListener('click', function (ev) {
        var el = ev.target.closest ? ev.target.closest('[data-action]') : null;
        if (!el) return;
        var action = el.getAttribute('data-action');

        var fn = Actions[action] ||
                 (w.OQEditors.Actions && w.OQEditors.Actions[action]) ||
                 (w.OQJournal.Actions && w.OQJournal.Actions[action]);

        if (!fn) return;
        ev.preventDefault();
        ev.stopPropagation();
        try { fn(el, ev); }
        catch (err) { console.error('[OQV2] action "' + action + '" failed', err); O.toast('Action failed: ' + err.message, 'err'); }
    });

    document.addEventListener('keydown', function (ev) {
        if (ev.key === 'Escape') {
            if (O.$('#confirm').classList.contains('is-open')) { O.closeConfirm(false); return; }
            if (O.Modal.isOpen()) { O.Modal.close(); return; }
            if (S.view) close();
        }
        if (ev.key === 'Enter' && O.$('#confirm').classList.contains('is-open')) {
            O.closeConfirm(true);
        }
    });

    /* ═══════════════════════ BROWSER DEV PREVIEW ═══════════════════════ */
    if (O.isBrowser) {
        O.setMock(function (name, data) {
            if (name === 'refresh') return w.OQ_MOCK ? w.OQ_MOCK.snapshot() : {};
            if (name === 'editor:currentCoords') return { x: 215.76, y: -810.12, z: 30.73, w: 156.4 };
            if (name === 'editor:waypoint') return { ok: true, x: 100.5, y: -200.25, z: 31.2, w: 0 };
            if (name === 'admin:save') return { success: true, uid: data.payload && data.payload.uid || 'm_new' };
            if (name === 'admin:export') return w.OQ_MOCK ? { missions: w.OQ_MOCK.snapshot().missions } : {};
            return { success: true };
        });

        w.addEventListener('DOMContentLoaded', function () {
            if (!w.OQ_MOCK) return;
            var params = new URLSearchParams(w.location.search);
            var view = params.get('view') || 'admin';
            if (view === 'journal') {
                open('journal', w.OQ_MOCK.journal());
            } else {
                open('admin', w.OQ_MOCK.snapshot());
                if (params.get('page')) w.OQAdmin.goto(params.get('page'));
            }
            if (params.get('hud')) {
                w.OQHud.Tracker.render(w.OQ_MOCK.tracker());
            }
        });
    }

    w.OQApp = { open: open, close: close, refresh: refresh, Actions: Actions };
})(window);
