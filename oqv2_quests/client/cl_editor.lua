--[[ OQV2 QUESTS — In-game editor helpers: coord picker & model preview
     Made with CodeX Dev. ]]

local picking   = false
local previewed = nil

-------------------------------------------------------------------------------
-- COORD PICKER
-- The panel hides, the admin walks to the spot, ENTER confirms / BACKSPACE cancels.
-------------------------------------------------------------------------------
function OQ.Client.runCoordPicker()
    if picking then return nil end
    picking = true

    lib.showTextUI(
        '**' .. Config.UI.brand .. ' — pick a position**  \n' ..
        '[ENTER] confirm   [BACKSPACE] cancel   \n' ..
        'Walk to the exact spot and face the right way.',
        { position = 'left-center', icon = 'location-crosshairs' }
    )

    local result = nil
    while picking do
        Wait(0)

        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)

        DrawMarker(1, c.x, c.y, c.z - 0.98, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 0.5,
            224, 27, 132, 140, false, false, 2, false, nil, nil, false)

        if IsControlJustReleased(0, 191) or IsControlJustReleased(0, 201) then  -- ENTER
            result = {
                x = OQ.round(c.x, 2),
                y = OQ.round(c.y, 2),
                z = OQ.round(c.z, 2),
                w = OQ.round(GetEntityHeading(ped), 2),
            }
            picking = false
        elseif IsControlJustReleased(0, 194) or IsControlJustReleased(0, 202) then -- BACKSPACE / ESC
            result = { cancelled = true }
            picking = false
        end
    end

    lib.hideTextUI()
    return result
end

-------------------------------------------------------------------------------
-- MODEL PREVIEW
-- Spawns the requested ped/object in front of the admin for a few seconds.
-------------------------------------------------------------------------------
local function clearPreview()
    if previewed and DoesEntityExist(previewed) then
        SetEntityAsMissionEntity(previewed, true, true)
        DeleteEntity(previewed)
    end
    previewed = nil
end

function OQ.Client.previewModel(model, kind)
    if not model or model == '' then return false end
    clearPreview()

    local hash = OQ.Client.loadModel(model)
    if not hash then
        OQ.Client.notify(Config.UI.brand, ('Invalid model: %s'):format(model), 'error')
        return false
    end

    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.2, 0.0)
    local heading = GetEntityHeading(ped) + 180.0

    if kind == 'object' then
        previewed = CreateObject(hash, coords.x, coords.y, coords.z - 1.0, false, false, false)
        if DoesEntityExist(previewed) then
            PlaceObjectOnGroundProperly(previewed)
            FreezeEntityPosition(previewed, true)
        end
    else
        previewed = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, heading, false, false)
        if DoesEntityExist(previewed) then
            FreezeEntityPosition(previewed, true)
            SetEntityInvincible(previewed, true)
            SetBlockingOfNonTemporaryEvents(previewed, true)
            TaskStartScenarioInPlace(previewed, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
        end
    end
    SetModelAsNoLongerNeeded(hash)

    if not previewed or not DoesEntityExist(previewed) then
        OQ.Client.notify(Config.UI.brand, 'Could not spawn the preview.', 'error')
        return false
    end

    lib.showTextUI('**Preview:** ' .. model .. '  \n[ENTER] keep looking · closes automatically',
        { position = 'left-center', icon = 'eye' })

    local timeout = GetGameTimer() + 8000
    while GetGameTimer() < timeout do
        Wait(0)
        if IsControlJustReleased(0, 194) or IsControlJustReleased(0, 202) then break end
    end

    lib.hideTextUI()
    clearPreview()
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= OQ.resource then return end
    clearPreview()
    lib.hideTextUI()
end)
