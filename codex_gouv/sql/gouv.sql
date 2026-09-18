-- Run this once after es_extended is installed.
-- The INSERT IGNORE form is safe to run again after edits.

INSERT IGNORE INTO `jobs` (`name`, `label`) VALUES
('gouv', 'Government of San Andreas');

INSERT IGNORE INTO `job_grades`
(`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES
('gouv', 0, 'judge', 'Judge', 0, '{}', '{}'),
('gouv', 1, 'prosecutor', 'Prosecutor', 0, '{}', '{}'),
('gouv', 2, 'governor', 'Governor', 0, '{}', '{}'),
('gouv', 3, 'president', 'President', 0, '{}', '{}'),
('gouv', 4, 'secret_service', 'Secret Services', 0, '{}', '{}'),
('gouv', 5, 'us_marshal', 'US Marshal', 0, '{}', '{}');

-- Optional if your server uses society accounts and society management:
-- INSERT IGNORE INTO addon_account (name, label, shared) VALUES ('society_gouv', 'Government', 1);
-- INSERT IGNORE INTO addon_inventory (name, label, shared) VALUES ('society_gouv', 'Government', 1);
-- INSERT IGNORE INTO datastore (name, label, shared) VALUES ('society_gouv', 'Government', 1);
