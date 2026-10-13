--[[
    tests/mock_fivem.lua - a small FiveM / QBCore / oxmysql emulator.

    It is good enough to actually execute the server modules and assert on real
    behaviour: a cooperative scheduler, an in-memory SQL engine that understands
    the exact statement shapes this resource emits, and a fake qb-core object.
]]

local Mock = {}

-- ---------------------------------------------------------------------------
-- SCHEDULER
-- ---------------------------------------------------------------------------
local clock = 0
local osOffset = 0
local threads = {}

local realOsTime = os.time
os.time = function(t)
    if t then return realOsTime(t) end
    return realOsTime() + osOffset
end

function Mock.AdvanceOsTime(seconds)
    osOffset = osOffset + (seconds or 0)
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

--- Run the scheduler for `ms` of virtual time.
function Mock.Tick(ms)
    local target = clock + (ms or 0)

    local guard = 0
    while clock <= target do
        guard = guard + 1
        if guard > 20000 then error('scheduler guard tripped', 0) end

        local ran = false
        for _, entry in ipairs(threads) do
            if not entry.dead and entry.wakeAt <= clock then
                resumeThread(entry)
                ran = true
            end
        end

        local alive = {}
        for _, entry in ipairs(threads) do
            if not entry.dead then alive[#alive + 1] = entry end
        end
        threads = alive

        if clock == target then break end

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
-- RESOURCE / EVENTS
-- ---------------------------------------------------------------------------
local resourceName = 'codex_policecreator'
local resourceStates = {
    oxmysql = 'started',
    ['qb-core'] = 'started',
    es_extended = 'missing',
    ox_inventory = 'missing',
    ox_lib = 'missing'
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

function IsDuplicityVersion()
    return true
end

local eventHandlers = {}
local netEventHandlers = {}

function AddEventHandler(name, handler)
    eventHandlers[name] = eventHandlers[name] or {}
    table.insert(eventHandlers[name], handler)
end

function RegisterNetEvent(name, handler)
    if handler then
        netEventHandlers[name] = netEventHandlers[name] or {}
        table.insert(netEventHandlers[name], handler)
    end
    return true
end

RegisterServerEvent = RegisterNetEvent

--- Runs an event with `source` set, like the FiveM runtime does.
function Mock.TriggerServer(name, src, ...)
    local previous = _G.source
    _G.source = src

    for _, handler in ipairs(netEventHandlers[name] or {}) do
        handler(...)
    end
    for _, handler in ipairs(eventHandlers[name] or {}) do
        handler(...)
    end

    _G.source = previous
end

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

function Mock.ClientEvents(name)
    local out = {}
    for _, event in ipairs(Mock.clientEvents) do
        if not name or event.name:find(name, 1, true) then out[#out + 1] = event end
    end
    return out
end

function Mock.ResetClientEvents()
    Mock.clientEvents = {}
end

function TriggerServerEvent(name, ...)
    TriggerEvent(name, ...)
end

Mock.commands = {}

function RegisterCommand(name, handler)
    Mock.commands[name] = handler
end

function IsPlayerAceAllowed()
    return false
end

function Mock.RunCommand(name, src, args)
    local handler = Mock.commands[name]
    if not handler then return false, 'unknown command ' .. tostring(name) end

    local previous = _G.source
    _G.source = src
    local ok, err = pcall(handler, src, args or {})
    _G.source = previous

    return ok, err
end

-- ---------------------------------------------------------------------------
-- NATIVES
-- ---------------------------------------------------------------------------
function joaat(value)
    local hash = 0
    for i = 1, #tostring(value) do
        hash = (hash * 31 + tostring(value):byte(i)) % 4294967296
    end
    return hash
end

local peds = {}
local pedCoords = {}

function GetPlayerPed(src)
    return peds[tonumber(src)] or 0
end

function GetEntityCoords(ped)
    return pedCoords[tonumber(ped)]
end

function Mock.SetCoords(src, x, y, z)
    src = tonumber(src)
    peds[src] = 1000 + src
    pedCoords[peds[src]] = { x = x, y = y, z = z }
    return peds[src]
end

function GiveWeaponToPed() end
function NetworkGetEntityFromNetworkId(netId)
    return tonumber(netId) or 0
end

-- ---------------------------------------------------------------------------
-- FAKE qb-core
-- ---------------------------------------------------------------------------
Mock.players = {}      -- src -> PlayerData
Mock.inventory = {}    -- src -> item -> { amount, metadata }
Mock.money = {}        -- src -> account -> amount
Mock.notifications = {}
Mock.useable = {}

local function playerIdFromPlayer(player)
    return player and player.PlayerData and player.PlayerData.source
end

local fakeQBCore = {
    Shared = { Items = {} },
    Functions = {
        GetPlayer = function(src)
            local data = Mock.players[tonumber(src)]
            if not data then return nil end

            return {
                PlayerData = data,
                Functions = {
                    AddMoney = function(account, amount)
                        Mock.money[src] = Mock.money[src] or {}
                        Mock.money[src][account] = (Mock.money[src][account] or 0) + (tonumber(amount) or 0)
                        data.money[account] = Mock.money[src][account]
                        return true
                    end,
                    RemoveMoney = function(account, amount)
                        Mock.money[src] = Mock.money[src] or {}
                        local balance = Mock.money[src][account] or 0
                        if balance < (tonumber(amount) or 0) then return false end
                        Mock.money[src][account] = balance - (tonumber(amount) or 0)
                        data.money[account] = Mock.money[src][account]
                        return true
                    end,
                    AddItem = function(item, amount)
                        Mock.inventory[src] = Mock.inventory[src] or {}
                        local entry = Mock.inventory[src][item] or { amount = 0 }
                        entry.amount = entry.amount + (tonumber(amount) or 1)
                        Mock.inventory[src][item] = entry
                        return true
                    end,
                    RemoveItem = function(item, amount)
                        local entry = Mock.inventory[src] and Mock.inventory[src][item]
                        if not entry or entry.amount < (tonumber(amount) or 1) then return false end
                        entry.amount = entry.amount - (tonumber(amount) or 1)
                        return true
                    end,
                    GetItemByName = function(item)
                        return Mock.inventory[src] and Mock.inventory[src][item]
                    end,
                    Notify = function(message, kind)
                        table.insert(Mock.notifications, { src = src, message = message, kind = kind })
                    end,
                    SetJob = function(job, grade)
                        data.job = { name = job, grade = { level = tonumber(grade) or 0 } }
                        return true
                    end
                }
            }
        end,
        CreateUseableItem = function(item, handler)
            Mock.useable[item] = handler
        end
    }
}

Mock.registeredExports = {}

exports = setmetatable({}, {
    __index = function(_, key)
        if key == 'qb-core' then
            return { GetCoreObject = function() return fakeQBCore end }
        end
        return {}
    end,
    --- Server side export registration: exports('name', handler)
    __call = function(_, name, handler)
        if type(name) == 'string' then
            Mock.registeredExports[name] = handler
        end
    end
})

--- Registers a playable character.
function Mock.AddPlayer(src, options)
    options = options or {}
    src = tonumber(src)

    Mock.players[src] = {
        source = src,
        citizenid = options.citizenid or ('CIT' .. src),
        charinfo = {
            firstname = options.firstName or ('First' .. src),
            lastname = options.lastName or ('Last' .. src)
        },
        job = {
            name = options.job or 'unemployed',
            grade = { level = tonumber(options.grade) or 0 }
        },
        money = { cash = options.cash or 0, bank = options.bank or 0 }
    }

    Mock.money[src] = { cash = options.cash or 0, bank = options.bank or 0 }
    Mock.inventory[src] = {}

    local playerList = {}
    for id in pairs(Mock.players) do playerList[#playerList + 1] = tostring(id) end
    Mock.playerList = playerList

    Mock.SetCoords(src, options.x or 0.0, options.y or 0.0, options.z or 0.0)
    return Mock.players[src]
end

function Mock.RemovePlayer(src)
    Mock.players[tonumber(src)] = nil
    local playerList = {}
    for id in pairs(Mock.players) do playerList[#playerList + 1] = tostring(id) end
    Mock.playerList = playerList
end

function GetPlayers()
    return Mock.playerList or {}
end

function GetPlayerName(src)
    local data = Mock.players[tonumber(src)]
    if not data then return nil end
    return data.charinfo.firstname .. ' ' .. data.charinfo.lastname
end

function Mock.GiveItem(src, item, amount)
    Mock.inventory[tonumber(src)] = Mock.inventory[tonumber(src)] or {}
    Mock.inventory[tonumber(src)][item] = { amount = tonumber(amount) or 1 }
end

function Mock.ItemCount(src, item)
    local entry = Mock.inventory[tonumber(src)] and Mock.inventory[tonumber(src)][item]
    return entry and entry.amount or 0
end

-- ---------------------------------------------------------------------------
-- IN MEMORY SQL
-- ---------------------------------------------------------------------------
local tables = {}
Mock.tables = tables
Mock.queryLog = {}

local function getTable(name)
    if not tables[name] then
        tables[name] = { rows = {}, auto = 0 }
    end
    return tables[name]
end

local function strip(value)
    return (tostring(value):gsub('^`', ''):gsub('`$', ''))
end

--- Splits a comma separated list while ignoring commas inside parentheses.
local function splitTopLevel(input)
    local parts, depth, current = {}, 0, ''

    for i = 1, #input do
        local char = input:sub(i, i)
        if char == '(' then depth = depth + 1 end
        if char == ')' then depth = depth - 1 end

        if char == ',' and depth == 0 then
            parts[#parts + 1] = current
            current = ''
        else
            current = current .. char
        end
    end

    if current ~= '' then parts[#parts + 1] = current end
    return parts
end

local function toNumberIfPossible(value)
    if type(value) == 'number' then return value end
    if type(value) == 'string' and value:match('^-?%d+$') then return tonumber(value) end
    return value
end

local function compare(actual, operator, expected)
    if operator == 'isnull' then return actual == nil end
    if operator == 'isnotnull' then return actual ~= nil end

    local left = toNumberIfPossible(actual)
    local right = toNumberIfPossible(expected)

    if type(left) == 'number' and type(right) == 'number' then
        if operator == '=' then return left == right end
        if operator == '<>' then return left ~= right end
        if operator == '<' then return left < right end
        if operator == '>' then return left > right end
        if operator == '<=' then return left <= right end
        if operator == '>=' then return left >= right end
    end

    left, right = tostring(actual), tostring(expected)
    if operator == '=' then return left == right end
    if operator == '<>' then return left ~= right end
    if operator == '<' then return left < right end
    if operator == '>' then return left > right end
    if operator == '<=' then return left <= right end
    if operator == '>=' then return left >= right end

    return false
end

local function makeMatcher(whereClause, params, cursor)
    local conditions = {}

    if whereClause and whereClause ~= '' then
        -- split on AND (a bare `$` inside a Lua pattern alternation would be a
        -- literal character, so the split is done by hand)
        local parts = {}
        local remaining = whereClause

        while true do
            local piece, rest = remaining:match('^(.-)%s+AND%s+(.*)$')
            if piece then
                piece = piece:match('^%s*(.-)%s*$')
                if piece ~= '' then parts[#parts + 1] = piece end
                remaining = rest
            else
                remaining = remaining:match('^%s*(.-)%s*$')
                if remaining ~= '' then parts[#parts + 1] = remaining end
                break
            end
        end

        for _, part in ipairs(parts) do
            -- `col` IS NULL / IS NOT NULL
            local column, operator = part:match('^`?([%w_]+)`?%s+(IS%s+NOT%s+NULL)%s*$')
            if column then
                conditions[#conditions + 1] = { column = column, operator = 'isnotnull', value = nil }
            else
                column, operator = part:match('^`?([%w_]+)`?%s+(IS%s+NULL)%s*$')
                if column then
                    conditions[#conditions + 1] = { column = column, operator = 'isnull', value = nil }
                end
            end

            if not column then
                -- `col` = / < / > / <= / >= / <> value
                -- NOTE: Lua patterns have no `|` alternation, so the operators
                -- are tried one by one, longest first.
                local operators = { '<=', '>=', '<>', '<', '>', '=' }

                for _, op in ipairs(operators) do
                    local col, rest = part:match('^`?([%w_]+)`?%s*' .. op .. '%s*(.+)$')
                    if col then
                        local value
                        column, operator = col, op
                        local raw = rest:match('^%s*(.-)%s*$')

                        if raw == '?' then
                            cursor[1] = cursor[1] + 1
                            operator, value = op, params[cursor[1]]
                        elseif raw == 'NULL' then
                            operator, value = op, nil
                        elseif raw:sub(1, 1) == "'" then
                            operator, value = op, raw:sub(2, -2)
                        else
                            operator, value = op, toNumberIfPossible(raw)
                        end

                        conditions[#conditions + 1] = { column = column, operator = operator, value = value }
                        break
                    end
                end
            end
        end
    end

    return function(row)
        for _, condition in ipairs(conditions) do
            if not compare(row[condition.column], condition.operator, condition.value) then
                return false
            end
        end
        return true
    end
end

local function splitStatement(query)
    local upper = query:upper()

    local whereStart = upper:find('%sWHERE%s')
    local orderStart = upper:find('%sORDER%s+BY%s')
    local limitStart = upper:find('%sLIMIT%s')

    local whereEnd = math.min(orderStart or math.huge, limitStart or math.huge, #query + 1)

    return {
        head = whereStart and query:sub(1, whereStart - 1) or query:sub(1, (orderStart or limitStart or (#query + 1)) - 1),
        where = whereStart and query:sub(whereStart + 7, whereEnd - 1) or nil,
        order = orderStart and query:sub(orderStart + 1, (limitStart or (#query + 1)) - 1) or nil,
        limit = limitStart and tonumber(query:sub(limitStart + 7):match('^%s*(%d+)')) or nil
    }
end

local function runSql(query, params)
    query = (query:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
    Mock.queryLog[#Mock.queryLog + 1] = query
    params = params or {}

    if query:upper():find('^CREATE TABLE') then
        local name = query:match('CREATE TABLE IF NOT EXISTS `([%w_]+)`')
        if name then getTable(name) end
        return 0
    end

    if query:upper():find('^INSERT INTO') then
        local table_ = query:match('INSERT INTO `([%w_]+)`')
        local columns = query:match('%(([^%)]+)%)%s*VALUES')
        local values = query:match('VALUES%s*%((.+)%)$')
        if not (table_ and columns and values) then return 0 end

        local target = getTable(table_)
        local names = {}
        for column in columns:gmatch('[^,]+') do names[#names + 1] = strip(column:match('^%s*(.-)%s*$')) end

        local literals = splitTopLevel(values)
        local cursor = { 0 }
        local row = { id = target.auto + 1 }

        for index, name in ipairs(names) do
            local raw = (literals[index] or ''):match('^%s*(.-)%s*$')
            local value

            if raw == '?' then
                cursor[1] = cursor[1] + 1
                value = params[cursor[1]]
            elseif raw:sub(1, 1) == "'" then
                value = raw:sub(2, -2)
            elseif raw == 'NULL' then
                value = nil
            else
                value = toNumberIfPossible(raw)
            end

            row[name] = value
        end

        target.auto = target.auto + 1
        target.rows[#target.rows + 1] = row
        return target.auto
    end

    local parts = splitStatement(query)

    if query:upper():find('^SELECT') then
        local table_ = parts.head:match('FROM `([%w_]+)`')
        if not table_ then return {} end

        local target = getTable(table_)
        local cursor = { 0 }
        local matches = makeMatcher(parts.where, params, cursor)

        local rows = {}
        for _, row in ipairs(target.rows) do
            if matches(row) then rows[#rows + 1] = row end
        end

        if parts.order then
            local column, direction = parts.order:match('ORDER BY `?([%w_]+)`?%s*(%a*)')
            local descending = tostring(direction):upper() == 'DESC'

            table.sort(rows, function(a, b)
                local left = a[column]
                local right = b[column]
                if left == nil then return false end
                if right == nil then return true end
                if descending then return left > right end
                return left < right
            end)
        end

        if parts.limit then
            local limited = {}
            for index = 1, math.min(parts.limit, #rows) do limited[index] = rows[index] end
            rows = limited
        end

        if parts.head:find('COUNT%(%*%)') then
            return { { c = #rows } }
        end

        -- return copies so callers cannot mutate the store accidentally
        local out = {}
        for index, row in ipairs(rows) do
            local copy = {}
            for key, value in pairs(row) do copy[key] = value end
            out[index] = copy
        end
        return out
    end

    if query:upper():find('^UPDATE') then
        local table_ = parts.head:match('UPDATE `([%w_]+)`')
        if not table_ then return 0 end

        local setClause = parts.head:match('SET%s+(.+)$')
        if not setClause then return 0 end

        local assignments = splitTopLevel(setClause)
        local cursor = { 0 }
        local updates = {}

        for _, assignment in ipairs(assignments) do
            local column, rawValue = assignment:match('^%s*`?([%w_]+)`?%s*=%s*(.-)%s*$')
            if column then
                local value
                if rawValue == '?' then
                    cursor[1] = cursor[1] + 1
                    value = params[cursor[1]]
                elseif rawValue == 'NULL' then
                    value = nil
                elseif rawValue:sub(1, 1) == "'" then
                    value = rawValue:sub(2, -2)
                else
                    value = toNumberIfPossible(rawValue)
                end
                updates[column] = value
            end
        end

        local matches = makeMatcher(parts.where, params, cursor)
        local affected = 0

        for _, row in ipairs(getTable(table_).rows) do
            if matches(row) then
                for column, value in pairs(updates) do
                    row[column] = value
                end
                affected = affected + 1
            end
        end

        return affected
    end

    if query:upper():find('^DELETE FROM') then
        local table_ = parts.head:match('DELETE FROM `([%w_]+)`')
        if not table_ then return 0 end

        local target = getTable(table_)
        local matches = makeMatcher(parts.where, params, { 0 })

        local kept, affected = {}, 0
        for _, row in ipairs(target.rows) do
            if matches(row) then
                affected = affected + 1
            else
                kept[#kept + 1] = row
            end
        end

        target.rows = kept
        return affected
    end

    error('mock SQL: unsupported statement: ' .. query, 0)
end

MySQL = {
    query = { await = function(query, params)
        local result = runSql(query, params)
        return type(result) == 'table' and result or {}
    end },
    insert = { await = function(query, params)
        return runSql(query, params)
    end },
    update = { await = function(query, params)
        return runSql(query, params)
    end },
    execute = { await = function(query, params)
        return runSql(query, params)
    end }
}

function Mock.Table(name)
    return getTable(name).rows
end

function Mock.RowCount(name)
    return #getTable(name).rows
end

function Mock.ResetDatabase()
    for name in pairs(tables) do
        tables[name] = { rows = {}, auto = 0 }
    end
    Mock.queryLog = {}
end

-- ---------------------------------------------------------------------------
-- JSON / VECTORS
-- ---------------------------------------------------------------------------
json = {
    encode = function(value)
        if type(value) ~= 'table' then return tostring(value) end
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = ('"%s":%s'):format(tostring(key), type(item) == 'table' and '{}' or tostring(item))
        end
        return '{' .. table.concat(parts, ',') .. '}'
    end,
    decode = function() return {} end
}

local vectorMeta = {
    __index = function(self, key)
        if key == 'x' then return self[1] end
        if key == 'y' then return self[2] end
        if key == 'z' then return self[3] end
        if key == 'w' then return self[4] end
        return rawget(self, key)
    end,
    __sub = function(a, b)
        return vector3(a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0))
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

return Mock
