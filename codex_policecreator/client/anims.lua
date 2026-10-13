--[[
    client/anims.lua - the bundled roleplay animations.
]]

Anims = {}

local playing = false
local current = nil

function Anims.Stop()
    if not playing then return end

    ClearPedTasks(PlayerPedId())
    playing = false
    current = nil
    SendNUIMessage({ action = 'animStopped', data = {} })
end

function Anims.IsPlaying()
    return playing
end

function Anims.Current()
    return current
end

--- index = position in Config.Animations
function Anims.Play(index)
    local entry = Config.Animations[tonumber(index)]
    if not entry then return false, 'invalid_animation' end

    if playing and current == index then
        Anims.Stop()
        return true
    end

    local ped = PlayerPedId()

    local loaded = 0
    RequestAnimDict(entry.dict)
    while not HasAnimDictLoaded(entry.dict) and loaded < 100 do
        Wait(10)
        loaded = loaded + 1
    end

    if not HasAnimDictLoaded(entry.dict) then return false, 'anim_load_failed' end

    local flags = (entry.loop or (entry.duration or 0) == 0) and 1 or 49
    TaskPlayAnim(ped, entry.dict, entry.clip, 8.0, -8.0, tonumber(entry.duration) or -1, flags, 0, false, false, false)

    playing = true
    current = index

    if (entry.duration or 0) > 0 then
        CreateThread(function()
            local duration = tonumber(entry.duration)
            Wait(duration)
            if playing and current == index then
                Anims.Stop()
            end
        end)
    end

    return true
end

function Anims.List()
    return Config.Animations
end

RegisterNetEvent('codex_policecreator:client:playAnim', function(index)
    Anims.Play(index)
end)

if (Config.Keys.Animations or 0) > 0 then
    CreateThread(function()
        while true do
            Wait(0)
            if IsControlJustReleased(0, Config.Keys.Animations) then
                SendNUIMessage({ action = 'animMenu', data = { animations = Config.Animations } })
                SetNuiFocus(true, true)
            end
        end
    end)
end
