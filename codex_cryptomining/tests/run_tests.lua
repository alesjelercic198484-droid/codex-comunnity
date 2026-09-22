--[[
    Automated test suite for codex_cryptomining.
    Run it with:  lua tests/run_tests.lua   (from the resource folder)

    It boots the real server scripts on top of the FiveM mock and asserts on
    the actual behaviour: economy maths, ownership, exploit protection,
    inventory rollbacks, electricity, robbery rules and persistence.
]]

package.path = './tests/?.lua;./?.lua;' .. package.path

local Mock = require('mock_fivem')

-- ---------------------------------------------------------------------------
-- TEST FRAMEWORK
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
        failures[#failures + 1] = ('[%s] %s%s'):format(currentGroup, name, detail and (' -> ' .. tostring(detail)) or '')
        print(('  \27[31mFAIL\27[0m %s%s'):format(name, detail and (' -> ' .. tostring(detail)) or ''))
    end
end

local function equals(actual, expected, name)
    ok(actual == expected, name, ('expected %s, got %s'):format(tostring(expected), tostring(actual)))
end

local function near(actual, expected, tolerance, name)
    local difference = math.abs((tonumber(actual) or 0) - expected)
    ok(difference <= tolerance, name, ('expected ~%s, got %s'):format(tostring(expected), tostring(actual)))
end

-- ---------------------------------------------------------------------------
-- LOAD THE RESOURCE
-- ---------------------------------------------------------------------------
local function load(path)
    local chunk, err = loadfile(path)

    if not chunk then
        print(('\27[31mSyntax error in %s: %s\27[0m'):format(path, err))
        os.exit(1)
    end

    chunk()
end

load('config.lua')
load('shared/core.lua')
load('locales/en.lua')
load('locales/fr.lua')
load('server/database.lua')
load('server/framework.lua')
load('server/market.lua')
load('server/warehouses.lua')
load('server/shops.lua')
load('server/robbery.lua')
load('server/main.lua')

local Crypto = CodexCrypto
local WH = CodexCryptoWH
local Market = CodexCryptoMarket
local Rob = CodexCryptoRob
local Shops = CodexCryptoShops
local FW = CodexCryptoFW

-- Make the tests deterministic.
math.randomseed(1337)

-- Boot the resource (the thread in server/main.lua).
Mock.Tick(8000)

-- ---------------------------------------------------------------------------
group('Boot & configuration')
-- ---------------------------------------------------------------------------
ok(CodexCryptoDB.ready, 'database initialised')
ok(Crypto.TableCount(WH.state) == #Config.Warehouses, 'every warehouse has a state')
ok(Market.GetPrice() > 0, 'market has a price')

local uniqueIds = {}
local duplicate = false
for _, warehouse in ipairs(Config.Warehouses) do
    if uniqueIds[warehouse.id] then
        duplicate = true
    end
    uniqueIds[warehouse.id] = true
end
ok(not duplicate, 'warehouse ids are unique')

local slotsOk = true
for typeName, interior in pairs(Config.Interiors) do
    if #interior.slots < interior.maxRigs then
        slotsOk = false
        print(('     interior %s: %d slots for %d rigs'):format(typeName, #interior.slots, interior.maxRigs))
    end
end
ok(slotsOk, 'every interior has enough rig slots')

for _, warehouse in ipairs(Config.Warehouses) do
    local interior = Crypto.GetInteriorConfig(warehouse.type)
    ok(interior ~= nil, ('warehouse %s has a valid interior'):format(warehouse.id))
end

-- Interiors must point at the base game Import / Export vehicle warehouse and
-- keep every spawn point inside that room (anchor 994.5925, -3002.594, -39.647).
-- A stray coordinate here means props / the player spawning in the void.
local IMPEXP_IPL = 'imp_impexp_interior_placement_interior_1_impexp_intwaremed_milo_'
local ANCHOR = { x = 994.5925, y = -3002.594, z = -39.64699 }

local function within(point, radius)
    if not point then
        return false
    end
    local dx = (point.x or 0) - ANCHOR.x
    local dy = (point.y or 0) - ANCHOR.y
    local dz = (point.z or 0) - ANCHOR.z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= radius
end

for typeName, interior in pairs(Config.Interiors) do
    local iplOk = false
    for _, ipl in ipairs(interior.ipls or {}) do
        if ipl == IMPEXP_IPL then
            iplOk = true
        end
    end
    ok(iplOk, ('interior %s loads the Import/Export vehicle warehouse IPL'):format(typeName))
    ok(within(interior.enter, 8.0), ('interior %s entrance sits inside the room'):format(typeName))
    ok(within(interior.terminal, 12.0), ('interior %s terminal sits inside the room'):format(typeName))
    ok(within(interior.power, 12.0), ('interior %s power panel sits inside the room'):format(typeName))
    ok(within(interior.storage, 12.0), ('interior %s storage sits inside the room'):format(typeName))

    local slotsInside = true
    for _, slot in ipairs(interior.slots or {}) do
        if not within(slot, 20.0) then
            slotsInside = false
        end
    end
    ok(slotsInside, ('every rig slot of interior %s stays inside the room'):format(typeName))
end

-- Locales must share the same keys.
local missingLocale = {}
for key in pairs(Locales.en) do
    if Locales.fr[key] == nil then
        missingLocale[#missingLocale + 1] = key
    end
end
ok(#missingLocale == 0, 'fr locale covers every en key', table.concat(missingLocale, ', '))

-- ---------------------------------------------------------------------------
group('Prop & ped models')
-- ---------------------------------------------------------------------------
-- Every model must be a real base game model. These names were verified
-- against the GTA V object/ped list; a typo here means an invisible rig in
-- game, which is exactly the kind of bug that is hard to spot by reading code.
local KNOWN_PROPS = {
    ['hei_prop_mini_sever_01'] = true,
    ['hei_prop_mini_sever_02'] = true,
    ['hei_prop_mini_sever_03'] = true,
    ['hei_prop_mini_sever_broken'] = true,
    ['ex_office_swag_electronic'] = true,
    ['ex_office_swag_electronic2'] = true,
    ['ex_office_swag_electronic3'] = true,
    ['gr_prop_bunker_deskfan_01a'] = true,
    ['bkr_prop_fakeid_deskfan_01a'] = true,
    ['prop_laptop_01a'] = true,
    ['hei_prop_hst_laptop'] = true,
    ['prop_elecbox_16'] = true,
    ['prop_elecbox_20'] = true,
    ['prop_box_wood04a'] = true,
    ['prop_table_03'] = true,
    ['prop_table_03b'] = true
}

local KNOWN_PEDS = {
    ['s_m_y_dealer_01'] = true,
    ['g_m_m_armboss_01'] = true,
    ['a_m_y_business_01'] = true,
    ['a_m_y_business_02'] = true,
    ['a_m_y_business_03'] = true
}

local function checkProp(model, label)
    if model == nil then
        return
    end
    ok(KNOWN_PROPS[model] == true, ('%s uses a real base game prop (%s)'):format(label, tostring(model)))
end

checkProp(Config.Props.Fallback, 'fallback')
checkProp(Config.Props.Rig.model, 'rig chassis')
checkProp(Config.Props.BrokenModel, 'broken rig')
checkProp(Config.Props.Rig.base and Config.Props.Rig.base.model, 'rig base')
checkProp(Config.Props.Gpu.model, 'gpu')
checkProp(Config.Props.Cooler.model, 'cooler')
checkProp(Config.Props.Terminal.model, 'terminal')
checkProp(Config.Props.PowerBox.model, 'power box')
checkProp(Config.Props.Storage.model, 'storage')

for _, entry in ipairs({
    { Config.TechShop.Model, 'techshop ped' },
    { Config.BlackMarket.Model, 'black market ped' },
    { Config.Informant.Model, 'informant ped' },
    { Config.Broker.Model, 'broker ped' }
}) do
    ok(KNOWN_PEDS[entry[1]] == true, ('%s uses a real ped model (%s)'):format(entry[2], tostring(entry[1])))
end

-- The resource must not depend on any streamed asset.
local streamFolder = io.open('stream', 'r')
ok(streamFolder == nil, 'the resource ships no streamed assets (base game props only)')
if streamFolder then streamFolder:close() end

-- ---------------------------------------------------------------------------
group('Shared maths')
-- ---------------------------------------------------------------------------
equals(Crypto.GetRigHashrate({ gpus = 0, cpu = 0, cooler = 0, durability = 100 }), 0.0, 'empty rig produces nothing')
equals(Crypto.GetRigHashrate({ gpus = 4, broken = true, durability = 100 }), 0.0, 'broken rig produces nothing')

local fullRig = { gpus = 8, cpu = 0, cooler = 0, durability = 100 }
equals(Crypto.GetRigHashrate(fullRig), 8 * Config.Mining.HashPerGpu, 'full rig hashrate at 100% durability')

local cpuRig = { gpus = 8, cpu = 2, cooler = 0, durability = 100 }
near(Crypto.GetRigHashrate(cpuRig), 8 * Config.Mining.HashPerGpu * 1.30, 0.01, 'cpu level 2 adds 30%')

local wornRig = { gpus = 8, cpu = 0, cooler = 0, durability = 0 }
near(Crypto.GetRigHashrate(wornRig), 8 * Config.Mining.HashPerGpu * Config.Mining.Durability.MinFactor, 0.01, 'worn rig falls back to the minimum factor')

near(Crypto.GetProduction(200, 3600), 200 * Config.Mining.BtcPerHashHour, 1e-9, 'production over one hour')
equals(Crypto.GetSellValue(1.0, 10000), math.floor(10000 * (1 - Config.Market.SellFee)), 'sell value applies the fee')
equals(Crypto.GetSellValue(0, 10000), 0, 'selling nothing pays nothing')
equals(Crypto.FormatMoney(1234567), '$1,234,567', 'money formatting')
equals(Crypto.FormatMoney(-2500), '-$2,500', 'negative money formatting')
equals(Crypto.L('missing_key_that_does_not_exist'), 'missing_key_that_does_not_exist', 'missing locale key falls back to the key')
ok(Crypto.L('warehouse_bought', 'Depot', '$10') :find('Depot') ~= nil, 'locale formatting works')

-- Clamp / conversions
equals(Crypto.Clamp(15, 0, 10), 10, 'clamp upper bound')
equals(Crypto.Clamp(-5, 0, 10), 0, 'clamp lower bound')
equals(Crypto.ToInt('42abc', 7), 7, 'ToInt fallback on garbage')
equals(Crypto.ToInt(nil, 3), 3, 'ToInt fallback on nil')
ok(Crypto.ToBool('1') and Crypto.ToBool(true) and not Crypto.ToBool(0), 'ToBool handles sql values')

-- ---------------------------------------------------------------------------
group('Players & ownership')
-- ---------------------------------------------------------------------------
local owner = Mock.NewPlayer(1, 'char1:owner', 'John Miner')
local friend = Mock.NewPlayer(2, 'char1:friend', 'Jane Friend')
local thief = Mock.NewPlayer(3, 'char1:thief', 'Rob Ber')

owner.accounts.bank = 5000000
friend.accounts.bank = 100000
thief.accounts.bank = 100000
thief.accounts.black_money = 100000

local firstWarehouse = Config.Warehouses[1]
owner.coords = vector3(firstWarehouse.entrance.x, firstWarehouse.entrance.y, firstWarehouse.entrance.z)
friend.coords = owner.coords
thief.coords = owner.coords

-- Broker is far away from the warehouse: buying must fail on distance.
local result = Mock.CallCallback('codex_cryptomining:shopAction', 1, { action = 'buyWarehouse', warehouseId = firstWarehouse.id })
ok(result and not result.ok, 'cannot buy a warehouse from far away')
equals(WH.Get(firstWarehouse.id).owner, nil, 'warehouse still has no owner')

-- Move to the broker and buy.
local brokerCoords = Config.Broker.Locations[1]
owner.coords = vector3(brokerCoords.x, brokerCoords.y, brokerCoords.z)

local moneyBefore = owner.accounts.bank
result = Mock.CallCallback('codex_cryptomining:shopAction', 1, { action = 'buyWarehouse', warehouseId = firstWarehouse.id })
ok(result and result.ok, 'warehouse bought at the broker')
equals(WH.Get(firstWarehouse.id).owner, owner.identifier, 'owner is set')
equals(owner.accounts.bank, moneyBefore - firstWarehouse.price, 'price was charged once')

-- Buying it again must fail.
result = Mock.CallCallback('codex_cryptomining:shopAction', 1, { action = 'buyWarehouse', warehouseId = firstWarehouse.id })
ok(result and not result.ok, 'cannot buy an owned warehouse')

-- Another player cannot buy it either.
friend.coords = owner.coords
result = Mock.CallCallback('codex_cryptomining:shopAction', 2, { action = 'buyWarehouse', warehouseId = firstWarehouse.id })
ok(result and not result.ok, 'another player cannot buy an owned warehouse')
equals(friend.accounts.bank, 100000, 'the other player was not charged')

-- Ownership limit.
local secondWarehouse = Config.Warehouses[2]
local thirdWarehouse = Config.Warehouses[3]
Mock.CallCallback('codex_cryptomining:shopAction', 1, { action = 'buyWarehouse', warehouseId = secondWarehouse.id })
equals(WH.CountOwned(owner.identifier), 2, 'owner has two warehouses')

local balanceBefore = owner.accounts.bank
result = Mock.CallCallback('codex_cryptomining:shopAction', 1, { action = 'buyWarehouse', warehouseId = thirdWarehouse.id })
ok(result and not result.ok, 'ownership limit is enforced')
equals(owner.accounts.bank, balanceBefore, 'no money taken when the limit blocks the purchase')

-- Regression: right after buying, the owner must be able to walk to the
-- entrance and actually enter the interior (the whole point of the purchase).
owner.coords = vector3(firstWarehouse.entrance.x, firstWarehouse.entrance.y, firstWarehouse.entrance.z)
local boughtEnter = Mock.CallCallback('codex_cryptomining:enterWarehouse', 1, firstWarehouse.id)
ok(boughtEnter ~= nil and boughtEnter.warehouse ~= nil, 'a fresh owner can enter right after buying')
ok(boughtEnter and boughtEnter.warehouse.isOwner == true, 'the buyer is recognised as the owner on entry')
-- Put the player back in the world so later tests start clean.
WH.RemoveViewer(1)
WH.SetPlayerBucket(1, nil)

-- ---------------------------------------------------------------------------
group('Rigs & GPUs')
-- ---------------------------------------------------------------------------
-- Move the owner inside the interior.
local interior = Crypto.GetInteriorConfig(firstWarehouse.type)
owner.coords = vector3(interior.enter.x, interior.enter.y, interior.enter.z)
friend.coords = owner.coords

local function panel(source, payload)
    return Mock.CallCallback('codex_cryptomining:panelAction', source, payload)
end

local bankBefore = owner.accounts.bank
result = panel(1, { action = 'installRig', warehouseId = firstWarehouse.id })
ok(result and result.ok, 'rig installed')
equals(owner.accounts.bank, bankBefore - Config.Mining.RigPrice, 'rig price charged')
equals(Crypto.TableCount(WH.Get(firstWarehouse.id).rigs), 1, 'warehouse has one rig')

local rigId
for id in pairs(WH.Get(firstWarehouse.id).rigs) do
    rigId = id
end

-- Installing a GPU without owning one must fail.
result = panel(1, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = 1 })
ok(result and not result.ok, 'cannot install a GPU you do not have')
equals(WH.GetRig(firstWarehouse.id, rigId).gpus, 0, 'rig still empty')

-- Give GPUs and install them.
owner.inventory.gpu = 10
result = panel(1, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = 4 })
ok(result and result.ok, 'four GPUs installed')
equals(WH.GetRig(firstWarehouse.id, rigId).gpus, 4, 'rig has four GPUs')
equals(owner.inventory.gpu, 6, 'four GPUs left the inventory')

-- Overfill protection: max is 8, we try 10 more.
result = panel(1, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = 10 })
equals(WH.GetRig(firstWarehouse.id, rigId).gpus, Crypto.GetMaxGpus(), 'GPU count is capped at the maximum')
ok(owner.inventory.gpu >= 0, 'inventory never goes negative')

-- Negative quantity exploit.
local gpusBefore = WH.GetRig(firstWarehouse.id, rigId).gpus
local inventoryBefore = owner.inventory.gpu
panel(1, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = -5 })
equals(WH.GetRig(firstWarehouse.id, rigId).gpus, gpusBefore, 'negative install quantity is rejected')

panel(1, { action = 'removeGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = -99 })
ok(WH.GetRig(firstWarehouse.id, rigId).gpus <= gpusBefore, 'negative remove quantity cannot add GPUs')
ok(owner.inventory.gpu >= 0, 'inventory stays positive after the negative remove')

-- Removing more than installed.
local installed = WH.GetRig(firstWarehouse.id, rigId).gpus
inventoryBefore = owner.inventory.gpu
panel(1, { action = 'removeGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = 999 })
equals(WH.GetRig(firstWarehouse.id, rigId).gpus, 0, 'all GPUs removed')
equals(owner.inventory.gpu, inventoryBefore + installed, 'exactly the installed GPUs came back')

-- Cannot dismantle a rig that still holds GPUs.
panel(1, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = 2 })
result = panel(1, { action = 'removeRig', warehouseId = firstWarehouse.id, rigId = rigId })
ok(result and not result.ok, 'cannot dismantle a loaded rig')

-- Unknown rig id.
result = panel(1, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = 999999, quantity = 1 })
ok(result and not result.ok, 'unknown rig id is rejected')

-- Unknown action.
result = panel(1, { action = 'giveMeMoney', warehouseId = firstWarehouse.id })
ok(result and not result.ok, 'unknown action is rejected')

-- Slot limit.
local warehouseState = WH.Get(firstWarehouse.id)
local maxRigs = Crypto.GetMaxRigs(firstWarehouse.id)
owner.accounts.bank = 5000000

for _ = 1, maxRigs + 3 do
    panel(1, { action = 'installRig', warehouseId = firstWarehouse.id })
end

equals(Crypto.TableCount(warehouseState.rigs), maxRigs, 'rig count never exceeds the slot limit')

local slotsSeen = {}
local slotDuplicate = false
for _, rig in pairs(warehouseState.rigs) do
    if slotsSeen[rig.slot] then
        slotDuplicate = true
    end
    slotsSeen[rig.slot] = true
end
ok(not slotDuplicate, 'no two rigs share the same slot')

-- ---------------------------------------------------------------------------
group('Permissions')
-- ---------------------------------------------------------------------------
-- The friend has no key yet.
result = panel(2, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = 1 })
ok(result and not result.ok, 'a stranger cannot touch the rigs')

result = panel(2, { action = 'sellBtc', warehouseId = firstWarehouse.id, all = true })
ok(result and not result.ok, 'a stranger cannot sell the BTC')

-- Give the keys.
result = panel(1, { action = 'giveKeys', warehouseId = firstWarehouse.id, target = 2 })
ok(result and result.ok, 'keys given to the friend')
ok(WH.HasAccess(friend.identifier, firstWarehouse.id), 'friend has access')

-- The friend can now handle GPUs...
friend.inventory.gpu = 3
result = panel(2, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = 1 })
ok(result and result.ok, 'friend can install a GPU')

-- ...but not sell the bitcoins or install a rig (owner only).
result = panel(2, { action = 'sellBtc', warehouseId = firstWarehouse.id, all = true })
ok(result and not result.ok, 'friend cannot sell the BTC')

result = panel(2, { action = 'installRig', warehouseId = firstWarehouse.id })
ok(result and not result.ok, 'friend cannot install a rig')

result = panel(2, { action = 'giveKeys', warehouseId = firstWarehouse.id, target = 3 })
ok(result and not result.ok, 'friend cannot hand out keys')

-- Distance check: move the friend far away.
friend.coords = vector3(0.0, 0.0, 0.0)
result = panel(2, { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = rigId, quantity = 1 })
ok(result and not result.ok, 'actions are blocked from outside the interior')
friend.coords = owner.coords

-- Remove the keys.
result = panel(1, { action = 'removeKeys', warehouseId = firstWarehouse.id, identifier = friend.identifier })
ok(result and result.ok, 'keys removed')
ok(not WH.HasAccess(friend.identifier, firstWarehouse.id), 'friend lost access')

-- ---------------------------------------------------------------------------
group('Mining, electricity & disasters')
-- ---------------------------------------------------------------------------
-- Clean slate: one warehouse, controlled rigs.
WH.Reset(secondWarehouse.id, false)
WH.SetOwner(secondWarehouse.id, owner.identifier, owner.name)

local state = WH.Get(secondWarehouse.id)
local testRig = WH.AddRig(secondWarehouse.id, 1)
testRig.gpus = 8
testRig.durability = 100.0

-- Disable random disasters for the deterministic production test.
local disasterEnabled = Config.Mining.Disaster.Enabled
Config.Mining.Disaster.Enabled = false

state.btc = 0
state.lastTick = os.time()
state.powered = true

local expectedHash = Crypto.GetRigHashrate(testRig)
WH.Tick(secondWarehouse.id, 3600)

near(state.btc, Crypto.GetProduction(expectedHash, 3600), Crypto.GetProduction(expectedHash, 3600) * 0.35, 'one hour of mining produced roughly the expected BTC')
ok(state.btc > 0, 'mining produced BTC')
ok(state.bill > 0, 'electricity was billed')
ok(testRig.durability < 100.0, 'durability decreased')

-- Power off = no production.
state.powered = false
local btcBefore = state.btc
WH.Tick(secondWarehouse.id, 3600)
equals(state.btc, btcBefore, 'no production while the power is off')
ok(state.bill > 0, 'the base fee keeps running while off')

state.powered = true

-- Storage cap.
Config.Mining.StorageLimit = 0.0001
state.btc = 0.00005
WH.Tick(secondWarehouse.id, 36000)
ok(state.btc <= 0.0001 + 1e-12, 'storage limit is respected')
Config.Mining.StorageLimit = 25.0

-- Catch-up cap: a huge elapsed time must be clamped to one day of production.
-- The owner is connected here, so the offline multiplier does not apply.
state.btc = 0
state.lastTick = os.time()
local hashBeforeCatchUp = Crypto.GetRigHashrate(testRig)
WH.Tick(secondWarehouse.id, 60 * 60 * 24 * 365)

local oneDay = Crypto.GetProduction(hashBeforeCatchUp, 86400)
ok(state.btc <= oneDay + 1e-9, 'a year of elapsed time is capped at one day of production')
ok(state.btc > 0, 'the capped catch-up still produced something')

-- Same scenario with nobody connected: the offline multiplier must apply.
local absentOwner = state.owner
state.owner = 'char1:nobody_is_online'
state.btc = 0
state.lastTick = os.time()
WH.Tick(secondWarehouse.id, 60 * 60 * 24 * 365)

local offlineCap = Crypto.GetProduction(hashBeforeCatchUp, 86400) * Config.Mining.OfflineMultiplier
ok(state.btc <= offlineCap + 1e-9, 'offline production applies the offline multiplier')
state.owner = absentOwner

-- Automatic power cut when the bill explodes.
state.bill = Config.Electricity.MaxDebt + 100
state.powered = true
WH.Tick(secondWarehouse.id, 60)
ok(not state.powered, 'power is cut when the debt is too high')

-- Paying the bill restores the power.
owner.coords = vector3(Crypto.GetInteriorConfig(secondWarehouse.type).enter.x, Crypto.GetInteriorConfig(secondWarehouse.type).enter.y, Crypto.GetInteriorConfig(secondWarehouse.type).enter.z)
owner.accounts.bank = 5000000
local billAmount = state.bill

result = panel(1, { action = 'payBill', warehouseId = secondWarehouse.id })
ok(result and result.ok, 'bill paid')
equals(state.bill, 0, 'bill reset to zero')
ok(state.powered, 'power restored after payment')
equals(owner.accounts.bank, 5000000 - billAmount, 'exactly the bill amount was charged')

result = panel(1, { action = 'payBill', warehouseId = secondWarehouse.id })
ok(result and not result.ok, 'cannot pay a bill of zero')

-- Disasters do happen when enabled.
Config.Mining.Disaster.Enabled = true
Config.Mining.Disaster.Chance = 0.9

local brokeAtLeastOnce = false
for _ = 1, 30 do
    testRig.broken = false
    testRig.gpus = 8
    WH.Tick(secondWarehouse.id, 60)
    if testRig.broken then
        brokeAtLeastOnce = true
        break
    end
end
ok(brokeAtLeastOnce, 'a rig can break down')

-- Broken rigs do not produce.
testRig.broken = true
state.btc = 0
WH.Tick(secondWarehouse.id, 3600)
equals(state.btc, 0, 'a broken rig produces nothing')

-- Repair needs a kit.
owner.inventory[FW.Item('repairkit')] = 0
result = panel(1, { action = 'repairRig', warehouseId = secondWarehouse.id, rigId = testRig.id })
ok(result and not result.ok, 'repair without a kit fails')
ok(testRig.broken, 'rig is still broken')

owner.inventory[FW.Item('repairkit')] = 2
result = panel(1, { action = 'repairRig', warehouseId = secondWarehouse.id, rigId = testRig.id })
ok(result and result.ok, 'rig repaired with a kit')
ok(not testRig.broken, 'rig is no longer broken')
equals(owner.inventory[FW.Item('repairkit')], 1, 'exactly one kit was consumed')

Config.Mining.Disaster.Enabled = disasterEnabled
Config.Mining.Disaster.Chance = 0.004

-- Upgrades.
local cpuBefore = testRig.cpu
result = panel(1, { action = 'upgradeCpu', warehouseId = secondWarehouse.id, rigId = testRig.id })
ok(result and result.ok, 'cpu upgraded')
equals(testRig.cpu, cpuBefore + 1, 'cpu level increased by one')

for _ = 1, 10 do
    panel(1, { action = 'upgradeCpu', warehouseId = secondWarehouse.id, rigId = testRig.id })
end
equals(testRig.cpu, Config.Mining.Cpu.MaxLevel, 'cpu level is capped')

for _ = 1, 10 do
    panel(1, { action = 'upgradeCooler', warehouseId = secondWarehouse.id, rigId = testRig.id })
end
equals(testRig.cooler, Config.Mining.Cooler.MaxLevel, 'cooler level is capped')

-- ---------------------------------------------------------------------------
group('Market & selling')
-- ---------------------------------------------------------------------------
local previousPrice = Market.GetPrice()
for _ = 1, 200 do
    Market.Update()
    local price = Market.GetPrice()
    if price < Config.Market.MinPrice or price > Config.Market.MaxPrice then
        ok(false, 'market price stayed inside the configured range', price)
        break
    end
end
ok(Market.GetPrice() >= Config.Market.MinPrice and Market.GetPrice() <= Config.Market.MaxPrice, 'market price stays inside the range after 200 updates')
ok(#Market.history <= Config.Market.HistorySize, 'market history is trimmed')

state.btc = 2.0
state.powered = true
local bankBeforeSale = owner.accounts.bank
local price = Market.GetPrice()

result = panel(1, { action = 'sellBtc', warehouseId = secondWarehouse.id, amount = 1.0 })
ok(result and result.ok, 'sold one BTC')
near(state.btc, 1.0, 1e-6, 'wallet decreased by exactly one BTC')
equals(owner.accounts.bank, bankBeforeSale + Crypto.GetSellValue(1.0, price), 'payout matches the formula')

-- Selling more than owned.
bankBeforeSale = owner.accounts.bank
result = panel(1, { action = 'sellBtc', warehouseId = secondWarehouse.id, amount = 9999 })
ok(result and result.ok, 'overselling is clamped to the balance')
near(state.btc, 0.0, 1e-6, 'wallet is empty')

-- Selling nothing.
result = panel(1, { action = 'sellBtc', warehouseId = secondWarehouse.id, all = true })
ok(result and not result.ok, 'cannot sell an empty wallet')

-- Negative amount exploit.
state.btc = 1.0
bankBeforeSale = owner.accounts.bank
result = panel(1, { action = 'sellBtc', warehouseId = secondWarehouse.id, amount = -50 })
ok(owner.accounts.bank >= bankBeforeSale, 'a negative sell amount cannot remove money')
ok(state.btc <= 1.0 + 1e-9, 'a negative sell amount cannot create BTC')

-- ---------------------------------------------------------------------------
group('Shops')
-- ---------------------------------------------------------------------------
local shopCoords = Config.TechShop.Locations[1]
thief.coords = vector3(shopCoords.x, shopCoords.y, shopCoords.z)
thief.accounts.bank = 100000
thief.inventory = {}

result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'buy', shop = 'techshop', index = 1, quantity = 2 })
ok(result and result.ok, 'bought two GPUs at the TechShop')
equals(thief.inventory[FW.Item('gpu')], 2, 'GPUs are in the inventory')
equals(thief.accounts.bank, 100000 - Config.TechShop.Buy[1].price * 2, 'correct amount charged')

-- Quantity exploits.
local bankSnapshot = thief.accounts.bank
result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'buy', shop = 'techshop', index = 1, quantity = -5 })
ok(result and not result.ok, 'negative quantity is rejected')
equals(thief.accounts.bank, bankSnapshot, 'no money moved on a negative quantity')

result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'buy', shop = 'techshop', index = 1, quantity = 99999 })
ok(result and not result.ok, 'quantity above the maximum is rejected')

result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'buy', shop = 'techshop', index = 999, quantity = 1 })
ok(result and not result.ok, 'unknown catalog index is rejected')

-- Not enough money.
thief.accounts.bank = 10
result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'buy', shop = 'techshop', index = 1, quantity = 1 })
ok(result and not result.ok, 'cannot buy without money')
equals(thief.accounts.bank, 10, 'balance untouched')

-- Selling back.
thief.inventory[FW.Item('gpu')] = 2
result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'sell', shop = 'techshop', index = 1, quantity = 2 })
ok(result and result.ok, 'sold two GPUs back')
equals(thief.inventory[FW.Item('gpu')], 0, 'GPUs left the inventory')
ok(thief.accounts.bank > 10, 'the player was paid')

-- Selling something you do not have.
result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'sell', shop = 'techshop', index = 1, quantity = 5 })
ok(result and not result.ok, 'cannot sell items you do not own')

-- Distance.
thief.coords = vector3(0.0, 0.0, 0.0)
result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'buy', shop = 'techshop', index = 1, quantity = 1 })
ok(result and not result.ok, 'cannot buy from far away')

-- Black market uses dirty money.
local blackCoords = Config.BlackMarket.Locations[1]
thief.coords = vector3(blackCoords.x, blackCoords.y, blackCoords.z)
thief.accounts.black_money = 50000
local cleanBefore = thief.accounts.bank

result = Mock.CallCallback('codex_cryptomining:shopAction', 3, { action = 'buy', shop = 'blackmarket', index = 1, quantity = 1 })
ok(result and result.ok, 'bought a lockpick with dirty money')
equals(thief.accounts.bank, cleanBefore, 'clean money untouched')
ok(thief.accounts.black_money < 50000, 'dirty money was charged')

-- ---------------------------------------------------------------------------
group('Robbery')
-- ---------------------------------------------------------------------------
-- Prepare a juicy target owned by someone else.
WH.Reset(thirdWarehouse.id, false)
WH.SetOwner(thirdWarehouse.id, owner.identifier, owner.name)

local targetRig = WH.AddRig(thirdWarehouse.id, 1)
targetRig.gpus = 8
local targetRig2 = WH.AddRig(thirdWarehouse.id, 2)
targetRig2.gpus = 6

thief.coords = vector3(thirdWarehouse.entrance.x, thirdWarehouse.entrance.y, thirdWarehouse.entrance.z)
thief.inventory[FW.Item('lockpick')] = 1
thief.inventory[FW.Item('usb')] = 1
thief.inventory[FW.Item('gpu')] = 0

-- Not enough police.
Config.Robbery.MinPolice = 5
result = Mock.CallCallback('codex_cryptomining:startRobbery', 3, thirdWarehouse.id)
ok(result and not result.ok, 'robbery blocked without enough police')

Config.Robbery.MinPolice = 0

-- The owner cannot rob himself.
owner.coords = thief.coords
result = Mock.CallCallback('codex_cryptomining:startRobbery', 1, thirdWarehouse.id)
ok(result and not result.ok, 'the owner cannot rob his own warehouse')

-- Missing tools.
thief.inventory[FW.Item('lockpick')] = 0
result = Mock.CallCallback('codex_cryptomining:startRobbery', 3, thirdWarehouse.id)
ok(result and not result.ok, 'robbery needs a lockpick')

thief.inventory[FW.Item('lockpick')] = 1

-- Real robbery.
result = Mock.CallCallback('codex_cryptomining:startRobbery', 3, thirdWarehouse.id)
ok(result and result.ok, 'robbery started')
ok(Rob.IsActive(thirdWarehouse.id), 'robbery is registered')
equals(thief.inventory[FW.Item('lockpick')], 0, 'lockpick consumed')
equals(thief.inventory[FW.Item('usb')], 0, 'usb consumed')

-- Loot the first rig.
result = Mock.CallCallback('codex_cryptomining:lootRig', 3, thirdWarehouse.id, targetRig.id)
ok(result and result.ok, 'first rig looted')
equals(targetRig.gpus, 0, 'the rig was emptied')
equals(thief.inventory[FW.Item('gpu')], 8, 'the thief got the GPUs')

-- The same rig cannot be looted twice.
result = Mock.CallCallback('codex_cryptomining:lootRig', 3, thirdWarehouse.id, targetRig.id)
ok(result and not result.ok, 'a rig cannot be looted twice')
equals(thief.inventory[FW.Item('gpu')], 8, 'no duplicated GPUs')

-- Another player cannot loot an ongoing robbery he did not start.
result = Mock.CallCallback('codex_cryptomining:lootRig', 2, thirdWarehouse.id, targetRig2.id)
ok(result and not result.ok, 'only the thief can loot')
equals(targetRig2.gpus, 6, 'the second rig is untouched')

-- Emptying everything ends the robbery.
result = Mock.CallCallback('codex_cryptomining:lootRig', 3, thirdWarehouse.id, targetRig2.id)
ok(result and result.ok, 'second rig looted')
ok(not Rob.IsActive(thirdWarehouse.id), 'robbery ends when the warehouse is empty')
equals(thief.inventory[FW.Item('gpu')], 14, 'the thief carries every stolen GPU')

-- Looting after the robbery ended.
result = Mock.CallCallback('codex_cryptomining:lootRig', 3, thirdWarehouse.id, targetRig.id)
ok(result and not result.ok, 'cannot loot once the robbery is over')

-- Player cooldown.
targetRig.gpus = 8
thief.inventory[FW.Item('lockpick')] = 1
thief.inventory[FW.Item('usb')] = 1
WH.Get(thirdWarehouse.id).robbedAt = 0

result = Mock.CallCallback('codex_cryptomining:startRobbery', 3, thirdWarehouse.id)
ok(result and not result.ok, 'the thief is on cooldown')

-- Warehouse cooldown, tested with a different thief.
local thief2 = Mock.NewPlayer(4, 'char1:thief2', 'Second Thief')
thief2.coords = thief.coords
thief2.inventory[FW.Item('lockpick')] = 1
thief2.inventory[FW.Item('usb')] = 1
WH.Get(thirdWarehouse.id).robbedAt = os.time()

result = Mock.CallCallback('codex_cryptomining:startRobbery', 4, thirdWarehouse.id)
ok(result and not result.ok, 'the warehouse is on cooldown')

-- Simultaneous robbery limit.
WH.Get(thirdWarehouse.id).robbedAt = 0
Rob.cooldowns = {}
Config.Robbery.MaxSimultaneous = 1

result = Mock.CallCallback('codex_cryptomining:startRobbery', 4, thirdWarehouse.id)
ok(result and result.ok, 'second thief started a robbery')

-- Another warehouse while one is running.
WH.Reset(Config.Warehouses[4].id, false)
WH.SetOwner(Config.Warehouses[4].id, owner.identifier, owner.name)
local otherRig = WH.AddRig(Config.Warehouses[4].id, 1)
otherRig.gpus = 8

local thief3 = Mock.NewPlayer(5, 'char1:thief3', 'Third Thief')
thief3.coords = vector3(Config.Warehouses[4].entrance.x, Config.Warehouses[4].entrance.y, Config.Warehouses[4].entrance.z)
thief3.inventory[FW.Item('lockpick')] = 1
thief3.inventory[FW.Item('usb')] = 1

result = Mock.CallCallback('codex_cryptomining:startRobbery', 5, Config.Warehouses[4].id)
ok(result and not result.ok, 'the simultaneous robbery limit is enforced')

Config.Robbery.MaxSimultaneous = 2
result = Mock.CallCallback('codex_cryptomining:startRobbery', 5, Config.Warehouses[4].id)
ok(result and result.ok, 'a second concurrent robbery is allowed when the limit permits it')

-- Disconnecting cancels the robbery.
Rob.OnPlayerDropped(5)
ok(not Rob.IsActive(Config.Warehouses[4].id), 'disconnecting ends the robbery')

-- ---------------------------------------------------------------------------
group('Informant')
-- ---------------------------------------------------------------------------
local informantCoords = Config.Informant.Locations[1]
local buyer = Mock.NewPlayer(6, 'char1:buyer', 'Info Buyer')
buyer.coords = vector3(informantCoords.x, informantCoords.y, informantCoords.z)
buyer.accounts.black_money = 100000

Mock.Reset()
result = Mock.CallCallback('codex_cryptomining:shopAction', 6, { action = 'informant' })
ok(result and result.ok, 'bought a warehouse location')
ok(buyer.accounts.black_money < 100000, 'dirty money was charged')

local gotTarget = false
for _, event in ipairs(Mock.clientEvents) do
    if event.name == 'codex_cryptomining:informantTarget' then
        gotTarget = true
        local payload = event.args[1]
        ok(payload and payload.coords ~= nil, 'the informant sends coordinates')
    end
end
ok(gotTarget, 'the informant event reached the client')

-- Cooldown.
result = Mock.CallCallback('codex_cryptomining:shopAction', 6, { action = 'informant' })
ok(result and not result.ok, 'the informant has a cooldown')

-- The informant never sells your own warehouse.
local selfBuyer = Mock.NewPlayer(7, owner.identifier, 'Owner Again')
selfBuyer.coords = buyer.coords
selfBuyer.accounts.black_money = 100000

Mock.Reset()
Shops.ClearCooldown(owner.identifier)
result = Mock.CallCallback('codex_cryptomining:shopAction', 7, { action = 'informant' })

local soldOwn = false
for _, event in ipairs(Mock.clientEvents) do
    if event.name == 'codex_cryptomining:informantTarget' then
        local payload = event.args[1]
        local targetState = WH.Get(payload.id)
        if targetState and targetState.owner == owner.identifier then
            soldOwn = true
        end
    end
end
ok(not soldOwn, 'the informant never sells your own warehouse')

-- ---------------------------------------------------------------------------
group('Routing buckets')
-- ---------------------------------------------------------------------------
-- Each warehouse must get its own stable, unique bucket, otherwise two owners
-- would share the same base game interior and see each other's rigs.
local buckets = {}
local bucketClash = false

for _, warehouse in ipairs(Config.Warehouses) do
    local bucket = WH.GetBucket(warehouse.id)

    if bucket == nil or bucket == 0 or buckets[bucket] then
        bucketClash = true
    end

    buckets[bucket] = warehouse.id
end

ok(not bucketClash, 'every warehouse has a unique non-zero bucket')
equals(WH.GetBucket(firstWarehouse.id), WH.GetBucket(firstWarehouse.id), 'bucket ids are stable')

-- Entering must move the player into the warehouse bucket.
WH.Reset(firstWarehouse.id, false)
WH.SetOwner(firstWarehouse.id, owner.identifier, owner.name)
owner.coords = vector3(firstWarehouse.entrance.x, firstWarehouse.entrance.y, firstWarehouse.entrance.z)

local enterPayload = Mock.CallCallback('codex_cryptomining:enterWarehouse', 1, firstWarehouse.id)
ok(enterPayload ~= nil and enterPayload.warehouse ~= nil, 'owner can enter his warehouse')
equals(GetPlayerRoutingBucket(1), WH.GetBucket(firstWarehouse.id), 'player moved into the warehouse bucket')

-- Leaving must put the player back into the main world.
WH.RemoveViewer(1)
WH.SetPlayerBucket(1, nil)
equals(GetPlayerRoutingBucket(1), 0, 'player returns to the main world bucket')

-- Regression: nil arguments must never raise "table index is nil".
local nilSafe = pcall(function()
    WH.RemoveViewer(nil)
    WH.AddViewer(nil, nil)
    WH.AddViewer(firstWarehouse.id, nil)
    WH.SetPlayerBucket(nil, nil)
    WH.SetPlayerBucket('not a number', firstWarehouse.id)
end)
ok(nilSafe, 'viewer and bucket helpers tolerate nil arguments')

-- The leaveWarehouse event must survive being fired without a valid source.
local eventSafe = pcall(function()
    TriggerEvent('codex_cryptomining:leaveWarehouse')
end)
ok(eventSafe, 'leaveWarehouse never crashes without a source')

-- A stranger cannot enter and must not be moved into a bucket.
thief.coords = owner.coords
Mock.buckets[3] = 0
local strangerEnter = Mock.CallCallback('codex_cryptomining:enterWarehouse', 3, firstWarehouse.id)
equals(strangerEnter, nil, 'a stranger cannot enter')
equals(GetPlayerRoutingBucket(3), 0, 'a rejected player is never bucketed')

-- Entering from far away is rejected.
owner.coords = vector3(0.0, 0.0, 0.0)
Mock.buckets[1] = 0
local farEnter = Mock.CallCallback('codex_cryptomining:enterWarehouse', 1, firstWarehouse.id)
equals(farEnter, nil, 'cannot enter a warehouse from far away')
equals(GetPlayerRoutingBucket(1), 0, 'a far away player is never bucketed')

-- Reconnecting resets the bucket.
Mock.buckets[1] = 9999
TriggerEvent('esx:playerLoaded', 1)
equals(GetPlayerRoutingBucket(1), 0, 'reconnecting resets the routing bucket')

-- ---------------------------------------------------------------------------
group('No OneSync fallback')
-- ---------------------------------------------------------------------------
-- Server side GetEntityCoords returns nothing useful without OneSync. The
-- resource must stay usable instead of locking everybody out of every action.
local savedOnesync = Mock.convars.onesync
local FWmod = CodexCryptoFW

ok(type(FWmod.IsOneSyncAvailable) == 'function', 'OneSync detection helper exists')
ok(type(FWmod.IsNear) == 'function', 'distance helper exists')
ok(type(FWmod.GetDistance) == 'function', 'GetDistance helper exists')

-- IsNear must never throw, whatever it is given.
local distanceSafe = pcall(function()
    FWmod.IsNear(1, nil, 10.0)
    FWmod.IsNear(1, {}, 10.0)
    FWmod.IsNear(1, vector3(0.0, 0.0, 0.0), 10.0)
    FWmod.IsNear(1, { vector3(1.0, 2.0, 3.0) }, 10.0)
    FWmod.IsNear(99999, { vector3(1.0, 2.0, 3.0) }, 10.0)
    FWmod.GetDistance(1, nil)
    FWmod.GetDistance(99999, vector3(0.0, 0.0, 0.0))
end)
ok(distanceSafe, 'distance helpers never crash on bad input')

-- An empty point list means "no location requirement".
ok(FWmod.IsNear(1, {}, 5.0) == true, 'an empty location list allows the action')

Mock.convars.onesync = savedOnesync

-- ---------------------------------------------------------------------------
group('Callbacks & payload safety')
-- ---------------------------------------------------------------------------
local bootstrap = Mock.CallCallback('codex_cryptomining:bootstrap', 1)
ok(bootstrap ~= nil and bootstrap.ready, 'bootstrap answers')
ok(#bootstrap.owned >= 1, 'bootstrap lists the owned warehouses')

local snapshot = Mock.CallCallback('codex_cryptomining:getWarehouse', 1, firstWarehouse.id)
ok(snapshot ~= nil, 'owner receives a snapshot')
ok(snapshot.isOwner == true, 'snapshot flags the owner')
ok(type(snapshot.rigs) == 'table', 'snapshot contains the rigs')
ok(snapshot.market ~= nil, 'snapshot embeds the market')

local strangerSnapshot = Mock.CallCallback('codex_cryptomining:getWarehouse', 3, firstWarehouse.id)
equals(strangerSnapshot, nil, 'a stranger gets no snapshot')

local unknownSnapshot = Mock.CallCallback('codex_cryptomining:getWarehouse', 1, 'does_not_exist')
equals(unknownSnapshot, nil, 'unknown warehouse id returns nil')

-- Malformed payloads must never crash the server.
local malformed = {
    'string instead of a table',
    42,
    { action = nil },
    { action = 'sellBtc' },
    { action = 'installGpu', warehouseId = firstWarehouse.id, rigId = 'abc', quantity = 'x' },
    { action = 'giveKeys', warehouseId = firstWarehouse.id, target = 'not a number' },
    { action = 'removeKeys', warehouseId = firstWarehouse.id, identifier = 12345 }
}

local crashed = false
for _, payload in ipairs(malformed) do
    local okCall, err = pcall(function()
        return Mock.CallCallback('codex_cryptomining:panelAction', 1, payload)
    end)

    if not okCall then
        crashed = true
        print('     crash on payload: ' .. tostring(err))
    end
end
ok(not crashed, 'malformed panel payloads never crash the server')

crashed = false
for _, payload in ipairs(malformed) do
    local okCall = pcall(function()
        return Mock.CallCallback('codex_cryptomining:shopAction', 1, payload)
    end)
    if not okCall then
        crashed = true
    end
end
ok(not crashed, 'malformed shop payloads never crash the server')

-- Unknown warehouse in an action.
result = panel(1, { action = 'installRig', warehouseId = 'ghost_warehouse' })
ok(result and not result.ok, 'unknown warehouse id is rejected in actions')

-- ---------------------------------------------------------------------------
group('Persistence')
-- ---------------------------------------------------------------------------
WH.Flush(true)

local savedWarehouse = nil
for _, row in ipairs(Mock.database.codex_crypto_warehouses) do
    if row.warehouse_id == secondWarehouse.id then
        savedWarehouse = row
    end
end

ok(savedWarehouse ~= nil, 'warehouse row written to the database')
equals(savedWarehouse.owner, owner.identifier, 'owner persisted')

local rigRows = 0
for _, row in ipairs(Mock.database.codex_crypto_rigs) do
    if row.warehouse_id == secondWarehouse.id then
        rigRows = rigRows + 1
    end
end
ok(rigRows >= 1, 'rig rows persisted')

-- Reload everything from the database and compare.
local btcBeforeReload = WH.Get(secondWarehouse.id).btc
local rigsBeforeReload = Crypto.TableCount(WH.Get(secondWarehouse.id).rigs)

WH.Load()
WH.LoadKeys()

equals(WH.Get(secondWarehouse.id).owner, owner.identifier, 'owner survives a reload')
near(WH.Get(secondWarehouse.id).btc, btcBeforeReload, 1e-6, 'BTC balance survives a reload')
equals(Crypto.TableCount(WH.Get(secondWarehouse.id).rigs), rigsBeforeReload, 'rigs survive a reload')

-- Regression: an unowned warehouse must persist a NULL-ish owner, never a
-- shifted column. A nil named parameter used to shift every following value.
WH.Reset(thirdWarehouse.id, false)
WH.Flush(true)

local unownedRow = nil
for _, row in ipairs(Mock.database.codex_crypto_warehouses) do
    if row.warehouse_id == thirdWarehouse.id then
        unownedRow = row
    end
end

ok(unownedRow ~= nil, 'unowned warehouse still has a row')
ok(unownedRow.owner == '' or unownedRow.owner == nil, 'unowned warehouse stores an empty owner')
equals(unownedRow.powered, 1, 'powered column is not shifted for an unowned warehouse')
equals(unownedRow.btc, 0, 'btc column is not shifted for an unowned warehouse')
equals(unownedRow.bill, 0, 'bill column is not shifted for an unowned warehouse')

WH.Load()
equals(WH.Get(thirdWarehouse.id).owner, nil, 'empty owner reloads as nil, not as an empty string')
ok(WH.Get(thirdWarehouse.id).powered == true, 'powered reloads correctly for an unowned warehouse')

-- Reset wipes everything.
WH.Reset(secondWarehouse.id, false)
equals(WH.Get(secondWarehouse.id).owner, nil, 'reset clears the owner')
equals(Crypto.TableCount(WH.Get(secondWarehouse.id).rigs), 0, 'reset clears the rigs')
equals(WH.Get(secondWarehouse.id).btc, 0.0, 'reset clears the wallet')

-- ---------------------------------------------------------------------------
group('Admin & exports')
-- ---------------------------------------------------------------------------
ok(Mock.commands[Config.Commands.Admin] ~= nil, 'admin command registered')

Mock.commands[Config.Commands.Admin](0, { 'price', '50000' })
equals(Market.GetPrice(), 50000, 'admin can set the price')

Mock.commands[Config.Commands.Admin](0, { 'price', '99999999' })
ok(Market.GetPrice() <= Config.Market.MaxPrice, 'admin price is clamped to the maximum')

local adminCrash = not pcall(function()
    Mock.commands[Config.Commands.Admin](0, { 'reset', 'unknown_warehouse' })
    Mock.commands[Config.Commands.Admin](0, { 'info' })
    Mock.commands[Config.Commands.Admin](0, {})
    Mock.commands[Config.Commands.Admin](0, { 'setowner', 'unknown', '99' })
end)
ok(not adminCrash, 'admin command never crashes on bad input')

ok(Mock.exportedFunctions.getBitcoinPrice ~= nil, 'getBitcoinPrice export exists')
equals(Mock.exportedFunctions.getBitcoinPrice(), Market.GetPrice(), 'export returns the current price')
ok(Mock.exportedFunctions.getWarehouseOwner ~= nil, 'getWarehouseOwner export exists')
equals(Mock.exportedFunctions.getWarehouseOwner('nope'), nil, 'export handles an unknown warehouse')

-- ---------------------------------------------------------------------------
group('Long run stability')
-- ---------------------------------------------------------------------------
-- Simulate a full day of ticks on a loaded warehouse and make sure nothing
-- drifts into an invalid state.
WH.Reset(firstWarehouse.id, false)
WH.SetOwner(firstWarehouse.id, owner.identifier, owner.name)

for slot = 1, 5 do
    local rig = WH.AddRig(firstWarehouse.id, slot)
    rig.gpus = 8
end

local longState = WH.Get(firstWarehouse.id)
longState.powered = true

local invalid = false
for _ = 1, 24 * 60 do
    WH.Tick(firstWarehouse.id, 60)

    if longState.btc < 0 or longState.bill < 0 then
        invalid = true
        break
    end

    for _, rig in pairs(longState.rigs) do
        if rig.durability < 0 or rig.durability > 100 or rig.gpus < 0 or rig.gpus > Crypto.GetMaxGpus() then
            invalid = true
            break
        end
    end

    if invalid then
        break
    end
end

ok(not invalid, 'a full simulated day keeps every value in a valid range')
ok(longState.btc >= 0, 'BTC balance never goes negative')

-- The scheduler must still be healthy.
local tickCrash = not pcall(function()
    Mock.Tick(120000)
end)
ok(not tickCrash, 'background threads run for two more minutes without error')

-- ---------------------------------------------------------------------------
-- RESULTS
-- ---------------------------------------------------------------------------
print(('\n\27[1m================ RESULT ================\27[0m'))
print(('  passed: \27[32m%d\27[0m'):format(passed))
print(('  failed: %s%d\27[0m'):format(failed > 0 and '\27[31m' or '\27[32m', failed))

if failed > 0 then
    print('\n\27[31mFailures:\27[0m')
    for _, failure in ipairs(failures) do
        print('  - ' .. failure)
    end
    os.exit(1)
end

print('\n\27[32mAll tests passed.\27[0m')
os.exit(0)
