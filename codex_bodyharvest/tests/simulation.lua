--[[
    codex_bodyharvest - readable end to end simulation

        lua tests/simulation.lua
        python3 tests/run_lua_tests.py simulation

    Boots the real client and server scripts with four players and plays a
    complete scenario, printing what every single player sees and what the
    server decides. Use it to verify the flow without starting FiveM.
]]

package.path = './tests/?.lua;./?.lua;' .. package.path

local Mock = require('mock_fivem')

local KILLER, VICTIM, COP, CIVIL = 1, 2, 3, 4
local NAMES = {
    [KILLER] = 'Marco  ',
    [VICTIM] = 'Victim ',
    [COP]    = 'Officer',
    [CIVIL]  = 'Civilian'
}

local problems = 0

local function stamp()
    local ms = Mock.Clock()
    return ('%02d:%05.2f'):format(math.floor(ms / 60000), (ms % 60000) / 1000)
end

local function line(actor, message)
    print(('[%s] %-9s %s'):format(stamp(), actor, message))
end

local function header(title)
    print('')
    print(('\27[1;36m%s\27[0m'):format(title))
    print(('-'):rep(78))
end

local function check(condition, message)
    if condition then
        print(('           \27[32m  OK\27[0m      %s'):format(message))
    else
        problems = problems + 1
        print(('           \27[31mERROR\27[0m     %s'):format(message))
    end
end

-- ---------------------------------------------------------------------------
print('')
print('\27[1m================================================================\27[0m')
print('\27[1m  codex_bodyharvest - full simulation (ESX + ox_target + ox_inventory)\27[0m')
print('\27[1m================================================================\27[0m')

Mock.AddPlayer({ id = KILLER, name = 'Marco Vitelli', x = 100.0, y = 100.0, z = 30.0, items = { WEAPON_KNIFE = 1, finger = 2, ear = 2, tongue = 2 } })
Mock.AddPlayer({ id = VICTIM, name = 'Leon Rusko',    x = 101.0, y = 100.0, z = 30.0 })
Mock.AddPlayer({ id = COP,    name = 'Officer Kim',   x = 700.0, y = 640.0, z = 30.0, job = 'police' })
Mock.AddPlayer({ id = CIVIL,  name = 'Random Civ',    x = 260.0, y = 240.0, z = 30.0 })

local Config = Mock.LoadConfig('config.lua')
Mock.LoadServer('server/main.lua')

for _, id in ipairs({ KILLER, VICTIM, COP, CIVIL }) do
    Mock.LoadClient(id, 'client/main.lua')
end

Mock.Tick(2000)

header('1. Server start')
line('SERVER', 'codex_bodyharvest started, 4 players online')
line('SERVER', ('hidden dealer spawned at %.2f %.2f %.2f (%s)'):format(Config.Dealer.Coords.x, Config.Dealer.Coords.y, Config.Dealer.Coords.z, Config.Dealer.Model))
line('Marco', 'carries WEAPON_KNIFE + 2 fingers, 2 ears, 2 tongues from earlier jobs')
line('Officer', 'job = police, 850m away from the scene')
check(#Mock.players[KILLER].target.globalPlayer == 3, 'three player target options registered (finger / ear / tongue)')
check(Mock.DealerPed(KILLER) ~= nil, 'hidden dealer ped exists with 3 sell options')

-- ---------------------------------------------------------------------------
header('2. Marco kills Leon and looks at the body')
Mock.Kill(VICTIM)
Mock.Tick(1000)
line('WORLD', 'Leon Rusko is dead (health 0), his client replicates the death state')

local options = Mock.PlayerOptions(KILLER, VICTIM)
line('Marco', 'ox_target on the corpse shows: ' .. table.concat(Mock.OptionLabels(options), ' | '))
check(#options == 3, 'all three cut options are offered to the knife carrier')

Mock.SetCoords(CIVIL, 102.0, 100.0, 30.0)
local civOptions = Mock.PlayerOptions(CIVIL, VICTIM)
line('Civilian', ('walks past the body without a knife -> %d options'):format(#civOptions))
check(#civOptions == 0, 'no knife = no options at all')
Mock.SetCoords(CIVIL, 260.0, 240.0, 30.0)

-- ---------------------------------------------------------------------------
header('3. Marco cuts off a finger')
Mock.Select(KILLER, options, 'finger', Mock.players[VICTIM].ped)
Mock.Tick(400)
local progress = Mock.LastProgress(KILLER)
line('Marco', ('kneels down, animation "%s / %s", knife prop attached'):format(progress.anim.dict, progress.anim.clip))
line('Marco', ('progress bar "%s" running for %.1fs'):format(progress.label, progress.duration / 1000))

Mock.Tick(6200)
line('SERVER', 'distance, death state, knife and duration re-checked -> item granted')
line('Marco', 'notification: ' .. Mock.LastNotification(KILLER).description)
check(Mock.ItemCount(KILLER, 'finger') == 3, 'exactly one finger item was added (2 + 1)')

local taken = Mock.State(VICTIM, Config.StateKeys.Parts)
check(taken and taken.finger == true, 'the body is flagged: the finger is gone for everybody')

-- ---------------------------------------------------------------------------
header('4. Police alert (instant)')
local alert = Mock.Notifications(COP, 'Assassination')[1]
local alertAt = alert and alert.at or Mock.Clock()
line('Officer', ('DISPATCH -> "%s"'):format(alert.title))
line('Officer', ('           "%s"'):format(alert.description))

local blip = Mock.BlipsOfType(COP, 'coord', true)[1]
line('Officer', ('map blip: colour %d (red), flashing %s, %ds, at %.1f / %.1f')
    :format(blip.colour, tostring(blip.flashes), Config.Alert.Blip.Duration, blip.coords.x, blip.coords.y))
check(blip.flashes and blip.colour == 1, 'flashing red blip on the police map')
check(#Mock.Notifications(CIVIL, 'Assassination') == 0, 'civilians receive nothing yet')
check(#Mock.Notifications(KILLER, 'Assassination') == 0, 'the killer is not alerted about himself')

-- ---------------------------------------------------------------------------
header('5. Twenty seconds later: OPEN FIRE ZONE')
Mock.TickUntil(alertAt + 19000)
line('WORLD', '19s after the alert - still quiet for the public')
check(#Mock.Notifications(CIVIL, 'OPEN FIRE') == 0, 'the public warning has not fired yet')

Mock.TickUntil(alertAt + 20500)
local warning = Mock.Notifications(CIVIL, 'OPEN FIRE')[1]
line('Civilian', ('ANNOUNCEMENT -> "%s"'):format(warning.title))
line('Civilian', ('               "%s"'):format(warning.description))

local circle = Mock.BlipsOfType(CIVIL, 'radius', true)[1]
line('Civilian', ('map circle: radius %.0fm, colour %d (red), blinking every %dms, %ds')
    :format(circle.radius, circle.colour, Config.OpenFireZone.FlashInterval, Config.OpenFireZone.Duration))
check(warning ~= nil and circle ~= nil, 'every player got the announcement and the red circle')
check(#Mock.Notifications(KILLER, 'OPEN FIRE') == 0, 'the killer is excluded from the public warning')

Mock.Tick(3000)
check(circle.alphaChanges > 2, 'the circle really blinks (alpha keeps toggling)')

-- ---------------------------------------------------------------------------
header('6. Marco takes the ear and the tongue too')
Mock.Select(KILLER, Mock.PlayerOptions(KILLER, VICTIM), 'ear', Mock.players[VICTIM].ped)
Mock.Tick(7500)
line('Marco', 'notification: ' .. Mock.LastNotification(KILLER).description)

Mock.Tick(3500)
Mock.Select(KILLER, Mock.PlayerOptions(KILLER, VICTIM), 'tongue', Mock.players[VICTIM].ped)
Mock.Tick(9500)
line('Marco', 'notification: ' .. Mock.LastNotification(KILLER).description)
line('Marco', ('bag: %d fingers, %d ears, %d tongues')
    :format(Mock.ItemCount(KILLER, 'finger'), Mock.ItemCount(KILLER, 'ear'), Mock.ItemCount(KILLER, 'tongue')))

local left = Mock.PlayerOptions(KILLER, VICTIM)
line('Marco', ('aims at the corpse again -> %d options left'):format(#left))
check(#left == 0, 'one finger, one ear, one tongue per body - the corpse is empty now')
check(#Mock.BlipsOfType(COP, 'coord') == 3, 'every cut produced its own police alert (3 total)')

Mock.SetCoords(CIVIL, 102.0, 100.0, 30.0)
Mock.GiveItem(CIVIL, 'WEAPON_KNIFE', 1)
Mock.ClearClientEvents(CIVIL)
Mock.EmitFromClient(CIVIL, 'codex_bodyharvest:request', VICTIM, 'finger')
Mock.Tick(100)
local refusal = Mock.LastClientEvent(CIVIL, 'codex_bodyharvest:denied')
line('Civilian', ('tries the same body with his own knife -> "%s"'):format(refusal.args[1]))
check(refusal.args[1] == Config.Text.AlreadyTaken, 'a second player cannot take the same parts again')
Mock.SetCoords(CIVIL, 260.0, 240.0, 30.0)
Mock.players[CIVIL].inventory['WEAPON_KNIFE'] = nil

-- ---------------------------------------------------------------------------
header('7. The alerts expire')
Mock.TickUntil(alertAt + 92000)
check(not blip.alive, ('the police blip disappeared after %.0fs'):format((blip.removedAt - blip.createdAt) / 1000))
Mock.TickUntil(alertAt + 113000)
check(not circle.alive, ('the open fire zone disappeared after %.0fs'):format((circle.removedAt - circle.createdAt) / 1000))
line('WORLD', 'map is clean again')

-- ---------------------------------------------------------------------------
header('8. Selling at the hidden dealer')
local dealer = Config.Dealer.Coords
Mock.SetCoords(KILLER, dealer.x, dealer.y, dealer.z)
Mock.Tick(1000)
line('Marco', ('drives to the mine shaft at %.0f / %.0f and talks to the collector'):format(dealer.x, dealer.y))

local sellOptions = Mock.EntityOptions(KILLER, Mock.DealerPed(KILLER))

for _, option in ipairs(sellOptions) do
    line('Dealer', 'offers: ' .. option.label)
end

check(#sellOptions == 3, 'all three deals are visible (3 fingers, 3 ears, 3 tongues in the bag)')

Mock.Select(KILLER, sellOptions, 'sell_finger', Mock.DealerPed(KILLER))
Mock.Tick(100)
line('Marco', 'notification: ' .. Mock.LastNotification(KILLER).description)

Mock.Tick(5500)
Mock.Select(KILLER, Mock.EntityOptions(KILLER, Mock.DealerPed(KILLER)), 'sell_ear', Mock.DealerPed(KILLER))
Mock.Tick(100)
line('Marco', 'notification: ' .. Mock.LastNotification(KILLER).description)

Mock.Tick(5500)
Mock.Select(KILLER, Mock.EntityOptions(KILLER, Mock.DealerPed(KILLER)), 'sell_tongue', Mock.DealerPed(KILLER))
Mock.Tick(100)
line('Marco', 'notification: ' .. Mock.LastNotification(KILLER).description)

line('Marco', ('cash: $%s   bag: %d fingers, %d ears, %d tongues')
    :format(Config.FormatMoney(Mock.Money(KILLER, 'money')), Mock.ItemCount(KILLER, 'finger'),
        Mock.ItemCount(KILLER, 'ear'), Mock.ItemCount(KILLER, 'tongue')))

check(Mock.Money(KILLER, 'money') == 3 * 30000 + 3 * 40000 + 3 * 35000, '3x$30,000 + 3x$40,000 + 3x$35,000 = $315,000')
check(Mock.ItemCount(KILLER, 'finger') == 0 and Mock.ItemCount(KILLER, 'ear') == 0 and Mock.ItemCount(KILLER, 'tongue') == 0, 'all parts were taken out of the inventory')

-- ---------------------------------------------------------------------------
header('9. Cheat attempts from a modified client')
Mock.Tick(6000)
Mock.GiveItem(KILLER, 'finger', 2)
Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:sell', 1)
Mock.Tick(100)
line('Marco', ('sells 2 fingers (minimum 3) -> "%s"'):format(Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied').args[1]))
check(Mock.ItemCount(KILLER, 'finger') == 2 and Mock.Money(KILLER, 'money') == 315000, 'below the minimum nothing is sold')

Mock.SetCoords(KILLER, 100.0, 100.0, 30.0)
Mock.GiveItem(KILLER, 'finger', 1)
Mock.Tick(6000)
Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:sell', 1)
Mock.Tick(100)
line('Marco', ('sells 3 fingers from 2km away -> "%s"'):format(Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied').args[1]))
check(Mock.Money(KILLER, 'money') == 315000, 'remote selling is impossible')

Mock.Revive(VICTIM)
Mock.Tick(1000)
Mock.players[VICTIM].state.values[Config.StateKeys.Dead] = true
Mock.ClearClientEvents(KILLER)
Mock.EmitFromClient(KILLER, 'codex_bodyharvest:request', VICTIM, 'finger')
Mock.Tick(100)
line('Marco', ('cuts a living player whose client claims to be dead -> "%s"'):format(Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied').args[1]))
check(Mock.LastClientEvent(KILLER, 'codex_bodyharvest:denied').args[1] == Config.Text.NotDead, 'the server checks the real ped health, not the client')

Mock.players[VICTIM].state.values[Config.StateKeys.Dead] = false
Mock.Kill(VICTIM)
Mock.Tick(1000)
line('WORLD', 'Leon dies a second time - the body resets')
check(#Mock.PlayerOptions(KILLER, VICTIM) == 3, 'a new death = a new finger, ear and tongue')

Mock.SetProgress(KILLER, { instant = true })
Mock.ClearClientEvents(KILLER)
Mock.Select(KILLER, Mock.PlayerOptions(KILLER, VICTIM), 'finger', Mock.players[VICTIM].ped)
Mock.Tick(1000)
line('Marco', 'client skips the animation and reports "finished" instantly')
check(Mock.ItemCount(KILLER, 'finger') == 3, 'no item: the server measures the real cutting time')
Mock.SetProgress(KILLER, nil)

-- ---------------------------------------------------------------------------
print('')
print(('-'):rep(78))

if problems == 0 then
    print('\27[1;32m  SIMULATION FINISHED - everything behaves as designed.\27[0m')
else
    print(('\27[1;31m  SIMULATION FINISHED - %d problem(s) found.\27[0m'):format(problems))
end

print(('-'):rep(78))
print('')

TEST_FAILURES = problems

if not LUPA_HOST then
    os.exit(problems > 0 and 1 or 0)
end
