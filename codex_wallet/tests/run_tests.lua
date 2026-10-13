--[[
    codex_wallet - automated test suite

    Runs the REAL server/main.lua + client/main.lua against a mocked FiveM
    runtime and asserts the full behaviour: money conservation, whitelist
    enforcement, wallet-in-wallet prevention, presentation, rate limiting,
    logging and more.

    python3 tests/run_lua_tests.py      (or)  lua tests/run_tests.lua
]]

TEST_FAILURES = 0
TEST_PASSES = 0

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        TEST_FAILURES = TEST_FAILURES + 1
        print(('  [FAIL] %s\n         expected: %s\n         actual:   %s')
            :format(label, tostring(expected), tostring(actual)))
    else
        TEST_PASSES = TEST_PASSES + 1
    end
end

local function assertTrue(value, label)
    assertEqual(value and true or false, true, label)
end

local function assertFalse(value, label)
    assertEqual(value and true or false, false, label)
end

local function section(name)
    print('\n== ' .. name .. ' ==')
end

-- ---------------------------------------------------------------------------
-- Boot the mocked runtime and load the resource
-- ---------------------------------------------------------------------------
local Mock = dofile('tests/mock_fivem.lua')

dofile('config.lua')

-- Quiet logging during tests but keep the file destination active.
Config.Logging.Level = 'DEBUG'
Config.Logging.Console = false

Logger = dofile('server/logger.lua')
Storage = dofile('server/storage.lua')

-- Make sure we exercise the oxmysql path first.
Storage.SetDatabaseMode(true)
Mock.db = {}

local server = dofile('server/main.lua')
Mock.runReady()

-- Helpers -------------------------------------------------------------------
local RESOURCE = 'codex_wallet'

local function act(src, action, data, skipTick)
    if not skipTick then
        Mock.tick(400) -- pass the rate limiter
    end
    Mock.netTrigger(src, RESOURCE .. ':action', action, data or {})
end

local function openWallet(src)
    Mock.tick(400)
    Mock.netTrigger(src, RESOURCE .. ':useWallet')
end

local function lastNotification()
    return Mock.notifications[#Mock.notifications]
end

local function walletSerial(src)
    local item = Mock.getItem(src, 'codex_wallet')
    return item and item.info and item.info.serial
end

local function makeWalletPlayer(id, options)
    options = options or {}

    local items = options.items or {
        [1] = { name = 'codex_wallet', amount = 1, slot = 1, info = { serial = ('CXW-TEST%d'):format(id) } }
    }

    return Mock.makePlayer(id, {
        items = items,
        cash = options.cash or 0,
        coords = options.coords or { x = 0.0, y = 0.0, z = 0.0 },
        citizenid = options.citizenid,
        charinfo = options.charinfo
    })
end

--- Give inventory cash items (item money mode).
local function giveCash(src, amount)
    return Mock.players[src].Functions.AddItem(Config.Money.ItemName, amount, false, nil)
end

--- Cash the player holds OUTSIDE the wallet (inventory cash items only -
--- the wallet is never linked to a bank/money account).
local function playerMoney(src)
    return Mock.countItems(src, Config.Money.ItemName)
end

local function dbWallet(serial)
    local row = Mock.db[serial]
    if not row then
        return nil
    end

    return {
        serial = row.serial,
        cash = tonumber(row.cash) or 0,
        items = (row.items and row.items ~= '') and json.decode(row.items) or {},
        owner = row.owner
    }
end

local function totalMoney(src, serial)
    local row = dbWallet(serial)
    return playerMoney(src) + (row and row.cash or 0)
end

-- ---------------------------------------------------------------------------
section('1. Boot & registration')
-- ---------------------------------------------------------------------------
assertTrue(Mock.useable['codex_wallet'] ~= nil, 'useable item registered')
assertTrue(Mock.commands['wallet'] ~= nil, 'wallet command registered')
assertTrue(Mock.commands['wallettest'] ~= nil, 'wallettest command registered')
assertTrue(type(server.OpenWallet) == 'function', 'server export table loads')
assertTrue(Mock.files['logs/wallet.log'] ~= nil, 'log file created on boot')
assertTrue(Mock.files['logs/wallet.log']:find('boot') ~= nil, 'boot entry logged')

-- ---------------------------------------------------------------------------
section('2. Opening the wallet')
-- ---------------------------------------------------------------------------
makeWalletPlayer(1, { cash = 5000 })
Mock.resetTraces()

Mock.useable['codex_wallet'](1)

local event = Mock.lastClientEvent('openWallet')
assertTrue(event ~= nil, 'openWallet event sent to client')
assertEqual(event.target, 1, 'openWallet sent to the right player')
assertEqual(event.args[1].wallet.serial, 'CXW-TEST1', 'wallet serial in payload')
assertEqual(event.args[1].wallet.cash, 0, 'new wallet starts empty')
assertEqual(event.args[1].player.name, 'John Doe', 'player name in payload')
assertEqual(event.args[1].wallet.slotsMax, Config.Wallet.Slots, 'slot limit in payload')
assertTrue(event.args[1].brand.Name == 'CodeX Wallet', 'branding says CodeX Wallet')

-- command opens it too
Mock.resetTraces()
openWallet(1)
event = Mock.lastClientEvent('openWallet')
assertTrue(event ~= nil, 'wallet command opens the wallet')

-- auto-serial assignment ---------------------------------------------------
Mock.makePlayer(2, {
    items = {
        [1] = { name = 'codex_wallet', amount = 1, slot = 1, info = nil }
    },
    cash = 0
})
Mock.resetTraces()
openWallet(2)

local assigned = walletSerial(2)
assertTrue(assigned ~= nil, 'missing serial is auto-assigned')
assertTrue(tostring(assigned):find('CXW') == 1, 'assigned serial has CXW prefix')
event = Mock.lastClientEvent('openWallet')
assertEqual(event.args[1].wallet.serial, assigned, 'payload uses the assigned serial')
assertTrue(dbWallet(assigned) ~= nil, 'wallet row created in database')

-- ---------------------------------------------------------------------------
section('3. Cash: inventory <-> wallet (inventory only)')
-- ---------------------------------------------------------------------------
assertEqual(Config.Money.ItemName, 'cash', 'cash is an inventory item (no bank link)')
assertTrue(Config.Money.Account == nil and Config.Money.Mode == nil, 'no account/bank mode configured')

makeWalletPlayer(1, {})
giveCash(1, 5000)
assertEqual(Mock.countItems(1, Config.Money.ItemName), 5000, 'player starts with cash items in inventory')

Mock.resetTraces()
local serial = walletSerial(1)

act(1, 'deposit', { amount = 1000 })
assertEqual(Mock.countItems(1, Config.Money.ItemName), 4000, 'cash items taken from inventory on deposit')
assertEqual(dbWallet(serial).cash, 1000, 'cash added to wallet on deposit')
assertEqual(totalMoney(1, serial), 5000, 'total money conserved after deposit')
assertEqual(lastNotification().message, 'You deposited $1,000 into your wallet.', 'deposit notification formatted')

act(1, 'withdraw', { amount = 400 })
assertEqual(Mock.countItems(1, Config.Money.ItemName), 4400, 'cash items returned to inventory on withdraw')
assertEqual(dbWallet(serial).cash, 600, 'cash removed from wallet on withdraw')
assertEqual(totalMoney(1, serial), 5000, 'total money conserved after withdraw')

-- deposit across multiple stacks
Mock.players[1].Functions.AddItem(Config.Money.ItemName, 300, false, nil) -- second stack
assertEqual(Mock.countItems(1, Config.Money.ItemName), 4700, 'second cash stack added')

act(1, 'deposit', { amount = 4000 })
assertEqual(Mock.countItems(1, Config.Money.ItemName), 700, 'deposit drained across multiple cash stacks')
assertEqual(dbWallet(serial).cash, 4600, 'wallet received the multi-stack deposit')

-- withdraw everything possible with one action
act(1, 'withdraw', { amount = 4600 })
assertEqual(dbWallet(serial).cash, 0, 'wallet emptied on full withdraw')
assertEqual(Mock.countItems(1, Config.Money.ItemName), 5300, 'all withdrawn cash back in inventory')
assertEqual(totalMoney(1, serial), 5300, 'total money conserved across multi-stack flow')

-- invalid amounts -----------------------------------------------------------
local before = totalMoney(1, serial)

act(1, 'deposit', { amount = -500 })
assertEqual(totalMoney(1, serial), before, 'negative deposit rejected')

act(1, 'deposit', { amount = 0 })
assertEqual(totalMoney(1, serial), before, 'zero deposit rejected')

act(1, 'deposit', { amount = 'abc' })
assertEqual(totalMoney(1, serial), before, 'non-numeric deposit rejected')

act(1, 'deposit', {})
assertEqual(totalMoney(1, serial), before, 'missing amount rejected')

act(1, 'deposit', { amount = 999999999 })
assertEqual(totalMoney(1, serial), before, 'over per-op limit deposit rejected')

act(1, 'withdraw', { amount = 99999 })
assertEqual(totalMoney(1, serial), before, 'withdraw above wallet balance rejected')

-- player cannot deposit more cash than they hold
act(1, 'deposit', { amount = 100000 })
assertEqual(totalMoney(1, serial), before, 'deposit above player cash rejected')

-- balance cap ---------------------------------------------------------------
act(1, 'deposit', { amount = Config.Money.MaxBalance })
assertEqual(totalMoney(1, serial), before, 'deposit above wallet MaxBalance rejected')

-- ---------------------------------------------------------------------------
section('4. Storing documents')
-- ---------------------------------------------------------------------------
Mock.giveItem(1, 'id_card', { firstname = 'Jane', lastname = 'Doe', birthdate = '1990-01-01' })

local idSlot = Mock.getItem(1, 'id_card').slot

act(1, 'storeItem', { slot = idSlot })
assertEqual(Mock.countItems(1, 'id_card'), 0, 'id_card removed from inventory on store')
assertEqual(#dbWallet(serial).items, 1, 'id_card stored inside wallet')
assertEqual(dbWallet(serial).items[1].name, 'id_card', 'stored entry keeps item name')
assertEqual(dbWallet(serial).items[1].metadata.firstname, 'Jane', 'stored entry keeps metadata')

-- whitelist enforcement ----------------------------------------------------
Mock.giveItem(1, 'burger', { fresh = true })
local burgerSlot = Mock.getItem(1, 'burger').slot

act(1, 'storeItem', { slot = burgerSlot })
assertEqual(Mock.countItems(1, 'burger'), 1, 'non-whitelisted item rejected')
assertEqual(#dbWallet(serial).items, 1, 'wallet unchanged after rejected store')

-- wallet-in-wallet ---------------------------------------------------------
assertTrue(Config.Wallet.PreventWalletInWallet, 'wallet-in-wallet prevention enabled')
assertTrue(Config.AllowedItems[Config.WalletItem] == nil, 'wallet is not a whitelisted item')

Mock.giveItem(1, 'codex_wallet', { serial = 'CXW-NESTED' })
local nestedSlot = Mock.getItem(1, 'codex_wallet').slot
-- grab the NESTED wallet slot (not the primary one at slot 1)
for slot, item in pairs(Mock.players[1].PlayerData.items) do
    if item.name == 'codex_wallet' and item.info and item.info.serial == 'CXW-NESTED' then
        nestedSlot = slot
        break
    end
end

act(1, 'storeItem', { slot = nestedSlot })
assertEqual(Mock.countItems(1, 'codex_wallet'), 2, 'wallet cannot be stored inside a wallet')

-- duplicates ----------------------------------------------------------------
Mock.giveItem(1, 'id_card', { firstname = 'Jane', lastname = 'Doe' })
local secondIdSlot = Mock.getItem(1, 'id_card').slot
act(1, 'storeItem', { slot = secondIdSlot })
assertEqual(#dbWallet(serial).items, 1, 'duplicate document rejected while PreventDuplicates is on')
assertEqual(Mock.countItems(1, 'id_card'), 1, 'duplicate document stays in inventory')

-- clean up the rejected duplicate so later counts stay simple
Mock.players[1].PlayerData.items[secondIdSlot] = nil

-- slot limit ---------------------------------------------------------------
local savedSlots = Config.Wallet.Slots
Config.Wallet.Slots = 2

Mock.giveItem(1, 'driver_license', {})
Mock.giveItem(1, 'weaponlicense', {})
local dlSlot = Mock.getItem(1, 'driver_license').slot
local wlSlot = Mock.getItem(1, 'weaponlicense').slot

act(1, 'storeItem', { slot = dlSlot })
assertEqual(#dbWallet(serial).items, 2, 'second document stored')

act(1, 'storeItem', { slot = wlSlot })
assertEqual(#dbWallet(serial).items, 2, 'third document rejected when wallet is full')
assertEqual(Mock.countItems(1, 'weaponlicense'), 1, 'rejected document stays in inventory')

Config.Wallet.Slots = savedSlots

-- weight limit --------------------------------------------------------------
local savedWeight = Config.Wallet.MaxWeight
Config.Wallet.MaxWeight = 60 -- id_card (50) fits, +50 more does not

act(1, 'storeItem', { slot = wlSlot })
assertEqual(#dbWallet(serial).items, 2, 'overweight store rejected')
assertEqual(Mock.countItems(1, 'weaponlicense'), 1, 'overweight document stays in inventory')

Config.Wallet.MaxWeight = savedWeight

-- ---------------------------------------------------------------------------
section('5. Removing documents')
-- ---------------------------------------------------------------------------
act(1, 'removeItem', { index = 1 })
assertEqual(#dbWallet(serial).items, 1, 'document removed from wallet')
assertEqual(Mock.countItems(1, 'id_card'), 1, 'document returned to inventory')

local returned = Mock.getItem(1, 'id_card')
assertTrue(returned ~= nil, 'returned document exists')
assertEqual(returned.info.firstname, 'Jane', 'returned document keeps its metadata')

act(1, 'removeItem', { index = 99 })
assertEqual(#dbWallet(serial).items, 1, 'invalid remove index rejected')

-- ---------------------------------------------------------------------------
section('6. Presenting documents')
-- ---------------------------------------------------------------------------
Mock.makePlayer(3, {
    items = { [1] = { name = 'codex_wallet', amount = 1, slot = 1, info = { serial = 'CXW-TEST3' } } },
    coords = { x = 1.0, y = 1.0, z = 0.0 }
})
Mock.makePlayer(4, {
    items = { [1] = { name = 'codex_wallet', amount = 1, slot = 1, info = { serial = 'CXW-TEST4' } } },
    coords = { x = 2.0, y = 2.0, z = 0.0 }
})
Mock.makePlayer(5, {
    items = { [1] = { name = 'codex_wallet', amount = 1, slot = 1, info = { serial = 'CXW-TEST5' } } },
    coords = { x = 500.0, y = 500.0, z = 0.0 }
})

-- player 1 still holds the id_card in inventory - store it again first
local idSlot2 = Mock.getItem(1, 'id_card').slot
act(1, 'storeItem', { slot = idSlot2 })

Mock.resetTraces()
act(1, 'showItem', { index = #dbWallet(serial).items })

local presented = 0
local presentedFar = false
local cardPayload = nil

for _, evt in ipairs(Mock.clientEvents) do
    if evt.name:find('presentCard') then
        presented = presented + 1
        if evt.target == 5 then
            presentedFar = true
        end
        if evt.target == 3 then
            cardPayload = evt.args[1]
        end
    end
end

assertTrue(presented >= 2, 'nearby players received the presented card')
assertFalse(presentedFar, 'far away player did not receive the card')
assertTrue(cardPayload ~= nil, 'card payload captured')
assertEqual(cardPayload.firstName, 'Jane', 'card shows metadata first name')
assertEqual(cardPayload.lastName, 'Doe', 'card shows metadata last name')
assertEqual(cardPayload.cardType, 'id_card', 'card keeps the document type')
assertEqual(cardPayload.presenterName, nil, 'presenter name is a separate argument')
assertEqual(Mock.lastClientEvent('presentCard').args[3], 'John Doe', 'presenter name passed along')

-- ---------------------------------------------------------------------------
section('7. Security: spoofed events, missing wallet, unknown actions')
-- ---------------------------------------------------------------------------
-- player without a wallet
Mock.makePlayer(6, {
    items = {},
    cash = 100
})
Mock.resetTraces()
openWallet(6)
assertEqual(Mock.lastClientEvent('openWallet'), nil, 'player without wallet cannot open one')
assertTrue(lastNotification() ~= nil and lastNotification().message == Config.Notifications.NoWallet, 'no-wallet notification sent')

act(6, 'deposit', { amount = 50 })
assertEqual(Mock.players[6].PlayerData.money.cash, 100, 'actions without wallet item rejected')

-- drop the wallet, cached actions must fail
Mock.players[1].PlayerData.items[1] = nil
for slot, item in pairs(Mock.players[1].PlayerData.items) do
    if item.name == 'codex_wallet' then
        Mock.players[1].PlayerData.items[slot] = nil
    end
end

local beforeHijack = dbWallet(serial).cash
act(1, 'withdraw', { amount = 100 })
assertEqual(dbWallet(serial).cash, beforeHijack, 'actions rejected after wallet item is gone')

-- unknown action must not crash
act(1, 'hack', { amount = 100 })
assertTrue(true, 'unknown action ignored without crash')

-- restore wallet for player 1
Mock.giveItem(1, 'codex_wallet', { serial = serial })

-- ---------------------------------------------------------------------------
section('8. Rate limiting')
-- ---------------------------------------------------------------------------
makeWalletPlayer(7, {})
giveCash(7, 1000)
Mock.resetTraces()

-- two actions with no time in between
Mock.netTrigger(7, RESOURCE .. ':action', 'deposit', { amount = 10 })
Mock.netTrigger(7, RESOURCE .. ':action', 'deposit', { amount = 10 })

assertTrue(lastNotification() ~= nil and lastNotification().message == Config.Notifications.Cooldown, 'second rapid action hits the cooldown')

-- after waiting it works again
act(7, 'deposit', { amount = 10 })
assertEqual(dbWallet(walletSerial(7)).cash, 20, 'action works again after cooldown (10 + 10 kept)')

-- ---------------------------------------------------------------------------
section('9. Logging & webhook')
-- ---------------------------------------------------------------------------
local logContent = Mock.files['logs/wallet.log'] or ''
assertTrue(logContent:find('deposit', 1, true) ~= nil, 'deposit action logged')
assertTrue(logContent:find('store', 1, true) ~= nil, 'store action logged')
assertTrue(logContent:find('WARN', 1, true) ~= nil, 'warnings logged')
assertTrue(logContent:find('CXW-TEST1', 1, true) ~= nil, 'wallet serials logged')

Config.Logging.Webhook = 'https://discord.test/webhook'
Mock.resetTraces()

act(7, 'deposit', { amount = 25 })
assertTrue(#Mock.httpRequests > 0, 'discord webhook request sent')
assertEqual(Mock.httpRequests[1].method, 'POST', 'webhook uses POST')
assertTrue(Mock.httpRequests[1].body:find('deposit', 1, true) ~= nil, 'webhook payload carries the event')
Config.Logging.Webhook = ''

-- level filtering -----------------------------------------------------------
Config.Logging.Level = 'ERROR'
Mock.resetTraces()
act(7, 'deposit', { amount = 5 })
assertTrue(#Mock.httpRequests == 0, 'INFO events suppressed at ERROR level')
Config.Logging.Level = 'DEBUG'

-- ---------------------------------------------------------------------------
section('10. Test kit & commands')
-- ---------------------------------------------------------------------------
Mock.makePlayer(8, { items = {}, cash = 0 })
Mock.permissions[8] = { admin = true }
Mock.resetTraces()

Mock.tick(400)
Mock.commands['wallettest'](8, {})

assertEqual(Mock.countItems(8, 'codex_wallet'), 1, 'test kit gives a wallet')
assertEqual(Mock.countItems(8, 'id_card'), 1, 'test kit gives an ID card')
assertEqual(Mock.countItems(8, 'driver_license'), 1, 'test kit gives a driver licence')
assertEqual(Mock.countItems(8, 'weaponlicense'), 1, 'test kit gives a weapon licence')
assertEqual(Mock.countItems(8, 'bank_card'), 1, 'test kit gives a bank card')
assertEqual(Mock.countItems(8, Config.Money.ItemName), 5000, 'test kit gives $5,000 cash as inventory items')

-- non-admin cannot use it
Mock.makePlayer(9, { items = {}, cash = 0 })
Mock.permissions[9] = {}
Mock.resetTraces()
Mock.tick(400)
Mock.commands['wallettest'](9, {})
assertEqual(Mock.countItems(9, 'codex_wallet'), 0, 'non-admin cannot run wallettest')

-- ---------------------------------------------------------------------------
section('11. Persistence & memory fallback')
-- ---------------------------------------------------------------------------
local row = dbWallet(serial)
assertEqual(row.serial, serial, 'wallet row persisted with serial')

local persistedId = nil
for _, entry in ipairs(row.items) do
    if entry.name == 'id_card' then
        persistedId = entry
        break
    end
end

assertTrue(persistedId ~= nil, 'document still inside the persisted wallet')
assertEqual(persistedId.metadata.firstname, 'Jane', 'document metadata persisted')

-- switch to memory mode and confirm the resource still works
Storage.SetDatabaseMode(false)
Storage.ResetMemory()

makeWalletPlayer(10, {
    items = { [1] = { name = 'codex_wallet', amount = 1, slot = 1, info = { serial = 'CXW-MEM1' } } }
})
giveCash(10, 500)

act(10, 'deposit', { amount = 200 })
local memWallet = Storage.Load('CXW-MEM1')
assertEqual(memWallet.cash, 200, 'memory fallback stores wallet cash')

act(10, 'withdraw', { amount = 50 })
memWallet = Storage.Load('CXW-MEM1')
assertEqual(memWallet.cash, 150, 'memory fallback updates wallet cash')
assertEqual(Mock.countItems(10, Config.Money.ItemName), 350, 'player inventory cash consistent in memory mode')

Storage.SetDatabaseMode(true)

-- ---------------------------------------------------------------------------
section('11b. WAdmin panel: whitelist management')
-- ---------------------------------------------------------------------------
-- non-admin cannot use the admin events
Mock.permissions[20] = {}
makeWalletPlayer(20, {})
Mock.resetTraces()
Mock.netTrigger(20, RESOURCE .. ':adminAction', 'addItem', { name = 'hackcard' })
assertTrue(lastNotification() ~= nil and lastNotification().message == Config.Notifications.NoPermission,
    'non-admin cannot modify the whitelist')
assertEqual(Mock.whitelistDb['hackcard'], nil, 'non-admin add did not persist')

-- admin adds a new item by spawn code (e.g. creditcard)
Mock.permissions[21] = { admin = true }
makeWalletPlayer(21, {})
Mock.resetTraces()

Mock.netTrigger(21, RESOURCE .. ':adminAction', 'addItem', {
    name = 'creditcard',
    label = 'Credit Card',
    weight = 20,
    presentable = false
})

assertEqual(Mock.whitelistDb['creditcard'] ~= nil, true, 'admin added creditcard to whitelist')
assertEqual(Mock.whitelistDb['creditcard'].label, 'Credit Card', 'whitelist entry keeps label')

local adminEvt = Mock.lastClientEvent('openAdmin')
assertTrue(adminEvt ~= nil, 'admin panel payload refreshed after change')
assertTrue(adminEvt.args[1].whitelist ~= nil, 'payload carries the whitelist')

-- the new spawn code can now go into the wallet and back
Mock.giveItem(21, 'creditcard', { number = '4242' })
local ccSlot = Mock.getItem(21, 'creditcard').slot
local serial21 = walletSerial(21)

act(21, 'storeItem', { slot = ccSlot })
assertEqual(Mock.countItems(21, 'creditcard'), 0, 'creditcard moved into the wallet')
assertEqual(dbWallet(serial21).items[#dbWallet(serial21).items].name, 'creditcard', 'creditcard stored in wallet record')

act(21, 'removeItem', { index = #dbWallet(serial21).items })
assertEqual(Mock.countItems(21, 'creditcard'), 1, 'creditcard moved back to the inventory')

-- invalid spawn codes are rejected
Mock.netTrigger(21, RESOURCE .. ':adminAction', 'addItem', { name = 'bad name!!' })
assertTrue(lastNotification().message == Config.Notifications.AdminInvalidName, 'invalid spawn code rejected')
assertEqual(Mock.whitelistDb['bad name!!'], nil, 'invalid spawn code not persisted')

-- admin adds police_badge with a spawn code at runtime
Mock.netTrigger(21, RESOURCE .. ':adminAction', 'addItem', { name = 'police_badge', label = 'Police Badge', weight = 60 })
assertEqual(Mock.whitelistDb['police_badge'] ~= nil, true, 'police_badge whitelist entry saved')

-- toggling disables the item (it can no longer be stored) - the player still
-- holds the creditcard returned by the earlier remove test
Mock.netTrigger(21, RESOURCE .. ':adminAction', 'toggleItem', { name = 'creditcard' })

ccSlot = Mock.getItem(21, 'creditcard').slot
act(21, 'storeItem', { slot = ccSlot })
assertEqual(Mock.countItems(21, 'creditcard'), 1, 'disabled item cannot be stored')
assertEqual(Mock.whitelistDb['creditcard'].enabled, false, 'toggle persisted as disabled')

-- toggle back on works again
Mock.netTrigger(21, RESOURCE .. ':adminAction', 'toggleItem', { name = 'creditcard' })
assertEqual(Mock.whitelistDb['creditcard'].enabled, true, 'toggle re-enabled persisted')

-- removing an admin-added item deletes it
Mock.netTrigger(21, RESOURCE .. ':adminAction', 'removeItem', { name = 'creditcard' })
assertEqual(Mock.whitelistDb['creditcard'], nil, 'admin-added entry deleted from whitelist')

-- removing a config-default item disables it (does not delete config)
Mock.netTrigger(21, RESOURCE .. ':adminAction', 'removeItem', { name = 'driver_license' })
assertEqual(Mock.whitelistDb['driver_license'] ~= nil, true, 'config-default entry kept as disabled override')
assertEqual(Mock.whitelistDb['driver_license'].enabled, false, 'config-default entry disabled')

Mock.giveItem(21, 'driver_license', {})
local dlSlot21 = Mock.getItem(21, 'driver_license').slot
act(21, 'storeItem', { slot = dlSlot21 })
assertEqual(Mock.countItems(21, 'driver_license'), 1, 'removed config item can no longer be stored')

-- console/admin can open the panel
Mock.resetTraces()
Mock.netTrigger(21, RESOURCE .. ':requestAdmin')
assertTrue(Mock.lastClientEvent('openAdmin') ~= nil, 'admin panel opens for permitted admin')

Mock.resetTraces()
Mock.netTrigger(20, RESOURCE .. ':requestAdmin')
assertEqual(Mock.lastClientEvent('openAdmin'), nil, 'admin panel refuses non-admin')

-- ---------------------------------------------------------------------------
section('12. Client shell')
-- ---------------------------------------------------------------------------
dofile('client/main.lua')
Mock.runReady()

assertTrue(Mock.keyMappings[1] ~= nil, 'keybind registered')
assertEqual(Mock.keyMappings[1].defaultKey, Config.Keybind.Default, 'default keybind matches config')

Mock.resetTraces()
Mock.clientTrigger(RESOURCE .. ':openWallet', {
    wallet = { serial = 'CXW-UI', cash = 750, items = {}, slotsUsed = 0, slotsMax = 8, weightUsed = 0, weightMax = 2000 },
    player = { name = 'John Doe', citizenid = 'CID1', job = 'Civilian' },
    inventory = {},
    brand = Config.Brand,
    limits = {}
})

assertEqual(Mock.nuiMessages[#Mock.nuiMessages].action, 'open', 'client forwards wallet payload to NUI')
assertEqual(Mock.nuiFocus.focus, true, 'NUI focus taken when wallet opens')

Mock.resetTraces()
Mock.nuiCall('close', {})
assertEqual(Mock.nuiFocus.focus, false, 'NUI focus released on close')
assertTrue(#Mock.serverEvents > 0 and Mock.serverEvents[1].name == RESOURCE .. ':closeWallet', 'close notifies the server')

Mock.resetTraces()
Mock.nuiCall('action', { action = 'deposit', data = { amount = '75' } })
assertEqual(Mock.serverEvents[1].name, RESOURCE .. ':action', 'NUI action forwarded to server')
assertEqual(Mock.serverEvents[1].args[1], 'deposit', 'action name forwarded intact')

Mock.resetTraces()
Mock.clientTrigger(RESOURCE .. ':presentCard', { cardType = 'id_card', firstName = 'Jane' }, 1000, 'John Doe')
assertEqual(Mock.nuiMessages[#Mock.nuiMessages].action, 'showCard', 'presented card forwarded to NUI')

-- WAdmin NUI shell
Mock.resetTraces()
Mock.clientTrigger(RESOURCE .. ':openAdmin', {
    whitelist = { { name = 'creditcard', label = 'Credit Card', weight = 20, presentable = false, enabled = true, source = 'admin' } },
    suggestions = { 'creditcard' },
    brand = Config.Brand,
    settings = { slots = 8, maxWeight = 2000, cashItem = 'cash', cashLabel = 'Cash', maxBalance = 1000000 }
})
assertEqual(Mock.nuiMessages[#Mock.nuiMessages].action, 'openAdmin', 'admin payload forwarded to NUI')
assertEqual(Mock.nuiFocus.focus, true, 'NUI focus taken when admin panel opens')

Mock.resetTraces()
Mock.nuiCall('adminAction', { action = 'addItem', data = { name = 'giftcard' } })
assertEqual(Mock.serverEvents[1].name, RESOURCE .. ':adminAction', 'admin NUI action forwarded to server')
assertEqual(Mock.serverEvents[1].args[1], 'addItem', 'admin action name forwarded intact')

Mock.nuiCall('closeAdmin', {})
assertEqual(Mock.nuiFocus.focus, false, 'admin focus released on close')

-- ESC/close safety: resource stop releases focus
Mock.clientTrigger(RESOURCE .. ':openWallet', { wallet = {}, player = {} })
Mock.fire('onResourceStop', RESOURCE)
assertEqual(Mock.nuiFocus.focus, false, 'focus released on resource stop')

-- ---------------------------------------------------------------------------
print(('\n-------------------------------\n%d passed, %d failed')
    :format(TEST_PASSES, TEST_FAILURES))

if TEST_FAILURES > 0 then
    error(('%d test(s) failed'):format(TEST_FAILURES))
end

print('ALL TESTS PASSED')
