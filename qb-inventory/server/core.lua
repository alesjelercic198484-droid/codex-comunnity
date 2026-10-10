--[============================================================================[
    CodeX Roleplay Inventory - core access layer

    Loaded before server/main.lua. It resolves the qb-core object once and wraps
    the few globals this resource needs (players, notify, permissions, SQL) so
    the rest of the code never has to nil-check the framework.

    Nothing here is monkey patched. Modern qb-core intentionally has NO
    `Player.Functions.AddItem` - every script is expected to talk to the
    inventory through `exports['qb-inventory']`. That export surface is what
    makes this a drop-in replacement; see server/main.lua.
]============================================================================]

Core = {}
Core.Version = '1.0.0'

local QBCore = nil
local sqlAvailable = false
local sqlWarned = false

-- ---------------------------------------------------------------------------
-- Framework
-- ---------------------------------------------------------------------------
local function resolveCore()
    local ok, object = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)

    if ok and type(object) == 'table' and type(object.Functions) == 'table' then
        return object
    end

    if type(_G.QBCore) == 'table' and type(_G.QBCore.Functions) == 'table' then
        return _G.QBCore
    end

    return nil
end

QBCore = resolveCore()

if not QBCore then
    -- qb-core is a hard dependency, but a slow `ensure` order happens. Retry a
    -- few times before giving up so the resource does not silently do nothing.
    for _ = 1, 25 do
        Wait(200)
        QBCore = resolveCore()
        if QBCore then break end
    end
end

if QBCore then
    print('^5[qb-inventory]^7 CodeX Roleplay Inventory ' .. Core.Version ..
          ' started - qb-core detected, drop-in replacement active.')
else
    print('^1[qb-inventory]^7 qb-core was not found. Start qb-core BEFORE ' ..
          'qb-inventory and make sure this folder is named "qb-inventory".')
end

function Core.Object()
    return QBCore
end

function Core.Ready()
    return QBCore ~= nil
end

--- @param source number|string
function Core.GetPlayer(source)
    if not QBCore or source == nil then return nil end

    local ok, player = pcall(function()
        return QBCore.Functions.GetPlayer(source)
    end)

    if ok and player then return player end
    return nil
end

function Core.SharedItems()
    if QBCore and QBCore.Shared and type(QBCore.Shared.Items) == 'table' then
        return QBCore.Shared.Items
    end
    return {}
end

--- @param name string
function Core.SharedItem(name)
    if type(name) ~= 'string' then return nil end
    return Core.SharedItems()[name:lower()]
end

function Core.CreateCallback(name, fn)
    if not QBCore then return false end

    local ok = pcall(function()
        QBCore.Functions.CreateCallback(name, fn)
    end)

    return ok
end

function Core.Players()
    if not QBCore then return {} end

    local ok, list = pcall(function()
        return QBCore.Functions.GetPlayers()
    end)

    if ok and type(list) == 'table' then return list end
    return {}
end

function Core.Notify(source, message, kind, length)
    if not QBCore then return end

    if type(message) ~= 'string' or message == '' then return end

    pcall(function()
        QBCore.Functions.Notify(source, message, kind or 'primary', length or 5000)
    end)
end

--- Money. `account` is 'cash', 'bank' or any custom qb-core account.
function Core.GetMoney(source, account)
    local player = Core.GetPlayer(source)
    if not player then return 0 end

    local money = player.PlayerData.money or {}
    return tonumber(money[account or 'cash']) or 0
end

function Core.RemoveMoney(source, account, amount, reason)
    local player = Core.GetPlayer(source)
    if not player or not player.Functions or not player.Functions.RemoveMoney then
        return false
    end

    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    if Core.GetMoney(source, account) < amount then return false end

    local ok = pcall(function()
        player.Functions.RemoveMoney(account or 'cash', amount, reason or 'purchase')
    end)

    return ok
end

--- Pushes the (possibly modified) PlayerData back to the client.
function Core.SetPlayerData(source, key, value)
    local player = Core.GetPlayer(source)
    if not player then return false end

    if player.Functions and player.Functions.SetPlayerData then
        local ok = pcall(function()
            player.Functions.SetPlayerData(key, value)
        end)
        return ok
    end

    return false
end

function Core.HasPermission(source, ace)
    if not ace or ace == '' then return true end
    if source == nil then return false end

    local ok, allowed = pcall(function()
        return IsPlayerAceAllowed(source, ace)
    end)

    return ok and allowed == true or allowed == 1
end

-- ---------------------------------------------------------------------------
-- SQL (optional)
--
-- Stashes / trunks / gloveboxes are persisted when oxmysql is running and the
-- `codex_inventories` table exists. If either is missing the resource keeps
-- everything in memory and prints ONE warning - it never hard fails, so the
-- inventory is usable straight after a copy/paste install.
-- ---------------------------------------------------------------------------
local function checkSql()
    if MySQL and MySQL.prepare and MySQL.prepare.await then
        sqlAvailable = true
        return true
    end
    return false
end

checkSql()

local function warnSqlOnce(err)
    if sqlWarned then return end
    sqlWarned = true
    print(('^3[qb-inventory]^7 SQL persistence disabled (%s). Install ' ..
           'install/qb_inventory_codex.sql for persistent stashes - the ' ..
           'inventory still works, stashes just reset on restart.'):format(tostring(err)))
end

function Core.SqlEnabled()
    return sqlAvailable
end

function Core.SqlQuery(query, params)
    if not sqlAvailable then return nil end

    local ok, result = pcall(function()
        return MySQL.prepare.await(query, params or {})
    end)

    if not ok then
        warnSqlOnce(result)
        sqlAvailable = false
        return nil
    end

    return result
end

function Core.SqlExecute(query, params)
    if not sqlAvailable then return false end

    local ok, result = pcall(function()
        return MySQL.prepare.await(query, params or {})
    end)

    if not ok then
        warnSqlOnce(result)
        sqlAvailable = false
        return false
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Misc helpers
-- ---------------------------------------------------------------------------
function Core.PlayerName(source)
    local ok, name = pcall(function()
        return GetPlayerName(source)
    end)

    if ok and type(name) == 'string' then return name end
    return tostring(source)
end

function Core.Distance(a, b)
    if not a or not b then return 9999.0 end

    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Core.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor((tonumber(value) or 0) * mult + 0.5) / mult
end

--- Deep copies a table (items carry an `info` sub table that must not be shared
--- between the player inventory and a stash).
function Core.DeepCopy(value)
    if type(value) ~= 'table' then return value end

    local copy = {}

    for k, v in pairs(value) do
        copy[k] = Core.DeepCopy(v)
    end

    return copy
end

function Core.Log(message)
    print(('^5[qb-inventory]^7 %s'):format(tostring(message)))
end

function Core.Debug(message)
    if Config and Config.Debug then
        print(('^6[qb-inventory:debug]^7 %s'):format(tostring(message)))
    end
end
