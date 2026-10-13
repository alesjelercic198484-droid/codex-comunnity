-- ---------------------------------------------------------------------------
-- codex_policecreator
--
-- Optional: the resource creates these tables automatically on first start
-- (Config.DB.AutoCreateTables = true). Import this file only if you prefer to
-- manage the schema yourself.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `codex_pc_departments` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_ranks` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `dept_id` INT NOT NULL,
    `grade` INT NOT NULL DEFAULT 0,
    `label` VARCHAR(64) NOT NULL,
    `salary` INT NOT NULL DEFAULT 200,
    `boss` TINYINT NOT NULL DEFAULT 0,
    `perms` TEXT,
    PRIMARY KEY (`id`),
    KEY `dept` (`dept_id`)
);

CREATE TABLE IF NOT EXISTS `codex_pc_divisions` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `dept_id` INT NOT NULL,
    `name` VARCHAR(48) NOT NULL,
    `label` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`id`),
    KEY `dept` (`dept_id`)
);

CREATE TABLE IF NOT EXISTS `codex_pc_nodes` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_members` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_finance_logs` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_duty_logs` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `dept_id` INT NOT NULL,
    `citizenid` VARCHAR(64) NOT NULL,
    `name` VARCHAR(96) NOT NULL,
    `went_on` INT NOT NULL DEFAULT 0,
    `went_off` INT NOT NULL DEFAULT 0,
    `duration` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `dept` (`dept_id`)
);

CREATE TABLE IF NOT EXISTS `codex_pc_evidence` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_calls` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_bolos` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_vehicles` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_cameras` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_trackers` (
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
);

CREATE TABLE IF NOT EXISTS `codex_pc_applications` (
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
);
