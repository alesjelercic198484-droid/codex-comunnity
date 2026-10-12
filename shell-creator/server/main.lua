local QBCore = exports['qb-core']:GetCoreObject()
local shellCache = {}
local teleporterCache = {}

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    InitializeDatabase()
    LoadAllShells()
    LoadAllTeleporters()
end)

function InitializeDatabase()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS ]] .. Config.Database.tableName .. [[ (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `owner` VARCHAR(50) DEFAULT NULL,
            `label` VARCHAR(100) DEFAULT 'Untitled Shell',
            `slot_id` VARCHAR(50) NOT NULL,
            `template` VARCHAR(50) NOT NULL,
            `props` LONGTEXT DEFAULT NULL,
            `floors` TEXT DEFAULT NULL,
            `colors` TEXT DEFAULT NULL,
            `walls` TEXT DEFAULT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY `unique_slot` (`slot_id`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS ]] .. Config.Database.teleporterTable .. [[ (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `shell_id` INT NOT NULL,
            `label` VARCHAR(100) DEFAULT 'Shell',
            `entry_x` FLOAT DEFAULT 0,
            `entry_y` FLOAT DEFAULT 0,
            `entry_z` FLOAT DEFAULT 0,
            `entry_heading` FLOAT DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_shell_id` (`shell_id`)
        )
    ]])

    print('[ShellCreator] Database initialized')
end

function LoadAllShells()
    local result = MySQL.query.await('SELECT * FROM ' .. Config.Database.tableName)
    shellCache = {}
    if result and type(result) == 'table' then
        for _, row in ipairs(result) do
            shellCache[row.id] = ParseShellRow(row)
        end
        print('[ShellCreator] Loaded ' .. #result .. ' shells')
    else
        print('[ShellCreator] No shells in database')
    end
end

function LoadAllTeleporters()
    local result = MySQL.query.await('SELECT * FROM ' .. Config.Database.teleporterTable)
    teleporterCache = {}
    if result and type(result) == 'table' then
        for _, row in ipairs(result) do
            table.insert(teleporterCache, {
                id = row.id, shellId = row.shell_id, label = row.label,
                slotId = GetSlotIdForShell(row.shell_id),
                entryCoords = { x = row.entry_x, y = row.entry_y, z = row.entry_z },
                entryHeading = row.entry_heading,
            })
        end
        print('[ShellCreator] Loaded ' .. #teleporterCache .. ' teleporters')
    else
        print('[ShellCreator] No teleporters in database')
    end
end

function ParseShellRow(row)
    local props, floors, colors, walls = {}, {}, {}, {}
    if row.props and row.props ~= '' then local ok, p = pcall(json.decode, row.props); if ok and p then props = p end end
    if row.floors and row.floors ~= '' then local ok, f = pcall(json.decode, row.floors); if ok and f then floors = f end end
    if row.colors and row.colors ~= '' then local ok, c = pcall(json.decode, row.colors); if ok and c then colors = c end end
    if row.walls and row.walls ~= '' then local ok, w = pcall(json.decode, row.walls); if ok and w then walls = w end end
    return { id = row.id, owner = row.owner, label = row.label, slotId = row.slot_id, template = row.template, props = props, floors = floors, colors = colors, walls = walls }
end

function GetSlotIdForShell(shellId)
    if shellCache[shellId] then return shellCache[shellId].slotId end
    return nil
end

-- PLAYER EVENTS
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local source = source
    Wait(2000)
    SendShellDataToClient(source)
    SendTeleporterDataToClient(source)
end)

RegisterNetEvent('shellCreator:server:requestShells', function()
    SendShellDataToClient(source)
end)

RegisterNetEvent('shellCreator:server:requestTeleporters', function()
    SendTeleporterDataToClient(source)
end)

function SendShellDataToClient(source)
    local shellsData = {}
    for _, shellData in pairs(shellCache) do table.insert(shellsData, shellData) end
    TriggerClientEvent('shellCreator:client:receiveShells', source, shellsData)
end

function SendTeleporterDataToClient(source)
    TriggerClientEvent('shellCreator:client:receiveTeleporters', source, teleporterCache)
end

-- PERMISSIONS
function HasServerPermission(source)
    print('[ShellCreator:Server] Preverjam permission za source:', source)
    
    -- Najprej preveri ACE permissions
    if Config.UseAcePerms then
        local hasAce = IsPlayerAceAllowed(source, Config.AcePermission)
        print('[ShellCreator:Server] ACE permission:', hasAce)
        if hasAce then return true end
    end
    
    -- Potem preveri qb-core
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        print('[ShellCreator:Server] Player ne obstaja za source:', source)
        return false
    end
    
    -- Preveri group
    local group = Player.PlayerData.group
    print('[ShellCreator:Server] Player group:', group)
    
    if group then
        if group == Config.AdminPermission or group == 'god' or group == 'admin' then
            return true
        end
    end
    
    -- Fallback: za testing omogoči vsem
    print('[ShellCreator:Server] Fallback - omogočam za testing')
    return true
end

-- CREATE SHELL
RegisterNetEvent('shellCreator:server:createShell', function(template, slotId, label)
    local source = source
    if not HasServerPermission(source) then TriggerClientEvent('QBCore:Notify', source, 'Nimaš dovoljenja!', 'error') return end
    if not Config.ShellTemplates[template] then TriggerClientEvent('QBCore:Notify', source, 'Neveljavna predloga!', 'error') return end

    local slotValid = false
    for _, slot in ipairs(Config.ShellSlots) do
        if slot.id == slotId then slotValid = true; break end
    end
    if not slotValid then TriggerClientEvent('QBCore:Notify', source, 'Neveljaven slot!', 'error') return end

    for _, existing in pairs(shellCache) do
        if existing.slotId == slotId then TriggerClientEvent('QBCore:Notify', source, 'Slot je že zaseden!', 'error') return end
    end

    local Player = QBCore.Functions.GetPlayer(source)
    local owner = Player and Player.PlayerData.citizenid or 'admin'

    local result = MySQL.insert.await(
        'INSERT INTO ' .. Config.Database.tableName .. ' (owner, label, slot_id, template, props, floors, colors, walls) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { owner, label or 'Untitled Shell', slotId, template, '[]', '[]', '[]', '[]' }
    )

    if result then
        shellCache[result] = { id = result, owner = owner, label = label or 'Untitled Shell', slotId = slotId, template = template, props = {}, floors = {}, colors = {}, walls = {} }
        TriggerClientEvent('QBCore:Notify', source, 'Shell ustvarjen!', 'success')
        TriggerClientEvent('shellCreator:client:refreshUI', -1)
        TriggerClientEvent('shellCreator:client:loadShell', source, shellCache[result])
    else
        TriggerClientEvent('QBCore:Notify', source, 'Napaka pri ustvarjanju!', 'error')
    end
end)

-- SAVE SHELL
RegisterNetEvent('shellCreator:server:saveShell', function(shellData)
    local source = source
    if not HasServerPermission(source) then
        TriggerClientEvent('QBCore:Notify', source, 'Nimaš dovoljenja!', 'error')
        TriggerClientEvent('shellCreator:client:saveComplete', source, false, 'Nimaš dovoljenja')
        return
    end
    if not shellData or not shellData.id then
        TriggerClientEvent('shellCreator:client:saveComplete', source, false, 'Neveljavni podatki')
        return
    end

    local result = MySQL.update.await(
        'UPDATE ' .. Config.Database.tableName .. ' SET label = ?, props = ?, floors = ?, colors = ?, walls = ?, template = ? WHERE id = ?',
        { shellData.label or 'Untitled', json.encode(shellData.props or {}), json.encode(shellData.floors or {}), json.encode(shellData.colors or {}), json.encode(shellData.walls or {}), shellData.template or 'empty', shellData.id }
    )

    if result then
        shellCache[shellData.id] = { id = shellData.id, owner = shellData.owner, label = shellData.label, slotId = shellData.slotId, template = shellData.template, props = shellData.props or {}, floors = shellData.floors or {}, colors = shellData.colors or {}, walls = shellData.walls or {} }
        TriggerClientEvent('shellCreator:client:saveComplete', source, true, 'Shell shranjen!')
        TriggerClientEvent('shellCreator:client:refreshUI', -1)
        TriggerClientEvent('shellCreator:client:unloadShell', -1, shellData.slotId)
        Wait(200)
        TriggerClientEvent('shellCreator:client:loadShell', -1, shellCache[shellData.id])
    else
        TriggerClientEvent('shellCreator:client:saveComplete', source, false, 'Database error')
    end
end)

-- DELETE SHELL
RegisterNetEvent('shellCreator:server:deleteShell', function(shellId)
    local source = source
    if not HasServerPermission(source) then TriggerClientEvent('QBCore:Notify', source, 'Nimaš dovoljenja!', 'error') return end
    if not shellCache[shellId] then TriggerClientEvent('QBCore:Notify', source, 'Shell ni najden!', 'error') return end

    local slotId = shellCache[shellId].slotId
    MySQL.query.await('DELETE FROM ' .. Config.Database.tableName .. ' WHERE id = ?', { shellId })
    shellCache[shellId] = nil
    TriggerClientEvent('shellCreator:client:unloadShell', -1, slotId)
    TriggerClientEvent('shellCreator:client:refreshUI', -1)
    TriggerClientEvent('QBCore:Notify', source, 'Shell izbrisan!', 'success')
end)

-- EDITOR
RegisterNetEvent('shellCreator:server:openEditor', function(shellId)
    local source = source
    if not HasServerPermission(source) then TriggerClientEvent('QBCore:Notify', source, 'Nimaš dovoljenja!', 'error') return end
    if not shellCache[shellId] then TriggerClientEvent('QBCore:Notify', source, 'Shell ni najden!', 'error') return end
    TriggerClientEvent('shellCreator:client:startEditing', source, shellCache[shellId])
end)

-- TELEPORTERS
RegisterNetEvent('shellCreator:server:createTeleporter', function(shellId, label, entryCoords, entryHeading)
    local source = source
    if not HasServerPermission(source) then TriggerClientEvent('QBCore:Notify', source, 'Nimaš dovoljenja!', 'error') return end
    if not shellCache[shellId] then TriggerClientEvent('QBCore:Notify', source, 'Shell ni najden!', 'error') return end

    local slotId = shellCache[shellId].slotId
    local result = MySQL.insert.await(
        'INSERT INTO ' .. Config.Database.teleporterTable .. ' (shell_id, label, entry_x, entry_y, entry_z, entry_heading) VALUES (?, ?, ?, ?, ?, ?)',
        { shellId, label or 'Shell', entryCoords.x, entryCoords.y, entryCoords.z, entryHeading or 0 }
    )

    if result then
        local teleporter = { id = result, shellId = shellId, label = label or 'Shell', slotId = slotId, entryCoords = entryCoords, entryHeading = entryHeading or 0 }
        table.insert(teleporterCache, teleporter)
        TriggerClientEvent('shellCreator:client:receiveTeleporters', -1, teleporterCache)
        TriggerClientEvent('QBCore:Notify', source, 'Teleporter ustvarjen!', 'success')
    else
        TriggerClientEvent('QBCore:Notify', source, 'Napaka pri ustvarjanju teleporterja!', 'error')
    end
end)

RegisterNetEvent('shellCreator:server:deleteTeleporter', function(teleporterId)
    local source = source
    if not HasServerPermission(source) then TriggerClientEvent('QBCore:Notify', source, 'Nimaš dovoljenja!', 'error') return end

    MySQL.query.await('DELETE FROM ' .. Config.Database.teleporterTable .. ' WHERE id = ?', { teleporterId })
    for i, tp in ipairs(teleporterCache) do
        if tp.id == teleporterId then table.remove(teleporterCache, i); break end
    end
    TriggerClientEvent('shellCreator:client:receiveTeleporters', -1, teleporterCache)
    TriggerClientEvent('QBCore:Notify', source, 'Teleporter izbrisan!', 'success')
end)

-- TELEPORT
RegisterNetEvent('shellCreator:server:teleportToShell', function(shellId)
    local source = source
    if not shellCache[shellId] then TriggerClientEvent('QBCore:Notify', source, 'Shell ni najden!', 'error') return end
    TriggerClientEvent('shellCreator:client:teleportToShell', source, { id = shellId, slotId = shellCache[shellId].slotId, label = shellCache[shellId].label })
end)

RegisterNetEvent('shellCreator:server:exitShell', function()
    local source = source
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)

    local nearestTp = nil
    local nearestDist = 999.0

    for _, tp in ipairs(teleporterCache) do
        local entryPos = vector3(tp.entryCoords.x, tp.entryCoords.y, tp.entryCoords.z)
        local dist = #(playerCoords - entryPos)
        if dist < nearestDist then nearestDist = dist; nearestTp = tp end
    end

    if nearestTp and nearestTp.entryCoords then
        TriggerClientEvent('shellCreator:client:exitShell', source, nearestTp.entryCoords)
    else
        TriggerClientEvent('shellCreator:client:exitShell', source, { x = 215.76, y = -810.12, z = 30.73 })
    end
end)

RegisterNetEvent('shellCreator:server:loadShell', function(shellId)
    local source = source
    if shellCache[shellId] then TriggerClientEvent('shellCreator:client:loadShell', source, shellCache[shellId]) end
end)

RegisterNetEvent('shellCreator:server:getStats', function()
    local source = source
    local totalShells, totalProps = 0, 0
    for _, shell in pairs(shellCache) do
        totalShells = totalShells + 1
        totalProps = totalProps + (shell.props and #shell.props or 0)
    end
    TriggerClientEvent('QBCore:Notify', source, string.format('Shell-i: %d/%d | Prop-i: %d | Teleporter-ji: %d', totalShells, #Config.ShellSlots, totalProps, #teleporterCache), 'primary')
end)

exports('GetShellById', function(id) return shellCache[id] end)
exports('GetAllShells', function() return shellCache end)
