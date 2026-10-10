--[============================================================================[
    CodeX Roleplay Inventory - client

    Handles the keybinds, the NUI bridge, the hotbar, drop markers and the
    compatibility events other qb-core scripts fire at `qb-inventory`.
]============================================================================]

local QBCore = exports['qb-core']:GetCoreObject()

local Inventory = {
    open = false,
    items = {},          -- own inventory, slot keyed
    other = nil,         -- second panel (stash / drop / trunk / shop / player)
    hotbar = {},
    drops = {},
    busy = false,
    dropHint = false,
}

local CURRENT_SETTINGS = {}

-- ===========================================================================
-- Helpers
-- ===========================================================================
local function PlayerData()
    local ok, data = pcall(function()
        return QBCore.Functions.GetPlayerData()
    end)

    if ok and type(data) == 'table' then return data end
    return {}
end

--- Everything the "showcase" column shows: name, job, money ...
local function PlayerCard()
    local data = PlayerData()
    local charinfo = type(data.charinfo) == 'table' and data.charinfo or {}
    local money = type(data.money) == 'table' and data.money or {}
    local job = type(data.job) == 'table' and data.job or {}
    local gang = type(data.gang) == 'table' and data.gang or {}

    local first = charinfo.firstname or ''
    local last = charinfo.lastname or ''
    local name = (first .. ' ' .. last)

    if name:gsub('%s', '') == '' then
        name = tostring(data.name or GetPlayerName(PlayerId()) or 'Citizen')
    end

    return {
        name = name,
        firstname = first,
        lastname = last,
        citizenid = data.citizenid or '',
        job = job.label or 'Unemployed',
        jobName = job.name or 'unemployed',
        gang = gang.label or '',
        cash = tonumber(money.cash) or 0,
        bank = tonumber(money.bank) or 0,
        phone = charinfo.phone or '',
        serverId = GetPlayerServerId(PlayerId()),
    }
end

local function SendNUI(message)
    SendNUIMessage(message)
end

--- Floating "[E]" hint. Older qb-core builds have no DrawText export, so the
--- call is protected - the drop markers and the keybind still work without it.
local function ShowDropHint(text)
    local ok = pcall(function()
        if text then
            exports['qb-core']:DrawText(text)
        else
            exports['qb-core']:HideText()
        end
    end)

    return ok
end

local function CloseInventoryNUI()
    Inventory.open = false
    Inventory.other = nil

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    SendNUI({ action = 'close' })

    if PedPreview and PedPreview.IsActive and PedPreview.IsActive() then
        PedPreview.Stop()
    end

    TriggerServerEvent('qb-inventory:server:closeInventory', Inventory.currentIdentifier)
    Inventory.currentIdentifier = nil
end

local function OpenInventoryNUI(items, other)
    Inventory.open = true
    Inventory.items = items or {}
    Inventory.other = other

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    SendNUI({
        action = 'open',
        inventory = Inventory.items,
        other = other,
        slots = Config.MaxSlots,
        maxweight = Config.MaxWeight,
        player = PlayerCard(),
    })

    if other and other.name then
        Inventory.currentIdentifier = other.name
    end

    -- The 3D ped preview only makes sense in the showcase layout.
    local layout = (CURRENT_SETTINGS and CURRENT_SETTINGS.Layout) or
                   (Config.Defaults and Config.Defaults.Layout) or 'showcase'

    if layout == 'showcase' and PedPreview then
        PedPreview.Start()
    end
end

-- ===========================================================================
-- Bootstrap
-- ===========================================================================
CreateThread(function()
    Wait(1500)

    CURRENT_SETTINGS = Config.Defaults or {}

    SendNUI({
        action = 'setup',
        config = {
            brand = Config.Brand,
            maxSlots = Config.MaxSlots,
            maxWeight = Config.MaxWeight,
            hotbarSlots = Config.HotbarSlots,
            images = Config.Images,
            rarity = Config.Rarity,
            sounds = Config.Sounds,
            toasts = Config.Toasts,
            permissions = Config.Permissions,
            drops = Config.Drops,
            locale = Config.Locale,
            availableLocales = Config.AvailableLocales,
        },
        defaults = Config.Defaults,
        player = PlayerCard(),
    })
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    SendNUI({ action = 'playerData', player = PlayerCard() })
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    CloseInventoryNUI()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function()
    if Inventory.open then
        SendNUI({ action = 'playerData', player = PlayerCard() })
    end
end)

-- ===========================================================================
-- Events coming from the server
-- ===========================================================================
RegisterNetEvent('qb-inventory:client:openInventory', function(items, other)
    OpenInventoryNUI(items, other)
end)

RegisterNetEvent('qb-inventory:client:refreshInventory', function(items, other)
    Inventory.items = items or {}

    if other ~= nil then
        Inventory.other = other
    end

    if not Inventory.open then return end

    SendNUI({
        action = 'refresh',
        inventory = Inventory.items,
        other = Inventory.other,
        player = PlayerCard(),
    })
end)

RegisterNetEvent('qb-inventory:client:closeInv', function()
    CloseInventoryNUI()
end)

RegisterNetEvent('qb-inventory:client:ItemBox', function(itemData, type, amount)
    if type(itemData) ~= 'table' then return end

    SendNUI({
        action = 'toast',
        kind = type == 'add' and 'pickup' or (type == 'remove' and 'drop' or (type or 'use')),
        title = itemData.label or itemData.name or 'Item',
        image = itemData.image or '',
        amount = tonumber(amount) or 1,
        rarity = itemData.rarity or 'common',
    })
end)

RegisterNetEvent('qb-inventory:client:hotbar', function(items)
    Inventory.hotbar = items or {}
    SendNUI({ action = 'hotbar', items = Inventory.hotbar })
end)

RegisterNetEvent('qb-inventory:client:requiredItems', function(items, bool)
    SendNUI({ action = 'requiredItems', items = items or {}, toggle = bool == true })
end)

RegisterNetEvent('qb-inventory:client:giveAnim', function()
    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then return end

    RequestAnimDict('mp_common')
    while not HasAnimDictLoaded('mp_common') do Wait(10) end

    TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 8.0, 1.0, -1, 16, 0, false, false, false)
end)

-- Sent by the server when a move was rejected so the UI never shows a
-- change that did not actually happen on the server.
RegisterNetEvent('qb-inventory:client:updateInventory', function(fromInventory, toInventory, fromItems, toItems, errorSlot)
    if not Inventory.open then return end

    if type(fromItems) == 'table' and fromInventory == 'player' then
        Inventory.items = fromItems
    end

    if type(toItems) == 'table' and toInventory == 'player' then
        Inventory.items = toItems
    end

    SendNUI({
        action = 'refresh',
        inventory = Inventory.items,
        other = Inventory.other,
        player = PlayerCard(),
        errorSlot = errorSlot,
    })

    SendNUI({ action = 'rejectMove', slot = errorSlot })
end)

RegisterNetEvent('qb-inventory:client:CheckWeapon', function(weaponName)
    local ped = PlayerPedId()
    local current = GetSelectedPedWeapon(ped)

    if current == GetHashKey(weaponName or '') then
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    end
end)

-- Legacy `inventory:client:*` aliases --------------------------------------
RegisterNetEvent('inventory:client:openInventory', function(items, other)
    OpenInventoryNUI(items, other)
end)

RegisterNetEvent('inventory:client:closeInv', function()
    CloseInventoryNUI()
end)

RegisterNetEvent('inventory:client:ItemBox', function(itemData, type, amount)
    TriggerEvent('qb-inventory:client:ItemBox', itemData, type, amount)
end)

RegisterNetEvent('inventory:client:hotbar', function(items)
    TriggerEvent('qb-inventory:client:hotbar', items)
end)

RegisterNetEvent('inventory:client:requiredItems', function(items, bool)
    TriggerEvent('qb-inventory:client:requiredItems', items, bool)
end)

RegisterNetEvent('inventory:client:CheckWeapon', function(weaponName)
    TriggerEvent('qb-inventory:client:CheckWeapon', weaponName)
end)

RegisterNetEvent('inventory:client:giveAnim', function()
    TriggerEvent('qb-inventory:client:giveAnim')
end)

-- ===========================================================================
-- Settings pushed by the server (admin lock)
-- ===========================================================================
RegisterNetEvent('qb-inventory:client:applySettings', function(settings, locked)
    if type(settings) ~= 'table' then return end

    CURRENT_SETTINGS = settings

    SendNUI({
        action = 'applySettings',
        settings = settings,
        locked = locked == true,
    })
end)

-- ===========================================================================
-- Drops
-- ===========================================================================
RegisterNetEvent('qb-inventory:client:addDrop', function(dropId, data)
    if type(dropId) ~= 'string' or type(data) ~= 'table' then return end

    Inventory.drops[dropId] = data
end)

RegisterNetEvent('qb-inventory:client:removeDrop', function(dropId)
    if type(dropId) ~= 'string' then return end

    Inventory.drops[dropId] = nil
end)

RegisterNetEvent('qb-inventory:client:syncDrops', function(drops)
    Inventory.drops = type(drops) == 'table' and drops or {}
end)

CreateThread(function()
    while true do
        local sleep = 1000

        if Config.Drops.Enabled then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local nearest, nearestDistance = nil, 9999.0

            for dropId, drop in pairs(Inventory.drops) do
                if drop and type(drop.coords) == 'table' then
                    local distance = #(coords - vector3(drop.coords.x, drop.coords.y, drop.coords.z))

                    if distance < Config.Drops.DrawRange then
                        sleep = 0

                        DrawMarker(
                            2,
                            drop.coords.x, drop.coords.y, drop.coords.z + 0.35,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            0.30, 0.30, 0.30,
                            255, 190, 60, 180,
                            false, false, 2, true, nil, nil, false
                        )
                    end

                    if distance < nearestDistance then
                        nearest, nearestDistance = dropId, distance
                    end
                end
            end

            local showHint = nearest ~= nil and nearestDistance <= Config.Drops.InteractRange

            if showHint ~= Inventory.dropHint then
                Inventory.dropHint = showHint

                ShowDropHint(showHint and '[E] Open drop' or nil)
            end

            if showHint and IsControlJustPressed(0, 38) and not Inventory.open then
                TriggerServerEvent('qb-inventory:server:openDrop', nearest)
            end

            Inventory.nearestDrop = nearest
        end

        Wait(sleep)
    end
end)

-- ===========================================================================
-- Keybinds
-- ===========================================================================
RegisterCommand('codex_inv_open', function()
    if Inventory.open then
        CloseInventoryNUI()
        return
    end

    if Inventory.busy then return end

    local ped = PlayerPedId()

    if IsPedDeadOrDying(ped, true) or IsPauseMenuActive() then return end

    TriggerServerEvent('qb-inventory:server:openSelf')
end, false)

RegisterKeyMapping('codex_inv_open', 'Open the inventory', 'keyboard', Config.Keys.Open)

for index = 1, (Config.HotbarSlots or 5) do
    RegisterCommand(('codex_inv_slot%d'):format(index), function()
        if Inventory.open or Inventory.busy then return end

        local ped = PlayerPedId()
        if IsPedDeadOrDying(ped, true) then return end

        TriggerEvent('qb-inventory:client:useSlot', index)
    end, false)

    RegisterKeyMapping(('codex_inv_slot%d'):format(index),
        ('Use hotbar slot %d'):format(index), 'keyboard', tostring(index))
end

RegisterNetEvent('qb-inventory:client:useSlot', function(slot)
    local index = tonumber(slot)
    if not index then return end

    local items = PlayerData().items or {}
    local item = items[index]

    if type(item) ~= 'table' or not item.name then return end

    -- The server sends the ItemBox when the item is really used, so we do not
    -- fire a second toast here.
    TriggerServerEvent('qb-inventory:server:useItem', { slot = index, name = item.name })
end)

-- ===========================================================================
-- NUI callbacks
-- ===========================================================================
RegisterNUICallback('CloseInventory', function(_, cb)
    CloseInventoryNUI()
    cb({ ok = true })
end)

RegisterNUICallback('UseItem', function(data, cb)
    local slot = tonumber(data and data.slot)

    if not slot then cb({ ok = false }) return end

    local item = Inventory.items[slot]
    local shouldClose = true

    if type(item) == 'table' and item.shouldClose == false then
        shouldClose = false
    end

    -- Weapons are handled by qb-weapons, everything else by the usable item.
    TriggerServerEvent('qb-inventory:server:useItem', { slot = slot, name = data.name })

    if shouldClose then
        CloseInventoryNUI()
    end

    cb({ ok = true })
end)

RegisterNUICallback('DropItem', function(data, cb)
    local slot = tonumber(data and data.slot)
    local amount = tonumber(data and data.amount) or 1

    if not slot then cb({ ok = false }) return end

    TriggerServerEvent('qb-inventory:server:dropItem', slot, amount)
    cb({ ok = true })
end)

RegisterNUICallback('GiveItem', function(data, cb)
    local target = tonumber(data and data.target)
    local slot = tonumber(data and data.slot)
    local amount = tonumber(data and data.amount) or 1

    if not target or not slot then cb({ ok = false }) return end

    QBCore.Functions.TriggerCallback('qb-inventory:server:giveItem', function(success)
        cb({ ok = success == true })
    end, target, data.name, amount, slot)
end)

RegisterNUICallback('SetInventoryData', function(data, cb)
    if type(data) ~= 'table' then cb({ ok = false }) return end

    TriggerServerEvent('qb-inventory:server:SetInventoryData',
        data.fromInventory, data.toInventory,
        data.fromSlot, data.toSlot,
        data.fromAmount, data.toAmount)

    cb({ ok = true })
end)

RegisterNUICallback('AttemptPurchase', function(data, cb)
    QBCore.Functions.TriggerCallback('qb-inventory:server:attemptPurchase', function(success)
        cb({ ok = success == true })
    end, data)
end)

RegisterNUICallback('GetNearbyPlayers', function(_, cb)
    local players = {}
    local coords = GetEntityCoords(PlayerPedId())
    local myId = GetPlayerServerId(PlayerId())

    for _, player in ipairs(GetActivePlayers()) do
        local serverId = GetPlayerServerId(player)

        if serverId ~= myId then
            local ped = GetPlayerPed(player)
            local distance = #(coords - GetEntityCoords(ped))

            if distance <= (Config.OtherPlayer.Range + 1.5) then
                players[#players + 1] = {
                    id = serverId,
                    name = GetPlayerName(serverId) or ('#' .. serverId),
                    distance = math.floor(distance * 10) / 10,
                }
            end
        end
    end

    cb(players)
end)

RegisterNUICallback('PlayDropFail', function(_, cb)
    PlaySound(-1, 'Place_Prop_Fail', 'DLC_Dmod_Prop_Editor_Sounds', 0, 0, 1)
    cb({ ok = true })
end)

RegisterNUICallback('SaveSettings', function(data, cb)
    if type(data) == 'table' and type(data.settings) == 'table' then
        CURRENT_SETTINGS = data.settings

        if data.settings.Layout ~= 'showcase' and PedPreview then
            PedPreview.Stop()
        elseif data.settings.Layout == 'showcase' and PedPreview and Inventory.open then
            PedPreview.Start()
        end

        if data.settings.PedPreview == false and PedPreview then
            PedPreview.Stop()
        end
    end

    cb({ ok = true })
end)

RegisterNUICallback('AdminPush', function(data, cb)
    TriggerServerEvent('qb-inventory:server:adminPush', data and data.settings)
    cb({ ok = true })
end)

RegisterNUICallback('ResetSettings', function(_, cb)
    CURRENT_SETTINGS = Config.Defaults or {}
    TriggerServerEvent('qb-inventory:server:resetSettings')
    SendNUI({ action = 'applySettings', settings = CURRENT_SETTINGS, locked = false })
    cb({ ok = true })
end)

RegisterNUICallback('GetWeaponData', function(data, cb)
    -- Compatibility with scripts that expect the old attachment API.
    cb({ WeaponData = nil, attachments = {} })
end)

RegisterNUICallback('RemoveAttachment', function(data, cb)
    TriggerServerEvent('qb-weapons:server:RemoveAttachment', data and data.AttachmentData, data and data.WeaponData)
    cb({ ok = true })
end)

-- ===========================================================================
-- Exports
-- ===========================================================================
local function ExportHasItem(items, amount)
    local data = PlayerData()
    local inventory = type(data.items) == 'table' and data.items or {}

    if type(items) == 'table' then
        for _, name in pairs(items) do
            local found = false

            for _, item in pairs(inventory) do
                if type(item) == 'table' and item.name == name and
                   (not amount or (tonumber(item.amount) or 0) >= amount) then
                    found = true
                    break
                end
            end

            if not found then return false end
        end

        return true
    end

    for _, item in pairs(inventory) do
        if type(item) == 'table' and item.name == items and
           (not amount or (tonumber(item.amount) or 0) >= amount) then
            return true
        end
    end

    return false
end

exports('HasItem', ExportHasItem)

exports('IsOpen', function()
    return Inventory.open
end)

exports('CloseInventory', CloseInventoryNUI)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    SetNuiFocus(false, false)
    exports['qb-core']:HideText()

    if PedPreview then PedPreview.Stop() end
end)
