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

-- Whitelist of items allowed inside the wallet (managed in-game via /walletadmin)
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
