local Keys = {}
local Config = require 'config.shared'
local Utils = require 'modules.utils.client'

local function getVehicleNetId(plate, entity)
    if not plate or plate == '' then return end
    if not entity or entity == 0 or not NetworkGetEntityIsNetworked(entity) then return end
    return NetworkGetNetworkIdFromEntity(entity)
end

function Keys:createKey(plate, entity)
    local netId = getVehicleNetId(plate, entity)
    if not netId then return end
    TriggerServerEvent('qc_vehiclekeys/createKey', plate, netId)
end

function Keys:removeKey(plate, _entity, removeAll)
    plate = plate and Utils:trim(plate) or ''
    if plate == '' then return end
    TriggerServerEvent('qc_vehiclekeys/removeKey', plate, removeAll)
end

function Keys:hasKey(plate)
    if not plate or plate == '' then return false end
    return Bridge.Inventory.getItemCount('car_key', { plate = Utils:trim(plate) }) > 0
end

-- Daj ključ in odkleni vozilo
function Keys:giveKeyAndUnlock(plate, entity)
    if not plate or plate == '' then return end
    plate = Utils:trim(plate)
    if not entity or entity == 0 then return end

    self:createKey(plate, entity)
    SetVehicleDoorsLocked(entity, 1)
    SetVehicleDoorsLockedForAllPlayers(entity, false)
end

exports('createKey', function(plate, entity)
    Keys:createKey(plate, entity)
end)

exports('removeKey', function(plate, entity, removeAll)
    Keys:removeKey(plate, entity, removeAll)
end)

exports('hasKey', function(plate)
    return Keys:hasKey(plate)
end)

exports('giveKeyAndUnlock', function(plate, entity)
    Keys:giveKeyAndUnlock(plate, entity)
end)

RegisterCommand('spawnKeys', function()
    if not cache.vehicle or cache.vehicle == 0 then
        return lib.print.info('You must be in a vehicle to spawn keys')
    end
    Keys:createKey(Utils:trim(GetVehicleNumberPlateText(cache.vehicle)), cache.vehicle)
end, false)

-- Auto-give keys when entering a vehicle you own (garage/shop)
-- Enostavna verzija brez callbackov
if Config.Settings.autoGiveKeys then
    lib.onCache('vehicle', function(value)
        if not value or value == 0 then return end
        if GetPedInVehicleSeat(value, -1) ~= cache.ped then return end

        local plate = Utils:trim(GetVehicleNumberPlateText(value))
        if not plate or plate == '' then return end

        -- Če že imaš ključ, ne naredi nič
        if Keys:hasKey(plate) then return end

        -- Počakaj da se vozilo naloži
        Citizen.Wait(1500)

        -- Ponovno preveri
        if Keys:hasKey(plate) then return end

        -- Pošlji serverju da preveri lastništvo in da ključ
        TriggerServerEvent('qc_vehiclekeys/server/checkAndGiveKey', plate)
    end)
end

-- Server odgovor
RegisterNetEvent('qc_vehiclekeys/client/keyResult', function(plate, success)
    if success then
        Bridge.Notify.showNotify(locale('vehicle_unlocked'), 'success')
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(3000)
    if GetResourceState('ox_inventory') == 'started' then
        exports['ox_inventory']:displayMetadata({
            plate = locale('plate'),
        })
    end

    if GetResourceState('tgiann-inventory') == 'started' then
        exports['tgiann-inventory']:DisplayMetadata({
            plate = locale('plate'),
        })
    end
end)

return Keys