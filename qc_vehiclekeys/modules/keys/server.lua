local Keys = {}
local Utils = require 'modules.utils.server'

local function validateVehicle(playerId, plate, netId, action)
    if not playerId or playerId < 1 then
        return lib.print.error(('[%s] Invalid player ID provided'):format(action), playerId)
    end

    if not plate or plate == '' then
        return lib.print.error(('[%s] Invalid plate provided'):format(action), playerId)
    end

    -- netId ni obvezen (npr. za auto-give ali NPC robbery)
    if netId then
        local entity = NetworkGetEntityFromNetworkId(netId)
        if not entity or entity == 0 then
            if Bridge.Config.Debug then
                lib.print.error(('[%s] Invalid entity for netId'):format(action), playerId)
            end
            -- Ne prekinemo - še vedno lahko damo ključ
        end
    end

    plate = Utils:trim(plate)
    return plate
end

function Keys:createKey(playerId, plate, netId)
    plate = validateVehicle(playerId, plate, netId, 'createKey')
    if not plate then return end

    Bridge.Inventory.addItem(playerId, 'car_key', 1, { plate = plate })
end

function Keys:removeKey(playerId, plate, removeAll)
    if not playerId or playerId < 1 then
        return lib.print.error('[removeKey] Invalid player ID provided', playerId)
    end

    plate = type(plate) == 'string' and Utils:trim(plate) or ''
    if plate == '' then
        return lib.print.error('[removeKey] Invalid plate provided', playerId)
    end

    local removeCount = removeAll and Bridge.Inventory.getItemCount(playerId, 'car_key', { plate = plate }) or 1
    Bridge.Inventory.removeItem(playerId, 'car_key', removeCount, { plate = plate })
end

RegisterNetEvent('qc_vehiclekeys/createKey', function(plate, netId)
    Keys:createKey(source, plate, netId)
end)

RegisterNetEvent('qc_vehiclekeys/removeKey', function(plate, removeAll)
    Keys:removeKey(source, plate, removeAll)
end)

-- Preveri ali igralec lasti vozilo s to tablico
lib.callback.register('qc_vehiclekeys:checkVehicleOwner', function(src, plate)
    if not plate or plate == '' then return false end
    plate = Utils:trim(plate)

    local citizenid = Bridge.Framework.getPlayerIdentifier(src)
    if not citizenid then return false end

    -- Preveri v player_vehicles tabeli (qb-core standard)
    local result = MySQL.scalar.await(
        'SELECT COUNT(*) FROM player_vehicles WHERE plate = ? AND citizenid = ?',
        { plate, citizenid }
    )

    if result and result > 0 then
        Keys:createKey(src, plate, nil)
        return true
    end

    -- Fallback: preveri tudi z TRIM za tablice s presledki
    local result2 = MySQL.scalar.await(
        'SELECT COUNT(*) FROM player_vehicles WHERE TRIM(plate) = ? AND citizenid = ?',
        { plate, citizenid }
    )

    if result2 and result2 > 0 then
        Keys:createKey(src, plate, nil)
        return true
    end

    return false
end)

-- Fallback server event če callback ne dela
RegisterNetEvent('qc_vehiclekeys/server/checkAndGiveKey', function(plate)
    local src = source
    if not plate or plate == '' then return end
    plate = Utils:trim(plate)

    local citizenid = Bridge.Framework.getPlayerIdentifier(src)
    if not citizenid then return end

    local result = MySQL.scalar.await(
        'SELECT COUNT(*) FROM player_vehicles WHERE plate = ? AND citizenid = ?',
        { plate, citizenid }
    )

    if result and result > 0 then
        Keys:createKey(src, plate, nil)
        TriggerClientEvent('qc_vehiclekeys/client/keyResult', src, plate, true)
        return
    end

    local result2 = MySQL.scalar.await(
        'SELECT COUNT(*) FROM player_vehicles WHERE TRIM(plate) = ? AND citizenid = ?',
        { plate, citizenid }
    )

    if result2 and result2 > 0 then
        Keys:createKey(src, plate, nil)
        TriggerClientEvent('qc_vehiclekeys/client/keyResult', src, plate, true)
    end
end)

Citizen.CreateThread(function()
    Bridge.Framework.registerItem('car_key', function(source, item)
        local metadata = type(item) == 'table' and (item.metadata or item.info) or nil
        local plate = metadata and metadata.plate
        if not plate or plate == '' then
            if Bridge.Config.Debug then
                lib.print.error('[car_key] No plate metadata on used item', source)
            end
            return
        end

        TriggerClientEvent('qc_vehiclekeys/client/keys/useCarKey', source, Utils:trim(plate))
    end)
end)

return Keys