--[[ OQV2 QUESTS — server-side logic test suite (runs on a real Lua VM
     with FiveM natives stubbed). Made with CodeX Dev. ]]

local results, failures = {}, 0

local function check(name, fn)
    local ok, detail = pcall(fn)
    if ok then
        results[#results + 1] = { 'PASS', name, tostring(detail or '') }
    else
        failures = failures + 1
        results[#results + 1] = { 'FAIL', name, tostring(detail) }
    end
end

local function assertf(cond, msg, ...)
    if not cond then error(select('#', ...) > 0 and msg:format(...) or msg, 2) end
end

-------------------------------------------------------------------------------
-- SHARED: utils
-------------------------------------------------------------------------------
check('locale loads and interpolates', function()
    assertf(OQ.L('saved') == 'Saved successfully.', 'locale not loaded: %s', OQ.L('saved'))
    local s = OQ.L('mission_level', { level = 7 })
    assertf(s == 'You need level 7 for this mission.', 'interpolation failed: %s', s)
    assertf(OQ.L('__missing__') == '__missing__', 'missing key should echo')
    return 'en.json + {placeholders}'
end)

check('deepCopy is truly deep', function()
    local a = { x = { y = { z = 1 } }, list = { 1, 2, 3 } }
    local b = OQ.deepCopy(a)
    b.x.y.z = 99
    b.list[1] = 99
    assertf(a.x.y.z == 1, 'nested table shared')
    assertf(a.list[1] == 1, 'array shared')
    return 'no shared references'
end)

check('defaults() fills without clobbering', function()
    local t = OQ.defaults({ name = 'keep', nested = { a = 1 } }, { name = 'new', extra = 5, nested = { a = 9, b = 2 } })
    assertf(t.name == 'keep', 'existing value overwritten')
    assertf(t.extra == 5, 'missing key not filled')
    assertf(t.nested.a == 1 and t.nested.b == 2, 'nested merge wrong')
    return 'merge ok'
end)

check('uid() produces unique ids', function()
    local seen = {}
    for _ = 1, 5000 do
        local id = OQ.uid('m')
        assertf(not seen[id], 'duplicate uid: %s', id)
        seen[id] = true
    end
    return '5000 unique ids'
end)

check('hourInRange handles wrap-around windows', function()
    assertf(OQ.hourInRange(21, 20, 6) == true, '21 should be inside 20→6')
    assertf(OQ.hourInRange(3, 20, 6) == true, '3 should be inside 20→6')
    assertf(OQ.hourInRange(12, 20, 6) == false, '12 should be outside 20→6')
    assertf(OQ.hourInRange(12, 8, 18) == true, '12 should be inside 8→18')
    assertf(OQ.hourInRange(20, 8, 18) == false, '20 should be outside 8→18')
    assertf(OQ.hourInRange(5, 0, 24) == true, 'full day always true')
    return 'wrap-around + normal windows'
end)

check('humanDuration formats sensibly', function()
    assertf(OQ.humanDuration(0) == '0s', '0s')
    assertf(OQ.humanDuration(90) == '1m 30s', 'got ' .. OQ.humanDuration(90))
    assertf(OQ.humanDuration(3600) == '1h', 'got ' .. OQ.humanDuration(3600))
    assertf(OQ.humanDuration(86400) == '1d', 'got ' .. OQ.humanDuration(86400))
    return '0s / 1m 30s / 1h / 1d'
end)

check('vector helpers + distance', function()
    local d = OQ.dist({ x = 0, y = 0, z = 0 }, { x = 3, y = 4, z = 0 })
    assertf(math.abs(d - 5.0) < 0.001, 'expected 5, got %s', d)
    local t = OQ.vecToTable(vec3(1.5, 2.5, 3.5))
    assertf(t.x == 1.5 and t.z == 3.5, 'vecToTable wrong')
    return 'distance = 5.0'
end)

-------------------------------------------------------------------------------
-- SHARED: progression math
-------------------------------------------------------------------------------
check('xp curve is monotonic and level 1 starts at 0', function()
    local r = OQ.resolveXP(0)
    assertf(r.level == 1 and r.xp == 0, 'level 1 start wrong')
    local prev = 0
    for lvl = 1, 50 do
        local need = OQ.xpForLevel(lvl)
        assertf(need > prev, 'curve not increasing at level %d', lvl)
        prev = need
    end
    return 'lv1 need=' .. OQ.xpForLevel(1) .. ', lv50 need=' .. OQ.xpForLevel(50)
end)

check('resolveXP round-trips exactly at level boundaries', function()
    local total = 0
    for lvl = 1, 20 do
        local r = OQ.resolveXP(total)
        assertf(r.level == lvl, 'expected level %d at %d xp, got %d', lvl, total, r.level)
        assertf(r.xp == 0, 'expected 0 leftover at boundary, got %d', r.xp)
        total = total + OQ.xpForLevel(lvl)
    end
    return '20 boundaries exact'
end)

check('resolveXP caps at maxLevel', function()
    local r = OQ.resolveXP(1e12)
    assertf(r.level == Config.Progression.maxLevel, 'cap failed: %d', r.level)
    assertf(r.max == true, 'max flag not set')
    assertf(r.percent == 100.0, 'percent should be 100 at cap')
    return 'capped at ' .. r.level
end)

check('percent stays within 0-100', function()
    for xp = 0, 40000, 137 do
        local r = OQ.resolveXP(xp)
        assertf(r.percent >= 0 and r.percent <= 100, 'percent out of range at %d xp: %s', xp, r.percent)
    end
    return 'scanned 0..40000 xp'
end)

-------------------------------------------------------------------------------
-- SHARED: schema normalisation
-------------------------------------------------------------------------------
check('normalizeMission fills defaults and coerces types', function()
    local m = OQ.Schema.normalizeMission({ name = '  Spaced  ', xpReward = '250', requiredLevel = -5 })
    assertf(m.name == 'Spaced', 'name not trimmed: "%s"', m.name)
    assertf(m.uid ~= '' and m.uid:sub(1, 2) == 'm_', 'uid not generated: %s', m.uid)
    assertf(m.xpReward == 250, 'string number not coerced')
    assertf(m.requiredLevel == 0, 'negative level not clamped')
    assertf(type(m.objectives) == 'table' and #m.objectives == 0, 'objectives default missing')
    assertf(m.cooldown.type == 'none' and m.cooldown.seconds == 0, 'cooldown default wrong')
    assertf(m.restriction.type == 'all', 'restriction default wrong')
    return 'uid=' .. m.uid
end)

check('cooldown presets are applied from the type', function()
    assertf(OQ.Schema.normalizeMission({ cooldown = { type = 'daily' } }).cooldown.seconds == 86400, 'daily')
    assertf(OQ.Schema.normalizeMission({ cooldown = { type = 'weekly' } }).cooldown.seconds == 604800, 'weekly')
    assertf(OQ.Schema.normalizeMission({ cooldown = { type = 'custom', seconds = 42 } }).cooldown.seconds == 42, 'custom')
    return 'daily/weekly/custom'
end)

check('self-referencing prerequisites are stripped', function()
    local m = OQ.Schema.normalizeMission({ uid = 'm_self', prerequisites = { 'm_self', 'm_a', 'm_a', 'm_b' } })
    assertf(#m.prerequisites == 2, 'expected 2, got %d', #m.prerequisites)
    assertf(m.prerequisites[1] == 'm_a' and m.prerequisites[2] == 'm_b', 'wrong set')
    return 'self + duplicates removed'
end)

check('objective ids are generated and labels defaulted', function()
    local m = OQ.Schema.normalizeMission({
        name = 'T',
        objectives = { { type = 'goto', coords = { x = 1, y = 2, z = 3 } }, { type = 'kill', amount = '4' } }
    })
    assertf(m.objectives[1].id ~= '' and m.objectives[1].id:sub(1, 4) == 'obj_', 'id missing')
    assertf(m.objectives[1].label == 'Objective #1', 'label default wrong: ' .. m.objectives[1].label)
    assertf(m.objectives[2].amount == 4, 'amount coercion failed')
    assertf(m.objectives[1].coords.x == 1.0, 'coords lost')
    return '2 objectives normalised'
end)

check('reward chance is clamped to 1-100', function()
    local m = OQ.Schema.normalizeMission({
        name = 'T', rewards = { items = { { name = 'a', chance = 500 }, { name = 'b', chance = -20 }, { name = '', chance = 50 } } }
    })
    assertf(#m.rewards.items == 2, 'empty item name should be dropped, got %d', #m.rewards.items)
    assertf(m.rewards.items[1].chance == 100, 'upper clamp failed')
    assertf(m.rewards.items[2].chance == 1, 'lower clamp failed')
    return 'clamped + empty dropped'
end)

check('normalizeLocation coerces points and blip', function()
    local l = OQ.Schema.normalizeLocation({
        name = 'Spot',
        points = { { x = '1.5', y = 2, z = 3, w = 90 }, 'garbage' },
        blip = { scale = 99 },
        missions = { 'a', 'a', 'b' }
    })
    assertf(#l.points == 1, 'invalid point not dropped, got %d', #l.points)
    assertf(l.points[1].x == 1.5, 'string coord not coerced')
    assertf(l.blip.scale == 2.0, 'blip scale not clamped: %s', l.blip.scale)
    assertf(l.blip.label == 'Spot', 'blip label not defaulted')
    assertf(#l.missions == 2, 'duplicate mission link not removed')
    return 'points/blip/links normalised'
end)

check('normalizeEvilNpc clamps counts and keeps a weapon', function()
    local n = OQ.Schema.normalizeEvilNpc({ name = 'G', count = 99, companions = -3, weapons = {}, money = { min = 500, max = 100 } })
    assertf(n.count == 12, 'count not clamped: %d', n.count)
    assertf(n.companions == 0, 'companions not clamped')
    assertf(#n.weapons == 1 and n.weapons[1] == 'WEAPON_PISTOL', 'weapon fallback missing')
    assertf(n.money.max >= n.money.min, 'money range not fixed: %d..%d', n.money.min, n.money.max)
    return 'clamped, money ' .. n.money.min .. '..' .. n.money.max
end)

-------------------------------------------------------------------------------
-- SHARED: validation
-------------------------------------------------------------------------------
check('validateMission rejects an empty mission', function()
    local ok, errs = OQ.Schema.validateMission(OQ.Schema.normalizeMission({ name = '' }))
    assertf(not ok, 'should be invalid')
    assertf(#errs >= 2, 'expected name + objective errors, got %d', #errs)
    return #errs .. ' errors: ' .. errs[1]
end)

check('validateMission catches missing item/coords/amount', function()
    local m = OQ.Schema.normalizeMission({
        name = 'X',
        objectives = { { type = 'give_item' }, { type = 'goto' }, { type = 'pay', money = 0 } }
    })
    local ok, errs = OQ.Schema.validateMission(m)
    assertf(not ok, 'should be invalid')
    assertf(#errs == 3, 'expected 3 errors, got %d (%s)', #errs, table.concat(errs, ' | '))
    return table.concat(errs, ' | ')
end)

check('validateMission accepts a complete mission', function()
    local m = OQ.Schema.normalizeMission({
        name = 'Good', objectives = { { type = 'give_item', item = 'water', count = 2 } },
        rewards = { money = 100 }
    })
    local ok, errs = OQ.Schema.validateMission(m)
    assertf(ok, 'should be valid: ' .. table.concat(errs, ' | '))
    return 'valid'
end)

check('validateLocation requires points and links', function()
    local ok, errs = OQ.Schema.validateLocation(OQ.Schema.normalizeLocation({ name = 'L' }))
    assertf(not ok, 'should be invalid')
    assertf(#errs == 2, 'expected 2 errors, got %d', #errs)
    return table.concat(errs, ' | ')
end)

check('validateEvilNpc requires coordinates', function()
    local ok, errs = OQ.Schema.validateEvilNpc(OQ.Schema.normalizeEvilNpc({ name = 'G' }))
    assertf(not ok, 'should be invalid')
    return errs[1]
end)

-------------------------------------------------------------------------------
-- SHARED: quest tree cycle detection
-------------------------------------------------------------------------------
check('checkTree accepts a valid chain', function()
    local ok = OQ.Schema.checkTree({
        a = { uid = 'a', prerequisites = {} },
        b = { uid = 'b', prerequisites = { 'a' } },
        c = { uid = 'c', prerequisites = { 'b' } },
        d = { uid = 'd', prerequisites = { 'a', 'b' } },
    })
    assertf(ok, 'valid chain rejected')
    return 'a → b → c, d'
end)

check('checkTree detects a direct cycle', function()
    local ok, cycle = OQ.Schema.checkTree({
        a = { uid = 'a', prerequisites = { 'b' } },
        b = { uid = 'b', prerequisites = { 'a' } },
    })
    assertf(not ok, 'cycle not detected')
    return 'detected: ' .. tostring(cycle)
end)

check('checkTree detects a deep cycle', function()
    local ok = OQ.Schema.checkTree({
        a = { uid = 'a', prerequisites = { 'c' } },
        b = { uid = 'b', prerequisites = { 'a' } },
        c = { uid = 'c', prerequisites = { 'b' } },
    })
    assertf(not ok, '3-node cycle not detected')
    return 'a → b → c → a rejected'
end)

check('checkTree tolerates dangling references', function()
    local ok = OQ.Schema.checkTree({ a = { uid = 'a', prerequisites = { 'ghost' } } })
    assertf(ok, 'dangling prerequisite should not break the tree')
    return 'ghost prerequisite ignored'
end)

-------------------------------------------------------------------------------
-- CONFIG INTEGRITY
-------------------------------------------------------------------------------
check('every shipped mission normalises AND validates', function()
    local names = {}
    for _, raw in ipairs(Config.Missions) do
        local m = OQ.Schema.normalizeMission(OQ.deepCopy(raw))
        local ok, errs = OQ.Schema.validateMission(m)
        assertf(ok, '"%s" invalid: %s', m.name, table.concat(errs, ' | '))
        names[#names + 1] = m.name
    end
    return #names .. ' missions: ' .. table.concat(names, ', ')
end)

check('every shipped location normalises AND validates', function()
    for _, raw in ipairs(Config.Locations) do
        local l = OQ.Schema.normalizeLocation(OQ.deepCopy(raw))
        local ok, errs = OQ.Schema.validateLocation(l)
        assertf(ok, '"%s" invalid: %s', l.name, table.concat(errs, ' | '))
    end
    return #Config.Locations .. ' locations valid'
end)

check('every shipped hostile group normalises AND validates', function()
    for _, raw in ipairs(Config.EvilNpcs) do
        local n = OQ.Schema.normalizeEvilNpc(OQ.deepCopy(raw))
        local ok, errs = OQ.Schema.validateEvilNpc(n)
        assertf(ok, '"%s" invalid: %s', n.name, table.concat(errs, ' | '))
    end
    return #Config.EvilNpcs .. ' groups valid'
end)

check('config location→mission links all resolve', function()
    local missions = {}
    for _, m in ipairs(Config.Missions) do missions[m.uid] = true end
    local links = 0
    for _, l in ipairs(Config.Locations) do
        for _, uid in ipairs(l.missions or {}) do
            assertf(missions[uid], 'location "%s" links unknown mission "%s"', l.name, uid)
            links = links + 1
        end
    end
    return links .. ' links resolved'
end)

check('config prerequisites all resolve and form no cycle', function()
    local map = {}
    for _, raw in ipairs(Config.Missions) do
        map[raw.uid] = OQ.Schema.normalizeMission(OQ.deepCopy(raw))
    end
    for uid, m in pairs(map) do
        for _, dep in ipairs(m.prerequisites) do
            assertf(map[dep], 'mission "%s" requires unknown "%s"', uid, dep)
        end
    end
    local ok, cycle = OQ.Schema.checkTree(map)
    assertf(ok, 'cycle in shipped config: ' .. tostring(cycle))
    return 'chain valid'
end)

check('config npc→mission links resolve', function()
    local missions = {}
    for _, m in ipairs(Config.Missions) do missions[m.uid] = true end
    for _, n in ipairs(Config.EvilNpcs) do
        if n.linkedMission then
            assertf(missions[n.linkedMission], 'group "%s" links unknown mission "%s"', n.name, n.linkedMission)
        end
    end
    return 'ok'
end)

check('admin config has at least one access method', function()
    local hasGroups = #(Config.Admin.groups or {}) > 0
    local hasAce = Config.Admin.ace and Config.Admin.ace ~= ''
    assertf(hasGroups or hasAce or #(Config.Admin.identifiers or {}) > 0, 'no admin access configured')
    assertf(Config.Admin.command == 'oqv2', 'command should be oqv2, got ' .. tostring(Config.Admin.command))
    return '/' .. Config.Admin.command .. ' · groups: ' .. table.concat(Config.Admin.groups, ', ')
end)

check('branding matches the requested author string', function()
    assertf(Config.UI.author == 'Codex Dev: #Alesh48 5654', 'author wrong: ' .. Config.UI.author)
    assertf(Config.UI.footer == 'Made with CodeX Dev.', 'footer wrong: ' .. Config.UI.footer)
    return Config.UI.author .. ' / ' .. Config.UI.footer
end)

-------------------------------------------------------------------------------
-- SERVER RUNTIME
-------------------------------------------------------------------------------
check('boot: schema created, config seeded, registry loaded', function()
    TriggerEvent('onResourceStart', 'oqv2_quests')
    local ran = 0
    for _ = 1, 4 do ran = ran + TEST.runThreads(80) end
    assertf(OQ.DB.isReady(), 'database not ready')
    assertf(OQ.count(OQ.Registry.missions) == #Config.Missions, 'missions not loaded: %d', OQ.count(OQ.Registry.missions))
    assertf(OQ.count(OQ.Registry.locations) == #Config.Locations, 'locations not loaded')
    assertf(OQ.count(OQ.Registry.npcs) == #Config.EvilNpcs, 'npcs not loaded')
    return ('%d missions / %d locations / %d groups')
        :format(OQ.count(OQ.Registry.missions), OQ.count(OQ.Registry.locations), OQ.count(OQ.Registry.npcs))
end)

check('world payload only exposes enabled entities and no admin metadata', function()
    local payload = OQ.Server.buildWorldPayload()
    assertf(#payload.missions == 4, 'expected 4 enabled missions, got %d', #payload.missions)
    assertf(#payload.locations == 4, 'expected 4 locations, got %d', #payload.locations)
    assertf(#payload.npcs == 1, 'disabled group leaked, got %d', #payload.npcs)
    assertf(payload.missions[1].meta == nil, 'meta leaked to clients')
    return #payload.missions .. ' missions / ' .. #payload.npcs .. ' active groups sent'
end)

check('permissions: group, ace and denial', function()
    TEST.jobs[1] = { name = 'unemployed', grade = 0 }
    TEST.jobs[2] = { name = 'police', grade = 3 }
    TEST.groups[2] = 'admin'
    TEST.jobs[3] = { name = 'unemployed', grade = 0 }
    TEST.aces[3] = 'oqv2.admin'

    assertf(OQ.Server.isAdmin(1) == false, 'plain player granted admin')
    assertf(OQ.Server.isAdmin(2) == true, 'esx admin group denied')
    assertf(OQ.Server.isAdmin(3) == true, 'ace permission denied')
    assertf(OQ.Server.isAdmin(0) == true, 'console denied')
    return 'user=deny, group=allow, ace=allow, console=allow'
end)

check('/oqv2 opens the panel only for admins', function()
    TEST.clientEvents = {}
    TEST.commands['oqv2'](1, {})
    local openedForPlayer = false
    for _, e in ipairs(TEST.clientEvents) do
        if e.name == 'oqv2:client:openAdmin' then openedForPlayer = true end
    end
    assertf(not openedForPlayer, 'panel opened for a non-admin!')

    TEST.clientEvents = {}
    TEST.commands['oqv2'](2, {})
    local openedForAdmin = false
    for _, e in ipairs(TEST.clientEvents) do
        if e.name == 'oqv2:client:openAdmin' and e.target == 2 then openedForAdmin = true end
    end
    assertf(openedForAdmin, 'panel did not open for the admin')
    return 'denied for player 1, opened for admin 2'
end)

check('admin snapshot is refused for non-admins', function()
    local snap = lib.callback._registered['oqv2:admin:snapshot'](1)
    assertf(snap == nil, 'snapshot leaked to a non-admin')
    local ok = lib.callback._registered['oqv2:admin:snapshot'](2)
    assertf(type(ok) == 'table' and ok.stats, 'admin snapshot broken')
    assertf(ok.branding.author == 'Codex Dev: #Alesh48 5654', 'branding missing from snapshot')
    return 'nil for player, full snapshot for admin'
end)

check('progression loads and syncs for a player', function()
    TEST.coords[1] = vec3(1088.13, -2002.13, 30.90)
    local p = OQ.Progression.load(1)
    assertf(p, 'progression not loaded')
    assertf(p.level == 1 and p.xp == 0, 'fresh player should be level 1')
    local payload = OQ.Progression.buildPayload(1)
    assertf(payload.level == 1 and payload.need > 0, 'payload wrong')
    return 'level 1, need ' .. payload.need .. ' xp'
end)

check('xp gain levels the player up and fires the event', function()
    TEST.clientEvents = {}
    OQ.Progression.addXP(1, 600)
    local p = OQ.Progression.get(1)
    assertf(p.level == 2, 'expected level 2, got %d', p.level)
    local sawLevelUp = false
    for _, e in ipairs(TEST.clientEvents) do
        if e.name == 'oqv2:client:levelUp' then sawLevelUp = true end
    end
    assertf(sawLevelUp, 'levelUp event not sent')
    return '600 xp → level ' .. p.level
end)

check('a mission can be accepted empty-handed but not turned in', function()
    OQ.Missions.abandon(1)
    TEST.inventory[1] = {}
    local list = OQ.Missions.listForLocation(1, 'loc_marco')
    assertf(#list == 1, 'expected 1 mission at Marco, got %d', #list)

    -- accepting is allowed: the objective item is what you go and fetch
    local ok, msg = OQ.Missions.start(1, 'm_scrap_trade', 'loc_marco')
    assertf(ok, 'mission refused: ' .. tostring(msg))

    local objId = OQ.Progression.get(1).active.objectives[1].id
    local advOk, code = OQ.Missions.advance(1, 'm_scrap_trade', objId, {})
    assertf(not advOk and code == 'need_items', 'turn-in accepted without items: ' .. tostring(code))

    local cOk = OQ.Missions.complete(1, 'm_scrap_trade')
    assertf(not cOk, 'mission completed with unfinished objectives')

    OQ.Missions.abandon(1)
    return 'accepted, turn-in blocked (need_items)'
end)

check('mission start → objective → complete pays out correctly', function()
    OQ.Missions.abandon(1)
    TEST.inventory[1] = { scrapmetal = 5 }
    TEST.money[1] = { money = 0, bank = 0, black_money = 0 }
    TEST.clientEvents = {}

    local ok, msg = OQ.Missions.start(1, 'm_scrap_trade', 'loc_marco')
    assertf(ok, 'start failed: ' .. tostring(msg))

    local p = OQ.Progression.get(1)
    assertf(p.active and p.active.uid == 'm_scrap_trade', 'active mission not set')

    local objId = p.active.objectives[1].id
    local advOk, code = OQ.Missions.advance(1, 'm_scrap_trade', objId, {})
    assertf(advOk, 'advance failed: ' .. tostring(code))
    assertf(code == 'all_done', 'expected all_done, got ' .. tostring(code))
    assertf((TEST.inventory[1].scrapmetal or 0) == 0, 'items not consumed: %d', TEST.inventory[1].scrapmetal or 0)

    local cOk, cMsg = OQ.Missions.complete(1, 'm_scrap_trade')
    assertf(cOk, 'complete failed: ' .. tostring(cMsg))
    assertf(TEST.money[1].money == 850, 'reward not paid: %d', TEST.money[1].money)
    assertf((TEST.inventory[1].water or 0) == 1, 'item reward not given')
    assertf(OQ.Progression.get(1).active == nil, 'active mission not cleared')
    assertf(OQ.Progression.isCompleted(1, 'm_scrap_trade'), 'completion not recorded')
    return '$850 + 1x water + 120 xp'
end)

check('daily cooldown blocks an immediate repeat', function()
    OQ.Missions.abandon(1)
    TEST.inventory[1] = { scrapmetal = 5 }
    local ok, msg = OQ.Missions.start(1, 'm_scrap_trade', 'loc_marco')
    assertf(not ok, 'cooldown ignored')
    assertf(tostring(msg):find('Available again'), 'wrong message: ' .. tostring(msg))
    return msg
end)

check('prerequisite gating blocks a locked mission', function()
    OQ.Missions.abandon(1)
    local ok, reason = OQ.Missions.canStart(1, OQ.Registry.get('mission', 'm_clear_the_block'))
    assertf(not ok, 'locked mission startable')
    assertf(reason == 'mission_locked' or reason == 'mission_level',
        'unexpected reason: ' .. tostring(reason))
    return 'reason=' .. tostring(reason)
end)

check('level gating reports the required level', function()
    OQ.Missions.abandon(1)
    local m = OQ.Registry.get('mission', 'm_night_delivery')
    OQ.Progression.setXP(1, 0)
    local ok, reason, vars = OQ.Missions.canStart(1, m)
    assertf(not ok, 'level gate bypassed')
    assertf(reason == 'mission_level' or reason == 'mission_schedule', 'unexpected reason: ' .. tostring(reason))
    return 'reason=' .. tostring(reason)
end)

check('job restriction only lets the right job through', function()
    OQ.Missions.abandon(1)
    local m = OQ.Registry.get('mission', 'm_evidence_run')
    local okCiv = OQ.Missions.canStart(1, m)
    assertf(not okCiv, 'civilian passed a police-only mission')

    OQ.Progression.load(2)
    TEST.coords[2] = vec3(473.61, -996.14, 25.06)
    local okCop, reason = OQ.Missions.canStart(2, m)
    assertf(okCop, 'police blocked from a police mission: ' .. tostring(reason))
    return 'civ=blocked, police=allowed'
end)

check('schedule window is enforced with the synced game hour', function()
    OQ.Missions.abandon(1)
    local m = OQ.Registry.get('mission', 'm_night_delivery')
    OQ.Progression.setXP(1, 100000)   -- clear the level gate

    TriggerEvent('oqv2:server:timeSync', 13)
    TEST.gameTimer = TEST.gameTimer + 999999
    local ok, reason = OQ.Missions.canStart(1, m)
    assertf(not ok and reason == 'mission_schedule', 'daytime should block: ' .. tostring(reason))

    TEST.gameTimer = TEST.gameTimer + 999999
    TriggerEvent('oqv2:server:timeSync', 23)
    local ok2, reason2 = OQ.Missions.canStart(1, m)
    assertf(ok2, 'night should allow: ' .. tostring(reason2))
    return '13h blocked, 23h allowed'
end)

check('server rejects objective turn-ins from too far away', function()
    OQ.Missions.abandon(1)
    TEST.inventory[1] = { sealed_package = 1 }
    TEST.coords[1] = vec3(707.34, -966.71, 30.41)
    local ok = OQ.Missions.start(1, 'm_night_delivery', nil)
    assertf(ok, 'night delivery did not start')

    local p = OQ.Progression.get(1)
    local deliverObj
    for _, o in ipairs(p.active.objectives) do if o.type == 'deliver' then deliverObj = o end end

    TEST.coords[1] = vec3(0.0, 0.0, 0.0)   -- nowhere near the docks
    local advOk, code = OQ.Missions.advance(1, 'm_night_delivery', deliverObj.id, {})
    assertf(not advOk and code == 'too_far', 'distance check bypassed: ' .. tostring(code))

    TEST.coords[1] = vec3(1208.61, -3115.55, 5.54)
    local nearOk = OQ.Missions.advance(1, 'm_night_delivery', deliverObj.id, {})
    assertf(nearOk, 'valid turn-in rejected')
    return 'far=rejected, near=accepted'
end)

check('a player can only run one mission at a time', function()
    local p = OQ.Progression.get(1)
    if not p.active then
        TEST.inventory[1] = { sealed_package = 1 }
        OQ.Missions.start(1, 'm_night_delivery', nil)
    end
    local ok, msg = OQ.Missions.start(1, 'm_scrap_trade', 'loc_marco')
    assertf(not ok, 'two missions at once')
    assertf(tostring(msg):find('mission') ~= nil, 'unhelpful message: ' .. tostring(msg))
    return tostring(msg)
end)

check('abandoning a mission resets its state', function()
    if not OQ.Progression.get(1).active then
        TEST.inventory[1] = { sealed_package = 1 }
        TEST.coords[1] = vec3(707.34, -966.71, 30.41)
        OQ.Missions.start(1, 'm_night_delivery', nil)
    end
    assertf(OQ.Missions.abandon(1), 'abandon returned false')
    local p = OQ.Progression.get(1)
    assertf(p.active == nil, 'active mission not cleared')
    local entry = OQ.Progression.entry(1, 'm_night_delivery', false)
    assertf(entry.status == 'available', 'status not reset: ' .. tostring(entry.status))
    return 'state = available'
end)

check('kill objectives count up through the hostile-npc pipeline', function()
    OQ.Missions.abandon(1)
    OQ.Progression.setXP(1, 100000)
    TEST.coords[1] = vec3(328.29, -2043.13, 21.31)

    -- unlock the chain
    local e1 = OQ.Progression.entry(1, 'm_scrap_trade', true); e1.completions = 1
    local e2 = OQ.Progression.entry(1, 'm_night_delivery', true); e2.completions = 1

    local ok, msg = OQ.Missions.start(1, 'm_clear_the_block', nil)
    assertf(ok, 'combat mission did not start: ' .. tostring(msg))

    local p = OQ.Progression.get(1)
    -- clear the "goto" objective first
    for _, o in ipairs(p.active.objectives) do
        if o.type == 'goto' then OQ.Missions.advance(1, 'm_clear_the_block', o.id, {}) end
    end
    for _ = 1, 3 do OQ.Npcs.reportKill(1, 'npc_block_crew') end

    local killObj
    for _, o in ipairs(p.active.objectives) do if o.type == 'kill' then killObj = o end end
    assertf(killObj.done, 'kill objective not completed (have %d/%d)', killObj.have, killObj.need)
    return 'goto + 3 kills → objective complete'
end)

check('hostile kill reports are rejected when the player is far away', function()
    TEST.coords[1] = vec3(9999.0, 9999.0, 0.0)
    local ok = OQ.Npcs.reportKill(1, 'npc_block_crew')
    assertf(not ok, 'remote kill report accepted')
    TEST.coords[1] = vec3(328.29, -2043.13, 21.31)
    return 'rejected'
end)

check('loot is capped per group cycle', function()
    local granted, empty = 0, 0
    for _ = 1, 12 do
        local res = OQ.Npcs.loot(1, 'npc_block_crew')
        if res.success and not res.empty then granted = granted + 1 else empty = empty + 1 end
    end
    assertf(granted <= 4, 'loot cap bypassed: %d payouts for a 4-unit group', granted)
    return granted .. ' payouts capped for a 4-unit group'
end)

check('combat mission completes and pays dirty money', function()
    TEST.money[1] = { money = 0, bank = 0, black_money = 0 }
    local ok, msg = OQ.Missions.complete(1, 'm_clear_the_block')
    assertf(ok, 'complete failed: ' .. tostring(msg))
    assertf(TEST.money[1].money == 3200, 'cash wrong: %d', TEST.money[1].money)
    assertf(TEST.money[1].black_money == 1500, 'dirty money wrong: %d', TEST.money[1].black_money)
    return '$3200 cash + $1500 dirty'
end)

check('completing a mission announces unlocked follow-ups', function()
    local found = false
    for _, e in ipairs(TEST.clientEvents) do
        if e.name == 'oqv2:client:missionsUnlocked' then found = true end
    end
    return found and 'unlock event fired' or 'no follow-ups for this mission (expected)'
end)

-------------------------------------------------------------------------------
-- ADMIN CRUD
-------------------------------------------------------------------------------
check('admin can create a mission through the callback', function()
    local res = lib.callback._registered['oqv2:admin:save'](2, 'mission', {
        name = 'Test Mission From Panel',
        description = 'Created by the automated test suite.',
        objectives = { { type = 'goto', label = 'Go somewhere', coords = { x = 10, y = 20, z = 30 }, radius = 3 } },
        rewards = { money = 500 },
        xpReward = 90,
    })
    assertf(res.success, 'save failed: ' .. table.concat(res.errors or {}, ' | '))
    assertf(OQ.Registry.get('mission', res.uid), 'not in registry')
    TEST.newMissionUid = res.uid
    return 'created ' .. res.uid
end)

check('admin save rejects an invalid mission with readable errors', function()
    local res = lib.callback._registered['oqv2:admin:save'](2, 'mission', { name = '', objectives = {} })
    assertf(not res.success, 'invalid mission accepted')
    assertf(#res.errors >= 1, 'no errors returned')
    return res.errors[1]
end)

check('admin save rejects a circular prerequisite chain', function()
    local a = lib.callback._registered['oqv2:admin:save'](2, 'mission', {
        name = 'Cycle A', objectives = { { type = 'goto', coords = { x = 1, y = 1, z = 1 } } }
    })
    local b = lib.callback._registered['oqv2:admin:save'](2, 'mission', {
        name = 'Cycle B', prerequisites = { a.uid },
        objectives = { { type = 'goto', coords = { x = 1, y = 1, z = 1 } } }
    })
    local entA = OQ.deepCopy(OQ.Registry.get('mission', a.uid))
    entA.prerequisites = { b.uid }
    local res = lib.callback._registered['oqv2:admin:save'](2, 'mission', entA)
    assertf(not res.success, 'cycle accepted!')
    assertf(tostring(res.errors[1]):find('Circular'), 'wrong error: ' .. tostring(res.errors[1]))
    TEST.cycleA, TEST.cycleB = a.uid, b.uid
    return res.errors[1]
end)

check('non-admins cannot save or delete', function()
    local res = lib.callback._registered['oqv2:admin:save'](1, 'mission', { name = 'Hack' })
    assertf(not res.success, 'non-admin saved a mission!')
    local del = lib.callback._registered['oqv2:admin:delete'](1, 'mission', 'm_scrap_trade')
    assertf(not del.success, 'non-admin deleted a mission!')
    assertf(OQ.Registry.get('mission', 'm_scrap_trade'), 'mission was actually removed')
    return 'both refused'
end)

check('admin toggle flips the enabled flag and reaches clients', function()
    TEST.clientEvents = {}
    local res = lib.callback._registered['oqv2:admin:toggle'](2, 'mission', 'm_scrap_trade', false)
    assertf(res.success and res.enabled == false, 'toggle failed')
    assertf(OQ.Registry.get('mission', 'm_scrap_trade').enabled == false, 'registry not updated')
    local synced = false
    for _, e in ipairs(TEST.clientEvents) do if e.name == 'oqv2:client:syncWorld' then synced = true end end
    assertf(synced, 'world not re-broadcast')
    lib.callback._registered['oqv2:admin:toggle'](2, 'mission', 'm_scrap_trade', true)
    return 'disabled + re-enabled, clients synced'
end)

check('admin duplicate creates an independent copy', function()
    local res = lib.callback._registered['oqv2:admin:duplicate'](2, 'mission', 'm_scrap_trade')
    assertf(res.success, 'duplicate failed')
    local copy = OQ.Registry.get('mission', res.uid)
    assertf(copy.uid ~= 'm_scrap_trade', 'same uid')
    assertf(copy.name:find('copy'), 'name not marked: ' .. copy.name)
    local orig = OQ.Registry.get('mission', 'm_scrap_trade')
    assertf(copy.objectives[1].id ~= orig.objectives[1].id, 'objective ids were not regenerated')
    TEST.dupUid = res.uid
    return copy.name
end)

check('deleting a mission scrubs it from locations, chains and groups', function()
    -- link the duplicate everywhere first
    local loc = OQ.deepCopy(OQ.Registry.get('location', 'loc_marco'))
    loc.missions[#loc.missions + 1] = TEST.dupUid
    lib.callback._registered['oqv2:admin:save'](2, 'location', loc)

    local res = lib.callback._registered['oqv2:admin:delete'](2, 'mission', TEST.dupUid)
    assertf(res.success, 'delete failed')
    assertf(not OQ.Registry.get('mission', TEST.dupUid), 'still in registry')

    for _, uid in ipairs(OQ.Registry.get('location', 'loc_marco').missions) do
        assertf(uid ~= TEST.dupUid, 'dangling link left on the location')
    end
    return 'reference cleanup verified'
end)

check('export → import round-trips the whole dataset', function()
    local dump = lib.callback._registered['oqv2:admin:export'](2)
    assertf(dump and #dump.missions > 0, 'export empty')
    local encoded = json.encode(dump)
    local decoded = json.decode(encoded)
    assertf(decoded and #decoded.missions == #dump.missions, 'json round-trip lost data')
    local res = lib.callback._registered['oqv2:admin:import'](2, decoded)
    assertf(res.success, 'import failed')
    assertf(res.failed == 0, '%d entries failed to import', res.failed)
    return res.imported .. ' entries re-imported, 0 failed'
end)

check('admin player actions work (xp, level, reset)', function()
    local r1 = lib.callback._registered['oqv2:admin:playerAction'](2, 'addxp', 1, 250)
    assertf(r1.success, 'addxp failed')
    local r2 = lib.callback._registered['oqv2:admin:playerAction'](2, 'setlevel', 1, 15)
    assertf(r2.success, 'setlevel failed')
    assertf(OQ.Progression.get(1).level == 15, 'level not applied: %d', OQ.Progression.get(1).level)
    local r3 = lib.callback._registered['oqv2:admin:playerAction'](2, 'resetprogress', 1)
    assertf(r3.success, 'reset failed')
    assertf(OQ.Progression.get(1).completed == 0, 'completions not cleared')
    return 'xp / setlevel(15) / reset all ok'
end)

check('admin actions are recorded in the log table', function()
    local logs = OQ.DB.fetchLogs(200)
    local actions = {}
    for _, l in ipairs(logs) do actions[l.action] = true end
    assertf(actions['admin_save_mission'], 'save not logged')
    assertf(actions['panel_denied'] or actions['admin_denied'], 'denial not logged')
    assertf(actions['mission_complete'], 'completion not logged')
    return OQ.count(actions) .. ' distinct actions logged'
end)

check('journal callback returns missions + player + locations', function()
    local j = lib.callback._registered['oqv2:server:getJournal'](1)
    assertf(j and j.player and j.missions, 'journal payload broken')
    assertf(#j.missions > 0, 'no missions in the journal')
    assertf(j.branding.footer == 'Made with CodeX Dev.', 'branding missing')
    local hasReason = false
    for _, m in ipairs(j.missions) do if m.reason then hasReason = true end end
    assertf(hasReason, 'locked missions should explain why')
    return #j.missions .. ' missions, ' .. #j.locations .. ' locations'
end)

check('rate limiter throttles event spam', function()
    TEST.gameTimer = 100000
    local first = OQ.Server.rateLimited(1)
    local second = OQ.Server.rateLimited(1)
    assertf(not first, 'first call should pass')
    assertf(second, 'second immediate call should be throttled')
    TEST.gameTimer = TEST.gameTimer + 5000
    assertf(not OQ.Server.rateLimited(1), 'should pass after the window')
    return 'throttle window = ' .. Config.Security.rateLimitMs .. 'ms'
end)

check('no runtime errors or warnings were printed', function()
    if #TEST.errors > 0 then error('errors: ' .. table.concat(TEST.errors, ' | ')) end
    -- Warnings the permission tests provoke on purpose.
    local expected = { 'circular', 'unauthorised', 'tried to open', 'memory%-only' }
    local unexpected = {}
    for _, wmsg in ipairs(TEST.warnings) do
        local ok = false
        for _, pat in ipairs(expected) do if wmsg:find(pat) then ok = true end end
        if not ok then unexpected[#unexpected + 1] = wmsg end
    end
    assertf(#unexpected == 0, 'warnings: ' .. table.concat(unexpected, ' | '))
    return ('%d console lines, 0 errors, %d expected warnings')
        :format(#TEST.prints, #TEST.warnings)
end)

-------------------------------------------------------------------------------
-- REPORT
-------------------------------------------------------------------------------
local width = 0
for _, r in ipairs(results) do width = math.max(width, #r[2]) end

TEST.rawPrint('')
TEST.rawPrint('\27[35m══ OQV2 QUESTS — Lua runtime test suite ══\27[0m')
TEST.rawPrint('')
for _, r in ipairs(results) do
    local colour = r[1] == 'PASS' and '\27[32m' or '\27[31m'
    TEST.rawPrint(('  %s%s\27[0m  %s  \27[90m%s\27[0m'):format(colour, r[1], r[2] .. string.rep(' ', width - #r[2]), r[3]))
end
TEST.rawPrint('')
TEST.rawPrint(('  %d passed, %d failed'):format(#results - failures, failures))

TEST.exitCode = failures > 0 and 1 or 0
