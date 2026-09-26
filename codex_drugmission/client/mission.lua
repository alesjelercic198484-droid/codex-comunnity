local function notify(message, typ) lib.notify({ description = message, type = typ or 'inform' }) end
local function playDialogueVoice(file)
    SendNUIMessage({ action = 'playSound', sound = file })
end
local function addBlip(coords, sprite, colour, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z); SetBlipSprite(blip, sprite); SetBlipColour(blip, colour); SetBlipScale(blip, 0.8); BeginTextCommandSetBlipName('STRING'); AddTextComponentString(label); EndTextCommandSetBlipName(blip); return blip
end
function StartDialogue(mission)
    if MissionClient.active then return notify('You already have an active mission.', 'error') end
    playDialogueVoice('dialogue_start.mp3')
    lib.alertDialog({ header = 'CodeX Roleplay', content = Config.Text.start, centered = true, cancel = false, labels = { confirm = 'Choose' } })
    local choice = lib.inputDialog('Choose your answer', { { type = 'select', label = 'Response', required = true, options = { { value = 'yes', label = Config.Text.brave }, { value = 'no', label = 'No, I am not ready yet.' } } } })
    if not choice then return end
    if choice[1] == 'no' then
        playDialogueVoice('player_not_ready.mp3')
        lib.alertDialog({ header = 'You', content = Config.Text.decline, centered = true, cancel = false })
        playDialogueVoice('dialogue_decline.mp3')
        return
    end
    playDialogueVoice('player_brave.mp3')
    Wait(1800)
    playDialogueVoice('dialogue_challenge.mp3')
    lib.alertDialog({ header = 'NPC', content = Config.Text.question .. '\n\n' .. Config.Text.challenge, centered = true, cancel = false })
    BeginMission(mission)
end

function BeginMission(mission)
    local ok, token, authoritativeMission = lib.callback.await('codex_drugmission:begin', false, mission.id)
    if not ok then return notify(token or 'Mission could not start.', 'error') end
    MissionClient = { active = true, token = token, mission = authoritativeMission, entities = {}, blips = {} }
    local v = authoritativeMission.vehicleSpawn; local hash = joaat(authoritativeMission.vehicle.model)
    if not IsModelInCdimage(hash) then MissionCleanup(true); return notify('Mission vehicle model is invalid.', 'error') end
    RequestModel(hash); while not HasModelLoaded(hash) do Wait(20) end
    local c = authoritativeMission.vehicleSpawn; local veh = CreateVehicle(hash, c.x, c.y, c.z, c.w or 0.0, true, true)
    if veh == 0 then MissionCleanup(true); return notify('Vehicle could not be created.', 'error') end
    SetVehicleColours(veh, (authoritativeMission.vehicle.color or { 20 })[1] or 20, (authoritativeMission.vehicle.color or { 20, 20 })[2] or 20); SetVehicleOnGroundProperly(veh); SetVehicleNumberPlateText(veh, 'CODEX');
    MissionClient.vehicle = veh; MissionClient.vehicleNet = NetworkGetNetworkIdFromEntity(veh); MissionClient.entities[#MissionClient.entities + 1] = veh
    SetModelAsNoLongerNeeded(hash); SetNewWaypoint(authoritativeMission.destination.x, authoritativeMission.destination.y)
    if Config.Blips.destination then MissionClient.destinationBlip = addBlip(authoritativeMission.destination, 1, 5, 'Drug delivery') end
    if Config.Blips.missionVehicle then MissionClient.vehicleBlip = AddBlipForEntity(veh); SetBlipSprite(MissionClient.vehicleBlip, 225); SetBlipColour(MissionClient.vehicleBlip, 5) end
    if authoritativeMission.vehicle.warpInto then TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1) end
    TriggerServerEvent('codex_drugmission:vehicleReady', token, MissionClient.vehicleNet, authoritativeMission.vehicle.model)
    notify(Config.Text.loaded, 'inform'); notify('You have 20 seconds before the attackers arrive.', 'warning')
    CreateThread(function()
        Wait(Config.FirstWaveDelay * 1000); if not MissionClient.active then return end
        notify('Attackers are coming!', 'error'); SpawnEnemyWave(1, authoritativeMission.enemyWaves[1])
        Wait((Config.SecondWaveDelay - Config.FirstWaveDelay) * 1000); if not MissionClient.active then return end
        if authoritativeMission.enemyWaves[2] then notify('More attackers have joined the chase!', 'error'); SpawnEnemyWave(2, authoritativeMission.enemyWaves[2]) end
    end)
    CreateThread(function() MonitorMission() end)
end

function MonitorMission()
    local outAt, nextWarning = nil, 110
    while MissionClient.active do
        Wait(1000); local ped = PlayerPedId()
        if IsEntityDead(ped) then notify(Config.Text.dead, 'error'); MissionCleanup(true); return end
        if not DoesEntityExist(MissionClient.vehicle) then notify('Mission failed – the mission vehicle was destroyed.', 'error'); MissionCleanup(true); return end
        if GetVehiclePedIsIn(ped, false) ~= MissionClient.vehicle then
            if not outAt then outAt = GetGameTimer() + Config.LeaveVehicleSeconds * 1000; nextWarning = 110 end
            local remaining = math.ceil((outAt - GetGameTimer()) / 1000)
            if remaining <= 0 then notify('Mission failed – you did not return to the vehicle.', 'error'); MissionCleanup(true); return end
            if remaining <= nextWarning then notify(('Return to the vehicle! %s seconds remaining.'):format(remaining), 'warning'); nextWarning = nextWarning - 10 end
            if remaining == 60 then notify(Config.Text.hurry, 'error'); SendNUIMessage({ action = 'playSound', sound = Config.HurrySound }) end
        else outAt = nil end
        local coords = GetEntityCoords(MissionClient.vehicle); local dest = MissionClient.mission.destination
        if #(coords - vector3(dest.x, dest.y, dest.z)) < 30.0 then
            local success, errorMessage = lib.callback.await('codex_drugmission:complete', false, MissionClient.token, MissionClient.vehicleNet, { x = coords.x, y = coords.y, z = coords.z })
            if success then return else if errorMessage then notify(errorMessage, 'error') end end
        end
    end
end

RegisterNetEvent('codex_drugmission:completed', function(token, mission)
    if not MissionClient.active or MissionClient.token ~= token then return end
    MissionCleanup(false); notify(Config.Text.success, 'success'); SpawnFinalNpc(mission)
end)
RegisterNetEvent('codex_drugmission:forceCleanup', function() MissionCleanup(false) end)

function SpawnFinalNpc(mission)
    local hash = joaat(mission.rewardNpc.model); RequestModel(hash); while not HasModelLoaded(hash) do Wait(20) end
    local c = mission.rewardNpc.coords; local npc = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false); SetEntityInvincible(npc, true); SetBlockingOfNonTemporaryEvents(npc, true)
    local player = PlayerPedId(); TaskGoToEntity(npc, player, -1, 2.0, 1.0, 1073741824, 0)
    CreateThread(function()
        local deadline = GetGameTimer() + 20000; while DoesEntityExist(npc) and #(GetEntityCoords(npc) - GetEntityCoords(player)) > 2.2 and GetGameTimer() < deadline do Wait(500) end
        if DoesEntityExist(npc) then TaskTurnPedToFaceEntity(npc, player, 1000); Wait(1000); lib.alertDialog({ header = 'NPC', content = Config.Text.final, centered = true, cancel = false }); DeleteEntity(npc) end
    end)
end
