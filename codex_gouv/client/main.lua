local RESOURCE = GetCurrentResourceName()

local ESX
local uiOpen = false
local uiMode = 'mdt'
local tabletProp
local spawnedPeds = {}
local globalTargetAdded = false
local currentCuff
local tabletAnimation = {
    dict = 'amb@world_human_seat_wall_tablet@female@base',
    anim = 'base'
}

local function TryGetESX()
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

local function Notify(message, notificationType)
    if not message or message == '' then
        return
    end

    if GetResourceState('ox_lib') == 'started' and lib and lib.notify then
        lib.notify({ description = message, type = notificationType or 'inform' })
        return
    end

    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(message)
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function PlayerJob()
    if not ESX or type(ESX.GetPlayerData) ~= 'function' then
        return nil
    end
    local data = ESX.GetPlayerData()
    return data and data.job or nil
end

local function IsGouv()
    local job = PlayerJob()
    if not job or tostring(job.name or ''):lower() ~= tostring(Config.Job.Name):lower() then
        return false
    end
    local grade = tonumber(job.grade or job.grade_level) or 0
    return grade >= tonumber(Config.Job.MinimumGrade or 0) and grade <= tonumber(Config.Job.MaximumGrade or 5)
end

local function CloseTabletAnimation()
    local ped = PlayerPedId()
    if tabletAnimation.dict and IsEntityPlayingAnim(ped, tabletAnimation.dict, tabletAnimation.anim, 3) then
        StopAnimTask(ped, tabletAnimation.dict, tabletAnimation.anim, 2.0)
    end

    if tabletProp and DoesEntityExist(tabletProp) then
        DetachEntity(tabletProp, true, true)
        DeleteEntity(tabletProp)
    end
    tabletProp = nil
end

local function StartTabletAnimation()
    CloseTabletAnimation()

    local ped = PlayerPedId()
    local dict = tabletAnimation.dict
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Wait(25)
    end

    if not HasAnimDictLoaded(dict) then
        dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base'
        tabletAnimation.dict = dict
        RequestAnimDict(dict)
        timeout = GetGameTimer() + 5000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
            Wait(25)
        end
    end

    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, tabletAnimation.anim, 3.0, 3.0, -1, 49, 0.0, false, false, false)
    end

    local model = joaat('prop_cs_tablet')
    RequestModel(model)
    timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(25)
    end

    if HasModelLoaded(model) then
        tabletProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
        if tabletProp and DoesEntityExist(tabletProp) then
            SetEntityAsMissionEntity(tabletProp, true, true)
            SetNetworkIdExistsOnAllMachines(NetworkGetNetworkIdFromEntity(tabletProp), true)
            AttachEntityToEntity(tabletProp, ped, GetPedBoneIndex(ped, 60309), 0.03, 0.002, -0.02, 10.0, 160.0, 0.0, true, true, false, true, 1, true)
        end
        SetModelAsNoLongerNeeded(model)
    end
end

local function CloseUI()
    uiOpen = false
    SetNuiFocus(false, false)
    CloseTabletAnimation()
    SendNUIMessage({ action = 'close' })
end

local function RequestDashboard(mode, callback)
    if not TryGetESX() or type(ESX.TriggerServerCallback) ~= 'function' then
        callback({ ok = false, error = 'ESX is not ready yet.' })
        return
    end

    ESX.TriggerServerCallback(RESOURCE .. ':getDashboard', function(state)
        callback(state or { ok = false, error = 'The government tablet did not respond.' })
    end, mode or uiMode)
end

local function OpenUI(mode)
    if not IsGouv() then
        Notify('This tablet is restricted to the gouv job.', 'error')
        return
    end
    if uiOpen then
        uiMode = mode or uiMode
        SendNUIMessage({ action = 'mode', mode = uiMode })
        return
    end

    mode = mode or 'mdt'
    RequestDashboard(mode, function(state)
        if not state.ok then
            Notify(state.error or 'Government data is unavailable.', 'error')
            return
        end

        uiOpen = true
        uiMode = mode
        SetNuiFocus(true, true)
        StartTabletAnimation()
        SendNUIMessage({
            action = 'open',
            state = state,
            ui = {
                title = Config.UI.Title,
                subtitle = Config.UI.Subtitle,
                accent = Config.UI.Accent
            }
        })
    end)
end

local function UpdateUI(mode)
    if not uiOpen then
        return
    end
    RequestDashboard(mode or uiMode, function(state)
        if state.ok then
            SendNUIMessage({ action = 'update', state = state })
        else
            Notify(state.error or 'The government tablet could not refresh.', 'error')
        end
    end)
end

local function CoordinateValue(coords, index, named, fallback)
    local ok, value = pcall(function()
        return coords and coords[named]
    end)
    if ok and value ~= nil then
        return value
    end
    ok, value = pcall(function()
        return coords and coords[index]
    end)
    return ok and value ~= nil and value or fallback
end

local function RemoveTargetPed(key)
    local entry = spawnedPeds[key]
    if not entry then
        return
    end

    if entry.entity and DoesEntityExist(entry.entity) and GetResourceState('ox_target') == 'started' then
        pcall(function()
            exports.ox_target:removeLocalEntity(entry.entity, entry.targetName)
        end)
    end
    if entry.entity and DoesEntityExist(entry.entity) then
        DeleteEntity(entry.entity)
    end
    spawnedPeds[key] = nil
end

local function SpawnTargetPed(key, location, mode)
    if not location or location.Enabled == false or spawnedPeds[key] then
        return
    end
    if GetResourceState('ox_target') ~= 'started' then
        print(('[%s] ox_target is not started; %s target was not created.'):format(RESOURCE, key))
        return
    end

    local model = location.Model or 's_m_m_highsec_01'
    local modelHash = type(model) == 'number' and model or joaat(model)
    local coords = location.Coords
    local x = CoordinateValue(coords, 1, 'x', 0.0)
    local y = CoordinateValue(coords, 2, 'y', 0.0)
    local z = CoordinateValue(coords, 3, 'z', 0.0)
    local heading = CoordinateValue(coords, 4, 'w', CoordinateValue(coords, 4, 'heading', 0.0))

    RequestModel(modelHash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
        Wait(50)
    end
    if not HasModelLoaded(modelHash) then
        print(('[%s] Could not load model for %s target.'):format(RESOURCE, key))
        return
    end

    local entity = CreatePed(4, modelHash, x, y, z - 1.0, heading, false, true)
    SetModelAsNoLongerNeeded(modelHash)
    if not entity or not DoesEntityExist(entity) then
        return
    end

    local targetName = RESOURCE .. ':' .. key
    spawnedPeds[key] = { entity = entity, targetName = targetName }
    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetPedCanRagdoll(entity, false)
    SetBlockingOfNonTemporaryEvents(entity, true)
    if location.Scenario and location.Scenario ~= '' then
        TaskStartScenarioInPlace(entity, location.Scenario, 0, true)
    end

    exports.ox_target:addLocalEntity(entity, {
        {
            name = targetName,
            label = location.Label or 'Open Government Tablet',
            icon = location.Icon or 'fa-solid fa-tablet-screen-button',
            distance = Config.Target.Distance or 2.2,
            canInteract = function()
                return IsGouv()
            end,
            onSelect = function()
                OpenUI(mode)
            end
        }
    })
end

local function GetTargetServerId(entity)
    if not entity or not DoesEntityExist(entity) or not IsPedAPlayer(entity) then
        return nil
    end
    local player = NetworkGetPlayerIndexFromPed(entity)
    if player == -1 then
        return nil
    end
    return GetPlayerServerId(player)
end

local function FineInput(callback)
    if GetResourceState('ox_lib') == 'started' and lib and lib.inputDialog then
        local result = lib.inputDialog('Issue Government Fine', {
            { type = 'number', label = 'Amount', required = true, min = Config.Fines.Minimum, max = Config.Fines.Maximum }
        })
        callback(result and tonumber(result[1]) or nil)
        return
    end

    AddTextEntry('GOUV_FINE_AMOUNT', 'Enter fine amount')
    DisplayOnscreenKeyboard(1, 'GOUV_FINE_AMOUNT', '', '', '', '', '', 12)
    while UpdateOnscreenKeyboard() == 0 do
        Wait(0)
    end
    local result = GetOnscreenKeyboardResult()
    callback(result and tonumber(result) or nil)
end

local function BlockUnauthorizedRestraint()
    if not IsGouv() then
        return
    end

    local ped = PlayerPedId()
    currentCuff = nil
    SetEnableHandcuffs(ped, false)
    SetPedCanPlayGestureAnims(ped, true)
    ClearPedSecondaryTask(ped)
    TriggerServerEvent(RESOURCE .. ':unauthorizedRestraint')
    Notify('Unauthorized restraint blocked. Nearby police have been tazed.', 'error')
end

local function TargetAction(entity, action)
    local target = GetTargetServerId(entity)
    if not target then
        Notify('That target is not a networked player.', 'error')
        return
    end

    if action == 'fine' then
        FineInput(function(amount)
            if amount and amount > 0 then
                TriggerServerEvent(RESOURCE .. ':fine', target, amount)
            end
        end)
    elseif action == 'soft' or action == 'hard' then
        TriggerServerEvent(RESOURCE .. ':requestCuff', target, action)
    elseif action == 'uncuff' then
        TriggerServerEvent(RESOURCE .. ':removeCuff', target)
    end
end

local function AddGlobalPlayerTargets()
    if globalTargetAdded or GetResourceState('ox_target') ~= 'started' then
        return
    end

    globalTargetAdded = true
    exports.ox_target:addGlobalPlayer({
        {
            name = RESOURCE .. ':soft_cuff',
            label = Config.Cuffs.SoftLabel,
            icon = 'fa-solid fa-link',
            distance = Config.Target.PlayerDistance or 2.4,
            canInteract = function(entity)
                return IsGouv() and entity ~= PlayerPedId()
            end,
            onSelect = function(data)
                TargetAction(data.entity, 'soft')
            end
        },
        {
            name = RESOURCE .. ':hard_cuff',
            label = Config.Cuffs.HardLabel,
            icon = 'fa-solid fa-lock',
            distance = Config.Target.PlayerDistance or 2.4,
            canInteract = function(entity)
                return IsGouv() and entity ~= PlayerPedId()
            end,
            onSelect = function(data)
                TargetAction(data.entity, 'hard')
            end
        },
        {
            name = RESOURCE .. ':fine',
            label = 'Issue Fine',
            icon = 'fa-solid fa-file-invoice-dollar',
            distance = Config.Target.PlayerDistance or 2.4,
            canInteract = function(entity)
                return IsGouv() and entity ~= PlayerPedId()
            end,
            onSelect = function(data)
                TargetAction(data.entity, 'fine')
            end
        },
        {
            name = RESOURCE .. ':remove_cuff',
            label = 'Remove Cuffs',
            icon = 'fa-solid fa-unlock',
            distance = Config.Target.PlayerDistance or 2.4,
            canInteract = function(entity)
                return IsGouv() and entity ~= PlayerPedId()
            end,
            onSelect = function(data)
                TargetAction(data.entity, 'uncuff')
            end
        }
    })
end

RegisterNUICallback('close', function(_, callback)
    CloseUI()
    callback({ ok = true })
end)

RegisterNUICallback('refresh', function(data, callback)
    if not IsGouv() then
        CloseUI()
        callback({ ok = false, error = 'Government access revoked.' })
        return
    end
    uiMode = tostring(data and data.mode or uiMode)
    RequestDashboard(uiMode, function(state)
        if state.ok then
            SendNUIMessage({ action = 'update', state = state })
        end
        callback(state)
    end)
end)

RegisterNUICallback('armoryGive', function(data, callback)
    if not IsGouv() then
        callback({ ok = false, error = 'Government access required.' })
        return
    end
    ESX.TriggerServerCallback(RESOURCE .. ':armoryGive', function(result)
        if result and (result.message or result.error) then
            Notify(result.message or result.error, result.ok and 'success' or 'error')
        end
        callback(result or { ok = false, error = 'No response from the arsenal.' })
    end, data or {})
end)

RegisterNUICallback('externalMdt', function(_, callback)
    local bridge = Config.MDT and Config.MDT.Bridge or {}
    if not bridge.Enabled then
        callback({ ok = false, error = 'No external police MDT bridge is configured.' })
        return
    end
    if bridge.Resource and GetResourceState(bridge.Resource) ~= 'started' then
        callback({ ok = false, error = 'The configured police MDT resource is not started.' })
        return
    end

    local ok = false
    if bridge.Export and bridge.ExportName and bridge.Resource then
        ok = pcall(function()
            exports[bridge.Resource][bridge.ExportName]()
        end)
    elseif bridge.ClientEvent and bridge.ClientEvent ~= '' then
        TriggerEvent(bridge.ClientEvent)
        ok = true
    end
    callback({ ok = ok, error = ok and nil or 'The MDT bridge could not be opened.' })
end)

RegisterNUICallback('mode', function(data, callback)
    uiMode = tostring(data and data.mode or 'mdt')
    UpdateUI(uiMode)
    callback({ ok = true })
end)

RegisterNetEvent(RESOURCE .. ':notify', function(message, notificationType)
    Notify(message, notificationType)
end)

RegisterNetEvent(RESOURCE .. ':applyCuff', function(mode, source, autoRelease)
    local ped = PlayerPedId()
    currentCuff = {
        mode = mode == 'hard' and 'hard' or 'soft',
        authorized = true,
        expiresAt = autoRelease and (GetGameTimer() + (tonumber(autoRelease) * 1000)) or false,
        appliedBy = source
    }

    SetEnableHandcuffs(ped, true)
    SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
    SetPedCanPlayGestureAnims(ped, false)

    local dict = 'mp_arresting'
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Wait(25)
    end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end
end)

RegisterNetEvent(RESOURCE .. ':removeCuff', function()
    currentCuff = nil
    local ped = PlayerPedId()
    SetEnableHandcuffs(ped, false)
    SetPedCanPlayGestureAnims(ped, true)
    ClearPedSecondaryTask(ped)
end)

RegisterNetEvent(RESOURCE .. ':forceTaze', function(reason)
    local ped = PlayerPedId()
    local untilTime = GetGameTimer() + 3500
    SetPedToRagdoll(ped, 2800, 3500, 0, false, false, false)
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.35)
    Notify(reason or 'You were tazed by the government immunity protocol.', 'error')

    CreateThread(function()
        while GetGameTimer() < untilTime do
            DisableAllControlActions(0)
            Wait(0)
        end
    end)
end)

-- These observers cover police resources that notify the target with a network
-- event but do not set IsPedCuffed until a later frame. They do not grant any
-- restraint power; they only invoke the same server-side punishment path.
for _, eventName in ipairs({
    'esx_policejob:handcuff',
    'esx_policejob:drag',
    'police:client:GetCuffed',
    'police:client:SearchPlayer'
}) do
    RegisterNetEvent(eventName, function()
        if IsGouv() and not (currentCuff and currentCuff.authorized) then
            BlockUnauthorizedRestraint()
        end
    end)
end

if Config.Commands and Config.Commands.Satellite then
    RegisterCommand(Config.Commands.Satellite, function()
        OpenUI('satellite')
    end, false)
end

if Config.Commands and Config.Commands.MDT then
    RegisterCommand(Config.Commands.MDT, function()
        OpenUI('mdt')
    end, false)
end

if Config.Commands and Config.Commands.Armory then
    RegisterCommand(Config.Commands.Armory, function()
        OpenUI('armory')
    end, false)
end

CreateThread(function()
    while not TryGetESX() do
        Wait(500)
    end
    while GetResourceState('ox_target') ~= 'started' do
        Wait(500)
    end

    AddGlobalPlayerTargets()
    SpawnTargetPed('mdt', Config.Locations.MDT, 'mdt')
    SpawnTargetPed('armory', Config.Locations.Armory, 'armory')
end)

-- Refresh the live player directory/map while the tablet is open.  The server does
-- the job checks again on every callback, so a grade/job change is immediately safe.
CreateThread(function()
    while true do
        Wait(tonumber(Config.UI.RefreshMilliseconds or 2500))
        if uiOpen then
            UpdateUI(uiMode)
        end
    end
end)

-- Every client reports a lightweight position snapshot so the satellite still works
-- on servers where server-side entity coordinates are unavailable without OneSync.
CreateThread(function()
    while true do
        Wait(tonumber(Config.Security.PositionUpdateMilliseconds or 2000))
        local coords = GetEntityCoords(PlayerPedId())
        TriggerServerEvent(RESOURCE .. ':updatePosition', { x = coords.x, y = coords.y, z = coords.z })
    end
end)

-- A police resource can still call SetEnableHandcuffs locally.  This watcher removes
-- the unauthorized state immediately and asks the server to taze nearby police.
CreateThread(function()
    while true do
        Wait(tonumber(Config.Security.RestraintCheckMilliseconds or 250))
        if IsGouv() then
            local ped = PlayerPedId()
            local authorized = currentCuff and currentCuff.authorized
            if currentCuff and currentCuff.expiresAt and GetGameTimer() >= currentCuff.expiresAt then
                currentCuff = nil
                authorized = false
                SetEnableHandcuffs(ped, false)
                SetPedCanPlayGestureAnims(ped, true)
            end

            if IsPedCuffed(ped) and not authorized then
                BlockUnauthorizedRestraint()
            end
        end
    end
end)

-- Keep soft and hard cuffs meaningful even when another resource tries to
-- re-enable controls after the cuff event. Hard cuffs also immobilize movement.
CreateThread(function()
    while true do
        if currentCuff then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true) -- attack
            DisableControlAction(0, 25, true) -- aim
            DisableControlAction(0, 37, true) -- weapon wheel
            DisableControlAction(0, 45, true) -- reload
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            if currentCuff.mode == 'hard' then
                DisableControlAction(0, 21, true) -- sprint
                DisableControlAction(0, 22, true) -- jump
                DisableControlAction(0, 30, true) -- move left/right
                DisableControlAction(0, 31, true) -- move forward/back
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

RegisterNetEvent('esx:playerLoaded', function()
    Wait(1000)
    TryGetESX()
end)

RegisterNetEvent('esx:setJob', function()
    if uiOpen and not IsGouv() then
        CloseUI()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then
        return
    end
    CloseUI()
    for key in pairs(spawnedPeds) do
        RemoveTargetPed(key)
    end
    if globalTargetAdded and GetResourceState('ox_target') == 'started' then
        pcall(function()
            exports.ox_target:removeGlobalPlayer({
                RESOURCE .. ':soft_cuff',
                RESOURCE .. ':hard_cuff',
                RESOURCE .. ':fine',
                RESOURCE .. ':remove_cuff'
            })
        end)
    end
end)

exports('OpenGouvMDT', function()
    OpenUI('mdt')
end)
exports('OpenSatellite', function()
    OpenUI('satellite')
end)
exports('CloseGouvTablet', CloseUI)
