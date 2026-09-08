/* OQV2 QUESTS — core helpers: DOM, NUI transport, toasts, modal, state
   Made with CodeX Dev. */
(function (w) {
    'use strict';

    var RESOURCE = 'oqv2_quests';
    try {
        if (w.GetParentResourceName) RESOURCE = w.GetParentResourceName();
    } catch (e) { /* browser dev */ }

    var isBrowser = (w.location.protocol === 'http:' || w.location.protocol === 'file:') &&
                    w.location.hostname !== RESOURCE;

    /* ─────────────────────────────── DOM ─────────────────────────────── */
    function $(sel, root) { return (root || document).querySelector(sel); }
    function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

    function esc(str) {
        if (str === null || str === undefined) return '';
        return String(str)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function show(el, on) {
        if (!el) return;
        el.setAttribute('aria-hidden', on ? 'false' : 'true');
        el.classList.toggle('is-visible', !!on);
    }

    /* ───────────────────────────── FORMATTING ────────────────────────── */
    function num(n) {
        n = Number(n) || 0;
        return n.toLocaleString('en-US');
    }

    function money(n) { return '$' + num(Math.round(Number(n) || 0)); }

    function duration(sec) {
        sec = Math.max(0, Math.floor(Number(sec) || 0));
        if (!sec) return '—';
        var d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600),
            m = Math.floor((sec % 3600) / 60), s = sec % 60, out = [];
        if (d) out.push(d + 'd');
        if (h) out.push(h + 'h');
        if (m && !d) out.push(m + 'm');
        if (s && !d && !h) out.push(s + 's');
        return out.join(' ');
    }

    function timeAgo(ts) {
        if (!ts) return '—';
        var diff = Math.floor(Date.now() / 1000) - Number(ts);
        if (diff < 60) return 'just now';
        if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
        if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
        return Math.floor(diff / 86400) + 'd ago';
    }

    function coordText(c) {
        if (!c) return '—';
        return [Number(c.x || 0).toFixed(1), Number(c.y || 0).toFixed(1), Number(c.z || 0).toFixed(1)].join(', ');
    }

    function titleCase(s) {
        return String(s || '').replace(/[_-]+/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
    }

    function clone(o) {
        return JSON.parse(JSON.stringify(o === undefined ? null : o));
    }

    function uid(prefix) {
        return (prefix || 'id') + '_' + Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-4);
    }

    /* ────────────────────────────── NUI CALL ─────────────────────────── */
    var mockHandler = null;
    function setMock(fn) { mockHandler = fn; }

    function post(name, data) {
        if (isBrowser || !w.fetch) {
            return Promise.resolve(mockHandler ? mockHandler(name, data || {}) : {});
        }
        return fetch('https://' + RESOURCE + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (r) {
            return r.json().catch(function () { return {}; });
        }).catch(function (err) {
            console.error('[OQV2] NUI call failed:', name, err);
            return {};
        });
    }

    /* ────────────────────────────── TOASTS ───────────────────────────── */
    function toast(message, type, timeout) {
        var host = $('#toasts');
        if (!host) return;
        var el = document.createElement('div');
        var kind = type || 'info';
        var iconName = kind === 'ok' ? 'check' : kind === 'err' ? 'warn' : kind === 'warn' ? 'warn' : 'info';
        el.className = 'toast toast--' + kind;
        el.innerHTML = w.OQIcon(iconName) + '<span>' + esc(message) + '</span>';
        host.appendChild(el);
        setTimeout(function () {
            el.classList.add('is-out');
            setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 250);
        }, timeout || 3200);
    }

    /* ───────────────────────────── CONFIRM ───────────────────────────── */
    var confirmResolve = null;
    function confirmBox(title, text, danger) {
        var box = $('#confirm');
        $('#confirm-title').textContent = title || 'Are you sure?';
        $('#confirm-text').textContent = text || '';
        var yes = $('[data-action="confirm-yes"]');
        yes.className = 'btn ' + (danger === false ? 'btn--primary' : 'btn--danger');
        box.classList.add('is-open');
        return new Promise(function (resolve) { confirmResolve = resolve; });
    }
    function closeConfirm(result) {
        $('#confirm').classList.remove('is-open');
        if (confirmResolve) { confirmResolve(result); confirmResolve = null; }
    }

    /* ────────────────────────────── MODAL ────────────────────────────── */
    var Modal = {
        open: function (opts) {
            $('#modal-title').textContent = opts.title || '';
            $('#modal-sub').textContent = opts.subtitle || '';
            $('#modal-tabs').innerHTML = opts.tabs || '';
            $('#modal-tabs').hidden = !opts.tabs;
            $('#modal-body').innerHTML = opts.body || '';
            $('#modal-foot').innerHTML = opts.foot || '';
            $('#modal-box').style.width = opts.width || '';
            $('#modal').classList.add('is-open');
            if (typeof opts.onMount === 'function') opts.onMount();
        },
        setBody: function (html) { $('#modal-body').innerHTML = html; },
        setTabs: function (html) { $('#modal-tabs').innerHTML = html; },
        isOpen: function () { return $('#modal').classList.contains('is-open'); },
        close: function () {
            $('#modal').classList.remove('is-open');
            $('#modal-body').innerHTML = '';
        }
    };

    /* ─────────────────────────── FORM HELPERS ────────────────────────── */
    function field(label, inputHtml, hint, spanCls) {
        return '<div class="field ' + (spanCls || '') + '">' +
            '<label class="field__label">' + esc(label) + '</label>' + inputHtml +
            (hint ? '<span class="field__hint">' + esc(hint) + '</span>' : '') +
            '</div>';
    }

    function input(key, value, opts) {
        opts = opts || {};
        return '<input class="input" data-key="' + esc(key) + '" type="' + (opts.type || 'text') + '"' +
            ' value="' + esc(value === undefined || value === null ? '' : value) + '"' +
            (opts.placeholder ? ' placeholder="' + esc(opts.placeholder) + '"' : '') +
            (opts.min !== undefined ? ' min="' + opts.min + '"' : '') +
            (opts.max !== undefined ? ' max="' + opts.max + '"' : '') +
            (opts.step !== undefined ? ' step="' + opts.step + '"' : '') + ' />';
    }

    function textarea(key, value, placeholder) {
        return '<textarea class="textarea" data-key="' + esc(key) + '" placeholder="' +
            esc(placeholder || '') + '">' + esc(value || '') + '</textarea>';
    }

    function select(key, value, options) {
        var html = '<select class="select" data-key="' + esc(key) + '">';
        options.forEach(function (o) {
            var val = (o.value !== undefined) ? o.value : o;
            var lbl = (o.label !== undefined) ? o.label : titleCase(o);
            html += '<option value="' + esc(val) + '"' + (String(val) === String(value) ? ' selected' : '') + '>' +
                esc(lbl) + '</option>';
        });
        return html + '</select>';
    }

    function toggle(key, value, label) {
        return '<label class="switch"><input type="checkbox" data-key="' + esc(key) + '"' +
            (value ? ' checked' : '') + ' /><span class="switch__track"></span>' +
            '<span class="switch__label">' + esc(label || '') + '</span></label>';
    }

    /** Reads every [data-key] inside `root` into a nested object (dot notation). */
    function readForm(root) {
        var out = {};
        $$('[data-key]', root).forEach(function (el) {
            var path = el.getAttribute('data-key');
            var val;
            if (el.type === 'checkbox') val = el.checked;
            else if (el.type === 'number') val = el.value === '' ? 0 : Number(el.value);
            else val = el.value;
            setPath(out, path, val);
        });
        return out;
    }

    function setPath(obj, path, value) {
        var parts = path.split('.');
        var cur = obj;
        for (var i = 0; i < parts.length - 1; i++) {
            var k = parts[i];
            var nextIsIndex = /^\d+$/.test(parts[i + 1]);
            if (cur[k] === undefined) cur[k] = nextIsIndex ? [] : {};
            cur = cur[k];
        }
        cur[parts[parts.length - 1]] = value;
    }

    function getPath(obj, path, fallback) {
        var parts = String(path).split('.'), cur = obj;
        for (var i = 0; i < parts.length; i++) {
            if (cur === null || cur === undefined) return fallback;
            cur = cur[parts[i]];
        }
        return cur === undefined ? fallback : cur;
    }

    /* ─────────────────────────────── STATE ───────────────────────────── */
    var State = {
        view: null,
        page: 'dashboard',
        data: null,
        journal: null,
        search: '',
        selected: null,
        draft: null,
        draftKind: null,
        draftTab: 0
    };

    w.OQ = {
        RESOURCE: RESOURCE,
        isBrowser: isBrowser,
        $: $, $$: $$, esc: esc, show: show,
        num: num, money: money, duration: duration, timeAgo: timeAgo,
        coordText: coordText, titleCase: titleCase, clone: clone, uid: uid,
        post: post, setMock: setMock,
        toast: toast, confirmBox: confirmBox, closeConfirm: closeConfirm,
        Modal: Modal,
        field: field, input: input, textarea: textarea, select: select, toggle: toggle,
        readForm: readForm, setPath: setPath, getPath: getPath,
        State: State
    };
})(window);
