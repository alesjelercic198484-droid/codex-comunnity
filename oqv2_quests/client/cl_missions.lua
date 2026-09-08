--[[ OQV2 QUESTS — Active mission runtime: objectives, markers, routing
     Made with CodeX Dev. ]]

local objectiveBlips = {}
local waiting        = false

-------------------------------------------------------------------------------
-- BLIPS / ROUTE
-------------------------------------------------------------------------------
local function clearObjectiveBlips()
    for _, blip in pairs(objectiveBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    objectiveBlips = {}
end

local function refreshObjectiveBlips()
    clearObjectiveBlips()
    local active = OQ.State.active
    if not active then return end

    for _, obj in ipairs(active.objectives or {}) do
        if not obj.done and obj.coords and obj.blip ~= false then
            local blip = AddBlipForCoord(obj.coords.x + 0.0, obj.coords.y + 0.0, obj.coords.z + 0.0)
            SetBlipSprite(blip, 1)
            SetBlipColour(blip, 5)
            SetBlipScale(blip, 0.9)
            SetBlipAsShortRange(blip, false)
            SetBlipRoute(blip, true)
            SetBlipRouteColour(blip, 5)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(obj.label or 'Objective')
            EndTextCommandSetBlipName(blip)
            objectiveBlips[#objectiveBlips + 1] = blip

            local radiusBlip = AddBlipForRadius(obj.coords.x + 0.0, obj.coords.y + 0.0, obj.coords.z + 0.0, (obj.radius or 2.0) + 8.0)
            SetBlipColour(radiusBlip, 5)
            SetBlipAlpha(radiusBlip, 90)
            objectiveBlips[#objectiveBlips + 1] = radiusBlip
        end
    end
end

-------------------------------------------------------------------------------
-- ADVANCE HELPER
-------------------------------------------------------------------------------
local function advance(objectiveId, payload)
    local active = OQ.State.active
    if not active then return false end
    local res = lib.callback.await('oqv2:server:advanceObjective', false, active.uid, objectiveId, payload or {})
    if res and res.success then
        OQ.Client.playSound('success')
        return true
    end
    if res and res.code and res.code ~= 'invalid_objective' and res.code ~= 'no_active' then
        OQ.Client.notify(Config.UI.brand, OQ.L(res.code), 'error')
    end
    return false
end

OQ.Client.advanceObjective = advance

-------------------------------------------------------------------------------
-- INTERACT / WAIT OBJECTIVE (progress bar + optional anim)
-------------------------------------------------------------------------------
local function runTimedObjective(obj)
    if waiting then return end
    waiting = true

    local anim
    if obj.anim and obj.anim.dict and obj.anim.dict ~= '' then
        anim = { dict = obj.anim.dict, clip = obj.anim.clip, flag = obj.anim.flag or 49 }
    end

    local ok = lib.progressBar({
        duration    = math.max(1000, obj.duration or 5000),
        label       = obj.label or 'Working...',
        useWhileDead= false,
        canCancel   = true,
        disable     = { car = true, move = true, combat = true },
        anim        = anim,
    })

    waiting = false
    if ok then
        advance(obj.id, {})
    else
        OQ.Client.notify(Config.UI.brand, OQ.L('mission_failed', { name = OQ.State.active and OQ.State.active.name or '' }), 'warning')
    end
end

-------------------------------------------------------------------------------
-- MAIN OBJECTIVE LOOP
-------------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 800
        local active = OQ.State.active

        if active and not OQ.State.nuiOpen then
            local coords = OQ.Client.playerCoords()

            for _, obj in ipairs(active.objectives or {}) do
                if not obj.done then

                    ------------------------------------------------------------------
                    -- location based objectives
                    ------------------------------------------------------------------
                    if obj.coords then
                        local target = vec3(obj.coords.x, obj.coords.y, obj.coords.z)
                        local d = #(coords - target)

                        if d < 60.0 then
                            sleep = 0
                            if obj.marker ~= false then
                                DrawMarker(1, target.x, target.y, target.z - 0.95, 0, 0, 0, 0, 0, 0,
                                    (obj.radius or 2.0) * 1.4, (obj.radius or 2.0) * 1.4, 0.75,
                                    224, 27, 132, 110, false, false, 2, false, nil, nil, false)
                            end
                        elseif d < 150.0 then
                            sleep = 250
                        end

                        if d <= (obj.radius or 2.0) then
                            if obj.type == 'goto' then
                                advance(obj.id, {})
                            elseif obj.type == 'deliver' then
                                lib.showTextUI(('[E] %s'):format(obj.label or 'Deliver'), { position = 'left-center' })
                                if IsControlJustReleased(0, 38) then
                                    lib.hideTextUI()
                                    advance(obj.id, {})
                                end
                            elseif obj.type == 'interact' or obj.type == 'wait' then
                                lib.showTextUI(('[E] %s'):format(obj.label or 'Interact'), { position = 'left-center' })
                                if IsControlJustReleased(0, 38) then
                                    lib.hideTextUI()
                                    runTimedObjective(obj)
                                end
                            elseif obj.type == 'pay' then
                                lib.showTextUI(('[E] Pay $%d'):format(obj.money or 0), { position = 'left-center' })
                                if IsControlJustReleased(0, 38) then
                                    lib.hideTextUI()
                                    advance(obj.id, {})
                                end
                            end
                        end

                    ------------------------------------------------------------------
                    -- collect: poll the inventory
                    ------------------------------------------------------------------
                    elseif obj.type == 'collect' and obj.item then
                        sleep = 1500
                        local ok, count = pcall(function()
                            return exports.ox_inventory:Search('count', obj.item)
                        end)
                        if ok and (tonumber(count) or 0) >= (obj.need or 1) then
                            advance(obj.id, {})
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- hide the text UI when nothing is in range
CreateThread(function()
    while true do
        Wait(1200)
        local active = OQ.State.active
        if not active then
            lib.hideTextUI()
        else
            local coords = OQ.Client.playerCoords()
            local near = false
            for _, obj in ipairs(active.objectives or {}) do
                if not obj.done and obj.coords then
                    if #(coords - vec3(obj.coords.x, obj.coords.y, obj.coords.z)) <= (obj.radius or 2.0) then
                        near = true
                        break
                    end
                end
            end
            if not near then lib.hideTextUI() end
        end
    end
end)

-------------------------------------------------------------------------------
-- SERVER EVENTS
-------------------------------------------------------------------------------
RegisterNetEvent('oqv2:client:missionStarted', function(active, alert)
    OQ.State.active = active
    refreshObjectiveBlips()

    if alert then
        OQ.Client.playSound(alert.sound == 'quest_alert' and 'quest_alert' or 'quest_start')
        SendNUIMessage({
            action = 'missionAlert',
            data   = {
                title       = alert.title,
                description = alert.description,
                duration    = alert.duration or 6000,
                icon        = active.icon or 'scroll',
            },
        })
    end

    SendNUIMessage({ action = 'tracker', data = { visible = true, mission = active } })
    TriggerEvent('oqv2:client:trackerUpdate')
end)

RegisterNetEvent('oqv2:client:objectiveUpdate', function(payload)
    if not OQ.State.active or OQ.State.active.uid ~= payload.missionUid then return end
    OQ.State.active.objectives = payload.objectives
    refreshObjectiveBlips()

    if payload.completedId then
        OQ.Client.notify(Config.UI.brand, OQ.L('objective_complete', { label = payload.label }), 'success')
    end
    if payload.allDone then
        OQ.Client.notify(Config.UI.brand, OQ.L('objective_all_complete'), 'inform', 7000)
    end

    SendNUIMessage({ action = 'tracker', data = { visible = true, mission = OQ.State.active } })
    TriggerEvent('oqv2:client:trackerUpdate')
end)

RegisterNetEvent('oqv2:client:missionCompleted', function(payload)
    OQ.State.active = nil
    clearObjectiveBlips()
    lib.hideTextUI()
    OQ.Client.playSound('success')

    SendNUIMessage({ action = 'tracker', data = { visible = false } })
    SendNUIMessage({
        action = 'missionComplete',
        data   = {
            name    = payload.name,
            rewards = payload.rewards,
        },
    })
    TriggerEvent('oqv2:client:trackerUpdate')
end)

RegisterNetEvent('oqv2:client:missionAbandoned', function()
    OQ.State.active = nil
    clearObjectiveBlips()
    lib.hideTextUI()
    SendNUIMessage({ action = 'tracker', data = { visible = false } })
    TriggerEvent('oqv2:client:trackerUpdate')
end)

RegisterNetEvent('oqv2:client:missionsUnlocked', function(list)
    for _, m in ipairs(list or {}) do
        OQ.Client.notify(Config.UI.brand, ('New mission unlocked: %s'):format(m.name), 'inform', 7000)
    end
    OQ.Client.playSound('quest_start')
end)

RegisterNetEvent('oqv2:client:xp', function(data)
    OQ.State.player.level   = data.level
    OQ.State.player.xp      = data.xp
    OQ.State.player.need    = data.need
    OQ.State.player.percent = data.percent
    OQ.State.player.totalXP = data.total

    SendNUIMessage({ action = 'xp', data = data })
    TriggerEvent('oqv2:client:trackerUpdate')
end)

RegisterNetEvent('oqv2:client:levelUp', function(level)
    OQ.Client.playSound('levelup')
    OQ.Client.notify(Config.UI.brand, OQ.L('level_up', { level = level }), 'success', 8000)
    SendNUIMessage({ action = 'levelUp', data = { level = level } })
end)

AddEventHandler('oqv2:client:playerUpdated', function()
    if OQ.State.active then
        refreshObjectiveBlips()
        SendNUIMessage({ action = 'tracker', data = { visible = true, mission = OQ.State.active } })
    else
        clearObjectiveBlips()
        SendNUIMessage({ action = 'tracker', data = { visible = false } })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= OQ.resource then return end
    clearObjectiveBlips()
end)
