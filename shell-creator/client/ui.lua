local QBCore = exports['qb-core']:GetCoreObject()
local nuiOpen = false

function OpenShellCreatorMenu()
    print('[ShellCreator] Odpiram NUI menu...')
    
    nuiOpen = true
    SetNuiFocus(true, true)

    local props = GetFormattedPropList()
    print('[ShellCreator] Props:', #props, 'kategorij')
    
    local data = {
        action = 'openMenu',
        props = props,
        colors = GetFormattedColorList(),
        templates = GetFormattedTemplates(),
        slots = GetFormattedSlots(),
        shells = GetShellsList(),
        keys = Config.Keys,
        maxProps = Config.Editor.maxPropsPerShell,
        maxFloors = Config.Editor.maxFloors,
        isEditing = editorActive,
    }
    
    print('[ShellCreator] Pošiljam NUI message...')
    SendNUIMessage(data)
    print('[ShellCreator] Menu odprt!')
end

function CloseShellCreatorMenu()
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMenu' })
end

function GetShellsList()
    local shells = {}
    for slotId, shellInfo in pairs(loadedShells) do
        table.insert(shells, {
            slotId = slotId, shellId = shellInfo.shellId,
            label = shellInfo.label or 'Untitled', template = shellInfo.template,
            propCount = shellInfo.props and #shellInfo.props or 0,
            floorCount = shellInfo.floors and #shellInfo.floors or 1,
        })
    end
    return shells
end

-- NUI CALLBACKS
RegisterNUICallback('closeMenu', function(data, cb)
    CloseShellCreatorMenu()
    cb('ok')
end)

RegisterNUICallback('selectProp', function(data, cb)
    if data.model then
        StartPlacingProp(data.model)
        CloseShellCreatorMenu()
    end
    cb('ok')
end)

RegisterNUICallback('createNewShell', function(data, cb)
    TriggerServerEvent('shellCreator:server:createShell', data.template, data.slotId, data.label or 'New Shell')
    cb('ok')
end)

RegisterNUICallback('editShell', function(data, cb)
    if data.shellId then
        OpenEditorForShell(data.shellId)
        CloseShellCreatorMenu()
    end
    cb('ok')
end)

RegisterNUICallback('deleteShell', function(data, cb)
    if data.shellId then TriggerServerEvent('shellCreator:server:deleteShell', data.shellId) end
    cb('ok')
end)

RegisterNUICallback('createTeleporter', function(data, cb)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    TriggerServerEvent('shellCreator:server:createTeleporter', data.shellId, data.label or 'Shell', { x = coords.x, y = coords.y, z = coords.z }, heading)
    cb('ok')
end)

RegisterNUICallback('deleteTeleporter', function(data, cb)
    if data.teleporterId then TriggerServerEvent('shellCreator:server:deleteTeleporter', data.teleporterId) end
    cb('ok')
end)

RegisterNUICallback('applyWallColor', function(data, cb)
    ApplyColorToWall(data.colorIndex)
    cb('ok')
end)

RegisterNUICallback('applyFloorColor', function(data, cb)
    ApplyColorToFloor(data.colorIndex)
    cb('ok')
end)

RegisterNUICallback('addFloor', function(data, cb)
    AddFloor()
    cb('ok')
end)

RegisterNUICallback('switchFloor', function(data, cb)
    SetCurrentFloor(data.floor)
    cb('ok')
end)

RegisterNUICallback('saveShell', function(data, cb)
    SaveCurrentShell()
    cb('ok')
end)

RegisterNUICallback('exportConfig', function(data, cb)
    if editingShellData then
        local config = GenerateHousingConfig(data.housingType, editingShellData)
        cb({ config = config })
    else
        cb({ config = '-- Ni shell-a v editiranju' })
    end
end)

RegisterNUICallback('getShells', function(data, cb)
    cb({ shells = GetShellsList() })
end)

RegisterNUICallback('teleportToShell', function(data, cb)
    if data.shellId then TriggerServerEvent('shellCreator:server:teleportToShell', data.shellId) end
    cb('ok')
end)

-- HOUSING EXPORT
function GenerateHousingConfig(housingType, shellData)
    local slot = GetSlotById(shellData.slotId)
    if not slot then return '-- Napaka: Slot ni najden' end

    local label = shellData.label or 'custom_shell'
    local template = shellData.template or 'empty'
    local cx, cy, cz = slot.coords.x, slot.coords.y, slot.coords.z
    local h = slot.heading

    if housingType == 'ps-housing' then
        return string.format("-- PS-Housing Config\n['%s'] = {\n    label = '%s',\n    doorzone = vector3(%.2f, %.2f, %.2f),\n    shell = '%s',\n    coords = vector3(%.2f, %.2f, %.2f),\n    heading = %.2f,\n},", label, label, cx, cy, cz, template, cx, cy, cz, h)
    elseif housingType == 'qs-housing' then
        return string.format("-- QS-Housing Config\nConfig.Properties['%s'] = {\n    label = '%s',\n    enter = vector4(%.2f, %.2f, %.2f, %.2f),\n    interior = { shell = '%s', coords = vector3(%.2f, %.2f, %.2f), heading = %.2f },\n},", label, label, cx, cy, cz, h, template, cx, cy, cz, h)
    elseif housingType == 'nolag_properties' then
        return string.format("-- NoLag Properties Config\n['%s'] = {\n    name = '%s',\n    coords = { enter = vector3(%.2f, %.2f, %.2f) },\n    shell = true, shell_model = '%s',\n    shell_coords = vector3(%.2f, %.2f, %.2f), shell_heading = %.2f,\n},", label, label, cx, cy, cz, template, cx, cy, cz, h)
    elseif housingType == 'esx_property' then
        return string.format("-- ESX Property Config\n{\n    name = '%s',\n    gateway = vector4(%.2f, %.2f, %.2f, %.2f),\n    shell = { id = '%s', coords = vector3(%.2f, %.2f, %.2f), heading = %.2f },\n},", label, cx, cy, cz, h, template, cx, cy, cz, h)
    elseif housingType == 'loaf-housing' then
        return string.format("-- Loaf Housing Config\nexports('AddProperty', {\n    id = '%s', label = '%s',\n    door = vector4(%.2f, %.2f, %.2f, %.2f),\n    interior = { shell = '%s', coords = vector3(%.2f, %.2f, %.2f), heading = %.2f },\n})", label, label, cx, cy, cz, h, template, cx, cy, cz, h)
    else
        return '-- Neznan housing type: ' .. tostring(housingType)
    end
end

-- EVENTS
RegisterNetEvent('shellCreator:client:refreshUI', function()
    if nuiOpen then
        SendNUIMessage({ action = 'refreshData', shells = GetShellsList(), slots = GetFormattedSlots() })
    end
end)

RegisterNetEvent('shellCreator:client:notify', function(message, type)
    QBCore.Functions.Notify(message, type or 'primary')
end)

if Config.QBCore.itemEnabled then
    RegisterNetEvent('QBCore:Client:UseItem', function(item)
        if item and item.name == Config.QBCore.itemName then OpenShellCreatorMenu() end
    end)
end

exports('OpenShellCreatorMenu', OpenShellCreatorMenu)
