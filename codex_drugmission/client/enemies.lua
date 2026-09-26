local function requestModel(model)
    local hash = joaat(model); if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash); local endAt = GetGameTimer() + 6000
    while not HasModelLoaded(hash) and GetGameTimer() < endAt do Wait(25) end
    return HasModelLoaded(hash) and hash or nil
end
function SpawnEnemyWave(waveIndex, wave)
    local target = PlayerPedId(); local targetCoords = GetEntityCoords(target); local ids = {}
    for i, vehicleModel in ipairs(wave.vehicles) do
        local vh = requestModel(vehicleModel); local ph = requestModel(wave.ped)
        if vh and ph then
            local angle = (i * 2.4) + waveIndex; local pos = targetCoords + vector3(math.cos(angle) * wave.spawnDistance, math.sin(angle) * wave.spawnDistance, 0.0)
            local found, ground = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 100.0, false); if found then pos = vector3(pos.x, pos.y, ground) end
            local car = CreateVehicle(vh, pos.x, pos.y, pos.z, GetEntityHeading(target), true, true)
            SetVehicleOnGroundProperly(car); SetVehicleEngineOn(car, true, true, false); SetVehicleDoorsLocked(car, 2)
            MissionClient.entities[#MissionClient.entities + 1] = car; ids[#ids + 1] = NetworkGetNetworkIdFromEntity(car)
            local driver = CreatePedInsideVehicle(car, 4, ph, -1, true, true); MissionClient.entities[#MissionClient.entities + 1] = driver
            GiveWeaponToPed(driver, joaat(wave.weapon), 500, false, true); SetPedCombatAttributes(driver, 3, true); SetPedCombatAttributes(driver, 5, true); SetPedCombatAbility(driver, 2); SetPedAccuracy(driver, 55); SetPedKeepTask(driver, true)
            for seat = 0, wave.count - 2 do
                local passenger = CreatePedInsideVehicle(car, 4, ph, seat, true, true); MissionClient.entities[#MissionClient.entities + 1] = passenger
                GiveWeaponToPed(passenger, joaat(wave.weapon), 500, false, true); SetPedCombatAttributes(passenger, 5, true); SetPedCombatAbility(passenger, 2); SetPedAccuracy(passenger, 50); SetPedKeepTask(passenger, true)
            end
            CreateThread(function()
                while MissionClient.active and DoesEntityExist(car) do
                    local player = PlayerPedId(); if DoesEntityExist(player) then
                        TaskVehicleChase(driver, player); SetTaskVehicleChaseBehaviorFlag(driver, 2, true); SetTaskVehicleChaseIdealPursuitDistance(driver, 12.0)
                        for seat = -1, wave.count - 2 do local ped = GetPedInVehicleSeat(car, seat); if ped ~= 0 and DoesEntityExist(ped) then TaskCombatPed(ped, player, 0, 16) end end
                    end
                    Wait(4000)
                end
            end)
            SetModelAsNoLongerNeeded(vh); SetModelAsNoLongerNeeded(ph)
        end
    end
    TriggerServerEvent('codex_drugmission:waveReady', MissionClient.token, waveIndex, ids)
end
