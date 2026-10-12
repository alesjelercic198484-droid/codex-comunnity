local QBCore = exports['qb-core']:GetCoreObject()

-- Editor state (global - shared with ui.lua)
editorActive = false
editorMode = 'idle'
selectedProp = nil
selectedPropIndex = nil
ghostProp = nil
ghostModel = nil
currentFloor = 1
editorSpeed = Config.Editor.moveSpeed
editorRotateSpeed = Config.Editor.rotateSpeed
useGridSnap = Config.Editor.useGridSnap

-- Shell being edited (global - shared with ui.lua)
editingShell = nil
editingShellData = nil
editingSlotId = nil

-- OPEN EDITOR
function OpenEditorForShell(shellId)
    if editorActive then
        QBCore.Functions.Notify('Že v editor modu!', 'error')
        return
    end
    if not HasPermission() then
        QBCore.Functions.Notify('Nimaš dovoljenja!', 'error')
        return
    end
    TriggerServerEvent('shellCreator:server:openEditor', shellId)
end

RegisterNetEvent('shellCreator:client:startEditing', function(shellData)
    if not shellData then
        QBCore.Functions.Notify('Napaka pri nalaganju shell-a!', 'error')
        return
    end

    editingShellData = shellData
    editingSlotId = shellData.slotId
    editorActive = true
    editorMode = 'idle'
    selectedProp = nil
    selectedPropIndex = nil
    currentFloor = 1
    isEditing = true

    local slot = GetSlotById(shellData.slotId)
    if slot then
        local playerPed = PlayerPedId()
        DoScreenFadeOut(500)
        Wait(600)
        SetEntityCoords(playerPed, slot.coords.x, slot.coords.y, slot.coords.z + 1.0)
        SetEntityHeading(playerPed, slot.heading)
        Wait(300)
        DoScreenFadeIn(500)
    end

    if slot and not loadedShells[shellData.slotId] then
        LoadShell(shellData)
    end

    SetEntityVisible(PlayerPedId(), false, false)
    QBCore.Functions.Notify('Shell Editor odprt! Pritisni F6 za menu.', 'success')
end)

-- EDITOR LOOP
CreateThread(function()
    while true do
        Wait(0)
        if not editorActive then
            Wait(500)
            goto continue_editor
        end
        DrawEditorHUD()
        HandleEditorInput()
        ::continue_editor::
    end
end)

-- HUD
function DrawEditorHUD()
    DrawRect(0.5, 0.02, 1.0, 0.04, 0, 0, 0, 180)
    DrawCenteredText('SHELL EDITOR', 0.5, 0.01, 0.5, {255, 255, 255})

    local modeText = 'Mode: ' .. string.upper(editorMode)
    if selectedPropIndex then
        modeText = modeText .. ' | Prop: #' .. selectedPropIndex
    end
    modeText = modeText .. ' | Floor: ' .. currentFloor

    DrawRect(0.5, 0.06, 0.6, 0.025, 0, 0, 0, 150)
    DrawCenteredText(modeText, 0.5, 0.052, 0.35, {200, 200, 200})

    -- Controls
    local helpY = 0.85
    local helpLines = {
        'CONTROLS:',
        '[Arrows] Move Prop',
        '[PgUp/PgDn] Up/Down',
        '[Shift] Fast Move',
        '[Q/E] Rotate',
        '[G] Grid Snap: ' .. (useGridSnap and 'ON' or 'OFF'),
        '[Enter] Place/Select',
        '[X] Cancel/Deselect',
        '[Del] Delete Prop',
        '[Ins] Duplicate',
        '[F5] Save | [F6] Menu',
        '[Backspace] Exit',
    }

    for i, line in ipairs(helpLines) do
        DrawRect(0.1, helpY + (i * 0.018), 0.2, 0.018, 0, 0, 0, 150)
        DrawLeftText(line, 0.01, helpY + (i * 0.018) - 0.003, 0.3, {200, 200, 200})
    end

    -- Ghost prop highlight
    if editorMode == 'placing' and ghostProp and ghostProp ~= 0 and DoesEntityExist(ghostProp) then
        local gc = GetEntityCoords(ghostProp)
        DrawMarker(2, gc.x, gc.y, gc.z, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, 0, 255, 0, 100, false, true, 2, nil, nil, false)
    end

    -- Selected prop highlight
    if selectedPropIndex and editingShellData and editingShellData.props and editingShellData.props[selectedPropIndex] then
        local propData = editingShellData.props[selectedPropIndex]
        local slot = GetSlotById(editingSlotId)
        if slot then
            local worldPos = GetWorldOffset(slot.coords, slot.heading, propData.x, propData.y, propData.z)
            DrawMarker(2, worldPos.x, worldPos.y, worldPos.z, 0, 0, 0, 0, 0, 0, 0.3, 0.3, 0.3, 255, 100, 0, 100, false, true, 2, nil, nil, false)
        end
    end
end

function DrawCenteredText(text, x, y, scale, color)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], 255)
    SetTextCentre(true)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

function DrawLeftText(text, x, y, scale, color)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], 255)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

-- INPUT
function HandleEditorInput()
    DisableAllControlActions(0)
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 24, true)
    EnableControlAction(0, 25, true)
    EnableControlAction(0, 30, true)
    EnableControlAction(0, 31, true)
    EnableControlAction(0, 32, true)
    EnableControlAction(0, 33, true)
    EnableControlAction(0, 34, true)
    EnableControlAction(0, 35, true)

    local speed = editorSpeed
    local rotSpeed = editorRotateSpeed

    if IsControlPressed(0, 21) then
        speed = Config.Editor.moveSpeedFast
        rotSpeed = Config.Editor.rotateSpeedFast
    end

    if editorMode == 'placing' or editorMode == 'moving' then
        local moveX = 0.0
        local moveY = 0.0
        local moveZ = 0.0
        local rotZ = 0.0

        if IsControlPressed(0, 172) then moveY = speed end
        if IsControlPressed(0, 173) then moveY = -speed end
        if IsControlPressed(0, 174) then moveX = -speed end
        if IsControlPressed(0, 175) then moveX = speed end
        if IsControlPressed(0, 10) then moveZ = speed end
        if IsControlPressed(0, 11) then moveZ = -speed end
        if IsControlPressed(0, 44) then rotZ = rotSpeed end
        if IsControlPressed(0, 38) and editorMode ~= 'placing' then rotZ = -rotSpeed end

        if moveX ~= 0 or moveY ~= 0 or moveZ ~= 0 or rotZ ~= 0 then
            if editorMode == 'placing' and ghostProp and ghostProp ~= 0 then
                MoveGhostProp(moveX, moveY, moveZ, rotZ)
            elseif editorMode == 'moving' and selectedPropIndex then
                MoveSelectedProp(moveX, moveY, moveZ, rotZ)
            end
        end
    end

    -- Grid snap toggle
    if IsControlJustPressed(0, 47) then
        useGridSnap = not useGridSnap
        QBCore.Functions.Notify('Grid Snap: ' .. (useGridSnap and 'ON' or 'OFF'), useGridSnap and 'success' or 'error')
    end

    -- Confirm
    if IsControlJustPressed(0, 38) then
        if editorMode == 'placing' then
            PlaceGhostProp()
        elseif editorMode == 'moving' then
            FinishMovingProp()
        elseif editorMode == 'idle' then
            TrySelectProp()
        end
    end

    -- Cancel
    if IsControlJustPressed(0, 73) then
        if editorMode == 'placing' then
            CancelPlacing()
        elseif editorMode == 'moving' then
            CancelMoving()
        else
            selectedProp = nil
            selectedPropIndex = nil
            QBCore.Functions.Notify('Odznačeno', 'primary')
        end
    end

    -- Delete
    if IsControlJustPressed(0, 245) then
        if selectedPropIndex then DeleteSelectedProp() end
    end

    -- Duplicate
    if IsControlJustPressed(0, 121) then
        if selectedPropIndex then DuplicateSelectedProp() end
    end

    -- Save
    if IsControlJustPressed(0, 166) then
        SaveCurrentShell()
    end

    -- Exit
    if IsControlJustPressed(0, 177) then
        ExitEditMode()
    end

    -- Menu
    if IsControlJustPressed(0, 167) then
        OpenShellCreatorMenu()
    end
end

-- PLACING
function StartPlacingProp(modelName)
    if not editingShellData then return end

    if editingShellData.props and #editingShellData.props >= Config.Editor.maxPropsPerShell then
        QBCore.Functions.Notify('Max propov dosežen! (' .. Config.Editor.maxPropsPerShell .. ')', 'error')
        return
    end

    local model = GetHashKey(modelName)
    if not IsModelValid(model) and not IsModelInCdimage(model) then
        QBCore.Functions.Notify('Neveljaven model: ' .. modelName, 'error')
        return
    end

    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if not HasModelLoaded(model) then
        QBCore.Functions.Notify('Model se ni naložil!', 'error')
        return
    end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local playerHeading = GetEntityHeading(playerPed)
    local forward = GetEntityForwardVector(playerPed)
    local ghostCoords = playerCoords + forward * 3.0

    ghostProp = CreateObjectNoOffset(model, ghostCoords.x, ghostCoords.y, ghostCoords.z, true, false, false)
    if ghostProp ~= 0 then
        SetEntityHeading(ghostProp, playerHeading)
        SetEntityCollision(ghostProp, false, false)
        SetEntityAlpha(ghostProp, 150, false)
    end

    ghostModel = modelName
    editorMode = 'placing'
    QBCore.Functions.Notify('Postavljam: ' .. modelName .. ' | [E] Postavi | [X] Prekliči', 'success')
end

function MoveGhostProp(moveX, moveY, moveZ, rotZ)
    if not ghostProp or ghostProp == 0 then return end

    local coords = GetEntityCoords(ghostProp)
    local heading = GetEntityHeading(ghostProp)
    local camRot = GetGameplayCamRot(2)
    local camYaw = math.rad(camRot.z)

    local newX = coords.x + (moveX * math.cos(camYaw) - moveY * math.sin(camYaw))
    local newY = coords.y + (moveX * math.sin(camYaw) + moveY * math.cos(camYaw))
    local newZ = coords.z + moveZ

    if useGridSnap then
        local gridSize = Config.Editor.gridSize
        newX = math.floor(newX / gridSize + 0.5) * gridSize
        newY = math.floor(newY / gridSize + 0.5) * gridSize
        newZ = math.floor(newZ / gridSize + 0.5) * gridSize
    end

    SetEntityCoords(ghostProp, newX, newY, newZ, false, false, false, false)
    if rotZ ~= 0 then
        SetEntityHeading(ghostProp, heading + rotZ)
    end
end

function PlaceGhostProp()
    if not ghostProp or ghostProp == 0 then return end
    if not editingShellData then return end

    local slot = GetSlotById(editingSlotId)
    if not slot then CancelPlacing() return end

    local ghostCoords = GetEntityCoords(ghostProp)
    local ghostHeading = GetEntityHeading(ghostProp)
    local localX, localY, localZ = WorldToLocal(ghostCoords, slot.coords, slot.heading)

    local propData = {
        model = ghostModel,
        x = localX,
        y = localY,
        z = localZ,
        heading = ghostHeading - slot.heading,
        floor = currentFloor,
    }

    if not editingShellData.props then editingShellData.props = {} end
    table.insert(editingShellData.props, propData)

    CreateShellProp(slot.coords, slot.heading, propData)

    DeleteEntity(ghostProp)
    ghostProp = nil
    ghostModel = nil
    editorMode = 'idle'
    QBCore.Functions.Notify('Prop postavljen! Skupaj: ' .. #editingShellData.props, 'success')
end

function CancelPlacing()
    if ghostProp and ghostProp ~= 0 then DeleteEntity(ghostProp) end
    ghostProp = nil
    ghostModel = nil
    editorMode = 'idle'
    QBCore.Functions.Notify('Preklicano', 'primary')
end

-- MOVING
function TrySelectProp()
    if not editingShellData or not editingShellData.props then return end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local slot = GetSlotById(editingSlotId)
    if not slot then return end

    local closestDist = 3.0
    local closestIndex = nil

    for i, propData in ipairs(editingShellData.props) do
        if (propData.floor or 1) == currentFloor then
            local worldPos = GetWorldOffset(slot.coords, slot.heading, propData.x, propData.y, propData.z)
            local dist = #(playerCoords - worldPos)
            if dist < closestDist then
                closestDist = dist
                closestIndex = i
            end
        end
    end

    if closestIndex then
        selectedPropIndex = closestIndex
        selectedProp = editingShellData.props[closestIndex]
        editorMode = 'moving'
        QBCore.Functions.Notify('Prop #' .. closestIndex .. ' izbran | [E] Potrdi | [X] Prekliči', 'success')
    else
        QBCore.Functions.Notify('Ni prop-a v bližini', 'error')
    end
end

function MoveSelectedProp(moveX, moveY, moveZ, rotZ)
    if not selectedPropIndex or not selectedProp then return end

    local slot = GetSlotById(editingSlotId)
    if not slot then return end

    local camRot = GetGameplayCamRot(2)
    local camYaw = math.rad(camRot.z)
    local headingRad = math.rad(slot.heading)

    local dx = moveX * math.cos(camYaw - headingRad) - moveY * math.sin(camYaw - headingRad)
    local dy = moveX * math.sin(camYaw - headingRad) + moveY * math.cos(camYaw - headingRad)

    selectedProp.x = (selectedProp.x or 0) + dx
    selectedProp.y = (selectedProp.y or 0) + dy
    selectedProp.z = (selectedProp.z or 0) + moveZ

    if rotZ ~= 0 then
        selectedProp.heading = (selectedProp.heading or 0) + rotZ
    end

    if useGridSnap then
        local gridSize = Config.Editor.gridSize
        selectedProp.x = math.floor(selectedProp.x / gridSize + 0.5) * gridSize
        selectedProp.y = math.floor(selectedProp.y / gridSize + 0.5) * gridSize
        selectedProp.z = math.floor(selectedProp.z / gridSize + 0.5) * gridSize
    end

    UpdatePropEntity(selectedPropIndex, selectedProp)
end

function FinishMovingProp()
    selectedProp = nil
    selectedPropIndex = nil
    editorMode = 'idle'
    QBCore.Functions.Notify('Pozicija shranjena', 'success')
end

function CancelMoving()
    selectedProp = nil
    selectedPropIndex = nil
    editorMode = 'idle'
    QBCore.Functions.Notify('Premik preklican', 'primary')
end

function UpdatePropEntity(propIndex, propData)
    if not editingSlotId then return end
    local slot = GetSlotById(editingSlotId)
    if not slot then return end

    if propData._entity and DoesEntityExist(propData._entity) then
        DeleteEntity(propData._entity)
    end
    CreateShellProp(slot.coords, slot.heading, propData)
end

-- DELETE / DUPLICATE
function DeleteSelectedProp()
    if not selectedPropIndex or not editingShellData then return end

    local propData = editingShellData.props[selectedPropIndex]
    if propData then
        if propData._entity and DoesEntityExist(propData._entity) then
            DeleteEntity(propData._entity)
        end
        table.remove(editingShellData.props, selectedPropIndex)
    end

    selectedProp = nil
    selectedPropIndex = nil
    editorMode = 'idle'
    QBCore.Functions.Notify('Prop izbrisan! Preostanek: ' .. #(editingShellData.props or {}), 'success')
end

function DuplicateSelectedProp()
    if not selectedPropIndex or not editingShellData then return end

    local original = editingShellData.props[selectedPropIndex]
    if not original then return end

    if #editingShellData.props >= Config.Editor.maxPropsPerShell then
        QBCore.Functions.Notify('Max propov dosežen!', 'error')
        return
    end

    local newProp = {
        model = original.model,
        x = (original.x or 0) + 0.5,
        y = (original.y or 0) + 0.5,
        z = original.z or 0,
        heading = original.heading or 0,
        floor = original.floor or currentFloor,
    }

    table.insert(editingShellData.props, newProp)

    local slot = GetSlotById(editingSlotId)
    if slot then CreateShellProp(slot.coords, slot.heading, newProp) end

    selectedPropIndex = #editingShellData.props
    selectedProp = newProp
    QBCore.Functions.Notify('Prop podvojen!', 'success')
end

-- SAVE / EXIT
function SaveCurrentShell()
    if not editingShellData then return end

    local saveData = {
        id = editingShellData.id,
        slotId = editingSlotId,
        label = editingShellData.label or 'Untitled Shell',
        template = editingShellData.template,
        props = CleanPropsData(editingShellData.props),
        floors = editingShellData.floors or {},
        colors = editingShellData.colors or {},
        walls = editingShellData.walls or {},
    }

    TriggerServerEvent('shellCreator:server:saveShell', saveData)
    QBCore.Functions.Notify('Shell shranjen!', 'success')
end

function CleanPropsData(props)
    if not props then return {} end
    local clean = {}
    for _, prop in ipairs(props) do
        table.insert(clean, {
            model = prop.model, x = prop.x, y = prop.y, z = prop.z,
            heading = prop.heading, floor = prop.floor,
        })
    end
    return clean
end

function ExitEditMode()
    if not editorActive then return end

    if ghostProp and ghostProp ~= 0 then DeleteEntity(ghostProp) end
    ghostProp = nil
    ghostModel = nil

    SetEntityVisible(PlayerPedId(), true, false)

    editorActive = false
    editorMode = 'idle'
    selectedProp = nil
    selectedPropIndex = nil
    editingShellData = nil
    editingSlotId = nil
    isEditing = false

    QBCore.Functions.Notify('Zaprl si editor', 'primary')
end

RegisterNetEvent('shellCreator:client:saveComplete', function(success, message)
    QBCore.Functions.Notify(message or (success and 'Shell shranjen!' or 'Napaka pri shranjevanju!'), success and 'success' or 'error')
end)

function WorldToLocal(worldPos, baseCoords, baseHeading)
    local dx = worldPos.x - baseCoords.x
    local dy = worldPos.y - baseCoords.y
    local dz = worldPos.z - baseCoords.z
    local headingRad = math.rad(-baseHeading)
    local cos_h = math.cos(headingRad)
    local sin_h = math.sin(headingRad)
    return dx * cos_h - dy * sin_h, dx * sin_h + dy * cos_h, dz
end

exports('OpenEditorForShell', OpenEditorForShell)
exports('StartPlacingProp', StartPlacingProp)
exports('ExitEditMode', ExitEditMode)
