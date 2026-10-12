--[[
    Minimal FiveM / QBCore / oxmysql emulator for codex_wallet tests.

    Implements just enough of the runtime (scheduler, events, commands, NUI,
    players, inventory, money, database) to execute client/main.lua and
    server/main.lua and assert on what happens.
]]

local Mock = {}

-- ---------------------------------------------------------------------------
-- Virtual clock (also replaces os.clock so rate limiting is testable)
-- ---------------------------------------------------------------------------
Mock.clock = 0

local realOsClock = os.clock
os.clock = function()
    return Mock.clock / 1000.0
end

function Mock.tick(ms)
    Mock.clock = Mock.clock + (tonumber(ms) or 0)
end

-- ---------------------------------------------------------------------------
-- JSON (tiny, enough for the payloads used by the resource)
-- ---------------------------------------------------------------------------
local Json = {}

local function isArray(tbl)
    local count = 0
    for key in pairs(tbl) do
        if type(key) ~= 'number' then
            return false
        end
        count = count + 1
    end
    for index = 1, count do
        if tbl[index] == nil then
            return false
        end
    end
    return true, count
end

local function encodeValue(value)
    local valueType = type(value)

    if value == nil then
        return 'null'
    end

    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return 'null'
        end
        return string.format('%.14g', value)
    end

    if valueType == 'boolean' then
        return value and 'true' or 'false'
    end

    if valueType == 'string' then
        local escaped = value
            :gsub('\\', '\\\\')
            :gsub('"', '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    end

    if valueType == 'table' then
        local array, count = isArray(value)
        if array and count > 0 then
            local parts = {}
            for index = 1, count do
                parts[#parts + 1] = encodeValue(value[index])
            end
            return '[' .. table.concat(parts, ',') .. ']'
        end

        if array and count == 0 then
            return '{}'
        end

        local parts = {}
        for key, entry in pairs(value) do
            parts[#parts + 1] = '"' .. tostring(key) .. '":' .. encodeValue(entry)
        end
        table.sort(parts)
        return '{' .. table.concat(parts, ',') .. '}'
    end

    return 'null'
end

function Json.encode(value)
    return encodeValue(value)
end

local function skipWhitespace(text, index)
    local _, endIndex = text:find('^[ \t\r\n]*', index)
    return endIndex + 1
end

local decodeValue

local function decodeString(text, index)
    local result = {}
    index = index + 1
    while index <= #text do
        local char = text:sub(index, index)
        if char == '"' then
            return table.concat(result), index + 1
        elseif char == '\\' then
            local nextChar = text:sub(index + 1, index + 1)
            local map = { n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
            result[#result + 1] = map[nextChar] or nextChar
            index = index + 2
        else
            result[#result + 1] = char
            index = index + 1
        end
    end
    error('unterminated string')
end

local function decodeNumber(text, index)
    local numStr = text:match('^-?%d+%.?%d*[eE]?[+-]?%d*', index)
    return tonumber(numStr), index + #numStr
end

decodeValue = function(text, index)
    index = skipWhitespace(text, index)
    local char = text:sub(index, index)

    if char == '{' then
        local result = {}
        index = skipWhitespace(text, index + 1)
        if text:sub(index, index) == '}' then
            return result, index + 1
        end
        while true do
            index = skipWhitespace(text, index)
            local key
            key, index = decodeString(text, index)
            index = skipWhitespace(text, index)
            assert(text:sub(index, index) == ':', 'expected : in json object')
            local value
            value, index = decodeValue(text, index + 1)
            result[key] = value
            index = skipWhitespace(text, index)
            local sep = text:sub(index, index)
            if sep == '}' then
                return result, index + 1
            end
            assert(sep == ',', 'expected , in json object')
            index = index + 1
        end
    end

    if char == '[' then
        local result = {}
        index = skipWhitespace(text, index + 1)
        if text:sub(index, index) == ']' then
            return result, index + 1
        end
        while true do
            local value
            value, index = decodeValue(text, index)
            result[#result + 1] = value
            index = skipWhitespace(text, index)
            local sep = text:sub(index, index)
            if sep == ']' then
                return result, index + 1
            end
            assert(sep == ',', 'expected , in json array')
            index = index + 1
        end
    end

    if char == '"' then
        return decodeString(text, index)
    end

    if text:sub(index, index + 3) == 'true' then
        return true, index + 4
    end

    if text:sub(index, index + 4) == 'false' then
        return false, index + 5
    end

    if text:sub(index, index + 3) == 'null' then
        return nil, index + 4
    end

    return decodeNumber(text, index)
end

function Json.decode(text)
    local value = decodeValue(text, 1)
    return value
end

json = Json

-- ---------------------------------------------------------------------------
-- Global mock state
-- ---------------------------------------------------------------------------
Mock.files = {}
Mock.convars = {}
Mock.clientEvents = {}
Mock.serverEvents = {}
Mock.netHandlers = {}
Mock.eventHandlers = {}
Mock.commands = {}
Mock.useable = {}
Mock.nui = {}
Mock.keyMappings = {}
Mock.httpRequests = {}
Mock.exports = {}
Mock.db = {}
Mock.players = {}
Mock.playerOrder = {}
Mock.permissions = {}
Mock.peds = {}
Mock.notifications = {}
Mock.resourceState = { ox_inventory = 'missing', oxmysql = 'started', ['qb-core'] = 'started' }

-- ---------------------------------------------------------------------------
-- Scheduler
-- ---------------------------------------------------------------------------
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
        entry.wakeAt = Mock.clock + (tonumber(result) or 0)
    end
end

function Mock.spawn(fn, label)
    local entry = { co = coroutine.create(fn), wakeAt = Mock.clock, label = label }
    threads[#threads + 1] = entry
    return entry
end

function Mock.runReady()
    local guard = 0

    while true do
        guard = guard + 1
        if guard > 10000 then
            error('scheduler runaway')
        end

        local ran = false
        for _, entry in ipairs(threads) do
            if not entry.dead and entry.wakeAt <= Mock.clock then
                ran = true
                resumeThread(entry)
            end
        end

        if not ran then
            return
        end
    end
end

function Mock.advance(ms)
    Mock.tick(ms)
    Mock.runReady()
end

function CreateThread(fn)
    Mock.spawn(fn, 'thread')
    Mock.runReady()
end

function Wait(ms)
    ms = tonumber(ms) or 0
    -- Wait(0) still resumes on the *next* frame in FiveM; keep it from
    -- spinning forever inside the cooperative scheduler.
    if ms < 1 then
        ms = 1
    end

    if coroutine.isyieldable() then
        coroutine.yield(ms)
    end

    Mock.tick(ms)
    Mock.runReady()
end

function SetTimeout(ms, fn)
    Mock.spawn(function()
        Wait(ms)
        fn()
    end, 'timeout')
end

-- ---------------------------------------------------------------------------
-- FiveM core
-- ---------------------------------------------------------------------------
function GetCurrentResourceName()
    return 'codex_wallet'
end

function GetResourceState(name)
    return Mock.resourceState[name] or 'missing'
end

function GetConvar(name, default)
    if Mock.convars[name] ~= nil then
        return Mock.convars[name]
    end
    return default
end

function LoadResourceFile(resource, path)
    return Mock.files[path]
end

function SaveResourceFile(resource, path, content)
    Mock.files[path] = content
    return true
end

function PerformHttpRequest(url, cb, method, body, headers)
    Mock.httpRequests[#Mock.httpRequests + 1] = {
        url = url,
        method = method,
        body = body,
        headers = headers
    }
    if cb then
        cb(200, '{}', {})
    end
end

function RegisterNetEvent(name, handler)
    if handler then
        Mock.netHandlers[name] = handler
    end
end

function AddEventHandler(name, handler)
    Mock.eventHandlers[name] = Mock.eventHandlers[name] or {}
    table.insert(Mock.eventHandlers[name], handler)
end

function TriggerEvent(name, ...)
    local args = table.pack(...)

    if Mock.netHandlers[name] then
        local handler = Mock.netHandlers[name]
        handler(table.unpack(args, 1, args.n))
    end

    for _, handler in ipairs(Mock.eventHandlers[name] or {}) do
        handler(table.unpack(args, 1, args.n))
    end
end

function TriggerClientEvent(name, target, ...)
    Mock.clientEvents[#Mock.clientEvents + 1] = {
        name = name,
        target = target,
        args = table.pack(...)
    }

    -- QBCore notifications arrive as client events; surface them for asserts.
    if name == 'QBCore:Notify' then
        Mock.notifications[#Mock.notifications + 1] = {
            src = target,
            message = select(1, ...),
            kind = select(2, ...)
        }
    end
end

function TriggerServerEvent(name, ...)
    Mock.serverEvents[#Mock.serverEvents + 1] = {
        name = name,
        args = table.pack(...)
    }
end

function RegisterCommand(name, handler, restricted)
    Mock.commands[name] = handler
end

function RegisterKeyMapping(command, description, defaultKey, defaultMapping)
    Mock.keyMappings[#Mock.keyMappings + 1] = {
        command = command,
        description = description,
        defaultKey = defaultMapping or defaultKey
    }
end

function RegisterNUICallback(name, handler)
    Mock.nui[name] = handler
end

function SetNuiFocus(focus, cursor)
    Mock.nuiFocus = { focus = focus, cursor = cursor }
end

function SendNUIMessage(message)
    Mock.nuiMessages[#Mock.nuiMessages + 1] = message
end

Mock.nuiMessages = {}

function IsControlJustPressed()
    return false
end

function BeginTextCommandThefeedPost() end
function AddTextComponentSubstringPlayerName() end
function EndTextCommandThefeedPostTicker() end

function IsPlayerAceAllowed(src, ace)
    local perms = Mock.permissions[src]
    if perms and perms[ace] then
        return true
    end
    return false
end

function GetPlayerPed(src)
    return (tonumber(src) or 0) * 1000
end

function GetEntityCoords(ped)
    return Mock.peds[ped] or { x = 0.0, y = 0.0, z = 0.0 }
end

-- `source` is a global in FiveM event contexts.
source = 0

-- ---------------------------------------------------------------------------
-- Test helpers for events
-- ---------------------------------------------------------------------------
function Mock.netTrigger(src, name, ...)
    local previous = source
    source = src
    local handler = Mock.netHandlers[name]

    if not handler then
        source = previous
        error('no net handler for ' .. tostring(name))
    end

    local args = table.pack(...)
    handler(table.unpack(args, 1, args.n))
    source = previous
end

function Mock.fire(name, ...)
    local previous = source
    source = 0
    TriggerEvent(name, ...)
    source = previous
end

function Mock.clientTrigger(name, ...)
    local handler = Mock.netHandlers[name]
    if handler then
        local args = table.pack(...)
        handler(table.unpack(args, 1, args.n))
    end

    for _, stored in ipairs(Mock.eventHandlers[name] or {}) do
        local args = table.pack(...)
        stored(table.unpack(args, 1, args.n))
    end
end

function Mock.nuiCall(name, data)
    local handler = Mock.nui[name]
    assert(handler, 'no nui callback ' .. tostring(name))

    local response
    handler(data, function(payload)
        response = payload
    end)

    return response
end

function Mock.lastClientEvent(nameFilter)
    for index = #Mock.clientEvents, 1, -1 do
        local event = Mock.clientEvents[index]
        if not nameFilter or event.name:find(nameFilter, 1, true) then
            return event
        end
    end
    return nil
end

function Mock.resetTraces()
    Mock.clientEvents = {}
    Mock.serverEvents = {}
    Mock.nuiMessages = {}
    Mock.httpRequests = {}
    Mock.notifications = {}
end

-- ---------------------------------------------------------------------------
-- oxmysql mock
-- ---------------------------------------------------------------------------
local function decodeItemsField(raw)
    if type(raw) == 'table' then
        return raw
    end
    if type(raw) ~= 'string' or raw == '' then
        return {}
    end
    local ok, decoded = pcall(Json.decode, raw)
    if ok and type(decoded) == 'table' then
        return decoded
    end
    return {}
end

MySQL = {
    query = {
        await = function(sql)
            -- CREATE TABLE etc. is a no-op in the mock.
            return {}
        end
    },
    single = {
        await = function(sql, params)
            local serial = params and params[1]
            local row = Mock.db[serial]
            if not row then
                return nil
            end
            return {
                serial = row.serial,
                cash = row.cash,
                items = row.items,
                owner = row.owner
            }
        end
    },
    insert = {
        await = function(sql, params)
            local serial = params[1]
            Mock.db[serial] = {
                serial = serial,
                cash = params[2],
                items = params[3],
                owner = params[4]
            }
            return 1
        end
    },
    update = {
        await = function(sql, params)
            local serial = params[4]
            local row = Mock.db[serial]
            if not row then
                return 0
            end
            row.cash = params[1]
            row.items = params[2]
            row.owner = params[3]
            return 1
        end
    }
}

-- ---------------------------------------------------------------------------
-- QBCore mock
-- ---------------------------------------------------------------------------
local function makePlayer(src, options)
    options = options or {}

    local items = options.items or {}
    local nextSlot = 1
    for slot, item in pairs(items) do
        item.slot = item.slot or slot
        item.amount = item.amount or 1
        if type(slot) == 'number' and slot >= nextSlot then
            nextSlot = slot + 1
        end
    end

    local money = {
        cash = options.cash or 0,
        bank = options.bank or 0
    }

    local player = {}
    local playerData = {
        citizenid = options.citizenid or ('CID' .. tostring(src)),
        charinfo = options.charinfo or {
            firstname = 'John',
            lastname = 'Doe',
            birthdate = '1990-01-01',
            gender = 0,
            nationality = 'San Andreas'
        },
        job = options.job or { name = 'civilian', label = 'Civilian' },
        items = items,
        money = money
    }

    local function findSlot(name, slot)
        if slot then
            local item = items[slot]
            if item and item.name == name then
                return slot, item
            end
            return nil, nil
        end

        for index, item in pairs(items) do
            if item.name == name then
                return index, item
            end
        end
        return nil, nil
    end

    player.PlayerData = playerData
    player.Functions = {
        GetMoney = function(account)
            return money[account] or 0
        end,
        AddMoney = function(account, amount, reason)
            amount = math.floor(tonumber(amount) or 0)
            if amount <= 0 then
                return false
            end
            money[account] = (money[account] or 0) + amount
            return true
        end,
        RemoveMoney = function(account, amount, reason)
            amount = math.floor(tonumber(amount) or 0)
            if amount <= 0 or (money[account] or 0) < amount then
                return false
            end
            money[account] = money[account] - amount
            return true
        end,
        AddItem = function(name, count, slot, info)
            count = tonumber(count) or 1
            if count <= 0 then
                return false
            end

            if slot and items[slot] then
                return false
            end

            local targetSlot = slot
            if not targetSlot then
                targetSlot = nextSlot
                nextSlot = nextSlot + 1
            end

            items[targetSlot] = {
                name = name,
                amount = count,
                slot = targetSlot,
                info = info
            }

            return true
        end,
        RemoveItem = function(name, count, slot)
            count = tonumber(count) or 1

            local index, item = findSlot(name, slot)
            if not item then
                return false
            end

            local current = item.amount or 1
            if current < count then
                return false
            end

            if current == count then
                items[index] = nil
            else
                item.amount = current - count
            end

            return true
        end
    }

    Mock.players[src] = player
    Mock.peds[GetPlayerPed(src)] = options.coords or { x = 0.0, y = 0.0, z = 0.0 }

    local found = false
    for _, id in ipairs(Mock.playerOrder) do
        if id == src then
            found = true
            break
        end
    end
    if not found then
        Mock.playerOrder[#Mock.playerOrder + 1] = src
    end

    return player
end

Mock.makePlayer = makePlayer

function Mock.removePlayer(src)
    Mock.players[src] = nil
    for index, id in ipairs(Mock.playerOrder) do
        if id == src then
            table.remove(Mock.playerOrder, index)
            break
        end
    end
end

function Mock.getItem(src, name)
    local player = Mock.players[src]
    if not player then
        return nil
    end

    for _, item in pairs(player.PlayerData.items) do
        if item.name == name then
            return item
        end
    end
    return nil
end

function Mock.countItems(src, name)
    local player = Mock.players[src]
    if not player then
        return 0
    end

    local total = 0
    for _, item in pairs(player.PlayerData.items) do
        if item.name == name then
            total = total + (item.amount or 1)
        end
    end
    return total
end

local QBCore = {
    Shared = {
        Items = {
            codex_wallet = { name = 'codex_wallet', label = 'CodeX Wallet' },
            id_card = { name = 'id_card', label = 'ID Card' },
            driver_license = { name = 'driver_license', label = "Driver's License" },
            weaponlicense = { name = 'weaponlicense', label = 'Weapon License' }
        }
    },
    Functions = {
        GetPlayer = function(src)
            return Mock.players[src]
        end,
        GetPlayers = function()
            local result = {}
            for _, id in ipairs(Mock.playerOrder) do
                if Mock.players[id] then
                    result[#result + 1] = id
                end
            end
            return result
        end,
        CreateUseableItem = function(name, handler)
            Mock.useable[name] = handler
        end,
        HasPermission = function(src, permission)
            local perms = Mock.permissions[src]
            return perms ~= nil and perms[permission] == true
        end,
        Notify = function(src, message, kind)
            Mock.notifications[#Mock.notifications + 1] = {
                src = src,
                message = message,
                kind = kind
            }
        end
    }
}

Mock.qbcore = QBCore

Mock.exportedResources = {
    ['qb-core'] = {
        GetCoreObject = function()
            return QBCore
        end
    }
}

exports = setmetatable({}, {
    __index = function(_, resourceName)
        return Mock.exportedResources[resourceName] or {}
    end,
    __call = function(_, name, handler)
        Mock.exports[name] = handler
    end
})

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------
function Mock.giveItem(src, name, info, slotOverride)
    local player = Mock.players[src]
    assert(player, 'no player ' .. tostring(src))

    local targetSlot = slotOverride
    if not targetSlot then
        local nextSlot = 1
        for slot in pairs(player.PlayerData.items) do
            if type(slot) == 'number' and slot >= nextSlot then
                nextSlot = slot + 1
            end
        end
        targetSlot = nextSlot
    end

    player.PlayerData.items[targetSlot] = {
        name = name,
        amount = 1,
        slot = targetSlot,
        info = info
    }

    return player.PlayerData.items[targetSlot]
end

function Mock.log(msg)
    io.write(msg .. '\n')
end

return Mock
