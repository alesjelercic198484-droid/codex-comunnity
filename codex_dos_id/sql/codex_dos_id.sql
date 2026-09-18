-- Legacy ESX (items table). Skip this if your server uses ox_inventory
-- (add the item to data/items.lua instead, see README.md).
INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`)
VALUES ('dos_id_card', 'DoS Secret Services ID', 0, 1, 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- Make sure a `gouv` job exists (skip if you already have it, or rename
-- Config.Job in config.lua to match your own DoD/government job name).
INSERT INTO `jobs` (`name`, `label`)
VALUES ('gouv', 'Government')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`)
VALUES ('gouv', 0, 'agent', 'Secret Service Agent', 0, '{}', '{}')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
