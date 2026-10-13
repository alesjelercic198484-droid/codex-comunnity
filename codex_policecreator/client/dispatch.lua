--[[
    client/dispatch.lua - call notifications, blips and sounds.
]]

local RESOURCE = GetCurrentResourceName()
local callBlips = {}

local function removeBlip(callId)
    local blip = callBlips[callId]
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
    callBlips[callId] = nil
end

local function clearBlips()
    for callId in pairs(callBlips) do
        removeBlip(callId)
    end
    callBlips = {}
end

RegisterNetEvent(RESOURCE .. ':client:newCall', function(call)
    if not call then return end

    local blip = AddBlipForRadius(call.x, call.y, call.z, tonumber(Config.Dispatch.Radius) or 25.0)
    SetBlipSprite(blip, tonumber(Config.Dispatch.BlipSprite) or 304)
    SetBlipColour(blip, tonumber(Config.Dispatch.BlipColor) or 1)
    SetBlipAlpha(blip, tonumber(Config.Dispatch.BlipAlpha) or 180)
    SetBlipAsShortRange(blip, false)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('%s %s'):format(call.code, call.label))
    EndTextCommandSetBlipName(blip)

    removeBlip(call.id)
    callBlips[call.id] = blip

    if Config.Dispatch.Sound.Enabled then
        PlaySoundFrontend(-1, Config.Dispatch.Sound.Name, Config.Dispatch.Sound.Set, true)
    end

    TriggerEvent(RESOURCE .. ':client:notify',
        ('NEW CALL %s - %s\n%s'):format(call.code, call.label, call.description or ''), 'error')

    if State.menuOpen then
        SendNUIMessage({ action = 'callAdded', data = call })
    end
end)

RegisterNetEvent(RESOURCE .. ':client:callUpdate', function(call)
    if not call then return end

    if State.menuOpen then
        SendNUIMessage({ action = 'callUpdated', data = call })
    end

    if call.status == 'active' then
        TriggerEvent(RESOURCE .. ':client:notify',
            ('%s is responding to %s'):format(call.assignedName or 'A unit', call.code), 'primary')
    else
        TriggerEvent(RESOURCE .. ':client:notify', ('Call %s is available again'):format(call.code), 'primary')
    end
end)

RegisterNetEvent(RESOURCE .. ':client:callClosed', function(callId)
    removeBlip(tonumber(callId))

    if State.menuOpen then
        SendNUIMessage({ action = 'callClosed', data = { id = tonumber(callId) } })
    end
end)

--- Clear stale blips when going off duty.
RegisterNetEvent(RESOURCE .. ':client:sync', function(payload)
    if payload and payload.member and not payload.member.onDuty then
        clearBlips()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then clearBlips() end
end)
