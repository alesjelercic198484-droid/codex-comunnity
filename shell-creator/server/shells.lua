-- SHELL CREATOR - SERVER SHELLS
-- Additional server utilities

function ValidateShellData(shellData)
    if not shellData then return false, 'No shell data' end
    if not shellData.id then return false, 'Missing ID' end
    if not shellData.slotId then return false, 'Missing slot' end
    if not shellData.template then return false, 'Missing template' end
    if not Config.ShellTemplates[shellData.template] then return false, 'Invalid template' end

    if shellData.props then
        if type(shellData.props) ~= 'table' then return false, 'Invalid props' end
        if #shellData.props > Config.Editor.maxPropsPerShell then return false, 'Too many props' end
    end

    if shellData.floors then
        if type(shellData.floors) ~= 'table' then return false, 'Invalid floors' end
        if #shellData.floors > Config.Editor.maxFloors then return false, 'Too many floors' end
    end

    return true, 'OK'
end

-- Clone shell
RegisterNetEvent('shellCreator:server:cloneShell', function(sourceShellId, targetSlotId)
    local source = source
    if not shellCache[sourceShellId] then TriggerClientEvent('QBCore:Notify', source, 'Source shell ni najden!', 'error') return end

    for _, shell in pairs(shellCache) do
        if shell.slotId == targetSlotId then TriggerClientEvent('QBCore:Notify', source, 'Ciljni slot je zaseden!', 'error') return end
    end

    local src = shellCache[sourceShellId]
    local Player = QBCore.Functions.GetPlayer(source)
    local owner = Player and Player.PlayerData.citizenid or 'admin'

    local newProps = {}
    if src.props then
        for _, prop in ipairs(src.props) do
            local newProp = {}
            for k, v in pairs(prop) do newProp[k] = v end
            table.insert(newProps, newProp)
        end
    end

    local result = MySQL.insert.await(
        'INSERT INTO ' .. Config.Database.tableName .. ' (owner, label, slot_id, template, props, floors, colors, walls) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { owner, src.label .. ' (Copy)', targetSlotId, src.template, json.encode(newProps), json.encode(src.floors or {}), json.encode(src.colors or {}), json.encode(src.walls or {}) }
    )

    if result then
        shellCache[result] = { id = result, owner = owner, label = src.label .. ' (Copy)', slotId = targetSlotId, template = src.template, props = newProps, floors = src.floors or {}, colors = src.colors or {}, walls = src.walls or {} }
        TriggerClientEvent('QBCore:Notify', source, 'Shell kloniran!', 'success')
        TriggerClientEvent('shellCreator:client:refreshUI', -1)
        TriggerClientEvent('shellCreator:client:loadShell', source, shellCache[result])
    end
end)
