--[[
    Backward compatibility layer (server).
    Re-implements the public exports/events of popular vehicle key resources
    on top of qc_vehiclekeys.
]]

local Compat = {}
local Config = require 'config.shared'
local Utils = require 'modules.utils.server'
local Locks = require 'modules.locks.server'

local shimmed = {}

local function shouldShim(resource)
    local state = GetResourceState(resource)
    if state == 'started' or state == 'starting' then
        lib.print.warn(('compat: %s is running, skipping its compatibility shims'):format(resource))
        return false
    end

    shimmed[resource] = true
    return true
end

AddEventHandler('onResourceStart', function(resourceName)
    if shimmed[resourceName] then
        lib.print.warn(('compat: %s just started while qc_vehiclekeys provides its compatibility shims'):format(resourceName))
    end
end)

local function registerExport(resource, exportName, fn)
    AddEventHandler(('__cfx_export_%s_%s'):format(resource, exportName), function(setCB)
        setCB(fn)
    end)
end

local function toPlayerId(playerId)
    playerId = tonumber(playerId)
    if not playerId or playerId < 1 then return end
    return playerId
end

local function toPlate(plate)
    if type(plate) ~= 'string' or plate == '' then return end
    plate = Utils:trim(plate)
    if plate == '' then return end
    return plate
end

local function plateFromEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    return toPlate(GetVehicleNumberPlateText(entity))
end

local function plateFromNetId(netId)
    if not netId or netId == 0 then return end
    return plateFromEntity(NetworkGetEntityFromNetworkId(netId))
end

local function giveKey(playerId, plate)
    playerId, plate = toPlayerId(playerId), toPlate(plate)
    if not playerId or not plate then return end
    Bridge.Inventory.addItem(playerId, 'car_key', 1, { plate = plate })
end

local function removeKey(playerId, plate, removeAll)
    playerId, plate = toPlayerId(playerId), toPlate(plate)
    if not playerId or not plate then return end

    local count = removeAll and Bridge.Inventory.getItemCount(playerId, 'car_key', { plate = plate }) or 1
    if count < 1 then return end
    Bridge.Inventory.removeItem(playerId, 'car_key', count, { plate = plate })
end

local function hasKey(playerId, plate)
    playerId, plate = toPlayerId(playerId), toPlate(plate)
    if not playerId or not plate then return false end
    return Bridge.Inventory.getItemCount(playerId, 'car_key', { plate = plate }) > 0
end

local function getAllKeys(playerId)
    playerId = toPlayerId(playerId)
    local plates = {}
    if not playerId then return plates end

    local items = Bridge.Inventory.getPlayerItems(playerId)
    if type(items) ~= 'table' then return plates end

    for _, item in pairs(items) do
        if item and item.name == 'car_key' then
            local metadata = item.metadata or item.info
            local plate = metadata and metadata.plate
            if plate then plates[#plates + 1] = plate end
        end
    end

    return plates
end

local function findVehicleByPlate(plate, playerId)
    plate = toPlate(plate)
    playerId = toPlayerId(playerId)
    if not plate or not playerId then return end

    local pedCoords = GetEntityCoords(GetPlayerPed(playerId))
    for _, vehicle in ipairs(GetAllVehicles()) do
        if Utils:trim(GetVehicleNumberPlateText(vehicle)) == plate
        and #(pedCoords - GetEntityCoords(vehicle)) <= 50.0 then
            return vehicle
        end
    end
end

local function sourceOrNil()
    local src = source
    if type(src) ~= 'number' or src < 1 then return end
    return src
end

-- qb-vehiclekeys compatibility
if shouldShim('qb-vehiclekeys') then
    registerExport('qb-vehiclekeys', 'GiveKeys', function(id, plate)
        giveKey(id, plate)
    end)

    registerExport('qb-vehiclekeys', 'RemoveKeys', function(id, plate)
        removeKey(id, plate)
    end)

    registerExport('qb-vehiclekeys', 'HasKeys', function(id, plate)
        return hasKey(id, plate)
    end)

    RegisterNetEvent('qc_vehiclekeys:compat:GiveVehicleKeys', function(receiver, plate)
        local src = sourceOrNil()
        if src and not hasKey(src, plate) then return end

        if type(receiver) == 'table' then
            for _, id in pairs(receiver) do
                giveKey(id, plate)
            end
        else
            giveKey(receiver, plate)
        end
    end)

    RegisterNetEvent('qb-vehiclekeys:server:GiveVehicleKeys', function(receiver, plate)
        local src = sourceOrNil()
        if src and not hasKey(src, plate) then return end

        if type(receiver) == 'table' then
            for _, id in pairs(receiver) do
                giveKey(id, plate)
            end
        else
            giveKey(receiver, plate)
        end
    end)

    RegisterNetEvent('qb-vehiclekeys:server:AcquireVehicleKeys', function(plate)
        local src = sourceOrNil()
        if not src then return end
        if not findVehicleByPlate(plate, src) then return end
        giveKey(src, plate)
    end)

    RegisterNetEvent('qb-vehiclekeys:server:RemoveVehicleKeys', function(plate)
        local src = sourceOrNil()
        if not src then return end
        removeKey(src, plate)
    end)

    RegisterNetEvent('qb-vehiclekeys:server:breakLockpick', function(itemName)
        local src = sourceOrNil()
        if not src then return end
        if itemName ~= 'lockpick' and itemName ~= 'advancedlockpick' then return end
        Bridge.Inventory.removeItem(src, itemName, 1)
    end)

    RegisterNetEvent('qb-vehiclekeys:server:setVehLockState', function(netId, state)
        Locks:toggleLock(sourceOrNil(), netId, state == 1, false)
    end)
end

-- qbx_vehiclekeys compatibility
if shouldShim('qbx_vehiclekeys') then
    registerExport('qbx_vehiclekeys', 'GiveKeys', function(src, vehicle)
        giveKey(src, plateFromEntity(vehicle))
    end)

    registerExport('qbx_vehiclekeys', 'RemoveKeys', function(src, vehicle)
        removeKey(src, plateFromEntity(vehicle))
    end)

    registerExport('qbx_vehiclekeys', 'HasKeys', function(src, vehicle)
        return hasKey(src, plateFromEntity(vehicle))
    end)
end

-- Renewed-Vehiclekeys compatibility
if shouldShim('Renewed-Vehiclekeys') then
    registerExport('Renewed-Vehiclekeys', 'addKey', function(src, plate)
        giveKey(src, plate)
    end)

    registerExport('Renewed-Vehiclekeys', 'removeKey', function(src, plate)
        removeKey(src, plate)
    end)

    registerExport('Renewed-Vehiclekeys', 'hasKey', function(src, plate)
        return hasKey(src, plate)
    end)
end

-- MrNewbVehicleKeys compatibility
if shouldShim('MrNewbVehicleKeys') then
    registerExport('MrNewbVehicleKeys', 'GiveKeysByPlate', function(src, plate)
        giveKey(src, plate)
    end)

    registerExport('MrNewbVehicleKeys', 'GiveKeys', function(src, netId)
        giveKey(src, plateFromNetId(netId))
    end)

    registerExport('MrNewbVehicleKeys', 'RemoveKeysByPlate', function(src, plate)
        removeKey(src, plate)
    end)

    registerExport('MrNewbVehicleKeys', 'RemoveKeys', function(src, netId)
        removeKey(src, plateFromNetId(netId))
    end)

    registerExport('MrNewbVehicleKeys', 'HasKeysByPlate', function(src, plate)
        return hasKey(src, plate)
    end)

    registerExport('MrNewbVehicleKeys', 'HaveKeys', function(src, netId)
        return hasKey(src, plateFromNetId(netId))
    end)

    registerExport('MrNewbVehicleKeys', 'SetVehicleLock', function(netId, lockStatus)
        Locks:toggleLock(nil, netId, lockStatus == 1, false)
    end)
end

for _, resource in ipairs({'qs-vehiclekeys', 'qs-carkeys'}) do
    if shouldShim(resource) then
        registerExport(resource, 'GiveKeys', function(src, plate)
            giveKey(src, plate)
        end)

        registerExport(resource, 'RemoveKeys', function(src, plate)
            removeKey(src, plate)
        end)

        registerExport(resource, 'HasKeys', function(src, plate)
            return hasKey(src, plate)
        end)
    end
end

return Compat