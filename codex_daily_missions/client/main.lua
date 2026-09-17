local RESOURCE = GetCurrentResourceName()

local ESX = nil
local uiOpen = false
local missionPed = nil
local targetName = RESOURCE .. ':mission_ped'

local function TryGetESX()
    if ESX then
        return ESX
    end

    if Config.ESX and Config.ESX.UseExport ~= false then
        local exportName = Config.ESX.ExportName or 'es_extended'
        local ok, object = pcall(function()
            return exports[exportName]:getSharedObject()
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

    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(message)
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function CloseUI()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'close'
    })
end

local function OpenUI()
    if uiOpen then
        return
    end

    if not TryGetESX() then
        Notify(Config.Notifications and Config.Notifications.NotReady or 'Daily mission data is not ready.', 'error')
        return
    end

    ESX.TriggerServerCallback(RESOURCE .. ':getState', function(state)
        if not state or state.ok == false then
            Notify((state and state.error) or (Config.Notifications and Config.Notifications.NotReady) or 'Daily mission data is not ready.', 'error')
            return
        end

        uiOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'open',
            state = state,
            ui = {
                title = Config.UI and Config.UI.Title or 'Daily Missions',
                subtitle = Config.UI and Config.UI.Subtitle or '',
                accentColor = Config.UI and Config.UI.AccentColor or '#26f3c9'
            }
        })
    end)
end

local function CoordValue(coords, index, fieldName, fallback)
    local ok, value = pcall(function()
        return coords and coords[fieldName]
    end)

    if ok and value ~= nil then
        return value
    end

    ok, value = pcall(function()
        return coords and coords[index]
    end)

    if ok and value ~= nil then
        return value
    end

    return fallback
end

local function RemoveMissionPed()
    if missionPed and DoesEntityExist(missionPed) then
        if GetResourceState('ox_target') == 'started' then
            pcall(function()
                exports.ox_target:removeLocalEntity(missionPed, targetName)
            end)
        end

        DeleteEntity(missionPed)
    end

    missionPed = nil
end

local function SpawnMissionPed()
    local pedConfig = Config.MissionPed or {}

    if pedConfig.Enabled == false then
        return
    end

    if missionPed and DoesEntityExist(missionPed) then
        return
    end

    if GetResourceState('ox_target') ~= 'started' then
        print(('[%s] ox_target is not started. Daily mission ped target was not created.'):format(RESOURCE))
        return
    end

    local model = pedConfig.Model or 'a_m_m_business_01'
    local modelHash = type(model) == 'number' and model or GetHashKey(model)
    local coords = pedConfig.Coords or vector4(215.76, -810.12, 30.73, 340.0)
    local x = CoordValue(coords, 1, 'x', 215.76)
    local y = CoordValue(coords, 2, 'y', -810.12)
    local z = CoordValue(coords, 3, 'z', 30.73)
    local heading = CoordValue(coords, 4, 'w', CoordValue(coords, 4, 'heading', 0.0))

    RequestModel(modelHash)

    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(modelHash) do
        Wait(50)
        if GetGameTimer() >= timeout then
            print(('[%s] Failed to load mission ped model: %s'):format(RESOURCE, tostring(model)))
            return
        end
    end

    missionPed = CreatePed(4, modelHash, x, y, z - 1.0, heading, false, true)

    if not missionPed or not DoesEntityExist(missionPed) then
        print(('[%s] Failed to create mission ped.'):format(RESOURCE))
        SetModelAsNoLongerNeeded(modelHash)
        missionPed = nil
        return
    end

    SetEntityAsMissionEntity(missionPed, true, true)
    SetEntityHeading(missionPed, heading)

    if pedConfig.Freeze ~= false then
        FreezeEntityPosition(missionPed, true)
    end

    if pedConfig.Invincible ~= false then
        SetEntityInvincible(missionPed, true)
        SetPedDiesWhenInjured(missionPed, false)
        SetPedCanRagdoll(missionPed, false)
    end

    if pedConfig.BlockEvents ~= false then
        SetBlockingOfNonTemporaryEvents(missionPed, true)
    end

    if pedConfig.Scenario and pedConfig.Scenario ~= '' then
        TaskStartScenarioInPlace(missionPed, pedConfig.Scenario, 0, true)
    end

    local targetConfig = pedConfig.Target or {}
    exports.ox_target:addLocalEntity(missionPed, {
        {
            name = targetName,
            label = targetConfig.Label or 'Open Daily Missions',
            icon = targetConfig.Icon or 'fa-solid fa-calendar-check',
            distance = pedConfig.Distance or 2.0,
            onSelect = function()
                OpenUI()
            end
        }
    })

    SetModelAsNoLongerNeeded(modelHash)
end

RegisterNUICallback('close', function(_, callback)
    CloseUI()
    callback({ ok = true })
end)

RegisterNUICallback('refresh', function(_, callback)
    if not ESX then
        callback({ ok = false, error = 'ESX is not ready.' })
        return
    end

    ESX.TriggerServerCallback(RESOURCE .. ':getState', function(state)
        if state and state.ok then
            SendNUIMessage({
                action = 'update',
                state = state
            })
        end

        callback({
            ok = state and state.ok == true,
            state = state,
            error = state and state.error or nil
        })
    end)
end)

RegisterNUICallback('claim', function(data, callback)
    if not ESX then
        callback({ ok = false, error = 'ESX is not ready.' })
        return
    end

    ESX.TriggerServerCallback(RESOURCE .. ':claim', function(result)
        if result and result.state then
            SendNUIMessage({
                action = 'update',
                state = result.state
            })
        end

        if result and result.error then
            Notify(result.error, 'error')
        elseif result and result.message then
            Notify(result.message, 'success')
        end

        callback(result or { ok = false, error = 'No response from server.' })
    end, {
        dayKey = data and data.dayKey or nil,
        missionKey = data and data.missionKey or nil
    })
end)

RegisterNetEvent(RESOURCE .. ':notify', function(message, notificationType)
    Notify(message, notificationType)
end)

RegisterNetEvent(RESOURCE .. ':stateUpdated', function(state)
    if uiOpen then
        SendNUIMessage({
            action = 'update',
            state = state
        })
    end
end)

if Config.OpenCommand and Config.OpenCommand ~= '' then
    RegisterCommand(Config.OpenCommand, function()
        OpenUI()
    end, false)
end

CreateThread(function()
    while not TryGetESX() do
        Wait(500)
    end

    SpawnMissionPed()
end)

CreateThread(function()
    while true do
        Wait(60000)
        TriggerServerEvent(RESOURCE .. ':heartbeat', {
            active = not IsPauseMenuActive() and NetworkIsPlayerActive(PlayerId())
        })
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE then
        RemoveMissionPed()
    end
end)

exports('OpenDailyMissions', OpenUI)
exports('CloseDailyMissions', CloseUI)
