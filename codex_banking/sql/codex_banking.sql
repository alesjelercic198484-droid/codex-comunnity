CREATE TABLE IF NOT EXISTS `codex_bank_accounts` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `account_no` VARCHAR(32) NOT NULL,
  `bank_id` VARCHAR(24) NOT NULL,
  `account_type` VARCHAR(20) NOT NULL DEFAULT 'checking',
  `label` VARCHAR(64) NOT NULL,
  `owner_cid` VARCHAR(64) DEFAULT NULL,
  `job_name` VARCHAR(50) DEFAULT NULL,
  `balance` BIGINT NOT NULL DEFAULT 0,
  `daily_limit` BIGINT NOT NULL DEFAULT 100000,
  `max_balance` BIGINT NOT NULL DEFAULT 10000000,
  `account_level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `savings_tier` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `savings_goal` BIGINT NOT NULL DEFAULT 0,
  `savings_goal_label` VARCHAR(64) NOT NULL DEFAULT '',
  `last_interest_day` DATE DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_codex_bank_account_no` (`account_no`),
  UNIQUE KEY `uq_codex_bank_owner` (`owner_cid`, `bank_id`, `account_type`),
  UNIQUE KEY `uq_codex_bank_job` (`job_name`),
  KEY `idx_codex_bank_owner` (`owner_cid`),
  KEY `idx_codex_bank_type` (`account_type`, `bank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_account_members` (
  `account_id` BIGINT UNSIGNED NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `role` VARCHAR(20) NOT NULL DEFAULT 'member',
  `daily_limit` BIGINT NOT NULL DEFAULT 100000,
  `daily_spent` BIGINT NOT NULL DEFAULT 0,
  `daily_spent_date` DATE DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`account_id`, `citizenid`),
  KEY `idx_codex_bank_member_cid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_transactions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reference` VARCHAR(32) NOT NULL,
  `from_account_id` BIGINT UNSIGNED DEFAULT NULL,
  `to_account_id` BIGINT UNSIGNED DEFAULT NULL,
  `actor_cid` VARCHAR(64) DEFAULT NULL,
  `type` VARCHAR(32) NOT NULL,
  `amount` BIGINT NOT NULL DEFAULT 0,
  `fee` BIGINT NOT NULL DEFAULT 0,
  `description` VARCHAR(160) NOT NULL DEFAULT '',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_codex_bank_transaction_ref` (`reference`),
  KEY `idx_codex_bank_tx_from` (`from_account_id`, `created_at`),
  KEY `idx_codex_bank_tx_to` (`to_account_id`, `created_at`),
  KEY `idx_codex_bank_tx_actor` (`actor_cid`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_cards` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `account_id` BIGINT UNSIGNED NOT NULL,
  `holder_cid` VARCHAR(64) NOT NULL,
  `tier` VARCHAR(20) NOT NULL DEFAULT 'standard',
  `last4` CHAR(4) NOT NULL,
  `pin_digest` CHAR(64) NOT NULL,
  `is_frozen` TINYINT(1) NOT NULL DEFAULT 0,
  `failed_attempts` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `locked_until` DATETIME DEFAULT NULL,
  `daily_limit` BIGINT NOT NULL DEFAULT 15000,
  `daily_spent` BIGINT NOT NULL DEFAULT 0,
  `daily_spent_date` DATE DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_codex_bank_card_holder` (`holder_cid`),
  KEY `idx_codex_bank_card_account` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_loans` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reference` VARCHAR(32) NOT NULL,
  `borrower_cid` VARCHAR(64) NOT NULL,
  `account_id` BIGINT UNSIGNED NOT NULL,
  `bank_id` VARCHAR(24) NOT NULL,
  `plan_id` VARCHAR(24) NOT NULL,
  `principal` BIGINT NOT NULL,
  `balance` BIGINT NOT NULL,
  `interest_rate` DECIMAL(8,5) NOT NULL DEFAULT 0,
  `due_at` DATETIME NOT NULL,
  `last_penalty_at` DATETIME DEFAULT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `collateral_plate` VARCHAR(16) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_codex_bank_loan_ref` (`reference`),
  KEY `idx_codex_bank_loan_borrower` (`borrower_cid`, `status`),
  KEY `idx_codex_bank_loan_due` (`status`, `due_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_invoices` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reference` VARCHAR(32) NOT NULL,
  `issuer_cid` VARCHAR(64) NOT NULL,
  `recipient_cid` VARCHAR(64) NOT NULL,
  `issuer_account_id` BIGINT UNSIGNED NOT NULL,
  `amount` BIGINT NOT NULL,
  `reason` VARCHAR(100) NOT NULL DEFAULT '',
  `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
  `due_at` DATETIME NOT NULL,
  `paid_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_codex_bank_invoice_ref` (`reference`),
  KEY `idx_codex_bank_invoice_recipient` (`recipient_cid`, `status`),
  KEY `idx_codex_bank_invoice_issuer` (`issuer_cid`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_cheques` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `cheque_no` VARCHAR(16) NOT NULL,
  `issuer_cid` VARCHAR(64) NOT NULL,
  `account_id` BIGINT UNSIGNED NOT NULL,
  `beneficiary_cid` VARCHAR(64) DEFAULT NULL,
  `amount` BIGINT NOT NULL,
  `reason` VARCHAR(100) NOT NULL DEFAULT '',
  `status` VARCHAR(20) NOT NULL DEFAULT 'issued',
  `expires_at` DATETIME NOT NULL,
  `cashed_by` VARCHAR(64) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `cashed_at` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_codex_bank_cheque_no` (`cheque_no`),
  KEY `idx_codex_bank_cheque_issuer` (`issuer_cid`, `status`),
  KEY `idx_codex_bank_cheque_beneficiary` (`beneficiary_cid`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_daily_usage` (
  `citizenid` VARCHAR(64) NOT NULL,
  `usage_type` VARCHAR(32) NOT NULL,
  `usage_day` DATE NOT NULL,
  `amount` BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`citizenid`, `usage_type`, `usage_day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_vaults` (
  `bank_id` VARCHAR(24) NOT NULL,
  `fee_balance` BIGINT NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`bank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_legacy_sync` (
  `citizenid` VARCHAR(64) NOT NULL,
  `last_bank_balance` BIGINT NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_credit_scores` (
  `citizenid` VARCHAR(64) NOT NULL,
  `score` SMALLINT UNSIGNED NOT NULL DEFAULT 650,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_activity` (
  `citizenid` VARCHAR(64) NOT NULL,
  `activity_day` DATE NOT NULL,
  `online_seconds` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`citizenid`, `activity_day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_atm_owners` (
  `atm_id` INT UNSIGNED NOT NULL,
  `owner_cid` VARCHAR(64) NOT NULL,
  `surcharge_percent` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  `fee_balance` BIGINT NOT NULL DEFAULT 0,
  `purchased_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`atm_id`),
  KEY `idx_codex_bank_atm_owner` (`owner_cid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_safe_boxes` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_cid` VARCHAR(64) NOT NULL,
  `bank_id` VARCHAR(24) NOT NULL,
  `stash_id` VARCHAR(100) NOT NULL,
  `slots` SMALLINT UNSIGNED NOT NULL,
  `max_weight` INT UNSIGNED NOT NULL,
  `rent_expires_at` DATETIME NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_codex_bank_safe_stash` (`stash_id`),
  KEY `idx_codex_bank_safe_owner` (`owner_cid`, `rent_expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_safe_box_members` (
  `box_id` BIGINT UNSIGNED NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`box_id`, `citizenid`),
  KEY `idx_codex_bank_safe_member` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_repossessions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `loan_id` BIGINT UNSIGNED NOT NULL,
  `plate` VARCHAR(16) NOT NULL,
  `previous_owner_cid` VARCHAR(64) NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'repossessed',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_codex_bank_repossessed_loan` (`loan_id`),
  KEY `idx_codex_bank_repossessed_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `codex_bank_settings` (
  `setting_key` VARCHAR(64) NOT NULL,
  `setting_value` VARCHAR(255) NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Widen existing early-development PIN verifiers for SHA-256 digests.
ALTER TABLE `codex_bank_cards` MODIFY COLUMN `pin_digest` CHAR(64) NOT NULL;
