--[[ OQV2 QUESTS — Evil NPC system: spawn, combat, loot, respawn
     Made with CodeX Dev. ]]

--- groups[uid] = { peds = { ped = handle, dead = bool, looted = bool }, spawnedAt, cleared, respawnAt }
local groups   = {}
local relationship = false

local function ensureRelationship()
    if relationship then return end
    AddRelationshipGroup('OQV2_HOSTILE')
    local hostile, player = joaat('OQV2_HOSTILE'), joaat('PLAYER')
    SetRelationshipBetweenGroups(5, hostile, player)
    SetRelationshipBetweenGroups(5, player, hostile)
    SetRelationshipBetweenGroups(0, hostile, hostile)
    relationship = true
end

local function difficultyStats(name)
    for _, d in ipairs(OQ.Schema.difficulties) do
        if d.value == name then return d end
    end
    return OQ.Schema.difficulties[2]
end

local function activeGroupCount()
    local n = 0
    for _, g in pairs(groups) do
        if not g.cleared then n = n + 1 end
    end
    return n
end

-------------------------------------------------------------------------------
-- CLEANUP
-------------------------------------------------------------------------------
local function removeGroup(uid, hard)
    local g = groups[uid]
    if not g then return end
    for _, unit in ipairs(g.peds) do
        if unit.ped and DoesEntityExist(unit.ped) then
            pcall(function() exports.ox_target:removeLocalEntity(unit.ped) end)
            SetEntityAsMissionEntity(unit.ped, true, true)
            DeleteEntity(unit.ped)
        end
    end
    if hard then
        groups[uid] = nil
    else
        g.peds = {}
    end
end

-------------------------------------------------------------------------------
-- LOOT TARGET
-------------------------------------------------------------------------------
local function addLootTarget(npc, unit)
    exports.ox_target:addLocalEntity(unit.ped, {
        {
            name     = 'oqv2_loot_' .. npc.uid .. '_' .. tostring(unit.ped),
            icon     = 'fa-solid fa-hand',
            label    = 'Search body',
            distance = Config.EvilNPC.lootRadius or 2.0,
            canInteract = function(entity)
                return IsEntityDead(entity) and not unit.looted
            end,
            onSelect = function()
                if unit.looted then return end
                local ok = lib.progressBar({
                    duration  = 3000,
                    label     = 'Searching...',
                    canCancel = true,
                    disable   = { car = true, move = true, combat = true },
                    anim      = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search' },
                })
                if not ok then return end
                unit.looted = true
                local res = lib.callback.await('oqv2:server:lootNpc', false, npc.uid)
                if res and res.success then
                    if res.empty then
                        OQ.Client.notify(Config.UI.brand, res.message, 'inform')
                    else
                        local lines = {}
                        for _, item in ipairs(res.items or {}) do
                            lines[#lines + 1] = ('%dx %s'):format(item.count, item.name)
                        end
                        if (res.money or 0) > 0 then lines[#lines + 1] = ('$%d'):format(res.money) end
                        OQ.Client.notify(Config.UI.brand, table.concat(lines, ', '), 'success')
                    end
                else
                    OQ.Client.notify(Config.UI.brand, res and res.message or OQ.L('generic_error'), 'error')
                end
                pcall(function() exports.ox_target:removeLocalEntity(unit.ped) end)
            end,
        },
    })
end

-------------------------------------------------------------------------------
-- SPAWN
-------------------------------------------------------------------------------
local function spawnGroup(npc)
    ensureRelationship()

    local hash = OQ.Client.loadModel(npc.model)
    if not hash then return end

    local stats = difficultyStats(npc.difficulty)
    local total = (npc.count or 1) + (npc.companions or 0)
    local units = {}

    for i = 1, total do
        local angle  = (i / total) * math.pi * 2
        local spread = math.min(npc.radius or 10.0, 12.0)
        local x = npc.coords.x + math.cos(angle) * spread * 0.5
        local y = npc.coords.y + math.sin(angle) * spread * 0.5
        local z = npc.coords.z

        local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
        if found then z = groundZ end

        local ped = CreatePed(4, hash, x, y, z, math.random(0, 359) + 0.0, false, true)
        if DoesEntityExist(ped) then
            SetPedRelationshipGroupHash(ped, joaat('OQV2_HOSTILE'))
            SetPedArmour(ped, stats.armour)
            SetEntityMaxHealth(ped, stats.health)
            SetEntityHealth(ped, stats.health)
            SetPedAccuracy(ped, stats.accuracy)
            SetPedDropsWeaponsWhenDead(ped, false)
            SetPedSuffersCriticalHits(ped, true)
            SetPedFleeAttributes(ped, 0, false)
            SetPedCombatAttributes(ped, 46, true)   -- always fight
            SetPedCombatAttributes(ped, 5, true)    -- can use vehicles
            SetPedCombatAttributes(ped, 0, true)    -- can use cover
            SetPedCombatRange(ped, 2)
            SetPedCombatMovement(ped, (npc.aggression or 75) > 60 and 3 or 1)
            SetPedAlertness(ped, 3)
            SetPedSeeingRange(ped, 90.0)
            SetPedHearingRange(ped, 120.0)

            local weapon = npc.weapons[math.random(1, #npc.weapons)]
            GiveWeaponToPed(ped, joaat(weapon), 250, false, true)

            TaskWanderInArea(ped, npc.coords.x, npc.coords.y, npc.coords.z, npc.radius or 15.0, 5.0, 5.0)

            units[#units + 1] = { ped = ped, dead = false, looted = false }
        end
    end

    SetModelAsNoLongerNeeded(hash)

    groups[npc.uid] = {
        peds      = units,
        spawnedAt = GetGameTimer(),
        cleared   = false,
        alerted   = false,
        respawnAt = nil,
    }
    OQ.debug('spawned hostile group', npc.uid, #units, 'units')
end

-------------------------------------------------------------------------------
-- MONITOR
-------------------------------------------------------------------------------
local function monitorGroup(npc)
    local g = groups[npc.uid]
    if not g then return end

    local alive = 0
    for _, unit in ipairs(g.peds) do
        if unit.ped and DoesEntityExist(unit.ped) then
            if IsEntityDead(unit.ped) then
                if not unit.dead then
                    unit.dead = true
                    local killer = GetPedSourceOfDeath(unit.ped)
                    if killer == PlayerPedId() then
                        TriggerServerEvent('oqv2:server:npcKilled', npc.uid)
                    end
                    addLootTarget(npc, unit)
                    SetTimeout((Config.EvilNPC.corpseCleanup or 120) * 1000, function()
                        if unit.ped and DoesEntityExist(unit.ped) then
                            pcall(function() exports.ox_target:removeLocalEntity(unit.ped) end)
                            SetEntityAsMissionEntity(unit.ped, true, true)
                            DeleteEntity(unit.ped)
                        end
                    end)
                end
            else
                alive = alive + 1
                -- engage the player when close enough
                local playerPed = PlayerPedId()
                local d = #(GetEntityCoords(unit.ped) - GetEntityCoords(playerPed))
                if d < (npc.radius or 20.0) + 25.0 then
                    if not IsPedInCombat(unit.ped, playerPed) then
                        TaskCombatPed(unit.ped, playerPed, 0, 16)
                    end
                    if not g.alerted then
                        g.alerted = true
                        if npc.alertPolice then
                            TriggerServerEvent('oqv2:server:npcAlert', npc.uid, OQ.vecToTable(GetEntityCoords(playerPed)))
                        end
                    end
                end
            end
        end
    end

    if alive == 0 and not g.cleared then
        g.cleared = true
        g.respawnAt = GetGameTimer() + ((npc.respawn or 300) * 1000)
        OQ.debug('hostile group cleared', npc.uid)
    end
end

-------------------------------------------------------------------------------
-- MAIN LOOP
-------------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 2000

        if Config.EvilNPC.enabled and OQ.State.ready then
            local coords = OQ.Client.playerCoords()
            local seen = {}

            for _, npc in ipairs(OQ.State.world.npcs or {}) do
                seen[npc.uid] = true
                local d = #(coords - vec3(npc.coords.x, npc.coords.y, npc.coords.z))
                local g = groups[npc.uid]

                -- respawn handling
                if g and g.cleared and g.respawnAt and GetGameTimer() >= g.respawnAt then
                    removeGroup(npc.uid, true)
                    TriggerServerEvent('oqv2:server:npcRespawned', npc.uid)
                    g = nil
                end

                local trigger = (npc.trigger and npc.trigger.distance) or 90.0

                if d <= trigger then
                    if not g and activeGroupCount() < (Config.EvilNPC.maxActiveGroups or 4) then
                        local linked = npc.linkedMission
                        local allowed = true
                        if linked then
                            -- only spawn story hostiles while the linked mission is running
                            allowed = OQ.State.active ~= nil and OQ.State.active.uid == linked
                        end
                        if allowed then spawnGroup(npc) end
                    elseif g and not g.cleared then
                        sleep = 500
                        monitorGroup(npc)
                    end
                elseif d > trigger + 100.0 and g then
                    removeGroup(npc.uid, true)
                end
            end

            for uid in pairs(groups) do
                if not seen[uid] then removeGroup(uid, true) end
            end
        end

        Wait(sleep)
    end
end)

AddEventHandler('oqv2:client:worldUpdated', function()
    for uid in pairs(groups) do removeGroup(uid, true) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= OQ.resource then return end
    for uid in pairs(groups) do removeGroup(uid, true) end
end)
