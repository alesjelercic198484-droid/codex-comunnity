--[[
    Minimal FiveM / ESX / ox emulator used by the codex_bodyharvest simulation.

    It implements just enough of the runtime (scheduler, events, state bags,
    peds, blips, ox_inventory, ox_target, ox_lib, ESX) to really execute
    client/main.lua and server/main.lua and to assert on what happens.

    The server script and every client script run in their own Lua environment,
    exactly like on a real server, so a client can never touch a server local.
]]

local Mock = {}

-- ---------------------------------------------------------------------------
-- SCHEDULER (virtual clock)
-- ---------------------------------------------------------------------------
local clock = 0
local threads = {}

local function resumeThread(entry)
    if entry.dead or coroutine.status(entry.co) == 'dead' then
        entry.dead = true
        return
    end

    local ok, result = coroutine.resume(entry.co)

    if not ok then
        entry.dead = true
        error(('thread error (%s): %s'):format(entry.label or '?', tostring(result)), 0)
    end

    if coroutine.status(entry.co) == 'dead' then
        entry.dead = true
    else
        entry.wakeAt = clock + (tonumber(result) or 0)
    end
end

local function spawn(fn, label)
    local entry = { co = coroutine.create(fn), wakeAt = clock, label = label }
    threads[#threads + 1] = entry
    return entry
end

local function runReady()
    local guard = 0

    while true do
        guard = guard + 1

        if guard > 50000 then
            error('scheduler livelock', 0)
        end

        local ran = false
        local snapshot = {}

        for index, entry in ipairs(threads) do
            snapshot[index] = entry
        end

        for _, entry in ipairs(snapshot) do
            if not entry.dead and entry.wakeAt <= clock then
                resumeThread(entry)
                ran = true
            end
        end

        local alive = {}

        for _, entry in ipairs(threads) do
            if not entry.dead then
                alive[#alive + 1] = entry
            end
        end

        threads = alive

        if not ran then
            return
        end
    end
end

--- Advances the virtual clock by `ms`, running every thread on the way.
function Mock.Tick(ms)
    local target = clock + (tonumber(ms) or 0)

    runReady()

    while clock < target do
        local nextWake = target

        for _, entry in ipairs(threads) do
            if not entry.dead and entry.wakeAt > clock and entry.wakeAt < nextWake then
                nextWake = entry.wakeAt
            end
        end

        clock = nextWake
        runReady()
    end

    clock = target
    runReady()
end

function Mock.Clock()
    return clock
end

--- Advances the clock to an absolute point in time (never backwards).
function Mock.TickUntil(target)
    local delta = (tonumber(target) or 0) - clock

    if delta > 0 then
        Mock.Tick(delta)
    else
        Mock.Tick(0)
    end
end

-- ---------------------------------------------------------------------------
-- WORLD STATE
-- ---------------------------------------------------------------------------
Mock.players = {}        -- [id] = player table
Mock.entities = {}       -- [handle] = entity table
Mock.clientEvents = {}   -- [id] = { {name, args} }
Mock.serverLog = {}
local entityCounter = 5000

local function vectorLength(v)
    return math.sqrt((v.x or 0) ^ 2 + (v.y or 0) ^ 2 + (v.z or 0) ^ 2)
end

local vectorMeta = {}
vectorMeta.__index = vectorMeta
vectorMeta.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = (a.z or 0) - (b.z or 0) }, vectorMeta)
end
vectorMeta.__add = function(a, b)
    return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = (a.z or 0) + (b.z or 0) }, vectorMeta)
end
vectorMeta.__len = function(self)
    return vectorLength(self)
end
vectorMeta.__tostring = function(self)
    return ('vec(%.2f, %.2f, %.2f)'):format(self.x or 0, self.y or 0, self.z or 0)
end

local function vector3(x, y, z)
    return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, vectorMeta)
end

local function vector4(x, y, z, w)
    local v = vector3(x, y, z)
    v.w = w or 0.0
    return v
end

Mock.vector3 = vector3

--- Registers a player in the fake world.
function Mock.AddPlayer(data)
    local id = data.id
    entityCounter = entityCounter + 1

    local player = {
        id = id,
        name = data.name or ('Player' .. id),
        identifier = data.identifier or ('char1:' .. id),
        ped = entityCounter,
        coords = vector3(data.x or 0.0, data.y or 0.0, data.z or 0.0),
        health = data.health or 200,
        job = { name = data.job or 'unemployed', grade = 0, label = data.job or 'Unemployed' },
        accounts = { money = data.money or 0, bank = data.bank or 0, black_money = 0 },
        inventory = {},
        state = { values = {} },
        online = true
    }

    Mock.entities[player.ped] = { type = 'ped', player = id }
    Mock.players[id] = player
    Mock.clientEvents[id] = {}

    for item, count in pairs(data.items or {}) do
        player.inventory[item] = count
    end

    return player
end

function Mock.SetCoords(id, x, y, z)
    Mock.players[id].coords = vector3(x, y, z)
end

function Mock.SetHealth(id, health)
    Mock.players[id].health = health
end

function Mock.Kill(id)
    Mock.players[id].health = 0
end

function Mock.Revive(id)
    Mock.players[id].health = 200
end

function Mock.Drop(id)
    local player = Mock.players[id]

    if player then
        player.online = false
    end
end

function Mock.GiveItem(id, item, count)
    local inventory = Mock.players[id].inventory
    inventory[item] = (inventory[item] or 0) + count
end

function Mock.ItemCount(id, item)
    return Mock.players[id].inventory[item] or 0
end

function Mock.Money(id, account)
    return Mock.players[id].accounts[account or 'money']
end

-- ---------------------------------------------------------------------------
-- STATE BAGS
-- ---------------------------------------------------------------------------
local stateHandlers = {}   -- { key = key, cb = cb }

local function fireStateHandlers(bagName, key, value)
    for _, handler in ipairs(stateHandlers) do
        if handler.key == nil or handler.key == key then
            local ok, err = pcall(handler.cb, bagName, key, value, nil, true)

            if not ok then
                error(('state bag handler error: %s'):format(tostring(err)), 0)
            end
        end
    end
end

local function stateObject(id)
    local player = Mock.players[id]

    if not player then
        return nil
    end

    if player.stateObject then
        return player.stateObject
    end

    local object = setmetatable({}, {
        __index = function(_, key)
            if key == 'set' then
                return function(_, stateKey, value, replicated)
                    player.state.values[stateKey] = value
                    fireStateHandlers(('player:%d'):format(id), stateKey, value, replicated)
                end
            end

            return player.state.values[key]
        end
    })

    player.stateObject = object

    return object
end

function Mock.State(id, key)
    local player = Mock.players[id]
    return player and player.state.values[key]
end

-- ---------------------------------------------------------------------------
-- EVENTS
-- ---------------------------------------------------------------------------
local serverHandlers = {}          -- [name] = { fn }
local clientHandlers = {}          -- [id][name] = { fn }
local serverEnv

local function dispatchServer(name, playerId, args)
    local handlers = serverHandlers[name]

    if not handlers then
        return
    end

    for _, handler in ipairs(handlers) do
        spawn(function()
            serverEnv.source = playerId
            handler(table.unpack(args, 1, args.n))
        end, 'server:' .. name)
    end
end

local function dispatchClient(id, name, args)
    local store = clientHandlers[id]

    table.insert(Mock.clientEvents[id], { name = name, args = args })

    if not store or not store[name] then
        return
    end

    for _, handler in ipairs(store[name]) do
        spawn(function()
            handler(table.unpack(args, 1, args.n))
        end, ('client%d:%s'):format(id, name))
    end
end

--- Raw event injection: simulates a modified client talking to the server.
function Mock.EmitFromClient(id, name, ...)
    dispatchServer(name, id, table.pack(...))
end

function Mock.ClientEvents(id, name)
    local result = {}

    for _, event in ipairs(Mock.clientEvents[id] or {}) do
        if not name or event.name == name then
            result[#result + 1] = event
        end
    end

    return result
end

function Mock.LastClientEvent(id, name)
    local events = Mock.ClientEvents(id, name)
    return events[#events]
end

function Mock.ClearClientEvents(id)
    Mock.clientEvents[id] = {}
end

-- ---------------------------------------------------------------------------
-- BLIPS / NOTIFICATIONS (per client)
-- ---------------------------------------------------------------------------
local blipCounter = 0

function Mock.Blips(id, onlyAlive)
    local result = {}

    for _, blip in ipairs(Mock.players[id].blips or {}) do
        if not onlyAlive or blip.alive then
            result[#result + 1] = blip
        end
    end

    return result
end

function Mock.BlipsOfType(id, kind, onlyAlive)
    local result = {}

    for _, blip in ipairs(Mock.Blips(id, onlyAlive)) do
        if blip.kind == kind then
            result[#result + 1] = blip
        end
    end

    return result
end

function Mock.Notifications(id, filter)
    local result = {}

    for _, note in ipairs(Mock.players[id].notifications or {}) do
        if not filter or (note.title or ''):find(filter, 1, true) or (note.description or ''):find(filter, 1, true) then
            result[#result + 1] = note
        end
    end

    return result
end

function Mock.LastNotification(id)
    local list = Mock.players[id].notifications or {}
    return list[#list]
end

function Mock.ClearNotifications(id)
    Mock.players[id].notifications = {}
end

-- ---------------------------------------------------------------------------
-- ox_target registry (per client)
-- ---------------------------------------------------------------------------
function Mock.PlayerOptions(viewerId, targetId)
    local viewer = Mock.players[viewerId]
    local entity = Mock.players[targetId].ped
    local visible = {}

    for _, option in ipairs(viewer.target.globalPlayer) do
        local ok = true

        if option.canInteract then
            ok = option.canInteract(entity, 0.0, nil, option.name, nil) and true or false
        end

        if ok then
            visible[#visible + 1] = option
        end
    end

    return visible
end

function Mock.EntityOptions(viewerId, entity)
    local viewer = Mock.players[viewerId]
    local visible = {}

    for _, option in ipairs(viewer.target.entities[entity] or {}) do
        local ok = true

        if option.canInteract then
            ok = option.canInteract(entity, 0.0, nil, option.name, nil) and true or false
        end

        if ok then
            visible[#visible + 1] = option
        end
    end

    return visible
end

function Mock.OptionLabels(options)
    local labels = {}

    for _, option in ipairs(options) do
        labels[#labels + 1] = option.label
    end

    return labels
end

function Mock.HasOption(options, needle)
    for _, option in ipairs(options) do
        if (option.name or ''):find(needle, 1, true) or (option.label or ''):find(needle, 1, true) then
            return option
        end
    end

    return nil
end

--- Clicks an ox_target option exactly like a player would.
function Mock.Select(viewerId, options, needle, entity)
    local option = Mock.HasOption(options, needle)

    if not option then
        error(('option %s is not visible for player %s'):format(needle, viewerId), 0)
    end

    option.onSelect({ entity = entity })
end

function Mock.DealerPed(viewerId)
    return Mock.players[viewerId].dealerPed
end

-- ---------------------------------------------------------------------------
-- ox_lib progress control
-- ---------------------------------------------------------------------------
Mock.progress = {}   -- [id] = { cancel = bool, instant = bool }

function Mock.SetProgress(id, settings)
    Mock.progress[id] = settings
end

function Mock.LastProgress(id)
    return Mock.players[id].lastProgress
end

-- ---------------------------------------------------------------------------
-- SHARED NATIVE TABLE
-- ---------------------------------------------------------------------------
local function baseEnv(name)
    local env = {}

    env._G = env
    env.print = function(...)
        local parts = {}

        for index = 1, select('#', ...) do
            parts[#parts + 1] = tostring((select(index, ...)))
        end

        local line = table.concat(parts, ' ')
        Mock.serverLog[#Mock.serverLog + 1] = line

        if Mock.verbose then
            print('    ' .. line)
        end
    end

    for _, key in ipairs({
        'pairs', 'ipairs', 'next', 'type', 'tostring', 'tonumber', 'pcall', 'xpcall', 'select',
        'error', 'assert', 'setmetatable', 'getmetatable', 'rawget', 'rawset', 'rawequal',
        'table', 'string', 'math', 'os', 'coroutine', 'load', 'require', 'unpack'
    }) do
        env[key] = _G[key]
    end

    env.vector3 = vector3
    env.vector4 = vector4
    env.vec3 = vector3
    env.vec4 = vector4
    env.CreateThread = function(fn) spawn(fn, name) end
    env.Citizen = { CreateThread = env.CreateThread, Wait = function(ms) coroutine.yield(ms) end }
    env.Wait = function(ms) coroutine.yield(ms) end
    env.SetTimeout = function(ms, fn)
        spawn(function()
            coroutine.yield(ms)
            fn()
        end, name .. ':timeout')
    end
    env.GetGameTimer = function() return clock end
    env.GetCurrentResourceName = function() return 'codex_bodyharvest' end
    env.GetResourceState = function(resource)
        if resource == 'es_extended' or resource == 'ox_inventory' or resource == 'ox_target' or resource == 'ox_lib' then
            return 'started'
        end
        return 'missing'
    end
    env.joaat = function(value) return #tostring(value) * 7919 end
    env.json = {
        encode = function() return '{}' end,
        decode = function() return {} end
    }
    env.PerformHttpRequest = function() end

    return env
end

-- ---------------------------------------------------------------------------
-- SERVER ENVIRONMENT
-- ---------------------------------------------------------------------------
local function buildESX()
    local function xPlayer(id)
        local player = Mock.players[id]

        if not player or not player.online then
            return nil
        end

        return {
            source = id,
            identifier = player.identifier,
            job = player.job,
            getName = function() return player.name end,
            addAccountMoney = function(account, amount)
                player.accounts[account] = (player.accounts[account] or 0) + amount
            end,
            removeAccountMoney = function(account, amount)
                player.accounts[account] = (player.accounts[account] or 0) - amount
            end,
            getAccount = function(account)
                return { name = account, money = player.accounts[account] or 0 }
            end
        }
    end

    return {
        GetPlayerFromId = xPlayer,
        GetExtendedPlayers = function(filter, value)
            local list = {}

            for id, player in pairs(Mock.players) do
                if player.online then
                    if filter == 'job' then
                        if player.job.name == value then
                            list[#list + 1] = xPlayer(id)
                        end
                    else
                        list[#list + 1] = xPlayer(id)
                    end
                end
            end

            return list
        end,
        GetPlayers = function()
            local list = {}

            for id, player in pairs(Mock.players) do
                if player.online then
                    list[#list + 1] = id
                end
            end

            return list
        end
    }
end

local function inventoryCount(id, query)
    local player = Mock.players[id]

    if not player then
        return 0
    end

    if type(query) == 'table' then
        local result = {}

        for _, item in ipairs(query) do
            result[item] = player.inventory[item] or 0
        end

        return result
    end

    return player.inventory[query] or 0
end

local function serverExports()
    return setmetatable({}, {
        __index = function(_, resource)
            if resource == 'es_extended' then
                return { getSharedObject = function() return Mock.ESX end }
            end

            if resource == 'ox_inventory' then
                return {
                    Search = function(_, source, search, item)
                        if search ~= 'count' then
                            error('unsupported ox_inventory search: ' .. tostring(search), 0)
                        end

                        return inventoryCount(source, item)
                    end,
                    AddItem = function(_, source, item, count)
                        local player = Mock.players[source]

                        if not player or not player.online then
                            return false
                        end

                        if player.inventoryFull then
                            return false
                        end

                        player.inventory[item] = (player.inventory[item] or 0) + count

                        return true
                    end,
                    RemoveItem = function(_, source, item, count)
                        local player = Mock.players[source]

                        if not player or (player.inventory[item] or 0) < count then
                            return false
                        end

                        player.inventory[item] = player.inventory[item] - count

                        return true
                    end,
                    CanCarryItem = function(_, source, item, count)
                        local player = Mock.players[source]
                        return player and not player.inventoryFull or false
                    end
                }
            end

            error('unknown server export: ' .. tostring(resource), 0)
        end
    })
end

local function buildServerEnv()
    local env = baseEnv('server')

    Mock.ESX = buildESX()

    env.exports = serverExports()
    env.source = 0

    env.RegisterNetEvent = function(name, handler)
        if handler then
            serverHandlers[name] = serverHandlers[name] or {}
            table.insert(serverHandlers[name], handler)
        end
    end
    env.RegisterServerEvent = env.RegisterNetEvent
    env.AddEventHandler = env.RegisterNetEvent
    env.TriggerEvent = function(name, ...)
        for _, handler in ipairs(serverHandlers[name] or {}) do
            handler(...)
        end
    end
    env.TriggerClientEvent = function(name, target, ...)
        local args = table.pack(...)

        if target == -1 then
            for id, player in pairs(Mock.players) do
                if player.online then
                    dispatchClient(id, name, args)
                end
            end

            return
        end

        local id = tonumber(target)

        if id and Mock.players[id] and Mock.players[id].online then
            dispatchClient(id, name, args)
        end
    end
    env.GetPlayers = function()
        local list = {}

        for id, player in pairs(Mock.players) do
            if player.online then
                list[#list + 1] = tostring(id)
            end
        end

        table.sort(list, function(a, b) return tonumber(a) < tonumber(b) end)

        return list
    end
    env.GetPlayerName = function(id)
        local player = Mock.players[tonumber(id)]
        return (player and player.online) and player.name or nil
    end
    env.GetPlayerPed = function(id)
        local player = Mock.players[tonumber(id)]
        return (player and player.online) and player.ped or 0
    end
    env.GetEntityCoords = function(ped)
        local entity = Mock.entities[ped]

        if not entity then
            return vector3(0.0, 0.0, 0.0)
        end

        return Mock.players[entity.player].coords
    end
    env.GetEntityHealth = function(ped)
        local entity = Mock.entities[ped]

        if not entity then
            return 0
        end

        return Mock.players[entity.player].health
    end
    env.Player = function(id)
        return { state = stateObject(tonumber(id)) or setmetatable({}, { __index = function() return nil end }) }
    end
    env.AddStateBagChangeHandler = function(key, bagName, cb)
        stateHandlers[#stateHandlers + 1] = { key = key, bag = bagName, cb = cb }
    end

    return env
end

-- ---------------------------------------------------------------------------
-- CLIENT ENVIRONMENT
-- ---------------------------------------------------------------------------
local function clientExports(id)
    local player = Mock.players[id]

    return setmetatable({}, {
        __index = function(_, resource)
            if resource == 'es_extended' then
                return { getSharedObject = function()
                    return {
                        PlayerData = player.playerData or {},
                        ShowNotification = function(message)
                            player.notifications[#player.notifications + 1] = { title = 'ESX', description = message }
                        end
                    }
                end }
            end

            if resource == 'ox_inventory' then
                return {
                    Search = function(_, search, item)
                        if search ~= 'count' then
                            error('unsupported ox_inventory search: ' .. tostring(search), 0)
                        end

                        return inventoryCount(id, item)
                    end
                }
            end

            if resource == 'ox_target' then
                return {
                    addGlobalPlayer = function(_, options)
                        for _, option in ipairs(options) do
                            table.insert(player.target.globalPlayer, option)
                        end
                    end,
                    removeGlobalPlayer = function(_, names)
                        local remove = {}

                        for _, name in ipairs(type(names) == 'table' and names or { names }) do
                            remove[name] = true
                        end

                        local kept = {}

                        for _, option in ipairs(player.target.globalPlayer) do
                            if not remove[option.name] then
                                kept[#kept + 1] = option
                            end
                        end

                        player.target.globalPlayer = kept
                    end,
                    addLocalEntity = function(_, entity, options)
                        player.target.entities[entity] = player.target.entities[entity] or {}

                        for _, option in ipairs(options) do
                            table.insert(player.target.entities[entity], option)
                        end
                    end,
                    removeLocalEntity = function(_, entity)
                        player.target.entities[entity] = nil
                    end
                }
            end

            error('unknown client export: ' .. tostring(resource), 0)
        end
    })
end

local function buildClientEnv(id)
    local player = Mock.players[id]

    player.notifications = {}
    player.blips = {}
    player.target = { globalPlayer = {}, entities = {} }
    player.playerData = {}

    local env = baseEnv('client' .. id)

    clientHandlers[id] = {}

    env.exports = clientExports(id)

    env.RegisterNetEvent = function(name, handler)
        if handler then
            clientHandlers[id][name] = clientHandlers[id][name] or {}
            table.insert(clientHandlers[id][name], handler)
        end
    end
    env.AddEventHandler = env.RegisterNetEvent
    env.TriggerEvent = function(name, ...)
        for _, handler in ipairs(clientHandlers[id][name] or {}) do
            handler(...)
        end
    end
    env.TriggerServerEvent = function(name, ...)
        dispatchServer(name, id, table.pack(...))
    end

    env.LocalPlayer = { state = stateObject(id) }
    env.Player = function(serverId)
        local other = stateObject(tonumber(serverId))

        if not other then
            error('unknown player state ' .. tostring(serverId), 0)
        end

        return { state = other }
    end

    env.PlayerId = function() return id end
    env.PlayerPedId = function() return player.ped end
    env.GetPlayerServerId = function(index) return index end
    env.GetPlayerFromServerId = function(serverId) return serverId end
    env.GetPlayerPed = function(index)
        local other = Mock.players[tonumber(index)]
        return other and other.ped or 0
    end
    env.NetworkGetPlayerIndexFromPed = function(ped)
        local entity = Mock.entities[ped]
        return entity and entity.player or -1
    end
    env.IsPedAPlayer = function(ped)
        local entity = Mock.entities[ped]
        return entity ~= nil and entity.player ~= nil
    end
    env.DoesEntityExist = function(entity)
        return Mock.entities[entity] ~= nil
    end
    env.IsEntityDead = function(entity)
        local record = Mock.entities[entity]

        if not record or not record.player then
            return false
        end

        return Mock.players[record.player].health <= 0
    end
    env.GetEntityCoords = function(entity)
        local record = Mock.entities[entity]

        if not record then
            return vector3(0.0, 0.0, 0.0)
        end

        if record.player then
            return Mock.players[record.player].coords
        end

        return record.coords or vector3(0.0, 0.0, 0.0)
    end

    -- Tasks / animations
    env.TaskTurnPedToFaceEntity = function() player.facedBody = true end
    env.ClearPedTasks = function() player.tasksCleared = (player.tasksCleared or 0) + 1 end
    env.TaskStartScenarioInPlace = function() end
    env.FreezeEntityPosition = function() end
    env.SetEntityInvincible = function() end
    env.SetEntityCanBeDamaged = function() end
    env.SetBlockingOfNonTemporaryEvents = function() end
    env.SetPedDiesWhenInjured = function() end
    env.SetPedCanRagdollFromPlayerImpact = function() end
    env.SetPedFleeAttributes = function() end
    env.SetModelAsNoLongerNeeded = function() end
    env.RequestModel = function() end
    env.HasModelLoaded = function() return true end
    env.IsModelInCdimage = function() return true end
    env.DeleteEntity = function(entity) Mock.entities[entity] = nil end
    env.CreatePed = function(_, _, x, y, z)
        entityCounter = entityCounter + 1
        Mock.entities[entityCounter] = { type = 'ped', coords = vector3(x, y, z) }
        player.dealerPed = entityCounter
        return entityCounter
    end
    env.PlaySoundFrontend = function(_, sound)
        player.sounds = player.sounds or {}
        player.sounds[#player.sounds + 1] = sound
    end
    env.GetStreetNameAtCoord = function() return 12345 end
    env.GetStreetNameFromHashKey = function() return 'Route 68' end

    -- Blips
    local function newBlip(kind, x, y, z, radius)
        blipCounter = blipCounter + 1

        local blip = {
            handle = blipCounter,
            kind = kind,
            coords = vector3(x, y, z),
            radius = radius,
            alive = true,
            createdAt = clock,
            alphaChanges = 0,
            flashes = false
        }

        player.blips[#player.blips + 1] = blip
        player.blipIndex = player.blipIndex or {}
        player.blipIndex[blipCounter] = blip

        return blipCounter
    end

    local function findBlip(handle)
        return player.blipIndex and player.blipIndex[handle]
    end

    env.AddBlipForCoord = function(x, y, z) return newBlip('coord', x, y, z) end
    env.AddBlipForRadius = function(x, y, z, radius) return newBlip('radius', x, y, z, radius) end
    env.SetBlipSprite = function(handle, value) local b = findBlip(handle) if b then b.sprite = value end end
    env.SetBlipColour = function(handle, value) local b = findBlip(handle) if b then b.colour = value end end
    env.SetBlipScale = function(handle, value) local b = findBlip(handle) if b then b.scale = value end end
    env.SetBlipAlpha = function(handle, value)
        local b = findBlip(handle)
        if b then
            if b.alpha ~= value then b.alphaChanges = b.alphaChanges + 1 end
            b.alpha = value
        end
    end
    env.SetBlipAsShortRange = function() end
    env.SetBlipHighDetail = function() end
    env.SetBlipCategory = function() end
    env.SetBlipFlashes = function(handle, value) local b = findBlip(handle) if b then b.flashes = value end end
    env.SetBlipFlashInterval = function(handle, value) local b = findBlip(handle) if b then b.flashInterval = value end end
    env.BeginTextCommandSetBlipName = function() player.pendingBlipName = nil end
    env.AddTextComponentSubstringPlayerName = function(text) player.pendingBlipName = text end
    env.EndTextCommandSetBlipName = function(handle)
        local b = findBlip(handle)
        if b then b.label = player.pendingBlipName end
    end
    env.DoesBlipExist = function(handle)
        local b = findBlip(handle)
        return b ~= nil and b.alive
    end
    env.RemoveBlip = function(handle)
        local b = findBlip(handle)
        if b then
            b.alive = false
            b.removedAt = clock
        end
    end

    -- ox_lib
    env.lib = {
        notify = function(options)
            player.notifications[#player.notifications + 1] = {
                title = options.title,
                description = options.description,
                type = options.type,
                at = clock
            }
        end,
        progressCircle = function(options)
            player.lastProgress = options

            local settings = Mock.progress[id] or {}

            if not settings.instant then
                coroutine.yield(options.duration)
            end

            if settings.cancel then
                return false
            end

            return true
        end
    }
    env.lib.progressBar = env.lib.progressCircle

    return env
end

-- ---------------------------------------------------------------------------
-- LOADING
-- ---------------------------------------------------------------------------
local function loadInto(path, env)
    local file = assert(io.open(path, 'r'), 'cannot open ' .. path)
    local source = file:read('*a')
    file:close()

    local chunk, err = load(source, '@' .. path, 't', env)

    if not chunk then
        error(('syntax error in %s: %s'):format(path, err), 0)
    end

    chunk()
end

Mock.loadInto = loadInto

--- Loads config.lua once and shares the table with every environment.
function Mock.LoadConfig(path)
    local shared = baseEnv('config')
    loadInto(path, shared)
    Mock.Config = shared.Config
    return shared.Config
end

function Mock.LoadServer(path)
    serverEnv = buildServerEnv()
    serverEnv.Config = Mock.Config
    loadInto(path, serverEnv)
    Mock.serverEnv = serverEnv
    return serverEnv
end

function Mock.LoadClient(id, path)
    local env = buildClientEnv(id)
    env.Config = Mock.Config
    loadInto(path, env)
    Mock.players[id].env = env
    return env
end

function Mock.StopResource()
    for id, player in pairs(Mock.players) do
        if player.env then
            for _, handler in ipairs(clientHandlers[id]['onResourceStop'] or {}) do
                handler('codex_bodyharvest')
            end
        end
    end
end

function Mock.DropPlayer(id)
    Mock.Drop(id)
    dispatchServer('playerDropped', id, table.pack('quit'))
end

return Mock
