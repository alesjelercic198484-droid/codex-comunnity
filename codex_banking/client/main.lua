local QBCore = exports['qb-core']:GetCoreObject()

local uiOpen = false
local uiMode = nil
local sessionToken = nil
local currentContext = nil
local bankBlips = {}
local opening = false

local function notify(message, kind)
    local text = tostring(message or '')
    local messages = {
        not_ready = 'Banking is still loading.',
        not_authenticated = 'You are not logged in.',
        no_permission = 'You are not authorized to do that.',
        too_far = 'You must be at a bank or ATM.',
        session_expired = 'Your banking session expired. Reopen the interface.',
        busy = 'Banking is busy. Try again shortly.',
        server_error = 'Something went wrong.',
        card_required = 'Insert and verify a valid card.',
        card_locked = 'Your card is temporarily locked.',
        card_frozen = 'Your card is frozen.',
        wrong_pin = 'Incorrect PIN.',
        welcome = 'Welcome to the bank.',
        safe_box_opened = 'Safe box opened.',
        invoice_created = 'Invoice issued.',
        invoice_received = 'You received a new invoice.',
        missing_inventory = 'A supported inventory resource is required to open a safe box.'
    }
    QBCore.Functions.Notify(messages[text] or text, kind or 'primary', 4500)
end

local function closeUI(sendToServer)
    if not uiOpen then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'close' })
    if sendToServer and sessionToken then
        TriggerServerEvent('codex_banking:server:closeSession', sessionToken)
    end
    uiOpen = false
    uiMode = nil
    sessionToken = nil
    currentContext = nil
    opening = false
end

local function showUI(mode, response)
    if not response or not response.ok then
        notify(response and response.message or 'server_error', 'error')
        opening = false
        return
    end
    uiOpen = true
    uiMode = mode
    sessionToken = response.token
    currentContext = response.data and response.data.session or (mode == 'atm' and { mode = 'atm_pending', atmId = response.atmId } or nil)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    if mode == 'atm' then
        SendNUIMessage({
            type = 'openAtm',
            locale = Config.Locale,
            currencySymbol = Config.CurrencySymbol,
            token = sessionToken,
            cards = response.cards or {},
            atm = response.atm or {}
        })
    else
        SendNUIMessage({ type = 'open', mode = mode, locale = Config.Locale, currencySymbol = Config.CurrencySymbol, token = sessionToken, data = response.data })
    end
    opening = false
end

local function openBranch(branch)
    if uiOpen or opening or not branch then return end
    opening = true
    QBCore.Functions.TriggerCallback('codex_banking:server:openBranch', function(response)
        showUI('bank', response)
    end, branch.bank)
end

local function getNearbyATMObject()
    if not Config.ATMs or Config.ATMs.Enabled == false then return nil end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    for _, model in ipairs(Config.ATMs.Models or {}) do
        local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, 2.6, GetHashKey(model), false, false, false)
        if entity and entity ~= 0 then
            local atmCoords = GetEntityCoords(entity)
            if #(coords - atmCoords) <= (Config.ATMs.InteractionRadius or 2.5) then
                return entity, atmCoords
            end
        end
    end
    return nil
end

local function openATM()
    if uiOpen or opening then return end
    opening = true
    QBCore.Functions.TriggerCallback('codex_banking:server:openATM', function(response)
        showUI('atm', response)
    end)
end

local function openAdmin()
    if uiOpen or opening then return end
    opening = true
    QBCore.Functions.TriggerCallback('codex_banking:server:openAdmin', function(response)
        showUI('admin', response)
        if response and response.ok then
            QBCore.Functions.TriggerCallback('codex_banking:server:adminAction', function(result)
                if result and result.ok then
                    SendNUIMessage({ type = 'adminData', overview = result.overview })
                end
            end, 'overview', {}, response.token)
        end
    end)
end

local function nearestBranch(maxDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDistance
    for _, branch in ipairs(Config.Branches or {}) do
        local distance = #(coords - branch.coords)
        if distance <= (maxDistance or Config.Interaction.DrawDistance) and (not bestDistance or distance < bestDistance) then
            best, bestDistance = branch, distance
        end
    end
    return best, bestDistance
end

local function drawText3D(coords, text)
    local onScreen, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.33, 0.33)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 225)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(screenX, screenY)
    local width = math.min(0.40, 0.018 + (#text / 450))
    DrawRect(screenX, screenY + 0.014, width, 0.032, 12, 20, 31, 165)
end

local function setupBlips()
    if not Config.Interaction.ShowBlips then return end
    for _, branch in ipairs(Config.Branches or {}) do
        local blip = AddBlipForCoord(branch.coords.x, branch.coords.y, branch.coords.z)
        SetBlipSprite(blip, 108)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.62)
        SetBlipColour(blip, branch.bank == 'pacific' and 46 or (branch.bank == 'maze' and 1 or 2))
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(branch.label or (Config.Banks[branch.bank] and Config.Banks[branch.bank].label) or 'Bank')
        EndTextCommandSetBlipName(blip)
        bankBlips[#bankBlips + 1] = blip
    end
end

RegisterNUICallback('close', function(_, cb)
    closeUI(true)
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    if not uiOpen or not sessionToken then
        cb({ ok = false, message = 'session_expired' })
        return
    end
    data = data or {}
    local callbackName = uiMode == 'admin' and 'codex_banking:server:adminAction' or 'codex_banking:server:action'
    QBCore.Functions.TriggerCallback(callbackName, function(response)
        response = response or { ok = false, message = 'server_error' }
        if response.data then
            SendNUIMessage({ type = 'update', data = response.data })
            currentContext = response.data.session or currentContext
        end
        if response.overview then
            SendNUIMessage({ type = 'adminData', overview = response.overview })
        end
        cb(response)
    end, data.action, data.payload or {}, sessionToken)
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    if not uiOpen or uiMode ~= 'admin' or not sessionToken then
        cb({ ok = false, message = 'no_permission' })
        return
    end
    QBCore.Functions.TriggerCallback('codex_banking:server:adminAction', function(response)
        if response and response.overview then
            SendNUIMessage({ type = 'adminData', overview = response.overview })
        end
        cb(response or { ok = false })
    end, 'overview', {}, sessionToken)
end)

RegisterNetEvent('codex_banking:client:notify', function(message, kind)
    notify(message, kind)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    closeUI(false)
end)

RegisterNetEvent('codex_banking:client:openSafeBox', function(box)
    if type(box) ~= 'table' or not box.stashId then return end
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:openInventory('stash', box.stashId)
        return
    end
    if GetResourceState('qb-inventory') == 'started' then
        TriggerServerEvent('inventory:server:OpenInventory', 'stash', box.stashId, {
            maxweight = tonumber(box.maxWeight) or 50000,
            slots = tonumber(box.slots) or 10
        })
        TriggerEvent('inventory:client:SetCurrentStash', box.stashId)
        return
    end
    notify('missing_inventory', 'error')
end)

RegisterCommand(Config.Commands.Bank, function()
    local branch, branchDistance = nearestBranch(12.0)
    if not branch or not branchDistance or branchDistance > (tonumber(branch.radius) or 4.0) then
        notify('too_far', 'error')
        return
    end
    openBranch(branch)
end, false)

RegisterCommand(Config.Commands.ATM, function()
    if not getNearbyATMObject() then
        notify('too_far', 'error')
        return
    end
    openATM()
end, false)

RegisterCommand(Config.Commands.Admin, function()
    openAdmin()
end, false)

CreateThread(function()
    Wait(1000)
    setupBlips()
    while true do
        local waitMs = 700
        if uiOpen then
            waitMs = 400
            if uiMode ~= 'admin' then
                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                local context = currentContext or {}
                local shouldClose = false
                if context.mode == 'branch' then
                    local branch
                    for _, item in ipairs(Config.Branches or {}) do
                        if item.id == context.branchId then branch = item break end
                    end
                    if branch and #(coords - branch.coords) > (tonumber(branch.radius) or Config.Interaction.AutoCloseDistance) then shouldClose = true end
                elseif context.mode == 'atm' or context.mode == 'atm_pending' then
                    local atm = context.atmId and Config.ATMs.AccessPoints[tonumber(context.atmId)]
                    if atm and #(coords - atm) > (Config.ATMs.SessionRadius or 4.0) then shouldClose = true end
                end
                if shouldClose then closeUI(true) end
            end
        else
            local branch, branchDistance = nearestBranch(Config.Interaction.DrawDistance)
            local atmEntity, atmCoords = getNearbyATMObject()
            local nearPrompt = false

            if branch and Config.Interaction.UseMarkers and branchDistance <= Config.Interaction.MarkerDistance then
                waitMs = 0
                DrawMarker(2, branch.coords.x, branch.coords.y, branch.coords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.24, 0.24, 0.18, 73, 197, 182, 130, false, true, 2, false, nil, nil, false)
            end

            if branch and branchDistance <= Config.Interaction.PromptDistance then
                waitMs = 0
                nearPrompt = true
                drawText3D(vector3(branch.coords.x, branch.coords.y, branch.coords.z + 0.6), ('~b~%s~s~\n%s'):format(branch.label, Config.Messages.interactBank))
                if branchDistance <= (tonumber(Config.Interaction.InteractDistance) or 1.8)
                    and IsControlJustReleased(0, Config.Interaction.Key) then
                    openBranch(branch)
                end
            elseif atmEntity and atmCoords then
                waitMs = 0
                nearPrompt = true
                drawText3D(vector3(atmCoords.x, atmCoords.y, atmCoords.z + 0.85), Config.Messages.interactATM)
                if #(GetEntityCoords(PlayerPedId()) - atmCoords) <= (tonumber(Config.Interaction.InteractDistance) or 1.8)
                    and IsControlJustReleased(0, Config.Interaction.Key) then
                    openATM()
                end
            end

            if not nearPrompt and waitMs == 0 then waitMs = 250 end
        end
        Wait(waitMs)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if uiOpen then
        SetNuiFocus(false, false)
        TriggerServerEvent('codex_banking:server:closeSession', sessionToken)
    end
    for _, blip in ipairs(bankBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
end)
