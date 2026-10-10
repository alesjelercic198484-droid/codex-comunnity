--[============================================================================[
    CodeX Roleplay Inventory - 3D ped preview

    Renders a live clone of the player ped inside the left column of the
    inventory ("showcase" layout).

    How it works
    ------------
    1. A local, NON networked clone of the player ped is created a couple of
       metres away. Because it is not networked nobody else can see it.
    2. A scripted camera frames the clone and `RenderScriptCams` is turned on.
    3. The NUI left column is a transparent window, so the live 3D ped shows
       through it while all the other panels are drawn on top.

    Everything is wrapped in pcall: if any native misbehaves the preview simply
    switches itself off and the inventory keeps working normally.
]============================================================================]

PedPreview = {}

local state = {
    enabled = true,     -- set to false permanently if something fails
    active = false,
    ped = 0,
    camera = -1,
    thread = false,
}

-- Camera framing. Positive `lookRight` shifts the ped to the LEFT on screen.
local FRAMING = {
    distance = 2.15,    -- metres between camera and ped
    height = 1.10,      -- camera height above the ped's feet
    lookHeight = 0.95,  -- point the camera at chest height
    lookRight = 0.62,   -- aim to the right of the ped -> ped sits left
    fov = 42.0
}

local function Fail(reason)
    state.enabled = false
    PedPreview.Stop()

    if Config and Config.Debug then
        print(('^1[qb-inventory]^7 Ped preview disabled: %s'):format(tostring(reason)))
    end
end

local function PlayerPed()
    return PlayerPedId()
end

local function RotateXY(x, y, heading)
    local radians = math.rad(heading)
    local cos = math.cos(radians)
    local sin = math.sin(radians)

    return (x * cos) - (y * sin), (x * sin) + (y * cos)
end

--- Creates the clone and points the camera at it.
local function Build()
    local ped = PlayerPed()

    if not ped or ped == 0 then
        Fail('no player ped')
        return false
    end

    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- Place the clone in front of the player so it is lit by the real world.
    local offsetX, offsetY = RotateXY(0.0, FRAMING.distance, heading)
    local pedX, pedY = coords.x + offsetX, coords.y + offsetY

    local found, groundZ = GetGroundZFor_3dCoord(pedX, pedY, coords.z + 2.0, false)
    local pedZ = (found and groundZ) or coords.z

    local clone = ClonePed(ped, heading, false, false)

    if not clone or clone == 0 then
        Fail('ClonePed failed')
        return false
    end

    SetEntityCoords(clone, pedX, pedY, pedZ, false, false, false, true)
    SetEntityHeading(clone, heading + 180.0)

    SetEntityInvincible(clone, true)
    SetEntityCollision(clone, false, false)
    SetEntityCanBeDamaged(clone, false)
    FreezeEntityPosition(clone, true)
    SetBlockingOfNonTemporaryEvents(clone, true)
    SetPedCanRagdoll(clone, false)
    SetPedCanBeTargetted(clone, false)
    ClearPedTasksImmediately(clone)
    SetEntityVisible(clone, true, false)

    -- Camera: sit in front of the clone, aimed slightly to its right.
    local camX = pedX - offsetX * 0.0
    local camY = pedY - offsetY * 0.0
    local camZ = pedZ + FRAMING.height

    local rightX, rightY = RotateXY(FRAMING.lookRight, 0.0, heading)

    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    if not camera or camera == -1 then
        DeleteEntity(clone)
        Fail('CreateCam failed')
        return false
    end

    -- Put the camera between the player and the clone.
    camX = coords.x + (pedX - coords.x) * 0.25
    camY = coords.y + (pedY - coords.y) * 0.25

    SetCamCoord(camera, camX, camY, camZ)
    PointCamAtCoord(camera, pedX + rightX, pedY + rightY, pedZ + FRAMING.lookHeight)
    SetCamFov(camera, FRAMING.fov)
    SetCamActive(camera, true)
    RenderScriptCams(true, true, 350, true, true)

    state.ped = clone
    state.camera = camera

    return true
end

--- Starts the preview. Safe to call while already running.
function PedPreview.Start()
    if not state.enabled then return false end
    if state.active then return true end

    if not (Config and Config.Defaults and Config.Defaults.PedPreview) then
        return false
    end

    local ok, built = pcall(Build)

    if not ok or not built then
        Fail(ok and 'build failed' or built)
        return false
    end

    state.active = true
    return true
end

--- Tears the preview down and restores the gameplay camera.
function PedPreview.Stop()
    if state.camera and state.camera ~= -1 then
        pcall(function()
            SetCamActive(state.camera, false)
            RenderScriptCams(false, true, 250, true, true)
            DestroyCam(state.camera, false)
        end)
        state.camera = -1
    end

    if state.ped and state.ped ~= 0 then
        pcall(function()
            DeleteEntity(state.ped)
        end)
        state.ped = 0
    end

    state.active = false
end

function PedPreview.IsActive()
    return state.active
end

function PedPreview.Available()
    return state.enabled
end

--- Called when the player changes clothes so the next open shows the new look.
function PedPreview.Refresh()
    if state.active then
        PedPreview.Stop()
        PedPreview.Start()
    end
end

--- Applies new framing values pushed from the NUI settings studio.
function PedPreview.SetFraming(values)
    if type(values) ~= 'table' then return end

    for key, value in pairs(values) do
        if FRAMING[key] ~= nil and type(value) == 'number' then
            FRAMING[key] = value
        end
    end

    if state.active then
        PedPreview.Stop()
        PedPreview.Start()
    end
end

-- Safety net: never leave a script camera running if the player dies or the
-- resource restarts.
CreateThread(function()
    while true do
        Wait(2000)

        if state.active then
            local ped = PlayerPed()

            if not ped or ped == 0 or IsEntityDead(ped) then
                PedPreview.Stop()
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    PedPreview.Stop()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PedPreview.Stop()
end)
