--[[
    CodeX Wallet - persistence layer

    Wallet contents live in the `codex_wallets` table, keyed by the wallet
    serial stored in the item metadata. This makes the contents survive item
    trades, server restarts and inventory resource swaps.

    When oxmysql is not available (unit tests / misconfiguration) the module
    transparently falls back to an in-memory store so the resource still runs
    (with a loud warning on the server).
]]

Storage = {}

local memory = {}
local useDatabase = nil
local initialised = false

local function dbReady()
    return type(MySQL) == 'table'
        and type(MySQL.single) == 'table'
        and type(MySQL.single.await) == 'function'
        and type(MySQL.query) == 'table'
        and type(MySQL.query.await) == 'function'
        and type(MySQL.update) == 'table'
        and type(MySQL.update.await) == 'function'
        and type(MySQL.insert) == 'table'
        and type(MySQL.insert.await) == 'function'
end

local function detectDatabase()
    if useDatabase == nil then
        useDatabase = dbReady()
    end
    return useDatabase
end

function Storage.IsUsingDatabase()
    return detectDatabase() == true
end

local function ensureTable()
    if initialised then
        return
    end
    initialised = true

    if not detectDatabase() then
        print('^3[codex_wallet] oxmysql not found - wallet data will NOT persist across restarts (memory mode).^0')
        return
    end

    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `codex_wallets` (
                `serial` VARCHAR(32) NOT NULL,
                `cash` BIGINT UNSIGNED NOT NULL DEFAULT 0,
                `items` LONGTEXT NULL,
                `owner` VARCHAR(64) NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`serial`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
    end)

    if not ok then
        print(('^1[codex_wallet] Failed to create the codex_wallets table: %s^0'):format(tostring(err)))
        useDatabase = false
    end
end

local function decodeItems(raw)
    if not raw or raw == '' then
        return {}
    end

    if type(raw) == 'table' then
        return raw
    end

    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then
        return decoded
    end

    return {}
end

local function normalize(row)
    if not row then
        return nil
    end

    return {
        serial = tostring(row.serial),
        cash = math.max(0, math.floor(tonumber(row.cash) or 0)),
        items = decodeItems(row.items),
        owner = row.owner
    }
end

--- Load (or create) a wallet record.
function Storage.Load(serial)
    ensureTable()
    serial = tostring(serial or '')

    if serial == '' then
        return nil
    end

    if detectDatabase() then
        local row = MySQL.single.await('SELECT `serial`, `cash`, `items`, `owner` FROM `codex_wallets` WHERE `serial` = ? LIMIT 1', { serial })
        return normalize(row)
    end

    local entry = memory[serial]
    if not entry then
        return nil
    end

    return {
        serial = entry.serial,
        cash = entry.cash,
        items = decodeItems(entry.items),
        owner = entry.owner
    }
end

--- Create a wallet record. Returns the normalized record or nil on conflict.
function Storage.Create(serial, owner)
    ensureTable()
    serial = tostring(serial or '')

    if serial == '' then
        return nil
    end

    local record = {
        serial = serial,
        cash = 0,
        items = {},
        owner = owner
    }

    if detectDatabase() then
        local existing = MySQL.single.await('SELECT `serial` FROM `codex_wallets` WHERE `serial` = ? LIMIT 1', { serial })
        if existing then
            return nil
        end

        MySQL.insert.await('INSERT INTO `codex_wallets` (`serial`, `cash`, `items`, `owner`) VALUES (?, ?, ?, ?)', {
            serial,
            0,
            json.encode({}),
            owner
        })

        return record
    end

    if memory[serial] then
        return nil
    end

    memory[serial] = {
        serial = serial,
        cash = 0,
        items = {},
        owner = owner
    }

    return {
        serial = serial,
        cash = 0,
        items = {},
        owner = owner
    }
end

--- Persist a wallet record. Returns true on success.
function Storage.Save(record)
    ensureTable()

    if not record or not record.serial or record.serial == '' then
        return false
    end

    record.cash = math.max(0, math.floor(tonumber(record.cash) or 0))
    record.items = type(record.items) == 'table' and record.items or {}

    if detectDatabase() then
        local ok, err = pcall(function()
            MySQL.update.await('UPDATE `codex_wallets` SET `cash` = ?, `items` = ?, `owner` = ? WHERE `serial` = ?', {
                record.cash,
                json.encode(record.items),
                record.owner,
                record.serial
            })
        end)

        if not ok then
            if Logger then
                Logger.Error('storage', 'Failed to save wallet', { serial = record.serial, error = tostring(err) })
            end
            return false
        end

        return true
    end

    memory[record.serial] = {
        serial = record.serial,
        cash = record.cash,
        items = record.items,
        owner = record.owner
    }

    return true
end

--- Test helper: wipe the in-memory store.
function Storage.ResetMemory()
    memory = {}
end

--- Test helper: force memory/database mode.
function Storage.SetDatabaseMode(enabled)
    useDatabase = enabled == true
    initialised = true
end

return Storage
