-- codex_blackmarket database schema.
-- Tables are created automatically when Config.Database.AutoCreate = true.

CREATE TABLE IF NOT EXISTS `codex_blackmarket_profiles` (
  `citizenid` varchar(50) NOT NULL,
  `xp` int unsigned NOT NULL DEFAULT 0,
  `respect` int unsigned NOT NULL DEFAULT 0,
  `completed_runs` int unsigned NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_blackmarket_stock` (
  `item` varchar(64) NOT NULL,
  `stock` int unsigned NOT NULL DEFAULT 0,
  `price_override` int unsigned DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_blackmarket_warehouse_access` (
  `citizenid` varchar(50) NOT NULL,
  `warehouse_id` varchar(32) NOT NULL,
  `pin` char(6) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`, `warehouse_id`),
  KEY `idx_codex_bm_warehouse_id` (`warehouse_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
