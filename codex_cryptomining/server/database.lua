--[[
    Database abstraction.
    Supports oxmysql, mysql-async and ghmattimysql with the same named
    parameter syntax (@name). Every call is wrapped so a database error can
    never take the resource down.
]]

CodexCryptoDB = CodexCryptoDB or {}

local DB = CodexCryptoDB
local Crypto = CodexCrypto
local RESOURCE = GetCurrentResourceName()

DB.driver = nil
DB.ready = false

local function IsStarted(resourceName)
    return GetResourceState(resourceName) == 'started'
end

local function DetectDriver()
    local configured = (Config.Database and Config.Database.Driver) or 'auto'

    if configured ~= 'auto' then
        return configured
    end

    if IsStarted('oxmysql') then
        return 'oxmysql'
    end

    if IsStarted('mysql-async') then
        return 'mysql-async'
    end

    if IsStarted('ghmattimysql') then
        return 'ghmattimysql'
    end

    return nil
end

--- Converts @named parameters into positional `?` placeholders.
--- A nil value MUST NOT be appended with `#ordered + 1`: that would leave a
--- hole in the array and shift every following parameter by one, silently
--- writing the wrong column. An explicit counter keeps the positions stable.
local function ConvertNamedParameters(query, parameters)
    local ordered = {}
    local count = 0

    local converted = query:gsub('@([%w_]+)', function(name)
        local value

        if parameters then
            value = parameters['@' .. name]
            if value == nil then
                value = parameters[name]
            end
        end

        count = count + 1

        -- `false` keeps the slot occupied. Callers of this file never pass nil
        -- for a column that must stay NULL, they pass an empty string instead.
        if value == nil then
            value = false
        end

        ordered[count] = value
        return '?'
    end)

    return converted, ordered
end

local function RunQuery(query, parameters, mode)
    if not DB.driver then
        print(('[%s] Query attempted before a MySQL driver was ready.'):format(RESOURCE))
        return mode == 'fetch' and {} or 0
    end

    local promiseObject = promise.new()
    local resolved = false

    local function finish(result)
        if resolved then
            return
        end
        resolved = true
        promiseObject:resolve(result)
    end

    local ok, err = pcall(function()
        if DB.driver == 'oxmysql' then
            local converted, ordered = ConvertNamedParameters(query, parameters)
            if mode == 'fetch' then
                exports.oxmysql:query(converted, ordered, finish)
            elseif mode == 'insert' then
                exports.oxmysql:insert(converted, ordered, finish)
            else
                exports.oxmysql:update(converted, ordered, finish)
            end
        elseif DB.driver == 'mysql-async' then
            -- Exports are used instead of the MySQL.Async global on purpose:
            -- the global only exists if '@mysql-async/lib/MySQL.lua' is added
            -- to server_scripts, which would make mysql-async a hard
            -- dependency and break every server that runs oxmysql instead.
            if mode == 'fetch' then
                exports['mysql-async']:mysql_fetch_all(query, parameters or {}, finish)
            elseif mode == 'insert' then
                exports['mysql-async']:mysql_insert(query, parameters or {}, finish)
            else
                exports['mysql-async']:mysql_execute(query, parameters or {}, finish)
            end
        elseif DB.driver == 'ghmattimysql' then
            if mode == 'insert' then
                exports.ghmattimysql:insert(query, parameters or {}, finish)
            else
                exports.ghmattimysql:execute(query, parameters or {}, finish)
            end
        else
            finish(nil)
        end
    end)

    if not ok then
        print(('[%s] MySQL error: %s\nQuery: %s'):format(RESOURCE, err, query))
        finish(nil)
    end

    local result = Citizen.Await(promiseObject)

    if mode == 'fetch' then
        if type(result) ~= 'table' then
            return {}
        end
        return result
    end

    return Crypto.ToNumber(result, 0)
end

function DB.Fetch(query, parameters)
    return RunQuery(query, parameters, 'fetch')
end

function DB.FetchOne(query, parameters)
    local rows = RunQuery(query, parameters, 'fetch')
    return rows and rows[1] or nil
end

function DB.Execute(query, parameters)
    return RunQuery(query, parameters, 'execute')
end

function DB.Insert(query, parameters)
    return RunQuery(query, parameters, 'insert')
end

--- Adds a column to an existing table when it is missing (migration for
--- databases created by older versions). MySQL has no "ADD COLUMN IF NOT
--- EXISTS" (MariaDB only), so we check first and only ALTER when needed.
--- Table / column names are hardcoded constants, never user input, so the
--- format interpolation is safe here.
local function EnsureColumn(tableName, columnName, ddl)
    local rows = DB.Fetch(("SHOW COLUMNS FROM `%s` LIKE '%s'"):format(tableName, columnName))

    if rows and #rows > 0 then
        return true
    end

    DB.Execute(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, ddl))

    return true
end

local SCHEMA = {
    [[
        CREATE TABLE IF NOT EXISTS `codex_crypto_warehouses` (
          `warehouse_id` varchar(48) NOT NULL,
          `owner` varchar(80) DEFAULT NULL,
          `owner_name` varchar(80) DEFAULT NULL,
          `btc` decimal(18,8) NOT NULL DEFAULT 0,
          `bill` int NOT NULL DEFAULT 0,
          `powered` tinyint(1) NOT NULL DEFAULT 1,
          `locked` tinyint(1) NOT NULL DEFAULT 1,
          `last_tick` bigint NOT NULL DEFAULT 0,
          `total_mined` decimal(18,8) NOT NULL DEFAULT 0,
          `total_earned` bigint NOT NULL DEFAULT 0,
          `robbed_at` bigint NOT NULL DEFAULT 0,
          `gpu_stock` int NOT NULL DEFAULT 0,
          `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`warehouse_id`),
          KEY `idx_crypto_warehouse_owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `codex_crypto_rigs` (
          `id` int unsigned NOT NULL AUTO_INCREMENT,
          `warehouse_id` varchar(48) NOT NULL,
          `slot` int unsigned NOT NULL,
          `gpus` int unsigned NOT NULL DEFAULT 0,
          `cpu` int unsigned NOT NULL DEFAULT 0,
          `cooler` int unsigned NOT NULL DEFAULT 0,
          `durability` decimal(6,2) NOT NULL DEFAULT 100.00,
          `broken` tinyint(1) NOT NULL DEFAULT 0,
          `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uniq_crypto_rig_slot` (`warehouse_id`, `slot`),
          KEY `idx_crypto_rig_warehouse` (`warehouse_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `codex_crypto_keys` (
          `warehouse_id` varchar(48) NOT NULL,
          `identifier` varchar(80) NOT NULL,
          `name` varchar(80) DEFAULT NULL,
          `granted_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`warehouse_id`, `identifier`),
          KEY `idx_crypto_keys_identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `codex_crypto_market` (
          `id` int unsigned NOT NULL AUTO_INCREMENT,
          `price` int NOT NULL,
          `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]]
}

function DB.Init()
    local attempts = 0

    while not DB.driver and attempts < 60 do
        DB.driver = DetectDriver()

        if not DB.driver then
            attempts = attempts + 1
            Wait(500)
        end
    end

    if not DB.driver then
        print(('[%s] ^1No MySQL resource found (oxmysql / mysql-async / ghmattimysql). The resource will stay idle.^0'):format(RESOURCE))
        return false
    end

    -- Give the driver time to open its connection pool.
    Wait(500)

    if Config.Database and Config.Database.AutoCreate ~= false then
        for _, statement in ipairs(SCHEMA) do
            DB.Execute(statement)
        end

        -- Migrations for databases created by older versions: add the columns
        -- one by one, ignoring "duplicate column" errors. MySQL has no
        -- "ADD COLUMN IF NOT EXISTS" (that is MariaDB only), so a plain
        -- protected ALTER is the portable option.
        EnsureColumn('codex_crypto_warehouses', 'gpu_stock', 'int NOT NULL DEFAULT 0')
    end

    DB.ready = true
    print(('[%s] Database ready using %s.'):format(RESOURCE, DB.driver))

    return true
end
