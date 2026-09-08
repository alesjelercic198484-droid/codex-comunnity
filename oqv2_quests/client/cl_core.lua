--[[ OQV2 QUESTS — Client core: state, sync, helpers | Made with CodeX Dev. ]]

OQ.Client = OQ.Client or {}

ESX = nil

OQ.State = {
    ready      = false,
    world      = { missions = {}, locations = {}, npcs = {} },
    missionMap = {},          -- [uid] = mission
    player     = {
        level = 1, xp = 0, need = 0, percent = 0, totalXP = 0,
        completed = 0, progress = {}, discovered = {}, active = nil,
    },
    discovered = {},          -- [locationUid] = true
    active     = nil,         -- active mission runtime
    nuiOpen    = false,
    isAdmin    = false,
}

-------------------------------------------------------------------------------
-- FRAMEWORK
-------------------------------------------------------------------------------
CreateThread(function()
    local attempts = 0
    while ESX == nil do
        local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and obj then ESX = obj break end
        attempts = attempts + 1
        if attempts == 20 then OQ.error('es_extended not found on the client.') end
        Wait(500)
    end
    OQ.debug('client ESX bridge ready')
end)

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------
function OQ.Client.notify(title, description, ntype, duration)
    lib.notify({
        id          = 'oqv2_' .. tostring(title),
        title       = title or Config.UI.brand,
        description = description,
        type        = ntype or 'inform',
        duration    = duration or 5000,
        position    = 'top-right',
        icon        = 'scroll',
        iconColor   = Config.UI.accent,
    })
end

function OQ.Client.playSound(name)
    if not Config.UI.sounds then return end
    local map = {
        open       = { 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        close      = { 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        click      = { 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        success    = { 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET' },
        fail       = { 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        quest_start= { 'MEDAL_BRONZE', 'HUD_AWARDS' },
        quest_alert= { 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS' },
        levelup    = { 'RANK_UP', 'HUD_AWARDS' },
    }
    local snd = map[name]
    if not snd then return end
    PlaySoundFrontend(-1, snd[1], snd[2], true)
end

function OQ.Client.loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelValid(hash) then
        OQ.warn(('invalid model "%s"'):format(tostring(model)))
        return nil
    end
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            OQ.warn(('model "%s" timed out'):format(tostring(model)))
            return nil
        end
        Wait(0)
    end
    return hash
end

function OQ.Client.loadAnim(dict)
    if not dict or dict == '' then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 8000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(0)
    end
    return true
end

function OQ.Client.gameHour()
    return GetClockHours()
end

function OQ.Client.scheduleActive(schedule)
    if not schedule or not schedule.enabled then return true end
    return OQ.hourInRange(GetClockHours(), schedule.from, schedule.to)
end

function OQ.Client.playerCoords()
    return GetEntityCoords(PlayerPedId())
end

-------------------------------------------------------------------------------
-- SYNC FROM SERVER
-------------------------------------------------------------------------------
RegisterNetEvent('oqv2:client:syncWorld', function(payload)
    if type(payload) ~= 'table' then return end
    OQ.State.world = payload

    local map = {}
    for _, m in ipairs(payload.missions or {}) do map[m.uid] = m end
    OQ.State.missionMap = map

    OQ.State.ready = true
    OQ.debug(('world synced: %d missions, %d locations, %d npc groups')
        :format(#(payload.missions or {}), #(payload.locations or {}), #(payload.npcs or {})))

    TriggerEvent('oqv2:client:worldUpdated')
end)

RegisterNetEvent('oqv2:client:syncPlayer', function(payload)
    if type(payload) ~= 'table' then return end
    OQ.State.player = payload

    local disc = {}
    for _, uid in ipairs(payload.discovered or {}) do disc[uid] = true end
    OQ.State.discovered = disc

    OQ.State.active = payload.active
    TriggerEvent('oqv2:client:playerUpdated')
end)

RegisterNetEvent('oqv2:client:discovered', function(uid, name)
    OQ.State.discovered[uid] = true
    OQ.Client.notify(Config.UI.brand, OQ.L('location_discovered', { name = name }), 'inform')
    OQ.Client.playSound('click')
    TriggerEvent('oqv2:client:worldUpdated')
end)

RegisterNetEvent('oqv2:client:teleport', function(point)
    if type(point) ~= 'table' then return end
    local ped = PlayerPedId()
    DoScreenFadeOut(300)
    Wait(350)
    SetEntityCoords(ped, point.x + 0.0, point.y + 0.0, point.z + 0.0, false, false, false, false)
    if point.w then SetEntityHeading(ped, point.w + 0.0) end
    Wait(250)
    DoScreenFadeIn(400)
end)

RegisterNetEvent('oqv2:client:policeBlip', function(coords)
    if type(coords) ~= 'table' then return end
    local blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.2)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Shots fired')
    EndTextCommandSetBlipName(blip)
    SetTimeout(120000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-------------------------------------------------------------------------------
-- BOOT
-------------------------------------------------------------------------------
CreateThread(function()
    while ESX == nil do Wait(200) end
    while not ESX.IsPlayerLoaded or not ESX.IsPlayerLoaded() do Wait(500) end
    Wait(1500)
    TriggerServerEvent('oqv2:server:playerReady')

    -- keep the server informed about the in-game hour (for mission schedules)
    while true do
        TriggerServerEvent('oqv2:server:timeSync', GetClockHours())
        Wait(60000)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= OQ.resource then return end
    CreateThread(function()
        Wait(2000)
        if ESX and ESX.IsPlayerLoaded and ESX.IsPlayerLoaded() then
            TriggerServerEvent('oqv2:server:playerReady')
        end
    end)
end)
