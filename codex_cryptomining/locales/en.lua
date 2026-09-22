Locales = Locales or {}

Locales['en'] = {
    -- generic
    ['not_ready'] = 'The crypto network is still starting, try again in a moment.',
    ['no_access'] = 'You do not have access to this warehouse.',
    ['not_owner'] = 'Only the owner can do that.',
    ['invalid_action'] = 'Invalid action.',
    ['too_far'] = 'You are too far away.',
    ['no_money'] = 'You cannot afford this.',
    ['no_space'] = 'You do not have enough room in your inventory.',
    ['busy'] = 'Please wait a moment.',
    ['cancelled'] = 'Cancelled.',
    ['failed'] = 'Something went wrong.',

    -- warehouse
    ['warehouse_bought'] = 'You bought %s for %s.',
    ['warehouse_sold'] = 'You sold %s for %s.',
    ['warehouse_owned'] = 'This warehouse already has an owner.',
    ['warehouse_limit'] = 'You already own the maximum number of warehouses.',
    ['warehouse_locked'] = 'The door is locked.',
    ['warehouse_enter'] = 'Enter warehouse',
    ['warehouse_exit'] = 'Leave warehouse',
    ['warehouse_panel'] = 'Management terminal',
    ['warehouse_power'] = 'Electricity panel',
    ['warehouse_storage'] = 'GPU storage',
    ['warehouse_blip'] = 'Crypto Warehouse',
    ['keys_given'] = 'You gave the keys to %s.',
    ['keys_received'] = 'You received the keys of %s.',
    ['keys_removed'] = 'You removed the keys of %s.',
    ['keys_lost'] = 'You lost access to %s.',
    ['keys_no_player'] = 'No player nearby.',

    -- rigs
    ['rig_installed'] = 'Mining rig installed.',
    ['rig_removed'] = 'Mining rig dismantled.',
    ['rig_full'] = 'No free slot left in this warehouse.',
    ['rig_not_found'] = 'This rig does not exist.',
    ['rig_not_empty'] = 'Remove every GPU before dismantling the rig.',
    ['rig_broken'] = 'This rig is broken, repair it first.',
    ['rig_repaired'] = 'Rig repaired (%s%%).',
    ['rig_disaster'] = 'A rig broke down in %s!',
    ['gpu_installed'] = 'GPU installed.',
    ['gpu_removed'] = 'GPU removed.',
    ['gpu_full'] = 'This rig is already full.',
    ['gpu_none'] = 'There is no GPU in this rig.',
    ['gpu_missing'] = 'You do not have a GPU.',
    ['cpu_installed'] = 'CPU upgraded to level %s.',
    ['cpu_max'] = 'This rig already has the best CPU.',
    ['cooler_installed'] = 'Cooler upgraded to level %s.',
    ['cooler_max'] = 'This rig already has the best cooler.',
    ['repairkit_missing'] = 'You need a repair kit.',

    -- power
    ['power_cut'] = 'The power of %s has been cut, pay the bill.',
    ['power_restored'] = 'Power restored in %s.',
    ['power_paid'] = 'You paid %s of electricity.',
    ['power_nothing'] = 'There is nothing to pay.',
    ['power_off'] = 'The power is off.',

    -- market
    ['market_sold'] = 'You sold %s BTC for %s.',
    ['market_empty'] = 'You do not have that much BTC.',
    ['market_price'] = 'Bitcoin is worth %s.',
    ['storage_full'] = 'The wallet of this warehouse is full, sell your BTC.',

    -- shops
    ['shop_bought'] = 'You bought %sx %s for %s.',
    ['shop_sold'] = 'You sold %sx %s for %s.',
    ['shop_no_item'] = 'You do not have this item.',
    ['shop_quantity'] = 'Invalid quantity.',
    ['techshop_target'] = 'TechShop',
    ['blackmarket_target'] = 'Black market',
    ['informant_target'] = 'Informant',
    ['broker_target'] = 'Real estate broker',

    -- informant
    ['informant_bought'] = 'The location of %s has been marked on your GPS.',
    ['informant_none'] = 'No interesting target right now.',
    ['informant_cooldown'] = 'Come back in %s minutes.',

    -- robbery
    ['robbery_started'] = 'You broke into the warehouse.',
    ['robbery_police'] = 'You do not have enough contacts in the city right now.',
    ['robbery_busy'] = 'Too many jobs are running right now.',
    ['robbery_cooldown'] = 'You need to lay low for %s minutes.',
    ['robbery_warehouse_cooldown'] = 'This warehouse has already been hit recently.',
    ['robbery_empty'] = 'There is nothing worth stealing here.',
    ['robbery_own'] = 'You cannot rob your own warehouse.',
    ['robbery_need_lockpick'] = 'You need a lockpick.',
    ['robbery_need_usb'] = 'You need a hacking USB drive.',
    ['robbery_lockpick_broken'] = 'Your lockpick broke.',
    ['robbery_failed'] = 'You failed.',
    ['robbery_looted'] = 'You stole %sx GPU.',
    ['robbery_nothing_left'] = 'This rig is empty.',
    ['robbery_owner_alert'] = 'Alarm: someone broke into %s!',
    ['robbery_finished'] = 'The job is over, get out.',
    ['robbery_timeout'] = 'You took too long.',

    -- targets / prompts
    ['target_rig'] = 'Mining rig',
    ['target_rig_loot'] = 'Steal the GPUs',
    ['target_door'] = 'Force the door',
    ['press_to_open'] = 'Press ~INPUT_CONTEXT~ to %s',

    -- rig monitor (per-computer status view)
    ['rig_monitor_title'] = 'Rig monitor #%s',
    ['rig_monitor_banner'] = 'Live status read from rig #%s',

    -- skillcheck
    ['skillcheck_title'] = 'Bypass security',
    ['skillcheck_door'] = 'Pick the lock',
    ['skillcheck_rig'] = 'Bypass the rig',

    -- admin
    ['admin_only'] = 'You are not allowed to use this command.',
    ['admin_reset'] = 'Warehouse %s has been reset.',
    ['admin_unknown'] = 'Unknown warehouse.',
    ['admin_usage'] = 'Usage: /%s [price|reset|info|setowner] ...'
}
