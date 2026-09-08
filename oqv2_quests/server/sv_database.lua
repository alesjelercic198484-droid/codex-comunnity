--[[ OQV2 QUESTS — Database layer (oxmysql) | Made with CodeX Dev. ]]

OQ.DB = {}

local ready = false

-------------------------------------------------------------------------------
-- SCHEMA
-------------------------------------------------------------------------------
local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `oqv2_missions` (
        `id` INT(11) NOT NULL AUTO_INCREMENT,
        `uid` VARCHAR(64) NOT NULL,
        `name` VARCHAR(128) NOT NULL DEFAULT 'Mission',
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        `data` LONGTEXT NOT NULL,
        `created_at` INT(11) NOT NULL DEFAULT 0,
        `updated_at` INT(11) NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`), UNIQUE KEY `uid` (`uid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `oqv2_locations` (
        `id` INT(11) NOT NULL AUTO_INCREMENT,
        `uid` VARCHAR(64) NOT NULL,
        `name` VARCHAR(128) NOT NULL DEFAULT 'Location',
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        `data` LONGTEXT NOT NULL,
        `created_at` INT(11) NOT NULL DEFAULT 0,
        `updated_at` INT(11) NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`), UNIQUE KEY `uid` (`uid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `oqv2_npcs` (
        `id` INT(11) NOT NULL AUTO_INCREMENT,
        `uid` VARCHAR(64) NOT NULL,
        `name` VARCHAR(128) NOT NULL DEFAULT 'Hostile',
        `enabled` TINYINT(1) NOT NULL DEFAULT 1,
        `data` LONGTEXT NOT NULL,
        `created_at` INT(11) NOT NULL DEFAULT 0,
        `updated_at` INT(11) NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`), UNIQUE KEY `uid` (`uid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `oqv2_players` (
        `identifier` VARCHAR(64) NOT NULL,
        `name` VARCHAR(128) NOT NULL DEFAULT '',
        `xp` INT(11) NOT NULL DEFAULT 0,
        `level` INT(11) NOT NULL DEFAULT 1,
        `completed` INT(11) NOT NULL DEFAULT 0,
        `data` LONGTEXT NULL,
        `updated_at` INT(11) NOT NULL DEFAULT 0,
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `oqv2_progress` (
        `id` INT(11) NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(64) NOT NULL,
        `mission_uid` VARCHAR(64) NOT NULL,
        `status` VARCHAR(16) NOT NULL DEFAULT 'available',
        `progress` LONGTEXT NULL,
        `completions` INT(11) NOT NULL DEFAULT 0,
        `last_completed` INT(11) NOT NULL DEFAULT 0,
        `window_start` INT(11) NOT NULL DEFAULT 0,
        `window_count` INT(11) NOT NULL DEFAULT 0,
        `updated_at` INT(11) NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        UNIQUE KEY `player_mission` (`identifier`,`mission_uid`),
        KEY `identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `oqv2_discovered` (
        `id` INT(11) NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(64) NOT NULL,
        `location_uid` VARCHAR(64) NOT NULL,
        `created_at` INT(11) NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        UNIQUE KEY `player_location` (`identifier`,`location_uid`),
        KEY `identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `oqv2_logs` (
        `id` INT(11) NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(64) NOT NULL DEFAULT '',
        `name` VARCHAR(128) NOT NULL DEFAULT '',
        `action` VARCHAR(64) NOT NULL DEFAULT '',
        `detail` TEXT NULL,
        `created_at` INT(11) NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`), KEY `action` (`action`), KEY `identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

--- Additive, idempotent-ish upgrades. Failures are ignored on purpose:
--- MySQL < 8.0 has no `ADD COLUMN IF NOT EXISTS`, so a duplicate-column error
--- simply means the migration already ran.
local MIGRATIONS = {
    'ALTER TABLE `oqv2_progress` ADD COLUMN `window_start` INT(11) NOT NULL DEFAULT 0',
    'ALTER TABLE `oqv2_progress` ADD COLUMN `window_count` INT(11) NOT NULL DEFAULT 0',
}

function OQ.DB.isReady()
    return ready
end

--- Create every table. Safe to call repeatedly.
function OQ.DB.ensureSchema()
    if not Config.UseDatabase then
        OQ.warn('Config.UseDatabase = false → running in memory-only mode (nothing is persisted).')
        return false
    end
    for _, stmt in ipairs(SCHEMA) do
        local ok, err = pcall(function() MySQL.query.await(stmt) end)
        if not ok then
            OQ.error('Failed to create a table: ' .. tostring(err))
            return false
        end
    end
    -- Non-fatal migrations for installs created by an earlier build.
    for _, stmt in ipairs(MIGRATIONS) do
        pcall(function() MySQL.query.await(stmt) end)
    end

    ready = true
    OQ.debug('database schema ready')
    return true
end

-------------------------------------------------------------------------------
-- GENERIC ENTITY CRUD  (missions / locations / npcs share the same shape)
-------------------------------------------------------------------------------
local TABLES = {
    mission  = 'oqv2_missions',
    location = 'oqv2_locations',
    npc      = 'oqv2_npcs',
}

local function tableFor(kind)
    local t = TABLES[kind]
    if not t then error(('unknown entity kind "%s"'):format(tostring(kind)), 2) end
    return t
end

function OQ.DB.fetchAll(kind)
    if not ready then return {} end
    local rows = MySQL.query.await(('SELECT `uid`,`data`,`enabled` FROM `%s`'):format(tableFor(kind))) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local data = OQ.decode(row.data, nil)
        if data then
            data.uid     = row.uid
            data.enabled = row.enabled == 1
            out[#out + 1] = data
        else
            OQ.warn(('corrupted %s row skipped (uid=%s)'):format(kind, tostring(row.uid)))
        end
    end
    return out
end

function OQ.DB.upsert(kind, entity)
    if not ready then return true end
    local tbl = tableFor(kind)
    local now = OQ.now()
    local ok, err = pcall(function()
        MySQL.prepare.await(([[
            INSERT INTO `%s` (`uid`,`name`,`enabled`,`data`,`created_at`,`updated_at`)
            VALUES (?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE `name`=VALUES(`name`), `enabled`=VALUES(`enabled`),
                                    `data`=VALUES(`data`), `updated_at`=VALUES(`updated_at`)
        ]]):format(tbl), {
            entity.uid,
            (entity.name or ''):sub(1, 128),
            entity.enabled and 1 or 0,
            OQ.encode(entity),
            entity.meta and entity.meta.createdAt or now,
            now,
        })
    end)
    if not ok then
        OQ.error(('upsert %s failed: %s'):format(kind, tostring(err)))
        return false, tostring(err)
    end
    return true
end

function OQ.DB.delete(kind, uid)
    if not ready then return true end
    local ok, err = pcall(function()
        MySQL.prepare.await(('DELETE FROM `%s` WHERE `uid` = ?'):format(tableFor(kind)), { uid })
    end)
    if not ok then
        OQ.error(('delete %s failed: %s'):format(kind, tostring(err)))
        return false, tostring(err)
    end
    return true
end

function OQ.DB.count(kind)
    if not ready then return 0 end
    return MySQL.scalar.await(('SELECT COUNT(*) FROM `%s`'):format(tableFor(kind))) or 0
end

-------------------------------------------------------------------------------
-- PLAYERS
-------------------------------------------------------------------------------
function OQ.DB.loadPlayer(identifier)
    if not ready then
        return { identifier = identifier, xp = 0, level = 1, completed = 0, data = {} }
    end
    local row = MySQL.single.await('SELECT * FROM `oqv2_players` WHERE `identifier` = ?', { identifier })
    if not row then
        return { identifier = identifier, xp = 0, level = 1, completed = 0, data = {} }
    end
    return {
        identifier = row.identifier,
        name       = row.name,
        xp         = row.xp or 0,
        level      = row.level or 1,
        completed  = row.completed or 0,
        data       = OQ.decode(row.data, {}),
    }
end

function OQ.DB.savePlayer(p)
    if not ready or not p or not p.identifier then return end
    MySQL.prepare(
        [[INSERT INTO `oqv2_players` (`identifier`,`name`,`xp`,`level`,`completed`,`data`,`updated_at`)
          VALUES (?,?,?,?,?,?,?)
          ON DUPLICATE KEY UPDATE `name`=VALUES(`name`), `xp`=VALUES(`xp`), `level`=VALUES(`level`),
                                  `completed`=VALUES(`completed`), `data`=VALUES(`data`),
                                  `updated_at`=VALUES(`updated_at`)]],
        { p.identifier, (p.name or ''):sub(1, 128), p.xp or 0, p.level or 1, p.completed or 0, OQ.encode(p.data or {}), OQ.now() }
    )
end

function OQ.DB.loadProgress(identifier)
    if not ready then return {} end
    local rows = MySQL.query.await('SELECT * FROM `oqv2_progress` WHERE `identifier` = ?', { identifier }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        out[row.mission_uid] = {
            status        = row.status,
            progress      = OQ.decode(row.progress, {}),
            completions   = row.completions or 0,
            lastCompleted = row.last_completed or 0,
            windowStart   = row.window_start or 0,
            windowCount   = row.window_count or 0,
        }
    end
    return out
end

function OQ.DB.saveProgress(identifier, missionUid, entry)
    if not ready then return end
    MySQL.prepare(
        [[INSERT INTO `oqv2_progress` (`identifier`,`mission_uid`,`status`,`progress`,`completions`,`last_completed`,`window_start`,`window_count`,`updated_at`)
          VALUES (?,?,?,?,?,?,?,?,?)
          ON DUPLICATE KEY UPDATE `status`=VALUES(`status`), `progress`=VALUES(`progress`),
                                  `completions`=VALUES(`completions`), `last_completed`=VALUES(`last_completed`),
                                  `window_start`=VALUES(`window_start`), `window_count`=VALUES(`window_count`),
                                  `updated_at`=VALUES(`updated_at`)]],
        {
            identifier, missionUid, entry.status or 'available',
            OQ.encode(entry.progress or {}), entry.completions or 0,
            entry.lastCompleted or 0, entry.windowStart or 0, entry.windowCount or 0, OQ.now(),
        }
    )
end

function OQ.DB.wipeProgress(identifier, missionUid)
    if not ready then return end
    if missionUid then
        MySQL.prepare('DELETE FROM `oqv2_progress` WHERE `identifier` = ? AND `mission_uid` = ?', { identifier, missionUid })
    else
        MySQL.prepare('DELETE FROM `oqv2_progress` WHERE `identifier` = ?', { identifier })
    end
end

function OQ.DB.deleteMissionProgress(missionUid)
    if not ready then return end
    MySQL.prepare('DELETE FROM `oqv2_progress` WHERE `mission_uid` = ?', { missionUid })
end

-------------------------------------------------------------------------------
-- DISCOVERED LOCATIONS
-------------------------------------------------------------------------------
function OQ.DB.loadDiscovered(identifier)
    if not ready then return {} end
    local rows = MySQL.query.await('SELECT `location_uid` FROM `oqv2_discovered` WHERE `identifier` = ?', { identifier }) or {}
    local out = {}
    for _, row in ipairs(rows) do out[row.location_uid] = true end
    return out
end

function OQ.DB.addDiscovered(identifier, locationUid)
    if not ready then return end
    MySQL.prepare('INSERT IGNORE INTO `oqv2_discovered` (`identifier`,`location_uid`,`created_at`) VALUES (?,?,?)',
        { identifier, locationUid, OQ.now() })
end

-------------------------------------------------------------------------------
-- LOGS
-------------------------------------------------------------------------------
function OQ.DB.log(identifier, name, action, detail)
    if not ready then return end
    MySQL.prepare('INSERT INTO `oqv2_logs` (`identifier`,`name`,`action`,`detail`,`created_at`) VALUES (?,?,?,?,?)',
        { identifier or '', (name or ''):sub(1, 128), (action or ''):sub(1, 64),
          type(detail) == 'table' and OQ.encode(detail) or tostring(detail or ''), OQ.now() })
end

function OQ.DB.fetchLogs(limit)
    if not ready then return {} end
    limit = OQ.clamp(math.floor(tonumber(limit) or 100), 1, 500)
    return MySQL.query.await(('SELECT * FROM `oqv2_logs` ORDER BY `id` DESC LIMIT %d'):format(limit)) or {}
end

-------------------------------------------------------------------------------
-- LEADERBOARD / STATS
-------------------------------------------------------------------------------
function OQ.DB.leaderboard(limit)
    if not ready then return {} end
    limit = OQ.clamp(math.floor(tonumber(limit) or 25), 1, 100)
    return MySQL.query.await(
        ('SELECT `identifier`,`name`,`xp`,`level`,`completed` FROM `oqv2_players` ORDER BY `xp` DESC LIMIT %d'):format(limit)
    ) or {}
end

function OQ.DB.globalStats()
    if not ready then
        return { players = 0, completions = 0, active = 0, topMission = nil }
    end
    local players     = MySQL.scalar.await('SELECT COUNT(*) FROM `oqv2_players`') or 0
    local completions = MySQL.scalar.await('SELECT COALESCE(SUM(`completions`),0) FROM `oqv2_progress`') or 0
    local active      = MySQL.scalar.await("SELECT COUNT(*) FROM `oqv2_progress` WHERE `status` = 'active'") or 0
    local top         = MySQL.single.await(
        'SELECT `mission_uid`, SUM(`completions`) AS total FROM `oqv2_progress` GROUP BY `mission_uid` ORDER BY total DESC LIMIT 1')
    return {
        players     = players,
        completions = completions,
        active      = active,
        topMission  = top and top.mission_uid or nil,
    }
end
