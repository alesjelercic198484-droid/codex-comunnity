local spawnedMissionNpcs = {}
local function loadModel(model)
    local hash = joaat(model); if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash); local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(20) end
    return HasModelLoaded(hash) and hash or nil
end
local function makeNpc(data)
    local hash = loadModel(data.model); if not hash then return nil end
    local c = data.coords; local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false)
    SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true); SetBlockingOfNonTemporaryEvents(ped, true); SetModelAsNoLongerNeeded(hash)
    return ped
end
function SpawnMissionNpcs(missions)
    for _, ped in ipairs(spawnedMissionNpcs) do if DoesEntityExist(ped) then DeleteEntity(ped) end end; spawnedMissionNpcs = {}
    for _, mission in ipairs(missions) do
        if mission.npc and mission.npc.coords then
            local ped = makeNpc(mission.npc); if ped then
                spawnedMissionNpcs[#spawnedMissionNpcs + 1] = ped
                exports.ox_target:addLocalEntity(ped, {{ name = 'codex_drugmission_' .. mission.id, icon = 'fa-solid fa-comments', label = 'Talk to the contact', distance = Config.DistanceToStart, onSelect = function() StartDialogue(mission) end }})
            end
        end
    end
end
RegisterNetEvent('codex_drugmission:missionsUpdated', function(missions) SpawnMissionNpcs(missions) end)
CreateThread(function() Wait(1000); local missions = lib.callback.await('codex_drugmission:getMissions', false); if missions and #missions > 0 then SpawnMissionNpcs(missions) end end)
