local RESOURCE = GetCurrentResourceName()
local ESX
local playerJob
local armoryZone
local trackedBlips = {}
local cardSession = 0
local cardMode
local tasedUntil = 0
local cuffReportCooldown = 0
local attemptReportCooldown = 0

local function debugPrint(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

local function notify(description, notificationType)
    lib.notify({
        title = Config.Notifications.Title,
        description = description,
        type = notificationType or 'inform'
    })
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

local function refreshPlayerData()
    local framework = getESX()
    if not framework then return end

    local data = framework.GetPlayerData and framework.GetPlayerData() or framework.PlayerData
    playerJob = data and data.job or playerJob
end

local function isGovernment()
    return playerJob and playerJob.name == Config.JobName
end

local function closeCard()
    cardSession = cardSession + 1
    cardMode = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function displayCard(card, mode, autoCloseMs)
    if mode == 'presented' and cardMode == 'own' then
        return
    end

    cardSession = cardSession + 1
    local session = cardSession
    cardMode = mode

    SetNuiFocus(mode == 'own', mode == 'own')
    SendNUIMessage({
        action = 'open',
        mode = mode,
        card = card,
        autoCloseMs = autoCloseMs
    })

    if mode == 'presented' and tonumber(autoCloseMs) and tonumber(autoCloseMs) > 0 then
        SetTimeout(tonumber(autoCloseMs), function()
            if cardSession == session and cardMode == 'presented' then
                closeCard()
            end
        end)
    end
end

local function clearTrackedBlips()
    for _, entry in pairs(trackedBlips) do
        if entry.blip and DoesBlipExist(entry.blip) then
            RemoveBlip(entry.blip)
        end
    end

    trackedBlips = {}
end

local function removeExpiredBlips(now)
    local expiry = tonumber(Config.Tracking.ExpireMs) or 6500

    for id, entry in pairs(trackedBlips) do
        if now - entry.updatedAt > expiry then
            if DoesBlipExist(entry.blip) then
                RemoveBlip(entry.blip)
            end
            trackedBlips[id] = nil
        end
    end
end

local function setupTargets()
    if Config.Armory.Enabled then
        armoryZone = exports.ox_target:addBoxZone({
            coords = Config.Armory.Coords,
            size = Config.Armory.Size,
            rotation = Config.Armory.Rotation,
            debug = Config.Armory.DebugZone,
            drawSprite = Config.Armory.DrawTargetSprite,
            options = {
                {
                    name = RESOURCE .. '_armory',
                    icon = 'fa-solid fa-shield-halved',
                    label = Config.Armory.Label,
                    groups = { [Config.JobName] = 0 },
                    distance = Config.Armory.TargetDistance,
                    canInteract = function()
                        return isGovernment() and not IsEntityDead(PlayerPedId())
                    end,
                    onSelect = function()
                        local opened = exports.ox_inventory:openInventory('shop', {
                            type = Config.Armory.ShopId,
                            id = 1
                        })

                        if opened == false then
                            notify(Config.Notifications.ArmoryUnavailable, 'error')
                        end
                    end
                }
            }
        })
    end

    if Config.Identification.EnablePlayerTarget then
        exports.ox_target:addGlobalPlayer({
            {
                name = RESOURCE .. '_present_id',
                icon = 'fa-solid fa-id-card',
                label = 'Present Government ID',
                groups = { [Config.JobName] = 0 },
                distance = Config.Identification.PresentRadius,
                canInteract = function(entity)
                    if not isGovernment() or entity == PlayerPedId() then return false end
                    return exports.ox_inventory:Search('count', Config.Identification.Item) > 0
                end,
                onSelect = function(data)
                    local playerIndex = NetworkGetPlayerIndexFromPed(data.entity)
                    if playerIndex == -1 then
                        notify(Config.Notifications.NoPlayer, 'error')
                        return
                    end

                    TriggerServerEvent(RESOURCE .. ':server:presentIdTo', GetPlayerServerId(playerIndex))
                end
            }
        })
    end
end

local function getClosestPlayerServerId(maxDistance)
    local ownPlayer = PlayerId()
    local ownCoords = GetEntityCoords(PlayerPedId())
    local closestServerId
    local closestDistance = tonumber(maxDistance) or 4.0

    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= ownPlayer then
            local targetPed = GetPlayerPed(playerIndex)
            if targetPed and targetPed > 0 then
                local distance = #(ownCoords - GetEntityCoords(targetPed))
                if distance <= closestDistance then
                    closestDistance = distance
                    closestServerId = GetPlayerServerId(playerIndex)
                end
            end
        end
    end

    return closestServerId
end

local function runProtectedCuff(pPoliceEvent)
    local targetServerId = getClosestPlayerServerId(Config.CuffProtection.MaxDistance)
    if not targetServerId then
        notify(Config.Notifications.NoPlayer, 'error')
        return
    end

    if not exports[RESOURCE]:CanCuff(targetServerId) then
        return
    end

    if GetResourceState('p_policejob') ~= 'started' then
        notify('p_policejob is not running.', 'error')
        return
    end

    TriggerEvent(pPoliceEvent)
end

-- Replace direct p_policejob hard/soft cuff calls with these protected wrappers.
RegisterNetEvent(RESOURCE .. ':client:protectedHardCuff', function()
    runProtectedCuff('p_policejob/hardCuff')
end)

RegisterNetEvent(RESOURCE .. ':client:protectedSoftCuff', function()
    runProtectedCuff('p_policejob/softCuff')
end)

-- ox_inventory client callback. The matching server callback performs the
-- authoritative job/item validation before ox_inventory confirms the use.
exports('governmentId', function(data, slot)
    if not isGovernment() then
        notify(Config.Notifications.NotGovernment, 'error')
        return
    end

    exports.ox_inventory:useItem(data, function(used)
        if used then
            debugPrint(('Government ID used from slot %s'):format(tostring(slot)))
        end
    end)
end)

-- Use this from p_policejob immediately before starting its hard/soft cuff
-- action. It returns false for protected gouv targets and securely reports the
-- attempt to the server (which validates both jobs and distance).
exports('CanCuff', function(targetServerId)
    targetServerId = tonumber(targetServerId)
    if not targetServerId or targetServerId <= 0 then return false end

    local protected = Player(targetServerId).state[Config.CuffProtection.StateKey] == true
    if protected and Config.CuffProtection.Enabled then
        local now = GetGameTimer()
        if now >= attemptReportCooldown then
            attemptReportCooldown = now + 1000
            TriggerServerEvent(RESOURCE .. ':server:cuffAttempt', targetServerId)
        end
        return false
    end

    return true
end)

exports('IsGovernmentProtected', function(targetServerId)
    targetServerId = tonumber(targetServerId)
    return targetServerId ~= nil
        and Player(targetServerId).state[Config.CuffProtection.StateKey] == true
end)

RegisterNUICallback('close', function(_, callback)
    closeCard()
    callback({ ok = true })
end)

RegisterNetEvent(RESOURCE .. ':client:openId', function(card)
    displayCard(card, 'own')
end)

RegisterNetEvent(RESOURCE .. ':client:receiveId', function(card, autoCloseMs)
    displayCard(card, 'presented', autoCloseMs)
end)

RegisterNetEvent(RESOURCE .. ':client:notify', function(description, notificationType)
    notify(description, notificationType)
end)

RegisterNetEvent(RESOURCE .. ':client:syncTracking', function(units)
    if not Config.Tracking.Enabled or not isGovernment() then
        clearTrackedBlips()
        return
    end

    local now = GetGameTimer()
    local seen = {}

    for i = 1, #(units or {}) do
        local unit = units[i]
        local id = tostring(unit.id)
        local entry = trackedBlips[id]

        if not entry or not DoesBlipExist(entry.blip) then
            local blip = AddBlipForCoord(unit.coords.x + 0.0, unit.coords.y + 0.0, unit.coords.z + 0.0)
            SetBlipAsShortRange(blip, false)
            SetBlipDisplay(blip, 4)
            SetBlipSprite(blip, tonumber(unit.sprite) or 1)
            SetBlipColour(blip, tonumber(unit.colour) or 3)
            SetBlipScale(blip, tonumber(unit.scale) or 0.82)
            SetBlipFlashes(blip, true)
            SetBlipFlashInterval(blip, tonumber(Config.Tracking.FlashIntervalMs) or 900)
            ShowHeadingIndicatorOnBlip(blip, true)

            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(unit.label or 'Emergency Unit')
            EndTextCommandSetBlipName(blip)

            entry = { blip = blip }
            trackedBlips[id] = entry
        else
            SetBlipCoords(entry.blip, unit.coords.x + 0.0, unit.coords.y + 0.0, unit.coords.z + 0.0)
            SetBlipRotation(entry.blip, math.floor(tonumber(unit.heading) or 0.0))
        end

        entry.updatedAt = now
        seen[id] = true
    end

    for id, entry in pairs(trackedBlips) do
        if not seen[id] then
            if DoesBlipExist(entry.blip) then
                RemoveBlip(entry.blip)
            end
            trackedBlips[id] = nil
        end
    end
end)

RegisterNetEvent(RESOURCE .. ':client:tasePenalty', function(durationMs)
    if not Config.CuffProtection.TaseAttacker then return end

    local duration = math.max(1000, math.min(tonumber(durationMs) or 5000, 10000))
    tasedUntil = math.max(tasedUntil, GetGameTimer() + duration)

    CreateThread(function()
        while GetGameTimer() < tasedUntil do
            local ped = PlayerPedId()
            if not IsPedRagdoll(ped) then
                SetPedToRagdoll(ped, 1000, 1000, 0, false, false, false)
            end

            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            Wait(0)
        end
    end)
end)

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    playerJob = xPlayer and xPlayer.job or playerJob
end)

RegisterNetEvent('esx:setJob', function(job)
    playerJob = job
    if not isGovernment() then
        clearTrackedBlips()
        if cardMode then closeCard() end
    end
end)

CreateThread(function()
    while not getESX() do Wait(250) end
    if ESX.IsPlayerLoaded then
        while not ESX.IsPlayerLoaded() do Wait(250) end
    else
        Wait(1000)
    end
    refreshPlayerData()
    setupTargets()
end)

-- Last-resort protection for cuff scripts that change native/state-bag state
-- without calling the CanCuff integration export.
CreateThread(function()
    while true do
        if Config.CuffProtection.Enabled and Config.CuffProtection.ClientSafetyNet and isGovernment() then
            local ped = PlayerPedId()
            local state = LocalPlayer.state

            if state.isCuffed == true or IsPedCuffed(ped) then
                state:set('isCuffed', false, true)
                state:set('cuffType', 'none', true)
                SetEnableHandcuffs(ped, false)
                UncuffPed(ped)
                FreezeEntityPosition(ped, false)
                ClearPedSecondaryTask(ped)

                local now = GetGameTimer()
                if now >= cuffReportCooldown then
                    cuffReportCooldown = now + (tonumber(Config.CuffProtection.AttemptCooldownMs) or 5000)
                    TriggerServerEvent(RESOURCE .. ':server:forcedCuffDetected')
                end
            end
        end
        Wait(250)
    end
end)

CreateThread(function()
    while true do
        Wait(2000)
        if next(trackedBlips) then
            removeExpiredBlips(GetGameTimer())
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if cardMode == 'own' and IsControlJustReleased(0, 322) then
            closeCard()
        elseif not cardMode then
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    if armoryZone then
        exports.ox_target:removeZone(armoryZone)
    end

    if Config.Identification.EnablePlayerTarget then
        exports.ox_target:removeGlobalPlayer(RESOURCE .. '_present_id')
    end

    clearTrackedBlips()
    SetNuiFocus(false, false)
end)
