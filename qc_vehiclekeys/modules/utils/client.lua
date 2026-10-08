local Utils = {}

lib.locale(Bridge.Config.Language or 'en')

RegisterNUICallback('getLocales', function(_, cb)
    cb(lib.getLocales())
end)

-- Handle server-side notifications forwarded to client
RegisterNetEvent('qc_vehiclekeys/client/notify', function(message, type)
    Bridge.Notify.showNotify(message, type)
end)

function Utils:trim(str)
    if type(str) ~= 'string' then return str end
    return str:match('^%s*(.-)%s*$')
end

function Utils:getVehicleByPlate(plate)
    plate = Utils:trim(plate)
    if not plate or plate == '' then
        return nil
    end

    local vehicles = lib.getNearbyVehicles(GetEntityCoords(cache.ped), 25.0, true)
    for _, v in ipairs(vehicles) do
        if Utils:trim(GetVehicleNumberPlateText(v.vehicle)) == plate then
            return v.vehicle
        end
    end

    return nil
end

function Utils:requestControl(entity)
    if not DoesEntityExist(entity) then return false end
    if not NetworkGetEntityIsNetworked(entity) then return true end
    if NetworkHasControlOfEntity(entity) then return true end

    local timeout = GetGameTimer() + 1000
    repeat
        NetworkRequestControlOfEntity(entity)
        Citizen.Wait(0)
    until NetworkHasControlOfEntity(entity) or GetGameTimer() > timeout

    return NetworkHasControlOfEntity(entity)
end

function Utils:toggleTrunk(vehicle)
    if GetVehicleDoorAngleRatio(vehicle, 5) > 0.0 then
        SetVehicleDoorShut(vehicle, 5, false)
    else
        SetVehicleDoorOpen(vehicle, 5, false, false)
    end
end

return Utils