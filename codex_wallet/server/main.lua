--[[
    CodeX Wallet - server core (QBCore)

    Everything is server-authoritative: money movement, item movement and
    presentation payloads are validated here. The NUI only ever sends intents.
]]

local RESOURCE = GetCurrentResourceName()

local QBCore = nil

-- runtime state -----------------------------------------------------------------
local cache = {}        -- [serial] = wallet record
local openWallet = {}   -- [source] = serial
local lastAction = {}   -- [source] = os.clock()*1000

-- framework ---------------------------------------------------------------------
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

local function GetPlayer(src)
    if not QBCore then
        return nil
    end

    local ok, player = pcall(function()
        return QBCore.Functions.GetPlayer(src)
    end)

    if ok then
        return player
    end

    return nil
end

local function Notify(src, message, kind)
    if not src or not message then
        return
    end

    TriggerClientEvent('QBCore:Notify', src, message, kind or 'primary')
end

local function FormatMoney(value)
    value = math.floor(tonumber(value) or 0)
    local formatted = tostring(value)
    local k
    while true do
        formatted, k = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

-- rate limiting -----------------------------------------------------------------
local function rateLimited(src)
    local now = (os.clock() * 1000)
    local minimum = tonumber(Config.Security and Config.Security.RateLimitMs) or 250

    if lastAction[src] and (now - lastAction[src]) < minimum then
        return true
    end

    lastAction[src] = now
    return false
end

-- inventory adapters -------------------------------------------------------------
local function InventoryType()
    local mode = (Config.Inventory or 'auto'):lower()

    if mode == 'qb' then
        return 'qb'
    end

    if mode == 'ox' then
        return 'ox'
    end

    local ok, state = pcall(function()
        return GetResourceState('ox_inventory')
    end)

    if ok and state == 'started' then
        return 'ox'
    end

    return 'qb'
end

local function GetItemMeta(item)
    if not item then
        return nil
    end
    return item.info or item.metadata
end

local function ItemBox(src, name, change)
    if not (QBCore and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[name]) then
        return
    end

    pcall(function()
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[name], change)
    end)
end

local function CountInventoryItems(src, name)
    local player = GetPlayer(src)
    if not player then
        return 0
    end

    if InventoryType() == 'ox' then
        local ok, count = pcall(function()
            return exports.ox_inventory:Search(src, 'count', name) or 0
        end)
        return ok and (tonumber(count) or 0) or 0
    end

    local items = (player.PlayerData and player.PlayerData.items) or {}
    local total = 0
    for _, item in pairs(items) do
        if item and item.name == name then
            total = total + (tonumber(item.amount) or tonumber(item.count) or 1)
        end
    end
    return total
end

--- Find the wallet item on a player. Returns item-like table with slot + metadata.
local function FindWalletItem(src)
    local player = GetPlayer(src)
    if not player then
        return nil
    end

    if InventoryType() == 'ox' then
        local ok, items = pcall(function()
            return exports.ox_inventory:Search(src, 'slots', Config.WalletItem)
        end)

        if ok and items then
            for _, item in pairs(items) do
                if item and item.name == Config.WalletItem then
                    return {
                        name = item.name,
                        slot = item.slot,
                        count = item.count or 1,
                        meta = item.metadata or item.info
                    }
                end
            end
        end

        return nil
    end

    local items = (player.PlayerData and player.PlayerData.items) or {}
    for slot, item in pairs(items) do
        if item and item.name == Config.WalletItem then
            return {
                name = item.name,
                slot = item.slot or slot,
                count = item.amount or item.count or 1,
                meta = GetItemMeta(item)
            }
        end
    end

    return nil
end

--- Ensure the wallet item carries a serial in its metadata. Returns the serial.
local function EnsureSerial(src)
    local walletItem = FindWalletItem(src)
    if not walletItem then
        return nil
    end

    local meta = walletItem.meta
    if meta and meta.serial and tostring(meta.serial) ~= '' then
        return tostring(meta.serial)
    end

    -- Generate a fresh serial and write it into the item metadata.
    local serial = ('CXW-%s%s'):format(
        tostring(math.random(0, 0xFFFFFF)),
        tostring(os.time() % 100000)
    )
    serial = serial:gsub('%.', ''):upper()

    local player = GetPlayer(src)
    if not player then
        return nil
    end

    if InventoryType() == 'ox' then
        local ok = pcall(function()
            exports.ox_inventory:SetItemMetadata(src, walletItem.slot, { serial = serial })
        end)
        if ok then
            return serial
        end
        return nil
    end

    -- qb-inventory: rebuild the item so the metadata sticks on every version.
    local removed = pcall(function()
        player.Functions.RemoveItem(Config.WalletItem, 1, walletItem.slot)
    end)

    if not removed then
        return nil
    end

    ItemBox(src, Config.WalletItem, 'remove')

    local added = pcall(function()
        player.Functions.AddItem(Config.WalletItem, 1, false, { serial = serial })
    end)

    if not added then
        -- Put the original back if we could not re-add with metadata.
        pcall(function()
            player.Functions.AddItem(Config.WalletItem, 1, false, meta)
        end)
        return nil
    end

    ItemBox(src, Config.WalletItem, 'add')

    return serial
end

--- Remove one unit of `name` from the player inventory (specific slot preferred).
local function RemoveItem(src, name, slot, count)
    local player = GetPlayer(src)
    if not player then
        return false
    end

    count = tonumber(count) or 1

    if InventoryType() == 'ox' then
        local ok, success = pcall(function()
            return exports.ox_inventory:RemoveItem(src, name, count, nil, slot)
        end)
        return ok and success == true
    end

    local ok, success = pcall(function()
        return player.Functions.RemoveItem(name, count, slot)
    end)

    if ok and success == false then
        return false
    end

    ItemBox(src, name, 'remove')

    return ok
end

--- Add `count` units of `name` with metadata to the player inventory.
local function AddItem(src, name, metadata, count)
    local player = GetPlayer(src)
    if not player then
        return false, 'no_player'
    end

    count = math.max(1, math.floor(tonumber(count) or 1))

    if InventoryType() == 'ox' then
        local ok, success = pcall(function()
            return exports.ox_inventory:AddItem(src, name, count, metadata)
        end)

        if ok and success == true then
            return true
        end

        return false, 'inventory_full'
    end

    local ok, success = pcall(function()
        return player.Functions.AddItem(name, count, false, metadata)
    end)

    if not ok then
        return false, 'error'
    end

    if success == false then
        return false, 'inventory_full'
    end

    ItemBox(src, name, 'add')

    return true
end

--- Remove `amount` units of `name` across all inventory stacks.
local function RemoveItemAmount(src, name, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return false
    end

    local player = GetPlayer(src)
    if not player then
        return false
    end

    if CountInventoryItems(src, name) < amount then
        return false
    end

    if InventoryType() == 'ox' then
        local ok, success = pcall(function()
            return exports.ox_inventory:RemoveItem(src, name, amount)
        end)
        return ok and success == true
    end

    -- qb-inventory: subtract the amount across stacks (lowest slots first).
    local items = (player.PlayerData and player.PlayerData.items) or {}
    local targets = {}

    for slot, item in pairs(items) do
        if item and item.name == name then
            targets[#targets + 1] = {
                slot = item.slot or slot,
                have = tonumber(item.amount) or tonumber(item.count) or 1
            }
        end
    end

    table.sort(targets, function(a, b)
        return a.slot < b.slot
    end)

    local remaining = amount
    for _, target in ipairs(targets) do
        if remaining <= 0 then
            break
        end

        local take = math.min(target.have, remaining)
        local ok, success = pcall(function()
            return player.Functions.RemoveItem(name, take, target.slot)
        end)

        if not ok or success == false then
            return false
        end

        remaining = remaining - take
    end

    ItemBox(src, name, 'remove')

    return remaining <= 0
end

--- Snapshot of storeable items the player currently carries.
local function GetStoreableItems(src)
    local player = GetPlayer(src)
    local result = {}

    if not player then
        return result
    end

    local function push(slot, name, label, description, meta)
        local allowed = Config.AllowedItems[name]
        if not allowed then
            return
        end

        if Config.Wallet.PreventWalletInWallet and name == Config.WalletItem then
            return
        end

        result[#result + 1] = {
            slot = slot,
            name = name,
            label = allowed.label or label or name,
            description = description or '',
            weight = tonumber(allowed.weight) or 50,
            metadata = meta or {}
        }
    end

    if InventoryType() == 'ox' then
        local ok, items = pcall(function()
            return exports.ox_inventory:GetInventoryItems(src)
        end)

        if ok and items then
            for _, item in pairs(items) do
                if item and item.name and (item.count or 1) > 0 then
                    push(item.slot, item.name, item.label, item.description, item.metadata)
                end
            end
        end

        return result
    end

    local items = (player.PlayerData and player.PlayerData.items) or {}
    for slot, item in pairs(items) do
        if item and item.name and (tonumber(item.amount) or tonumber(item.count) or 1) > 0 then
            push(item.slot or slot, item.name, item.label, item.description, GetItemMeta(item))
        end
    end

    return result
end

-- money -------------------------------------------------------------------------
-- Two modes:
--   'item'    - cash is an inventory item: wallet deposits take cash items
--               out of the inventory, withdrawals put cash items back.
--   'account' - classic QBCore money account.
local function MoneyMode()
    return string.lower(tostring((Config.Money and Config.Money.Mode) or 'item'))
end

local function CashItemName()
    return (Config.Money and Config.Money.ItemName) or 'cash'
end

--- Money the player currently holds outside the wallet (deposit source).
local function GetCash(src)
    if MoneyMode() == 'item' then
        return CountInventoryItems(src, CashItemName())
    end

    local player = GetPlayer(src)
    if not player then
        return 0
    end

    local account = (Config.Money and Config.Money.Account) or 'cash'
    local ok, amount = pcall(function()
        return player.Functions.GetMoney(account)
    end)

    return ok and (tonumber(amount) or 0) or 0
end

--- Take money from the player (used by deposits into the wallet).
local function RemoveCash(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return false
    end

    if MoneyMode() == 'item' then
        return RemoveItemAmount(src, CashItemName(), amount)
    end

    local player = GetPlayer(src)
    if not player then
        return false
    end

    local account = (Config.Money and Config.Money.Account) or 'cash'
    local ok, success = pcall(function()
        return player.Functions.RemoveMoney(account, amount, 'wallet-deposit')
    end)

    return ok and success ~= false
end

--- Give money to the player (used by withdrawals from the wallet).
local function AddCash(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return false
    end

    if MoneyMode() == 'item' then
        return (AddItem(src, CashItemName(), nil, amount))
    end

    local player = GetPlayer(src)
    if not player then
        return false
    end

    local account = (Config.Money and Config.Money.Account) or 'cash'
    local ok, success = pcall(function()
        return player.Functions.AddMoney(account, amount, 'wallet-withdraw')
    end)

    return ok and success ~= false
end

-- wallet records -----------------------------------------------------------------
local function GetWallet(serial)
    serial = tostring(serial or '')
    if serial == '' then
        return nil
    end

    if cache[serial] then
        return cache[serial]
    end

    local record = Storage.Load(serial)
    if not record then
        local playerOwner = nil
        record = Storage.Create(serial, playerOwner)
    end

    if record then
        cache[serial] = record
    end

    return record
end

local function SaveWallet(record)
    if not record then
        return false
    end

    local saved = Storage.Save(record)
    return saved
end

local function WalletWeight(record)
    local total = 0
    for _, entry in ipairs(record.items or {}) do
        total = total + (tonumber(entry.weight) or 50)
    end
    return total
end

local function WalletValue(record)
    return tonumber(record.cash) or 0
end

-- payload builders ----------------------------------------------------------------
local function BuildPlayerInfo(src)
    local player = GetPlayer(src)
    if not player then
        return {
            name = 'Unknown',
            citizenid = '',
            job = ''
        }
    end

    local charinfo = player.PlayerData and player.PlayerData.charinfo or {}
    local firstname = charinfo.firstname or 'Unknown'
    local lastname = charinfo.lastname or ''
    local job = player.PlayerData and player.PlayerData.job or {}

    return {
        name = ('%s %s'):format(firstname, lastname):gsub('%s+$', ''),
        citizenid = player.PlayerData and player.PlayerData.citizenid or '',
        job = job.label or job.name or ''
    }
end

local function BuildWalletPayload(src, serial)
    local record = GetWallet(serial)
    if not record then
        return nil
    end

    local items = {}
    for index, entry in ipairs(record.items or {}) do
        items[#items + 1] = {
            index = index,
            name = entry.name,
            label = entry.label or entry.name,
            description = entry.description or '',
            weight = tonumber(entry.weight) or 50,
            metadata = entry.metadata or {},
            storedAt = entry.storedAt
        }
    end

    return {
        serial = record.serial,
        cash = WalletValue(record),
        items = items,
        slotsUsed = #items,
        slotsMax = tonumber(Config.Wallet.Slots) or 8,
        weightUsed = WalletWeight(record),
        weightMax = tonumber(Config.Wallet.MaxWeight) or 2000
    }
end

local function OpenWallet(src, serial)
    serial = serial or EnsureSerial(src)
    if not serial then
        Notify(src, Config.Notifications.NoWallet, 'error')
        return
    end

    local payload = BuildWalletPayload(src, serial)
    if not payload then
        Notify(src, Config.Notifications.NotReady, 'error')
        return
    end

    openWallet[src] = serial

    TriggerClientEvent(RESOURCE .. ':openWallet', src, {
        wallet = payload,
        player = BuildPlayerInfo(src),
        inventory = GetStoreableItems(src),
        brand = Config.Brand,
        limits = {
            minAmount = Config.Money.MinAmount,
            maxAmount = Config.Money.MaxAmount,
            maxBalance = Config.Money.MaxBalance,
            moneyEnabled = Config.Money.Enabled == true,
            moneyMode = MoneyMode(),
            cashItemLabel = Config.Money.ItemLabel or 'Cash',
            inventoryCash = GetCash(src)
        }
    })

    Logger.Debug('open', 'Wallet opened', { source = src, serial = serial })
end

-- validation helpers ---------------------------------------------------------------
local function ValidateAmount(raw, walletCash)
    local amount = tonumber(raw)
    if not amount then
        return nil, Config.Notifications.InvalidAmount
    end

    amount = math.floor(amount)

    local minAmount = tonumber(Config.Money.MinAmount) or 1
    local maxAmount = tonumber(Config.Money.MaxAmount) or 250000

    if amount < minAmount then
        return nil, Config.Notifications.InvalidAmount
    end

    if amount > maxAmount then
        return nil, Config.Notifications.AmountTooHigh
    end

    if walletCash and (tonumber(walletCash) or 0) + amount > (tonumber(Config.Money.MaxBalance) or 1000000) then
        return nil, Config.Notifications.AmountTooHigh
    end

    return amount
end

local function ResolveWallet(src)
    local serial = openWallet[src]
    if serial and cache[serial] then
        return cache[serial], serial
    end

    serial = EnsureSerial(src)
    if not serial then
        return nil, nil
    end

    local record = GetWallet(serial)
    return record, serial
end

-- actions ---------------------------------------------------------------------------
local function ActionDeposit(src, data)
    if not Config.Money.Enabled then
        Notify(src, Config.Notifications.InvalidAmount, 'error')
        return
    end

    local record = ResolveWallet(src)
    if not record then
        Notify(src, Config.Notifications.NoWallet, 'error')
        return
    end

    local amount, err = ValidateAmount(data and data.amount, record.cash)
    if not amount then
        Notify(src, err, 'error')
        return
    end

    if GetCash(src) < amount then
        Notify(src, Config.Notifications.NotEnoughCash, 'error')
        return
    end

    -- Take the money first: if anything fails afterwards the player keeps it.
    if not RemoveCash(src, amount) then
        Notify(src, Config.Notifications.NotEnoughCash, 'error')
        return
    end

    record.cash = (tonumber(record.cash) or 0) + amount

    if not SaveWallet(record) then
        record.cash = (tonumber(record.cash) or 0) - amount
        AddCash(src, amount)
        Notify(src, Config.Notifications.NotReady, 'error')
        return
    end

    Logger.Info('deposit', 'Cash deposited into wallet', {
        source = src,
        serial = record.serial,
        amount = amount,
        walletCash = record.cash
    })

    Notify(src, Config.Notifications.Deposited:format(FormatMoney(amount)), 'success')
    OpenWallet(src, record.serial)
end

local function ActionWithdraw(src, data)
    if not Config.Money.Enabled then
        Notify(src, Config.Notifications.InvalidAmount, 'error')
        return
    end

    local record = ResolveWallet(src)
    if not record then
        Notify(src, Config.Notifications.NoWallet, 'error')
        return
    end

    local amount, err = ValidateAmount(data and data.amount)
    if not amount then
        Notify(src, err, 'error')
        return
    end

    if (tonumber(record.cash) or 0) < amount then
        Notify(src, Config.Notifications.NotEnoughWalletCash, 'error')
        return
    end

    -- Move the money first, only then touch the wallet balance.
    if not AddCash(src, amount) then
        Notify(src, Config.Notifications.NotReady, 'error')
        return
    end

    record.cash = (tonumber(record.cash) or 0) - amount

    if not SaveWallet(record) then
        record.cash = (tonumber(record.cash) or 0) + amount
        RemoveCash(src, amount)
        Notify(src, Config.Notifications.NotReady, 'error')
        return
    end

    Logger.Info('withdraw', 'Cash withdrawn from wallet', {
        source = src,
        serial = record.serial,
        amount = amount,
        walletCash = record.cash
    })

    Notify(src, Config.Notifications.Withdrew:format(FormatMoney(amount)), 'success')
    OpenWallet(src, record.serial)
end

local function ActionStoreItem(src, data)
    local record = ResolveWallet(src)
    if not record then
        Notify(src, Config.Notifications.NoWallet, 'error')
        return
    end

    local slot = data and tonumber(data.slot)
    if not slot then
        Notify(src, Config.Notifications.NothingToStore, 'error')
        return
    end

    local storeable = GetStoreableItems(src)
    local found = nil

    for _, entry in ipairs(storeable) do
        if entry.slot == slot then
            found = entry
            break
        end
    end

    if not found then
        Logger.Warn('store', 'Rejected store: item not storeable', { source = src, slot = slot })
        Notify(src, Config.Notifications.ItemNotAllowed, 'error')
        return
    end

    -- Hard whitelist double-check (payload tamper safety).
    local allowed = Config.AllowedItems[found.name]
    if not allowed then
        Logger.Warn('store', 'Rejected store: item not in whitelist', { source = src, item = found.name })
        Notify(src, Config.Notifications.ItemNotAllowed, 'error')
        return
    end

    if Config.Wallet.PreventWalletInWallet and found.name == Config.WalletItem then
        Logger.Warn('store', 'Rejected store: wallet-in-wallet attempt', { source = src, serial = record.serial })
        Notify(src, Config.Notifications.WalletInWallet, 'error')
        return
    end

    if Config.Wallet.PreventDuplicates then
        for _, entry in ipairs(record.items or {}) do
            if entry.name == found.name then
                Notify(src, Config.Notifications.AlreadyStored, 'error')
                return
            end
        end
    end

    if #(record.items or {}) >= (tonumber(Config.Wallet.Slots) or 8) then
        Notify(src, Config.Notifications.WalletFull, 'error')
        return
    end

    local itemWeight = tonumber(allowed.weight) or tonumber(found.weight) or 50
    if WalletWeight(record) + itemWeight > (tonumber(Config.Wallet.MaxWeight) or 2000) then
        Notify(src, Config.Notifications.WalletTooHeavy, 'error')
        return
    end

    if not RemoveItem(src, found.name, found.slot, 1) then
        Notify(src, Config.Notifications.NothingToStore, 'error')
        return
    end

    record.items = record.items or {}
    record.items[#record.items + 1] = {
        name = found.name,
        label = allowed.label or found.label or found.name,
        description = found.description or '',
        weight = itemWeight,
        metadata = found.metadata or {},
        storedAt = os.time()
    }

    if not SaveWallet(record) then
        -- roll back
        table.remove(record.items, #record.items)
        AddItem(src, found.name, found.metadata)
        Notify(src, Config.Notifications.NotReady, 'error')
        return
    end

    Logger.Info('store', 'Item stored in wallet', {
        source = src,
        serial = record.serial,
        item = found.name
    })

    Notify(src, Config.Notifications.Stored:format(found.label or found.name), 'success')
    OpenWallet(src, record.serial)
end

local function ActionRemoveItem(src, data)
    local record = ResolveWallet(src)
    if not record then
        Notify(src, Config.Notifications.NoWallet, 'error')
        return
    end

    local index = data and tonumber(data.index)
    if not index or not record.items or not record.items[index] then
        Notify(src, Config.Notifications.NothingToStore, 'error')
        return
    end

    local entry = record.items[index]

    local added, reason = AddItem(src, entry.name, entry.metadata)
    if not added then
        Notify(src, Config.Notifications.NoRoomInventory, 'error')
        return
    end

    table.remove(record.items, index)

    if not SaveWallet(record) then
        table.insert(record.items, index, entry)
        Notify(src, Config.Notifications.NotReady, 'error')
        return
    end

    Logger.Info('remove', 'Item removed from wallet', {
        source = src,
        serial = record.serial,
        item = entry.name
    })

    Notify(src, Config.Notifications.Removed:format(entry.label or entry.name), 'success')
    OpenWallet(src, record.serial)
end

local function BuildCardPayload(src, entry)
    local meta = entry.metadata or {}
    local player = GetPlayer(src)
    local charinfo = player and player.PlayerData and player.PlayerData.charinfo or {}

    local firstName = meta.firstname or meta.firstName or charinfo.firstname or 'Unknown'
    local lastName = meta.lastname or meta.lastName or charinfo.lastname or ''
    local birthdate = meta.birthdate or meta.dateofbirth or meta.dob or charinfo.birthdate or ''
    local gender = meta.gender or charinfo.gender or ''
    local nationality = meta.nationality or charinfo.nationality or 'San Andreas'
    local licenseType = meta.type or meta.licensetype or entry.label or entry.name

    return {
        cardType = entry.name,
        label = entry.label or entry.name,
        description = entry.description or '',
        firstName = firstName,
        lastName = lastName,
        birthdate = birthdate,
        gender = gender,
        nationality = nationality,
        licenseType = licenseType,
        serial = meta.serial or meta.credential or '',
        citizenid = player and player.PlayerData and player.PlayerData.citizenid or '',
        issued = meta.issued or os.date('%Y-%m-%d')
    }
end

local function ActionShowItem(src, data)
    if not Config.Presentation.Enabled then
        return
    end

    local record = ResolveWallet(src)
    if not record then
        Notify(src, Config.Notifications.NoWallet, 'error')
        return
    end

    local index = data and tonumber(data.index)
    if not index or not record.items or not record.items[index] then
        Notify(src, Config.Notifications.NothingToStore, 'error')
        return
    end

    local entry = record.items[index]
    local allowed = Config.AllowedItems[entry.name]
    if not allowed or allowed.presentable == false then
        Notify(src, Config.Notifications.ItemNotAllowed, 'error')
        return
    end

    local card = BuildCardPayload(src, entry)

    local presenterName = BuildPlayerInfo(src).name
    local radius = tonumber(Config.Presentation.Radius) or 4.0
    local autoClose = tonumber(Config.Presentation.AutoCloseMs) or 12000

    local myCoords = nil
    if GetPlayerPed and GetEntityCoords then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            myCoords = GetEntityCoords(ped)
        end
    end

    local viewers = {}
    if QBCore and QBCore.Functions and QBCore.Functions.GetPlayers then
        for _, targetId in ipairs(QBCore.Functions.GetPlayers()) do
            local include = false

            if targetId == src then
                include = Config.Presentation.ShowOwnPopupToo == true
            elseif myCoords and GetPlayerPed and GetEntityCoords then
                local targetPed = GetPlayerPed(targetId)
                if targetPed and targetPed ~= 0 then
                    local targetCoords = GetEntityCoords(targetPed)
                    local dx = (targetCoords.x or 0) - (myCoords.x or 0)
                    local dy = (targetCoords.y or 0) - (myCoords.y or 0)
                    local dz = (targetCoords.z or 0) - (myCoords.z or 0)
                    if (dx * dx + dy * dy + dz * dz) <= (radius * radius) then
                        include = true
                    end
                end
            end

            if include then
                viewers[#viewers + 1] = targetId
            end
        end
    end

    for _, targetId in ipairs(viewers) do
        TriggerClientEvent(RESOURCE .. ':presentCard', targetId, card, autoClose, presenterName)
    end

    Logger.Info('present', 'ID card presented from wallet', {
        source = src,
        serial = record.serial,
        item = entry.name,
        viewers = #viewers
    })

    Notify(src, Config.Notifications.Presented:format(entry.label or entry.name), 'success')
end

local function ActionRefresh(src)
    local serial = openWallet[src] or EnsureSerial(src)
    if serial then
        OpenWallet(src, serial)
    end
end

local ACTIONS = {
    deposit = ActionDeposit,
    withdraw = ActionWithdraw,
    storeItem = ActionStoreItem,
    removeItem = ActionRemoveItem,
    showItem = ActionShowItem,
    refresh = ActionRefresh
}

-- events ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':useWallet', function()
    local src = source

    if rateLimited(src) then
        return
    end

    if not FindWalletItem(src) then
        Notify(src, Config.Notifications.NoWallet, 'error')
        Logger.Warn('open', 'Rejected open: player has no wallet item', { source = src })
        return
    end

    OpenWallet(src)
end)

RegisterNetEvent(RESOURCE .. ':action', function(action, data)
    local src = source

    if type(action) ~= 'string' or not ACTIONS[action] then
        Logger.Warn('action', 'Rejected unknown action', { source = src, action = tostring(action) })
        return
    end

    if rateLimited(src) then
        Notify(src, Config.Notifications.Cooldown, 'error')
        return
    end

    -- Every mutation requires the player to still own their wallet item.
    if not FindWalletItem(src) then
        Notify(src, Config.Notifications.NoWallet, 'error')
        Logger.Warn('action', 'Rejected action: player has no wallet item', { source = src, action = action })
        return
    end

    local ok, err = pcall(ACTIONS[action], src, type(data) == 'table' and data or {})

    if not ok then
        Logger.Error('action', 'Wallet action crashed', { source = src, action = action, error = tostring(err) })
        Notify(src, Config.Notifications.NotReady, 'error')
    end
end)

RegisterNetEvent(RESOURCE .. ':closeWallet', function()
    local src = source
    openWallet[src] = nil
end)

-- item use -------------------------------------------------------------------------
local function UseWalletItem(src)
    src = tonumber(src) or src

    if not src or src <= 0 then
        return
    end

    if rateLimited(src) then
        return
    end

    if not FindWalletItem(src) then
        Notify(src, Config.Notifications.NoWallet, 'error')
        return
    end

    OpenWallet(src)
end

CreateThread(function()
    while not TryGetCore() do
        Wait(250)
    end

    Logger.Info('boot', 'CodeX Wallet started', {
        inventory = InventoryType(),
        database = Storage.IsUsingDatabase() and 'oxmysql' or 'memory'
    })

    if QBCore.Functions and QBCore.Functions.CreateUseableItem then
        QBCore.Functions.CreateUseableItem(Config.WalletItem, function(source)
            UseWalletItem(source)
        end)
    end

    if Config.Command and Config.Command ~= '' and Config.Command ~= false then
        RegisterCommand(Config.Command, function(source)
            if source <= 0 then
                print('[codex_wallet] /' .. tostring(Config.Command) .. ' can only be used in-game.')
                return
            end

            if rateLimited(source) then
                return
            end

            if not FindWalletItem(source) then
                Notify(source, Config.Notifications.NoWallet, 'error')
                return
            end

            OpenWallet(source)
        end, false)
    end

    if Config.AdminCommand and Config.AdminCommand ~= '' and Config.AdminCommand ~= false then
        RegisterCommand(Config.AdminCommand, function(source, args)
            if source <= 0 then
                -- console: give to a target id
                local target = tonumber(args[1])
                if not target then
                    print('[codex_wallet] Usage (console): /' .. Config.AdminCommand .. ' <serverId>')
                    return
                end
                GiveTestKit(target)
                return
            end

            local allowed = false

            if IsPlayerAceAllowed and IsPlayerAceAllowed(source, 'codexwallet.admin') then
                allowed = true
            end

            if not allowed and QBCore.Functions.HasPermission then
                local ok, result = pcall(function()
                    return QBCore.Functions.HasPermission(source, 'admin') or QBCore.Functions.HasPermission(source, 'god')
                end)
                allowed = ok and result == true
            end

            if not allowed then
                Notify(source, Config.Notifications.NoPermission, 'error')
                return
            end

            local target = tonumber(args[1]) or source
            GiveTestKit(target)
        end, false)
    end
end)

-- ---------------------------------------------------------------------------
-- Test kit: wallet + cash + sample documents. Used by /wallettest.
-- ---------------------------------------------------------------------------
function GiveTestKit(target)
    local src = tonumber(target) or 0
    if src <= 0 then
        return
    end

    local player = GetPlayer(src)
    if not player then
        Notify(src, Config.Notifications.NotReady, 'error')
        return
    end

    if CountInventoryItems(src, Config.WalletItem) == 0 then
        AddItem(src, Config.WalletItem, { serial = ('CXW-TEST%s'):format(math.random(100000, 999999)) })
    end

    -- Sample documents (skipped silently when the server does not have them).
    local samples = {
        'id_card',
        'driver_license',
        'weaponlicense'
    }

    for _, name in ipairs(samples) do
        if CountInventoryItems(src, name) == 0 then
            local charinfo = player.PlayerData and player.PlayerData.charinfo or {}
            AddItem(src, name, {
                firstname = charinfo.firstname or 'John',
                lastname = charinfo.lastname or 'Doe',
                birthdate = charinfo.birthdate or '1990-01-01',
                gender = charinfo.gender or 0,
                nationality = charinfo.nationality or 'San Andreas',
                type = name == 'id_card' and 'Identification Card' or (name == 'driver_license' and "Driver's License" or 'Weapon License')
            })
        end
    end

    AddCash(src, 5000)

    Logger.Info('testkit', 'Test kit issued', { source = src })
    Notify(src, 'Test kit received: wallet, documents and $5,000 cash.', 'success')
end

-- cleanup ---------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    openWallet[src] = nil
    lastAction[src] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then
        return
    end

    for _, record in pairs(cache) do
        Storage.Save(record)
    end
end)

-- exports ---------------------------------------------------------------------------
exports('OpenWallet', function(source)
    source = tonumber(source) or source
    if source and FindWalletItem(source) then
        OpenWallet(source)
        return true
    end
    return false
end)

exports('GetWalletData', function(serial)
    return GetWallet(serial)
end)

exports('GiveTestKit', function(source)
    GiveTestKit(source)
end)

return {
    OpenWallet = OpenWallet,
    GiveTestKit = GiveTestKit
}
