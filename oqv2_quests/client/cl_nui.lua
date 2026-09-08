--[[ OQV2 QUESTS — NUI bridge (admin panel + player journal)
     Made with CodeX Dev. ]]

local nuiView = nil   -- 'admin' | 'journal' | nil

-------------------------------------------------------------------------------
-- FOCUS HELPERS
-------------------------------------------------------------------------------
local function setFocus(state)
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
    OQ.State.nuiOpen = state
    if state then
        SetCursorLocation(0.5, 0.5)
    end
end

function OQ.Client.closeNui(silent)
    if not nuiView then return end
    nuiView = nil
    setFocus(false)
    SendNUIMessage({ action = 'close' })
    if not silent then OQ.Client.playSound('close') end
    OQ.Client.pushTracker(true)
end

-------------------------------------------------------------------------------
-- OPEN: ADMIN PANEL
-------------------------------------------------------------------------------
function OQ.Client.openAdmin()
    if nuiView then return end

    local snapshot = lib.callback.await('oqv2:admin:snapshot', false)
    if not snapshot then
        OQ.Client.notify(Config.UI.brand, OQ.L('panel_denied'), 'error')
        OQ.Client.playSound('fail')
        return
    end

    nuiView = 'admin'
    setFocus(true)
    SendNUIMessage({ action = 'open', view = 'admin', data = snapshot })
    OQ.Client.playSound('open')
end

RegisterNetEvent('oqv2:client:openAdmin', function()
    OQ.Client.openAdmin()
end)

-------------------------------------------------------------------------------
-- OPEN: PLAYER JOURNAL
-------------------------------------------------------------------------------
function OQ.Client.openJournal()
    if not Config.Journal.enabled or nuiView then return end

    local data = lib.callback.await('oqv2:server:getJournal', false)
    if not data then
        OQ.Client.notify(Config.UI.brand, OQ.L('generic_error'), 'error')
        return
    end
    data.ui = Config.UI

    nuiView = 'journal'
    setFocus(true)
    SendNUIMessage({ action = 'open', view = 'journal', data = data })
    OQ.Client.playSound('open')
end

-------------------------------------------------------------------------------
-- NUI CALLBACKS
-------------------------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    OQ.Client.closeNui()
    cb({ ok = true })
end)

RegisterNUICallback('sound', function(data, cb)
    OQ.Client.playSound(data and data.name or 'click')
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    if nuiView == 'admin' then
        cb(lib.callback.await('oqv2:admin:snapshot', false) or { error = true })
    elseif nuiView == 'journal' then
        local data = lib.callback.await('oqv2:server:getJournal', false)
        if data then data.ui = Config.UI end
        cb(data or { error = true })
    else
        cb({ error = true })
    end
end)

-- ── admin CRUD ─────────────────────────────────────────────────────────────
RegisterNUICallback('admin:save', function(data, cb)
    if nuiView ~= 'admin' then return cb({ success = false, errors = { 'Panel closed' } }) end
    cb(lib.callback.await('oqv2:admin:save', false, data.kind, data.payload) or { success = false })
end)

RegisterNUICallback('admin:delete', function(data, cb)
    if nuiView ~= 'admin' then return cb({ success = false }) end
    cb(lib.callback.await('oqv2:admin:delete', false, data.kind, data.uid) or { success = false })
end)

RegisterNUICallback('admin:toggle', function(data, cb)
    if nuiView ~= 'admin' then return cb({ success = false }) end
    cb(lib.callback.await('oqv2:admin:toggle', false, data.kind, data.uid, data.enabled) or { success = false })
end)

RegisterNUICallback('admin:duplicate', function(data, cb)
    if nuiView ~= 'admin' then return cb({ success = false }) end
    cb(lib.callback.await('oqv2:admin:duplicate', false, data.kind, data.uid) or { success = false })
end)

RegisterNUICallback('admin:player', function(data, cb)
    if nuiView ~= 'admin' then return cb({ success = false }) end
    cb(lib.callback.await('oqv2:admin:playerAction', false, data.action, data.target, data.value) or { success = false })
end)

RegisterNUICallback('admin:export', function(_, cb)
    if nuiView ~= 'admin' then return cb({ success = false }) end
    cb(lib.callback.await('oqv2:admin:export', false) or { success = false })
end)

RegisterNUICallback('admin:import', function(data, cb)
    if nuiView ~= 'admin' then return cb({ success = false }) end
    cb(lib.callback.await('oqv2:admin:import', false, data.payload) or { success = false })
end)

RegisterNUICallback('admin:reload', function(_, cb)
    if nuiView ~= 'admin' then return cb({ success = false }) end
    cb(lib.callback.await('oqv2:admin:reload', false) or { success = false })
end)

RegisterNUICallback('admin:logs', function(data, cb)
    if nuiView ~= 'admin' then return cb({}) end
    cb(lib.callback.await('oqv2:admin:logs', false, data and data.limit or 100) or {})
end)

-- ── in-game editor helpers ─────────────────────────────────────────────────
RegisterNUICallback('editor:currentCoords', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    cb({
        x = OQ.round(c.x, 2),
        y = OQ.round(c.y, 2),
        z = OQ.round(c.z, 2),
        w = OQ.round(GetEntityHeading(ped), 2),
    })
end)

RegisterNUICallback('editor:pickCoords', function(_, cb)
    -- hand control back to the player, let them walk to the spot and confirm
    setFocus(false)
    SendNUIMessage({ action = 'suspend' })
    local result = OQ.Client.runCoordPicker()
    setFocus(true)
    SendNUIMessage({ action = 'resume' })
    cb(result or { cancelled = true })
end)

RegisterNUICallback('editor:previewModel', function(data, cb)
    setFocus(false)
    SendNUIMessage({ action = 'suspend' })
    local ok = OQ.Client.previewModel(data and data.model, data and data.kind)
    setFocus(true)
    SendNUIMessage({ action = 'resume' })
    cb({ ok = ok })
end)

RegisterNUICallback('editor:teleport', function(data, cb)
    if not data or not data.coords then return cb({ ok = false }) end
    OQ.Client.closeNui(true)
    local ped = PlayerPedId()
    DoScreenFadeOut(250)
    Wait(300)
    SetEntityCoords(ped, data.coords.x + 0.0, data.coords.y + 0.0, data.coords.z + 0.0, false, false, false, false)
    if data.coords.w then SetEntityHeading(ped, data.coords.w + 0.0) end
    Wait(200)
    DoScreenFadeIn(400)
    cb({ ok = true })
end)

RegisterNUICallback('editor:waypoint', function(_, cb)
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then
        return cb({ ok = false, message = 'No waypoint set on the map' })
    end
    local coords = GetBlipInfoIdCoord(blip)
    local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, 1000.0, false)
    cb({
        ok = true,
        x = OQ.round(coords.x, 2),
        y = OQ.round(coords.y, 2),
        z = OQ.round(found and z or 30.0, 2),
        w = 0.0,
    })
end)

-- ── journal actions ────────────────────────────────────────────────────────
RegisterNUICallback('journal:abandon', function(_, cb)
    local ok = lib.callback.await('oqv2:server:abandonMission', false)
    cb({ success = ok and true or false })
end)

RegisterNUICallback('journal:route', function(data, cb)
    if not data or not data.coords then return cb({ ok = false }) end
    SetNewWaypoint(data.coords.x + 0.0, data.coords.y + 0.0)
    OQ.Client.notify(Config.UI.brand, 'Waypoint set.', 'success')
    cb({ ok = true })
end)

-------------------------------------------------------------------------------
-- ESC handling (NUI sends 'close', but keep a native fallback)
-------------------------------------------------------------------------------
CreateThread(function()
    while true do
        if nuiView then
            Wait(0)
            if IsControlJustReleased(0, 200) or IsControlJustReleased(0, 322) then  -- ESC
                OQ.Client.closeNui()
            end
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 47, true)
            DisableControlAction(0, 245, true)
        else
            Wait(300)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= OQ.resource then return end
    if nuiView then setFocus(false) end
end)
