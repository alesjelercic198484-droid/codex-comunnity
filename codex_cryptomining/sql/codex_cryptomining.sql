-- ---------------------------------------------------------------------------
-- codex_cryptomining - database schema
-- ---------------------------------------------------------------------------
-- The resource creates these tables automatically on first start
-- (Config.Database.AutoCreate = true). Import this file manually if you
-- prefer to manage your schema yourself.
-- ---------------------------------------------------------------------------

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
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`warehouse_id`),
  KEY `idx_crypto_warehouse_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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

CREATE TABLE IF NOT EXISTS `codex_crypto_keys` (
  `warehouse_id` varchar(48) NOT NULL,
  `identifier` varchar(80) NOT NULL,
  `name` varchar(80) DEFAULT NULL,
  `granted_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`warehouse_id`, `identifier`),
  KEY `idx_crypto_keys_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_crypto_market` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `price` int NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Items are NOT created here on purpose.
--
--   * ox_inventory  -> copy install/ox_inventory_items.lua into
--                      ox_inventory/data/items.lua
--   * ESX inventory -> import sql/esx_items.sql
--
-- Keeping them separate means importing this file can never fail with
-- "Table 'items' doesn't exist" on an ox_inventory server.
-- ---------------------------------------------------------------------------
