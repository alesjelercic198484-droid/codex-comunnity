--[[
    Entry point: ESX callbacks, secured events, admin commands.
    No gameplay logic lives here, it only validates the caller and forwards
    the request to the right module.
]]

local Crypto = CodexCrypto
local DB = CodexCryptoDB
local FW = CodexCryptoFW
local WH = CodexCryptoWH
local Market = CodexCryptoMarket
local Shops = CodexCryptoShops
local Rob = CodexCryptoRob
local RESOURCE = GetCurrentResourceName()

local started = false
local actionLocks = {}

-- Forward declaration: referenced by the panelAction callback registered
-- above its implementation. Local to avoid a global name collision.
local HandlePanelAction

--- Prevents a player from spamming two actions at the same time.
local function Lock(source)
    if actionLocks[source] then
        return false
    end
    actionLocks[source] = true
    return true
end

local function Unlock(source)
    actionLocks[source] = nil
end

local function Reply(source, ok, message, notificationType)
    if message and message ~= '' then
        FW.Notify(source, message, notificationType or (ok and 'success' or 'error'))
    end
    return ok
end

--- Distance check against the warehouse entrance or its interior.
local function IsNearWarehouse(source, warehouseId, inside)
    local warehouse = Crypto.GetWarehouseConfig(warehouseId)
    if not warehouse then
        return false
    end

    local interior = Crypto.GetInteriorConfig(warehouse.type)
    local targets = {}

    if inside and interior then
        targets[#targets + 1] = interior.enter
        targets[#targets + 1] = interior.terminal
        targets[#targets + 1] = interior.power
        targets[#targets + 1] = interior.storage
    else
        targets[#targets + 1] = warehouse.entrance
    end

    -- Interiors can be large (60 rigs), keep a generous radius.
    return FW.IsNear(source, targets, inside and 90.0 or 8.0)
end

-- ---------------------------------------------------------------------------
-- BOOT
-- ---------------------------------------------------------------------------
CreateThread(function()
    -- Wait for ESX.
    local attempts = 0
    while not FW.GetESX() and attempts < 120 do
        attempts = attempts + 1
        Wait(250)
    end

    if not FW.GetESX() then
        print(('[%s] ^1es_extended was not found, the resource cannot start.^0'):format(RESOURCE))
        return
    end

    if not DB.Init() then
        return
    end

    WH.Load()
    WH.LoadKeys()
    Market.Load()
    WH.CatchUp()
    WH.Flush(true)
    Market.Start()
    WH.StartLoop()

    started = true
    print(('[%s] ^2Started. %d warehouses, BTC at %s.^0'):format(RESOURCE, #(Config.Warehouses or {}), Crypto.FormatMoney(Market.GetPrice())))
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then
        return
    end

    if started then
        WH.Flush(true)
    end

    -- Never leave a player stuck in a private bucket after a restart.
    for _, playerId in ipairs(GetPlayers() or {}) do
        pcall(WH.SetPlayerBucket, tonumber(playerId), nil)
    end
end)

AddEventHandler('playerDropped', function()
    local source = source
    WH.RemoveViewer(source)
    Rob.OnPlayerDropped(source)
    Unlock(source)
end)

-- A player who reconnects must never stay stuck in a warehouse bucket: the
-- interior props are client side and are gone after the reconnect.
AddEventHandler('esx:playerLoaded', function(playerId)
    local source = tonumber(playerId)

    if source then
        WH.RemoveViewer(source)
        WH.SetPlayerBucket(source, nil)
    end
end)

-- ---------------------------------------------------------------------------
-- GPU STORAGE
-- ---------------------------------------------------------------------------
-- The wooden crate inside the interior is a real storage. With ox_inventory
-- it opens a registered stash chest; with the classic ESX inventory it is a
-- "store all / take all" transfer persisted in the `gpu_stock` column.
local function HandleStorageAction(source, warehouseId)
    if not started or (Config.Storage and Config.Storage.Enabled == false) then
        return nil
    end

    local identifier = FW.GetIdentifier(source)
    local warehouse = Crypto.GetWarehouseConfig(warehouseId)

    if not identifier or not warehouse or not WH.Get(warehouseId) then
        return nil
    end

    if not WH.HasAccess(identifier, warehouseId) then
        Reply(source, false, Crypto.L('no_access'))
        return nil
    end

    if not IsNearWarehouse(source, warehouseId, true) then
        Reply(source, false, Crypto.L('too_far'))
        return nil
    end

    -- ox_inventory: a proper chest opened on the client.
    if FW.GetInventoryType() == 'ox_inventory' and FW.IsStarted('ox_inventory') then
        local stashId = ('codexcrypto_storage_%s'):format(warehouseId)

        pcall(function()
            exports.ox_inventory:RegisterStash(
                stashId,
                (Config.Storage and Config.Storage.Label) or 'GPU storage',
                Crypto.ToInt(Config.Storage and Config.Storage.Slots, 40),
                Crypto.ToNumber(Config.Storage and Config.Storage.MaxWeight, 250000),
                false)
        end)

        return { ok = true, mode = 'stash', stashId = stashId }
    end

    -- Classic ESX inventory: deposit everything you carry, otherwise take
    -- from the stock (as much as fits).
    local carried = FW.GetItemCount(source, 'gpu')
    local stock = WH.GetGpuStock(warehouseId)

    if carried > 0 then
        if not FW.RemoveItem(source, 'gpu', carried) then
            Reply(source, false, Crypto.L('storage_failed'))
            return nil
        end

        WH.SetGpuStock(warehouseId, stock + carried)
        Reply(source, true, Crypto.L('storage_deposited', carried, stock + carried))

        return { ok = true, mode = 'esx', action = 'deposited', count = carried, stock = stock + carried }
    end

    if stock <= 0 then
        Reply(source, false, Crypto.L('storage_empty'))
        return nil
    end

    local amount = stock
    while amount > 0 and not FW.CanCarry(source, 'gpu', amount) do
        amount = amount - 1
    end

    if amount <= 0 or not FW.AddItem(source, 'gpu', amount) then
        Reply(source, false, Crypto.L('storage_cannot_carry'))
        return nil
    end

    WH.SetGpuStock(warehouseId, stock - amount)
    Reply(source, true, Crypto.L('storage_withdrew', amount, stock - amount))

    return { ok = true, mode = 'esx', action = 'withdrew', count = amount, stock = stock - amount }
end

-- ---------------------------------------------------------------------------
-- CALLBACKS
-- ---------------------------------------------------------------------------
local function RegisterCallback(name, handler)
    local ESX = FW.GetESX()
    if not ESX then
        return
    end

    ESX.RegisterServerCallback(RESOURCE .. ':' .. name, handler)
end

CreateThread(function()
    while not FW.GetESX() do
        Wait(200)
    end

    -- Bootstrap data sent to every client when it joins.
    RegisterCallback('bootstrap', function(source, cb)
        local identifier = FW.GetIdentifier(source)
        local owned = {}
        local accessible = {}

        for warehouseId, state in pairs(WH.state) do
            if state.owner == identifier then
                owned[#owned + 1] = warehouseId
            elseif identifier and state.keys[identifier] then
                accessible[#accessible + 1] = warehouseId
            end
        end

        cb({
            ready = started,
            owned = owned,
            accessible = accessible,
            market = Market.GetState(),
            locale = Config.Locale
        })
    end)

    -- Full warehouse snapshot, used when opening the panel.
    RegisterCallback('getWarehouse', function(source, cb, warehouseId)
        local identifier = FW.GetIdentifier(source)

        if not started or not identifier or not WH.Get(warehouseId) then
            return cb(nil)
        end

        if not WH.HasAccess(identifier, warehouseId) then
            return cb(nil)
        end

        WH.AddViewer(warehouseId, source)
        cb(WH.Serialize(warehouseId, identifier))
    end)

    -- Everything the client needs to build the interior (rigs + access).
    RegisterCallback('enterWarehouse', function(source, cb, warehouseId)
        local identifier = FW.GetIdentifier(source)
        local state = WH.Get(warehouseId)

        if not started or not identifier or not state then
            return cb(nil)
        end

        local isRobbery = Rob.IsActive(warehouseId) and Rob.active[warehouseId].source == source

        if not WH.HasAccess(identifier, warehouseId) and not isRobbery then
            return cb(nil)
        end

        if not IsNearWarehouse(source, warehouseId, false) then
            return cb(nil)
        end

        WH.AddViewer(warehouseId, source)

        -- Isolate the player: several warehouses share the same base game
        -- interior, the bucket keeps each session private.
        WH.SetPlayerBucket(source, warehouseId)

        cb({
            warehouse = WH.Serialize(warehouseId, identifier),
            robbery = isRobbery,
            lootable = isRobbery and Rob.GetLootableRigs(source, warehouseId) or nil,
            bucket = Config.Routing and Config.Routing.Enabled ~= false and true or false
        })
    end)

    RegisterCallback('getBrokerList', function(source, cb)
        local identifier = FW.GetIdentifier(source)
        cb({
            list = Shops.GetBrokerList(identifier),
            owned = WH.CountOwned(identifier),
            max = Crypto.ToInt(Config.Broker.MaxPerPlayer, 2)
        })
    end)

    RegisterCallback('getShop', function(source, cb, shop)
        local catalog, shopConfig = Shops.GetCatalog(shop)

        if not shopConfig or shopConfig.Enabled == false then
            return cb(nil)
        end

        local entries = {}
        for index, entry in ipairs(catalog) do
            entries[#entries + 1] = {
                index = index,
                item = FW.Item(entry.item),
                label = entry.label or entry.item,
                price = Crypto.ToInt(entry.price, 0),
                sellPrice = shop == 'techshop' and math.floor(Crypto.ToNumber(entry.price, 0) * Crypto.Clamp(Crypto.ToNumber(Config.TechShop.SellRatio, 0.45), 0.0, 1.0)) or nil,
                owned = FW.GetItemCount(source, entry.item)
            }
        end

        cb({
            shop = shop,
            entries = entries,
            canSell = shop == 'techshop',
            maxQuantity = Crypto.ToInt(shopConfig.MaxQuantity, 10),
            account = shopConfig.Account or Config.Money.BuyAccount
        })
    end)

    -- Single entry point for every panel action.
    RegisterCallback('storageAction', function(source, cb, warehouseId)
        if not Lock(source) then
            return cb({ ok = false, message = Crypto.L('busy') })
        end

        local ok, result = pcall(HandleStorageAction, source, warehouseId)

        Unlock(source)

        if not ok then
            print(('[%s] storageAction error: %s'):format(RESOURCE, result))
            return cb({ ok = false, message = Crypto.L('failed') })
        end

        cb(result)
    end)

    RegisterCallback('panelAction', function(source, cb, payload)
        if type(payload) ~= 'table' then
            return cb({ ok = false, message = Crypto.L('invalid_action') })
        end

        if not Lock(source) then
            return cb({ ok = false, message = Crypto.L('busy') })
        end

        local ok, result = pcall(function()
            return HandlePanelAction(source, payload)
        end)

        Unlock(source)

        if not ok then
            print(('[%s] panelAction error: %s'):format(RESOURCE, result))
            return cb({ ok = false, message = Crypto.L('failed') })
        end

        cb(result)
    end)

    RegisterCallback('shopAction', function(source, cb, payload)
        if type(payload) ~= 'table' then
            return cb({ ok = false, message = Crypto.L('invalid_action') })
        end

        if not Lock(source) then
            return cb({ ok = false, message = Crypto.L('busy') })
        end

        local action = payload.action
        local ok, success, message = pcall(function()
            if action == 'buy' then
                return Shops.Buy(source, payload.shop, payload.index, payload.quantity)
            elseif action == 'sell' then
                return Shops.Sell(source, payload.index, payload.quantity)
            elseif action == 'buyWarehouse' then
                return Shops.BuyWarehouse(source, payload.warehouseId)
            elseif action == 'sellWarehouse' then
                return Shops.SellWarehouse(source, payload.warehouseId)
            elseif action == 'informant' then
                return Shops.BuyInformation(source)
            end

            return false, Crypto.L('invalid_action')
        end)

        Unlock(source)

        if not ok then
            print(('[%s] shopAction error: %s'):format(RESOURCE, success))
            return cb({ ok = false, message = Crypto.L('failed') })
        end

        Reply(source, success, message)
        cb({ ok = success == true, message = message })
    end)

    RegisterCallback('startRobbery', function(source, cb, warehouseId)
        if not Lock(source) then
            return cb({ ok = false, message = Crypto.L('busy') })
        end

        local ok, success, message = pcall(Rob.Start, source, warehouseId)
        Unlock(source)

        if not ok then
            print(('[%s] startRobbery error: %s'):format(RESOURCE, success))
            return cb({ ok = false, message = Crypto.L('failed') })
        end

        Reply(source, success, message)
        cb({ ok = success == true, message = message })
    end)

    RegisterCallback('canStartRobbery', function(source, cb, warehouseId)
        local ok, success, message = pcall(Rob.CanStart, source, warehouseId)

        if not ok then
            return cb({ ok = false, message = Crypto.L('failed') })
        end

        cb({ ok = success == true, message = message })
    end)

    RegisterCallback('lootRig', function(source, cb, warehouseId, rigId)
        if not Lock(source) then
            return cb({ ok = false, message = Crypto.L('busy') })
        end

        local ok, success, message = pcall(Rob.LootRig, source, warehouseId, rigId)
        Unlock(source)

        if not ok then
            print(('[%s] lootRig error: %s'):format(RESOURCE, success))
            return cb({ ok = false, message = Crypto.L('failed') })
        end

        Reply(source, success, message)
        cb({ ok = success == true, message = message })
    end)
end)

-- ---------------------------------------------------------------------------
-- PANEL ACTIONS
-- ---------------------------------------------------------------------------
--- Shared guard for every action performed from inside a warehouse.
local function ResolveAccess(source, warehouseId, ownerOnly)
    local identifier = FW.GetIdentifier(source)
    local state = WH.Get(warehouseId)

    if not started then
        return nil, nil, Crypto.L('not_ready')
    end

    if not identifier or not state then
        return nil, nil, Crypto.L('invalid_action')
    end

    if ownerOnly then
        if state.owner ~= identifier then
            return nil, nil, Crypto.L('not_owner')
        end
    elseif not WH.HasAccess(identifier, warehouseId) then
        return nil, nil, Crypto.L('no_access')
    end

    if not IsNearWarehouse(source, warehouseId, true) then
        return nil, nil, Crypto.L('too_far')
    end

    return identifier, state, nil
end

local Actions = {}

Actions.installRig = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    local slot = WH.GetFreeSlot(payload.warehouseId)
    if not slot then
        return { ok = false, message = Crypto.L('rig_full') }
    end

    local price = Crypto.ToInt(Config.Mining.RigPrice, 9000)
    if not FW.RemoveMoney(source, price, Config.Money.BuyAccount) then
        return { ok = false, message = Crypto.L('no_money') }
    end

    local rig = WH.AddRig(payload.warehouseId, slot)
    if not rig then
        FW.AddMoney(source, price, Config.Money.BuyAccount)
        return { ok = false, message = Crypto.L('rig_full') }
    end

    WH.MarkWarehouseDirty(payload.warehouseId)
    WH.Sync(payload.warehouseId)

    FW.Log('warehouse', 'Rig installed', ('%s installed a rig in %s'):format(FW.GetName(source), WH.GetLabel(payload.warehouseId)), {
        { name = 'Price', value = Crypto.FormatMoney(price) },
        { name = 'Slot', value = tostring(slot) }
    })

    return { ok = true, message = Crypto.L('rig_installed') }
end

Actions.removeRig = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    local rig = WH.GetRig(payload.warehouseId, Crypto.ToInt(payload.rigId, 0))
    if not rig then
        return { ok = false, message = Crypto.L('rig_not_found') }
    end

    if Crypto.ToInt(rig.gpus, 0) > 0 then
        return { ok = false, message = Crypto.L('rig_not_empty') }
    end

    WH.RemoveRig(payload.warehouseId, rig.id)

    local refund = math.floor(Crypto.ToNumber(Config.Mining.RigPrice, 9000) * Crypto.Clamp(Crypto.ToNumber(Config.Mining.RigSellRatio, 0.4), 0.0, 1.0))
    if refund > 0 then
        FW.AddMoney(source, refund, Config.Money.SellAccount)
    end

    WH.MarkWarehouseDirty(payload.warehouseId)
    WH.Sync(payload.warehouseId)

    return { ok = true, message = Crypto.L('rig_removed') }
end

Actions.installGpu = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, false)
    if err then
        return { ok = false, message = err }
    end

    local rig = WH.GetRig(payload.warehouseId, Crypto.ToInt(payload.rigId, 0))
    if not rig then
        return { ok = false, message = Crypto.L('rig_not_found') }
    end

    local maxGpus = Crypto.GetMaxGpus()
    local free = maxGpus - Crypto.ToInt(rig.gpus, 0)

    if free <= 0 then
        return { ok = false, message = Crypto.L('gpu_full') }
    end

    local quantity = Crypto.Clamp(Crypto.ToInt(payload.quantity, 1), 1, free)
    quantity = math.floor(quantity)

    if FW.GetItemCount(source, 'gpu') < quantity then
        return { ok = false, message = Crypto.L('gpu_missing') }
    end

    if not FW.RemoveItem(source, 'gpu', quantity) then
        return { ok = false, message = Crypto.L('gpu_missing') }
    end

    rig.gpus = Crypto.ToInt(rig.gpus, 0) + quantity
    WH.MarkRigDirty(rig)
    WH.MarkWarehouseDirty(payload.warehouseId)
    WH.Sync(payload.warehouseId)

    return { ok = true, message = Crypto.L('gpu_installed') }
end

Actions.removeGpu = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, false)
    if err then
        return { ok = false, message = err }
    end

    local rig = WH.GetRig(payload.warehouseId, Crypto.ToInt(payload.rigId, 0))
    if not rig then
        return { ok = false, message = Crypto.L('rig_not_found') }
    end

    local available = Crypto.ToInt(rig.gpus, 0)
    if available <= 0 then
        return { ok = false, message = Crypto.L('gpu_none') }
    end

    local quantity = math.floor(Crypto.Clamp(Crypto.ToInt(payload.quantity, 1), 1, available))

    if not FW.CanCarry(source, 'gpu', quantity) then
        return { ok = false, message = Crypto.L('no_space') }
    end

    rig.gpus = available - quantity

    if not FW.AddItem(source, 'gpu', quantity) then
        rig.gpus = available
        return { ok = false, message = Crypto.L('failed') }
    end

    WH.MarkRigDirty(rig)
    WH.MarkWarehouseDirty(payload.warehouseId)
    WH.Sync(payload.warehouseId)

    return { ok = true, message = Crypto.L('gpu_removed') }
end

Actions.upgradeCpu = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    local rig = WH.GetRig(payload.warehouseId, Crypto.ToInt(payload.rigId, 0))
    if not rig then
        return { ok = false, message = Crypto.L('rig_not_found') }
    end

    local maxLevel = Crypto.ToInt(Config.Mining.Cpu.MaxLevel, 3)
    if Crypto.ToInt(rig.cpu, 0) >= maxLevel then
        return { ok = false, message = Crypto.L('cpu_max') }
    end

    -- The player can either use a CPU item or pay the price.
    local usedItem = FW.GetItemCount(source, 'cpu') > 0 and FW.RemoveItem(source, 'cpu', 1)

    if not usedItem then
        local price = Crypto.ToInt(Config.Mining.Cpu.Price, 4500)
        if not FW.RemoveMoney(source, price, Config.Money.BuyAccount) then
            return { ok = false, message = Crypto.L('no_money') }
        end
    end

    rig.cpu = Crypto.ToInt(rig.cpu, 0) + 1
    WH.MarkRigDirty(rig)
    WH.Sync(payload.warehouseId)

    return { ok = true, message = Crypto.L('cpu_installed', rig.cpu) }
end

Actions.upgradeCooler = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    local rig = WH.GetRig(payload.warehouseId, Crypto.ToInt(payload.rigId, 0))
    if not rig then
        return { ok = false, message = Crypto.L('rig_not_found') }
    end

    local maxLevel = Crypto.ToInt(Config.Mining.Cooler.MaxLevel, 3)
    if Crypto.ToInt(rig.cooler, 0) >= maxLevel then
        return { ok = false, message = Crypto.L('cooler_max') }
    end

    local usedItem = FW.GetItemCount(source, 'cooler') > 0 and FW.RemoveItem(source, 'cooler', 1)

    if not usedItem then
        local price = Crypto.ToInt(Config.Mining.Cooler.Price, 3800)
        if not FW.RemoveMoney(source, price, Config.Money.BuyAccount) then
            return { ok = false, message = Crypto.L('no_money') }
        end
    end

    rig.cooler = Crypto.ToInt(rig.cooler, 0) + 1
    WH.MarkRigDirty(rig)
    WH.Sync(payload.warehouseId)

    return { ok = true, message = Crypto.L('cooler_installed', rig.cooler) }
end

Actions.repairRig = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, false)
    if err then
        return { ok = false, message = err }
    end

    local rig = WH.GetRig(payload.warehouseId, Crypto.ToInt(payload.rigId, 0))
    if not rig then
        return { ok = false, message = Crypto.L('rig_not_found') }
    end

    if not rig.broken and Crypto.ToNumber(rig.durability, 100) >= 100.0 then
        return { ok = false, message = Crypto.L('invalid_action') }
    end

    if not FW.RemoveItem(source, 'repairkit', 1) then
        return { ok = false, message = Crypto.L('repairkit_missing') }
    end

    rig.durability = Crypto.Clamp(Crypto.ToNumber(rig.durability, 0) + Crypto.ToNumber(Config.Mining.Durability.RepairAmount, 50), 0.0, 100.0)
    rig.broken = false

    WH.MarkRigDirty(rig)
    WH.Sync(payload.warehouseId)

    return { ok = true, message = Crypto.L('rig_repaired', math.floor(rig.durability)) }
end

Actions.sellBtc = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    local available = Crypto.ToNumber(state.btc, 0)
    if available <= 0 then
        return { ok = false, message = Crypto.L('market_empty') }
    end

    local amount = Crypto.ToNumber(payload.amount, 0)
    if payload.all == true or amount <= 0 then
        amount = available
    end

    amount = math.min(amount, available)

    if amount <= 0 then
        return { ok = false, message = Crypto.L('market_empty') }
    end

    local price = Market.GetPrice()
    local payout = Crypto.GetSellValue(amount, price)

    if payout <= 0 then
        return { ok = false, message = Crypto.L('market_empty') }
    end

    state.btc = math.max(0.0, available - amount)
    state.totalEarned = Crypto.ToInt(state.totalEarned, 0) + payout

    FW.AddMoney(source, payout, Config.Money.SellAccount)
    WH.MarkWarehouseDirty(payload.warehouseId)
    WH.SaveWarehouse(payload.warehouseId)
    WH.Sync(payload.warehouseId)

    FW.Log('market', 'BTC sold', ('%s sold %s BTC'):format(FW.GetName(source), Crypto.FormatBtc(amount)), {
        { name = 'Warehouse', value = WH.GetLabel(payload.warehouseId) },
        { name = 'Rate', value = Crypto.FormatMoney(price) },
        { name = 'Payout', value = Crypto.FormatMoney(payout) }
    })

    return { ok = true, message = Crypto.L('market_sold', Crypto.FormatBtc(amount), Crypto.FormatMoney(payout)) }
end

Actions.payBill = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    local bill = math.floor(Crypto.ToNumber(state.bill, 0))
    if bill <= 0 then
        return { ok = false, message = Crypto.L('power_nothing') }
    end

    if not FW.RemoveMoney(source, bill, Config.Electricity.Account or Config.Money.BuyAccount) then
        return { ok = false, message = Crypto.L('no_money') }
    end

    state.bill = 0
    state.billFraction = 0.0

    local restored = false
    if not state.powered then
        state.powered = true
        restored = true
    end

    WH.MarkWarehouseDirty(payload.warehouseId)
    WH.SaveWarehouse(payload.warehouseId)
    WH.Sync(payload.warehouseId)

    FW.Log('warehouse', 'Bill paid', ('%s paid the bill of %s'):format(FW.GetName(source), WH.GetLabel(payload.warehouseId)), {
        { name = 'Amount', value = Crypto.FormatMoney(bill) }
    })

    if restored then
        FW.Notify(source, Crypto.L('power_restored', WH.GetLabel(payload.warehouseId)), 'success')
    end

    return { ok = true, message = Crypto.L('power_paid', Crypto.FormatMoney(bill)) }
end

Actions.togglePower = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    -- The power cannot be switched back on while the bill is unpaid.
    if not state.powered then
        local maxDebt = Crypto.ToNumber(Config.Electricity.MaxDebt, 0)
        if maxDebt > 0 and Crypto.ToNumber(state.bill, 0) >= maxDebt then
            return { ok = false, message = Crypto.L('power_cut', WH.GetLabel(payload.warehouseId)) }
        end
    end

    state.powered = not state.powered
    state.lastTick = os.time()

    WH.MarkWarehouseDirty(payload.warehouseId)
    WH.Sync(payload.warehouseId)

    return { ok = true, message = state.powered and Crypto.L('power_restored', WH.GetLabel(payload.warehouseId)) or Crypto.L('power_off') }
end

Actions.toggleLock = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, false)
    if err then
        return { ok = false, message = err }
    end

    state.locked = not state.locked
    WH.MarkWarehouseDirty(payload.warehouseId)
    WH.Sync(payload.warehouseId)

    return { ok = true, message = state.locked and Crypto.L('warehouse_locked') or Crypto.L('warehouse_enter') }
end

Actions.giveKeys = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    local targetId = Crypto.ToInt(payload.target, 0)
    local targetPlayer = FW.GetPlayer(targetId)

    if not targetPlayer or targetId == source then
        return { ok = false, message = Crypto.L('keys_no_player') }
    end

    -- Distance check between the two players (skipped without OneSync).
    if FW.IsOneSyncAvailable() then
        local targetPed = GetPlayerPed(targetId)

        if targetPed and targetPed ~= 0 then
            if not FW.IsNear(source, GetEntityCoords(targetPed), 8.0) then
                return { ok = false, message = Crypto.L('keys_no_player') }
            end
        end
    end

    local targetName = FW.GetName(targetId)
    WH.GiveKey(payload.warehouseId, targetPlayer.identifier, targetName)
    WH.Sync(payload.warehouseId)

    FW.Notify(targetId, Crypto.L('keys_received', WH.GetLabel(payload.warehouseId)), 'success')

    return { ok = true, message = Crypto.L('keys_given', targetName) }
end

Actions.removeKeys = function(source, payload)
    local identifier, state, err = ResolveAccess(source, payload.warehouseId, true)
    if err then
        return { ok = false, message = err }
    end

    local targetIdentifier = tostring(payload.identifier or '')
    if targetIdentifier == '' or not state.keys[targetIdentifier] then
        return { ok = false, message = Crypto.L('invalid_action') }
    end

    local name = state.keys[targetIdentifier]
    WH.RemoveKey(payload.warehouseId, targetIdentifier)
    WH.Sync(payload.warehouseId)

    FW.NotifyIdentifier(targetIdentifier, Crypto.L('keys_lost', WH.GetLabel(payload.warehouseId)), 'error')

    return { ok = true, message = Crypto.L('keys_removed', name) }
end

HandlePanelAction = function(source, payload)
    local handler = Actions[payload.action]

    if not handler then
        return { ok = false, message = Crypto.L('invalid_action') }
    end

    local result = handler(source, payload) or { ok = false, message = Crypto.L('failed') }

    if result.message then
        FW.Notify(source, result.message, result.ok and 'success' or 'error')
    end

    return result
end

-- ---------------------------------------------------------------------------
-- EVENTS
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':leaveWarehouse', function()
    local source = source
    WH.RemoveViewer(source)
    -- Always put the player back in the main world.
    WH.SetPlayerBucket(source, nil)
end)

RegisterNetEvent(RESOURCE .. ':cancelRobbery', function()
    Rob.Cancel(source)
end)

-- ---------------------------------------------------------------------------
-- ADMIN
-- ---------------------------------------------------------------------------
if Config.Commands and Config.Commands.Admin then
    RegisterCommand(Config.Commands.Admin, function(source, args)
        local permission = Config.Commands.AcePermission or 'codex_cryptomining.admin'

        if source > 0 and not IsPlayerAceAllowed(source, permission) then
            FW.Notify(source, Crypto.L('admin_only'), 'error')
            return
        end

        local function output(message)
            if source > 0 then
                FW.Notify(source, message, 'inform')
            else
                print(('[%s] %s'):format(RESOURCE, message))
            end
        end

        local sub = (args[1] or ''):lower()

        if sub == 'price' then
            local value = Crypto.ToInt(args[2], 0)

            if value > 0 then
                Market.price = math.floor(Crypto.Clamp(value, Config.Market.MinPrice, Config.Market.MaxPrice))
                Market.Update(true)
            end

            output(Crypto.L('market_price', Crypto.FormatMoney(Market.GetPrice())))
        elseif sub == 'reset' then
            local warehouseId = args[2]

            if not warehouseId or not WH.Get(warehouseId) then
                output(Crypto.L('admin_unknown'))
                return
            end

            WH.Reset(warehouseId, false)
            output(Crypto.L('admin_reset', warehouseId))

            FW.Log('admin', 'Warehouse reset', ('%s reset %s'):format(source > 0 and FW.GetName(source) or 'console', warehouseId))
        elseif sub == 'setowner' then
            local warehouseId = args[2]
            local targetId = Crypto.ToInt(args[3], 0)
            local targetPlayer = FW.GetPlayer(targetId)

            if not warehouseId or not WH.Get(warehouseId) then
                output(Crypto.L('admin_unknown'))
                return
            end

            if not targetPlayer then
                output(Crypto.L('keys_no_player'))
                return
            end

            WH.Reset(warehouseId, false)
            WH.SetOwner(warehouseId, targetPlayer.identifier, FW.GetName(targetId))
            output(('%s -> %s'):format(warehouseId, FW.GetName(targetId)))

            FW.Log('admin', 'Owner changed', ('%s is now the owner of %s'):format(FW.GetName(targetId), warehouseId))
        elseif sub == 'info' then
            for warehouseId, state in pairs(WH.state) do
                output(('%s | owner: %s | rigs: %d | gpus: %d | btc: %s | bill: %s | power: %s'):format(
                    warehouseId,
                    tostring(state.ownerName or state.owner or '-'),
                    Crypto.TableCount(state.rigs),
                    WH.CountGpus(warehouseId),
                    Crypto.FormatBtc(state.btc),
                    Crypto.FormatMoney(state.bill),
                    state.powered and 'on' or 'off'
                ))
            end
        else
            output(Crypto.L('admin_usage', Config.Commands.Admin))
        end
    end, false)
end

-- ---------------------------------------------------------------------------
-- EXPORTS
-- ---------------------------------------------------------------------------
exports('getBitcoinPrice', function()
    return Market.GetPrice()
end)

exports('getWarehouseOwner', function(warehouseId)
    local state = WH.Get(warehouseId)
    return state and state.owner or nil
end)

exports('getWarehouseBalance', function(warehouseId)
    local state = WH.Get(warehouseId)
    return state and Crypto.Round(state.btc, 8) or 0
end)

exports('isRobberyActive', function(warehouseId)
    return CodexCryptoRob.IsActive(warehouseId)
end)
