-- Shell Creator SQL Setup
-- Tables are auto-created on resource start, but you can run this manually if needed

CREATE TABLE IF NOT EXISTS `shell_creator` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `owner` VARCHAR(50) DEFAULT NULL,
    `label` VARCHAR(100) DEFAULT 'Untitled Shell',
    `slot_id` VARCHAR(50) NOT NULL,
    `template` VARCHAR(50) NOT NULL,
    `props` LONGTEXT DEFAULT NULL,
    `floors` TEXT DEFAULT NULL,
    `colors` TEXT DEFAULT NULL,
    `walls` TEXT DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_slot` (`slot_id`),
    INDEX `idx_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `shell_teleporters` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `shell_id` INT NOT NULL,
    `label` VARCHAR(100) DEFAULT 'Shell',
    `entry_x` FLOAT DEFAULT 0,
    `entry_y` FLOAT DEFAULT 0,
    `entry_z` FLOAT DEFAULT 0,
    `entry_heading` FLOAT DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_shell_id` (`shell_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
