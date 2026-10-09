local QBCore = exports['qb-core']:GetCoreObject()
local RESOURCE = GetCurrentResourceName()

local vendorPeds = {}
local vendorVans = {}
local vendorIds = {}
local warehouseZones = {}
local activeVendorId = nil
local nuiOpen = false
local activeMission = nil
local missionBlip = nil
local missionProps = {}
local lastMissionInteraction = 0

local function Notify(message, kind, duration)
    QBCore.Functions.Notify(tostring(message or ''), kind or 'primary', duration or 5000)
end

local function LoadModel(modelName)
    local model = type(modelName) == 'number' and modelName or joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end
    RequestModel(model)
    local expires = GetGameTimer() + 10000
    while not HasModelLoaded(model) and GetGameTimer() < expires do
        Wait(25)
    end
    if not HasModelLoaded(model) then return nil end
    return model
end

local function IsMarketOpen()
    if not Config.MarketHours or Config.MarketHours.Enabled == false then return true end
    local hour = GetClockHours()
    local opens = tonumber(Config.MarketHours.Open) or 22
    local closes = tonumber(Config.MarketHours.Close) or 10
    if opens == closes then return true end
    if opens < closes then return hour >= opens and hour < closes end
    return hour >= opens or hour < closes
end

local function SetNuiVisible(visible)
    nuiOpen = visible == true
    SetNuiFocus(nuiOpen, nuiOpen)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = nuiOpen and 'show' or 'hide' })
end

local function OpenVendor(vendorId)
    if not IsMarketOpen() then
        Notify(Config.Notifications.ContactClosed, 'error')
        return
    end

    QBCore.Functions.TriggerCallback('codex_blackmarket:server:getData', function(response)
        if not response or not response.ok then
            Notify(response and response.message or 'The contact could not be reached.', 'error')
            return
        end
        activeVendorId = vendorId
        nuiOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = 'open', mode = 'market', data = response.data })
    end, 'market', vendorId)
end

local function OpenWarehouse(warehouseId)
    QBCore.Functions.TriggerCallback('codex_blackmarket:server:getData', function(response)
        if not response or not response.ok then
            Notify(response and response.message or 'The storage terminal could not be reached.', 'error')
            return
        end
        activeVendorId = nil
        nuiOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = 'open', mode = 'warehouse', data = response.data, warehouseId = warehouseId })
    end, 'warehouse', warehouseId)
end

local function OpenAdmin()
    QBCore.Functions.TriggerCallback('codex_blackmarket:server:adminData', function(response)
        if not response or not response.ok then
            Notify(response and response.message or 'The admin panel could not be opened.', 'error')
            return
        end
        activeVendorId = nil
        nuiOpen = true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = 'open', mode = 'admin', data = response.data })
    end)
end

local function AddMarketTarget(ped, vendor)
    local vendorId = vendor.id
    exports['qb-target']:AddTargetEntity(ped, {
        options = {
            {
                icon = 'fas fa-mask',
                label = 'Talk to the black market contact',
                action = function()
                    OpenVendor(vendorId)
                end,
                canInteract = function()
                    return IsMarketOpen()
                end
            }
        },
        distance = tonumber(vendor.targetDistance) or 2.2
    })
    vendorIds[#vendorIds + 1] = ped
end

local function SpawnVendor(vendor)
    local pedModel = LoadModel(vendor.ped or 'g_m_y_mexgoon_02')
    if not pedModel then
        print(('[%s] Could not load vendor ped model "%s".'):format(RESOURCE, tostring(vendor.ped)))
        return
    end

    local coords = vendor.coords
    local ped = CreatePed(4, pedModel, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, true)
    if not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(pedModel)
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    if vendor.scenario and vendor.scenario ~= '' then
        TaskStartScenarioInPlace(ped, vendor.scenario, 0, true)
    end
    vendorPeds[#vendorPeds + 1] = { entity = ped, vendor = vendor }
    AddMarketTarget(ped, vendor)
    SetModelAsNoLongerNeeded(pedModel)

    if vendor.van and vendor.vanCoords then
        local vanModel = LoadModel(vendor.van)
        if vanModel then
            local vanCoords = vendor.vanCoords
            local van = CreateVehicle(vanModel, vanCoords.x, vanCoords.y, vanCoords.z, vanCoords.w or 0.0, false, false)
            if DoesEntityExist(van) then
                SetEntityAsMissionEntity(van, true, true)
                SetVehicleOnGroundProperly(van)
                SetVehicleDoorsLocked(van, 2)
                SetVehicleEngineOn(van, false, true, true)
                SetVehicleUndriveable(van, true)
                FreezeEntityPosition(van, true)
                vendorVans[#vendorVans + 1] = { entity = van }
            end
            SetModelAsNoLongerNeeded(vanModel)
        end
    end
end

local function AddWarehouseTargets()
    for _, warehouse in ipairs(Config.Warehouses or {}) do
        local id = warehouse.id
        local zoneName = ('codex_blackmarket_%s'):format(id)
        local success, result = pcall(function()
            return exports['qb-target']:AddCircleZone(zoneName, warehouse.coords, 1.15, {
                name = zoneName,
                useZ = true,
                debugPoly = Config.Debug == true
            }, {
                options = {
                    {
                        icon = 'fas fa-warehouse',
                        label = ('Access %s terminal'):format(warehouse.label),
                        action = function()
                            OpenWarehouse(id)
                        end
                    }
                },
                distance = 1.8
            })
        end)
        if success then
            warehouseZones[#warehouseZones + 1] = zoneName
        else
            print(('[%s] Could not add warehouse target "%s": %s'):format(RESOURCE, id, tostring(result)))
        end
    end
end

local function ClearMissionBlip()
    if missionBlip and DoesBlipExist(missionBlip) then
        RemoveBlip(missionBlip)
    end
    missionBlip = nil
end

local function RemoveMissionProps()
    for _, object in ipairs(missionProps) do
        if DoesEntityExist(object) then
            DetachEntity(object, true, true)
            SetEntityAsMissionEntity(object, true, true)
            DeleteObject(object)
        end
    end
    missionProps = {}
end

local function ClearMission()
    ClearMissionBlip()
    RemoveMissionProps()
    activeMission = nil
end

local function CurrentMissionPoint()
    if not activeMission then return nil end
    if activeMission.stage == 'pickup' then return activeMission.pickup end
    return activeMission.drops and activeMission.drops[activeMission.currentDrop]
end

local function SetMissionWaypoint()
    ClearMissionBlip()
    local point = CurrentMissionPoint()
    if not point then return end

    missionBlip = AddBlipForCoord(point.x, point.y, point.z)
    SetBlipSprite(missionBlip, activeMission.stage == 'pickup' and 478 or 501)
    SetBlipColour(missionBlip, 46)
    SetBlipScale(missionBlip, 0.9)
    SetBlipRoute(missionBlip, true)
    SetBlipRouteColour(missionBlip, 46)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(activeMission.stage == 'pickup' and 'Cargo Pickup' or 'Cargo Handoff')
    EndTextCommandSetBlipName(missionBlip)
    SetNewWaypoint(point.x, point.y)
end

local function SpawnGroundCargo()
    RemoveMissionProps()
    if not activeMission or not activeMission.pickup then return end

    local model = LoadModel(Config.Cargo.CrateModel or 'prop_box_wood02a')
    if not model then return end
    local amount = math.max(1, math.min(tonumber(activeMission.packages) or 1, 4))
    for index = 1, amount do
        local offsetX = (index - 1) * 0.65
        local object = CreateObject(model, activeMission.pickup.x + offsetX, activeMission.pickup.y, activeMission.pickup.z - 0.95, true, true, false)
        if DoesEntityExist(object) then
            SetEntityAsMissionEntity(object, true, true)
            PlaceObjectOnGroundProperly(object)
            FreezeEntityPosition(object, true)
            missionProps[#missionProps + 1] = object
        end
    end
    SetModelAsNoLongerNeeded(model)
end

local function AttachCargoToVehicle()
    RemoveMissionProps()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    local model = LoadModel(Config.Cargo.CrateModel or 'prop_box_wood02a')
    if not model then return end
    local amount = math.max(1, math.min(tonumber(activeMission and activeMission.packages) or 1, 4))
    local bone = GetEntityBoneIndexByName(vehicle, 'boot')
    if bone == -1 then bone = GetEntityBoneIndexByName(vehicle, 'chassis') end
    if bone == -1 then bone = 0 end

    for index = 1, amount do
        local vehicleCoords = GetEntityCoords(vehicle)
        local object = CreateObject(model, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z, true, true, false)
        if DoesEntityExist(object) then
            SetEntityAsMissionEntity(object, true, true)
            local row = index - 1
            AttachEntityToEntity(object, vehicle, bone, 0.0, -1.15 - row * 0.18, 0.55 + row * 0.28, 0.0, 0.0, 0.0, false, false, true, false, 2, true)
            missionProps[#missionProps + 1] = object
        end
    end
    SetModelAsNoLongerNeeded(model)
end

local function ShowMissionHelp(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function BeginMission(mission)
    ClearMission()
    activeMission = mission
    SpawnGroundCargo()
    SetMissionWaypoint()
    Notify(('Cargo run: %s. Follow the route to load the packages.'):format(mission.tierLabel or 'Delivery'), 'success', 7000)
end

RegisterNetEvent('codex_blackmarket:client:missionUpdate', function(payload)
    if type(payload) ~= 'table' then return end
    if payload.action == 'failed' or payload.action == 'complete' then
        ClearMission()
        if payload.message then Notify(payload.message, payload.action == 'complete' and 'success' or 'error', 8000) end
        return
    end

    if payload.mission then
        local previousStage = activeMission and activeMission.stage
        activeMission = payload.mission
        if payload.action == 'pickedUp' or (previousStage == 'pickup' and activeMission.stage == 'delivery') then
            AttachCargoToVehicle()
        end
        SetMissionWaypoint()
    end
    if payload.message then Notify(payload.message, 'success', 7000) end
end)

CreateThread(function()
    while true do
        local delay = 900
        if activeMission then
            delay = 450
            local point = CurrentMissionPoint()
            if point then
                local playerCoords = GetEntityCoords(PlayerPedId())
                local distance = #(playerCoords - vector3(point.x, point.y, point.z))
                if distance < 55.0 then
                    delay = 0
                    DrawMarker(1, point.x, point.y, point.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.8, 1.8, 0.6, 107, 213, 165, 145, false, false, 2, false, nil, nil, false)
                    if distance < 2.5 then
                        if activeMission.stage == 'pickup' then
                            ShowMissionHelp(('Press ~INPUT_CONTEXT~ to load %s cargo package(s)'):format(activeMission.packages or 1))
                        else
                            ShowMissionHelp(('Press ~INPUT_CONTEXT~ to hand over cargo (%s/%s)'):format(activeMission.currentDrop or 1, activeMission.dropCount or 1))
                        end
                        if IsControlJustReleased(0, 38) and GetGameTimer() - lastMissionInteraction > 1000 then
                            lastMissionInteraction = GetGameTimer()
                            local action = activeMission.stage == 'pickup' and 'pickup' or 'deliver'
                            TriggerServerEvent('codex_blackmarket:server:missionAction', activeMission.id, action)
                        end
                    end
                end
            end
        end
        Wait(delay)
    end
end)

RegisterNUICallback('close', function(_, callback)
    SetNuiVisible(false)
    activeVendorId = nil
    callback({ ok = true })
end)

RegisterNUICallback('checkout', function(data, callback)
    QBCore.Functions.TriggerCallback('codex_blackmarket:server:checkout', function(response)
        if response and response.data then
            SendNUIMessage({ action = 'updateData', data = response.data })
        end
        callback(response or { ok = false, message = 'No response from the market.' })
    end, data)
end)

RegisterNUICallback('sell', function(data, callback)
    QBCore.Functions.TriggerCallback('codex_blackmarket:server:sell', function(response)
        if response and response.data then
            SendNUIMessage({ action = 'updateData', data = response.data })
        end
        callback(response or { ok = false, message = 'No response from the buyer.' })
    end, data)
end)

RegisterNUICallback('startMission', function(data, callback)
    local tier = data and tonumber(data.tier) or nil
    QBCore.Functions.TriggerCallback('codex_blackmarket:server:startMission', function(response)
        if response and response.ok and response.mission then
            activeVendorId = nil
            SetNuiVisible(false)
            BeginMission(response.mission)
        end
        callback(response or { ok = false, message = 'No response from the contact.' })
    end, tier, activeVendorId)
end)

RegisterNUICallback('openWarehouse', function(data, callback)
    local warehouseId = data and data.id
    local pin = data and tostring(data.pin or '') or ''
    QBCore.Functions.TriggerCallback('codex_blackmarket:server:openWarehouse', function(response)
        if response and response.ok then
            SetNuiVisible(false)
            activeVendorId = nil
            Notify(response.message or 'Warehouse access granted.', 'success')
        end
        callback(response or { ok = false, message = 'No response from the terminal.' })
    end, warehouseId, pin)
end)

RegisterNUICallback('adminUpdate', function(data, callback)
    QBCore.Functions.TriggerCallback('codex_blackmarket:server:adminUpdate', function(response)
        if response and response.data then
            SendNUIMessage({ action = 'updateAdminData', data = response.data })
        end
        callback(response or { ok = false, message = 'No response from the admin panel.' })
    end, data)
end)

RegisterNetEvent('codex_blackmarket:client:openAdmin', function()
    OpenAdmin()
end)

CreateThread(function()
    for _, vendor in ipairs(Config.Dealer.Vendors or {}) do
        SpawnVendor(vendor)
    end
    AddWarehouseTargets()
end)

-- Hide the contact outside the configured window, but keep one low-frequency
-- schedule check rather than running a frame loop.
CreateThread(function()
    while true do
        local visible = IsMarketOpen()
        for _, row in ipairs(vendorPeds) do
            if DoesEntityExist(row.entity) then
                SetEntityVisible(row.entity, visible, false)
                SetEntityCollision(row.entity, visible, visible)
            end
        end
        for _, row in ipairs(vendorVans) do
            if DoesEntityExist(row.entity) then
                SetEntityVisible(row.entity, visible, false)
                SetEntityCollision(row.entity, visible, visible)
            end
        end
        Wait(15000)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    SetNuiFocus(false, false)
    ClearMission()
    for _, ped in ipairs(vendorIds) do
        if DoesEntityExist(ped) then
            pcall(function() exports['qb-target']:RemoveTargetEntity(ped) end)
        end
    end
    for _, zoneName in ipairs(warehouseZones) do
        pcall(function() exports['qb-target']:RemoveZone(zoneName) end)
    end
    for _, row in ipairs(vendorPeds) do
        if DoesEntityExist(row.entity) then DeleteEntity(row.entity) end
    end
    for _, row in ipairs(vendorVans) do
        if DoesEntityExist(row.entity) then DeleteEntity(row.entity) end
    end
end)
