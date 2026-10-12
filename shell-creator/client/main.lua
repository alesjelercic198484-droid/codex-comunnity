local QBCore = exports['qb-core']:GetCoreObject()

local isLoggedIn = false
isEditing = false
local currentShell = nil
local currentShellData = nil
loadedShells = {}
local teleporters = {}
local isInShellZone = false
local currentShellZone = nil

-- INIT
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    isLoggedIn = true
    TriggerServerEvent('shellCreator:server:requestShells')
    TriggerServerEvent('shellCreator:server:requestTeleporters')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
    ExitEditMode()
    UnloadAllShells()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    isLoggedIn = true
    TriggerServerEvent('shellCreator:server:requestShells')
    TriggerServerEvent('shellCreator:server:requestTeleporters')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    UnloadAllShells()
    ExitEditMode()
end)

-- COMMANDS
RegisterCommand(Config.QBCore.commandName, function()
    if not HasPermission() then return end
    if not isLoggedIn then
        QBCore.Functions.Notify('Nisi prijavljen!', 'error')
        return
    end
    OpenShellCreatorMenu()
end, false)

RegisterCommand(Config.QBCore.teleportCommand, function(source, args)
    if not HasPermission() then return end
    if not args[1] then
        QBCore.Functions.Notify('Uporaba: /' .. Config.QBCore.teleportCommand .. ' [shell_id]', 'error')
        return
    end
    local shellId = tonumber(args[1])
    if shellId then
        TriggerServerEvent('shellCreator:server:teleportToShell', shellId)
    else
        QBCore.Functions.Notify('Neveljaven shell ID!', 'error')
    end
end, false)

RegisterCommand('shelllist', function()
    if not HasPermission() then return end
    TriggerServerEvent('shellCreator:server:getStats')
end, false)

-- PERMISSIONS
function HasPermission()
    if Config.UseAcePerms then
        return IsPlayerAceAllowed(PlayerId(), Config.AcePermission)
    else
        local PlayerData = QBCore.Functions.GetPlayerData()
        if PlayerData and PlayerData.group then
            return PlayerData.group == Config.AdminPermission or PlayerData.group == 'god'
        end
        return false
    end
end

exports('HasPermission', HasPermission)

-- SHELL LOADING
function LoadShell(shellData)
    if not shellData or not shellData.slotId then return false end

    local slot = GetSlotById(shellData.slotId)
    if not slot then return false end

    if loadedShells[shellData.slotId] then
        UnloadShell(shellData.slotId)
    end

    local shellInfo = {
        slotId = shellData.slotId,
        shellId = shellData.id,
        coords = slot.coords,
        heading = slot.heading,
        template = shellData.template,
        props = shellData.props or {},
        floors = shellData.floors or {},
        colors = shellData.colors or {},
        label = shellData.label or 'Untitled Shell',
    }

    LoadShellEntities(shellInfo)
    loadedShells[shellData.slotId] = shellInfo
    return true
end

function LoadShellEntities(shellInfo)
    local coords = shellInfo.coords
    local heading = shellInfo.heading

    if shellInfo.floors and #shellInfo.floors > 0 then
        for _, floor in ipairs(shellInfo.floors) do
            CreateFloorEntity(coords, heading, floor)
        end
    else
        CreateFloorEntity(coords, heading, { height = 0, color = Config.Colors[1] })
    end

    if shellInfo.props then
        for _, propData in ipairs(shellInfo.props) do
            CreateShellProp(coords, heading, propData)
        end
    end
end

function CreateFloorEntity(baseCoords, baseHeading, floorData)
    local height = floorData.height or 0.0
    local floorModel = GetHashKey('v_corp_floor')

    if not HasModelLoaded(floorModel) then
        RequestModel(floorModel)
        local timeout = 0
        while not HasModelLoaded(floorModel) and timeout < 50 do
            Wait(10)
            timeout = timeout + 1
        end
    end

    if not HasModelLoaded(floorModel) then return end

    local floorCoords = vector3(baseCoords.x, baseCoords.y, baseCoords.z + height)
    local floorObj = CreateObjectNoOffset(floorModel, floorCoords.x, floorCoords.y, floorCoords.z, false, false, false)

    if floorObj ~= 0 then
        SetEntityHeading(floorObj, baseHeading)
        FreezeEntityPosition(floorObj, true)
        SetEntityCollision(floorObj, true, true)
        SetModelAsNoLongerNeeded(floorModel)
        if not floorData._entities then floorData._entities = {} end
        table.insert(floorData._entities, floorObj)
    end
end

function CreateShellProp(baseCoords, baseHeading, propData)
    local model = GetHashKey(propData.model)
    if not IsModelValid(model) and not IsModelInCdimage(model) then return nil end

    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 50 do
        Wait(10)
        timeout = timeout + 1
    end

    if not HasModelLoaded(model) then return nil end

    local worldCoords = GetWorldOffset(baseCoords, baseHeading, propData.x or 0, propData.y or 0, propData.z or 0)
    local worldHeading = baseHeading + (propData.heading or 0)

    local obj = CreateObjectNoOffset(model, worldCoords.x, worldCoords.y, worldCoords.z, false, false, false)
    if obj ~= 0 then
        SetEntityHeading(obj, worldHeading)
        FreezeEntityPosition(obj, true)
        SetEntityCollision(obj, true, true)
        SetModelAsNoLongerNeeded(model)
        propData._entity = obj
        propData._model = model
    end

    return obj
end

function UnloadShell(slotId)
    local shellInfo = loadedShells[slotId]
    if not shellInfo then return end

    if shellInfo.props then
        for _, propData in ipairs(shellInfo.props) do
            if propData._entity and DoesEntityExist(propData._entity) then
                DeleteEntity(propData._entity)
                propData._entity = nil
            end
        end
    end

    if shellInfo.floors then
        for _, floor in ipairs(shellInfo.floors) do
            if floor._entities then
                for _, ent in ipairs(floor._entities) do
                    if DoesEntityExist(ent) then DeleteEntity(ent) end
                end
                floor._entities = nil
            end
        end
    end

    loadedShells[slotId] = nil
end

function UnloadAllShells()
    for slotId, _ in pairs(loadedShells) do
        UnloadShell(slotId)
    end
    loadedShells = {}
end

-- TELEPORTERS
RegisterNetEvent('shellCreator:client:receiveTeleporters', function(teleporterData)
    teleporters = teleporterData or {}
end)

CreateThread(function()
    while true do
        Wait(500)
        if not isLoggedIn or isEditing then
            Wait(2000)
            goto continue
        end

        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local nearTeleporter = false

        for _, tp in ipairs(teleporters) do
            if tp.entryCoords then
                local entryPos = vector3(tp.entryCoords.x, tp.entryCoords.y, tp.entryCoords.z)
                local dist = #(playerCoords - entryPos)

                if dist < 2.0 then
                    nearTeleporter = true
                    isInShellZone = true
                    currentShellZone = tp

                    if Config.Editor.teleporterMarker then
                        DrawMarker(Config.Editor.markerType, entryPos.x, entryPos.y, entryPos.z - 1.0, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, Config.Editor.markerColor.r, Config.Editor.markerColor.g, Config.Editor.markerColor.b, Config.Editor.markerColor.a, false, true, 2, nil, nil, false)
                    end

                    DrawText3D(entryPos.x, entryPos.y, entryPos.z + 0.5, '[E] Enter Shell - ' .. (tp.label or 'Shell'))

                    if IsControlJustPressed(0, 38) then
                        TeleportToShell(tp)
                    end

                    if HasPermission() then
                        DrawText3D(entryPos.x, entryPos.y, entryPos.z + 0.2, '[G] Edit Shell')
                        if IsControlJustPressed(0, 47) then
                            OpenEditorForShell(tp.shellId)
                        end
                    end
                end
            end
        end

        if not nearTeleporter then
            local exiting = false
            for slotId, shellInfo in pairs(loadedShells) do
                local dist = #(playerCoords - shellInfo.coords)
                if dist < 3.0 then
                    DrawText3D(shellInfo.coords.x, shellInfo.coords.y, shellInfo.coords.z + 0.5, '[E] Exit Shell')
                    if IsControlJustPressed(0, 38) then
                        TriggerServerEvent('shellCreator:server:exitShell')
                    end
                    isInShellZone = true
                    exiting = true
                end
            end
            if not exiting then
                isInShellZone = false
                currentShellZone = nil
            end
        end

        ::continue::
    end
end)

function TeleportToShell(teleporter)
    local slot = GetSlotById(teleporter.slotId)
    if not slot then
        QBCore.Functions.Notify('Shell slot ni najden!', 'error')
        return
    end

    local playerPed = PlayerPedId()
    DoScreenFadeOut(1000)
    Wait(1200)

    SetEntityCoords(playerPed, slot.coords.x, slot.coords.y, slot.coords.z + 1.0, false, false, false, false)
    SetEntityHeading(playerPed, slot.heading)

    if not loadedShells[teleporter.slotId] then
        TriggerServerEvent('shellCreator:server:loadShell', teleporter.shellId or teleporter.id)
    end

    Wait(500)
    DoScreenFadeIn(1000)
    QBCore.Functions.Notify('Entered: ' .. (teleporter.label or 'Shell'), 'success')
end

RegisterNetEvent('shellCreator:client:exitShell', function(exitCoords)
    local playerPed = PlayerPedId()
    DoScreenFadeOut(1000)
    Wait(1200)
    SetEntityCoords(playerPed, exitCoords.x, exitCoords.y, exitCoords.z, false, false, false, false)
    Wait(500)
    DoScreenFadeIn(1000)
end)

RegisterNetEvent('shellCreator:client:teleportToShell', function(shellData)
    if shellData then
        TeleportToShell({ id = shellData.id, slotId = shellData.slotId, label = shellData.label, shellId = shellData.id })
    end
end)

-- RECEIVE DATA
RegisterNetEvent('shellCreator:client:receiveShells', function(shellsData)
    if shellsData then
        for _, shellData in ipairs(shellsData) do
            LoadShell(shellData)
        end
    end
end)

RegisterNetEvent('shellCreator:client:loadShell', function(shellData)
    if shellData then LoadShell(shellData) end
end)

RegisterNetEvent('shellCreator:client:unloadShell', function(slotId)
    if slotId then UnloadShell(slotId) end
end)

-- UTILS
function GetSlotById(slotId)
    for _, slot in ipairs(Config.ShellSlots) do
        if slot.id == slotId then return slot end
    end
    return nil
end

function GetWorldOffset(baseCoords, baseHeading, offsetX, offsetY, offsetZ)
    local headingRad = math.rad(baseHeading)
    local cos_h = math.cos(headingRad)
    local sin_h = math.sin(headingRad)
    return vector3(
        baseCoords.x + (offsetX * cos_h - offsetY * sin_h),
        baseCoords.y + (offsetX * sin_h + offsetY * cos_h),
        baseCoords.z + (offsetZ or 0)
    )
end

function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(1)
    AddTextComponentString(text)
    DrawText(_x, _y)
end

function GetCurrentShellData()
    return currentShellData
end

exports('GetCurrentShellData', GetCurrentShellData)
exports('IsEditing', function() return isEditing end)
