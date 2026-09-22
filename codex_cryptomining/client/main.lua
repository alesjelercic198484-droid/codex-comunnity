--[[
    Client entry point: blips, peds, targets, interaction, NUI bridge.
    The client is a renderer only, every decision is taken by the server.
]]

local Crypto = CodexCrypto
local Interior = CodexCryptoInterior
local RobClient = CodexCryptoRobClient
local RESOURCE = GetCurrentResourceName()

local ESX = nil
local bootstrapped = false
local uiOpen = false
local marketState = nil
local currentWarehouse = nil     -- warehouse the player is inside
local currentData = nil          -- last snapshot
local exitCoords = nil           -- where to teleport back
local accessCache = {}           -- warehouseId -> true
local spawnedPeds = {}
local createdBlips = {}
local targetHandles = {}
local informantBlip = nil
local busy = false

-- Forward declarations: these are referenced inside callbacks defined above
-- their implementation. Keeping them local avoids polluting the global table
-- and colliding with another resource.
local EnterWarehouse
local ExitWarehouse
local LootRig
local RefreshAccess

local function IsStarted(resourceName)
    return GetResourceState(resourceName) == 'started'
end

-- ---------------------------------------------------------------------------
-- ESX
-- ---------------------------------------------------------------------------
local function GetESX()
    if ESX then
        return ESX
    end

    if Config.ESX and Config.ESX.UseExport ~= false then
        local ok, object = pcall(function()
            return exports[Config.ESX.ExportName or 'es_extended']:getSharedObject()
        end)

        if ok and object then
            ESX = object
            return ESX
        end
    end

    TriggerEvent((Config.ESX and Config.ESX.SharedObjectEvent) or 'esx:getSharedObject', function(object)
        ESX = object
    end)

    return ESX
end

local function ServerCallback(name, ...)
    local esx = GetESX()
    if not esx then
        return nil
    end

    local promiseObject = promise.new()
    local resolved = false

    esx.TriggerServerCallback(RESOURCE .. ':' .. name, function(result)
        if not resolved then
            resolved = true
            promiseObject:resolve(result)
        end
    end, ...)

    -- Safety timeout so the UI can never hang forever.
    CreateThread(function()
        Wait(10000)
        if not resolved then
            resolved = true
            promiseObject:resolve(nil)
        end
    end)

    return Citizen.Await(promiseObject)
end

-- ---------------------------------------------------------------------------
-- UI HELPERS
-- ---------------------------------------------------------------------------
local function Notify(message, notificationType)
    if not message or message == '' then
        return
    end

    local configured = (Config.Notifications and Config.Notifications.Type) or 'builtin'

    -- Optional ox_lib integration (only when explicitly asked for).
    if configured == 'ox_lib' and IsStarted('ox_lib') then
        local ok = pcall(function()
            lib.notify({
                title = 'CryptoMining',
                description = message,
                type = notificationType == 'success' and 'success'
                    or notificationType == 'error' and 'error'
                    or 'inform',
                position = (Config.Notifications and Config.Notifications.Position) or 'top-right',
                duration = Crypto.ToInt(Config.Notifications and Config.Notifications.Duration, 5000)
            })
        end)

        if ok then
            return
        end
    end

    -- Optional ESX notification.
    if configured == 'esx' then
        local esx = GetESX()
        if esx and esx.ShowNotification then
            esx.ShowNotification(message)
            return
        end
    end

    -- Built-in toast (default): drawn by our own NUI, needs no dependency and
    -- no focus. Works whether the panel is open or not.
    SendNUIMessage({
        action = 'notify',
        message = message,
        type = notificationType == 'success' and 'success'
            or notificationType == 'error' and 'error'
            or 'inform',
        position = (Config.Notifications and Config.Notifications.Position) or 'top-right',
        duration = Crypto.ToInt(Config.Notifications and Config.Notifications.Duration, 5000)
    })
end

local function HelpText(message)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

-- Resolved by the 'progressDone' NUI callback.
local progressPromise = nil

local function Progress(label, duration)
    local configured = (Config.Progress and Config.Progress.Type) or 'builtin'
    duration = math.max(100, Crypto.ToInt(duration, 3000))

    -- Optional ox_lib integration (only when explicitly asked for).
    if configured == 'ox_lib' and IsStarted('ox_lib') then
        local ok, result = pcall(function()
            return lib.progressBar({
                duration = duration,
                label = label,
                useWhileDead = false,
                canCancel = true,
                disable = { move = true, combat = true, car = true },
                anim = { dict = 'anim@amb@machinery@speed_drill@', clip = 'operate_biker_stand_working_02_male' }
            })
        end)

        if ok then
            return result ~= false
        end
    end

    -- Optional ESX progress bar.
    if configured == 'esx' then
        local esx = GetESX()
        if esx and esx.Progressbar then
            local promiseObject = promise.new()

            esx.Progressbar(label, duration, {
                FreezePlayer = true,
                animation = { type = 'anim', dict = 'amb@world_human_bum_wash@male@low@idle_a', lib = 'idle_d' },
                onFinish = function()
                    promiseObject:resolve(true)
                end,
                onCancel = function()
                    promiseObject:resolve(false)
                end
            })

            return Citizen.Await(promiseObject) == true
        end
    end

    -- Built-in progress bar (default): drawn by our own NUI, no dependency.
    -- The player is frozen and a work animation is played for immersion.
    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)

    local dict = 'anim@amb@machinery@speed_drill@'
    RequestAnimDict(dict)
    local animTimeout = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < animTimeout do
        Wait(10)
    end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(playerPed, dict, 'operate_biker_stand_working_02_male', 4.0, -4.0, -1, 49, 0.0, false, false, false)
    end

    progressPromise = promise.new()

    -- Progress bars do NOT take focus (so movement keys still register the
    -- freeze), the NUI just renders on top.
    SendNUIMessage({
        action = 'progress',
        label = label,
        duration = duration
    })

    -- Safety timeout: if the NUI never answers, resolve anyway.
    local guard = duration + 2000
    CreateThread(function()
        Wait(guard)
        if progressPromise then
            local p = progressPromise
            progressPromise = nil
            p:resolve(true)
        end
    end)

    local finished = Citizen.Await(progressPromise) == true

    ClearPedTasks(playerPed)
    FreezeEntityPosition(playerPed, false)

    return finished
end

RegisterNUICallback('progressDone', function(data, cb)
    if progressPromise then
        local p = progressPromise
        progressPromise = nil
        p:resolve(not data or data.ok ~= false)
    end
    cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- BUILT-IN SKILLCHECK
-- ---------------------------------------------------------------------------
-- Self-contained skillcheck minigame drawn by our own NUI, so the robbery
-- needs no ox_lib and no external minigame resource. `rounds` is a list of
-- difficulties ('easy' | 'medium' | 'hard'); the player must clear them all.
local skillPromise = nil

function CodexCryptoSkillcheck(rounds, title)
    if type(rounds) ~= 'table' or #rounds == 0 then
        rounds = { 'easy' }
    end

    skillPromise = promise.new()

    -- The skillcheck DOES need focus so it can read the key press.
    SetNuiFocus(true, false)

    SendNUIMessage({
        action = 'skillcheck',
        rounds = rounds,
        title = title or Crypto.L('skillcheck_title'),
        key = 'E'
    })

    -- Safety timeout so the player can never get stuck.
    CreateThread(function()
        Wait(30000)
        if skillPromise then
            local p = skillPromise
            skillPromise = nil
            SetNuiFocus(uiOpen, uiOpen)
            p:resolve(false)
        end
    end)

    return Citizen.Await(skillPromise) == true
end

RegisterNUICallback('skillcheckDone', function(data, cb)
    if skillPromise then
        local p = skillPromise
        skillPromise = nil
        -- Restore focus to whatever state the panel was in.
        SetNuiFocus(uiOpen, uiOpen)
        p:resolve(data and data.ok == true)
    end
    cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- TARGET BRIDGE
-- ---------------------------------------------------------------------------
local function GetTargetType()
    local configured = (Config.Target and Config.Target.Type) or 'auto'

    if configured ~= 'auto' then
        return configured
    end

    if IsStarted('ox_target') then
        return 'ox_target'
    end

    if IsStarted('qb-target') then
        return 'qb-target'
    end

    return 'textui'
end

--- Adds a boxzone style interaction. Returns a handle used for cleanup.
local function AddTargetPoint(name, coords, label, icon, onSelect, distance)
    distance = distance or Crypto.ToNumber(Config.Target.Distance, 2.0)
    local targetType = GetTargetType()

    if targetType == 'ox_target' then
        local ok = pcall(function()
            exports.ox_target:addBoxZone({
                name = name,
                coords = vector3(coords.x, coords.y, coords.z),
                size = vector3(1.6, 1.6, 2.2),
                rotation = coords.w or 0.0,
                debug = Config.Debug,
                options = { {
                    name = name,
                    icon = icon or 'fa-solid fa-microchip',
                    label = label,
                    distance = distance,
                    onSelect = onSelect
                } }
            })
        end)

        if ok then
            targetHandles[#targetHandles + 1] = { type = 'ox_target', name = name }
            return name
        end
    end

    if targetType == 'qb-target' then
        local ok = pcall(function()
            exports['qb-target']:AddBoxZone(name, vector3(coords.x, coords.y, coords.z), 1.6, 1.6, {
                name = name,
                heading = coords.w or 0.0,
                minZ = coords.z - 1.5,
                maxZ = coords.z + 1.5,
                debugPoly = Config.Debug
            }, {
                options = { {
                    icon = icon or 'fa-solid fa-microchip',
                    label = label,
                    action = onSelect
                } },
                distance = distance
            })
        end)

        if ok then
            targetHandles[#targetHandles + 1] = { type = 'qb-target', name = name }
            return name
        end
    end

    -- TextUI fallback handled by the interaction thread.
    targetHandles[#targetHandles + 1] = {
        type = 'textui',
        name = name,
        coords = vector3(coords.x, coords.y, coords.z),
        label = label,
        onSelect = onSelect,
        distance = distance
    }

    return name
end

local function AddTargetEntity(entity, name, label, icon, onSelect, distance)
    if not entity or entity == 0 then
        return
    end

    distance = distance or Crypto.ToNumber(Config.Target.Distance, 2.0)
    local targetType = GetTargetType()

    if targetType == 'ox_target' then
        local ok = pcall(function()
            exports.ox_target:addLocalEntity(entity, { {
                name = name,
                icon = icon or 'fa-solid fa-microchip',
                label = label,
                distance = distance,
                onSelect = onSelect
            } })
        end)

        if ok then
            targetHandles[#targetHandles + 1] = { type = 'ox_entity', entity = entity }
            return
        end
    end

    if targetType == 'qb-target' then
        local ok = pcall(function()
            exports['qb-target']:AddTargetEntity(entity, {
                options = { {
                    icon = icon or 'fa-solid fa-microchip',
                    label = label,
                    action = onSelect
                } },
                distance = distance
            })
        end)

        if ok then
            targetHandles[#targetHandles + 1] = { type = 'qb_entity', entity = entity }
            return
        end
    end

    local coords = GetEntityCoords(entity)
    targetHandles[#targetHandles + 1] = {
        type = 'textui',
        name = name,
        coords = coords,
        label = label,
        onSelect = onSelect,
        distance = distance
    }
end

local function ClearTargets(prefix)
    local remaining = {}

    for _, handle in ipairs(targetHandles) do
        local matches = not prefix or (handle.name and handle.name:find(prefix, 1, true) == 1)

        if matches then
            pcall(function()
                if handle.type == 'ox_target' then
                    exports.ox_target:removeZone(handle.name)
                elseif handle.type == 'qb-target' then
                    exports['qb-target']:RemoveZone(handle.name)
                elseif handle.type == 'ox_entity' then
                    if handle.entity and DoesEntityExist(handle.entity) then
                        exports.ox_target:removeLocalEntity(handle.entity)
                    end
                elseif handle.type == 'qb_entity' then
                    if handle.entity and DoesEntityExist(handle.entity) then
                        exports['qb-target']:RemoveTargetEntity(handle.entity)
                    end
                end
            end)
        else
            remaining[#remaining + 1] = handle
        end
    end

    targetHandles = remaining
end

-- TextUI fallback loop: only runs when at least one textui handle exists.
CreateThread(function()
    while true do
        local sleep = 800
        local hasTextUi = false

        for _, handle in ipairs(targetHandles) do
            if handle.type == 'textui' then
                hasTextUi = true
                break
            end
        end

        if hasTextUi and not uiOpen then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local closest, closestDistance = nil, math.huge

            for _, handle in ipairs(targetHandles) do
                if handle.type == 'textui' and handle.coords then
                    local distance = #(playerCoords - handle.coords)

                    if distance <= (handle.distance or 2.0) and distance < closestDistance then
                        closest, closestDistance = handle, distance
                    end
                end
            end

            if closest then
                sleep = 0
                HelpText(Crypto.L('press_to_open', closest.label))

                if IsControlJustReleased(0, 38) then
                    sleep = 400
                    local callback = closest.onSelect

                    if callback then
                        CreateThread(function()
                            pcall(callback)
                        end)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ---------------------------------------------------------------------------
-- BLIPS
-- ---------------------------------------------------------------------------
local function CreateBlip(coords, sprite, color, scale, name, shortRange)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    SetBlipSprite(blip, Crypto.ToInt(sprite, 1))
    SetBlipColour(blip, Crypto.ToInt(color, 0))
    SetBlipScale(blip, Crypto.ToNumber(scale, 0.8))
    SetBlipAsShortRange(blip, shortRange ~= false)
    SetBlipDisplay(blip, 4)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(name or 'Blip')
    EndTextCommandSetBlipName(blip)

    createdBlips[#createdBlips + 1] = blip

    return blip
end

local function RefreshBlips()
    for _, blip in ipairs(createdBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    createdBlips = {}

    if Config.Blips.Warehouse and Config.Blips.Warehouse.enabled then
        for _, warehouse in ipairs(Config.Warehouses or {}) do
            local show = true

            if Config.Blips.OwnedOnly then
                show = accessCache[warehouse.id] == true
            end

            if show then
                local blipConfig = warehouse.blip or {}
                CreateBlip(warehouse.entrance, blipConfig.sprite or 492, blipConfig.color or 5, blipConfig.scale or 0.8,
                    ('%s - %s'):format(Config.Blips.Warehouse.name or 'Crypto Warehouse', warehouse.label),
                    Config.Blips.Warehouse.shortRange)
            end
        end
    end

    local function shopBlips(setting, locations)
        if not setting or not setting.enabled then
            return
        end

        for _, location in ipairs(locations or {}) do
            CreateBlip(location, setting.sprite, setting.color, setting.scale, setting.name, true)
        end
    end

    shopBlips(Config.Blips.TechShop, Config.TechShop.Enabled ~= false and Config.TechShop.Locations or {})
    shopBlips(Config.Blips.Broker, Config.Broker.Enabled ~= false and Config.Broker.Locations or {})
    shopBlips(Config.Blips.BlackMarket, Config.BlackMarket.Enabled ~= false and Config.BlackMarket.Locations or {})
    shopBlips(Config.Blips.Informant, Config.Informant.Enabled ~= false and Config.Informant.Locations or {})
end

-- ---------------------------------------------------------------------------
-- NUI
-- ---------------------------------------------------------------------------
local function OpenPanel(data)
    if not data then
        Notify(Crypto.L('no_access'), 'error')
        return
    end

    uiOpen = true
    currentData = data
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'open',
        warehouse = data,
        market = data.market or marketState,
        locale = {
            title = 'CRYPTO MINING',
            subtitle = data.label
        }
    })
end

local function ClosePanel()
    if not uiOpen then
        return
    end

    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb)
    ClosePanel()
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    if type(data) ~= 'table' or not currentWarehouse then
        cb({ ok = false })
        return
    end

    data.warehouseId = currentWarehouse

    local result = ServerCallback('panelAction', data)
    cb(result or { ok = false })
end)

RegisterNUICallback('refresh', function(_, cb)
    if not currentWarehouse then
        cb({ ok = false })
        return
    end

    local data = ServerCallback('getWarehouse', currentWarehouse)

    if data then
        currentData = data
        SendNUIMessage({ action = 'update', warehouse = data, market = data.market })
    end

    cb({ ok = data ~= nil })
end)

RegisterNUICallback('nearbyPlayers', function(_, cb)
    local players = {}
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    for _, otherPlayer in ipairs(GetActivePlayers()) do
        local otherPed = GetPlayerPed(otherPlayer)

        if otherPed ~= playerPed and DoesEntityExist(otherPed) then
            local distance = #(playerCoords - GetEntityCoords(otherPed))

            if distance <= 8.0 then
                players[#players + 1] = {
                    id = GetPlayerServerId(otherPlayer),
                    name = GetPlayerName(otherPlayer),
                    distance = Crypto.Round(distance, 1)
                }
            end
        end
    end

    table.sort(players, function(a, b)
        return a.distance < b.distance
    end)

    cb({ ok = true, players = players })
end)

-- ---------------------------------------------------------------------------
-- WAREHOUSE INTERIOR
-- ---------------------------------------------------------------------------
local function BuildInteriorTargets(data, robbery, lootable)
    ClearTargets('codexcrypto:interior')

    local interiorConfig = Crypto.GetInteriorConfig(data.type)
    if not interiorConfig then
        return
    end

    -- Exit
    AddTargetPoint('codexcrypto:interior:exit', interiorConfig.enter, Crypto.L('warehouse_exit'), 'fa-solid fa-door-open', function()
        ExitWarehouse()
    end, 2.5)

    if not robbery then
        AddTargetPoint('codexcrypto:interior:terminal', interiorConfig.terminal, Crypto.L('warehouse_panel'), 'fa-solid fa-laptop-code', function()
            local fresh = ServerCallback('getWarehouse', currentWarehouse)
            OpenPanel(fresh)
        end, 2.0)

        AddTargetPoint('codexcrypto:interior:power', interiorConfig.power, Crypto.L('warehouse_power'), 'fa-solid fa-bolt', function()
            local fresh = ServerCallback('getWarehouse', currentWarehouse)

            if fresh then
                OpenPanel(fresh)
                SendNUIMessage({ action = 'tab', tab = 'power' })
            end
        end, 2.0)
    end

    -- Rig interactions.
    for _, rig in ipairs(data.rigs or {}) do
        local slot = Interior.GetSlotCoords(data.type, rig.slot)

        if slot then
            local rigId = rig.id
            local name = ('codexcrypto:interior:rig:%s'):format(rigId)

            if robbery then
                local isLooted = false
                for _, entry in ipairs(lootable or {}) do
                    if entry.id == rigId and entry.looted then
                        isLooted = true
                    end
                end

                if not isLooted and Crypto.ToInt(rig.gpus, 0) > 0 then
                    AddTargetPoint(name, slot, Crypto.L('target_rig_loot'), 'fa-solid fa-hand', function()
                        LootRig(rigId)
                    end, 1.8)
                end
            else
                -- Every rig is also the computer you read the crypto status
                -- on: walk to the rig monitor and it opens the panel already
                -- focused on that rig, with a "live from this rig" banner.
                AddTargetPoint(name, slot, Crypto.L('rig_monitor_title', rig.slot), 'fa-solid fa-desktop', function()
                    local fresh = ServerCallback('getWarehouse', currentWarehouse)

                    if fresh then
                        OpenPanel(fresh)
                        SendNUIMessage({
                            action = 'selectRig',
                            rigId = rigId,
                            monitor = Crypto.L('rig_monitor_banner', rig.slot)
                        })
                    end
                end, 1.8)
            end
        end
    end
end

EnterWarehouse = function(warehouseId, asRobbery)
    if busy or currentWarehouse then
        return
    end

    busy = true

    local response = ServerCallback('enterWarehouse', warehouseId)

    if not response or not response.warehouse then
        busy = false
        Notify(Crypto.L('no_access'), 'error')
        return
    end

    local data = response.warehouse
    local interiorConfig = Crypto.GetInteriorConfig(data.type)

    if not interiorConfig then
        busy = false
        Notify(Crypto.L('failed'), 'error')
        return
    end

    local playerPed = PlayerPedId()
    exitCoords = GetEntityCoords(playerPed)

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do
        Wait(10)
    end

    currentWarehouse = warehouseId
    currentData = data

    Interior.Build(data)

    SetEntityCoords(playerPed, interiorConfig.enter.x, interiorConfig.enter.y, interiorConfig.enter.z, false, false, false, false)
    SetEntityHeading(playerPed, interiorConfig.enter.w or 0.0)

    -- Let the interior stream in before showing it.
    local timeout = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(playerPed) and GetGameTimer() < timeout do
        Wait(10)
    end

    Wait(250)

    if response.robbery then
        RobClient.Start(warehouseId)
    end

    BuildInteriorTargets(data, response.robbery, response.lootable)

    DoScreenFadeIn(600)
    busy = false
end

ExitWarehouse = function()
    if not currentWarehouse then
        return
    end

    local warehouse = Crypto.GetWarehouseConfig(currentWarehouse)

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do
        Wait(10)
    end

    ClosePanel()
    ClearTargets('codexcrypto:interior')
    Interior.Clear(false)

    local playerPed = PlayerPedId()
    local destination = warehouse and warehouse.entrance or exitCoords

    if destination then
        SetEntityCoords(playerPed, destination.x, destination.y, destination.z, false, false, false, false)

        if warehouse then
            SetEntityHeading(playerPed, (warehouse.entrance.w or 0.0) + 180.0)
        end
    end

    local timeout = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(playerPed) and GetGameTimer() < timeout do
        Wait(10)
    end

    TriggerServerEvent(RESOURCE .. ':leaveWarehouse')

    if RobClient.IsActive(currentWarehouse) then
        TriggerServerEvent(RESOURCE .. ':cancelRobbery')
        RobClient.Stop()
    end

    currentWarehouse = nil
    currentData = nil

    DoScreenFadeIn(500)
end

LootRig = function(rigId)
    if busy or not currentWarehouse then
        return
    end

    busy = true

    local success = RobClient.PlayMinigame('rig')

    if not success then
        busy = false
        Notify(Crypto.L('robbery_failed'), 'error')
        return
    end

    if not Progress(Crypto.L('target_rig_loot'), Crypto.ToInt(Config.Robbery.LootDuration, 6000)) then
        busy = false
        Notify(Crypto.L('cancelled'), 'error')
        return
    end

    local result = ServerCallback('lootRig', currentWarehouse, rigId)

    if result and result.ok then
        RobClient.MarkLooted(rigId)
        ClearTargets(('codexcrypto:interior:rig:%s'):format(rigId))
    end

    busy = false
end

-- ---------------------------------------------------------------------------
-- ENTRANCES
-- ---------------------------------------------------------------------------
local function TryEnter(warehouseId)
    if busy then
        return
    end

    if accessCache[warehouseId] then
        EnterWarehouse(warehouseId, false)
        return
    end

    -- No access: offer the robbery path.
    if Config.Robbery.Enabled == false then
        Notify(Crypto.L('no_access'), 'error')
        return
    end

    local check = ServerCallback('canStartRobbery', warehouseId)

    if not check or not check.ok then
        Notify((check and check.message) or Crypto.L('no_access'), 'error')
        return
    end

    busy = true

    local success = RobClient.PlayMinigame('door')

    if not success then
        busy = false

        if Config.Robbery.LockpickBreakChance and math.random() < Crypto.ToNumber(Config.Robbery.LockpickBreakChance, 0.25) then
            Notify(Crypto.L('robbery_lockpick_broken'), 'error')
        else
            Notify(Crypto.L('robbery_failed'), 'error')
        end

        return
    end

    local result = ServerCallback('startRobbery', warehouseId)
    busy = false

    if result and result.ok then
        EnterWarehouse(warehouseId, true)
    end
end

local function BuildEntranceTargets()
    ClearTargets('codexcrypto:entrance')

    for _, warehouse in ipairs(Config.Warehouses or {}) do
        local warehouseId = warehouse.id

        AddTargetPoint(('codexcrypto:entrance:%s'):format(warehouseId), warehouse.entrance,
            ('%s - %s'):format(Crypto.L('warehouse_enter'), warehouse.label), 'fa-solid fa-warehouse', function()
                TryEnter(warehouseId)
            end, 2.5)
    end
end

-- ---------------------------------------------------------------------------
-- PEDS & SHOPS
-- ---------------------------------------------------------------------------
local function SpawnPed(model, coords, scenario)
    local hash = Interior.LoadModel(model)

    if not hash then
        return nil
    end

    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, false)

    if not ped or ped == 0 or not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    if Config.Peds.Freeze then
        FreezeEntityPosition(ped, true)
    end

    if Config.Peds.Invincible then
        SetEntityInvincible(ped, true)
    end

    if Config.Peds.BlockEvents then
        SetBlockingOfNonTemporaryEvents(ped, true)
    end

    SetPedDiesWhenInjured(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedFleeAttributes(ped, 0, false)

    if scenario then
        TaskStartScenarioInPlace(ped, scenario, 0, true)
    end

    SetModelAsNoLongerNeeded(hash)
    spawnedPeds[#spawnedPeds + 1] = ped

    return ped
end

local function OpenShop(shop)
    local data = ServerCallback('getShop', shop)

    if not data then
        Notify(Crypto.L('invalid_action'), 'error')
        return
    end

    uiOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'openShop',
        shop = data
    })
end

RegisterNUICallback('shopAction', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false })
        return
    end

    local result = ServerCallback('shopAction', data)

    -- Refresh the catalog so the owned counters stay accurate.
    if result and result.ok and data.shop then
        local fresh = ServerCallback('getShop', data.shop)

        if fresh then
            SendNUIMessage({ action = 'updateShop', shop = fresh })
        end
    end

    cb(result or { ok = false })
end)

RegisterNUICallback('brokerAction', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false })
        return
    end

    local result = ServerCallback('shopAction', data)

    if result and result.ok then
        local fresh = ServerCallback('getBrokerList')

        if fresh then
            SendNUIMessage({ action = 'updateBroker', broker = fresh })
        end

        -- Ownership changed, refresh local caches.
        RefreshAccess()
    end

    cb(result or { ok = false })
end)

local function OpenBroker()
    local data = ServerCallback('getBrokerList')

    if not data then
        Notify(Crypto.L('failed'), 'error')
        return
    end

    uiOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'openBroker',
        broker = data
    })
end

local function BuyInformation()
    if busy then
        return
    end

    busy = true
    ServerCallback('shopAction', { action = 'informant' })
    busy = false
end

local pedZonesBuilt = false

local function BuildPeds()
    if pedZonesBuilt then
        return
    end
    pedZonesBuilt = true

    local function place(setting, label, icon, onSelect)
        if not setting or setting.Enabled == false then
            return
        end

        for index, location in ipairs(setting.Locations or {}) do
            local ped = SpawnPed(setting.Model, location, setting.Scenario)

            if ped then
                AddTargetEntity(ped, ('codexcrypto:ped:%s:%d'):format(label, index), label, icon, onSelect, 2.0)
            else
                AddTargetPoint(('codexcrypto:ped:%s:%d'):format(label, index), location, label, icon, onSelect, 2.0)
            end
        end
    end

    place(Config.TechShop, Crypto.L('techshop_target'), 'fa-solid fa-microchip', function()
        OpenShop('techshop')
    end)

    place(Config.BlackMarket, Crypto.L('blackmarket_target'), 'fa-solid fa-mask', function()
        OpenShop('blackmarket')
    end)

    place(Config.Broker, Crypto.L('broker_target'), 'fa-solid fa-building', function()
        OpenBroker()
    end)

    place(Config.Informant, Crypto.L('informant_target'), 'fa-solid fa-user-secret', function()
        BuyInformation()
    end)
end

local function ClearPeds()
    for _, ped in ipairs(spawnedPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    spawnedPeds = {}
    pedZonesBuilt = false
end

-- ---------------------------------------------------------------------------
-- BOOTSTRAP
-- ---------------------------------------------------------------------------
RefreshAccess = function()
    local data = ServerCallback('bootstrap')

    if not data then
        return false
    end

    accessCache = {}

    for _, warehouseId in ipairs(data.owned or {}) do
        accessCache[warehouseId] = true
    end

    for _, warehouseId in ipairs(data.accessible or {}) do
        accessCache[warehouseId] = true
    end

    marketState = data.market
    RefreshBlips()

    return data.ready == true
end

CreateThread(function()
    while not GetESX() do
        Wait(200)
    end

    -- Wait until the player is fully spawned.
    while not NetworkIsSessionStarted() do
        Wait(250)
    end

    Wait(1500)

    local attempts = 0
    while not bootstrapped and attempts < 40 do
        bootstrapped = RefreshAccess()

        if not bootstrapped then
            attempts = attempts + 1
            Wait(2000)
        end
    end

    BuildEntranceTargets()
    BuildPeds()
end)

-- ---------------------------------------------------------------------------
-- EVENTS
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':notify', function(message, notificationType)
    Notify(message, notificationType)
end)

RegisterNetEvent(RESOURCE .. ':marketUpdate', function(state)
    marketState = state

    if uiOpen then
        SendNUIMessage({ action = 'market', market = state })
    end
end)

RegisterNetEvent(RESOURCE .. ':warehouseUpdate', function(data)
    if not data then
        return
    end

    if currentWarehouse == data.id then
        currentData = data
        Interior.Refresh(data)

        if not RobClient.IsActive(data.id) then
            BuildInteriorTargets(data, false, nil)
        end
    end

    if uiOpen then
        SendNUIMessage({ action = 'update', warehouse = data, market = data.market })
    end
end)

RegisterNetEvent(RESOURCE .. ':robberyEnded', function(warehouseId, reason)
    RobClient.Stop()

    if reason == 'timeout' then
        Notify(Crypto.L('robbery_timeout'), 'error')
    elseif reason == 'cleared' then
        Notify(Crypto.L('robbery_finished'), 'inform')
    end

    if currentWarehouse == warehouseId then
        ExitWarehouse()
    end
end)

RegisterNetEvent(RESOURCE .. ':informantTarget', function(data)
    if not data or not data.coords then
        return
    end

    if informantBlip and DoesBlipExist(informantBlip) then
        RemoveBlip(informantBlip)
    end

    informantBlip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(informantBlip, 492)
    SetBlipColour(informantBlip, 1)
    SetBlipScale(informantBlip, 1.0)
    SetBlipRoute(informantBlip, true)
    SetBlipRouteColour(informantBlip, 1)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(data.label or 'Target')
    EndTextCommandSetBlipName(informantBlip)

    local duration = math.max(30, Crypto.ToInt(data.duration, 900))

    CreateThread(function()
        Wait(duration * 1000)

        if informantBlip and DoesBlipExist(informantBlip) then
            RemoveBlip(informantBlip)
            informantBlip = nil
        end
    end)
end)

RegisterNetEvent('esx:playerLoaded', function()
    Wait(2000)
    bootstrapped = RefreshAccess()
end)

RegisterNetEvent('esx:setJob', function()
    -- Nothing job specific on the client, kept for integrations.
end)

-- ---------------------------------------------------------------------------
-- COMMANDS & KEYS
-- ---------------------------------------------------------------------------
if Config.Commands and Config.Commands.Panel then
    RegisterCommand(Config.Commands.Panel, function()
        if not currentWarehouse then
            Notify(Crypto.L('no_access'), 'error')
            return
        end

        local data = ServerCallback('getWarehouse', currentWarehouse)
        OpenPanel(data)
    end, false)
end

if Config.KeyBinding and Config.KeyBinding.Enabled and Config.Commands and Config.Commands.Panel then
    RegisterKeyMapping(Config.Commands.Panel, 'Open the crypto mining panel', 'keyboard', Config.KeyBinding.Key or 'F7')
end

-- Close the UI with ESC / BACKSPACE.
CreateThread(function()
    while true do
        if uiOpen then
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                ClosePanel()
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- CLEANUP
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then
        return
    end

    ClosePanel()
    ClearTargets(nil)
    ClearPeds()
    Interior.Clear(false)

    for _, blip in ipairs(createdBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    if informantBlip and DoesBlipExist(informantBlip) then
        RemoveBlip(informantBlip)
    end

    if currentWarehouse then
        local warehouse = Crypto.GetWarehouseConfig(currentWarehouse)

        if warehouse then
            local playerPed = PlayerPedId()
            SetEntityCoords(playerPed, warehouse.entrance.x, warehouse.entrance.y, warehouse.entrance.z, false, false, false, false)
        end
    end
end)
