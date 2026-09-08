--[[ OQV2 QUESTS — FiveM native / dependency stubs for the offline test runner.
     Loaded before the resource files so they can execute outside the game. ]]

-------------------------------------------------------------------------------
-- minimal JSON (enough for our data shapes)
-------------------------------------------------------------------------------
json = {}

local function encodeValue(v, out)
    local t = type(v)
    if v == nil then
        out[#out + 1] = 'null'
    elseif t == 'boolean' then
        out[#out + 1] = tostring(v)
    elseif t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = 'null'
        elseif math.type and math.type(v) == 'integer' then out[#out + 1] = tostring(v)
        elseif v == math.floor(v) then out[#out + 1] = string.format('%d', v)
        else out[#out + 1] = string.format('%.14g', v) end
    elseif t == 'string' then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
            local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
            return map[c] or string.format('\\u%04x', c:byte())
        end) .. '"'
    elseif t == 'table' then
        local isArray, n = true, 0
        for k in pairs(v) do
            n = n + 1
            if type(k) ~= 'number' then isArray = false end
        end
        if isArray and n == #v then
            out[#out + 1] = '['
            for i = 1, #v do
                if i > 1 then out[#out + 1] = ',' end
                encodeValue(v[i], out)
            end
            out[#out + 1] = ']'
        else
            out[#out + 1] = '{'
            local first = true
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local val = v[k] ~= nil and v[k] or v[tonumber(k)]
                if not first then out[#out + 1] = ',' end
                first = false
                encodeValue(tostring(k), out)
                out[#out + 1] = ':'
                encodeValue(val, out)
            end
            out[#out + 1] = '}'
        end
    else
        out[#out + 1] = 'null'
    end
end

function json.encode(v)
    local out = {}
    encodeValue(v, out)
    return table.concat(out)
end

function json.decode(str)
    if type(str) ~= 'string' then return nil end
    local pos = 1
    local function skip()
        while pos <= #str and str:sub(pos, pos):match('%s') do pos = pos + 1 end
    end
    local parseValue
    local function parseString()
        pos = pos + 1
        local buf = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then pos = pos + 1 return table.concat(buf) end
            if c == '\\' then
                local n = str:sub(pos + 1, pos + 1)
                local map = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
                if map[n] then buf[#buf + 1] = map[n] pos = pos + 2
                elseif n == 'u' then buf[#buf + 1] = '?' pos = pos + 6
                else buf[#buf + 1] = n pos = pos + 2 end
            else
                buf[#buf + 1] = c
                pos = pos + 1
            end
        end
        error('unterminated string')
    end
    parseValue = function()
        skip()
        local c = str:sub(pos, pos)
        if c == '{' then
            pos = pos + 1
            local obj = {}
            skip()
            if str:sub(pos, pos) == '}' then pos = pos + 1 return obj end
            while true do
                skip()
                local k = parseString()
                skip()
                pos = pos + 1 -- :
                obj[k] = parseValue()
                skip()
                local d = str:sub(pos, pos)
                pos = pos + 1
                if d == '}' then return obj end
            end
        elseif c == '[' then
            pos = pos + 1
            local arr = {}
            skip()
            if str:sub(pos, pos) == ']' then pos = pos + 1 return arr end
            while true do
                arr[#arr + 1] = parseValue()
                skip()
                local d = str:sub(pos, pos)
                pos = pos + 1
                if d == ']' then return arr end
            end
        elseif c == '"' then
            return parseString()
        elseif str:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
        elseif str:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
        elseif str:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
        else
            local s, e = str:find('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
            if not s then error('unexpected char at ' .. pos .. ': ' .. c) end
            local numStr = str:sub(s, e)
            pos = e + 1
            return tonumber(numStr)
        end
    end
    local ok, res = pcall(parseValue)
    if not ok then return nil end
    return res
end

-------------------------------------------------------------------------------
-- vector3
-------------------------------------------------------------------------------
local vecMT = {}
vecMT.__index = vecMT
vecMT.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vecMT) end
vecMT.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vecMT) end
vecMT.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
vecMT.__tostring = function(a) return ('vec3(%.2f, %.2f, %.2f)'):format(a.x, a.y, a.z) end

function vec3(x, y, z)
    return setmetatable({ x = x + 0.0, y = y + 0.0, z = z + 0.0 }, vecMT)
end
vector3 = vec3

-------------------------------------------------------------------------------
-- test harness bookkeeping
-------------------------------------------------------------------------------
TEST = {
    prints = {},
    warnings = {},
    errors = {},
    clientEvents = {},   -- { name, target, args }
    threads = {},
    inventory = {},      -- [src][item] = count
    money = {},          -- [src][account] = amount
    db = { rows = {}, logs = {} },
    coords = {},         -- [src] = vec3
    jobs = {},           -- [src] = { name, grade }
    groups = {},         -- [src] = 'admin'
    aces = {},
    gameTimer = 0,
    resourceName = 'oqv2_quests',
}

local realPrint = print
TEST.rawPrint = realPrint
function print(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, ' ')
    TEST.prints[#TEST.prints + 1] = line
    if line:find('%[error%]') then TEST.errors[#TEST.errors + 1] = line end
    if line:find('%[warn%]') then TEST.warnings[#TEST.warnings + 1] = line end
    if os.getenv('OQ_VERBOSE') then realPrint(line) end
end

-------------------------------------------------------------------------------
-- CFX core natives
-------------------------------------------------------------------------------
function IsDuplicityVersion() return true end
function GetCurrentResourceName() return TEST.resourceName end
function GetResourceMetadata() return '2.0.0' end

function LoadResourceFile(_, file)
    return (TEST.files or {})[file]
end

function GetGameTimer() return TEST.gameTimer end

-- Wait() has a budget so `while true do ... Wait() end` game loops terminate
-- inside the test runner instead of hanging it.
TEST.waitBudget = 200
function Wait(_)
    TEST.waitBudget = TEST.waitBudget - 1
    if TEST.waitBudget <= 0 then error('__WAIT_BUDGET__', 0) end
end

--- Run every queued CreateThread/SetTimeout body once, with a fresh budget.
function TEST.runThreads(budget)
    local queued = TEST.threads
    TEST.threads = {}
    for _, fn in ipairs(queued) do
        TEST.waitBudget = budget or 60
        local ok, err = pcall(fn)
        if not ok and tostring(err):find('__WAIT_BUDGET__') == nil then
            TEST.errors[#TEST.errors + 1] = 'thread error: ' .. tostring(err)
        end
    end
    TEST.waitBudget = 1e9
    return #queued
end
function CreateThread(fn) TEST.threads[#TEST.threads + 1] = fn end
function SetTimeout(_, fn) TEST.threads[#TEST.threads + 1] = fn end

local eventHandlers = {}
function AddEventHandler(name, fn) eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
    for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
end
function TriggerClientEvent(name, target, ...)
    TEST.clientEvents[#TEST.clientEvents + 1] = { name = name, target = target, args = { ... } }
end
function RegisterCommand(name, fn) TEST.commands = TEST.commands or {}; TEST.commands[name] = fn end
function exports(name, fn) TEST.exports = TEST.exports or {}; TEST.exports[name] = fn end
function GetPlayers()
    local out = {}
    for src in pairs(TEST.jobs) do out[#out + 1] = tostring(src) end
    table.sort(out)
    return out
end
function GetPlayerName(src) return TEST.jobs[tonumber(src)] and ('Player' .. src) or nil end
function GetPlayerPed(src) return 1000 + tonumber(src) end
function GetEntityCoords(ped) return TEST.coords[ped - 1000] or vec3(0, 0, 0) end
function GetNumPlayerIdentifiers() return 1 end
function GetPlayerIdentifier(src) return 'license:test' .. src end
function IsPlayerAceAllowed(src, ace) return TEST.aces[tonumber(src)] == ace end
function DropPlayer() end

-------------------------------------------------------------------------------
-- oxmysql
-------------------------------------------------------------------------------
local function tableName(q)
    return q:match('`(oqv2_%w+)`')
end

MySQL = {
    query = { await = function(q, params)
        local t = tableName(q)
        if q:find('CREATE TABLE') then return {} end
        if q:find('^SELECT') or q:find('SELECT') then
            local rows = TEST.db.rows[t] or {}
            if t == 'oqv2_logs' then return TEST.db.logs end
            local out = {}
            for _, r in pairs(rows) do
                if not params or not params[1] or r.identifier == params[1] then out[#out + 1] = r end
            end
            return out
        end
        return {}
    end },
    prepare = setmetatable({ await = function(q, params)
        local t = tableName(q)
        TEST.db.rows[t] = TEST.db.rows[t] or {}
        if q:find('DELETE') then
            local keep = {}
            for _, r in pairs(TEST.db.rows[t]) do
                if not (r.uid == params[1] or r.identifier == params[1]) then keep[#keep + 1] = r end
            end
            TEST.db.rows[t] = keep
            return 1
        end
        if t == 'oqv2_logs' then
            TEST.db.logs[#TEST.db.logs + 1] = {
                identifier = params[1], name = params[2], action = params[3], detail = params[4], created_at = params[5]
            }
            return 1
        end
        if t == 'oqv2_missions' or t == 'oqv2_locations' or t == 'oqv2_npcs' then
            local row = { uid = params[1], name = params[2], enabled = params[3], data = params[4] }
            for i, r in ipairs(TEST.db.rows[t]) do
                if r.uid == row.uid then TEST.db.rows[t][i] = row return 1 end
            end
            TEST.db.rows[t][#TEST.db.rows[t] + 1] = row
            return 1
        end
        if t == 'oqv2_players' then
            local row = { identifier = params[1], name = params[2], xp = params[3], level = params[4],
                          completed = params[5], data = params[6] }
            for i, r in ipairs(TEST.db.rows[t]) do
                if r.identifier == row.identifier then TEST.db.rows[t][i] = row return 1 end
            end
            TEST.db.rows[t][#TEST.db.rows[t] + 1] = row
            return 1
        end
        if t == 'oqv2_progress' then
            local row = { identifier = params[1], mission_uid = params[2], status = params[3],
                          progress = params[4], completions = params[5], last_completed = params[6] }
            for i, r in ipairs(TEST.db.rows[t]) do
                if r.identifier == row.identifier and r.mission_uid == row.mission_uid then
                    TEST.db.rows[t][i] = row return 1
                end
            end
            TEST.db.rows[t][#TEST.db.rows[t] + 1] = row
            return 1
        end
        if t == 'oqv2_discovered' then
            local row = { identifier = params[1], location_uid = params[2] }
            TEST.db.rows[t][#TEST.db.rows[t] + 1] = row
            return 1
        end
        return 1
    end }, { __call = function(self, q, params) return self.await(q, params) end }),
    single = { await = function(q, params)
        local t = tableName(q)
        for _, r in pairs(TEST.db.rows[t] or {}) do
            if r.identifier == params[1] then return r end
        end
        return nil
    end },
    scalar = { await = function(q)
        local t = tableName(q)
        if q:find('COUNT') then return #(TEST.db.rows[t] or {}) end
        return 0
    end },
    insert = { await = function() return 1 end },
    update = { await = function() return 1 end },
}

-------------------------------------------------------------------------------
-- ox_lib
-------------------------------------------------------------------------------
lib = {
    callback = {
        _registered = {},
        register = function(name, fn) lib.callback._registered[name] = fn end,
    },
    notify = function() end,
    print = { info = function() end, error = function() end },
}

-------------------------------------------------------------------------------
-- exports proxy (ox_inventory / es_extended)
-------------------------------------------------------------------------------
local esxObject = {
    GetPlayerFromId = function(src)
        src = tonumber(src)
        if not TEST.jobs[src] then return nil end
        TEST.money[src] = TEST.money[src] or { money = 5000, bank = 10000, black_money = 0 }
        return {
            identifier = 'char1:test' .. src,
            source = src,
            getName = function() return 'Player' .. src end,
            getJob = function() return TEST.jobs[src] end,
            getGroup = function() return TEST.groups[src] or 'user' end,
            getMoney = function() return TEST.money[src].money end,
            getAccount = function(a) return { money = TEST.money[src][a] or 0 } end,
            addMoney = function(v) TEST.money[src].money = TEST.money[src].money + v end,
            removeMoney = function(v) TEST.money[src].money = TEST.money[src].money - v end,
            addAccountMoney = function(a, v) TEST.money[src][a] = (TEST.money[src][a] or 0) + v end,
            removeAccountMoney = function(a, v) TEST.money[src][a] = (TEST.money[src][a] or 0) - v end,
        }
    end,
}

local oxInventory = {
    Search = function(_, _, src, item)
        return (TEST.inventory[src] or {})[item] or 0
    end,
    CanCarryItem = function() return true end,
    AddItem = function(_, src, item, count)
        TEST.inventory[src] = TEST.inventory[src] or {}
        TEST.inventory[src][item] = (TEST.inventory[src][item] or 0) + count
        return true
    end,
    RemoveItem = function(_, src, item, count)
        TEST.inventory[src] = TEST.inventory[src] or {}
        local have = TEST.inventory[src][item] or 0
        if have < count then return false end
        TEST.inventory[src][item] = have - count
        return true
    end,
}

-- ox_inventory Search is called as exports.ox_inventory:Search(src, 'count', item)
local inventoryProxy = setmetatable({}, {
    __index = function(_, key)
        if key == 'Search' then
            return function(_, src, _, item) return (TEST.inventory[src] or {})[item] or 0 end
        end
        return function(_, ...) return oxInventory[key](nil, ...) end
    end
})

exports = setmetatable({}, {
    __call = function(_, name, fn) TEST.exports = TEST.exports or {}; TEST.exports[name] = fn end,
    __index = function(_, resource)
        if resource == 'es_extended' then
            return { getSharedObject = function() return esxObject end }
        end
        if resource == 'ox_inventory' then
            return inventoryProxy
        end
        return setmetatable({}, { __index = function() return function() return nil end end })
    end
})
