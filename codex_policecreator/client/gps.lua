--[[
    client/gps.lua - sticking a physical GPS tracker on a vehicle and keeping
    its position fresh while the vehicle exists.
]]

local RESOURCE = GetCurrentResourceName()
local placing = false
local updaters = {}

local function findTargetVehicle()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local best, bestDistance = 0, 3.5

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local distance = #(coords - GetEntityCoords(vehicle))
            if distance < bestDistance then
                bestDistance = distance
                best = vehicle
            end
        end
    end

    return best
end

local function startUpdater(trackerId, netId)
    if updaters[trackerId] then return end

    updaters[trackerId] = true

    CreateThread(function()
        local vehicle = NetToVeh(netId)
        local misses = 0

        while updaters[trackerId] do
            Wait(tonumber(Config.Trackers.UpdateInterval) or 4000)

            if DoesEntityExist(vehicle) and vehicle ~= 0 then
                local coords = GetEntityCoords(vehicle)
                TriggerServerEvent(RESOURCE .. ':server:trackerUpdate', trackerId,
                    { x = coords.x, y = coords.y, z = coords.z })
                misses = 0
            else
                vehicle = NetToVeh(netId)
                misses = misses + 1
                if misses > 30 then
                    -- the vehicle is gone for good; stop reporting
                    updaters[trackerId] = nil
                    return
                end
            end
        end
    end)
end

RegisterNetEvent(RESOURCE .. ':client:useTracker', function()
    if placing then return end
    if not State.member then
        TriggerEvent(RESOURCE .. ':client:notify', 'You are not part of a department', 'error')
        return
    end

    local target = findTargetVehicle()
    if not target or target == 0 then
        TriggerEvent(RESOURCE .. ':client:notify', 'Get closer to a vehicle', 'error')
        return
    end

    placing = true
    local ped = PlayerPedId()
    local anim = Config.Trackers.Anims

    RequestAnimDict(anim.dict)
    local waited = 0
    while not HasAnimDictLoaded(anim.dict) and waited < 100 do
        Wait(10)
        waited = waited + 1
    end

    if HasAnimDictLoaded(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0,
            tonumber(Config.Trackers.PlaceTime) or 6000, tonumber(anim.flag) or 49, 0, false, false, false)
    end

    Wait(tonumber(Config.Trackers.PlaceTime) or 6000)
    ClearPedTasks(ped)

    local coords = GetEntityCoords(target)
    TriggerServerEvent(RESOURCE .. ':server:trackerPlace', {
        plate = GetVehicleNumberPlateText(target),
        netId = VehToNet(target),
        x = coords.x, y = coords.y, z = coords.z
    })

    placing = false
end)

RegisterNetEvent(RESOURCE .. ':client:trackerPlaced', function(trackerId, netId)
    if netId then startUpdater(tonumber(trackerId), tonumber(netId)) end
end)

--- The menu "recover" button: stop reporting and give the item back.
RegisterNetEvent(RESOURCE .. ':client:trackerRemoved', function(trackerId)
    updaters[tonumber(trackerId)] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then updaters = {} end
end)
