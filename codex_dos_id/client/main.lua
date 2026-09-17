local RESOURCE = GetCurrentResourceName()

local ESX = nil
local uiOpen = false

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

local function Notify(message)
    if not message or message == '' then
        return
    end

    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(message)
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function CloseUI()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function OpenUI(card, mode, autoCloseMs)
    uiOpen = true

    local interactive = mode ~= 'presented'
    SetNuiFocus(interactive, interactive)

    SendNUIMessage({
        action = 'open',
        card = card,
        mode = mode or 'own',
        autoCloseMs = tonumber(autoCloseMs) or 0
    })
end

RegisterNetEvent(RESOURCE .. ':openCard', function(card)
    OpenUI(card, 'own', 0)
end)

RegisterNetEvent(RESOURCE .. ':presentCard', function(card, autoCloseMs)
    -- Read-only popup shown to a nearby officer when the item owner uses
    -- their ID card. No NUI focus is taken so the officer can keep playing.
    OpenUI(card, 'presented', autoCloseMs)
end)

RegisterNetEvent(RESOURCE .. ':notify', function(message)
    Notify(message)
end)

RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb({ ok = true })
end)

CreateThread(function()
    while not TryGetESX() do
        Wait(500)
    end
end)

-- Safety net: ESC always closes the interactive card window.
CreateThread(function()
    while true do
        Wait(0)
        if uiOpen then
            if IsControlJustPressed(0, 200) then -- INPUT_FRONTEND_PAUSE (ESC)
                CloseUI()
            end
        else
            Wait(250)
        end
    end
end)
