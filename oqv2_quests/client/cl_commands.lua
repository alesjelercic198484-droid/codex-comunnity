--[[ OQV2 QUESTS — Client commands, keybinds & exports | Made with CodeX Dev. ]]

-------------------------------------------------------------------------------
-- PLAYER JOURNAL
-------------------------------------------------------------------------------
if Config.Journal.enabled then
    RegisterCommand(Config.Journal.command, function()
        if OQ.State.nuiOpen then
            OQ.Client.closeNui()
        else
            OQ.Client.openJournal()
        end
    end, false)

    if Config.Journal.keybind then
        RegisterKeyMapping(Config.Journal.command, 'OQV2 — Mission journal', 'keyboard', Config.Journal.keybind)
    end

    TriggerEvent('chat:addSuggestion', '/' .. Config.Journal.command, 'Open your OQV2 mission journal')
end

-------------------------------------------------------------------------------
-- CHAT SUGGESTION for the admin command (the server does the permission check)
-------------------------------------------------------------------------------
CreateThread(function()
    Wait(1000)
    TriggerEvent('chat:addSuggestion', '/' .. Config.Admin.command, 'Open the OQV2 admin panel (administrators only)')
end)

-------------------------------------------------------------------------------
-- ABANDON SHORTCUT
-------------------------------------------------------------------------------
RegisterCommand('oqv2abandon', function()
    if not OQ.State.active then
        OQ.Client.notify(Config.UI.brand, 'You have no active mission.', 'inform')
        return
    end
    local confirm = lib.alertDialog({
        header   = OQ.State.active.name,
        content  = 'Abandon this mission? All progress on it will be lost.',
        centered = true,
        cancel   = true,
    })
    if confirm == 'confirm' then
        lib.callback.await('oqv2:server:abandonMission', false)
    end
end, false)

-------------------------------------------------------------------------------
-- EXPORTS
-------------------------------------------------------------------------------
exports('isNuiOpen', function()
    return OQ.State.nuiOpen
end)

exports('getActiveMission', function()
    return OQ.State.active
end)

exports('getPlayerLevel', function()
    return OQ.State.player and OQ.State.player.level or 1
end)

exports('openJournal', function()
    OQ.Client.openJournal()
end)

exports('closeUI', function()
    OQ.Client.closeNui()
end)
