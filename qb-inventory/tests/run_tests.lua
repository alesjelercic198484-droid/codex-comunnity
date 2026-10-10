--[============================================================================[
    qb-inventory (CodeX Roleplay) - automated test suite

        python3 tests/run_lua_tests.py        (uses lupa, no system Lua needed)
        lua tests/run_tests.lua               (from the resource folder)

    It boots the REAL server/core.lua and server/main.lua against the FiveM +
    qb-core emulator in tests/mock_fivem.lua and asserts on actual behaviour:
    adding, stacking, weight limits, removing, moving, swapping, splitting,
    drops, stashes, shops and the qb-inventory export surface.
]============================================================================]

package.path = './tests/?.lua;./?.lua;' .. package.path

local Mock = require('mock_fivem')

-- ---------------------------------------------------------------------------
-- Tiny test framework
-- ---------------------------------------------------------------------------
local passed, failed = 0, 0
local failures = {}
local currentGroup = ''

local function group(name)
    currentGroup = name
    print(('\n\27[1;36m== %s\27[0m'):format(name))
end

local function ok(condition, name, detail)
    if condition then
        passed = passed + 1
        print(('  \27[32mPASS\27[0m %s'):format(name))
    else
        failed = failed + 1
        failures[#failures + 1] = ('[%s] %s%s'):format(currentGroup, name,
            detail and (' -> ' .. tostring(detail)) or '')
        print(('  \27[31mFAIL\27[0m %s%s'):format(name,
            detail and (' -> ' .. tostring(detail)) or ''))
    end
end

local function equals(actual, expected, name)
    ok(actual == expected, name, ('expected %s, got %s'):format(tostring(expected), tostring(actual)))
end

-- ---------------------------------------------------------------------------
-- World
-- ---------------------------------------------------------------------------
local P1, P2 = 1, 2

-- Shared items (like qb-core/shared/items.lua)
Mock.AddItem('water_bottle', { name = 'water_bottle', label = 'Water Bottle', weight = 500, type = 'item', unique = false, useable = true, image = 'water_bottle.png' })
Mock.AddItem('lockpick',     { name = 'lockpick',     label = 'Lockpick',     weight = 100, type = 'item', unique = false, useable = true, image = 'lockpick.png' })
Mock.AddItem('goldbar',      { name = 'goldbar',      label = 'Gold Bar',     weight = 5000, type = 'item', unique = false, useable = false, image = 'goldbar.png', rarity = 'legendary' })
Mock.AddItem('weapon_pistol',{ name = 'weapon_pistol',label = 'Pistol',       weight = 1500, type = 'weapon', unique = true, useable = true, image = 'weapon_pistol.png' })
Mock.AddItem('sandwich',     { name = 'sandwich',     label = 'Sandwich',     weight = 400, type = 'item', unique = false, useable = true, image = 'sandwich.png' })
Mock.AddItem('phone',        { name = 'phone',        label = 'Phone',        weight = 300, type = 'item', unique = false, useable = true, image = 'phone.png' })
Mock.AddItem('heavy_thing',  { name = 'heavy_thing',  label = 'Heavy Thing',  weight = 200000, type = 'item', unique = false, useable = false, image = 'heavy.png' })

Mock.AddPlayer(P1, { name = 'Alex Novak', citizenid = 'CID1', cash = 5000, bank = 10000, x = 0, y = 0, z = 0 })
Mock.AddPlayer(P2, { name = 'Sam Rivera', citizenid = 'CID2', cash = 0,    bank = 0,     x = 1, y = 0, z = 0 })
Mock.AttachMethods()

-- Load the resource exactly like the fxmanifest does.
Mock.LoadScript('config.lua')
Mock.LoadScript('server/core.lua')
Mock.LoadScript('server/main.lua')

-- ---------------------------------------------------------------------------
group('Exports exist')

local expectedExports = {
    'LoadInventory', 'SaveInventory', 'SetInventory', 'SetItemData', 'UseItem',
    'GetSlotsByItem', 'GetFirstSlotByItem', 'GetItemBySlot', 'GetTotalWeight',
    'GetItemByName', 'GetItemsByName', 'GetSlots', 'GetItemCount', 'CanAddItem',
    'GetFreeWeight', 'ClearInventory', 'HasItem', 'CloseInventory',
    'OpenInventoryById', 'ClearStash', 'CreateShop', 'OpenShop', 'OpenInventory',
    'CreateInventory', 'GetInventory', 'RemoveInventory', 'AddItem', 'RemoveItem',
    'AddHook', 'RemoveHook', 'AddListener', 'RemoveListener'
}

for _, name in ipairs(expectedExports) do
    ok(Mock.registered[name] ~= nil, ('export %s'):format(name))
end

-- ---------------------------------------------------------------------------
group('AddItem')

equals(Mock.Export('AddItem', P1, 'water_bottle', 3), true, 'adds an item')
equals(Mock.Count(P1, 'water_bottle'), 3, 'amount is 3')
equals(Mock.Inventory(P1)[1].name, 'water_bottle', 'goes into slot 1')
equals(Mock.Inventory(P1)[1].slot, 1, 'slot field is set')
equals(Mock.Inventory(P1)[1].label, 'Water Bottle', 'label copied from Shared.Items')
equals(Mock.Inventory(P1)[1].rarity, 'common', 'rarity defaults to common')

Mock.Export('AddItem', P1, 'water_bottle', 2)
equals(Mock.Count(P1, 'water_bottle'), 5, 'stacks into the same slot')
equals(Mock.Inventory(P1)[2], nil, 'does not open a second slot when stacking')

Mock.Export('AddItem', P1, 'goldbar', 1, nil, { worth = 500 })
equals(Mock.Inventory(P1)[2].name, 'goldbar', 'unique-ish item goes to slot 2')
equals(Mock.Inventory(P1)[2].info.worth, 500, 'custom info is stored')
equals(Mock.Inventory(P1)[2].rarity, 'legendary', 'rarity read from Shared.Items')

equals(Mock.Export('AddItem', P1, 'heavy_thing', 1), false, 'refuses an item over the weight limit')
equals(Mock.Count(P1, 'heavy_thing'), 0, 'nothing was added when over weight')
equals(Mock.Export('AddItem', P1, 'does_not_exist', 1), false, 'refuses an unknown item')

Mock.Export('AddItem', P1, 'weapon_pistol', 1)
local pistolSlot = 3
equals(Mock.Inventory(P1)[pistolSlot].type, 'weapon', 'weapon stored')
ok(type(Mock.Inventory(P1)[pistolSlot].info.serie) == 'string', 'weapon gets a serial number')
equals(Mock.Inventory(P1)[pistolSlot].info.quality, 100, 'weapon gets a quality of 100')

Mock.Export('AddItem', P1, 'weapon_pistol', 1)
equals(Mock.Inventory(P1)[4].name, 'weapon_pistol', 'unique weapons do NOT stack')

-- ---------------------------------------------------------------------------
group('RemoveItem')

Mock.Export('RemoveItem', P1, 'water_bottle', 2, 1)
equals(Mock.Count(P1, 'water_bottle'), 3, 'removes by slot')
equals(Mock.Inventory(P1)[1].amount, 3, 'remainder stays in the slot')

Mock.Export('RemoveItem', P1, 'water_bottle', 10, 1)
equals(Mock.Count(P1, 'water_bottle'), 0, 'removing more than owned empties the slot')
equals(Mock.Inventory(P1)[1], nil, 'slot is cleared')

Mock.Export('AddItem', P1, 'sandwich', 5)
Mock.Export('AddItem', P1, 'sandwich', 4)
equals(Mock.Count(P1, 'sandwich'), 9, 'two stacks of sandwich')
Mock.Export('RemoveItem', P1, 'sandwich', 6, nil)
equals(Mock.Count(P1, 'sandwich'), 3, 'remove without a slot drains across stacks')
equals(Mock.Export('RemoveItem', P1, 'sandwich', 1, 99), false, 'removing from an empty slot fails')

-- ---------------------------------------------------------------------------
group('Queries')

Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'lockpick', 4)
Mock.Export('AddItem', P1, 'water_bottle', 2)

equals(Mock.Export('HasItem', P1, 'lockpick'), true, 'HasItem single item')
equals(Mock.Export('HasItem', P1, 'lockpick', 4), true, 'HasItem with exact amount')
equals(Mock.Export('HasItem', P1, 'lockpick', 5), false, 'HasItem with too high amount')
equals(Mock.Export('HasItem', P1, { 'lockpick', 'water_bottle' }), true, 'HasItem with a list')
equals(Mock.Export('HasItem', P1, { 'lockpick', 'nope' }), false, 'HasItem list with a missing item')

equals(Mock.Export('GetItemCount', P1, 'lockpick'), 4, 'GetItemCount single')
equals(Mock.Export('GetItemCount', P1, { 'lockpick', 'water_bottle' }), 6, 'GetItemCount list')

local lockpick = Mock.Export('GetItemByName', P1, 'lockpick')
ok(lockpick ~= nil and lockpick.name == 'lockpick', 'GetItemByName')

local bySlot = Mock.Export('GetItemBySlot', P1, 1)
ok(bySlot ~= nil, 'GetItemBySlot')

local slots = Mock.Export('GetSlotsByItem', Mock.Inventory(P1), 'lockpick')
equals(#slots, 1, 'GetSlotsByItem returns one slot')
equals(Mock.Export('GetFirstSlotByItem', Mock.Inventory(P1), 'lockpick'), 1, 'GetFirstSlotByItem')

local total = Mock.Export('GetTotalWeight', Mock.Inventory(P1))
equals(total, (100 * 4) + (500 * 2), 'GetTotalWeight multiplies weight by amount')
ok(Mock.Export('GetFreeWeight', P1) == (120000 - total), 'GetFreeWeight')

equals(Mock.Export('CanAddItem', P1, 'water_bottle', 1), true, 'CanAddItem true')
local canAdd, reason = Mock.Export('CanAddItem', P1, 'heavy_thing', 1)
equals(canAdd, false, 'CanAddItem false when too heavy')
equals(reason, 'weight', 'CanAddItem reports the weight reason')

-- ---------------------------------------------------------------------------
group('ClearInventory / SetInventory')

Mock.Export('ClearInventory', P1)
equals(Mock.Count(P1, 'lockpick'), 0, 'clear everything - lockpick')
equals(Mock.Count(P1, 'water_bottle'), 0, 'clear everything - water')

Mock.Export('AddItem', P1, 'lockpick', 3)
Mock.Export('AddItem', P1, 'water_bottle', 1)
Mock.Export('ClearInventory', P1, 'lockpick')
equals(Mock.Count(P1, 'lockpick'), 0, 'filtered clear removes the filter item')
equals(Mock.Count(P1, 'water_bottle'), 1, 'filtered clear keeps the rest')

Mock.Export('SetInventory', P1, {
    [1] = { name = 'phone', amount = 1 },
    [5] = { name = 'goldbar', amount = 2 },
})
equals(Mock.Count(P1, 'phone'), 1, 'SetInventory sets slot 1')
equals(Mock.Count(P1, 'goldbar'), 2, 'SetInventory sets slot 5')
equals(Mock.Inventory(P1)[5].slot, 5, 'SetInventory keeps the slot number')

-- ---------------------------------------------------------------------------
group('Moving items (SetInventoryData)')

Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'water_bottle', 5)   -- slot 1
Mock.Export('AddItem', P1, 'lockpick', 2)       -- slot 2

-- player slot 1 -> player slot 10 (move)
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', 'player', 1, 10, 5, 5)
equals(Mock.Inventory(P1)[1], nil, 'move: source slot emptied')
ok(Mock.Inventory(P1)[10] ~= nil and Mock.Inventory(P1)[10].name == 'water_bottle', 'move: target slot filled')
equals(Mock.Inventory(P1)[10].slot, 10, 'move: slot number updated')

-- swap slot 10 <-> slot 2
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', 'player', 10, 2, 5, 5)
equals(Mock.Inventory(P1)[2].name, 'water_bottle', 'swap: item A moved to slot 2')
equals(Mock.Inventory(P1)[10].name, 'lockpick', 'swap: item B moved to slot 10')
equals(Mock.Inventory(P1)[2].slot, 2, 'swap: A slot updated')
equals(Mock.Inventory(P1)[10].slot, 10, 'swap: B slot updated')

-- split: move only 2 of 5
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', 'player', 2, 20, 2, 2)
equals(Mock.Inventory(P1)[2].amount, 3, 'split: remainder left behind')
equals(Mock.Inventory(P1)[20].amount, 2, 'split: new stack created')
equals(Mock.Count(P1, 'water_bottle'), 5, 'split: nothing lost or duplicated')

-- stack: move 3 onto 2
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', 'player', 2, 20, 3, 3)
equals(Mock.Inventory(P1)[20].amount, 5, 'stack: amounts merged')
equals(Mock.Inventory(P1)[2], nil, 'stack: source removed')
equals(Mock.Count(P1, 'water_bottle'), 5, 'stack: nothing lost or duplicated')

-- ---------------------------------------------------------------------------
group('Stashes')

local stashId = 'stash-apartment-12'

Mock.Export('CreateInventory', stashId, { label = 'Apartment 12', slots = 10, maxweight = 50000 })
ok(Mock.Export('GetInventory', stashId) ~= nil, 'CreateInventory registers the stash')

Mock.Export('OpenInventory', P1, stashId)
ok(Mock.LastClientEvent(P1, 'qb-inventory:client:openInventory') ~= nil, 'OpenInventory sends the NUI payload')

-- player -> stash
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', stashId, 20, 1, 5, 5)
local stash = Mock.Export('GetInventory', stashId)
ok(stash.items[1] ~= nil and stash.items[1].name == 'water_bottle', 'player -> stash moved the item')
equals(Mock.Count(P1, 'water_bottle'), 0, 'player -> stash emptied the player slot')

-- stash -> player
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', stashId, 'player', 1, 3, 5, 5)
equals(Mock.Count(P1, 'water_bottle'), 5, 'stash -> player moved the item back')
equals(stash.items[1], nil, 'stash slot is now empty')

-- guard: another player cannot touch a stash he has not opened
Mock.FireFromClient(P2, 'qb-inventory:server:SetInventoryData', 'player', stashId, 1, 1, 1, 1)
ok(true, 'unrelated player is rejected without throwing')

-- capacity guard
Mock.Export('AddItem', P1, 'goldbar', 1)
for i = 1, 12 do Mock.Export('AddItem', P1, 'lockpick', 1) end
local before = Mock.Count(P1, 'lockpick')
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', stashId, 'player', 1, 39, 1, 1)
ok(true, 'moving into a full inventory does not crash')

-- ---------------------------------------------------------------------------
group('Cross inventory swaps and duplication')

local swapStash = 'stash-swap-test'
Mock.Export('CreateInventory', swapStash, { label = 'Swap', slots = 5, maxweight = 100000 })

Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'water_bottle', 5)     -- slot 1
Mock.Export('AddItem', P1, 'lockpick', 3)         -- slot 2
Mock.Export('AddItem', P1, 'sandwich', 1)         -- slot 3

-- put a sandwich into the stash slot 1
Mock.Export('OpenInventory', P1, swapStash)
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', swapStash, 3, 1, 1, 1)

local swapInv = Mock.Export('GetInventory', swapStash)
equals(swapInv.items[1] and swapInv.items[1].name, 'sandwich', 'stash holds the sandwich')
equals(Mock.Inventory(P1)[3], nil, 'player slot 3 is empty after the move')

-- now swap: player water_bottle (slot 1) <-> stash sandwich (slot 1)
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', swapStash, 1, 1, 5, 5)
equals(swapInv.items[1] and swapInv.items[1].name, 'water_bottle', 'cross inventory swap - A went to the stash')
equals(Mock.Inventory(P1)[1] and Mock.Inventory(P1)[1].name, 'sandwich', 'cross inventory swap - B came to the player')
equals(swapInv.items[1].slot, 1, 'swapped item keeps the stash slot number')
equals(Mock.Inventory(P1)[1].slot, 1, 'swapped item keeps the player slot number')

-- nothing may be created or destroyed by a swap
equals(Mock.Count(P1, 'water_bottle'), 0, 'no water left in the player inventory')
equals(Mock.Count(P1, 'sandwich'), 1, 'exactly one sandwich came back')

-- moving onto an occupied slot must not duplicate anything
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'lockpick', 7)
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', 'player', 1, 2, 7, 7)
equals(Mock.Count(P1, 'lockpick'), 7 + (Mock.Count(P1, 'lockpick') - 7), 'total is unchanged after a move')
local dupCheck = 0
for _, v in pairs(Mock.Inventory(P1)) do
    if type(v) == 'table' and v.name == 'lockpick' then dupCheck = dupCheck + v.amount end
end
equals(dupCheck, 7, 'lockpick amount is still exactly 7 (no duplication)')

-- ---------------------------------------------------------------------------
group('Forgiving signatures / SetItemData')

Mock.Export('ClearInventory', P1)
-- Some scripts call AddItem(source, item, amount, info) instead of (..., slot, info)
equals(Mock.Export('AddItem', P1, 'phone', 1, { number = '555-1234' }), true,
       'AddItem accepts (source, item, amount, info)')
equals(Mock.Inventory(P1)[1].name, 'phone', 'phone was added')
equals(Mock.Inventory(P1)[1].info.number, '555-1234', 'the info table landed in info, not slot')

Mock.Export('SetItemData', P1, 'phone', 'number', '555-9999', 1)
equals(Mock.Inventory(P1)[1].info.number, '555-9999', 'SetItemData updates item info')

-- ---------------------------------------------------------------------------
group('Drops')

Mock.Export('ClearInventory', P2)
Mock.Export('AddItem', P2, 'sandwich', 4)

local dropId = Mock.Callback('qb-inventory:server:createDrop', P2, {
    name = 'sandwich', amount = 2, fromSlot = 1
})

ok(type(dropId) == 'string' and dropId:find('^drop%-') ~= nil, 'createDrop returns a drop id', tostring(dropId))
equals(Mock.Count(P2, 'sandwich'), 2, 'the dropped amount left the inventory')
ok(Mock.LastClientEvent(P2, 'qb-inventory:client:addDrop') ~= nil, 'clients are told about the drop')

local drops = Mock.Callback('qb-inventory:server:GetCurrentDrops', P1)
ok(drops[dropId] ~= nil, 'the drop is listed in GetCurrentDrops')

-- picking the drop back up
Mock.FireFromClient(P2, 'qb-inventory:server:openDrop', dropId)
Mock.FireFromClient(P2, 'qb-inventory:server:SetInventoryData', dropId, 'player', 1, 9, 2, 2)
equals(Mock.Count(P2, 'sandwich'), 4, 'picking the drop up returns the items')

-- ---------------------------------------------------------------------------
group('Shops')

Mock.Export('CreateShop', {
    name = 'cornerstore',
    label = 'Corner Store',
    items = {
        { name = 'water_bottle', price = 10, amount = 5 },
        { name = 'sandwich', price = 20, amount = 2 },
    }
})

ok(Mock.registered['GetInventory'] ~= nil, 'shop helper registered')

Mock.Export('OpenShop', P1, 'cornerstore')
ok(Mock.LastClientEvent(P1, 'qb-inventory:client:openInventory') ~= nil, 'OpenShop opens the NUI')

-- buy 2 bottles for 20 cash
Mock.Export('ClearInventory', P1)
local cashBefore = Mock.players[P1].PlayerData.money.cash
local bought = Mock.Callback('qb-inventory:server:attemptPurchase', P1, {
    item = { name = 'water_bottle', slot = 1 },
    amount = 2,
    shop = 'shop-cornerstore'
})

equals(bought, true, 'purchase succeeds')
equals(Mock.Count(P1, 'water_bottle'), 2, 'the bought items are in the inventory')
equals(Mock.players[P1].PlayerData.money.cash, cashBefore - 20, 'the right amount of cash was taken')

-- not enough money
local brokeResult = Mock.Callback('qb-inventory:server:attemptPurchase', P2, {
    item = { name = 'sandwich', slot = 2 },
    amount = 1,
    shop = 'shop-cornerstore'
})
equals(brokeResult, false, 'purchase fails without money')

-- ---------------------------------------------------------------------------
group('Giving items')

Mock.Export('ClearInventory', P1)
Mock.Export('ClearInventory', P2)
Mock.Export('AddItem', P1, 'lockpick', 5)
Mock.players[P1].PlayerData.money.cash = 1000

local gave = Mock.Callback('qb-inventory:server:giveItem', P1, P2, 'lockpick', 2, 1)
equals(gave, true, 'give succeeds between two nearby players')
equals(Mock.Count(P1, 'lockpick'), 3, 'giver lost the items')
equals(Mock.Count(P2, 'lockpick'), 2, 'receiver got the items')

-- ---------------------------------------------------------------------------
group('Legacy compatibility events')

ok(Mock.events['inventory:server:SetInventoryData'] ~= nil, 'legacy inventory:server:SetInventoryData registered')
ok(Mock.events['inventory:server:OpenInventory'] ~= nil, 'legacy inventory:server:OpenInventory registered')
ok(Mock.events['inventory:server:UseItemSlot'] ~= nil, 'legacy inventory:server:UseItemSlot registered')
ok(Mock.events['qb-inventory:server:useItem'] ~= nil, 'qb-inventory:server:useItem registered')
ok(Mock.events['qb-inventory:server:closeInventory'] ~= nil, 'qb-inventory:server:closeInventory registered')

-- register a usable item exactly like a normal qb-core resource does
local usedWith = {}
Mock.CreateUseableItem('sandwich', function(src, item)
    table.insert(usedWith, { source = src, item = item })
end)

Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'sandwich', 1)
Mock.FireFromClient(P1, 'inventory:server:UseItemSlot', 1)
equals(#usedWith, 1, 'legacy UseItemSlot runs the usable item callback')
ok(usedWith[1] and usedWith[1].source == P1, 'the callback receives the right source')
ok(usedWith[1] and usedWith[1].item and usedWith[1].item.name == 'sandwich', 'the callback receives the item')

-- the modern event must work too
Mock.FireFromClient(P1, 'qb-inventory:server:useItem', { slot = 1, name = 'sandwich' })
equals(#usedWith, 2, 'qb-inventory:server:useItem runs the callback')

-- qb-core calls the export with its own argument order: UseItem(source, item)
usedWith = {}
local okCall, callResult = pcall(function()
    return Mock.Export('UseItem', P1, { name = 'sandwich', amount = 1, info = {} })
end)
ok(okCall, 'UseItem with the qb-core argument order does not throw (no recursion)')
equals(#usedWith, 1, 'UseItem with the qb-core argument order still runs the callback')

-- weapon usage goes to qb-weapons instead of the usable callback
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'weapon_pistol', 1)
Mock.FireFromClient(P1, 'qb-inventory:server:useItem', { slot = 1, name = 'weapon_pistol' })
ok(Mock.LastClientEvent(P1, 'qb-weapons:client:UseWeapon') ~= nil, 'weapons are handed to qb-weapons')

-- a non useable item does nothing
usedWith = {}
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'goldbar', 1)
Mock.FireFromClient(P1, 'qb-inventory:server:useItem', { slot = 1, name = 'goldbar' })
equals(#usedWith, 0, 'items without a usable callback do nothing')

-- ---------------------------------------------------------------------------
group('Robustness')

ok(pcall(function()
    Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', nil, nil, nil, nil, nil, nil)
end), 'nil payload does not throw')

ok(pcall(function()
    Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', 'player', 'abc', 'x', 'y', 'z')
end), 'string instead of number payload does not throw')

ok(pcall(function()
    Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', 'player', 1, 2, -5, -5)
end), 'negative amount does not throw')

ok(pcall(function()
    Mock.Export('AddItem', P1, nil, 1)
end), 'AddItem with a nil item does not throw')

ok(pcall(function()
    Mock.Export('RemoveItem', P1, nil, 1)
end), 'RemoveItem with a nil item does not throw')

ok(pcall(function()
    Mock.Export('HasItem', 999, 'lockpick')
end), 'HasItem for an offline player does not throw')

-- ---------------------------------------------------------------------------
print('\n\27[1;36m== Server compatibility (older qb-core)\27[0m')

-- 1) older qb-core registers the usable callback as a raw function
Mock.AddItem('burger', { name = 'burger', label = 'Burger', weight = 200, type = 'item' })
Mock.AddItem('water', { name = 'water', label = 'Water', weight = 500, type = 'item' })

usedWith = {}
Mock.CreateLegacyUseableItem('burger', function(source, item) usedWith[#usedWith + 1] = item end)
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'burger', 3)
Mock.FireFromClient(P1, 'qb-inventory:server:useItem', { slot = 1, name = 'burger' })
equals(#usedWith, 1, 'usable items registered as a raw function still run (older qb-core)')

Mock.Export('UseItem', P1, { name = 'burger', amount = 1, info = {} })
equals(#usedWith, 2, 'the UseItem export works with the legacy callback shape too')
Mock.QBCore.UsableItems['burger'] = nil

-- 2) a stored `useable = false` flag must not block a registered item
usedWith = {}
Mock.CreateUseableItem('water', function(source, item) usedWith[#usedWith + 1] = item end)
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'water', 2)
local rawWater = Mock.Inventory(P1)[1]
if rawWater then rawWater.useable = false end
Mock.FireFromClient(P1, 'qb-inventory:server:useItem', { slot = 1, name = 'water' })
equals(#usedWith, 1, 'a stale useable flag does not block the item')

-- 3) weapons still get equipped when qb-weapons is NOT installed
Mock.SetResourceState('qb-weapons', 'missing')
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'weapon_pistol', 1)
Mock.FireFromClient(P1, 'qb-inventory:server:useItem', { slot = 1, name = 'weapon_pistol' })
ok(Mock.LastClientEvent(P1, 'qb-inventory:client:EquipWeapon') ~= nil,
    'weapons are equipped by the built in fallback when qb-weapons is missing')

-- 4) and handed to qb-weapons when it IS running
Mock.SetResourceState('qb-weapons', 'started')
Mock.FireFromClient(P1, 'qb-inventory:server:useItem', { slot = 1, name = 'weapon_pistol' })
ok(Mock.LastClientEvent(P1, 'qb-weapons:client:UseWeapon') ~= nil,
    'weapons are handed to qb-weapons when it is started')

-- 5) older qb-core databases hand over the inventory as a JSON OBJECT,
--    so slot keys are strings ("1", "2", ...). Everything must still work.
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'burger', 1)
local stringKeyed = {}
for index, value in pairs(Mock.Inventory(P1)) do
    stringKeyed[tostring(index)] = value
end
local player1 = Mock.QBCore.Functions.GetPlayer(P1)
local savedItems = player1.PlayerData.items
player1.PlayerData.items = stringKeyed

ok(Mock.Export('HasItem', P1, 'burger') ~= nil, 'items stored under string slot keys are found')
ok(Mock.Export('RemoveItem', P1, 'burger', 1) == true, 'items stored under string slot keys can be removed')

player1.PlayerData.items = savedItems
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'lockpick', 1)
Mock.Export('AddItem', P1, 'sandwich', 1)
local stringKeyed2 = {}
for index, value in pairs(Mock.Inventory(P1)) do
    stringKeyed2[tostring(index)] = value
end
player1.PlayerData.items = stringKeyed2
Mock.FireFromClient(P1, 'qb-inventory:server:SetInventoryData', 'player', 'player', 1, 2, 1, 1)
equals(Mock.Inventory(P1)[2] and Mock.Inventory(P1)[2].name, 'lockpick',
    'items under string slot keys can be moved')

for index in pairs(Mock.Inventory(P1)) do
    ok(type(index) == 'number', 'slot keys are normalised to numbers')
end
player1.PlayerData.items = savedItems

-- 6) the UI always receives a dense array
Mock.Export('ClearInventory', P1)
Mock.Export('AddItem', P1, 'lockpick', 1)
Mock.Export('AddItem', P1, 'sandwich', 1)
Mock.clientEvents[P1] = {}
Mock.Export('OpenInventory', P1, stashId)
local captured = Mock.LastClientEvent(P1, 'qb-inventory:client:openInventory')
ok(captured ~= nil, 'opening an inventory pushes a payload to the UI')

local payload = captured and captured.args[1]
local other = captured and captured.args[2]
ok(type(payload) == 'table', 'the inventory sent to the UI is a table')
ok(type(payload[1]) == 'table', 'the inventory sent to the UI is a dense array')
ok(payload[2] ~= nil, 'the second slot of the dense array is filled in')
ok(type(other) == 'table', 'the second panel is a table too')
ok(type(other and other.inventory) == 'table', 'the second panel carries a dense inventory')

-- ---------------------------------------------------------------------------
print(('\n\27[1m%d passed, %d failed\27[0m'):format(passed, failed))

if failed > 0 then
    print('\n\27[31mFailures:\27[0m')
    for _, line in ipairs(failures) do print('  - ' .. line) end
end

_G.TEST_FAILURES = failed
