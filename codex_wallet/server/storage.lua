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
local memoryWhitelist = {}
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

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `codex_wallet_whitelist` (
                `name` VARCHAR(64) NOT NULL,
                `label` VARCHAR(128) NOT NULL DEFAULT '',
                `weight` INT UNSIGNED NOT NULL DEFAULT 50,
                `presentable` TINYINT(1) NOT NULL DEFAULT 1,
                `enabled` TINYINT(1) NOT NULL DEFAULT 1,
                `source` VARCHAR(16) NOT NULL DEFAULT 'admin',
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`name`)
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
    memoryWhitelist = {}
end

-- ---------------------------------------------------------------------------
-- Whitelist (items allowed inside the wallet, managed via the WAdmin panel)
-- ---------------------------------------------------------------------------

local function normalizeWhitelistRow(row)
    if not row then
        return nil
    end

    return {
        name = tostring(row.name),
        label = tostring(row.label or ''),
        weight = math.max(1, math.floor(tonumber(row.weight) or 50)),
        presentable = tonumber(row.presentable) == 1 or row.presentable == true,
        enabled = tonumber(row.enabled) == 1 or row.enabled == true,
        source = tostring(row.source or 'admin')
    }
end

--- Load every whitelist row (including disabled ones).
function Storage.LoadWhitelist()
    ensureTable()

    if detectDatabase() then
        local rows = MySQL.query.await('SELECT `name`, `label`, `weight`, `presentable`, `enabled`, `source` FROM `codex_wallet_whitelist`') or {}
        local result = {}
        for _, row in ipairs(rows) do
            result[#result + 1] = normalizeWhitelistRow(row)
        end
        return result
    end

    local result = {}
    for _, entry in pairs(memoryWhitelist) do
        result[#result + 1] = normalizeWhitelistRow(entry)
    end
    table.sort(result, function(a, b)
        return a.name < b.name
    end)
    return result
end

--- Insert or replace one whitelist entry.
function Storage.SaveWhitelistEntry(entry)
    ensureTable()

    if not entry or not entry.name or tostring(entry.name) == '' then
        return false
    end

    local row = normalizeWhitelistRow(entry)
    row.presentable = row.presentable and 1 or 0
    row.enabled = row.enabled and 1 or 0

    if detectDatabase() then
        local ok, err = pcall(function()
            MySQL.insert.await([[
                INSERT INTO `codex_wallet_whitelist` (`name`, `label`, `weight`, `presentable`, `enabled`, `source`)
                VALUES (?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    `label` = VALUES(`label`),
                    `weight` = VALUES(`weight`),
                    `presentable` = VALUES(`presentable`),
                    `enabled` = VALUES(`enabled`),
                    `source` = VALUES(`source`)
            ]], {
                row.name,
                row.label,
                row.weight,
                row.presentable,
                row.enabled,
                row.source
            })
        end)

        if not ok then
            if Logger then
                Logger.Error('storage', 'Failed to save whitelist entry', { name = row.name, error = tostring(err) })
            end
            return false
        end

        return true
    end

    memoryWhitelist[row.name] = {
        name = row.name,
        label = row.label,
        weight = row.weight,
        presentable = row.presentable == 1,
        enabled = row.enabled == 1,
        source = row.source
    }

    return true
end

--- Delete a whitelist entry completely.
function Storage.DeleteWhitelistEntry(name)
    ensureTable()
    name = tostring(name or '')

    if name == '' then
        return false
    end

    if detectDatabase() then
        local ok, err = pcall(function()
            MySQL.update.await('DELETE FROM `codex_wallet_whitelist` WHERE `name` = ?', { name })
        end)

        if not ok then
            if Logger then
                Logger.Error('storage', 'Failed to delete whitelist entry', { name = name, error = tostring(err) })
            end
            return false
        end

        return true
    end

    memoryWhitelist[name] = nil
    return true
end

--- Test helper: force memory/database mode.
function Storage.SetDatabaseMode(enabled)
    useDatabase = enabled == true
    initialised = true
end

return Storage
