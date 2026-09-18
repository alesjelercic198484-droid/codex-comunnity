local RESOURCE = GetCurrentResourceName()
local ESX
local presentationCooldowns = {}
local cuffCooldowns = {}
local safetyCooldowns = {}

local function debugPrint(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

local function getESX()
    if ESX then return ESX end

    local ok, object = pcall(function()
        return exports.es_extended:getSharedObject()
    end)

    if ok and object then
        ESX = object
    end

    return ESX
end

local function getXPlayer(playerId)
    local framework = getESX()
    return framework and framework.GetPlayerFromId(tonumber(playerId)) or nil
end

local function getJob(xPlayer)
    if not xPlayer then return nil end

    if xPlayer.getJob then
        local ok, job = pcall(xPlayer.getJob)
        if ok and job then return job end
    end

    return xPlayer.job
end

local function isGovernmentPlayer(playerId)
    local job = getJob(getXPlayer(playerId))
    return job and job.name == Config.JobName or false
end

local function notify(playerId, description, notificationType)
    if not playerId or not description then return end

    TriggerClientEvent(RESOURCE .. ':client:notify', playerId, description, notificationType or 'inform')
end

local function getPlayerCoords(playerId)
    local ped = GetPlayerPed(playerId)
    if not ped or ped <= 0 then return nil, nil end

    local coords = GetEntityCoords(ped)
    if not coords then return nil, nil end

    return coords, ped
end

local function playersAreNear(firstId, secondId, maxDistance)
    local firstCoords = getPlayerCoords(firstId)
    local secondCoords = getPlayerCoords(secondId)
    if not firstCoords or not secondCoords then return false end

    return #(firstCoords - secondCoords) <= maxDistance
end

local function getIdentity(xPlayer)
    local firstName
    local lastName

    if xPlayer.get then
        local firstOk, firstValue = pcall(xPlayer.get, 'firstName')
        local lastOk, lastValue = pcall(xPlayer.get, 'lastName')
        if firstOk then firstName = firstValue end
        if lastOk then lastName = lastValue end
    end

    if (not firstName or firstName == '') and xPlayer.variables then
        firstName = xPlayer.variables.firstName
        lastName = xPlayer.variables.lastName
    end

    if not firstName or firstName == '' then
        local fullName
        if xPlayer.getName then
            local ok, value = pcall(xPlayer.getName)
            if ok then fullName = value end
        end

        fullName = fullName or GetPlayerName(xPlayer.source) or 'Unknown Official'
        firstName, lastName = fullName:match('^(%S+)%s+(.+)$')
        firstName = firstName or fullName
    end

    return tostring(firstName or 'Unknown'), tostring(lastName or '')
end

local function getIdentifier(xPlayer)
    if xPlayer.getIdentifier then
        local ok, identifier = pcall(xPlayer.getIdentifier)
        if ok and identifier then return tostring(identifier) end
    end

    return tostring(xPlayer.identifier or xPlayer.source or 'unknown')
end

local function credentialNumber(identifier)
    local hash = 17
    for i = 1, #identifier do
        hash = (hash * 37 + identifier:byte(i)) % 1000000
    end
    return ('GOV-%06d'):format(hash)
end

local function buildCard(playerId)
    local xPlayer = getXPlayer(playerId)
    if not xPlayer then return nil end

    local job = getJob(xPlayer)
    if not job or job.name ~= Config.JobName then return nil end

    local firstName, lastName = getIdentity(xPlayer)
    local grade = tonumber(job.grade) or 0
    local configuredRank = Config.Ranks[grade]
    local rankLabel = configuredRank and configuredRank.label
        or job.grade_label
        or job.grade_name
        or 'Government Official'

    return {
        firstName = firstName,
        lastName = lastName,
        fullName = (firstName .. ' ' .. lastName):gsub('%s+$', ''),
        rank = tostring(rankLabel),
        grade = grade,
        credential = credentialNumber(getIdentifier(xPlayer)),
        agency = Config.Identification.Agency,
        department = Config.Identification.Department,
        authority = Config.Identification.Authority,
        footer = Config.Identification.Footer
    }
end

local function hasGovernmentId(playerId)
    local ok, count = pcall(function()
        return exports.ox_inventory:Search(playerId, 'count', Config.Identification.Item)
    end)

    return ok and tonumber(count) and tonumber(count) > 0 or false
end

local function sendCardToViewer(ownerId, viewerId, card)
    TriggerClientEvent(
        RESOURCE .. ':client:receiveId',
        viewerId,
        card,
        tonumber(Config.Identification.AutoCloseMs) or 12000
    )

    local message = Config.Notifications.IdReceived:format(card.fullName)
    notify(viewerId, message, 'inform')
end

local function presentIdentification(ownerId, selectedViewer)
    if not isGovernmentPlayer(ownerId) then
        notify(ownerId, Config.Notifications.NotGovernment, 'error')
        return false
    end

    if not hasGovernmentId(ownerId) then
        notify(ownerId, Config.Notifications.MissingId, 'error')
        return false
    end

    local now = GetGameTimer()
    if presentationCooldowns[ownerId] and now < presentationCooldowns[ownerId] then
        return false
    end
    presentationCooldowns[ownerId] = now + 1000

    local card = buildCard(ownerId)
    if not card then return false end

    local radius = tonumber(Config.Identification.PresentRadius) or 5.0
    local shown = 0

    if selectedViewer then
        selectedViewer = tonumber(selectedViewer)
        if not selectedViewer or selectedViewer == ownerId or not getXPlayer(selectedViewer) then
            notify(ownerId, Config.Notifications.NoPlayer, 'error')
            return false
        end

        if not playersAreNear(ownerId, selectedViewer, radius) then
            notify(ownerId, Config.Notifications.NoPlayer, 'error')
            return false
        end
    end

    TriggerClientEvent(RESOURCE .. ':client:openId', ownerId, card)

    if selectedViewer then
        sendCardToViewer(ownerId, selectedViewer, card)
        shown = 1
    elseif Config.Identification.ShowToAllNearbyOnUse then
        for _, playerIdString in ipairs(GetPlayers()) do
            local viewerId = tonumber(playerIdString)
            if viewerId and viewerId ~= ownerId and playersAreNear(ownerId, viewerId, radius) then
                sendCardToViewer(ownerId, viewerId, card)
                shown = shown + 1
            end
        end
    end

    notify(ownerId, Config.Notifications.IdPresented, 'success')
    debugPrint(('Player %d presented Government ID to %d player(s)'):format(ownerId, shown))
    return true
end

local function setProtectionState(playerId)
    playerId = tonumber(playerId)
    if not playerId then return end

    local player = Player(playerId)
    if not player or not player.state then return end

    local shouldProtect = Config.CuffProtection.Enabled and isGovernmentPlayer(playerId)
    if player.state[Config.CuffProtection.StateKey] ~= shouldProtect then
        player.state:set(Config.CuffProtection.StateKey, shouldProtect, true)
    end
end

local function processCuffAttempt(attackerId, targetId)
    attackerId = tonumber(attackerId)
    targetId = tonumber(targetId)
    if not attackerId or not targetId or attackerId == targetId then return false end
    if not Config.CuffProtection.Enabled or not isGovernmentPlayer(targetId) then return true end

    local attackerJob = getJob(getXPlayer(attackerId))
    if not attackerJob or not Config.CuffProtection.PoliceJobs[attackerJob.name] then
        return false
    end

    local maxDistance = tonumber(Config.CuffProtection.MaxDistance) or 4.0
    if not playersAreNear(attackerId, targetId, maxDistance) then return false end

    local now = GetGameTimer()
    if cuffCooldowns[attackerId] and now < cuffCooldowns[attackerId] then
        return false
    end
    cuffCooldowns[attackerId] = now + (tonumber(Config.CuffProtection.AttemptCooldownMs) or 5000)

    notify(attackerId, Config.Notifications.CuffBlockedOfficer, 'error')
    notify(targetId, Config.Notifications.CuffBlockedOfficial, 'warning')

    if Config.CuffProtection.TaseAttacker then
        TriggerClientEvent(
            RESOURCE .. ':client:tasePenalty',
            attackerId,
            tonumber(Config.CuffProtection.TaseDurationMs) or 5000
        )
    end

    print(('[%s] Blocked cuff attempt: officer %d -> protected official %d'):format(
        RESOURCE,
        attackerId,
        targetId
    ))
    return false
end

local function registerArmory()
    if not Config.Armory.Enabled then return end

    local inventory = {}
    local skipped = {}

    for i = 1, #Config.Armory.Items do
        local configuredItem = Config.Armory.Items[i]
        local ok, item = pcall(function()
            return exports.ox_inventory:Items(configuredItem.name)
        end)

        if ok and item then
            inventory[#inventory + 1] = configuredItem
        else
            skipped[#skipped + 1] = configuredItem.name
        end
    end

    if #skipped > 0 then
        print(('[%s] Armory skipped unregistered ox_inventory items: %s'):format(
            RESOURCE,
            table.concat(skipped, ', ')
        ))
        print(('[%s] Install the official p_policejob/INSTALL/ITEMS definitions, then restart this resource.'):format(RESOURCE))
    end

    local ok, result = pcall(function()
        return exports.ox_inventory:RegisterShop(Config.Armory.ShopId, {
            name = Config.Armory.Label,
            inventory = inventory,
            locations = { Config.Armory.Coords },
            groups = { [Config.JobName] = 0 }
        })
    end)

    if not ok or result == false then
        print(('[%s] ERROR: failed to register armory shop: %s'):format(RESOURCE, tostring(result)))
        return
    end

    debugPrint(('Registered armory with %d available item(s)'):format(#inventory))
end

-- ox_inventory server item callback referenced by install/ox_inventory_items.lua.
exports('useGovernmentId', function(event, _, inventory)
    local playerId = inventory and tonumber(inventory.id)
    if not playerId then return false end

    if event == 'usingItem' then
        if not isGovernmentPlayer(playerId) then
            notify(playerId, Config.Notifications.NotGovernment, 'error')
            return false
        end
        return
    end

    if event == 'usedItem' then
        SetTimeout(100, function()
            presentIdentification(playerId)
        end)
    end
end)

-- Server-side integration exports for any restraint resource.
exports('IsGovernmentPlayer', isGovernmentPlayer)
exports('CanCuff', function(targetId)
    return not (Config.CuffProtection.Enabled and isGovernmentPlayer(targetId))
end)
exports('ReportCuffAttempt', function(attackerId, targetId)
    return processCuffAttempt(attackerId, targetId)
end)

RegisterNetEvent(RESOURCE .. ':server:presentIdTo', function(targetId)
    presentIdentification(source, targetId)
end)

RegisterNetEvent(RESOURCE .. ':server:cuffAttempt', function(targetId)
    processCuffAttempt(source, targetId)
end)

RegisterNetEvent(RESOURCE .. ':server:forcedCuffDetected', function()
    local playerId = source
    if not isGovernmentPlayer(playerId) then return end

    local now = GetGameTimer()
    if safetyCooldowns[playerId] and now < safetyCooldowns[playerId] then return end
    safetyCooldowns[playerId] = now + (tonumber(Config.CuffProtection.AttemptCooldownMs) or 5000)

    notify(playerId, Config.Notifications.SafetyReleased, 'warning')
    print(('[%s] Safety net removed a cuff state from protected official %d; apply the p_policejob guard for full prevention.'):format(
        RESOURCE,
        playerId
    ))
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    SetTimeout(1000, function()
        setProtectionState(playerId)
    end)
end)

AddEventHandler('esx:setJob', function(playerId)
    SetTimeout(0, function()
        setProtectionState(playerId)
    end)
end)

AddEventHandler('playerDropped', function()
    local playerId = source
    presentationCooldowns[playerId] = nil
    cuffCooldowns[playerId] = nil
    safetyCooldowns[playerId] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    for _, playerIdString in ipairs(GetPlayers()) do
        local player = Player(tonumber(playerIdString))
        if player and player.state then
            player.state:set(Config.CuffProtection.StateKey, false, true)
        end
    end
end)

CreateThread(function()
    while not getESX() do Wait(250) end
    Wait(500)
    registerArmory()

    while true do
        local units = {}
        local recipients = {}

        for _, playerIdString in ipairs(GetPlayers()) do
            local playerId = tonumber(playerIdString)
            local xPlayer = getXPlayer(playerId)
            local job = getJob(xPlayer)

            if playerId and job then
                setProtectionState(playerId)

                if job.name == Config.JobName then
                    recipients[#recipients + 1] = playerId
                elseif Config.Tracking.Enabled and Config.Tracking.Jobs[job.name] then
                    local coords, ped = getPlayerCoords(playerId)
                    if coords and ped then
                        local tracking = Config.Tracking.Jobs[job.name]
                        local firstName, lastName = getIdentity(xPlayer)
                        local unitLabel = tracking.label

                        if Config.Tracking.ShowPlayerNames then
                            unitLabel = ('%s | %s %s [%d]'):format(
                                tracking.label,
                                firstName,
                                lastName,
                                playerId
                            )
                        end

                        units[#units + 1] = {
                            id = playerId,
                            coords = { x = coords.x, y = coords.y, z = coords.z },
                            heading = GetEntityHeading(ped),
                            label = unitLabel,
                            sprite = tracking.sprite,
                            colour = tracking.colour,
                            scale = tracking.scale
                        }
                    end
                end
            end
        end

        if Config.Tracking.Enabled then
            for i = 1, #recipients do
                TriggerClientEvent(RESOURCE .. ':client:syncTracking', recipients[i], units)
            end
        end

        Wait(math.max(1000, tonumber(Config.Tracking.RefreshMs) or 2000))
    end
end)
