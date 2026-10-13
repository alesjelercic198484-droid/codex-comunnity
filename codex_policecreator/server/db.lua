--[[
    server/db.lua - schema + thin oxmysql wrapper.

    The resource creates its own tables on first start so it is genuinely
    copy-paste. sql/codex_policecreator.sql contains the same schema for people
    who prefer to import it by hand.
]]

DB = {}

local RESOURCE = GetCurrentResourceName()
local tablesReady = false

local function prefix()
    return (Config.DB and Config.DB.Prefix) or 'codex_pc_'
end

DB.Prefix = prefix()

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

-- ---------------------------------------------------------------------------
-- QUERY WRAPPERS (all synchronous via oxmysql's .await helpers)
-- ---------------------------------------------------------------------------

--- SELECT. Always returns a table.
function DB.Fetch(query, params)
    local result = MySQL.query.await(query, params or {})
    return result or {}
end

--- INSERT. Returns the auto increment id.
function DB.Insert(query, params)
    return MySQL.insert.await(query, params or {})
end

--- UPDATE / DELETE. Returns affected rows.
function DB.Execute(query, params)
    return MySQL.update.await(query, params or {})
end

--- Single scalar helper: SELECT COUNT(*) / SUM() ...
function DB.Scalar(query, params)
    local rows = DB.Fetch(query, params)
    local row = rows[1]
    if not row then return 0 end
    for _, value in pairs(row) do
        return tonumber(value) or value
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- SCHEMA
-- ---------------------------------------------------------------------------
local function schema()
    local p = prefix()

    return {
        ([[CREATE TABLE IF NOT EXISTS `%sdepartments` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(64) NOT NULL,
            `label` VARCHAR(96) NOT NULL,
            `type` VARCHAR(32) NOT NULL DEFAULT 'police',
            `color` VARCHAR(16) NOT NULL DEFAULT '#2f6df6',
            `blip_sprite` INT NOT NULL DEFAULT 60,
            `blip_color` INT NOT NULL DEFAULT 29,
            `blip_scale` FLOAT NOT NULL DEFAULT 0.9,
            `funds` BIGINT NOT NULL DEFAULT 0,
            `default_salary` INT NOT NULL DEFAULT 200,
            `created_at` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            UNIQUE KEY `name` (`name`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%sranks` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `grade` INT NOT NULL DEFAULT 0,
            `label` VARCHAR(64) NOT NULL,
            `salary` INT NOT NULL DEFAULT 200,
            `boss` TINYINT NOT NULL DEFAULT 0,
            `perms` TEXT,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%sdivisions` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `name` VARCHAR(48) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%snodes` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `type` VARCHAR(24) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `x` FLOAT NOT NULL DEFAULT 0,
            `y` FLOAT NOT NULL DEFAULT 0,
            `z` FLOAT NOT NULL DEFAULT 0,
            `heading` FLOAT NOT NULL DEFAULT 0,
            `blip` TINYINT NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%smembers` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL,
            `first_name` VARCHAR(48) NOT NULL DEFAULT 'Unknown',
            `last_name` VARCHAR(48) NOT NULL DEFAULT '',
            `rank_id` INT NOT NULL DEFAULT 0,
            `division_id` INT NOT NULL DEFAULT 0,
            `salary` INT NOT NULL DEFAULT 0,
            `on_duty` TINYINT NOT NULL DEFAULT 0,
            `duty_seconds` INT NOT NULL DEFAULT 0,
            `hired_at` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            UNIQUE KEY `citizenid` (`citizenid`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%sfinance_logs` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `citizenid` VARCHAR(64) DEFAULT NULL,
            `name` VARCHAR(96) NOT NULL,
            `type` VARCHAR(24) NOT NULL,
            `amount` BIGINT NOT NULL DEFAULT 0,
            `balance_after` BIGINT NOT NULL DEFAULT 0,
            `timestamp` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%sduty_logs` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL,
            `name` VARCHAR(96) NOT NULL,
            `went_on` INT NOT NULL DEFAULT 0,
            `went_off` INT NOT NULL DEFAULT 0,
            `duration` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%sevidence` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `label` VARCHAR(96) NOT NULL,
            `description` TEXT,
            `grade` INT NOT NULL DEFAULT 1,
            `x` FLOAT NOT NULL DEFAULT 0,
            `y` FLOAT NOT NULL DEFAULT 0,
            `z` FLOAT NOT NULL DEFAULT 0,
            `officer` VARCHAR(96) NOT NULL,
            `owner` VARCHAR(96) DEFAULT NULL,
            `bagged` TINYINT NOT NULL DEFAULT 0,
            `taken_by` VARCHAR(64) DEFAULT NULL,
            `created_at` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%scalls` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `code` VARCHAR(16) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `description` TEXT,
            `x` FLOAT NOT NULL DEFAULT 0,
            `y` FLOAT NOT NULL DEFAULT 0,
            `z` FLOAT NOT NULL DEFAULT 0,
            `caller_id` INT NOT NULL DEFAULT 0,
            `caller_name` VARCHAR(96) NOT NULL,
            `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
            `assigned_id` INT NOT NULL DEFAULT 0,
            `assigned_name` VARCHAR(96) DEFAULT NULL,
            `created_at` INT NOT NULL DEFAULT 0,
            `closed_at` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%sbolos` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `type` VARCHAR(16) NOT NULL DEFAULT 'plate',
            `value` VARCHAR(64) NOT NULL,
            `description` TEXT,
            `created_by` VARCHAR(96) NOT NULL,
            `active` TINYINT NOT NULL DEFAULT 1,
            `created_at` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%svehicles` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `model` VARCHAR(48) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `plate` VARCHAR(16) NOT NULL,
            `spawn_node` INT NOT NULL DEFAULT 0,
            `rank_min` INT NOT NULL DEFAULT 0,
            `division_id` INT NOT NULL DEFAULT 0,
            `livery` INT NOT NULL DEFAULT -1,
            `fuel` INT NOT NULL DEFAULT 100,
            `body_health` INT NOT NULL DEFAULT 1000,
            `engine_health` INT NOT NULL DEFAULT 1000,
            `stored` TINYINT NOT NULL DEFAULT 1,
            `impounded` TINYINT NOT NULL DEFAULT 0,
            `out_by` VARCHAR(64) DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%scameras` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `x` FLOAT NOT NULL DEFAULT 0,
            `y` FLOAT NOT NULL DEFAULT 0,
            `z` FLOAT NOT NULL DEFAULT 0,
            `heading` FLOAT NOT NULL DEFAULT 0,
            `rank_min` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%strackers` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `plate` VARCHAR(16) NOT NULL,
            `net_id` INT NOT NULL DEFAULT 0,
            `x` FLOAT NOT NULL DEFAULT 0,
            `y` FLOAT NOT NULL DEFAULT 0,
            `z` FLOAT NOT NULL DEFAULT 0,
            `placed_by` VARCHAR(96) NOT NULL,
            `active` TINYINT NOT NULL DEFAULT 1,
            `created_at` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p),

        ([[CREATE TABLE IF NOT EXISTS `%sapplications` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `dept_id` INT NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL,
            `first_name` VARCHAR(48) NOT NULL,
            `last_name` VARCHAR(48) NOT NULL,
            `message` TEXT,
            `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
            `created_at` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `dept` (`dept_id`)
        )]]):format(p)
    }
end

function DB.CreateTables()
    if tablesReady then return true end
    if not (Config.DB and Config.DB.AutoCreateTables) then
        tablesReady = true
        return true
    end

    for _, statement in ipairs(schema()) do
        MySQL.query.await(statement, {})
    end

    tablesReady = true
    log('database tables ready')
    return true
end

function DB.IsReady()
    return tablesReady
end

--- Wipes every row of every table (admin command).
function DB.Wipe()
    local p = prefix()
    local order = {
        'finance_logs', 'duty_logs', 'evidence', 'calls', 'bolos', 'vehicles',
        'cameras', 'trackers', 'applications', 'members', 'nodes', 'divisions',
        'ranks', 'departments'
    }

    for _, name in ipairs(order) do
        MySQL.query.await(('DELETE FROM `%s%s`'):format(p, name), {})
    end
end
