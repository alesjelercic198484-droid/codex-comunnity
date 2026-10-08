local Keys = {}
local Utils = require 'modules.utils.server'

function Keys:createKey(playerId, plate, netId)
    if not playerId or playerId < 1 then return end
    if not plate or plate == '' then return end
    plate = Utils:trim(plate)
    Bridge.Inventory.addItem(playerId, 'car_key', 1, { plate = plate })
end

function Keys:removeKey(playerId, plate, removeAll)
    if not playerId or playerId < 1 then return end
    plate = type(plate) == 'string' and Utils:trim(plate) or ''
    if plate == '' then return end

    local removeCount = removeAll and Bridge.Inventory.getItemCount(playerId, 'car_key', { plate = plate }) or 1
    Bridge.Inventory.removeItem(playerId, 'car_key', removeCount, { plate = plate })
end

RegisterNetEvent('qc_vehiclekeys/createKey', function(plate, netId)
    Keys:createKey(source, plate, netId)
end)

RegisterNetEvent('qc_vehiclekeys/removeKey', function(plate, removeAll)
    Keys:removeKey(source, plate, removeAll)
end)

-- Preveri lastništvo in daj ključ (enostavna verzija)
RegisterNetEvent('qc_vehiclekeys/server/checkAndGiveKey', function(plate)
    local src = source
    if not plate or plate == '' then return end
    plate = Utils:trim(plate)

    local citizenid = Bridge.Framework.getPlayerIdentifier(src)
    if not citizenid then return end

    -- Preveri v player_vehicles
    local result = MySQL.scalar.await(
        'SELECT COUNT(*) FROM player_vehicles WHERE plate = ? AND citizenid = ?',
        { plate, citizenid }
    )

    if result and result > 0 then
        Keys:createKey(src, plate, nil)
        TriggerClientEvent('qc_vehiclekeys/client/keyResult', src, plate, true)
        return
    end

    -- Fallback: TRIM match
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