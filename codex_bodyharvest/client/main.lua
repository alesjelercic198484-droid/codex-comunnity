--[[
    codex_bodyharvest - client
    ---------------------------------------------------------------------
    * replicates the local death state so everybody's ox_target knows when a
      body can be cut,
    * registers the ox_target options on dead players (finger / ear / tongue),
    * plays the cutting animation through ox_lib,
    * spawns the hidden dealer and his ox_target sell options,
    * draws the flashing police blip and the flashing open fire zone.

    The client only asks - every single check is repeated on the server.
]]

local ESX

if GetResourceState(Config.ESX.ExportName) == 'started' and Config.ESX.UseExport then
    pcall(function() ESX = exports[Config.ESX.ExportName]:getSharedObject() end)
end

if not ESX then
    TriggerEvent(Config.ESX.SharedObjectEvent, function(object) ESX = object end)
end

local RESOURCE = GetCurrentResourceName()

for _, dependency in ipairs({ 'ox_lib', 'ox_target', 'ox_inventory' }) do
    if GetResourceState(dependency) ~= 'started' then
        print(('[%s] WARNING: %s is not started, this resource needs it.'):format(RESOURCE, dependency))
    end
end

local partsById = {}
for _, part in ipairs(Config.Parts) do
    partsById[part.id] = part
end

local dealerPed = nil
local dealerBlip = nil
local activeBlips = {}
local optionNames = {}

local busy = false          -- a cut is being requested / played right now
local busyUntil = 0         -- hard guard, so a lost server answer cannot lock the player
local isDead = false
local deathId = 0

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------
local function debug(...)
    if Config.Debug then
        print(('[%s]'):format(RESOURCE), ...)
    end
end

local function notify(description, kind, title)
    if Config.Notify.UseOxLib and lib and lib.notify then
        lib.notify({
            title = title or Config.Notify.Title,
            description = description,
            type = kind or 'inform',
            duration = Config.Notify.Duration,
            position = Config.Notify.Position
        })
        return
    end

    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(description)
    end
end

--- Counts one item or a list of items inside ox_inventory.
local function countItems(items)
    local ok, result = pcall(function()
        return exports.ox_inventory:Search('count', items)
    end)

    if not ok or not result then
        return 0
    end

    if type(result) == 'number' then
        return result
    end

    local total = 0

    if type(result) == 'table' then
        for _, amount in pairs(result) do
            if type(amount) == 'number' then
                total = total + amount
            end
        end
    end

    return total
end

local function hasKnife()
    if not Config.Harvest.RequireKnife then
        return true
    end

    return countItems(Config.Knives) > 0
end

local function getPlayerServerId(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil
    end

    if not IsPedAPlayer(entity) then
        return nil
    end

    local index = NetworkGetPlayerIndexFromPed(entity)

    if not index or index == -1 then
        return nil
    end

    local serverId = GetPlayerServerId(index)

    if not serverId or serverId <= 0 then
        return nil
    end

    return serverId
end

local function getPlayerState(serverId)
    local ok, state = pcall(function()
        return Player(serverId).state
    end)

    if ok then
        return state
    end

    return nil
end

local function localPlayerIsDead()
    if IsEntityDead(PlayerPedId()) then
        return true
    end

    if ESX and ESX.PlayerData and ESX.PlayerData.dead then
        return true
    end

    return false
end

local function releaseBusy()
    busy = false
    busyUntil = 0
end

-- ---------------------------------------------------------------------------
-- DEATH STATE REPLICATION
-- Everybody publishes his own death state, the server validates it again with
-- the real ped health before anything can be cut off.
-- ---------------------------------------------------------------------------
local function setDeadState(value, force)
    if value == isDead and not force then
        return
    end

    isDead = value

    if value then
        deathId = deathId + 1
        LocalPlayer.state:set(Config.StateKeys.Death, deathId, true)
    end

    LocalPlayer.state:set(Config.StateKeys.Dead, value, true)
    debug('death state ->', value, 'deathId', deathId)
end

CreateThread(function()
    -- Publish the state once on start up. A "dead" flag left over from an
    -- earlier resource start would otherwise keep a living player harvestable.
    setDeadState(localPlayerIsDead(), true)

    while true do
        Wait(Config.Harvest.DeathCheckInterval)
        setDeadState(localPlayerIsDead())
    end
end)

RegisterNetEvent('esx:onPlayerDeath', function()
    setDeadState(true)
end)

AddEventHandler('baseevents:onPlayerDied', function()
    setDeadState(true)
end)

AddEventHandler('baseevents:onPlayerKilled', function()
    setDeadState(true)
end)

RegisterNetEvent('esx:onPlayerSpawn', function()
    setDeadState(false)
end)

AddEventHandler('playerSpawned', function()
    setDeadState(false)
end)

-- ---------------------------------------------------------------------------
-- TARGET OPTIONS ON DEAD PLAYERS
-- ---------------------------------------------------------------------------
local function targetIsHarvestable(entity)
    if not IsEntityDead(entity) then
        -- Some ambulance jobs keep the ped alive while the player is "down",
        -- so the replicated death state is accepted as well.
        local serverId = getPlayerServerId(entity)
        local state = serverId and getPlayerState(serverId)

        if not state or state[Config.StateKeys.Dead] ~= true then
            return false
        end
    end

    return true
end

local function canHarvest(entity, partId)
    if busy then
        return false
    end

    if not entity or not DoesEntityExist(entity) then
        return false
    end

    if entity == PlayerPedId() and not Config.Harvest.AllowSelf then
        return false
    end

    if Config.Harvest.RequireAlive and localPlayerIsDead() then
        return false
    end

    if not targetIsHarvestable(entity) then
        return false
    end

    local serverId = getPlayerServerId(entity)

    if not serverId then
        return false
    end

    local state = getPlayerState(serverId)
    local taken = state and state[Config.StateKeys.Parts]

    if taken and taken[partId] then
        return false
    end

    return hasKnife()
end

CreateThread(function()
    local options = {}

    for _, part in ipairs(Config.Parts) do
        local name = ('%s:%s'):format(RESOURCE, part.id)
        optionNames[#optionNames + 1] = name

        options[#options + 1] = {
            name = name,
            icon = part.icon,
            label = part.label,
            distance = Config.Harvest.TargetDistance,
            canInteract = function(entity)
                return canHarvest(entity, part.id)
            end,
            onSelect = function(data)
                local entity = data and data.entity

                if not canHarvest(entity, part.id) then
                    return
                end

                local serverId = getPlayerServerId(entity)

                if not serverId then
                    notify(Config.Text.InvalidTarget, 'error')
                    return
                end

                busy = true
                busyUntil = GetGameTimer() + 5000
                TriggerServerEvent('codex_bodyharvest:request', serverId, part.id)
            end
        }
    end

    exports.ox_target:addGlobalPlayer(options)
end)

-- Safety net: if the server answer is lost the player is never stuck.
CreateThread(function()
    while true do
        if busy and busyUntil > 0 and GetGameTimer() > busyUntil then
            debug('busy guard released')
            releaseBusy()
        end

        Wait(1000)
    end
end)

-- ---------------------------------------------------------------------------
-- CUTTING
-- ---------------------------------------------------------------------------
RegisterNetEvent('codex_bodyharvest:denied', function(message)
    releaseBusy()

    if message then
        notify(message, 'error')
    end
end)

RegisterNetEvent('codex_bodyharvest:begin', function(token, targetId, partId)
    local part = partsById[partId]

    if not part or not token then
        releaseBusy()
        return
    end

    busy = true
    busyUntil = GetGameTimer() + part.duration + 15000

    if not lib or not lib.progressCircle then
        print(('[%s] ox_lib is missing, the cutting animation cannot be played.'):format(RESOURCE))
        releaseBusy()
        TriggerServerEvent('codex_bodyharvest:finish', token, false)
        return
    end

    local ped = PlayerPedId()
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))

    if targetPed and targetPed ~= 0 and targetPed ~= ped then
        TaskTurnPedToFaceEntity(ped, targetPed, 800)
        Wait(300)
    end

    local success = lib.progressCircle({
        duration = part.duration,
        label = part.progress,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, sprint = true },
        anim = part.anim,
        prop = part.prop
    })

    ClearPedTasks(PlayerPedId())
    releaseBusy()

    TriggerServerEvent('codex_bodyharvest:finish', token, success and true or false)

    if not success then
        notify(Config.Text.Cancelled, 'inform')
    end
end)

RegisterNetEvent('codex_bodyharvest:notify', function(description, kind, title)
    notify(description, kind, title)
end)

-- ---------------------------------------------------------------------------
-- BLIPS
-- ---------------------------------------------------------------------------
local function trackBlip(blip)
    activeBlips[#activeBlips + 1] = blip
end

local function forgetBlip(blip)
    for index, handle in ipairs(activeBlips) do
        if handle == blip then
            table.remove(activeBlips, index)
            break
        end
    end
end

local function removeBlipSafe(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end

    forgetBlip(blip)
end

--- Flashing red point blip for the police alert.
local function createAlertBlip(coords, duration, label)
    local settings = Config.Alert.Blip
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    SetBlipSprite(blip, settings.Sprite)
    SetBlipColour(blip, settings.Colour)
    SetBlipScale(blip, settings.Scale + 0.0)
    SetBlipAlpha(blip, settings.Alpha)
    SetBlipAsShortRange(blip, false)
    SetBlipCategory(blip, 2)

    if settings.Flash then
        SetBlipFlashes(blip, true)
        SetBlipFlashInterval(blip, settings.FlashInterval)
    end

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or settings.Label)
    EndTextCommandSetBlipName(blip)

    trackBlip(blip)

    CreateThread(function()
        local expires = GetGameTimer() + (duration * 1000)
        local visible = true

        -- The blip always disappears after `duration`. AlphaFlash is only
        -- needed when a blip category ignores SetBlipFlashes.
        while DoesBlipExist(blip) and GetGameTimer() < expires do
            if settings.AlphaFlash then
                visible = not visible
                SetBlipAlpha(blip, visible and settings.Alpha or 0)
                Wait(settings.FlashInterval)
            else
                Wait(1000)
            end
        end

        removeBlipSafe(blip)
    end)

    return blip
end

--- Flashing red circle (radius blip) for the open fire zone.
local function createZoneBlip(coords, radius, duration)
    local settings = Config.OpenFireZone
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius + 0.0)

    SetBlipHighDetail(blip, true)
    SetBlipColour(blip, settings.Colour)
    SetBlipAlpha(blip, settings.Alpha)

    trackBlip(blip)

    CreateThread(function()
        local expires = GetGameTimer() + (duration * 1000)
        local visible = true

        while DoesBlipExist(blip) and GetGameTimer() < expires do
            visible = not visible
            SetBlipAlpha(blip, visible and settings.Alpha or 0)
            Wait(settings.FlashInterval)
        end

        removeBlipSafe(blip)
    end)

    return blip
end

RegisterNetEvent('codex_bodyharvest:policeAlert', function(data)
    if not data or not data.coords then
        return
    end

    local coords = vec3(data.coords.x, data.coords.y, data.coords.z)
    local settings = Config.Alert.Blip
    local street = ''

    local ok, streetHash = pcall(GetStreetNameAtCoord, coords.x, coords.y, coords.z)

    if ok and streetHash then
        street = GetStreetNameFromHashKey(streetHash) or ''
    end

    local description = data.body or Config.Text.PoliceAlertBody

    if street ~= '' then
        description = ('%s (%s)'):format(description, street)
    end

    notify(description, 'error', data.title or Config.Text.PoliceAlertTitle)
    createAlertBlip(coords, data.duration or settings.Duration, data.title or settings.Label)

    if settings.Sound then
        PlaySoundFrontend(-1, settings.SoundName, settings.SoundSet, true)
    end
end)

RegisterNetEvent('codex_bodyharvest:openFireZone', function(data)
    if not data or not data.coords then
        return
    end

    local coords = vec3(data.coords.x, data.coords.y, data.coords.z)

    createZoneBlip(coords, data.radius or Config.OpenFireZone.Radius, data.duration or Config.OpenFireZone.Duration)

    if data.notify ~= false then
        notify(data.body or Config.Text.ZoneBody, 'error', data.title or Config.Text.ZoneTitle)
    end
end)

-- ---------------------------------------------------------------------------
-- HIDDEN DEALER
-- ---------------------------------------------------------------------------
local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)

    if not IsModelInCdimage(hash) then
        return nil
    end

    RequestModel(hash)

    local timeout = GetGameTimer() + 10000

    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(20)
    end

    return HasModelLoaded(hash) and hash or nil
end

local function dealerOptions()
    local options = {}

    for index, deal in ipairs(Config.Dealer.Deals) do
        options[#options + 1] = {
            name = ('%s:sell_%s'):format(RESOURCE, deal.item),
            icon = deal.icon,
            label = ('%s ($%s each, min %s)'):format(deal.label, Config.FormatMoney(deal.price), deal.min),
            distance = Config.Dealer.Distance,
            canInteract = function()
                if localPlayerIsDead() then
                    return false
                end

                return countItems(deal.item) >= deal.min
            end,
            onSelect = function()
                TriggerServerEvent('codex_bodyharvest:sell', index)
            end
        }
    end

    return options
end

CreateThread(function()
    if not Config.Dealer.Enabled then
        return
    end

    local hash = loadModel(Config.Dealer.Model)

    if not hash then
        print(('[%s] dealer model %s could not be loaded.'):format(RESOURCE, tostring(Config.Dealer.Model)))
        return
    end

    local coords = Config.Dealer.Coords

    dealerPed = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)

    SetEntityInvincible(dealerPed, true)
    SetEntityCanBeDamaged(dealerPed, false)
    SetBlockingOfNonTemporaryEvents(dealerPed, true)
    SetPedDiesWhenInjured(dealerPed, false)
    SetPedCanRagdollFromPlayerImpact(dealerPed, false)
    SetPedFleeAttributes(dealerPed, 0, false)
    FreezeEntityPosition(dealerPed, true)

    if Config.Dealer.Scenario then
        TaskStartScenarioInPlace(dealerPed, Config.Dealer.Scenario, 0, true)
    end

    exports.ox_target:addLocalEntity(dealerPed, dealerOptions())
    SetModelAsNoLongerNeeded(hash)

    if Config.Dealer.Blip.Enabled then
        dealerBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(dealerBlip, Config.Dealer.Blip.Sprite)
        SetBlipColour(dealerBlip, Config.Dealer.Blip.Colour)
        SetBlipScale(dealerBlip, Config.Dealer.Blip.Scale + 0.0)
        SetBlipAsShortRange(dealerBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.Dealer.Blip.Label)
        EndTextCommandSetBlipName(dealerBlip)
    end
end)

-- ---------------------------------------------------------------------------
-- CLEAN UP
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then
        return
    end

    if dealerPed and DoesEntityExist(dealerPed) then
        pcall(function() exports.ox_target:removeLocalEntity(dealerPed) end)
        DeleteEntity(dealerPed)
    end

    if dealerBlip and DoesBlipExist(dealerBlip) then
        RemoveBlip(dealerBlip)
    end

    for _, blip in ipairs(activeBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    pcall(function() exports.ox_target:removeGlobalPlayer(optionNames) end)

    LocalPlayer.state:set(Config.StateKeys.Dead, nil, true)
    LocalPlayer.state:set(Config.StateKeys.Death, nil, true)
end)
