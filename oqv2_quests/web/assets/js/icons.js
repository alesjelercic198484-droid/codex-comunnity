/* OQV2 QUESTS — inline SVG icon set (no external CDN, works offline in NUI)
   Made with CodeX Dev. */
(function (w) {
    'use strict';

    var P = {
        dashboard:  '<path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/>',
        scroll:     '<path d="M8 3h9a2 2 0 0 1 2 2v13a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V6"/><path d="M4 6h4V4a1 1 0 0 0-2 0"/><path d="M9 8h7M9 12h7M9 16h4"/>',
        pin:        '<path d="M12 21s7-5.5 7-11a7 7 0 1 0-14 0c0 5.5 7 11 7 11z"/><circle cx="12" cy="10" r="2.6"/>',
        skull:      '<path d="M12 2a8 8 0 0 0-8 8v3.2a3 3 0 0 0 1.6 2.6L7 16.5V19a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2v-2.5l1.4-.7A3 3 0 0 0 20 13.2V10a8 8 0 0 0-8-8z"/><circle cx="9" cy="11" r="1.6"/><circle cx="15" cy="11" r="1.6"/><path d="M11 17h2"/>',
        tree:       '<rect x="9" y="2" width="6" height="5" rx="1.5"/><rect x="2" y="16" width="6" height="5" rx="1.5"/><rect x="16" y="16" width="6" height="5" rx="1.5"/><path d="M12 7v5M5 16v-2.5h14V16"/>',
        users:      '<path d="M16 20v-1.6a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4V20"/><circle cx="9" cy="7" r="3.4"/><path d="M22 20v-1.6a4 4 0 0 0-3-3.8"/><path d="M16.5 3.6a4 4 0 0 1 0 7.2"/>',
        logs:       '<path d="M4 4h16v16H4z"/><path d="M8 9h8M8 13h8M8 17h5"/>',
        gear:       '<circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1 1.56V21a2 2 0 1 1-4 0v-.11a1.7 1.7 0 0 0-1.11-1.56 1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.56-1H3a2 2 0 1 1 0-4h.11A1.7 1.7 0 0 0 4.6 8.9a1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.56V3a2 2 0 1 1 4 0v.11a1.7 1.7 0 0 0 1 1.56 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.7 1.7 0 0 0 19.4 9v.09a1.7 1.7 0 0 0 1.56 1H21a2 2 0 1 1 0 4h-.11a1.7 1.7 0 0 0-1.49 1z"/>',
        plus:       '<path d="M12 5v14M5 12h14"/>',
        search:     '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
        edit:       '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
        trash:      '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/><path d="M10 11v6M14 11v6"/>',
        copy:       '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
        power:      '<path d="M12 3v9"/><path d="M18.4 6.6a9 9 0 1 1-12.8 0"/>',
        check:      '<path d="M20 6L9 17l-5-5"/>',
        x:          '<path d="M6 6l12 12M18 6L6 18"/>',
        refresh:    '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 3v6h-6"/>',
        download:   '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5M12 15V3"/>',
        upload:     '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M17 8l-5-5-5 5M12 3v12"/>',
        target:     '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r="1"/>',
        box:        '<path d="M21 8l-9-5-9 5 9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/>',
        truck:      '<path d="M3 6h11v9H3z"/><path d="M14 9h4l3 3v3h-7z"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
        money:      '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.8"/><path d="M6 12h.01M18 12h.01"/>',
        clock:      '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.2 2"/>',
        star:       '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.2-5.4-2.9-5.4 2.9 1-6.2L3.2 9.5l6.1-.9z"/>',
        bolt:       '<path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z"/>',
        shield:     '<path d="M12 3l8 3v6c0 5-3.4 8.6-8 10-4.6-1.4-8-5-8-10V6z"/><path d="M9 12l2 2 4-4"/>',
        map:        '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
        hand:       '<path d="M11 11V5.5a1.5 1.5 0 0 1 3 0V11"/><path d="M14 10.5V4a1.5 1.5 0 0 1 3 0v7"/><path d="M17 11V6.5a1.5 1.5 0 0 1 3 0V14a7 7 0 0 1-7 7h-1a7 7 0 0 1-7-7v-2.5a1.5 1.5 0 0 1 3 0V13"/>',
        chevron:    '<path d="M9 6l6 6-6 6"/>',
        info:       '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
        warn:       '<path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
        crosshair:  '<circle cx="12" cy="12" r="8"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
        location:   '<path d="M12 21s7-5.5 7-11a7 7 0 1 0-14 0c0 5.5 7 11 7 11z"/><circle cx="12" cy="10" r="2.6"/>',
        hourglass:  '<path d="M6 2h12M6 22h12"/><path d="M8 2v4a4 4 0 0 0 4 4 4 4 0 0 0 4-4V2"/><path d="M8 22v-4a4 4 0 0 1 4-4 4 4 0 0 1 4 4v4"/>',
        recycle:    '<path d="M7 19H4.8a2 2 0 0 1-1.7-3l2.3-4"/><path d="M11 19h6.2a2 2 0 0 0 1.7-3l-1.2-2"/><path d="M9.4 5.5l1.3-2.2a2 2 0 0 1 3.4 0L16 7"/><path d="M4 12l3-1.7M20 14l-3 1.7M9 19l2-3"/>',
        eye:        '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
        lock:       '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
        unlock:     '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 7.5-2"/>',
        db:         '<ellipse cx="12" cy="5.5" rx="8" ry="3"/><path d="M4 5.5v13c0 1.7 3.6 3 8 3s8-1.3 8-3v-13"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
        play:       '<path d="M6 4l14 8-14 8z"/>',
        stop:       '<rect x="6" y="6" width="12" height="12" rx="2"/>',
        route:      '<circle cx="6" cy="19" r="3"/><circle cx="18" cy="5" r="3"/><path d="M9 19h5a4 4 0 0 0 0-8H10a4 4 0 0 1 0-8h5"/>',
        list:       '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
        gift:       '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M5 12v9h14v-9M12 8v13"/><path d="M12 8S9.5 3 7.5 4.5 9 8 12 8zM12 8s2.5-5 4.5-3.5S15 8 12 8z"/>',
        flag:       '<path d="M4 21V4"/><path d="M4 5h12l-2 4 2 4H4"/>',
        user:       '<circle cx="12" cy="8" r="4"/><path d="M4 21v-1a6 6 0 0 1 6-6h4a6 6 0 0 1 6 6v1"/>',
        sparkle:    '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M18.5 16l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/>',
        save:       '<path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><path d="M17 21v-8H7v8M7 3v5h8"/>',
        link:       '<path d="M10 13a5 5 0 0 0 7.5.5l3-3A5 5 0 0 0 13.5 3.5l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3A5 5 0 0 0 10.5 20.5l1.7-1.7"/>'
    };

    var ALIASES = {
        'give_item': 'box', 'collect': 'hand', 'deliver': 'truck', 'goto': 'location',
        'kill': 'crosshair', 'interact': 'hand', 'pay': 'money', 'wait': 'hourglass',
        'general': 'scroll', 'delivery': 'truck', 'crime': 'skull', 'legal': 'shield',
        'gang': 'skull', 'story': 'scroll', 'event': 'star', 'daily': 'clock',
        'mission': 'scroll', 'location': 'pin', 'npc': 'skull',
        'circle-check': 'check', 'box-open': 'box', 'truck-fast': 'truck',
        'location-dot': 'location', 'crosshairs': 'crosshair', 'hands': 'hand',
        'money-bill': 'money', 'hourglass-half': 'hourglass', 'shield-halved': 'shield'
    };

    /**
     * @param {string} name icon key
     * @param {string} [cls] optional css class for the wrapping svg
     * @returns {string} svg markup
     */
    function icon(name, cls) {
        var key = ALIASES[name] || name;
        var path = P[key] || P.scroll;
        return '<svg viewBox="0 0 24 24"' + (cls ? ' class="' + cls + '"' : '') + '>' + path + '</svg>';
    }

    icon.has = function (name) { return !!(P[ALIASES[name] || name]); };
    icon.list = function () { return Object.keys(P); };

    w.OQIcon = icon;
})(window);
