--[[
    client/garage.lua - spawning, tracking and returning department vehicles.
]]

local RESOURCE = GetCurrentResourceName()
local active = nil -- { vehicleId, netId, entity }

local function deleteActive()
    if active and active.entity and DoesEntityExist(active.entity) then
        SetEntityAsMissionEntity(active.entity, true, true)
        DeleteVehicle(active.entity)
    end
    active = nil
end

local function clearSpawnPoint(coords)
    local range = tonumber(Config.Garage.SpawnClearRange) or 3.0

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - coords) <= range then
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteVehicle(vehicle)
        end
    end
end

local function spawn(data)
    deleteActive()

    local model = joaat(data.model)
    RequestModel(model)

    local waited = 0
    while not HasModelLoaded(model) and waited < 200 do
        Wait(10)
        waited = waited + 1
    end

    if not HasModelLoaded(model) then
        TriggerEvent(RESOURCE .. ':client:notify', ('Model %s is not streamed'):format(data.model), 'error')
        return false
    end

    local coords = data.coords or { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 }
    local point = vector3(coords.x, coords.y, coords.z)
    clearSpawnPoint(point)

    local vehicle = CreateVehicle(model, coords.x, coords.y, coords.z, coords.heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(model)

    if not vehicle or vehicle == 0 then return false end

    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, data.plate)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehRadioStation(vehicle, 'OFF')

    if data.livery and tonumber(data.livery) >= 0 then
        SetVehicleModKit(vehicle, 0)
        SetVehicleLivery(vehicle, tonumber(data.livery))
    end

    if data.fuel then SetVehicleFuelLevel(vehicle, tonumber(data.fuel) + 0.0) end
    if data.bodyHealth then SetVehicleBodyHealth(vehicle, tonumber(data.bodyHealth) + 0.0) end
    if data.engineHealth then SetVehicleEngineHealth(vehicle, tonumber(data.engineHealth) + 0.0) end

    active = {
        vehicleId = data.id,
        entity = vehicle,
        netId = VehToNet(vehicle),
        label = data.label or data.model
    }

    TriggerEvent(RESOURCE .. ':client:notify', ('Took out %s (%s)'):format(active.label, data.plate), 'success')
    return true
end

RegisterNetEvent(RESOURCE .. ':client:spawnVehicle', function(data)
    if not data then return end
    State.CloseMenu()
    spawn(data)
end)

RegisterNetEvent(RESOURCE .. ':client:openGarage', function(payload)
    if not payload then return end
    State.OpenMenu('garage', payload)
end)

--- Return the vehicle when you park it back on the garage node.
CreateThread(function()
    while true do
        local wait = 1000

        if active and active.entity and DoesEntityExist(active.entity) then
            wait = 0
            local coords = GetEntityCoords(active.entity)

            local nearest = nil
            local nearestDistance = math.huge

            for _, dept in ipairs((State.sync and State.sync.departments) or {}) do
                if dept.id == State.deptId then
                    for _, node in ipairs(dept.nodes) do
                        if node.type == 'garage' or node.type == 'impound' then
                            local distance = #(coords - vector3(node.x, node.y, node.z))
                            if distance < nearestDistance then
                                nearestDistance = distance
                                nearest = node
                            end
                        end
                    end
                end
            end

            if nearest and nearestDistance <= (tonumber(Config.Garage.ReturnRange) or 6.0) then
                DrawMarker(1, nearest.x, nearest.y, nearest.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    4.0, 4.0, 1.0, 60, 190, 120, 100, false, true, 2, false, nil, nil, false)

                if IsControlJustReleased(0, Config.Keys.Interact or 38) then
                    local state = {
                        fuel = GetVehicleFuelLevel(active.entity),
                        bodyHealth = GetVehicleBodyHealth(active.entity),
                        engineHealth = GetVehicleEngineHealth(active.entity)
                    }

                    local vehicleId = active.vehicleId
                    deleteActive()
                    TriggerServerEvent(RESOURCE .. ':server:garageReturn', vehicleId, state)
                    wait = 800
                end
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then deleteActive() end
end)
