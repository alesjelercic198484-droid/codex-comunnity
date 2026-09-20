--[[
    Minimal FiveM / ESX emulator used by the automated test suite.
    It implements just enough of the runtime (natives, threads, callbacks,
    oxmysql-like driver backed by an in-memory table) to actually execute the
    resource code and assert on real behaviour.
]]

local Mock = {}

-- ---------------------------------------------------------------------------
-- SCHEDULER
-- ---------------------------------------------------------------------------
local clock = 0            -- virtual game time in ms
local osOffset = 0         -- virtual offset applied to os.time()
local threads = {}

local realOsTime = os.time
local realOsDate = os.date

os.time = function(t)
    if t then
        return realOsTime(t)
    end
    return realOsTime() + osOffset
end

os.date = function(format, timestamp)
    return realOsDate(format, timestamp or os.time())
end

function Mock.AdvanceOsTime(seconds)
    osOffset = osOffset + seconds
end

function Mock.GetClock()
    return clock
end

local function resumeThread(entry)
    if coroutine.status(entry.co) == 'dead' then
        entry.dead = true
        return
    end

    local ok, result = coroutine.resume(entry.co)

    if not ok then
        entry.dead = true
        error(('thread error: %s'):format(result), 0)
    end

    if coroutine.status(entry.co) == 'dead' then
        entry.dead = true
    else
        entry.wakeAt = clock + (tonumber(result) or 0)
    end
end

function CreateThread(fn)
    local entry = { co = coroutine.create(fn), wakeAt = clock }
    threads[#threads + 1] = entry
    return entry
end

Citizen = Citizen or {}
Citizen.CreateThread = CreateThread
Citizen.CreateThreadNow = CreateThread

function Wait(ms)
    coroutine.yield(tonumber(ms) or 0)
end

Citizen.Wait = Wait

function SetTimeout(ms, fn)
    CreateThread(function()
        Wait(ms)
        fn()
    end)
end

--- Runs the scheduler until `ms` of virtual time has passed.
function Mock.Tick(ms)
    local target = clock + (ms or 0)

    while clock <= target do
        local ran = false

        for _, entry in ipairs(threads) do
            if not entry.dead and entry.wakeAt <= clock then
                resumeThread(entry)
                ran = true
            end
        end

        -- Drop finished threads.
        local alive = {}
        for _, entry in ipairs(threads) do
            if not entry.dead then
                alive[#alive + 1] = entry
            end
        end
        threads = alive

        if clock == target then
            break
        end

        -- Jump straight to the next wake up to keep the tests fast.
        local nextWake = target
        for _, entry in ipairs(threads) do
            if entry.wakeAt > clock and entry.wakeAt < nextWake then
                nextWake = entry.wakeAt
            end
        end

        if not ran and nextWake == target then
            clock = target
        else
            clock = math.min(nextWake, target)
        end
    end

    clock = target
end

-- ---------------------------------------------------------------------------
-- PROMISES
-- ---------------------------------------------------------------------------
promise = {}
promise.__index = promise

function promise.new()
    return setmetatable({ _resolved = false, _value = nil }, promise)
end

function promise:resolve(value)
    if self._resolved then
        return
    end
    self._resolved = true
    self._value = value
end

function Citizen.Await(p)
    if type(p) ~= 'table' then
        return p
    end

    local guard = 0
    while not p._resolved do
        guard = guard + 1
        if guard > 100000 then
            error('Citizen.Await deadlock', 0)
        end
        Wait(0)
    end

    return p._value
end

-- ---------------------------------------------------------------------------
-- RESOURCE / EVENTS
-- ---------------------------------------------------------------------------
local resourceName = 'codex_cryptomining'
local resourceStates = {
    oxmysql = 'started',
    es_extended = 'started',
    ox_inventory = 'missing',
    ox_target = 'missing',
    ox_lib = 'missing',
    ['qb-target'] = 'missing'
}

function GetCurrentResourceName()
    return resourceName
end

function GetResourceState(name)
    return resourceStates[name] or 'missing'
end

function Mock.SetResourceState(name, state)
    resourceStates[name] = state
end

local eventHandlers = {}
local netEventHandlers = {}

function AddEventHandler(name, handler)
    eventHandlers[name] = eventHandlers[name] or {}
    table.insert(eventHandlers[name], handler)
    return { name = name }
end

function RegisterNetEvent(name, handler)
    if handler then
        netEventHandlers[name] = netEventHandlers[name] or {}
        table.insert(netEventHandlers[name], handler)
    end
    return true
end

RegisterServerEvent = RegisterNetEvent

function TriggerEvent(name, ...)
    for _, handler in ipairs(eventHandlers[name] or {}) do
        handler(...)
    end
    for _, handler in ipairs(netEventHandlers[name] or {}) do
        handler(...)
    end
end

Mock.clientEvents = {}

function TriggerClientEvent(name, target, ...)
    table.insert(Mock.clientEvents, { name = name, target = target, args = { ... } })
end

function TriggerServerEvent(name, ...)
    TriggerEvent(name, ...)
end

Mock.commands = {}

function RegisterCommand(name, handler)
    Mock.commands[name] = handler
end

function IsPlayerAceAllowed()
    return true
end

Mock.exportedFunctions = {}

function exports(name, fn)
    if type(name) == 'string' then
        Mock.exportedFunctions[name] = fn
    end
end

function PerformHttpRequest() end

-- ---------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------
json = {
    encode = function(value)
        local function encode(v)
            local t = type(v)
            if t == 'nil' then
                return 'null'
            elseif t == 'boolean' then
                return tostring(v)
            elseif t == 'number' then
                return tostring(v)
            elseif t == 'string' then
                return '"' .. v:gsub('[%c"\\]', function(c)
                    return ('\\u%04x'):format(c:byte())
                end) .. '"'
            elseif t == 'table' then
                local isArray = #v > 0
                local parts = {}

                if isArray then
                    for _, item in ipairs(v) do
                        parts[#parts + 1] = encode(item)
                    end
                    return '[' .. table.concat(parts, ',') .. ']'
                end

                for key, item in pairs(v) do
                    parts[#parts + 1] = encode(tostring(key)) .. ':' .. encode(item)
                end
                return '{' .. table.concat(parts, ',') .. '}'
            end
            return 'null'
        end

        return encode(value)
    end,
    decode = function()
        return {}
    end
}

-- ---------------------------------------------------------------------------
-- VECTORS
-- ---------------------------------------------------------------------------
local vectorMeta = {
    __index = function(self, key)
        return rawget(self, key)
    end,
    __sub = function(a, b)
        return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = (a.z or 0) - (b.z or 0) }, getmetatable(a))
    end,
    __len = function(self)
        return math.sqrt(self.x * self.x + self.y * self.y + (self.z or 0) * (self.z or 0))
    end
}

function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vectorMeta)
end

function vector4(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w }, vectorMeta)
end

-- ---------------------------------------------------------------------------
-- IN MEMORY SQL  (only the statements the resource actually uses)
-- ---------------------------------------------------------------------------
local database = {
    codex_crypto_warehouses = {},
    codex_crypto_rigs = {},
    codex_crypto_keys = {},
    codex_crypto_market = {}
}

Mock.database = database
Mock.queryLog = {}
local autoIncrement = { codex_crypto_rigs = 0, codex_crypto_market = 0 }

local function normalise(query)
    return (query:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function runSql(query, params, mode)
    query = normalise(query)
    table.insert(Mock.queryLog, query)
    params = params or {}

    local function param(index)
        return params[index]
    end

    if query:find('^CREATE TABLE') then
        return 0
    end

    -- INSERT INTO codex_crypto_warehouses ... ON DUPLICATE KEY UPDATE
    if query:find('INSERT INTO `codex_crypto_warehouses`') then
        local row = {
            warehouse_id = param(1),
            owner = param(2),
            owner_name = param(3),
            btc = param(4),
            bill = param(5),
            powered = param(6),
            locked = param(7),
            last_tick = param(8),
            total_mined = param(9),
            total_earned = param(10),
            robbed_at = param(11)
        }

        for index, existing in ipairs(database.codex_crypto_warehouses) do
            if existing.warehouse_id == row.warehouse_id then
                database.codex_crypto_warehouses[index] = row
                return 1
            end
        end

        table.insert(database.codex_crypto_warehouses, row)
        return 1
    end

    if query:find('INSERT INTO `codex_crypto_rigs`') then
        autoIncrement.codex_crypto_rigs = autoIncrement.codex_crypto_rigs + 1
        local id = autoIncrement.codex_crypto_rigs

        table.insert(database.codex_crypto_rigs, {
            id = id,
            warehouse_id = param(1),
            slot = param(2),
            gpus = 0,
            cpu = 0,
            cooler = 0,
            durability = 100,
            broken = 0
        })

        return id
    end

    if query:find('UPDATE `codex_crypto_rigs`') then
        local id = param(6)
        for _, row in ipairs(database.codex_crypto_rigs) do
            if row.id == id then
                row.gpus = param(1)
                row.cpu = param(2)
                row.cooler = param(3)
                row.durability = param(4)
                row.broken = param(5)
                return 1
            end
        end
        return 0
    end

    if query:find('DELETE FROM `codex_crypto_rigs` WHERE `id`') then
        local id = param(1)
        for index, row in ipairs(database.codex_crypto_rigs) do
            if row.id == id then
                table.remove(database.codex_crypto_rigs, index)
                return 1
            end
        end
        return 0
    end

    if query:find('DELETE FROM `codex_crypto_rigs` WHERE `warehouse_id`') then
        local warehouseId = param(1)
        local kept = {}
        local removed = 0

        for _, row in ipairs(database.codex_crypto_rigs) do
            if row.warehouse_id == warehouseId then
                removed = removed + 1
            else
                kept[#kept + 1] = row
            end
        end

        database.codex_crypto_rigs = kept
        return removed
    end

    if query:find('INSERT INTO `codex_crypto_keys`') then
        local warehouseId, identifier, name = param(1), param(2), param(3)

        for _, row in ipairs(database.codex_crypto_keys) do
            if row.warehouse_id == warehouseId and row.identifier == identifier then
                row.name = name
                return 1
            end
        end

        table.insert(database.codex_crypto_keys, { warehouse_id = warehouseId, identifier = identifier, name = name })
        return 1
    end

    if query:find('DELETE FROM `codex_crypto_keys` WHERE `warehouse_id` = %? AND `identifier`') then
        local warehouseId, identifier = param(1), param(2)
        local kept = {}

        for _, row in ipairs(database.codex_crypto_keys) do
            if not (row.warehouse_id == warehouseId and row.identifier == identifier) then
                kept[#kept + 1] = row
            end
        end

        database.codex_crypto_keys = kept
        return 1
    end

    if query:find('DELETE FROM `codex_crypto_keys` WHERE `warehouse_id`') then
        local warehouseId = param(1)
        local kept = {}

        for _, row in ipairs(database.codex_crypto_keys) do
            if row.warehouse_id ~= warehouseId then
                kept[#kept + 1] = row
            end
        end

        database.codex_crypto_keys = kept
        return 1
    end

    if query:find('INSERT INTO `codex_crypto_market`') then
        autoIncrement.codex_crypto_market = autoIncrement.codex_crypto_market + 1
        table.insert(database.codex_crypto_market, { id = autoIncrement.codex_crypto_market, price = param(1) })
        return autoIncrement.codex_crypto_market
    end

    if query:find('DELETE FROM `codex_crypto_market`') then
        return 0
    end

    -- SELECTs
    if query:find('SELECT %* FROM `codex_crypto_warehouses`') then
        local rows = {}
        for _, row in ipairs(database.codex_crypto_warehouses) do
            rows[#rows + 1] = row
        end
        return rows
    end

    if query:find('SELECT %* FROM `codex_crypto_rigs`') then
        local rows = {}
        for _, row in ipairs(database.codex_crypto_rigs) do
            rows[#rows + 1] = row
        end
        return rows
    end

    if query:find('SELECT %* FROM `codex_crypto_keys`') then
        local rows = {}
        for _, row in ipairs(database.codex_crypto_keys) do
            rows[#rows + 1] = row
        end
        return rows
    end

    if query:find('SELECT `price` FROM `codex_crypto_market`') then
        local rows = {}
        for index = #database.codex_crypto_market, 1, -1 do
            rows[#rows + 1] = { price = database.codex_crypto_market[index].price }
        end
        return rows
    end

    if mode == 'fetch' then
        return {}
    end

    return 0
end

Mock.oxmysql = {
    query = function(_, query, params, cb)
        local result = runSql(query, params, 'fetch')
        if cb then
            cb(result)
        end
    end,
    insert = function(_, query, params, cb)
        local result = runSql(query, params, 'insert')
        if cb then
            cb(result)
        end
    end,
    update = function(_, query, params, cb)
        local result = runSql(query, params, 'execute')
        if cb then
            cb(result)
        end
    end
}

-- exports table used by the resource: exports.oxmysql:query(...)
local exportsTable = setmetatable({}, {
    __index = function(_, key)
        if key == 'oxmysql' then
            return Mock.oxmysql
        end

        if key == 'es_extended' then
            return {
                getSharedObject = function()
                    return Mock.ESX
                end
            }
        end

        return setmetatable({}, {
            __index = function()
                return function()
                    error(('export "%s" is not available in the test environment'):format(tostring(key)), 0)
                end
            end
        })
    end,
    __call = function(_, name, fn)
        Mock.exportedFunctions[name] = fn
    end
})

_G.exports = exportsTable

-- ---------------------------------------------------------------------------
-- ESX
-- ---------------------------------------------------------------------------
local players = {}
Mock.players = players

local function newPlayer(source, identifier, name)
    local player = {
        source = source,
        identifier = identifier,
        name = name,
        job = { name = 'unemployed', grade = 0 },
        accounts = { bank = 0, money = 0, black_money = 0 },
        inventory = {},
        coords = vector3(0.0, 0.0, 0.0)
    }

    function player.getName()
        return player.name
    end

    function player.getMoney()
        return player.accounts.money
    end

    function player.addMoney(amount)
        player.accounts.money = player.accounts.money + amount
    end

    function player.removeMoney(amount)
        player.accounts.money = player.accounts.money - amount
    end

    function player.getAccount(account)
        return { name = account, money = player.accounts[account] or 0 }
    end

    function player.addAccountMoney(account, amount)
        player.accounts[account] = (player.accounts[account] or 0) + amount
    end

    function player.removeAccountMoney(account, amount)
        player.accounts[account] = (player.accounts[account] or 0) - amount
    end

    function player.getInventoryItem(item)
        return { name = item, count = player.inventory[item] or 0 }
    end

    function player.addInventoryItem(item, count)
        player.inventory[item] = (player.inventory[item] or 0) + count
    end

    function player.removeInventoryItem(item, count)
        player.inventory[item] = math.max(0, (player.inventory[item] or 0) - count)
    end

    function player.canCarryItem()
        return true
    end

    return player
end

Mock.NewPlayer = function(source, identifier, name)
    local player = newPlayer(source, identifier, name)
    players[source] = player
    return player
end

Mock.serverCallbacks = {}

Mock.ESX = {
    GetPlayerFromId = function(source)
        return players[tonumber(source)]
    end,
    GetExtendedPlayers = function()
        local list = {}
        for _, player in pairs(players) do
            list[#list + 1] = player
        end
        return list
    end,
    RegisterServerCallback = function(name, handler)
        Mock.serverCallbacks[name] = handler
    end,
    ShowNotification = function() end
}

--- Calls a registered server callback synchronously inside a thread.
function Mock.CallCallback(name, source, ...)
    local handler = Mock.serverCallbacks[name]

    if not handler then
        error(('callback "%s" is not registered'):format(name), 0)
    end

    local result = nil
    local done = false
    local args = { ... }

    CreateThread(function()
        handler(source, function(value)
            result = value
            done = true
        end, table.unpack(args))
    end)

    local guard = 0
    while not done and guard < 200 do
        Mock.Tick(50)
        guard = guard + 1
    end

    if not done then
        error(('callback "%s" never answered'):format(name), 0)
    end

    return result
end

-- ---------------------------------------------------------------------------
-- PED / WORLD NATIVES
-- ---------------------------------------------------------------------------
function GetPlayerPed(source)
    local player = players[tonumber(source)]
    return player and (1000 + tonumber(source)) or 0
end

function GetEntityCoords(entity)
    for source, player in pairs(players) do
        if entity == 1000 + source then
            return player.coords
        end
    end
    return vector3(0.0, 0.0, 0.0)
end

function GetPlayerName(source)
    local player = players[tonumber(source)]
    return player and player.name or nil
end

-- Convars. OneSync is reported as enabled so the distance checks are active
-- during the tests (the suite asserts that they actually block players).
Mock.convars = { onesync = 'on' }

function GetConvar(name, default)
    local value = Mock.convars[name]
    if value == nil then
        return default
    end
    return value
end

function GetConvarInt(name, default)
    return tonumber(Mock.convars[name]) or default
end

function GetPlayers()
    local list = {}
    for source in pairs(players) do
        list[#list + 1] = tostring(source)
    end
    return list
end

-- Routing buckets
Mock.buckets = {}
Mock.bucketLockdown = {}

function SetPlayerRoutingBucket(source, bucket)
    Mock.buckets[tonumber(source)] = bucket
end

function GetPlayerRoutingBucket(source)
    return Mock.buckets[tonumber(source)] or 0
end

function SetRoutingBucketEntityLockdownMode(bucket, mode)
    Mock.bucketLockdown[bucket] = mode
end

function SetRoutingBucketPopulationEnabled() end

Mock.Reset = function()
    Mock.clientEvents = {}
    Mock.queryLog = {}
end

return Mock
