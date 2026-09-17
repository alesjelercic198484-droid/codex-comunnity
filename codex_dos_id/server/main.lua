local RESOURCE = GetCurrentResourceName()

ESX = nil

local function TryGetESX()
    if ESX then
        return ESX
    end

    if Config.ESX and Config.ESX.UseExport ~= false then
        local exportName = Config.ESX.ExportName or 'es_extended'
        local ok, object = pcall(function()
            return exports[exportName]:getSharedObject()
        end)

        if ok and object then
            ESX = object
            return ESX
        end
    end

    TriggerEvent((Config.ESX and Config.ESX.SharedObjectEvent) or 'esx:getSharedObject', function(object)
        ESX = object
    end)

    return ESX
end

local function Debug(...)
    if Config.Debug then
        print(('[%s]'):format(RESOURCE), ...)
    end
end

local function Notify(source, message)
    if not source or not message or message == '' then
        return
    end

    local xPlayer = ESX and ESX.GetPlayerFromId(source)
    if xPlayer and xPlayer.showNotification then
        xPlayer.showNotification(message)
        return
    end

    TriggerClientEvent(RESOURCE .. ':notify', source, message)
end

local function IsJobAllowed(jobName)
    if not jobName then
        return false
    end

    if jobName == Config.Job then
        return true
    end

    for _, allowed in ipairs(Config.AllowedJobs or {}) do
        if allowed == jobName then
            return true
        end
    end

    return false
end

-- Builds the public card payload shown in the NUI for a given xPlayer.
local function BuildCardData(xPlayer)
    if not xPlayer then
        return nil
    end

    local firstName, lastName = 'Unknown', 'Unknown'

    if xPlayer.get and xPlayer.get('firstName') then
        firstName = xPlayer.get('firstName')
        lastName = xPlayer.get('lastName')
    elseif xPlayer.variables and xPlayer.variables.firstName then
        firstName = xPlayer.variables.firstName
        lastName = xPlayer.variables.lastName
    else
        local ok, result = pcall(function()
            return xPlayer.getName and xPlayer.getName()
        end)
        if ok and result then
            local parts = {}
            for word in result:gmatch('%S+') do
                parts[#parts + 1] = word
            end
            firstName = parts[1] or firstName
            lastName = parts[2] or lastName
        end
    end

    local job = xPlayer.job or {}
    local jobLabel = job.label or (Config.Card and Config.Card.FallbackJobLabel) or 'Federal Agent'
    local gradeLabel = (job.grade_label or job.grade_name or '')

    return {
        firstName = firstName or 'Unknown',
        lastName = lastName or 'Unknown',
        job = jobLabel,
        grade = gradeLabel,
        agency = Config.Card and Config.Card.Agency or 'DEPARTMENT OF DEFENSE',
        division = Config.Card and Config.Card.Division or 'SECRET SERVICES',
        footer = Config.Card and Config.Card.Footer or '',
        identifier = xPlayer.identifier
    }
end

local function ShowOwnCard(source)
    local xPlayer = ESX.GetPlayerFromId(source)

    if not xPlayer then
        Notify(source, Config.Notifications and Config.Notifications.NotReady)
        return
    end

    if not IsJobAllowed(xPlayer.job and xPlayer.job.name) then
        Notify(source, Config.Notifications and Config.Notifications.NoPermission)
        return
    end

    local card = BuildCardData(xPlayer)
    if not card then
        Notify(source, Config.Notifications and Config.Notifications.NotReady)
        return
    end

    TriggerClientEvent(RESOURCE .. ':openCard', source, card)

    -- Present the card to any nearby officers automatically, exactly like
    -- physically handing over an ID card.
    local ownerPed = GetPlayerPed(source)
    if not ownerPed or ownerPed == 0 then
        return
    end

    local ok, ownerCoords = pcall(GetEntityCoords, ownerPed)
    if not ok or not ownerCoords then
        return
    end

    local radius = tonumber(Config.Presentation and Config.Presentation.Radius) or 4.0
    local viewerJobs = (Config.Presentation and Config.Presentation.ViewerJobs) or {}
    local shownTo = {}

    for _, playerId in ipairs(GetPlayers()) do
        local targetId = tonumber(playerId)

        if targetId and targetId ~= source then
            local xTarget = ESX.GetPlayerFromId(targetId)

            if xTarget and xTarget.job then
                local isViewer = false
                for _, viewerJob in ipairs(viewerJobs) do
                    if xTarget.job.name == viewerJob then
                        isViewer = true
                        break
                    end
                end

                if isViewer then
                    local targetPed = GetPlayerPed(targetId)
                    if targetPed and targetPed ~= 0 then
                        local okT, targetCoords = pcall(GetEntityCoords, targetPed)
                        if okT and targetCoords then
                            local distance = #(ownerCoords - targetCoords)
                            if distance <= radius then
                                TriggerClientEvent(RESOURCE .. ':presentCard', targetId, card, tostring(Config.Presentation.AutoCloseMs or 12000))
                                shownTo[#shownTo + 1] = targetId
                            end
                        end
                    end
                end
            end
        end
    end

    if #shownTo > 0 then
        Notify(source, Config.Notifications and Config.Notifications.Shown)
        for _, targetId in ipairs(shownTo) do
            local ownerName = ('%s %s'):format(card.firstName, card.lastName)
            local template = (Config.Notifications and Config.Notifications.Received) or '%s presented their ID card to you.'
            Notify(targetId, template:format(ownerName))
        end
    end

    Debug(('%s used the DoS ID card, shown to %d nearby officer(s).'):format(source, #shownTo))
end

CreateThread(function()
    while not TryGetESX() do
        Wait(500)
    end

    ESX.RegisterUsableItem(Config.Item, function(source)
        ShowOwnCard(source)
    end)

    -- ox_inventory compatibility: it also fires this exact event name for
    -- usable items registered through ESX.RegisterUsableItem, but if your
    -- server relies purely on ox_inventory's own useItem export, this second
    -- registration keeps things working either way.
    if GetResourceState('ox_inventory') == 'started' then
        local ok = pcall(function()
            exports.ox_inventory:RegisterUsableItem(Config.Item, function(sourcePlayer)
                ShowOwnCard(sourcePlayer)
            end)
        end)

        if not ok then
            Debug('Could not register ox_inventory usable item hook, falling back to ESX.RegisterUsableItem only.')
        end
    end

    Debug('Started, item = ' .. tostring(Config.Item))
end)

if Config.Command then
    RegisterCommand(Config.Command, function(source)
        if source == 0 then
            return
        end
        ShowOwnCard(source)
    end, false)
end
