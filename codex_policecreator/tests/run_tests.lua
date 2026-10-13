--[[
    tests/run_tests.lua - executes the real server modules against the mock
    runtime and asserts on behaviour.

    python3 tests/run_lua_tests.py     (or: lua tests/run_tests.lua)
]]

local Mock = dofile('tests/mock_fivem.lua')

dofile('config.lua')
dofile('shared/core.lua')
dofile('shared/bridge.lua')

dofile('server/db.lua')
dofile('server/departments.lua')
dofile('server/members.lua')
dofile('server/finance.lua')
dofile('server/duty.lua')
dofile('server/armory.lua')
dofile('server/garage.lua')
dofile('server/evidence.lua')
dofile('server/dispatch.lua')
dofile('server/bolo.lua')
dofile('server/cameras.lua')
dofile('server/trackers.lua')
dofile('server/main.lua')

-- ---------------------------------------------------------------------------
-- TINY TEST FRAMEWORK
-- ---------------------------------------------------------------------------
local passed, failed = 0, 0
local failures = {}
local currentGroup = ''

local function group(name)
    currentGroup = name
end

local function check(condition, message)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = ('[%s] %s'):format(currentGroup, message or 'assertion failed')
    end
end

local function eq(actual, expected, message)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = ('[%s] %s (expected %s, got %s)')
            :format(currentGroup, message or 'values differ', tostring(expected), tostring(actual))
    end
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = ('[%s] %s threw: %s'):format(currentGroup, name, tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- BOOT
-- ---------------------------------------------------------------------------
Mock.Tick(0)

group('boot')
check(DB.IsReady(), 'tables created')
check(Departments.Count() >= 1, 'default department seeded')
check(Bridge.Mode() == 'qbcore', 'qbcore detected, got ' .. tostring(Bridge.Mode()))
eq(Mock.RowCount('codex_pc_ranks') >= 6, true, 'template ranks inserted')

local lspd = Departments.GetByName('lspd')
check(lspd ~= nil, 'lspd exists')
check(#lspd.ranks == 6, 'lspd has 6 ranks')

-- ---------------------------------------------------------------------------
-- CORE HELPERS
-- ---------------------------------------------------------------------------
group('core')
eq(Core.NormalizePlate(' abc123 '), 'ABC123', 'plate normalised')
eq(Core.NormalizePlate(nil), '', 'nil plate')
eq(Core.FormatMoney(1234567), '$1,234,567', 'money format')
eq(Core.FormatMoney(-50), '-$50', 'negative money format')
eq(Core.SecondsToClock(3725), '01:02', 'seconds to clock')
eq(Core.SanitizeLabel("  O'Malley; DROP  "), 'OMalley DROP', 'label sanitised')
eq(Core.Clamp(15, 0, 10), 10, 'clamp upper')
eq(Core.Clamp(-3, 0, 10), 0, 'clamp lower')

local perms = Core.DecodePerms('dispatch,evidence,garage')
eq(perms.dispatch, true, 'perm decoded')
eq(perms.finance, nil, 'missing perm is nil')
eq(Core.EncodePerms({ b = true, a = true }), 'a,b', 'perms encoded sorted')
eq(Core.DecodePerms('all').all, true, 'all permission decoded')

eq(Core.Distance(0, 0, 0, 3, 4, 0), 5, 'distance 3-4-5')
check(Core.Distance(0, 0, 0, 1, 1, 1) > 1.7, 'distance 3d')

-- ---------------------------------------------------------------------------
-- DEPARTMENTS
-- ---------------------------------------------------------------------------
group('departments')

local bcsoId, bcso = Departments.Create({ name = 'BCSO', label = "Blaine County Sheriff's Office", template = 'sheriff' })
check(bcsoId ~= nil, 'department created')
eq(bcso.name, 'bcso', 'name lowercased and stripped')
eq(#bcso.ranks, 4, 'sheriff template has 4 ranks')

local duplicate = { Departments.Create({ name = 'bcso', label = 'dup', template = 'police' }) }
eq(duplicate[1], nil, 'duplicate name rejected')
eq(duplicate[2], 'exists', 'duplicate reason')

local invalid = { Departments.Create({ name = '!!!', template = 'police' }) }
eq(invalid[2], 'invalid_name', 'invalid name rejected')

local customId = Departments.Create({ name = 'fib_test', template = 'fib', funds = 5000 })
local custom = Departments.Get(customId)
eq(custom.funds, 5000, 'starting funds honoured')
eq(custom.type, 'police', 'template type applied')

local updated = Departments.Update(bcsoId, { label = 'BCSO Renamed', defaultSalary = 300 })
eq(updated.label, 'BCSO Renamed', 'department label updated')
eq(updated.defaultSalary, 300, 'default salary updated')

-- nodes
local bossNode = Departments.AddNode(bcsoId, { type = 'boss', label = 'HQ', x = 100.0, y = 100.0, z = 30.0, heading = 90.0 })
check(bossNode ~= nil, 'boss node added')

local uniqueAgain = { Departments.AddNode(bcsoId, { type = 'boss', label = 'HQ2', x = 200.0, y = 200.0, z = 30.0 }) }
eq(uniqueAgain[2], 'unique', 'second unique node rejected')

local tooClose = { Departments.AddNode(bcsoId, { type = 'armory', label = 'A', x = 101.0, y = 100.0, z = 30.0 }) }
eq(tooClose[2], 'too_close', 'node too close rejected')

local badType = { Departments.AddNode(bcsoId, { type = 'not_a_type', x = 300.0, y = 300.0, z = 30.0 }) }
eq(badType[2], 'invalid_type', 'unknown node type rejected')

local garageNode = Departments.AddNode(bcsoId, { type = 'garage', label = 'Garage', x = 120.0, y = 100.0, z = 30.0, heading = 0.0 })
check(garageNode ~= nil, 'garage node added')
check(Core.FindNode(Departments.Get(bcsoId), 'garage') ~= nil, 'FindNode locates garage')

-- ranks
local newRankId = Departments.CreateRank(bcsoId, { label = 'Chaplain', salary = 99, perms = { 'dispatch' } })
check(newRankId ~= nil, 'rank created')
local withChaplain = Departments.Get(bcsoId)
eq(#withChaplain.ranks, 5, 'rank count increased')

Departments.UpdateRank(newRankId, { label = 'Senior Chaplain', salary = 150 })
local chaplain = Core.FindRankById(Departments.Get(bcsoId), newRankId)
eq(chaplain.label, 'Senior Chaplain', 'rank renamed')
eq(chaplain.salary, 150, 'rank salary updated')

-- divisions
local k9Id = Departments.CreateDivision(bcsoId, 'K9', 'K9 Unit')
check(k9Id ~= nil, 'division created')
local dupDivision = { Departments.CreateDivision(bcsoId, 'k9', 'dup') }
eq(dupDivision[2], 'exists', 'duplicate division rejected')

-- funds
local startFunds = Departments.Get(bcsoId).funds
check(startFunds > 0, 'template starting funds applied')
local balance = Departments.AddFunds(bcsoId, 1500, 'deposit', 'Test Officer', 'TEST')
eq(balance, startFunds + 1500, 'funds added')
eq(Departments.Get(bcsoId).funds, startFunds + 1500, 'funds balance stored')
local negative = { Departments.AddFunds(bcsoId, -(startFunds + 1500 + 1), 'withdraw', 'Test', 'TEST') }
eq(negative[2], 'insufficient', 'cannot go below zero')

-- ---------------------------------------------------------------------------
-- MEMBERS
-- ---------------------------------------------------------------------------
group('members')

Mock.AddPlayer(1, { citizenid = 'ABC123', firstName = 'John', lastName = 'Doe', bank = 10000 })
Mock.AddPlayer(2, { citizenid = 'XYZ789', firstName = 'Jane', lastName = 'Roe', bank = 500 })
Mock.AddPlayer(3, { citizenid = 'BOSS01', firstName = 'Chief', lastName = 'Wiggum', bank = 0 })

eq(Bridge.GetIdentifier(1), 'ABC123', 'identifier from qbcore')
eq(Bridge.GetCharName(1), 'John', 'first name from qbcore')
eq(Bridge.GetMoney(1), 10000, 'bank money read')

local sheriffRank = Core.SortedRanks(Departments.Get(bcsoId))[1]
local bossRank = nil
for _, rank in ipairs(Core.SortedRanks(Departments.Get(bcsoId))) do
    if rank.boss then bossRank = rank end
end
check(bossRank ~= nil, 'boss rank exists')

local john = Members.Hire(bcsoId, 'ABC123', 'John', 'Doe', sheriffRank.id)
check(john ~= nil, 'john hired')
eq(john.rankId, sheriffRank.id, 'rank stored')
eq(Members.CountByDept(bcsoId), 1, 'member counted')

local again = { Members.Hire(bcsoId, 'ABC123', 'John', 'Doe') }
eq(again[2], 'already_member', 'double hire rejected')

local chief = Members.Hire(bcsoId, 'BOSS01', 'Chief', 'Wiggum', bossRank.id)
check(chief ~= nil, 'chief hired')

local jane = Members.Hire(bcsoId, 'XYZ789', 'Jane', 'Roe', sheriffRank.id)
check(jane ~= nil, 'jane hired')
eq(Members.Count(), 3, 'three members total')

Members.SetRank('XYZ789', Core.SortedRanks(Departments.Get(bcsoId))[2].id)
eq(Members.Get('XYZ789').rankId, Core.SortedRanks(Departments.Get(bcsoId))[2].id, 'jane promoted')

Members.SetSalary('XYZ789', 999)
eq(Members.Get('XYZ789').salary, 999, 'salary overridden')

Members.SetDivision('XYZ789', k9Id)
eq(Members.Get('XYZ789').divisionId, k9Id, 'division assigned')

local badDivision = { Members.SetDivision('XYZ789', 9999) }
eq(badDivision[2], 'no_division', 'unknown division rejected')

-- permissions
local bcsoDept = Departments.Get(bcsoId)
check(Core.HasPerm(bcsoDept, Members.Get('BOSS01'), 'finance'), 'boss has every permission')
check(not Core.HasPerm(bcsoDept, Members.Get('ABC123'), 'finance'), 'deputy has no finance permission')
eq(Core.MaxAssignableGrade(bcsoDept, Members.Get('ABC123')), -1, 'lowest rank cannot promote')
eq(Core.MaxAssignableGrade(bcsoDept, Members.Get('BOSS01')), Core.HighestGrade(bcsoDept), 'boss can promote anyone')

-- applications
local appId = Members.Apply(bcsoId, 'NEWGUY', 'I want to join')
check(appId ~= nil, 'application created')
local pendingAgain = { Members.Apply(bcsoId, 'NEWGUY', 'again') }
eq(pendingAgain[2], 'pending', 'duplicate pending application rejected')

local resolved = Members.ResolveApplication(appId, 'accepted')
check(resolved ~= nil, 'application resolved')
check(Members.Get('NEWGUY') ~= nil, 'applicant hired automatically')
eq(Members.CountByDept(bcsoId), 4, 'member count after application')

local payload = Members.Payload(bcsoId)
eq(#payload, 4, 'payload contains every member')
eq(payload[1].grade >= payload[#payload].grade, true, 'payload sorted by grade descending')
eq(payload[1].online, true, 'online flag set for connected players')

-- ---------------------------------------------------------------------------
-- DUTY
-- ---------------------------------------------------------------------------
group('duty')

local onDuty = Duty.SetDuty('ABC123', true)
eq(onDuty.onDuty, true, 'went on duty')
eq(Duty.Get('ABC123'), true, 'duty getter')
check(Mock.RowCount('codex_pc_duty_logs') == 1, 'duty log opened')

local unchanged = Duty.SetDuty('ABC123', true)
eq(unchanged, onDuty, 'double on-duty returns member')

Mock.AdvanceOsTime(600)
local offDuty = Duty.SetDuty('ABC123', false)
eq(offDuty.onDuty, false, 'went off duty')
eq(offDuty.dutySeconds, 600, 'duty time accrued')

local logs = Duty.Logs(bcsoId)
eq(#logs, 1, 'one duty log')
eq(logs[1].duration, 600, 'log duration stored')
eq(logs[1].clock, '00:10', 'log clock format')

Duty.SetDuty('ABC123', true)
Duty.SetDuty('XYZ789', true)
local onDutyList = Duty.OnDuty(bcsoId)
eq(#onDutyList, 2, 'two officers on duty')
eq(#Duty.OnDutyByType('police') >= 2, true, 'on duty by type')

-- orphan cleanup on restart
Duty.CloseOrphans()
eq(Duty.Get('ABC123'), false, 'orphaned duty cleared')
eq(Mock.Table('codex_pc_duty_logs')[#Mock.Table('codex_pc_duty_logs')].went_off > 0, true, 'orphan log closed')

-- ---------------------------------------------------------------------------
-- FINANCE
-- ---------------------------------------------------------------------------
group('finance')

local okDeposit = { Finance.Deposit(1, 2000) }
eq(okDeposit[1], true, 'deposit accepted')
eq(Mock.RowCount('codex_pc_finance_logs') >= 1, true, 'finance log written')
eq(Bridge.GetMoney(1), 8000, 'player charged')

local tooMuch = { Finance.Deposit(1, 999999) }
eq(tooMuch[2], 'no_money', 'deposit rejected without funds')

-- withdraw requires the finance permission: the deputy must fail
local deputyWithdraw = { Finance.Withdraw(1, 100) }
eq(deputyWithdraw[2], 'no_permission', 'deputy cannot withdraw')

-- promote john to the boss rank so he can use finance
Members.SetRank('ABC123', bossRank.id)
local withdraw = { Finance.Withdraw(1, 500) }
eq(withdraw[1], true, 'boss can withdraw')
eq(Bridge.GetMoney(1), 8500, 'withdraw credited')

local overdraw = { Finance.Withdraw(1, 999999) }
eq(overdraw[2], 'insufficient', 'cannot overdraw')

Members.SetRank('ABC123', sheriffRank.id)

-- bonus to another member
Members.SetRank('BOSS01', bossRank.id)
local bonus = { Finance.Bonus(3, 'XYZ789', 250) }
eq(bonus[1], true, 'bonus paid')
eq(Bridge.GetMoney(2), 750, 'bonus received')

-- salary payout
Departments.SetFunds(bcsoId, 100000)
local paid, total = Finance.PayoutDepartment(bcsoId)
eq(paid, 4, 'every member paid')
check(total > 0, 'payout total positive')
check(Departments.Get(bcsoId).funds < 100000, 'funds reduced by salaries')

local forcedPaid = { Finance.PayoutAll(true) }
check(forcedPaid[1] >= 4, 'forced payout runs for all departments')

local logs2 = Finance.Logs(bcsoId, 10)
check(#logs2 >= 3, 'finance logs returned')
check(logs2[1].date ~= nil, 'finance log has a formatted date')

-- ---------------------------------------------------------------------------
-- ARMORY
-- ---------------------------------------------------------------------------
group('armory')

local catalog = Armory.Catalog(Departments.Get(bcsoId), Members.Get('ABC123'))
eq(#catalog, #Config.Armory.Items, 'catalogue lists every configured item')

local nightstickIndex
local rifleIndex
for index, entry in ipairs(catalog) do
    if entry.item == 'WEAPON_NIGHTSTICK' then nightstickIndex = index end
    if entry.item == 'WEAPON_CARBINERIFLE' then rifleIndex = index end
end

check(nightstickIndex ~= nil, 'nightstick in catalogue')
check(rifleIndex ~= nil, 'rifle in catalogue')

-- a Corporal may use the armory but is below the rifle's minimum grade
Members.SetRank('ABC123', Core.SortedRanks(Departments.Get(bcsoId))[2].id)
local takeRifle = { Armory.Take(1, rifleIndex) }
eq(takeRifle[2], 'rank_too_low', 'junior rank cannot take a rifle')

Members.SetRank('ABC123', Core.SortedRanks(Departments.Get(bcsoId))[4].id)
local takeAgain = { Armory.Take(1, rifleIndex) }
eq(takeAgain[1], true, 'senior rank can take the rifle')
eq(Mock.ItemCount(1, 'WEAPON_CARBINERIFLE'), 1, 'rifle in inventory')

local storeRifle = { Armory.Store(1, rifleIndex) }
eq(storeRifle[1], true, 'rifle returned')
eq(Mock.ItemCount(1, 'WEAPON_CARBINERIFLE'), 0, 'rifle removed from inventory')

local storeMissing = { Armory.Store(1, rifleIndex) }
eq(storeMissing[2], 'no_item', 'cannot return what you do not have')

local badIndex = { Armory.Take(1, 9999) }
eq(badIndex[2], 'invalid_item', 'unknown catalogue index rejected')

-- ---------------------------------------------------------------------------
-- GARAGE
-- ---------------------------------------------------------------------------
group('garage')

local seeded = Garage.Seed(bcsoId)
check(seeded > 0, 'garage seeded with defaults')
eq(#Garage.List(bcsoId), seeded, 'seeded vehicles cached')

local added = Garage.Add(bcsoId, { model = 'POLICE3', label = 'Unmarked', rankMin = 1, spawnNode = garageNode })
check(added ~= nil, 'vehicle added')
eq(added.model, 'police3', 'model lowercased')
check(#added.plate <= 8, 'plate fits 8 characters')

local badNode = { Garage.Add(bcsoId, { model = 'police', spawnNode = 99999 }) }
eq(badNode[2], 'invalid_node', 'invalid spawn node rejected')

local badModel = { Garage.Add(bcsoId, { model = '' }) }
eq(badModel[2], 'invalid_model', 'empty model rejected')

-- spawn requires the garage permission and the right rank
Members.SetRank('ABC123', Core.SortedRanks(Departments.Get(bcsoId))[1].id)
local deputySpawn = { Garage.Spawn(1, added.id, garageNode, { x = 120.0, y = 100.0, z = 30.0 }) }
eq(deputySpawn[2], 'no_permission', 'deputy cannot use the garage')

Members.SetRank('ABC123', Core.SortedRanks(Departments.Get(bcsoId))[3].id)
local farSpawn = { Garage.Spawn(1, added.id, garageNode, { x = 9000.0, y = 9000.0, z = 30.0 }) }
eq(farSpawn[2], 'too_far', 'spawn rejected when far from the node')

local spawned, spawnError = Garage.Spawn(1, added.id, garageNode, { x = 120.0, y = 100.0, z = 30.0 })
check(type(spawned) == 'table', 'vehicle spawned (' .. tostring(spawnError) .. ')')
eq(spawned and spawned.plate, added.plate, 'correct plate returned')
eq(spawned and spawned.coords.x, 120.0, 'spawn point returned')

local spawnAgain = { Garage.Spawn(1, added.id, garageNode) }
eq(spawnAgain[2], 'already_out', 'cannot take the same vehicle twice')

local returned = Garage.Return(1, added.id, { fuel = 42, bodyHealth = 800, engineHealth = 900 })
eq(returned, true, 'vehicle returned')
eq(Garage.Find(added.id).fuel, 42, 'fuel saved')
eq(Garage.Find(added.id).bodyHealth, 800, 'body health saved')

Garage.SetImpound(added.id, true)
eq(Garage.Find(added.id).impounded, true, 'vehicle impounded')
local impoundedSpawn = { Garage.Spawn(1, added.id, garageNode) }
eq(impoundedSpawn[2], 'impounded', 'impounded vehicle cannot be taken')
Garage.SetImpound(added.id, false)

-- drop cleanup
Garage.Spawn(1, added.id, garageNode)
eq(Garage.ReturnByCitizen('ABC123'), 1, 'dropped player vehicle stored')
eq(Garage.Find(added.id).stored, true, 'vehicle stored after drop')

-- ---------------------------------------------------------------------------
-- EVIDENCE
-- ---------------------------------------------------------------------------
group('evidence')

Duty.SetDuty('ABC123', true)
local offDutyEvidence = { Evidence.Create(2, { label = 'Test', grade = 1, x = 1, y = 2, z = 3 }) }
eq(offDutyEvidence[2], 'off_duty', 'off duty officers cannot file evidence')

Mock.GiveItem(1, Config.Evidence.BagItem, 2)
local noBag = { Evidence.Create(2, { label = 'Test', grade = 1, x = 1, y = 2, z = 3 }) }
check(noBag[1] == nil, 'jane is off duty too')

local evidenceId = Evidence.Create(1, { label = 'Bloody knife', description = 'Found at the scene', grade = 3, x = 10.0, y = 20.0, z = 30.0, owner = 'John Doe' })
check(evidenceId ~= nil, 'evidence stored')
eq(Mock.ItemCount(1, Config.Evidence.BagItem), 1, 'one bag consumed')

local emptyLabel = { Evidence.Create(1, { label = '', grade = 1 }) }
eq(emptyLabel[2], 'invalid_label', 'empty label rejected')

local list = Evidence.List(bcsoId)
eq(#list, 1, 'evidence listed')
eq(list[1].grade, 3, 'grade stored')
eq(list[1].bagged, true, 'evidence is bagged')

local took = Evidence.Take(1, evidenceId)
eq(took, true, 'evidence checked out')
eq(Mock.ItemCount(1, Config.Evidence.BagItem), 2, 'bag given back')

local takeTwice = { Evidence.Take(1, evidenceId) }
eq(takeTwice[2], 'taken', 'cannot check out twice')

-- demote so the 'manage' permission check is actually exercised
Members.SetRank('ABC123', Core.SortedRanks(Departments.Get(bcsoId))[2].id)
local deleteDenied = { Evidence.Delete(1, evidenceId) }
eq(deleteDenied[2], 'no_permission', 'non manager cannot destroy evidence')

Members.SetRank('ABC123', bossRank.id)
local deleted = Evidence.Delete(1, evidenceId)
eq(deleted, true, 'boss destroyed the evidence')
eq(#Evidence.List(bcsoId), 0, 'evidence removed')

-- ---------------------------------------------------------------------------
-- DISPATCH
-- ---------------------------------------------------------------------------
group('dispatch')

Mock.ResetClientEvents()
local call = Dispatch.Create(2, { code = '10-31', description = 'Shots fired' })
check(call ~= nil, 'call created')
eq(call.code, '10-31', 'call code')
check(call.id ~= nil, 'call row id')

-- the payload id belongs to whichever department was routed first, so look the
-- BCSO row up explicitly - that is the one john may act on
local bcsoCall
for _, entry in ipairs(Dispatch.List(bcsoId)) do
    if entry.code == '10-31' then bcsoCall = entry break end
end
check(bcsoCall ~= nil, 'call routed to BCSO')

local badCode = { Dispatch.Create(3, { code = 'nope' }) }
eq(badCode[2], 'invalid_code', 'unknown code rejected')

local broadcast = Mock.ClientEvents(':client:newCall')
check(#broadcast >= 1, 'call broadcast to on-duty units')

local accept = Dispatch.Accept(1, bcsoCall.id)
eq(accept, true, 'call accepted')

Duty.SetDuty('BOSS01', true)
local stolen = { Dispatch.Accept(3, bcsoCall.id) }
eq(stolen[2], 'taken', 'another officer cannot steal an assigned call')

local release = Dispatch.Release(1, bcsoCall.id)
eq(release, true, 'call released')

-- only john is on duty now, so exactly one client should hear about the closure
Duty.SetDuty('BOSS01', false)
Mock.ResetClientEvents()
local closed = Dispatch.Close(1, bcsoCall.id)
eq(closed, true, 'call closed')
eq(#Mock.ClientEvents(':client:callClosed'), 1, 'closure broadcast to on-duty units')

local closeAgain = Dispatch.Close(1, 999999)
eq(closeAgain, false, 'unknown call cannot be closed')

-- ---------------------------------------------------------------------------
-- BOLO / ALPR
-- ---------------------------------------------------------------------------
group('bolo')

-- a Corporal has no 'bolo' permission
Members.SetRank('ABC123', Core.SortedRanks(Departments.Get(bcsoId))[2].id)
local noPerm = { Bolo.Create(1, { type = 'plate', value = 'ABC123' }) }
eq(noPerm[2], 'no_permission', 'junior rank cannot publish BOLOs')
eq(#Bolo.List(bcsoId), 0, 'rejected BOLO was not stored')

Members.SetRank('ABC123', Core.SortedRanks(Departments.Get(bcsoId))[3].id)
local boloId = Bolo.Create(1, { type = 'plate', value = ' abc123 ', description = 'Stolen cruiser' })
check(boloId ~= nil, 'bolo created')
eq(Bolo.List(bcsoId)[1].value, 'ABC123', 'plate normalised on insert')

local badType = { Bolo.Create(1, { type = 'spaceship', value = 'x' }) }
eq(badType[2], 'invalid_type', 'unknown bolo type rejected')

local match = Bolo.MatchPlate('abc123')
check(match ~= nil, 'ALPR matched the plate')
eq(match.description, 'Stolen cruiser', 'bolo description returned')
eq(Bolo.MatchPlate('zzz999'), nil, 'clean plate has no hit')

Bolo.SetActive(1, boloId, false)
eq(Bolo.MatchPlate('abc123'), nil, 'deactivated bolo does not match')
Bolo.SetActive(1, boloId, true)

local personBolo = Bolo.Create(1, { type = 'person', value = 'John Doe', description = 'Wanted' })
check(personBolo ~= nil, 'person bolo created')
check(Bolo.MatchPerson('john doe') ~= nil, 'person matched case insensitively')

local otherDeptBolo = { Bolo.Delete(2, personBolo) }
eq(otherDeptBolo[2], 'no_permission', 'off duty member cannot delete')

-- ---------------------------------------------------------------------------
-- CAMERAS / TRACKERS
-- ---------------------------------------------------------------------------
group('cameras')

local camId = Cameras.Add(bcsoId, { label = 'Main street', x = 1.0, y = 2.0, z = 3.0, heading = 45.0, rankMin = 0 })
check(camId ~= nil, 'camera added')
eq(#Cameras.List(bcsoId), 1, 'camera listed')

local restricted = Cameras.Add(bcsoId, { label = 'Evidence room', rankMin = 99 })
local visible = Cameras.ForMember(bcsoId, Members.Get('ABC123'))
eq(#visible, 1, 'rank restricted camera hidden')
_ = restricted

group('trackers')

-- trackers need the 'trackers' permission: use the boss rank, not the chaplain
Members.SetRank('ABC123', bossRank.id)
Duty.SetDuty('ABC123', true)

local noItem = { Trackers.Place(1, { plate = 'TEST123', netId = 555, x = 1, y = 2, z = 3 }) }
eq(noItem[2], 'no_item', 'tracker needs the item')

Mock.GiveItem(1, Config.Trackers.Item, 1)
local trackerId = Trackers.Place(1, { plate = 'TEST123', netId = 555, x = 1.0, y = 2.0, z = 3.0 })
check(trackerId ~= nil, 'tracker placed')
eq(Mock.ItemCount(1, Config.Trackers.Item), 0, 'tracker item consumed')

Trackers.Update(1, trackerId, { x = 9.0, y = 9.0, z = 9.0 })
local activeTrackers = Trackers.List(bcsoId, true)
eq(activeTrackers[1] and activeTrackers[1].x, 9.0, 'tracker position updated')

local recovered = Trackers.Recover(1, trackerId)
eq(recovered, true, 'tracker recovered')
eq(Mock.ItemCount(1, Config.Trackers.Item), 1, 'tracker item returned')
eq(#Trackers.List(bcsoId, true), 0, 'no active trackers left')

-- ---------------------------------------------------------------------------
-- MAIN: PAYLOADS, EVENTS, COMMANDS
-- ---------------------------------------------------------------------------
group('main')

local menu = Main.MenuPayload(1)
eq(menu.error, nil, 'menu payload built')
eq(menu.dept.id, bcsoId, 'correct department')
check(menu.perms ~= nil, 'permissions included')
eq(#menu.members, 4, 'members included')
check(menu.armory ~= nil, 'armory catalogue included')
check(menu.codes ~= nil, 'dispatch codes included')

local outsiderMenu = Main.MenuPayload(99)
eq(outsiderMenu.error, 'no_character', 'unknown player rejected')

local sync = Main.SyncPayload(1)
eq(sync.canCreate, false, 'normal player cannot create departments')
eq(sync.deptId, bcsoId, 'sync carries the member department')
check(#sync.departments >= 2, 'all departments synced')

-- node use validation
Mock.ResetClientEvents()
local bossNodeRow = Core.FindNode(Departments.Get(bcsoId), 'boss')
Mock.SetCoords(1, bossNodeRow.x, bossNodeRow.y, bossNodeRow.z)
Mock.TriggerServer('codex_policecreator:server:useNode', 1, bcsoId, bossNodeRow.id, 'boss')
eq(#Mock.ClientEvents(':client:menuData'), 1, 'boss node opens the menu')

-- far away from the node the same request must be refused
Mock.ResetClientEvents()
Mock.SetCoords(1, 9000.0, 9000.0, 30.0)
Mock.TriggerServer('codex_policecreator:server:useNode', 1, bcsoId, bossNodeRow.id, 'boss')
eq(#Mock.ClientEvents(':client:menuData'), 0, 'node use rejected when too far away')

Mock.ResetClientEvents()
Mock.TriggerServer('codex_policecreator:server:useNode', 1, lspd.id, 1, 'boss')
eq(#Mock.ClientEvents(':client:notify'), 1, 'wrong department blocked')

-- hire nearby
Mock.SetCoords(1, 0.0, 0.0, 0.0)
Mock.SetCoords(2, 1.0, 0.0, 0.0)
Members.Fire('XYZ789')
Mock.TriggerServer('codex_policecreator:server:hireNearby', 1, Core.SortedRanks(Departments.Get(bcsoId))[1].id)
check(Members.Get('XYZ789') ~= nil, 'nearby player hired')

-- duty command
Mock.RunCommand(Config.Commands.Duty, 1)
eq(Members.Get('ABC123').onDuty, false, '/duty toggled off')
Mock.RunCommand(Config.Commands.Duty, 1)
eq(Members.Get('ABC123').onDuty, true, '/duty toggled on')

-- 911 (wait out the civilian call cooldown first)
Mock.AdvanceOsTime(120)
Mock.ResetClientEvents()
Mock.RunCommand(Config.Commands.Call, 2, { 'shooting' })
check(#Mock.ClientEvents(':client:newCall') >= 1, '/911 created a call')

-- creator command requires permission
Mock.ResetClientEvents()
Mock.RunCommand(Config.Commands.Creator, 1)
eq(#Mock.ClientEvents(':client:openCreator'), 0, 'normal player cannot open the creator')

-- creator events require permission
Mock.ResetClientEvents()
Mock.TriggerServer('codex_policecreator:server:creatorCreate', 1, { name = 'hacked', template = 'police' })
eq(Departments.GetByName('hacked'), nil, 'unauthorised department creation blocked')
eq(#Mock.ClientEvents(':client:notify'), 1, 'unauthorised creator notified')

-- node add through the event with permission granted
Config.Ace.Creator = false
Config.CreatorJobs = { 'unemployed' }
Mock.ResetClientEvents()
Mock.TriggerServer('codex_policecreator:server:creatorAddNode', 1, bcsoId,
    { type = 'evidence', label = 'Board', x = 500.0, y = 500.0, z = 30.0, heading = 0.0, blip = true })
check(Core.FindNode(Departments.Get(bcsoId), 'evidence') ~= nil, 'evidence node placed through the event')

-- alpr scan end to end
Mock.ResetClientEvents()
Mock.TriggerServer('codex_policecreator:server:alprScan', 1, 'abc123', 'Police Cruiser')
check(#Mock.ClientEvents(':client:alprHit') >= 1, 'ALPR scan produced a hit')

Mock.ResetClientEvents()
Mock.TriggerServer('codex_policecreator:server:alprScan', 1, 'zzz111', 'Civic')
eq(#Mock.ClientEvents(':client:alprHit'), 0, 'clean plate produces no hit')

-- k9 sniff
Mock.ResetClientEvents()
Mock.GiveItem(2, 'weed', 3)
Members.SetRank('ABC123', bossRank.id)
Mock.TriggerServer('codex_policecreator:server:k9SniffPlayer', 1, 2)
local sniffResults = Mock.ClientEvents(':client:k9Result')
eq(#sniffResults, 1, 'k9 sniff answered')
eq(sniffResults[1].args[1].found, true, 'contraband detected')

-- player dropped cleanup
Members.SetRank('ABC123', bossRank.id)
Garage.Spawn(1, added.id, garageNode)
Mock.TriggerServer('playerDropped', 1)
eq(Garage.Find(added.id).stored, true, 'vehicle stored when the owner dropped')
eq(Members.Get('ABC123').onDuty, false, 'duty cleared on drop')

-- exports
check(Mock.registeredExports.IsMember ~= nil, 'IsMember export registered')
eq(Mock.registeredExports.IsMember('ABC123'), true, 'IsMember export works')
eq(Mock.registeredExports.IsMember('NOPE'), false, 'IsMember export rejects strangers')
eq(Mock.registeredExports.IsOnDuty('ABC123'), false, 'IsOnDuty export works')
eq(Mock.registeredExports.GetDepartment('bcso') ~= nil, true, 'GetDepartment by name works')
eq(Mock.registeredExports.GetDepartment(9999), nil, 'GetDepartment rejects unknown ids')
local hiredExport = Mock.registeredExports.Hire(bcsoId, 'EXPORT01', 'Ex', 'Port')
check(hiredExport ~= nil, 'Hire export works')
local fundsBefore = Departments.Get(bcsoId).funds
eq(Mock.registeredExports.AddFunds('bcso', 100, 'adjust', 'Test'), fundsBefore + 100, 'AddFunds export works')

-- ---------------------------------------------------------------------------
-- RESULT
-- ---------------------------------------------------------------------------
print('')
print(('codex_policecreator test suite: %d passed, %d failed'):format(passed, failed))

if failed > 0 then
    print('')
    for _, message in ipairs(failures) do
        print('  FAIL ' .. message)
    end
    os.exit(1)
end

print('all tests passed')
os.exit(0)
