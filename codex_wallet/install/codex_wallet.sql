-- ============================================================================
-- CodeX Wallet - database
-- Import this into your QBCore server database.
-- ============================================================================

CREATE TABLE IF NOT EXISTS `codex_wallets` (
    `serial` VARCHAR(32) NOT NULL,
    `cash` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `items` LONGTEXT NULL,
    `owner` VARCHAR(64) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`serial`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
