-- Entry point intentionally kept small; mission logic is split into focused client files.
CreateThread(function()
    while true do
        Wait(30000)
        if MissionClient.active and MissionClient.vehicle and DoesEntityExist(MissionClient.vehicle) then
            SetVehicleEngineCanDegrade(MissionClient.vehicle, true)
        end
    end
end)
