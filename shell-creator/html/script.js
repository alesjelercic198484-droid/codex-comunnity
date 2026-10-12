// SHELL CREATOR NUI
let appData = { props: [], colors: [], templates: [], slots: [], shells: [], keys: {}, maxProps: 200, maxFloors: 5, isEditing: false };
let currentCategory = 'all';
let currentFloor = 1;

window.addEventListener('message', function(event) {
    const data = event.data;
    switch (data.action) {
        case 'openMenu':
            appData = { ...appData, ...data };
            document.getElementById('shell-creator-app').style.display = 'flex';
            renderAll();
            break;
        case 'closeMenu':
            document.getElementById('shell-creator-app').style.display = 'none';
            break;
        case 'refreshData':
            if (data.shells) appData.shells = data.shells;
            if (data.slots) appData.slots = data.slots;
            renderShellList();
            break;
    }
});

function renderAll() {
    renderTemplates();
    renderSlots();
    renderShellList();
    renderCategories();
    renderPropsGrid();
    renderColors();
    updateFloorInfo();
}

// NAV
document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', function() {
        document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
        this.classList.add('active');
        document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
        document.getElementById('tab-' + this.dataset.tab).classList.add('active');
    });
});

// TEMPLATES & SLOTS
function renderTemplates() {
    const select = document.getElementById('shell-template');
    select.innerHTML = '';
    appData.templates.forEach(t => {
        const o = document.createElement('option');
        o.value = t.id;
        o.textContent = t.label + ' - ' + t.description;
        select.appendChild(o);
    });
}

function renderSlots() {
    const select = document.getElementById('shell-slot');
    select.innerHTML = '';
    appData.slots.forEach(s => {
        const o = document.createElement('option');
        o.value = s.id;
        o.textContent = s.label + (s.occupied ? ' [OCCUPIED]' : ' [FREE]');
        o.disabled = s.occupied;
        select.appendChild(o);
    });
}

function renderShellList() {
    const container = document.getElementById('shell-list');
    container.innerHTML = '';
    if (!appData.shells || appData.shells.length === 0) {
        container.innerHTML = '<p class="info-text">No shells yet. Click "New Shell" to start!</p>';
        return;
    }
    appData.shells.forEach(shell => {
        const card = document.createElement('div');
        card.className = 'shell-card';
        card.innerHTML = `
            <div class="shell-card-title">${esc(shell.label || 'Untitled')}</div>
            <div class="shell-card-info">
                <span>📦 Props: ${shell.propCount || 0}</span>
                <span>📐 Floors: ${shell.floorCount || 1}</span>
                <span>🏠 ${shell.template || 'empty'}</span>
            </div>
            <div class="shell-card-actions">
                <button class="btn btn-primary btn-sm" onclick="editShell(${shell.shellId})">✏️ Edit</button>
                <button class="btn btn-secondary btn-sm" onclick="tpShell(${shell.shellId})">🚪 TP</button>
                <button class="btn btn-danger btn-sm" onclick="delShell(${shell.shellId})">🗑️</button>
            </div>`;
        container.appendChild(card);
    });
}

document.getElementById('btn-new-shell').addEventListener('click', () => { document.getElementById('new-shell-form').style.display = 'block'; });
document.getElementById('btn-cancel-create').addEventListener('click', () => { document.getElementById('new-shell-form').style.display = 'none'; });

document.getElementById('btn-create-shell').addEventListener('click', function() {
    const name = document.getElementById('shell-name').value.trim() || 'New Shell';
    const template = document.getElementById('shell-template').value;
    const slotId = document.getElementById('shell-slot').value;
    fetch('https://shell-creator/createNewShell', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ template, slotId, label: name }) });
    document.getElementById('new-shell-form').style.display = 'none';
    document.getElementById('shell-name').value = '';
});

function editShell(id) { fetch('https://shell-creator/editShell', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ shellId: id }) }); }
function tpShell(id) { fetch('https://shell-creator/teleportToShell', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ shellId: id }) }); }
function delShell(id) {
    showConfirm('Delete this shell?', function(ok) {
        if (ok) fetch('https://shell-creator/deleteShell', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ shellId: id }) });
    });
}

// PROPS
function renderCategories() {
    const container = document.getElementById('category-list');
    container.innerHTML = '';
    const allBtn = document.createElement('button');
    allBtn.className = 'category-btn active';
    allBtn.textContent = 'All';
    allBtn.dataset.category = 'all';
    allBtn.addEventListener('click', () => setCategory('all'));
    container.appendChild(allBtn);

    appData.props.forEach(cat => {
        const btn = document.createElement('button');
        btn.className = 'category-btn';
        btn.textContent = cat.label + ' (' + cat.count + ')';
        btn.dataset.category = cat.name;
        btn.addEventListener('click', () => setCategory(cat.name));
        container.appendChild(btn);
    });
}

function setCategory(cat) {
    currentCategory = cat;
    document.querySelectorAll('.category-btn').forEach(b => b.classList.toggle('active', b.dataset.category === cat));
    renderPropsGrid();
}

function renderPropsGrid() {
    const container = document.getElementById('props-grid');
    container.innerHTML = '';
    let props = [];
    if (currentCategory === 'all') {
        appData.props.forEach(c => { props = props.concat(c.props); });
    } else {
        const cat = appData.props.find(c => c.name === currentCategory);
        if (cat) props = cat.props;
    }
    props.forEach(prop => {
        const item = document.createElement('div');
        item.className = 'prop-item';
        item.innerHTML = `<div class="prop-item-icon">📦</div><div><div class="prop-item-label">${esc(prop.label)}</div><div class="prop-item-model">${esc(prop.model)}</div></div>`;
        item.addEventListener('click', () => {
            fetch('https://shell-creator/selectProp', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: prop.model }) });
        });
        container.appendChild(item);
    });
}

document.getElementById('prop-search').addEventListener('input', function() {
    const q = this.value.toLowerCase();
    const container = document.getElementById('props-grid');
    container.innerHTML = '';
    if (!q) { renderPropsGrid(); return; }
    let all = [];
    appData.props.forEach(c => c.props.forEach(p => {
        if (p.label.toLowerCase().includes(q) || p.model.toLowerCase().includes(q)) all.push(p);
    }));
    all.forEach(prop => {
        const item = document.createElement('div');
        item.className = 'prop-item';
        item.innerHTML = `<div class="prop-item-icon">📦</div><div><div class="prop-item-label">${esc(prop.label)}</div><div class="prop-item-model">${esc(prop.model)}</div></div>`;
        item.addEventListener('click', () => fetch('https://shell-creator/selectProp', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: prop.model }) }));
        container.appendChild(item);
    });
});

// COLORS
function renderColors() {
    renderColorGrid('wall-colors', 'Wall');
    renderColorGrid('floor-colors', 'Floor');
}

function renderColorGrid(id, type) {
    const container = document.getElementById(id);
    container.innerHTML = '';
    appData.colors.forEach((color, i) => {
        const swatch = document.createElement('div');
        swatch.className = 'color-swatch';
        swatch.style.backgroundColor = color.hex;
        swatch.innerHTML = `<span class="color-label">${esc(color.label)}</span>`;
        swatch.addEventListener('click', () => fetch(`https://shell-creator/apply${type}Color`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ colorIndex: i + 1 }) }));
        container.appendChild(swatch);
    });
}

// FLOORS
function updateFloorInfo() {
    document.getElementById('current-floor').textContent = currentFloor;
    document.getElementById('max-floors').textContent = appData.maxFloors || 5;
}

document.getElementById('btn-floor-up').addEventListener('click', () => {
    if (currentFloor < (appData.maxFloors || 5)) {
        currentFloor++;
        document.getElementById('current-floor').textContent = currentFloor;
        fetch('https://shell-creator/switchFloor', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ floor: currentFloor }) });
    }
});

document.getElementById('btn-floor-down').addEventListener('click', () => {
    if (currentFloor > 1) {
        currentFloor--;
        document.getElementById('current-floor').textContent = currentFloor;
        fetch('https://shell-creator/switchFloor', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ floor: currentFloor }) });
    }
});

document.getElementById('btn-add-floor').addEventListener('click', () => fetch('https://shell-creator/addFloor', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) }));

// SAVE / CLOSE
document.getElementById('btn-save').addEventListener('click', () => fetch('https://shell-creator/saveShell', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) }));
document.getElementById('btn-close').addEventListener('click', () => fetch('https://shell-creator/closeMenu', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) }));

// EXPORT
document.getElementById('btn-export').addEventListener('click', function() {
    const type = document.getElementById('export-housing-type').value;
    fetch('https://shell-creator/exportConfig', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ housingType: type }) })
        .then(r => r.json())
        .then(d => { document.getElementById('export-code').value = d.config || 'No config'; });
});

document.getElementById('btn-copy-export').addEventListener('click', function() {
    const ta = document.getElementById('export-code');
    ta.select();
    document.execCommand('copy');
    this.textContent = '✅ Copied!';
    setTimeout(() => { this.textContent = '📋 Copy to Clipboard'; }, 2000);
});

// TELEPORTERS
document.getElementById('btn-create-teleporter').addEventListener('click', function() {
    if (appData.shells && appData.shells.length > 0) {
        showPrompt('Teleporter Label', 'Shell Entry', function(label) {
            if (label && label.trim()) {
                fetch('https://shell-creator/createTeleporter', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ shellId: appData.shells[0].shellId, label: label.trim() }) });
            }
        });
    }
});

// INLINE PROMPT (browser prompt doesn't work in NUI)
function showPrompt(title, def, cb) {
    const ov = document.createElement('div');
    ov.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.7);display:flex;align-items:center;justify-content:center;z-index:9999;';
    ov.innerHTML = `<div style="background:#1e2128;border:1px solid #2a2d35;border-radius:12px;padding:24px;width:350px;">
        <h3 style="color:#fff;margin-bottom:16px;">${esc(title)}</h3>
        <input type="text" id="__prompt_input" value="${esc(def)}" style="width:100%;padding:10px;background:#0f1117;border:1px solid #2a2d35;border-radius:8px;color:#e0e0e0;font-family:inherit;margin-bottom:16px;" />
        <div style="display:flex;gap:10px;justify-content:flex-end;">
            <button id="__prompt_cancel" style="padding:8px 16px;background:#2a2d35;border:1px solid #3a3d45;border-radius:8px;color:#ccc;cursor:pointer;">Cancel</button>
            <button id="__prompt_ok" style="padding:8px 16px;background:#2563eb;border:none;border-radius:8px;color:#fff;cursor:pointer;">OK</button>
        </div></div>`;
    document.body.appendChild(ov);
    const input = ov.querySelector('#__prompt_input');
    input.focus(); input.select();
    ov.querySelector('#__prompt_ok').addEventListener('click', () => { ov.remove(); cb(input.value); });
    ov.querySelector('#__prompt_cancel').addEventListener('click', () => { ov.remove(); cb(null); });
    input.addEventListener('keydown', e => { if (e.key === 'Enter') { ov.remove(); cb(input.value); } if (e.key === 'Escape') { ov.remove(); cb(null); } });
}

function showConfirm(msg, cb) {
    const ov = document.createElement('div');
    ov.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.7);display:flex;align-items:center;justify-content:center;z-index:9999;';
    ov.innerHTML = `<div style="background:#1e2128;border:1px solid #2a2d35;border-radius:12px;padding:24px;width:350px;text-align:center;">
        <p style="color:#ddd;margin-bottom:16px;">${esc(msg)}</p>
        <div style="display:flex;gap:10px;justify-content:center;">
            <button id="__confirm_no" style="padding:8px 24px;background:#2a2d35;border:1px solid #3a3d45;border-radius:8px;color:#ccc;cursor:pointer;">Cancel</button>
            <button id="__confirm_yes" style="padding:8px 24px;background:#dc2626;border:none;border-radius:8px;color:#fff;cursor:pointer;">Confirm</button>
        </div></div>`;
    document.body.appendChild(ov);
    ov.querySelector('#__confirm_yes').addEventListener('click', () => { ov.remove(); cb(true); });
    ov.querySelector('#__confirm_no').addEventListener('click', () => { ov.remove(); cb(false); });
}

// UTIL
function esc(t) { if (!t) return ''; const d = document.createElement('div'); d.textContent = t; return d.innerHTML; }

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        fetch('https://shell-creator/closeMenu', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
    }
});
