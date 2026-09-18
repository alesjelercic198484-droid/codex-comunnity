-- codex_government / ESX Legacy job installer
-- Safe to run more than once: existing grades are updated and missing grades
-- are inserted. Existing salaries are preserved; new grades start at salary 0.

START TRANSACTION;

INSERT INTO `jobs` (`name`, `label`)
VALUES ('gouv', 'United States Government')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

UPDATE `job_grades` SET `name` = 'judge',          `label` = 'Judge'           WHERE `job_name` = 'gouv' AND `grade` = 0;
UPDATE `job_grades` SET `name` = 'prosecutor',     `label` = 'Prosecutor'      WHERE `job_name` = 'gouv' AND `grade` = 1;
UPDATE `job_grades` SET `name` = 'governor',       `label` = 'Governor'        WHERE `job_name` = 'gouv' AND `grade` = 2;
UPDATE `job_grades` SET `name` = 'president',      `label` = 'President'       WHERE `job_name` = 'gouv' AND `grade` = 3;
UPDATE `job_grades` SET `name` = 'secret service', `label` = 'Secret Services' WHERE `job_name` = 'gouv' AND `grade` = 4;
UPDATE `job_grades` SET `name` = 'us marshal',     `label` = 'US Marshal'      WHERE `job_name` = 'gouv' AND `grade` = 5;

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`)
SELECT 'gouv', 0, 'judge', 'Judge', 0
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'gouv' AND `grade` = 0);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`)
SELECT 'gouv', 1, 'prosecutor', 'Prosecutor', 0
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'gouv' AND `grade` = 1);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`)
SELECT 'gouv', 2, 'governor', 'Governor', 0
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'gouv' AND `grade` = 2);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`)
SELECT 'gouv', 3, 'president', 'President', 0
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'gouv' AND `grade` = 3);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`)
SELECT 'gouv', 4, 'secret service', 'Secret Services', 0
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'gouv' AND `grade` = 4);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`)
SELECT 'gouv', 5, 'us marshal', 'US Marshal', 0
WHERE NOT EXISTS (SELECT 1 FROM `job_grades` WHERE `job_name` = 'gouv' AND `grade` = 5);

COMMIT;
