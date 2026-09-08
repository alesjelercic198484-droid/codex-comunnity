--[[ OQV2 QUESTS — Quest locations: peds, objects, targets, blips, discovery
     Made with CodeX Dev. ]]

local spawned = {}   -- [uid] = { entity = handle, point = index, blip = handle }
local blips   = {}   -- [uid] = blip handle
local busy    = false

-------------------------------------------------------------------------------
-- POINT SELECTION (rotating NPCs pick the same spot on every client)
-------------------------------------------------------------------------------
local function activePoint(loc)
    local points = loc.points or {}
    if #points == 0 then return nil, 0 end
    if not loc.rotate or not loc.rotate.enabled or #points == 1 then
        return points[1], 1
    end
    local interval = math.max(30, loc.rotate.interval or 1800)
    local index = (math.floor(os.time() / interval) % #points) + 1
    return points[index], index
end

-------------------------------------------------------------------------------
-- BLIPS
-------------------------------------------------------------------------------
local function removeBlip(uid)
    local blip = blips[uid]
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    blips[uid] = nil
end

local function refreshBlips()
    if not Config.Interaction.useBlips then return end

    local seen = {}
    for _, loc in ipairs(OQ.State.world.locations or {}) do
        seen[loc.uid] = true
        local wants = loc.blip and loc.blip.enabled and OQ.Client.scheduleActive(loc.schedule)
        local point = select(1, activePoint(loc))

        if wants and point then
            if not blips[loc.uid] then
                local blip = AddBlipForCoord(point.x + 0.0, point.y + 0.0, point.z + 0.0)
                SetBlipSprite(blip, loc.blip.sprite or 480)
                SetBlipColour(blip, loc.blip.color or 27)
                SetBlipScale(blip, (loc.blip.scale or 0.8) + 0.0)
                SetBlipAsShortRange(blip, loc.blip.shortRange ~= false)
                SetBlipDisplay(blip, 4)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(loc.blip.label or loc.name or 'Quest')
                EndTextCommandSetBlipName(blip)
                blips[loc.uid] = blip
            else
                SetBlipCoords(blips[loc.uid], point.x + 0.0, point.y + 0.0, point.z + 0.0)
            end
        else
            removeBlip(loc.uid)
        end
    end

    for uid in pairs(blips) do
        if not seen[uid] then removeBlip(uid) end
    end
end

-------------------------------------------------------------------------------
-- INTERACTION
-------------------------------------------------------------------------------
local function buildMissionRows(loc, missions)
    local options = {}
    for _, mission in ipairs(missions) do
        local metaLines = {}
        if mission.requiredLevel and mission.requiredLevel > 0 then
            metaLines[#metaLines + 1] = { label = 'Required level', value = mission.requiredLevel }
        end
        if mission.xpReward and mission.xpReward > 0 then
            metaLines[#metaLines + 1] = { label = 'XP', value = '+' .. mission.xpReward }
        end
        if mission.rewards then
            if (mission.rewards.money or 0) > 0 then
                metaLines[#metaLines + 1] = { label = 'Cash', value = '$' .. mission.rewards.money }
            end
            if (mission.rewards.bank or 0) > 0 then
                metaLines[#metaLines + 1] = { label = 'Bank', value = '$' .. mission.rewards.bank }
            end
            if (mission.rewards.black or 0) > 0 then
                metaLines[#metaLines + 1] = { label = 'Dirty cash', value = '$' .. mission.rewards.black }
            end
            for _, item in ipairs(mission.rewards.items or {}) do
                metaLines[#metaLines + 1] = { label = 'Item', value = ('%dx %s'):format(item.count, item.name) }
            end
        end
        if mission.completions and mission.completions > 0 then
            metaLines[#metaLines + 1] = { label = 'Completed', value = mission.completions .. 'x' }
        end

        options[#options + 1] = {
            title       = mission.available and mission.name or ('🔒 ' .. mission.name),
            description = mission.available and mission.description or (mission.reason or OQ.L('mission_locked')),
            icon        = mission.icon or 'scroll',
            iconColor   = mission.available and Config.UI.accent or '#6b7280',
            disabled    = not mission.available,
            metadata    = metaLines,
            arrow       = mission.available,
            onSelect    = function()
                local res = lib.callback.await('oqv2:server:startMission', false, mission.uid, loc.uid)
                if res and res.success then
                    OQ.Client.notify(Config.UI.brand, res.message, 'success')
                else
                    OQ.Client.notify(Config.UI.brand, res and res.message or OQ.L('generic_error'), 'error')
                    OQ.Client.playSound('fail')
                end
            end,
        }
    end
    return options
end

function OQ.Client.interactLocation(loc)
    if busy then return end
    busy = true

    TriggerServerEvent('oqv2:server:discover', loc.uid)

    local missions = lib.callback.await('oqv2:server:getLocationMissions', false, loc.uid) or {}

    -- turning in an active mission at its giver?
    local active = OQ.State.active
    local canTurnIn = false
    if active and active.location == loc.uid then
        canTurnIn = true
        for _, obj in ipairs(active.objectives or {}) do
            if not obj.done and not obj.optional then canTurnIn = false break end
        end
    end

    local options = {}

    if canTurnIn then
        options[#options + 1] = {
            title       = 'Turn in: ' .. (active.name or 'mission'),
            description = OQ.L('objective_all_complete'),
            icon        = 'circle-check',
            iconColor   = '#22c55e',
            arrow       = true,
            onSelect    = function()
                local res = lib.callback.await('oqv2:server:completeMission', false, active.uid)
                if res and res.success then
                    OQ.Client.notify(Config.UI.brand, res.message, 'success')
                else
                    OQ.Client.notify(Config.UI.brand, res and res.message or OQ.L('generic_error'), 'error')
                end
            end,
        }
    end

    -- hand-over objectives that point at this location
    if active then
        for _, obj in ipairs(active.objectives or {}) do
            if not obj.done and obj.type == 'give_item' and active.location == loc.uid then
                options[#options + 1] = {
                    title       = obj.label,
                    description = ('Hand over %dx %s'):format(obj.need or 1, obj.item or '?'),
                    icon        = 'box-open',
                    iconColor   = Config.UI.accent,
                    onSelect    = function()
                        local res = lib.callback.await('oqv2:server:advanceObjective', false, active.uid, obj.id, {})
                        if res and res.success then
                            OQ.Client.notify(Config.UI.brand, OQ.L('items_removed'), 'success')
                            OQ.Client.playSound('success')
                        else
                            OQ.Client.notify(Config.UI.brand, OQ.L(res and res.code or 'generic_error'), 'error')
                        end
                    end,
                }
            end
        end
    end

    local rows = buildMissionRows(loc, missions)
    for _, row in ipairs(rows) do options[#options + 1] = row end

    if #options == 0 then
        OQ.Client.notify(loc.name, OQ.L('no_missions_here'), 'inform')
        busy = false
        return
    end

    lib.registerContext({
        id      = 'oqv2_location_' .. loc.uid,
        title   = loc.dialogue and loc.dialogue.title or loc.name,
        options = options,
        onExit  = function() busy = false end,
    })
    lib.showContext('oqv2_location_' .. loc.uid)
    OQ.Client.playSound('open')

    SetTimeout(500, function() busy = false end)
end

-------------------------------------------------------------------------------
-- SPAWN / DESPAWN
-------------------------------------------------------------------------------
local function despawn(uid)
    local data = spawned[uid]
    if not data then return end
    if data.entity and DoesEntityExist(data.entity) then
        pcall(function() exports.ox_target:removeLocalEntity(data.entity) end)
        SetEntityAsMissionEntity(data.entity, true, true)
        DeleteEntity(data.entity)
    end
    spawned[uid] = nil
end

local function spawn(loc)
    local point, index = activePoint(loc)
    if not point then return end

    local ent
    if loc.entity.type == 'ped' then
        local hash = OQ.Client.loadModel(loc.entity.model)
        if not hash then return end
        ent = CreatePed(4, hash, point.x + 0.0, point.y + 0.0, point.z - 1.0, point.w + 0.0, false, true)
        SetModelAsNoLongerNeeded(hash)
        if not DoesEntityExist(ent) then return end

        SetEntityInvincible(ent, loc.entity.invincible ~= false)
        SetBlockingOfNonTemporaryEvents(ent, loc.entity.ignore ~= false)
        SetPedDiesWhenInjured(ent, false)
        SetPedCanRagdollFromPlayerImpact(ent, false)
        SetPedCanBeTargetted(ent, false)
        SetPedFleeAttributes(ent, 0, false)
        SetPedCombatAttributes(ent, 17, true)
        if loc.entity.freeze ~= false then
            FreezeEntityPosition(ent, true)
        end

        if loc.entity.scenario and loc.entity.scenario ~= '' then
            TaskStartScenarioInPlace(ent, loc.entity.scenario, 0, true)
        elseif loc.entity.anim and loc.entity.anim.dict then
            if OQ.Client.loadAnim(loc.entity.anim.dict) then
                TaskPlayAnim(ent, loc.entity.anim.dict, loc.entity.anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
            end
        end

    elseif loc.entity.type == 'object' then
        local hash = OQ.Client.loadModel(loc.entity.model)
        if not hash then return end
        ent = CreateObject(hash, point.x + 0.0, point.y + 0.0, point.z - 1.0, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        if not DoesEntityExist(ent) then return end
        PlaceObjectOnGroundProperly(ent)
        FreezeEntityPosition(ent, true)
        SetEntityInvincible(ent, true)
    else
        -- marker only
        spawned[loc.uid] = { entity = nil, point = index, marker = true }
        return
    end

    exports.ox_target:addLocalEntity(ent, {
        {
            name     = 'oqv2_location_' .. loc.uid,
            icon     = loc.target.icon or 'fa-solid fa-comments',
            label    = loc.target.label or 'Talk',
            distance = loc.target.distance or Config.Interaction.targetDistance,
            onSelect = function()
                OQ.Client.interactLocation(loc)
            end,
        },
    })

    spawned[loc.uid] = { entity = ent, point = index }
    OQ.debug('spawned location', loc.uid, 'at point', index)
end

-------------------------------------------------------------------------------
-- MARKER FALLBACK (for `marker` type locations)
-------------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        if Config.Interaction.markerFallback and OQ.State.ready and not OQ.State.nuiOpen then
            local coords = OQ.Client.playerCoords()
            for _, loc in ipairs(OQ.State.world.locations or {}) do
                if loc.entity.type == 'marker' and OQ.Client.scheduleActive(loc.schedule) then
                    local point = activePoint(loc)
                    if point then
                        local d = #(coords - vec3(point.x, point.y, point.z))
                        if d < 20.0 then
                            sleep = 0
                            DrawMarker(1, point.x, point.y, point.z - 0.95, 0, 0, 0, 0, 0, 0,
                                1.0, 1.0, 0.6, 224, 27, 132, 120, false, false, 2, false, nil, nil, false)
                            if d < 1.6 then
                                lib.showTextUI(('[E] %s'):format(loc.target.label or 'Interact'), { position = 'left-center' })
                                if IsControlJustReleased(0, 38) then
                                    lib.hideTextUI()
                                    OQ.Client.interactLocation(loc)
                                end
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-------------------------------------------------------------------------------
-- STREAMING LOOP
-------------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = Config.Interaction.tickIdle

        if OQ.State.ready then
            local coords = OQ.Client.playerCoords()
            local seen = {}

            for _, loc in ipairs(OQ.State.world.locations or {}) do
                seen[loc.uid] = true
                local point = activePoint(loc)
                if point then
                    local d = #(coords - vec3(point.x, point.y, point.z))

                    if d < Config.Interaction.discoveryRadius and not OQ.State.discovered[loc.uid] then
                        OQ.State.discovered[loc.uid] = true
                        TriggerServerEvent('oqv2:server:discover', loc.uid)
                    end

                    local shouldExist = d < Config.Interaction.spawnDistance
                        and OQ.Client.scheduleActive(loc.schedule)
                        and loc.entity.type ~= 'marker'

                    if shouldExist then
                        sleep = Config.Interaction.tickActive
                        local data = spawned[loc.uid]
                        if not data then
                            spawn(loc)
                        else
                            local _, index = activePoint(loc)
                            if data.point ~= index or (data.entity and not DoesEntityExist(data.entity)) then
                                despawn(loc.uid)
                                spawn(loc)
                            end
                        end
                    elseif spawned[loc.uid] and d > Config.Interaction.despawnDistance then
                        despawn(loc.uid)
                    elseif spawned[loc.uid] and not OQ.Client.scheduleActive(loc.schedule) then
                        despawn(loc.uid)
                    end
                end
            end

            for uid in pairs(spawned) do
                if not seen[uid] then despawn(uid) end
            end
        end

        Wait(sleep)
    end
end)

-- blips refresh (cheap, every 30s and on world updates)
CreateThread(function()
    while true do
        if OQ.State.ready then refreshBlips() end
        Wait(30000)
    end
end)

AddEventHandler('oqv2:client:worldUpdated', function()
    for uid in pairs(spawned) do despawn(uid) end
    refreshBlips()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= OQ.resource then return end
    for uid in pairs(spawned) do despawn(uid) end
    for uid in pairs(blips) do removeBlip(uid) end
    lib.hideTextUI()
end)
