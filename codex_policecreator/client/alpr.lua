--[[
    client/alpr.lua - automatic plate scanning while driving a duty vehicle.
]]

local RESOURCE = GetCurrentResourceName()
local lastPlates = {}

local function angleBetween(forward, target)
    local length = math.sqrt(target.x * target.x + target.y * target.y)
    if length < 0.01 then return 0 end

    local dot = (forward.x * target.x + forward.y * target.y) / length
    if dot > 1 then dot = 1 end
    if dot < -1 then dot = -1 end

    return math.deg(math.acos(dot))
end

local function scan()
    if not Config.ALPR.Enabled then return end
    if not State.member then return end
    if Config.ALPR.RequireDuty and not State.member.onDuty then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    local coords = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local cone = tonumber(Config.ALPR.ConeAngle) or 60
    local range = tonumber(Config.ALPR.Range) or 22.0
    local now = GetGameTimer()

    for _, other in ipairs(GetGamePool('CVehicle')) do
        if other ~= vehicle and DoesEntityExist(other) then
            local otherCoords = GetEntityCoords(other)
            local delta = otherCoords - coords
            local distance = #delta

            if distance <= range and angleBetween(forward, delta) <= cone then
                local plate = GetVehicleNumberPlateText(other)
                if plate and plate ~= '' then
                    local key = tostring(plate)
                    local last = lastPlates[key]
                    if not last or (now - last) > 15000 then
                        lastPlates[key] = now
                        TriggerServerEvent(RESOURCE .. ':server:alprScan', plate,
                            GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(other))))
                    end
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(tonumber(Config.ALPR.Interval) or 2500)
        local ok, err = pcall(scan)
        if not ok and Config.Debug then
            print(('[%s] ALPR error: %s'):format(RESOURCE, err))
        end
    end
end)

--- Alert from the server - a plate on a BOLO was seen nearby.
RegisterNetEvent(RESOURCE .. ':client:alprHit', function(payload)
    if not payload then return end

    local message = ('ALPR HIT %s\n%s'):format(payload.plate, payload.bolo and payload.bolo.description or '')
    TriggerEvent(RESOURCE .. ':client:notify', message, 'error')

    if Config.Dispatch.Sound.Enabled then
        PlaySoundFrontend(-1, Config.Dispatch.Sound.Name, Config.Dispatch.Sound.Set, true)
    end

    local blip = AddBlipForRadius(payload.bolo and payload.bolo.x or 0.0,
        payload.bolo and payload.bolo.y or 0.0, payload.bolo and payload.bolo.z or 0.0, 40.0)
    SetBlipColour(blip, 1)
    SetBlipAlpha(blip, 120)

    SetTimeout(20000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)
