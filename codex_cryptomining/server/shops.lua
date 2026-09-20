--[[
    Shops: TechShop, black market, informant, real estate broker.
    Every price is read from the config on the server, the client only sends
    an index and a quantity.
]]

CodexCryptoShops = CodexCryptoShops or {}

local Shops = CodexCryptoShops
local Crypto = CodexCrypto
local FW = CodexCryptoFW
local WH = CodexCryptoWH
local RESOURCE = GetCurrentResourceName()

local informantCooldowns = {}

--- Distance guard for every shop. Delegates to the OneSync aware helper so a
--- server without OneSync does not lock players out of the shops.
local function DistanceOk(source, locations, extra)
    if not locations or #locations == 0 then
        return true
    end

    return FW.IsNear(source, locations, (extra or 0.0) + 6.0)
end

Shops.DistanceOk = DistanceOk

function Shops.GetCatalog(shop)
    if shop == 'techshop' then
        return Config.TechShop.Buy or {}, Config.TechShop
    end

    if shop == 'blackmarket' then
        return Config.BlackMarket.Buy or {}, Config.BlackMarket
    end

    return {}, nil
end

--- Buys `quantity` of catalog entry `index` from `shop`.
function Shops.Buy(source, shop, index, quantity)
    local catalog, shopConfig = Shops.GetCatalog(shop)

    if not shopConfig or shopConfig.Enabled == false then
        return false, Crypto.L('invalid_action')
    end

    local entry = catalog[Crypto.ToInt(index, 0)]
    if not entry then
        return false, Crypto.L('invalid_action')
    end

    quantity = Crypto.ToInt(quantity, 1)
    local maxQuantity = math.max(1, Crypto.ToInt(shopConfig.MaxQuantity, 10))

    if quantity < 1 or quantity > maxQuantity then
        return false, Crypto.L('shop_quantity')
    end

    if not DistanceOk(source, shopConfig.Locations) then
        return false, Crypto.L('too_far')
    end

    local price = math.floor(Crypto.ToNumber(entry.price, 0) * quantity)
    local account = shopConfig.Account or Config.Money.BuyAccount

    if not FW.CanAfford(source, price, account) then
        return false, Crypto.L('no_money')
    end

    if not FW.CanCarry(source, entry.item, quantity) then
        return false, Crypto.L('no_space')
    end

    if not FW.RemoveMoney(source, price, account) then
        return false, Crypto.L('no_money')
    end

    if not FW.AddItem(source, entry.item, quantity) then
        -- Refund, the player never received the item.
        FW.AddMoney(source, price, account)
        return false, Crypto.L('failed')
    end

    FW.Log('shop', 'Purchase', ('%s bought %sx %s'):format(FW.GetName(source), quantity, entry.label or entry.item), {
        { name = 'Shop', value = shop },
        { name = 'Price', value = Crypto.FormatMoney(price) }
    })

    return true, Crypto.L('shop_bought', quantity, entry.label or entry.item, Crypto.FormatMoney(price))
end

--- Sells items back to the TechShop.
function Shops.Sell(source, index, quantity)
    if Config.TechShop.Enabled == false then
        return false, Crypto.L('invalid_action')
    end

    local entry = (Config.TechShop.Buy or {})[Crypto.ToInt(index, 0)]
    if not entry then
        return false, Crypto.L('invalid_action')
    end

    quantity = Crypto.ToInt(quantity, 1)
    local maxQuantity = math.max(1, Crypto.ToInt(Config.TechShop.MaxQuantity, 25))

    if quantity < 1 or quantity > maxQuantity then
        return false, Crypto.L('shop_quantity')
    end

    if not DistanceOk(source, Config.TechShop.Locations) then
        return false, Crypto.L('too_far')
    end

    if FW.GetItemCount(source, entry.item) < quantity then
        return false, Crypto.L('shop_no_item')
    end

    if not FW.RemoveItem(source, entry.item, quantity) then
        return false, Crypto.L('shop_no_item')
    end

    local ratio = Crypto.Clamp(Crypto.ToNumber(Config.TechShop.SellRatio, 0.45), 0.0, 1.0)
    local payout = math.floor(Crypto.ToNumber(entry.price, 0) * ratio * quantity)

    FW.AddMoney(source, payout, Config.Money.SellAccount)

    FW.Log('shop', 'Sale', ('%s sold %sx %s'):format(FW.GetName(source), quantity, entry.label or entry.item), {
        { name = 'Payout', value = Crypto.FormatMoney(payout) }
    })

    return true, Crypto.L('shop_sold', quantity, entry.label or entry.item, Crypto.FormatMoney(payout))
end

-- ---------------------------------------------------------------------------
-- BROKER
-- ---------------------------------------------------------------------------
function Shops.GetBrokerList(identifier)
    local list = {}

    for _, warehouse in ipairs(Config.Warehouses or {}) do
        local state = WH.Get(warehouse.id)

        if state then
            local interior = Crypto.GetInteriorConfig(warehouse.type)

            list[#list + 1] = {
                id = warehouse.id,
                label = warehouse.label,
                type = warehouse.type,
                typeLabel = interior and interior.label or warehouse.type,
                price = Crypto.ToInt(warehouse.price, 0),
                sellPrice = math.floor(Crypto.ToNumber(warehouse.price, 0) * Crypto.Clamp(Crypto.ToNumber(warehouse.sellRatio, 0.5), 0.0, 1.0)),
                maxRigs = Crypto.GetMaxRigs(warehouse.id),
                owned = state.owner ~= nil,
                isMine = identifier ~= nil and state.owner == identifier,
                coords = { x = warehouse.entrance.x, y = warehouse.entrance.y, z = warehouse.entrance.z }
            }
        end
    end

    return list
end

function Shops.BuyWarehouse(source, warehouseId)
    if Config.Broker.Enabled == false then
        return false, Crypto.L('invalid_action')
    end

    local identifier = FW.GetIdentifier(source)
    if not identifier then
        return false, Crypto.L('failed')
    end

    local warehouse = Crypto.GetWarehouseConfig(warehouseId)
    local state = WH.Get(warehouseId)

    if not warehouse or not state then
        return false, Crypto.L('invalid_action')
    end

    if not DistanceOk(source, Config.Broker.Locations) then
        return false, Crypto.L('too_far')
    end

    if state.owner then
        return false, Crypto.L('warehouse_owned')
    end

    local maxPerPlayer = Crypto.ToInt(Config.Broker.MaxPerPlayer, 2)
    if maxPerPlayer > 0 and WH.CountOwned(identifier) >= maxPerPlayer then
        return false, Crypto.L('warehouse_limit')
    end

    local price = Crypto.ToInt(warehouse.price, 0)

    if not FW.RemoveMoney(source, price, Config.Money.BuyAccount) then
        return false, Crypto.L('no_money')
    end

    WH.Reset(warehouseId, false)
    WH.SetOwner(warehouseId, identifier, FW.GetName(source))

    FW.Log('warehouse', 'Warehouse purchased', ('%s bought %s'):format(FW.GetName(source), warehouse.label), {
        { name = 'Price', value = Crypto.FormatMoney(price) },
        { name = 'Identifier', value = identifier }
    })

    return true, Crypto.L('warehouse_bought', warehouse.label, Crypto.FormatMoney(price))
end

function Shops.SellWarehouse(source, warehouseId)
    local identifier = FW.GetIdentifier(source)
    local warehouse = Crypto.GetWarehouseConfig(warehouseId)
    local state = WH.Get(warehouseId)

    if not identifier or not warehouse or not state then
        return false, Crypto.L('invalid_action')
    end

    if not DistanceOk(source, Config.Broker.Locations) then
        return false, Crypto.L('too_far')
    end

    if state.owner ~= identifier then
        return false, Crypto.L('not_owner')
    end

    local ratio = Crypto.Clamp(Crypto.ToNumber(warehouse.sellRatio, 0.5), 0.0, 1.0)
    local payout = math.floor(Crypto.ToNumber(warehouse.price, 0) * ratio)

    -- The outstanding electricity bill is deducted from the sale.
    payout = math.max(0, payout - math.floor(Crypto.ToNumber(state.bill, 0)))

    WH.Reset(warehouseId, false)
    FW.AddMoney(source, payout, Config.Money.SellAccount)

    FW.Log('warehouse', 'Warehouse sold', ('%s sold %s'):format(FW.GetName(source), warehouse.label), {
        { name = 'Payout', value = Crypto.FormatMoney(payout) }
    })

    return true, Crypto.L('warehouse_sold', warehouse.label, Crypto.FormatMoney(payout))
end

-- ---------------------------------------------------------------------------
-- INFORMANT
-- ---------------------------------------------------------------------------
function Shops.BuyInformation(source)
    if Config.Informant.Enabled == false then
        return false, Crypto.L('invalid_action')
    end

    local identifier = FW.GetIdentifier(source)
    if not identifier then
        return false, Crypto.L('failed')
    end

    if not DistanceOk(source, Config.Informant.Locations) then
        return false, Crypto.L('too_far')
    end

    local now = os.time()
    local readyAt = informantCooldowns[identifier] or 0

    if now < readyAt then
        return false, Crypto.L('informant_cooldown', math.ceil((readyAt - now) / 60))
    end

    -- Build the list of valid targets: owned, not mine, with GPUs inside.
    local candidates = {}

    for _, warehouse in ipairs(Config.Warehouses or {}) do
        local state = WH.Get(warehouse.id)

        if state and state.owner and state.owner ~= identifier then
            local gpus = WH.CountGpus(warehouse.id)

            if Config.Informant.OnlyLoaded == false or gpus >= math.max(1, Crypto.ToInt(Config.Robbery.MinGpus, 4)) then
                candidates[#candidates + 1] = { warehouse = warehouse, gpus = gpus }
            end
        end
    end

    if #candidates == 0 then
        return false, Crypto.L('informant_none')
    end

    local price = Crypto.ToInt(Config.Informant.Price, 15000)
    local account = Config.Informant.Account or Config.Money.DirtyAccount

    if not FW.RemoveMoney(source, price, account) then
        return false, Crypto.L('no_money')
    end

    informantCooldowns[identifier] = now + math.max(0, Crypto.ToInt(Config.Informant.Cooldown, 600))

    local pick = candidates[math.random(#candidates)]
    local entrance = pick.warehouse.entrance

    TriggerClientEvent(RESOURCE .. ':informantTarget', source, {
        id = pick.warehouse.id,
        label = pick.warehouse.label,
        coords = { x = entrance.x, y = entrance.y, z = entrance.z },
        duration = math.max(30, Crypto.ToInt(Config.Informant.Duration, 900))
    })

    FW.Log('robbery', 'Informant', ('%s bought the location of %s'):format(FW.GetName(source), pick.warehouse.label), {
        { name = 'Price', value = Crypto.FormatMoney(price) },
        { name = 'GPUs inside', value = tostring(pick.gpus) }
    })

    return true, Crypto.L('informant_bought', pick.warehouse.label)
end

function Shops.ClearCooldown(identifier)
    informantCooldowns[identifier] = nil
end
