--[[
    client/k9.lua - deployable K9 companion with follow / sit / attack / search.
]]

local RESOURCE = GetCurrentResourceName()

K9 = {}

local dog = nil
local mode = 'follow'
local target = nil

local function notify(message, kind)
    TriggerEvent(RESOURCE .. ':client:notify', message, kind or 'primary')
end

local function clear()
    if dog and DoesEntityExist(dog) then
        SetEntityAsMissionEntity(dog, true, true)
        DeleteEntity(dog)
    end
    dog = nil
    mode = 'follow'
    target = nil
end

function K9.IsDeployed()
    return dog ~= nil and DoesEntityExist(dog)
end

function K9.Deploy()
    if not Config.K9.Enabled then return false, 'disabled' end

    if K9.IsDeployed() then
        K9.Dismiss()
        return true
    end

    if State.member then
        local grade = State.rank and tonumber(State.rank.grade) or -1
        if grade < (tonumber(Config.K9.MinRank) or 0) then
            return false, 'rank_too_low'
        end
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local model = joaat(Config.K9.Model)

    RequestModel(model)
    local waited = 0
    while not HasModelLoaded(model) and waited < 150 do
        Wait(10)
        waited = waited + 1
    end

    if not HasModelLoaded(model) then return false, 'model' end

    dog = CreatePed(28, model, coords.x + 1.0, coords.y + 1.0, coords.z, 0.0, true, false)
    SetModelAsNoLongerNeeded(model)

    if not dog or dog == 0 then return false, 'spawn' end

    SetEntityAsMissionEntity(dog, true, true)
    SetPedCanRagdoll(dog, false)
    SetPedDiesWhenInjured(dog, false)
    SetBlockingOfNonTemporaryEvents(dog, true)
    SetPedFleeAttributes(dog, 0, false)
    SetPedRelationshipGroupHash(dog, joaat('HATES_PLAYER'))

    notify('K9 deployed', 'success')
    return true
end

function K9.Dismiss()
    clear()
    notify('K9 returned to the kennel')
    return true
end

function K9.Follow()
    if not K9.IsDeployed() then return false end
    mode = 'follow'
    target = nil
    notify('K9: following')
    return true
end

function K9.Sit()
    if not K9.IsDeployed() then return false end
    mode = 'sit'
    TaskFollowNavMeshToCoord(dog, 0.0, 0.0, 0.0, 0.0, 0, 0.0, 0, false)
    ClearPedTasks(dog)
    TaskPlayAnim(dog, 'creatures@rottweiler@amb@sleep_in_kennel@', 'sleep_in_kennel', 8.0, -8.0, -1, 1, 0, false, false, false)
    notify('K9: sitting')
    return true
end

function K9.Attack()
    if not K9.IsDeployed() then return false end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local hit, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())

    if not hit or not entity or not IsPedAPlayer(entity) then
        -- fall back to the closest hostile ped
        local best, bestDistance = 0, 25.0
        for _, other in ipairs(GetGamePool('CPed')) do
            if other ~= ped and other ~= dog and IsPedAPlayer(other) then
                local distance = #(coords - GetEntityCoords(other))
                if distance < bestDistance then
                    bestDistance = distance
                    best = other
                end
            end
        end
        entity = best
    end

    if not entity or entity == 0 then
        notify('No target for the K9', 'error')
        return false
    end

    mode = 'attack'
    target = entity
    TaskCombatPed(dog, entity, 0, 16)
    notify('K9: attacking')
    return true
end

--- Ask the server whether the aimed player carries contraband.
function K9.Search()
    if not K9.IsDeployed() then return false end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local range = tonumber(Config.K9.SniffRange) or 4.0

    for _, other in ipairs(GetGamePool('CPed')) do
        if other ~= ped and other ~= dog and IsPedAPlayer(other) then
            if #(coords - GetEntityCoords(other)) <= range then
                TriggerServerEvent(RESOURCE .. ':server:k9SniffPlayer', GetPlayerServerId(NetworkGetPlayerIndexFromPed(other)))
                return true
            end
        end
    end

    -- no player nearby: sniff the closest vehicle
    local vehicleRange = tonumber(Config.K9.VehicleSniffRange) or 3.5
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if #(coords - GetEntityCoords(vehicle)) <= vehicleRange then
            TriggerServerEvent(RESOURCE .. ':server:k9SniffVehicle', VehToNet(vehicle))
            return true
        end
    end

    notify('Nothing to sniff here')
    return false
end

function K9.Menu()
    State.OpenMenu('k9', { deployed = K9.IsDeployed() })
end

local commands = {
    follow = K9.Follow,
    sit = K9.Sit,
    attack = K9.Attack,
    search = K9.Search,
    dismiss = K9.Dismiss,
    deploy = K9.Deploy
}

function K9.Command(name)
    local handler = commands[tostring(name):lower()]
    if not handler then return false, 'unknown_command' end
    return handler()
end

--- Keep the dog next to its handler.
CreateThread(function()
    while true do
        Wait(1000)

        if K9.IsDeployed() then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local dogCoords = GetEntityCoords(dog)
            local distance = #(coords - dogCoords)

            if mode == 'follow' then
                if distance > (tonumber(Config.K9.FollowDistance) or 3.0) then
                    if distance > 25.0 then
                        SetEntityCoords(dog, coords.x + 1.0, coords.y + 1.0, coords.z, false, false, false, false)
                    else
                        TaskGoToEntity(dog, ped, -1, 2.0, 2.0, 1073741824, 0)
                    end
                end
            end

            if distance > 200.0 then
                SetEntityCoords(dog, coords.x + 1.0, coords.y + 1.0, coords.z, false, false, false, false)
            end
        end
    end
end)

RegisterNetEvent(RESOURCE .. ':client:k9Result', function(payload)
    if not payload then return end

    if payload.found then
        notify(('K9 ALERT: %s'):format(payload.label or 'contraband found'), 'error')
        PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', true)
    else
        notify('K9 found nothing', 'primary')
    end
end)

RegisterNetEvent(RESOURCE .. ':client:k9Command', function(name)
    K9.Command(name)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then clear() end
end)
