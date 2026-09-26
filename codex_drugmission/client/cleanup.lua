MissionClient = MissionClient or { entities = {}, blips = {}, active = false }

function MissionCleanup(sendAbort)
    for _, entity in ipairs(MissionClient.entities) do
        if DoesEntityExist(entity) then SetEntityAsMissionEntity(entity, true, true); DeleteEntity(entity) end
    end
    MissionClient.entities, MissionClient.blips = {}, {}
    for _, blip in ipairs(MissionClient.blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    if MissionClient.destinationBlip and DoesBlipExist(MissionClient.destinationBlip) then RemoveBlip(MissionClient.destinationBlip) end
    if MissionClient.vehicleBlip and DoesBlipExist(MissionClient.vehicleBlip) then RemoveBlip(MissionClient.vehicleBlip) end
    MissionClient.destinationBlip, MissionClient.vehicleBlip = nil, nil
    if MissionClient.token and sendAbort then TriggerServerEvent('codex_drugmission:abort', MissionClient.token, 'client_cleanup') end
    MissionClient = { entities = {}, blips = {}, active = false }
end

AddEventHandler('onClientResourceStop', function(resource) if resource == GetCurrentResourceName() then MissionCleanup(false) end end)
AddEventHandler('playerSpawned', function() if MissionClient.active then MissionCleanup(true) end end)
