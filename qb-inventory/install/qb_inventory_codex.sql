-- =============================================================================
--  CodeX Roleplay Inventory - optional SQL
--
--  This table is ONLY used to persist stashes, trunks and gloveboxes.
--  The inventory works WITHOUT it: if the table is missing the resource prints
--  a single warning and keeps everything in memory (stashes then reset when
--  the server restarts).
--
--  Run this once in your database (HeidiSQL / phpMyAdmin / oxmysql console).
-- =============================================================================

CREATE TABLE IF NOT EXISTS `codex_inventories` (
    `identifier` VARCHAR(150) NOT NULL,
    `label`      VARCHAR(100) DEFAULT NULL,
    `slots`      INT NOT NULL DEFAULT 50,
    `maxweight`  INT NOT NULL DEFAULT 1000000,
    `items`      LONGTEXT DEFAULT NULL,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Player items are NOT stored here on purpose. They stay in the qb-core
-- `players.inventory` column, which is what makes this a drop-in replacement:
-- every other qb-core script keeps reading and writing the same data.
