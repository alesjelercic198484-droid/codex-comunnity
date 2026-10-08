--[[
    Backward compatibility layer (client).
    Re-implements the public exports/events of popular vehicle key resources
    on top of qc_vehiclekeys, so scripts written against them keep working:
      - qb-vehiclekeys
      - qbx_vehiclekeys
      - Renewed-Vehiclekeys
      - MrNewbVehicleKeys
      - qs-vehiclekeys
      - wasabi_carlock
]]

local Compat = {}

local Utils = require 'modules.utils.client'
local Keys = require 'modules.keys.client'
local Engine = require 'modules.engine.client'
local Locks = require 'modules.locks.client'

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

AddEventHandler('onClientResourceStart', function(resourceName)
    if shimmed[resourceName] then
        lib.print.warn(('compat: %s just started while qc_vehiclekeys provides its compatibility shims'):format(resourceName))
    end
end)

local function registerExport(resource, exportName, fn)
    AddEventHandler(('__cfx_export_%s_%s'):format(resource, exportName), function(setCB)
        setCB(fn)
    end)
end

local function toPlate(plate)
    if type(plate) ~= 'string' or plate == '' then return end
    plate = Utils:trim(plate)
    if plate == '' then return end
    return plate
end

local function hasKey(plate)
    plate = toPlate(plate)
    if not plate then return false end
    return Bridge.Inventory.getItemCount('car_key', { plate = plate }) > 0
end

local function getAllKeys()
    local plates = {}
    local items = Bridge.Inventory.getPlayerItems()
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

local function findVehicleByPlate(plate)
    plate = toPlate(plate)
    if not plate then return end

    if cache.vehicle and cache.vehicle ~= 0
    and Utils:trim(GetVehicleNumberPlateText(cache.vehicle)) == plate then
        return cache.vehicle
    end

    for _, v in ipairs(lib.getNearbyVehicles(GetEntityCoords(cache.ped), 50.0, true)) do
        if Utils:trim(GetVehicleNumberPlateText(v.vehicle)) == plate then
            return v.vehicle
        end
    end
end

local function addKeyByPlate(plate)
    plate = toPlate(plate)
    if not plate then return end

    local vehicle = findVehicleByPlate(plate)
    if not vehicle then return end

    Keys:createKey(plate, vehicle)
end

local function removeKeyByPlate(plate, removeAll)
    plate = toPlate(plate)
    if not plate then return end
    Keys:removeKey(plate, nil, removeAll)
end

local function addKeyByEntity(vehicle)
    vehicle = vehicle or cache.vehicle
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local plate = toPlate(GetVehicleNumberPlateText(vehicle))
    if not plate then return end
    Keys:createKey(plate, vehicle)
end

local function removeKeyByEntity(vehicle)
    vehicle = vehicle or cache.vehicle
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local plate = toPlate(GetVehicleNumberPlateText(vehicle))
    if not plate then return end
    Keys:removeKey(plate, vehicle)
end

local function hasKeyForEntity(vehicle)
    vehicle = vehicle or cache.vehicle
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    return hasKey(GetVehicleNumberPlateText(vehicle))
end

-- qb-vehiclekeys compatibility
if shouldShim('qb-vehiclekeys') then
    registerExport('qb-vehiclekeys', 'HasKeys', function(plate)
        return hasKey(plate)
    end)

    registerExport('qb-vehiclekeys', 'addNoLockVehicles', function(_model) end)
    registerExport('qb-vehiclekeys', 'removeNoLockVehicles', function(_model) end)

    RegisterNetEvent('qb-vehiclekeys:client:AddKeys', function(plate)
        addKeyByPlate(plate)
    end)

    RegisterNetEvent('qb-vehiclekeys:client:RemoveKeys', function(plate)
        removeKeyByPlate(plate)
    end)

    RegisterNetEvent('qb-vehiclekeys:client:ToggleEngine', function()
        Engine:toggleEngine()
    end)

    RegisterNetEvent('qb-vehiclekeys:client:GiveKeys', function(id)
        local vehicle = cache.vehicle
        if not vehicle or vehicle == 0 then return end

        local plate = toPlate(GetVehicleNumberPlateText(vehicle))
        if not plate or not hasKey(plate) then return end

        local target = tonumber(id)
        if not target then
            local playerId = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
            if not playerId then return end
            target = GetPlayerServerId(playerId)
        end

        if not target or target < 1 then return end
        TriggerServerEvent('qc_vehiclekeys:compat:GiveVehicleKeys', target, plate)
    end)
end

-- qbx_vehiclekeys compatibility
if shouldShim('qbx_vehiclekeys') then
    registerExport('qbx_vehiclekeys', 'HasKeys', function(vehicle)
        return hasKeyForEntity(vehicle)
    end)
end

-- Renewed-Vehiclekeys compatibility
if shouldShim('Renewed-Vehiclekeys') then
    registerExport('Renewed-Vehiclekeys', 'addKey', function(plate)
        addKeyByPlate(plate)
    end)

    registerExport('Renewed-Vehiclekeys', 'removeKey', function(plate)
        removeKeyByPlate(plate)
    end)

    registerExport('Renewed-Vehiclekeys', 'hasKey', function(plate)
        return hasKey(plate)
    end)
end

-- MrNewbVehicleKeys compatibility
if shouldShim('MrNewbVehicleKeys') then
    local tempKey = false

    registerExport('MrNewbVehicleKeys', 'GiveKeysByPlate', function(plate)
        addKeyByPlate(plate)
    end)

    registerExport('MrNewbVehicleKeys', 'GiveKeys', function(vehicle)
        addKeyByEntity(vehicle)
    end)

    registerExport('MrNewbVehicleKeys', 'RemoveKeysByPlate', function(plate)
        removeKeyByPlate(plate)
    end)

    registerExport('MrNewbVehicleKeys', 'RemoveKeys', function(vehicle)
        removeKeyByEntity(vehicle)
    end)

    registerExport('MrNewbVehicleKeys', 'HasKeysByPlate', function(plate)
        return tempKey or hasKey(plate)
    end)

    registerExport('MrNewbVehicleKeys', 'HaveKeys', function(vehicle)
        return tempKey or hasKeyForEntity(vehicle)
    end)

    registerExport('MrNewbVehicleKeys', 'GetVehicleState', function()
        if tempKey then return true end
        local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 10.0, true)
        if not vehicle then return false end
        return hasKeyForEntity(vehicle)
    end)

    registerExport('MrNewbVehicleKeys', 'ToggleTempKey', function(state)
        tempKey = state and true or false
    end)

    registerExport('MrNewbVehicleKeys', 'GetTempKey', function()
        return tempKey
    end)
end

-- qs-vehiclekeys compatibility
if shouldShim('qs-vehiclekeys') then
    registerExport('qs-vehiclekeys', 'GiveKeys', function(plate, _model, _bypass)
        addKeyByPlate(plate)
    end)

    registerExport('qs-vehiclekeys', 'RemoveKeys', function(plate, _model)
        removeKeyByPlate(plate)
    end)

    registerExport('qs-vehiclekeys', 'GiveKeysAuto', function()
        local vehicle = cache.vehicle
        if not vehicle or vehicle == 0 then return end
        local plate = toPlate(GetVehicleNumberPlateText(vehicle))
        if not plate then return end
        addKeyByPlate(plate)
    end)

    registerExport('qs-vehiclekeys', 'RemoveKeysAuto', function()
        local vehicle = cache.vehicle
        if not vehicle or vehicle == 0 then return end
        local plate = toPlate(GetVehicleNumberPlateText(vehicle))
        if not plate then return end
        removeKeyByPlate(plate)
    end)
end

-- wasabi_carlock compatibility
if shouldShim('wasabi_carlock') then
    registerExport('wasabi_carlock', 'ToggleLock', function()
        Locks:toggleLock()
    end)

    registerExport('wasabi_carlock', 'HasKey', function(plate)
        return hasKey(plate)
    end)

    registerExport('wasabi_carlock', 'GiveKey', function(plate)
        addKeyByPlate(plate)
        return toPlate(plate)
    end)

    registerExport('wasabi_carlock', 'RemoveKey', function(plate)
        removeKeyByPlate(plate, true)
        return true
    end)

    registerExport('wasabi_carlock', 'GetAllKeys', function()
        return getAllKeys()
    end)
end

return Compat