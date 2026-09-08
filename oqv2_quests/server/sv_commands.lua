--[[ OQV2 QUESTS — Server commands & exports | Made with CodeX Dev. ]]

-------------------------------------------------------------------------------
-- /oqv2  →  opens the admin NUI (administrators only)
-------------------------------------------------------------------------------
RegisterCommand(Config.Admin.command, function(source, args)
    local src = source

    -- console usage: /oqv2 reload | stats
    if src == 0 then
        local sub = (args[1] or ''):lower()
        if sub == 'reload' then
            OQ.Server.loadAll()
            OQ.Server.broadcastWorld(-1)
            OQ.print('^2data reloaded^7')
        elseif sub == 'stats' then
            local s = OQ.DB.globalStats()
            OQ.print(('missions=%d locations=%d npcs=%d players=%d completions=%d')
                :format(OQ.count(OQ.Registry.missions), OQ.count(OQ.Registry.locations),
                        OQ.count(OQ.Registry.npcs), s.players, s.completions))
        else
            OQ.print('usage: oqv2 reload | oqv2 stats   (in-game: /' .. Config.Admin.command .. ' opens the panel)')
        end
        return
    end

    local allowed, reason = OQ.Server.isAdmin(src)
    if not allowed then
        OQ.Server.notify(src, Config.UI.brand, OQ.L('panel_denied'), 'error')
        if Config.Admin.logDenied then
            OQ.warn(('%s (%s) tried to open the admin panel'):format(GetPlayerName(src) or '?', src))
            OQ.DB.log(OQ.Server.getIdentifier(src), OQ.Server.getName(src), 'panel_denied', reason)
        end
        return
    end

    TriggerClientEvent('oqv2:client:openAdmin', src)
    OQ.DB.log(OQ.Server.getIdentifier(src), OQ.Server.getName(src), 'panel_open', reason)
end, false)

-------------------------------------------------------------------------------
-- /oqv2give  →  quick admin helper to grant xp
-------------------------------------------------------------------------------
RegisterCommand(Config.Admin.command .. 'xp', function(source, args)
    local src = source
    if src ~= 0 and not OQ.Server.isAdmin(src) then
        OQ.Server.notify(src, Config.UI.brand, OQ.L('no_permission'), 'error')
        return
    end
    local target = tonumber(args[1])
    local amount = tonumber(args[2])
    if not target or not amount then
        if src == 0 then OQ.print('usage: oqv2xp <playerId> <amount>') end
        return
    end
    if not GetPlayerName(target) then return end
    OQ.Progression.addXP(target, amount)
    if src ~= 0 then
        OQ.Server.notify(src, Config.UI.brand, ('Gave %d XP to %s'):format(amount, GetPlayerName(target)), 'success')
    end
end, false)

-------------------------------------------------------------------------------
-- EXPORTS (for other resources)
-------------------------------------------------------------------------------
exports('getPlayerLevel', function(src)
    return OQ.Progression.getLevel(src)
end)

exports('getPlayerXP', function(src)
    local p = OQ.Progression.get(src, false)
    return p and p.xp or 0
end)

exports('addPlayerXP', function(src, amount)
    OQ.Progression.addXP(src, amount)
    return true
end)

exports('hasCompletedMission', function(src, missionUid)
    return OQ.Progression.isCompleted(src, missionUid)
end)

exports('startMission', function(src, missionUid)
    return OQ.Missions.start(src, missionUid, nil)
end)

exports('getMissions', function()
    return OQ.Registry.list('mission')
end)

exports('getLocations', function()
    return OQ.Registry.list('location')
end)

exports('reload', function()
    OQ.Server.loadAll()
    OQ.Server.broadcastWorld(-1)
    return true
end)
