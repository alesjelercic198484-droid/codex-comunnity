-- ---------------------------------------------------------------------------
-- codex_cryptomining - items for the ESX inventory
-- ---------------------------------------------------------------------------
-- ONLY import this file if you use the classic ESX inventory (the `items`
-- table). If you use ox_inventory, do NOT run this: copy
-- install/ox_inventory_items.lua into ox_inventory/data/items.lua instead.
--
-- Safe to run several times.
-- ---------------------------------------------------------------------------

INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
  ('gpu',              'Mining GPU',        2, 0, 1),
  ('crypto_cpu',       'CPU upgrade kit',   1, 0, 1),
  ('crypto_cooler',    'Cooling unit',      2, 0, 1),
  ('crypto_repairkit', 'Repair kit',        1, 0, 1),
  ('hacking_usb',      'Hacking USB drive', 1, 0, 1),
  ('hacking_laptop',   'Hacking laptop',    4, 0, 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- The robbery also uses a lockpick. Most servers already have one; uncomment
-- this line only if `lockpick` does not exist in your items table yet.
-- INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`)
--   VALUES ('lockpick', 'Lockpick', 1, 0, 1)
--   ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
