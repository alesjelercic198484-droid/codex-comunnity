local ESX = exports.es_extended:getSharedObject()
local Missions = LoadMissions()
local Active = {}

local function isAdmin(source)
    if source == 0 then return true end
    if Config.AdminAce and IsPlayerAceAllowed(source, Config.AdminAce) then return true end
    local xPlayer = ESX.GetPlayerFromId(source)
    return xPlayer and Config.AdminGroups[xPlayer.getGroup()] == true
end

local function notify(source, message, type) TriggerClientEvent('ox_lib:notify', source, { description = message, type = type or 'inform' }) end
local function publicMissions()
    local result = {}
    for _, mission in ipairs(Missions) do
        result[#result + 1] = {
            id = mission.id,
            name = mission.name,
            npc = mission.npc
        }
    end
    return result
end

lib.callback.register('codex_drugmission:getMissions', function(source)
    if not isAdmin(source) then return {} end
    return Missions
end)
lib.callback.register('codex_drugmission:getPublicMissions', function()
    return publicMissions()
end)
lib.callback.register('codex_drugmission:saveMission', function(source, mission)
    if not isAdmin(source) then return false, 'Not authorised' end
    local clean, err = SanitizeMission(mission)
    if not clean then return false, err end
    local found = false
    for i, old in ipairs(Missions) do if old.id == clean.id then Missions[i] = clean; found = true end end
    if not found then Missions[#Missions + 1] = clean end
    SaveMissions(Missions)
    TriggerClientEvent('codex_drugmission:missionsUpdated', source, Missions)
    TriggerClientEvent('codex_drugmission:publicMissionsUpdated', -1, publicMissions())
    return true
end)

lib.callback.register('codex_drugmission:begin', function(source, missionId)
    if Active[source] then return false, 'You already have an active mission.' end
    local mission
    for _, value in ipairs(Missions) do if value.id == missionId then mission = value break end end
    if not mission then return false, 'Mission not found.' end
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Player unavailable.' end
    local playerPed = GetPlayerPed(source)
    local npc = mission.npc.coords
    if playerPed == 0 or #(GetEntityCoords(playerPed) - vector3(npc.x, npc.y, npc.z)) > (Config.DistanceToStart + 5.0) then return false, 'You are too far from the mission contact.' end
    local token = ('%s:%s:%s'):format(xPlayer.identifier, os.time(), math.random(100000, 999999))
    Active[source] = { token = token, id = mission.id, stage = 'starting', vehicle = nil, rewards = false, started = os.time() }
    return true, token, mission
end)

RegisterNetEvent('codex_drugmission:vehicleReady', function(token, netId, model)
    local src, state = source, Active[source]
    if not state or state.token ~= token or state.stage ~= 'starting' then return end
    local entity = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local mission; for _, value in ipairs(Missions) do if value.id == state.id then mission = value break end end
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 or not mission then return end
    local spawn = mission.vehicleSpawn
    if GetEntityModel(entity) ~= joaat(mission.vehicle.model) or #(GetEntityCoords(entity) - vector3(spawn.x, spawn.y, spawn.z)) > 35.0 then return end
    state.vehicle = netId; state.vehicleModel = mission.vehicle.model; state.stage = 'active'; state.lastSeen = os.time()
    TriggerClientEvent('codex_drugmission:authorised', src, token)
end)
RegisterNetEvent('codex_drugmission:waveReady', function(token, wave, netIds)
    local state = Active[source]
    if not state or state.token ~= token or state.stage ~= 'active' or type(netIds) ~= 'table' or wave < 1 or wave > 2 then return end
    state.waves = state.waves or {}; state.waves[wave] = netIds
end)

lib.callback.register('codex_drugmission:complete', function(source, token, vehicleNet, coords)
    local state = Active[source]
    if not state or state.token ~= token or state.stage ~= 'active' or state.rewards then return false, 'Mission is not active.' end
    if state.vehicle ~= vehicleNet or type(coords) ~= 'table' then return false, 'Invalid vehicle.' end
    local mission; for _, value in ipairs(Missions) do if value.id == state.id then mission = value break end end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNet) or 0)
    if not mission or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return false, 'Vehicle validation failed.' end
    local playerPed = GetPlayerPed(source)
    if playerPed == 0 or GetVehiclePedIsIn(playerPed, false) ~= vehicle or GetPedInVehicleSeat(vehicle, -1) ~= playerPed then return false, 'You must be driving the mission vehicle.' end
    local d = #(vector3(coords.x, coords.y, coords.z) - vector3(mission.destination.x, mission.destination.y, mission.destination.z))
    if d > 35.0 then return false, 'You are not at the destination.' end
    local actual = GetEntityCoords(vehicle)
    if #(actual - vector3(mission.destination.x, mission.destination.y, mission.destination.z)) > 45.0 then return false, 'Vehicle is not at the destination.' end
    state.rewards = true; state.stage = 'complete'
    if not GiveMissionRewards(source, mission.rewards) then state.rewards = false; state.stage = 'active'; return false, 'Reward could not be delivered.' end
    TriggerClientEvent('codex_drugmission:completed', source, token, mission)
    Active[source] = nil
    return true
end)

RegisterNetEvent('codex_drugmission:abort', function(token, reason)
    local state = Active[source]
    if state and state.token == token then Active[source] = nil end
end)
AddEventHandler('playerDropped', function() Active[source] = nil end)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then Active = {} end end)

CreateThread(function()
    while true do
        Wait(10000)
        for src, state in pairs(Active) do
            if state.started and os.time() - state.started > 1800 then Active[src] = nil; notify(src, 'Mission expired.', 'error'); TriggerClientEvent('codex_drugmission:forceCleanup', src) end
        end
    end
end)

RegisterCommand('drugmission', function(source) if source > 0 and isAdmin(source) then TriggerClientEvent('codex_drugmission:openAdmin', source) elseif source > 0 then notify(source, 'You are not authorised.', 'error') end end)
