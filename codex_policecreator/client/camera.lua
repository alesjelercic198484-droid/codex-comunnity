--[[
    client/camera.lua - security camera feed rendered from the office PC.
]]

local RESOURCE = GetCurrentResourceName()
local cam = nil
local yaw = 0.0
local pitch = -10.0
local active = false

local function destroy()
    if cam and DoesCamExist(cam) then
        SetCamActive(cam, false)
        DestroyCam(cam, true)
    end
    cam = nil
    active = false
    RenderScriptCams(false, false, 0, true, false)
    ClearTimecycleModifier()
    SetNuiFocus(false, false)
end

local function create(camera)
    destroy()

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        camera.x, camera.y, camera.z, -10.0, 0.0, camera.heading or 0.0,
        tonumber(Config.Cameras.Fov) or 70.0, true, 2)

    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    SetTimecycleModifier('scanline_cam_cheap')
    SetTimecycleModifierStrength(0.6)

    yaw = tonumber(camera.heading) or 0.0
    pitch = -10.0
    active = true
end

RegisterNetEvent(RESOURCE .. ':client:viewCamera', function(camera)
    if not camera then return end
    create(camera)

    CreateThread(function()
        while active do
            Wait(0)

            local dx = GetDisabledControlNormal(1, 1) * (tonumber(Config.Cameras.FreeLookSpeed) or 3.0)
            local dy = GetDisabledControlNormal(1, 2) * (tonumber(Config.Cameras.FreeLookSpeed) or 3.0)

            yaw = yaw - dx
            pitch = math.max(-80.0, math.min(60.0, pitch - dy))

            SetCamRot(cam, pitch, 0.0, yaw, 2)

            if IsDisabledControlJustPressed(1, 202) or IsControlJustReleased(0, 200) then
                destroy()
                TriggerEvent(RESOURCE .. ':client:notify', 'Camera feed closed', 'primary')
            end

            DisableControlAction(1, 1, true)
            DisableControlAction(1, 2, true)
            DisableControlAction(1, 202, true)
            DisableControlAction(0, 200, true)

            SetTextFont(4)
            SetTextScale(0.0, 0.4)
            SetTextColour(255, 80, 80, 215)
            SetTextOutline()
            SetTextEntry('STRING')
            AddTextComponentString(('CAM %s  |  ESC to exit'):format(tostring(camera.label)))
            DrawText(0.02, 0.02)
        end
    end)
end)

--- Optional night vision toggle while a feed is open.
CreateThread(function()
    while true do
        Wait(500)
        if active and Config.Cameras.NightVision and IsControlJustReleased(0, 246) then
            SetNightvision(not GetNightvisionState())
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE and active then destroy() end
end)
