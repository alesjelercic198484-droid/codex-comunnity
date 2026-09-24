--[[
    codex_bodyharvest - automated simulation / test suite

        lua tests/run_tests.lua          (from the resource folder)
        python3 tests/run_lua_tests.py   (if you have no system Lua)

    The suite boots the real client and server scripts on top of the FiveM mock
    with four players (killer, victim, police officer, civilian) and asserts on
    the actual behaviour: target options, animation, one part per body, police
    alert, open fire zone, blips, dealer economy and every anti cheat guard.
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

-- ---------------------------------------------------------------------------
-- WORLD
-- ---------------------------------------------------------------------------
local KILLER, VICTIM, COP, CIVIL = 1, 2, 3, 4

Mock.AddPlayer({ id = KILLER, name = 'Marco Vitelli', x = 100.0, y = 100.0, z = 30.0, items = { WEAPON_KNIFE = 1 } })
Mock.AddPlayer({ id = VICTIM, name = 'Dead Guy',     x = 101.0, y = 100.0, z = 30.0 })
Mock.AddPlayer({ id = COP,    name = 'Officer Kim',  x = 800.0, y = 800.0, z = 30.0, job = 'police' })
Mock.AddPlayer({ id = CIVIL,  name = 'Random Civ',   x = 300.0, y = 300.0, z = 30.0 })

local Config = Mock.LoadConfig('config.lua')
Mock.LoadServer('server/main.lua')

for _, id in ipairs({ KILLER, VICTIM, COP, CIVIL }) do
    Mock.LoadClient(id, 'client/main.lua')
end

Mock.Tick(2000)

local function partConfig(id)
    for _, part in ipairs(Config.Parts) do
        if part.id == id then
            return part
        end
    end
end

local function notificationCount(id, needle)
    return #Mock.Notifications(id, needle)
end

local function hasNotification(id, needle)
    return notificationCount(id, needle) > 0
end

--- Performs a full cut through the ox_target UI, exactly like a player.
local function cutPart(killerId, victimId, partId)
    local options = Mock.PlayerOptions(killerId, victimId)
    Mock.Select(killerId, options, partId, Mock.players[victimId].ped)
    Mock.Tick(partConfig(partId).duration + 1500)
end

-- ---------------------------------------------------------------------------
group('Boot / registration')
-- ---------------------------------------------------------------------------
equals(#Mock.players[KILLER].target.globalPlayer, 3, 'three ox_target options are registered on players')

local labels = Mock.OptionLabels(Mock.players[KILLER].target.globalPlayer)
equals(labels[1], 'Cut the finger', 'option 1 is "Cut the finger"')
equals(labels[2], 'Cut the ear', 'option 2 is "Cut the ear"')
equals(labels[3], 'Cut the tongue', 'option 3 is "Cut the tongue"')

local dealerPed = Mock.DealerPed(KILLER)
ok(dealerPed ~= nil, 'hidden dealer ped is spawned')
equals(#(Mock.players[KILLER].target.entities[dealerPed] or {}), 3, 'dealer has three sell options')

-- ---------------------------------------------------------------------------
group('Target visibility')
-- ---------------------------------------------------------------------------
equals(#Mock.PlayerOptions(KILLER, VICTIM), 0, 'no options on a living player')

Mock.Kill(VICTIM)
Mock.Tick(1000)

equals(Mock.State(VICTIM, Config.StateKeys.Dead), true, 'victim replicates his death state')
equals(#Mock.PlayerOptions(KILLER, VICTIM), 3, 'all three options appear on the dead body')

Mock.SetCoords(CIVIL, 101.5, 100.0, 30.0)
equals(#Mock.PlayerOptions(CIVIL, VICTIM), 0, 'a player without a knife sees no option')

Mock.GiveItem(CIVIL, 'WEAPON_MACHETE', 1)
equals(#Mock.PlayerOptions(CIVIL, VICTIM), 3, 'any knife (machete) unlocks the options')
Mock.players[CIVIL].inventory['WEAPON_MACHETE'] = nil
Mock.SetCoords(CIVIL, 300.0, 300.0, 30.0)

equals(#Mock.PlayerOptions(VICTIM, VICTIM), 0, 'a dead player cannot target his own body')

-- ---------------------------------------------------------------------------
group('Cutting a finger')
-- ---------------------------------------------------------------------------
cutPart(KILLER, VICTIM, 'finger')

equals(Mock.ItemCount(KILLER, 'finger'), 1, 'the killer received exactly one finger item')

local progress = Mock.LastProgress(KILLER)
ok(progress ~= nil, 'a progress bar was played')
equals(progress and progress.anim and progress.anim.dict, 'anim@gangops@facility@servers@bodysearch', 'the cutting animation is played')
equals(progress and progress.prop and progress.prop.model, 'prop_knife', 'a knife prop is attached while cutting')
equals(progress and progress.duration, 6000, 'the finger takes 6 seconds')
ok(Mock.players[KILLER].facedBody, 'the killer turns towards the body')
ok(hasNotification(KILLER, 'cut off a finger'), 'the killer is notified')

local taken = Mock.State(VICTIM, Config.StateKeys.Parts)
equals(taken and taken.finger, true, 'the body now replicates that the finger is gone')

-- ---------------------------------------------------------------------------
group('One finger, one ear, one tongue per body')
-- ---------------------------------------------------------------------------
local remaining = Mock.PlayerOptions(KILLER, VICTIM)
equals(#remaining, 2, 'the finger option disappeared for everybody')
ok(Mock.HasOption(remaining, 'ear') ~= nil, 'the ear is still available')
ok(Mock.HasOption(remaining, 'tongue') ~= nil, 'the tongue is still available')
equals(#Mock.PlayerOptions(CIVIL, VICTIM), 0, 'other players see the same (no knife, no options)')

Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:request', VICTIM, 'ear')
Mock.Tick(100)
local spam = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(spam and spam.args[1], Config.Text.Cooldown, 'a cut right after another one hits the cooldown')

Mock.Tick(3500) -- harvest cooldown is over
Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:request', VICTIM, 'finger')
Mock.Tick(100)

local denied = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
ok(denied ~= nil, 'a second finger request is denied by the server')
equals(denied and denied.args[1], Config.Text.AlreadyTaken, 'the reason is "already taken"')
equals(Mock.ItemCount(KILLER, 'finger'), 1, 'no second finger was given')

-- ---------------------------------------------------------------------------
group('Police alert')
-- ---------------------------------------------------------------------------
local alertAt = (Mock.Notifications(COP, 'Assassination In Progress')[1] or {}).at
ok(hasNotification(COP, 'Assassination In Progress'), 'police received "Assassination In Progress"')
ok(not hasNotification(CIVIL, 'Assassination In Progress'), 'civilians do not receive the police alert')
ok(not hasNotification(KILLER, 'Assassination In Progress'), 'the killer does not receive the police alert')

local copBlips = Mock.BlipsOfType(COP, 'coord', true)
equals(#copBlips, 1, 'police got exactly one alert blip')
local alertBlip = copBlips[1]
equals(alertBlip and alertBlip.colour, 1, 'the alert blip is red (colour 1)')
equals(alertBlip and alertBlip.flashes, true, 'the alert blip flashes')
equals(alertBlip and alertBlip.label, 'Assassination In Progress', 'the blip is labelled "Assassination In Progress"')
ok(alertBlip and math.abs(alertBlip.coords.x - 101.0) < 0.01, 'the blip sits on the body')
equals(#Mock.BlipsOfType(CIVIL, 'coord', true), 0, 'civilians have no alert blip')
ok(#(Mock.players[COP].sounds or {}) > 0, 'a dispatch sound was played for the police')

-- ---------------------------------------------------------------------------
group('Open fire zone (20 seconds later)')
-- ---------------------------------------------------------------------------
equals(#Mock.BlipsOfType(CIVIL, 'radius', true), 0, 'no zone before the delay')

Mock.TickUntil(alertAt + 19000)
ok(not hasNotification(CIVIL, 'OPEN FIRE ZONE'), 'still nothing 19 seconds after the police alert')

Mock.TickUntil(alertAt + 20500)
ok(hasNotification(CIVIL, 'OPEN FIRE ZONE'), 'every player is warned ~20s after the police alert')
ok(hasNotification(CIVIL, 'Police Announcement'), 'the warning is titled "Police Announcement"')
ok(hasNotification(COP, 'OPEN FIRE ZONE'), 'the police also see the public announcement')
ok(not hasNotification(KILLER, 'OPEN FIRE ZONE'), 'the killer is not warned about his own scene')

local zoneBlips = Mock.BlipsOfType(CIVIL, 'radius', true)
equals(#zoneBlips, 1, 'a red circle appears on the map')
local zone = zoneBlips[1]
equals(zone and zone.colour, 1, 'the circle is red')
equals(zone and zone.radius, 120.0, 'the circle uses the configured radius')
equals(#Mock.BlipsOfType(KILLER, 'radius', true), 1, 'the killer sees the circle as well (only the text is skipped)')

Mock.Tick(3000)
ok(zone.alphaChanges > 2, 'the circle is flashing (alpha keeps toggling)')

-- ---------------------------------------------------------------------------
group('Blip lifetime')
-- ---------------------------------------------------------------------------
ok(alertBlip.alive, 'the police blip is still alive ~24s after the cut')

Mock.TickUntil(alertAt + 85000)
ok(alertBlip.alive, 'the police blip is still alive after 85 seconds')

Mock.TickUntil(alertAt + 92000)
ok(not alertBlip.alive, 'the police blip is gone after 90 seconds')
ok((alertBlip.removedAt - alertBlip.createdAt) >= 90000, 'the police blip lasted at least 90s')
ok((alertBlip.removedAt - alertBlip.createdAt) < 91000, 'the police blip did not overstay')
ok(zone.alive, 'the open fire zone is still up (its own 90s)')

Mock.TickUntil(alertAt + 112000)
ok(not zone.alive, 'the open fire zone disappears after 90 seconds')
ok((zone.removedAt - zone.createdAt) >= 90000, 'the circle lasted the configured 90 seconds')

-- ---------------------------------------------------------------------------
group('Ear and tongue on the same body')
-- ---------------------------------------------------------------------------
cutPart(KILLER, VICTIM, 'ear')
equals(Mock.ItemCount(KILLER, 'ear'), 1, 'the killer received one ear')

Mock.Tick(3500) -- harvest cooldown
cutPart(KILLER, VICTIM, 'tongue')
equals(Mock.ItemCount(KILLER, 'tongue'), 1, 'the killer received one tongue')

equals(#Mock.PlayerOptions(KILLER, VICTIM), 0, 'the body is completely harvested, no options left')

local takenAll = Mock.State(VICTIM, Config.StateKeys.Parts)
ok(takenAll and takenAll.finger and takenAll.ear and takenAll.tongue, 'all three parts are marked as taken')
equals(#Mock.BlipsOfType(COP, 'coord', true), 2, 'each cut fires its own police alert')

-- ---------------------------------------------------------------------------
group('Respawn resets the body')
-- ---------------------------------------------------------------------------
Mock.Revive(VICTIM)
Mock.Tick(1000)
equals(Mock.State(VICTIM, Config.StateKeys.Dead), false, 'the victim reports being alive again')
equals(Mock.State(VICTIM, Config.StateKeys.Parts), nil, 'the harvest record is cleared on respawn')
equals(#Mock.PlayerOptions(KILLER, VICTIM), 0, 'a living player cannot be cut')

Mock.Kill(VICTIM)
Mock.Tick(1000)
equals(#Mock.PlayerOptions(KILLER, VICTIM), 3, 'after dying again all three parts are available')

-- ---------------------------------------------------------------------------
group('Anti cheat: instant finish')
-- ---------------------------------------------------------------------------
Mock.Tick(3500)
Mock.SetProgress(KILLER, { instant = true })
Mock.ClearClientEvents(KILLER)
cutPart(KILLER, VICTIM, 'finger')

equals(Mock.ItemCount(KILLER, 'finger'), 1, 'an instantly finished cut gives no item')
ok(Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied') ~= nil, 'the server rejects the packet')
equals(#Mock.PlayerOptions(KILLER, VICTIM), 3, 'the part is released again after the rejection')

-- ---------------------------------------------------------------------------
group('Anti cheat: cancelled animation')
-- ---------------------------------------------------------------------------
Mock.SetProgress(KILLER, { cancel = true })
cutPart(KILLER, VICTIM, 'finger')

equals(Mock.ItemCount(KILLER, 'finger'), 1, 'a cancelled cut gives no item')
ok(hasNotification(KILLER, 'stopped cutting'), 'the player is told that he stopped')
equals(#Mock.PlayerOptions(KILLER, VICTIM), 3, 'the finger can still be taken by somebody else')

Mock.SetProgress(KILLER, nil)

-- ---------------------------------------------------------------------------
group('Anti cheat: running away mid cut')
-- ---------------------------------------------------------------------------
local finger = partConfig('finger')
Mock.Select(KILLER, Mock.PlayerOptions(KILLER, VICTIM), 'finger', Mock.players[VICTIM].ped)
Mock.Tick(1000)
Mock.SetCoords(KILLER, 400.0, 400.0, 30.0)  -- teleport / sprint away
Mock.ClearClientEvents(KILLER)
Mock.Tick(finger.duration + 1500)

equals(Mock.ItemCount(KILLER, 'finger'), 1, 'no item when the cut is finished far away')
local farDenied = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(farDenied and farDenied.args[1], Config.Text.TooFar, 'the server answers "too far away"')

Mock.SetCoords(KILLER, 100.0, 100.0, 30.0)

-- ---------------------------------------------------------------------------
group('Anti cheat: killed while cutting')
-- ---------------------------------------------------------------------------
Mock.Tick(4000)
Mock.Select(KILLER, Mock.PlayerOptions(KILLER, VICTIM), 'finger', Mock.players[VICTIM].ped)
Mock.Tick(1000)
Mock.Kill(KILLER)                 -- the killer gets shot mid cut
Mock.ClearClientEvents(KILLER)
Mock.Tick(finger.duration + 1500)

equals(Mock.ItemCount(KILLER, 'finger'), 1, 'a player killed during the cut gets no item')
local diedDenied = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(diedDenied and diedDenied.args[1], Config.Text.DeadHarvester, 'the server answers that he is down')

Mock.Revive(KILLER)
Mock.Tick(1000)
equals(#Mock.PlayerOptions(KILLER, VICTIM), 3, 'the part is free again after he was revived')

-- ---------------------------------------------------------------------------
group('Anti cheat: spoofed state / missing knife / dead harvester')
-- ---------------------------------------------------------------------------
Mock.Revive(VICTIM)
Mock.Tick(1000)
Mock.players[VICTIM].state.values[Config.StateKeys.Dead] = true   -- modded client lies
Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:request', VICTIM, 'finger')
Mock.Tick(100)

local spoof = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(spoof and spoof.args[1], Config.Text.NotDead, 'a healthy player cannot be harvested even if his state bag lies')

Mock.players[VICTIM].state.values[Config.StateKeys.Dead] = false
Mock.Kill(VICTIM)
Mock.Tick(1000)

local knives = Mock.players[KILLER].inventory['WEAPON_KNIFE']
Mock.players[KILLER].inventory['WEAPON_KNIFE'] = nil
equals(#Mock.PlayerOptions(KILLER, VICTIM), 0, 'without a knife the options disappear')

Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:request', VICTIM, 'finger')
Mock.Tick(100)
local noKnife = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(noKnife and noKnife.args[1], Config.Text.NoKnife, 'the server also refuses a knifeless request')
Mock.players[KILLER].inventory['WEAPON_KNIFE'] = knives

Mock.ClearClientEvents(VICTIM)
Mock.EmitFromClient(VICTIM, 'codex_bodyharvest:request', VICTIM, 'finger')
Mock.Tick(100)
ok(Mock.LastClientEvent(VICTIM, 'codex_bodyharvest:denied') ~= nil, 'a corpse cannot harvest itself')
equals(Mock.ItemCount(VICTIM, 'finger'), 0, 'and receives nothing')

Mock.ClearClientEvents(CIVIL)
Mock.EmitFromClient(CIVIL, 'codex_bodyharvest:request', VICTIM, 'finger')
Mock.Tick(100)
local farCiv = Mock.LastClientEvent(CIVIL, 'codex_bodyharvest:denied')
equals(farCiv and farCiv.args[1], Config.Text.TooFar, 'a player 200m away cannot cut the body')

Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:request', VICTIM, 'kidney')
Mock.Tick(100)
local badPart = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(badPart and badPart.args[1], Config.Text.InvalidTarget, 'an unknown body part is refused')

-- ---------------------------------------------------------------------------
group('Anti cheat: two players, same finger')
-- ---------------------------------------------------------------------------
Mock.Tick(4000)
Mock.SetCoords(CIVIL, 101.5, 100.0, 30.0)
Mock.GiveItem(CIVIL, 'WEAPON_KNIFE', 1)

Mock.Select(KILLER, Mock.PlayerOptions(KILLER, VICTIM), 'finger', Mock.players[VICTIM].ped)
Mock.Tick(500)
Mock.ClearClientEvents(CIVIL)
Mock.EmitFromClient(CIVIL, 'codex_bodyharvest:request', VICTIM, 'finger')
Mock.Tick(100)

local raced = Mock.LastClientEvent(CIVIL, 'codex_bodyharvest:denied')
equals(raced and raced.args[1], Config.Text.InProgress, 'the second player is told the part is being cut')

Mock.Tick(finger.duration + 1500)
equals(Mock.ItemCount(KILLER, 'finger'), 2, 'the first player got the finger')
equals(Mock.ItemCount(CIVIL, 'finger'), 0, 'the second player got nothing')

Mock.SetCoords(CIVIL, 300.0, 300.0, 30.0)
Mock.players[CIVIL].inventory['WEAPON_KNIFE'] = nil

-- ---------------------------------------------------------------------------
group('Selling to the hidden dealer')
-- ---------------------------------------------------------------------------
local dealer = Config.Dealer.Coords
Mock.SetCoords(KILLER, dealer.x, dealer.y, dealer.z)
Mock.players[KILLER].inventory = { WEAPON_KNIFE = 1, finger = 2 }
Mock.Tick(1500)

ok(#Mock.players[KILLER].nuiMessages > 0 or hasNotification(KILLER, Config.Dealer.Dialogue.Text), 'the dealer greets the player with dialogue')
equals(Mock.players[KILLER].nuiMessages[1] and Mock.players[KILLER].nuiMessages[1].action, 'playSound', 'an audio trigger is sent to the NUI audio player')

Mock.Tick(4500)

local dealerOptions = Mock.EntityOptions(KILLER, Mock.DealerPed(KILLER))
equals(#dealerOptions, 0, 'with 2 fingers the dealer shows nothing (minimum is 3)')

Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:sell', 1)
Mock.Tick(100)
local tooFew = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(tooFew and tooFew.args[1], Config.Text.SellNotEnough:format(3, 'fingers'), 'the server refuses a sale below the minimum')
equals(Mock.ItemCount(KILLER, 'finger'), 2, 'the fingers stay in the inventory')

Mock.GiveItem(KILLER, 'finger', 2)   -- 4 fingers
Mock.Tick(600)                       -- a refused sale only costs the 0.5s spam lock
dealerOptions = Mock.EntityOptions(KILLER, Mock.DealerPed(KILLER))
equals(#dealerOptions, 1, 'with 4 fingers the "Sell fingers" option shows up')
equals(dealerOptions[1].label, 'Sell fingers ($30,000 each, min 3)', 'the price is written on the option')

Mock.Select(KILLER, dealerOptions, 'sell_finger', Mock.DealerPed(KILLER))
Mock.Tick(100)
equals(Mock.Money(KILLER, Config.Dealer.Account), 120000, '4 fingers x $30,000 = $120,000 (' .. Config.Dealer.Account .. ')')
equals(Mock.ItemCount(KILLER, 'finger'), 0, 'the fingers are removed')
ok(hasNotification(KILLER, 'Sold 4x fingers for $120,000'), 'the sale is confirmed with a formatted amount')

Mock.GiveItem(KILLER, 'ear', 3)
Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:sell', 2)
Mock.Tick(100)
local cooldown = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(cooldown and cooldown.args[1], Config.Text.SellCooldown, 'a second sale inside the cooldown is blocked')
equals(Mock.ItemCount(KILLER, 'ear'), 3, 'nothing was taken during the cooldown')

Mock.Tick(6000)
Mock.Select(KILLER, Mock.EntityOptions(KILLER, Mock.DealerPed(KILLER)), 'sell_ear', Mock.DealerPed(KILLER))
Mock.Tick(100)
equals(Mock.Money(KILLER, Config.Dealer.Account), 240000, '3 ears x $40,000 = $120,000 more')

Mock.Tick(6000)
Mock.GiveItem(KILLER, 'tongue', 3)
Mock.Select(KILLER, Mock.EntityOptions(KILLER, Mock.DealerPed(KILLER)), 'sell_tongue', Mock.DealerPed(KILLER))
Mock.Tick(100)
equals(Mock.Money(KILLER, Config.Dealer.Account), 345000, '3 tongues x $35,000 = $105,000 more')
equals(Mock.ItemCount(KILLER, 'tongue'), 0, 'the tongues are gone')

Mock.Tick(6000)
Mock.SetCoords(KILLER, 100.0, 100.0, 30.0)
Mock.GiveItem(KILLER, 'finger', 3)
Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:sell', 1)
Mock.Tick(100)
local farSale = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(farSale and farSale.args[1], Config.Text.TooFar, 'selling from the other side of the map is refused')
equals(Mock.ItemCount(KILLER, 'finger'), 3, 'the items are untouched')
equals(Mock.Money(KILLER, Config.Dealer.Account), 345000, 'no money was paid')

Mock.Tick(6000)
Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:sell', 99)
Mock.Tick(100)
equals(Mock.Money(KILLER, Config.Dealer.Account), 345000, 'an invalid deal index pays nothing')

-- ---------------------------------------------------------------------------
group('Inventory full')
-- ---------------------------------------------------------------------------
Mock.SetCoords(KILLER, 101.0, 100.0, 30.0)
Mock.Tick(4000)
Mock.players[KILLER].inventoryFull = true
Mock.ClearClientEvents(KILLER)
cutPart(KILLER, VICTIM, 'ear')
local fullDenied = Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied')
equals(fullDenied and fullDenied.args[1], Config.Text.NoSpace, 'a full inventory is handled instead of losing the item')
equals(Mock.ItemCount(KILLER, 'ear'), 0, 'no ear was created out of thin air')
Mock.players[KILLER].inventoryFull = false
equals(#Mock.PlayerOptions(KILLER, VICTIM), 2, 'the ear is still on the body')

-- ---------------------------------------------------------------------------
group('Disconnect / resource stop clean up')
-- ---------------------------------------------------------------------------
Mock.Select(KILLER, Mock.PlayerOptions(KILLER, VICTIM), 'ear', Mock.players[VICTIM].ped)
Mock.Tick(1000)
Mock.DropPlayer(KILLER)
Mock.Tick(100)
ok(true, 'a disconnect during a cut does not crash the server')

Mock.Tick(70000) -- pending clean up thread
Mock.players[KILLER].online = true
Mock.Tick(100)
equals(#Mock.PlayerOptions(KILLER, VICTIM), 2, 'the unfinished part is released after the timeout')

Mock.StopResource()
Mock.Tick(100)
equals(#Mock.players[COP].target.globalPlayer, 0, 'ox_target options are removed on resource stop')
equals(Mock.DealerPed(COP) and Mock.entities[Mock.DealerPed(COP)], nil, 'the dealer ped is deleted on resource stop')

-- ---------------------------------------------------------------------------
-- SUMMARY
-- ---------------------------------------------------------------------------
print(('\n\27[1m%s passed, %s failed\27[0m'):format(passed, failed))

if failed > 0 then
    print('\n\27[31mFailures:\27[0m')

    for _, failure in ipairs(failures) do
        print('  - ' .. failure)
    end
end

TEST_FAILURES = failed

if not LUPA_HOST then
    os.exit(failed > 0 and 1 or 0)
end
