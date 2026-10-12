--[[
    CodeX Wallet - client (QBCore)

    The client is a thin shell: it opens/closes the NUI and forwards intents to
    the server. Every wallet action is validated server-side.
]]

local RESOURCE = GetCurrentResourceName()

local QBCore = nil
local uiOpen = false
local presentedOpen = false

local function TryGetCore()
    if QBCore then
        return QBCore
    end

    local ok, object = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)

    if ok and object then
        QBCore = object
        return QBCore
    end

    TriggerEvent('QBCore:GetObject', function(object)
        QBCore = object
    end)

    return QBCore
end

local function Notify(message, kind)
    if not message or message == '' then
        return
    end

    if QBCore and QBCore.Functions and QBCore.Functions.Notify then
        QBCore.Functions.Notify(message, kind or 'primary')
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function CloseUI()
    if not uiOpen then
        return
    end

    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerServerEvent(RESOURCE .. ':closeWallet')
end

local function ClosePresented()
    if not presentedOpen then
        return
    end

    presentedOpen = false
    SendNUIMessage({ action = 'closeCard' })
end

-- wallet window ------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':openWallet', function(payload)
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        payload = payload
    })
end)

RegisterNetEvent(RESOURCE .. ':notify', function(message, kind)
    Notify(message, kind)
end)

-- presented ID card ---------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':presentCard', function(card, autoCloseMs, presenterName)
    presentedOpen = true

    SendNUIMessage({
        action = 'showCard',
        card = card,
        presenterName = presenterName,
        autoCloseMs = tonumber(autoCloseMs) or 0
    })

    if tonumber(autoCloseMs) and tonumber(autoCloseMs) > 0 then
        SetTimeout(tonumber(autoCloseMs), function()
            if presentedOpen then
                ClosePresented()
            end
        end)
    end
end)

-- NUI callbacks -------------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    if type(data) ~= 'table' or type(data.action) ~= 'string' then
        cb({ ok = false })
        return
    end

    TriggerServerEvent(RESOURCE .. ':action', data.action, data.data or {})
    cb({ ok = true })
end)

RegisterNUICallback('notify', function(data, cb)
    if data and data.message then
        Notify(data.message, data.kind)
    end
    cb({ ok = true })
end)

-- controls -----------------------------------------------------------------------
CreateThread(function()
    while not TryGetCore() do
        Wait(250)
    end

    if Config.Keybind and Config.Keybind.Enabled ~= false then
        local command = 'codexwallet_open'

        RegisterCommand(command, function()
            TriggerServerEvent(RESOURCE .. ':useWallet')
        end, false)

        RegisterKeyMapping(
            command,
            (Config.Keybind.Description) or 'Open your CodeX Wallet',
            'keyboard',
            (Config.Keybind.Default) or 'F7'
        )
    end

    if Config.Command and Config.Command ~= '' and Config.Command ~= false then
        RegisterCommand(Config.Command, function()
            TriggerServerEvent(RESOURCE .. ':useWallet')
        end, false)
    end
end)

-- Safety net: ESC always closes the wallet window.
CreateThread(function()
    while true do
        Wait(0)

        if uiOpen then
            if IsControlJustPressed(0, 200) or IsControlJustPressed(0, 177) then -- ESC / Backspace
                CloseUI()
            end
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then
        return
    end

    if uiOpen then
        SetNuiFocus(false, false)
    end
end)
