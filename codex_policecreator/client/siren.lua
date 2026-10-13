--[[
    client/siren.lua - unmarked siren / light pattern switching.

    Works on any vehicle, so a normal sedan can run lights without a modded
    livery. Purely client side, no database involved.
]]

local RESOURCE = GetCurrentResourceName()
local currentPattern = 0
local lastVehicle = 0

local function applyPattern(vehicle, index)
    local pattern = Config.Sirens.Patterns[index]
    if not vehicle or not DoesEntityExist(vehicle) or not pattern then return end

    SetVehicleSiren(vehicle, pattern.siren and true or false)
    SetVehicleHasMutedSirens(vehicle, pattern.muted and true or false)

    for extra = 1, 14 do
        local wanted = pattern.extras[extra]
        if wanted == nil then wanted = false end
        if DoesExtraExist(vehicle, extra) then
            SetVehicleExtra(vehicle, extra, not wanted)
        end
    end

    if Config.Sirens.InteriorLight then
        SetVehicleInteriorlight(vehicle, pattern.siren and true or false)
    end
end

local function toggle(vehicle)
    if not Config.Sirens.Enabled then return end

    if Config.Sirens.RequireOnDuty and not State.member then return end

    currentPattern = currentPattern + 1
    if currentPattern > #Config.Sirens.Patterns then
        currentPattern = 1
    end

    applyPattern(vehicle, currentPattern)
    TriggerEvent(RESOURCE .. ':client:notify',
        ('Unmarked lights: %s'):format(Config.Sirens.Patterns[currentPattern].label), 'primary')
end

CreateThread(function()
    while true do
        Wait(0)

        local key = tonumber(Config.Sirens.MenuKey) or tonumber(Config.Keys.Siren) or 85
        if key > 0 and IsControlJustReleased(0, key) then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                if vehicle ~= lastVehicle then
                    lastVehicle = vehicle
                    currentPattern = 0
                end
                toggle(vehicle)
                Wait(300)
            end
        end
    end
end)

--- Restore lights when the player leaves the vehicle.
CreateThread(function()
    while true do
        Wait(1000)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if (not vehicle or vehicle == 0) and lastVehicle ~= 0 then
            lastVehicle = 0
            currentPattern = 0
        end
    end
end)
