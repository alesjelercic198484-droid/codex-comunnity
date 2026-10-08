local Locks = {}
local Config = require 'config.shared'
local Utils = require 'modules.utils.server'

function Locks:toggleLock(playerId, netId, state, requireKey)
    if not netId or netId == 0 then
        return
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then
        return
    end

    if requireKey then
        if not playerId or playerId < 1 then
            return
        end

        local plyCoords = GetEntityCoords(GetPlayerPed(playerId))
        if #(plyCoords - GetEntityCoords(entity)) > 50.0 then
            return
        end

        local vehPlate = Utils:trim(GetVehicleNumberPlateText(entity))
        if Bridge.Inventory.getItemCount(playerId, 'car_key', {plate = vehPlate}) < 1 then
            return
        end
    end

    local notified = {}
    if playerId then
        notified[playerId] = true
        TriggerClientEvent('qc_vehiclekeys/client/locks/toggle', playerId, netId, state, requireKey and true or false)
    end

    local ownerId = NetworkGetEntityOwner(entity)
    if ownerId and ownerId > 0 and not notified[ownerId] then
        notified[ownerId] = true
        TriggerClientEvent('qc_vehiclekeys/client/locks/toggle', ownerId, netId, state)
    end

    for _, player in ipairs(lib.getNearbyPlayers(GetEntityCoords(entity), 20.0)) do
        if not notified[player.id] then
            notified[player.id] = true
            TriggerClientEvent('qc_vehiclekeys/client/locks/toggle', player.id, netId, state)
        end
    end
end

RegisterNetEvent('qc_vehiclekeys/server/locks/toggle', function(netId, state)
    Locks:toggleLock(source, netId, state, true)
end)

RegisterNetEvent('qc_vehiclekeys/server/locks/unlockTool', function(netId)
    local _source = source
    if not netId or netId == 0 then
        return
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then
        return
    end

    local plyCoords = GetEntityCoords(GetPlayerPed(_source))
    if #(plyCoords - GetEntityCoords(entity)) > 10.0 then
        return
    end

    local job = Bridge.Framework.getPlayerJob(_source)
    local jobName = type(job) == 'table' and job.name or job
    if not lib.table.contains(Config.Locks.unlockToolJobs, jobName) then
        return
    end

    Locks:toggleLock(_source, netId, true, false)
end)

exports('changeLockState', function(playerId, netId, state)
    Locks:toggleLock(playerId, netId, state, playerId and true or false)
end)

return Locks