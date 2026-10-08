local Engine = {}
local Config = require 'config.shared'
local Utils = require 'modules.utils.client'
local Locks = require 'modules.locks.client'

lib.onCache('ped', function(value)
    Engine:applyFlags()
end)

lib.onCache('vehicle', function(value)
    if not value or value == 0 then return end

    Engine:applyFlags()
    SetVehicleNeedsToBeHotwired(value, false)

    -- Ugasni motor za VSA vozila - igralec mora imeti ključ in pritisniti Y
    if GetPedInVehicleSeat(value, -1) == cache.ped then
        SetVehicleEngineOn(value, false, true, true)
    end
end)

function Engine:applyFlags()
    local playerPed = cache.ped
    SetPedConfigFlag(playerPed, 241, true) -- Prevent engine stopping
    SetPedConfigFlag(playerPed, 429, true) -- Prevent engine starting
    SetPedConfigFlag(playerPed, 184, true) -- Prevent auto-shuffle
end

Citizen.CreateThread(function()
    Engine:applyFlags()

    local lockAmbient = Config.Locks.lockNpcVehicles or Config.Locks.lockParkedVehicles

    while true do
        local sleep = cache.vehicle and 500 or 0

        if not cache.vehicle then
            local vehicle = GetVehiclePedIsTryingToEnter(cache.ped)
            if vehicle and vehicle ~= 0 then
                SetVehicleNeedsToBeHotwired(vehicle, false)

                if lockAmbient
                and not IsVehiclePreviouslyOwnedByPlayer(vehicle)
                and not Locks.theftUnlocked[vehicle]
                and (GetVehicleDoorLockStatus(vehicle) < 2
                or GetVehicleDoorLockStatus(vehicle) == 7) then
                    local driverPed = GetPedInVehicleSeat(vehicle, -1)
                    local hasNpcDriver = driverPed ~= 0 and not IsPedAPlayer(driverPed)
                    local isParked = driverPed == 0

                    if (hasNpcDriver and Config.Locks.lockNpcVehicles)
                    or (isParked and Config.Locks.lockParkedVehicles) then
                        SetVehicleDoorsLocked(vehicle, 2)
                    end
                end
            end
        end

        Citizen.Wait(sleep)
    end
end)

function Engine:toggleEngine()
    local vehicle = cache.vehicle
    if not vehicle or vehicle == 0 then return end
    local vehicleClass = GetVehicleClass(vehicle)
    if Config.Engine.ignoreBikes and vehicleClass == 13 then
        return
    end

    local driverPed = GetPedInVehicleSeat(vehicle, -1)
    if driverPed ~= cache.ped then return end

    local vehPlate = Utils:trim(GetVehicleNumberPlateText(vehicle))
    local itemCount = Bridge.Inventory.getItemCount('car_key', {plate = vehPlate})
    if itemCount < 1 then
        Bridge.Notify.showNotify(locale('vehicle_locked'), 'error')
        return
    end

    local engineOn = GetIsVehicleEngineRunning(vehicle)
    if engineOn then
        -- Ugasni motor
        SetVehicleEngineOn(vehicle, false, true, true)
        Bridge.Notify.showNotify(locale('engine_off'), 'success')
    else
        -- Prižgi motor
        SetVehicleEngineOn(vehicle, true, true, true)
        Bridge.Notify.showNotify(locale('engine_on'), 'success')
    end
end

-- Kontinuiran thread: prepreči vožnjo brez ključa
Citizen.CreateThread(function()
    while true do
        local sleep = 1000

        if cache.vehicle and cache.seat == -1 then
            sleep = 500
            local vehicle = cache.vehicle
            local vehicleClass = GetVehicleClass(vehicle)

            -- Kolesa so izvzeta če je ignoreBikes
            if not (Config.Engine.ignoreBikes and vehicleClass == 13) then
                local vehPlate = Utils:trim(GetVehicleNumberPlateText(vehicle))
                local itemCount = Bridge.Inventory.getItemCount('car_key', {plate = vehPlate})

                -- Če igralec nima ključa in motor teče, ugasni motor
                if itemCount < 1 and GetIsVehicleEngineRunning(vehicle) then
                    SetVehicleEngineOn(vehicle, false, true, true)
                end
            end
        end

        Citizen.Wait(sleep)
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(1000)
    if Config.Engine.keyBind then
        lib.addKeybind({
            name = 'qc_vehiclekeys/toggleEngine',
            description = locale('keybind_toggle_engine'),
            defaultKey = Config.Engine.keyBind,
            onPressed = function()
                Engine:toggleEngine()
            end,
        })
    end

    Engine:applyFlags()
end)

if Config.Engine.ignoreBikes then
    lib.onCache('vehicle', function(value)
        if value and value ~= 0 then
            local vehicleClass = GetVehicleClass(value)
            if vehicleClass ~= 13 then
                return
            end

            SetVehicleEngineOn(value, true, true, true)
        end
    end)
end

if Config.Settings.keepSteeringWheel then
    local steeringAngles = {}
    local inVehicle = false
    lib.onCache('vehicle', function(value)
        inVehicle = value and value ~= 0
        if not value or value == 0 then
            local lastVehicle = GetVehiclePedIsIn(cache.ped, true)
            if lastVehicle and lastVehicle ~= 0 then
                local steeringAngle = steeringAngles[lastVehicle] or 0.0
                SetVehicleSteeringAngle(lastVehicle, steeringAngle)
                steeringAngles[lastVehicle] = nil
            end
        else
            Citizen.CreateThread(function()
                while inVehicle do
                    local currentVehicle = cache.vehicle
                    if not currentVehicle or currentVehicle == 0 or cache.seat ~= -1 then
                        break
                    end

                    local steeringAngle = GetVehicleSteeringAngle(currentVehicle)
                    if not GetIsTaskActive(cache.ped, 2) and steeringAngle and steeringAngle ~= 0.0 then
                        steeringAngles[currentVehicle] = steeringAngle
                    end

                    if GetIsTaskActive(cache.ped, 2) and steeringAngles[currentVehicle] then
                        SetVehicleSteeringAngle(currentVehicle, steeringAngles[currentVehicle])
                    end
                    Citizen.Wait(100)
                end
            end)
        end
    end)
end

return Engine