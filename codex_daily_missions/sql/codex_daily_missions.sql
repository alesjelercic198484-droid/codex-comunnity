CREATE TABLE IF NOT EXISTS `codex_daily_missions` (
  `identifier` varchar(80) NOT NULL,
  `day_key` varchar(32) NOT NULL,
  `mission_key` varchar(64) NOT NULL,
  `label` varchar(128) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `required_seconds` int unsigned NOT NULL DEFAULT 0,
  `progress` int unsigned NOT NULL DEFAULT 0,
  `completed` tinyint(1) NOT NULL DEFAULT 0,
  `claimed` tinyint(1) NOT NULL DEFAULT 0,
  `rewards_json` longtext DEFAULT NULL,
  `completed_at` timestamp NULL DEFAULT NULL,
  `claimed_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`, `day_key`, `mission_key`),
  KEY `idx_codex_daily_identifier_claimed` (`identifier`, `claimed`),
  KEY `idx_codex_daily_day` (`day_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
