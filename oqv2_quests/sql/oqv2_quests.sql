-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  OQV2 QUESTS — Database schema                                       ║
-- ║  Author: Codex Dev: #Alesh48 5654   •   Made with CodeX Dev.         ║
-- ╚══════════════════════════════════════════════════════════════════════╝
-- The resource creates these tables automatically on first start,
-- this file is provided for manual/managed installs.

CREATE TABLE IF NOT EXISTS `oqv2_missions` (
  `id`         INT(11) NOT NULL AUTO_INCREMENT,
  `uid`        VARCHAR(64) NOT NULL,
  `name`       VARCHAR(128) NOT NULL DEFAULT 'Mission',
  `enabled`    TINYINT(1) NOT NULL DEFAULT 1,
  `data`       LONGTEXT NOT NULL,
  `created_at` INT(11) NOT NULL DEFAULT 0,
  `updated_at` INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uid` (`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `oqv2_locations` (
  `id`         INT(11) NOT NULL AUTO_INCREMENT,
  `uid`        VARCHAR(64) NOT NULL,
  `name`       VARCHAR(128) NOT NULL DEFAULT 'Location',
  `enabled`    TINYINT(1) NOT NULL DEFAULT 1,
  `data`       LONGTEXT NOT NULL,
  `created_at` INT(11) NOT NULL DEFAULT 0,
  `updated_at` INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uid` (`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `oqv2_npcs` (
  `id`         INT(11) NOT NULL AUTO_INCREMENT,
  `uid`        VARCHAR(64) NOT NULL,
  `name`       VARCHAR(128) NOT NULL DEFAULT 'Hostile',
  `enabled`    TINYINT(1) NOT NULL DEFAULT 1,
  `data`       LONGTEXT NOT NULL,
  `created_at` INT(11) NOT NULL DEFAULT 0,
  `updated_at` INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uid` (`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `oqv2_players` (
  `identifier` VARCHAR(64) NOT NULL,
  `name`       VARCHAR(128) NOT NULL DEFAULT '',
  `xp`         INT(11) NOT NULL DEFAULT 0,
  `level`      INT(11) NOT NULL DEFAULT 1,
  `completed`  INT(11) NOT NULL DEFAULT 0,
  `data`       LONGTEXT NULL,
  `updated_at` INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `oqv2_progress` (
  `id`             INT(11) NOT NULL AUTO_INCREMENT,
  `identifier`     VARCHAR(64) NOT NULL,
  `mission_uid`    VARCHAR(64) NOT NULL,
  `status`         VARCHAR(16) NOT NULL DEFAULT 'available',
  `progress`       LONGTEXT NULL,
  `completions`    INT(11) NOT NULL DEFAULT 0,
  `last_completed` INT(11) NOT NULL DEFAULT 0,
  `window_start` INT(11) NOT NULL DEFAULT 0,
  `window_count` INT(11) NOT NULL DEFAULT 0,
  `updated_at`     INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `player_mission` (`identifier`, `mission_uid`),
  KEY `identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `oqv2_discovered` (
  `id`           INT(11) NOT NULL AUTO_INCREMENT,
  `identifier`   VARCHAR(64) NOT NULL,
  `location_uid` VARCHAR(64) NOT NULL,
  `created_at`   INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `player_location` (`identifier`, `location_uid`),
  KEY `identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `oqv2_logs` (
  `id`         INT(11) NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL DEFAULT '',
  `name`       VARCHAR(128) NOT NULL DEFAULT '',
  `action`     VARCHAR(64) NOT NULL DEFAULT '',
  `detail`     TEXT NULL,
  `created_at` INT(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `action` (`action`),
  KEY `identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
