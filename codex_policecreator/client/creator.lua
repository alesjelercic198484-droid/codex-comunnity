--[[
    client/creator.lua - in-game department/node editor helpers.

    The actual editor UI lives in html/app.js (creator mode). This file draws
    every node of every department while the editor is open and lets you delete
    the node you are standing on.
]]

local RESOURCE = GetCurrentResourceName()

local function creatorActive()
    return State.menuOpen and State.menuMode == 'creator'
end

local function drawLabel(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z + 1.2, 0)
    SetTextFont(4)
    SetTextScale(0.0, 0.35)
    SetTextColour(255, 220, 120, 215)
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        local wait = 500

        if creatorActive() and State.sync then
            wait = 0
            local coords = GetEntityCoords(PlayerPedId())

            for _, dept in ipairs(State.sync.departments) do
                for _, node in ipairs(dept.nodes) do
                    local point = vector3(node.x, node.y, node.z)
                    local distance = #(coords - point)

                    if distance <= 25.0 then
                        DrawMarker(1, node.x, node.y, node.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            0.7, 0.7, 1.2, 255, 200, 60, 120, false, true, 2, false, nil, nil, false)

                        drawLabel(point, ('%s\n%s\n[%s]'):format(dept.label, node.label, node.type))
                    end

                    if distance <= 2.0 and IsControlJustReleased(0, 73) then -- X
                        TriggerServerEvent(RESOURCE .. ':server:creatorDeleteNode', node.id)
                        TriggerEvent(RESOURCE .. ':client:notify',
                            ('Deleted %s node'):format(node.label), 'success')
                        wait = 600
                    end
                end
            end
        end

        Wait(wait)
    end
end)

--- The creator asks the client where the player is standing before saving a node.
RegisterNUICallback('position', function(_, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    cb({
        x = coords.x, y = coords.y, z = coords.z,
        heading = GetEntityHeading(ped)
    })
end)
