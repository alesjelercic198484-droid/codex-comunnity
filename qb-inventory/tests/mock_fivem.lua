--[============================================================================[
    Minimal FiveM + qb-core emulator used by the qb-inventory test suite.

    It implements just enough of the runtime (events, exports, state bags,
    players, a fake qb-core) to really EXECUTE server/core.lua and
    server/main.lua and then assert on the results.

    Run it with:      python3 tests/run_lua_tests.py
    or with Lua:      lua tests/run_tests.lua
]============================================================================]

local Mock = {}

Mock.events = {}          -- [name] = { handlers }
Mock.clientEvents = {}    -- [source] = { {name, args} }
Mock.players = {}         -- [source] = fake player
Mock.log = {}

-- ---------------------------------------------------------------------------
-- JSON (the test environment has no FiveM json global)
-- ---------------------------------------------------------------------------
local json = {}

function json.encode(value)
    local kind = type(value)

    if value == nil then return 'null' end
    if kind == 'boolean' then return tostring(value) end
    if kind == 'number' then
        if math.floor(value) == value then return string.format('%d', value) end
        return tostring(value)
    end
    if kind == 'string' then
        local out = value:gsub('[%c"\\]', function(c)
            local map = { ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
                          ['"'] = '\\"', ['\\'] = '\\\\' }
            return map[c] or string.format('\\u%04X', c:byte())
        end)
        return '"' .. out .. '"'
    end

    if kind ~= 'table' then return 'null' end

    -- detect array
    local count, max = 0, 0
    for k in pairs(value) do
        if type(k) == 'number' then
            count = count + 1
            if k > max then max = k end
        end
    end

    local parts = {}

    if count > 0 and count == max then
        for i = 1, max do parts[#parts + 1] = json.encode(value[i]) end
        return '[' .. table.concat(parts, ',') .. ']'
    end

    for k, v in pairs(value) do
        parts[#parts + 1] = json.encode(tostring(k)) .. ':' .. json.encode(v)
    end

    return '{' .. table.concat(parts, ',') .. '}'
end

function json.decode(text)
    if type(text) ~= 'string' or text == '' then return nil end

    local pos = 1

    local function skip()
        while pos <= #text and text:sub(pos, pos):match('%s') do pos = pos + 1 end
    end

    local parse

    local function parseString()
        pos = pos + 1
        local out = {}

        while pos <= #text do
            local c = text:sub(pos, pos)
            if c == '"' then pos = pos + 1 break end
            if c == '\\' then
                local n = text:sub(pos + 1, pos + 1)
                local map = { n = '\n', t = '\t', r = '\r', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
                out[#out + 1] = map[n] or n
                pos = pos + 2
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end

        return table.concat(out)
    end

    function parse()
        skip()
        local c = text:sub(pos, pos)

        if c == '{' then
            pos = pos + 1
            local out = {}
            skip()
            if text:sub(pos, pos) == '}' then pos = pos + 1 return out end

            while pos <= #text do
                skip()
                local key = parseString()
                skip()
                pos = pos + 1 -- ':'
                out[key] = parse()
                skip()
                local d = text:sub(pos, pos)
                pos = pos + 1
                if d == '}' then break end
            end
            return out
        end

        if c == '[' then
            pos = pos + 1
            local out = {}
            skip()
            if text:sub(pos, pos) == ']' then pos = pos + 1 return out end

            while pos <= #text do
                out[#out + 1] = parse()
                skip()
                local d = text:sub(pos, pos)
                pos = pos + 1
                if d == ']' then break end
            end
            return out
        end

        if c == '"' then return parseString() end

        local literal = text:match('^[-%d%.eE+]+', pos) or text:match('^%a+', pos)
        if literal then
            pos = pos + #literal
            if literal == 'true' then return true end
            if literal == 'false' then return false end
            if literal == 'null' then return nil end
            return tonumber(literal)
        end

        pos = pos + 1
        return nil
    end

    return parse()
end

-- ---------------------------------------------------------------------------
-- Globals the resource expects
-- ---------------------------------------------------------------------------
_G.json = json

local registered = {}       -- [name] = fn  (exports defined by the resource)
local resourceProxy = {}

_G.exports = setmetatable({}, {
    __call = function(_, name, fn)
        registered[name] = fn
    end,
    __index = function(_, key)
        if not resourceProxy[key] then
            resourceProxy[key] = setmetatable({}, {
                __index = function(_, method)
                    return function(_, ...)
                        local res = Mock.qbcore and Mock.qbcore.exports and
                                    Mock.qbcore.exports[key] and
                                    Mock.qbcore.exports[key][method]
                        if res then return res(...) end
                        return nil
                    end
                end
            })
        end
        return resourceProxy[key]
    end
})

Mock.registered = registered

function Mock.Export(name, ...)
    local fn = registered[name]
    if not fn then error('export not registered: ' .. tostring(name), 2) end
    return fn(...)
end

_G.RegisterNetEvent = function(name, fn)
    Mock.events[name] = Mock.events[name] or {}
    if fn then table.insert(Mock.events[name], fn) end
end

_G.RegisterServerEvent = _G.RegisterNetEvent

_G.AddEventHandler = function(name, fn)
    Mock.events[name] = Mock.events[name] or {}
    table.insert(Mock.events[name], fn)
end

_G.RegisterCommand = function(name, fn, restricted)
    Mock.commands = Mock.commands or {}
    Mock.commands[name] = fn
end

_G.TriggerEvent = function(name, ...)
    for _, fn in ipairs(Mock.events[name] or {}) do
        fn(...)
    end
end

local currentSource = nil

_G.TriggerClientEvent = function(name, source, ...)
    if type(name) ~= 'string' then return end

    if source == -1 then
        for id in pairs(Mock.players) do
            Mock.clientEvents[id] = Mock.clientEvents[id] or {}
            table.insert(Mock.clientEvents[id], { name = name, args = { ... } })
        end
    else
        Mock.clientEvents[source] = Mock.clientEvents[source] or {}
        table.insert(Mock.clientEvents[source], { name = name, args = { ... } })
    end
end

_G.GetCurrentResourceName = function() return 'qb-inventory' end
_G.GetInvokingResource = function() return 'test' end
_G.Wait = function() end
_G.SetTimeout = function(_, fn) fn() end
_G.CreateThread = function(fn) end
_G.IsPlayerAceAllowed = function(source, ace) return Mock.aces and Mock.aces[ace] == true end
_G.GetPlayerName = function(source)
    local p = Mock.players[source]
    return p and p.name or ('Player' .. tostring(source))
end

_G.GetPlayerPed = function(source)
    local p = Mock.players[source]
    return p and p.ped or 0
end

_G.GetEntityCoords = function(entity)
    local p = Mock.pedCoords and Mock.pedCoords[entity]
    if p then return { x = p.x, y = p.y, z = p.z } end
    return { x = 0, y = 0, z = 0 }
end

_G.Player = function(source)
    return {
        state = setmetatable({}, {
            __newindex = function(_, k, v)
                Mock.players[source].stateBag[k] = v
            end,
            __index = function(_, k)
                return Mock.players[source].stateBag[k]
            end
        })
    }
end

-- No SQL by default: this also proves the "works without the table" fallback.
_G.MySQL = nil

function Mock.EnableSql()
    Mock.sql = {}
    _G.MySQL = {
        prepare = {
            await = function(query, params)
                if query:find('SELECT') then
                    return Mock.sql[params[1]]
                end
                Mock.sql[params[1]] = { items = params[5] }
                return 1
            end
        }
    }
end

-- ---------------------------------------------------------------------------
-- Fake qb-core
-- ---------------------------------------------------------------------------
local QBCore = {}

QBCore.Shared = { Items = {} }
QBCore.Functions = {}
QBCore.exportTable = {}

function Mock.AddItem(name, definition)
    QBCore.Shared.Items[name] = definition
end

function Mock.AddPlayer(source, data)
    data = data or {}

    Mock.players[source] = {
        source = source,
        name = data.name or ('Player' .. tostring(source)),
        ped = 1000 + source,
        stateBag = {},
        PlayerData = {
            source = source,
            citizenid = data.citizenid or ('CID' .. tostring(source)),
            name = data.name or ('Player' .. tostring(source)),
            money = { cash = data.cash or 0, bank = data.bank or 0 },
            items = data.items or {},
            job = { name = data.job or 'unemployed', label = data.job or 'Unemployed' },
        },
        notifications = {},
        saved = false,
    }

    Mock.pedCoords = Mock.pedCoords or {}
    Mock.pedCoords[1000 + source] = { x = data.x or 0, y = data.y or 0, z = data.z or 0 }
    Mock.clientEvents[source] = {}

    return Mock.players[source]
end

function Mock.Inventory(source)
    return Mock.players[source].PlayerData.items
end

function Mock.Count(source, item)
    local total = 0
    for _, v in pairs(Mock.Inventory(source)) do
        if type(v) == 'table' and v.name == item then
            total = total + (tonumber(v.amount) or 1)
        end
    end
    return total
end

function QBCore.Functions.GetPlayer(source)
    return Mock.players[source]
end

-- QBCore.UsableItems[item] = { func = <callback> }  (matches qb-core)
QBCore.UsableItems = {}

function QBCore.Functions.CreateUseableItem(item, cb)
    QBCore.UsableItems[item] = { func = cb, resource = 'test' }
end

function QBCore.Functions.CanUseItem(item)
    return QBCore.UsableItems[item]
end

function QBCore.Functions.UseItem(source, item)
    -- Real qb-core delegates straight back to the inventory export.
    local fn = registered['UseItem']
    if fn then return fn(source, item) end
end

function QBCore.Functions.Notify(source, message, kind)
    local p = Mock.players[source]
    if p then table.insert(p.notifications, { message = message, kind = kind }) end
end

QBCore.Functions.CreateCallback = function(name, fn)
    Mock.callbacks = Mock.callbacks or {}
    Mock.callbacks[name] = fn
end

-- Player object methods used by the resource
local function attachPlayerMethods(player)
    player.Functions = player.Functions or {}

    player.Functions.SetPlayerData = function(self, key, value)
        if key == 'items' then
            player.PlayerData.items = value
        elseif key == nil then
            -- full refresh
        end
    end

    -- qb-core signature: Player.Functions.RemoveMoney(moneytype, amount, reason)
    player.Functions.RemoveMoney = function(account, amount, reason)
        amount = tonumber(amount)
        if not amount or amount < 0 then return false end
        if player.PlayerData.money[account] == nil then return false end
        if (player.PlayerData.money[account] - amount) < 0 then return false end
        player.PlayerData.money[account] = player.PlayerData.money[account] - amount
        return true
    end

    player.Functions.AddMoney = function(account, amount, reason)
        amount = tonumber(amount) or 0
        if player.PlayerData.money[account] == nil then return false end
        player.PlayerData.money[account] = player.PlayerData.money[account] + amount
        return true
    end

    player.Functions.Save = function(self) player.saved = true end

    return player
end

function Mock.AttachMethods()
    for _, player in pairs(Mock.players) do attachPlayerMethods(player) end
end

function Mock.CreateUseableItem(item, cb)
    QBCore.Functions.CreateUseableItem(item, cb)
end

function Mock.UsedItems()
    return Mock.usedItems
end

Mock.qbcore = { exports = { ['qb-core'] = { GetCoreObject = function() return QBCore end } } }
Mock.QBCore = QBCore

-- ---------------------------------------------------------------------------
-- Loading the resource scripts
-- ---------------------------------------------------------------------------
--- Loads a resource script into the global environment (like fxserver does).
function Mock.LoadScript(path, env)
    local handle = assert(loadfile(path))

    if env and env ~= _G then
        setmetatable(env, { __index = _G })
        if _G.setfenv then _G.setfenv(handle, env) end
    end

    return handle()
end

function Mock.Fire(name, ...)
    for _, fn in ipairs(Mock.events[name] or {}) do
        currentSource = nil
        fn(...)
    end
end

function Mock.FireFromClient(source, name, ...)
    -- emulate `source` inside a server net event handler
    local handlers = Mock.events[name] or {}

    for _, fn in ipairs(handlers) do
        currentSource = source
        _G.source = source
        fn(...)
    end

    _G.source = nil
end

function Mock.LastClientEvent(source, name)
    local list = Mock.clientEvents[source] or {}

    for i = #list, 1, -1 do
        if list[i].name == name then return list[i] end
    end

    return nil
end

--- Calls a QBCore callback: Mock.Callback(name, source, ...arguments)
function Mock.Callback(name, source, ...)
    local fn = Mock.callbacks and Mock.callbacks[name]
    if not fn then error('callback not registered: ' .. tostring(name), 2) end

    local result
    fn(source, function(value) result = value end, ...)
    return result
end

return Mock
