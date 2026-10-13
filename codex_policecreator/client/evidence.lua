--[[
    client/evidence.lua - collecting evidence at a crime scene.
]]

local RESOURCE = GetCurrentResourceName()

RegisterNetEvent(RESOURCE .. ':client:useEvidenceBag', function()
    if State.menuOpen then return end
    if not State.member then
        TriggerEvent(RESOURCE .. ':client:notify', 'You are not part of a department', 'error')
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    State.OpenMenu('evidence', {
        x = coords.x, y = coords.y, z = coords.z,
        grades = Config.Evidence.Grades,
        officer = ('%s %s'):format(tostring(State.member.firstName), tostring(State.member.lastName))
    })
end)

--- Optional: hold a flashlight while collecting evidence in the dark.
local function holdFlashlight(duration)
    local ped = PlayerPedId()
    local model = joaat(Config.Evidence.FlashlightModel)

    RequestModel(model)
    local waited = 0
    while not HasModelLoaded(model) and waited < 100 do
        Wait(10)
        waited = waited + 1
    end

    if not HasModelLoaded(model) then return end

    local object = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, 57005), 0.09, 0.0, -0.02, -70.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)

    SetTimeout(duration or 8000, function()
        if DoesEntityExist(object) then DeleteEntity(object) end
    end)
end

RegisterNetEvent(RESOURCE .. ':client:evidenceFlashlight', function()
    holdFlashlight(8000)
end)
