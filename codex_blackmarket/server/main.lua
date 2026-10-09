local QBCore = exports['qb-core']:GetCoreObject()
local RESOURCE = GetCurrentResourceName()

local marketItems = {}
local categories = {}
local warehouses = {}
local sellOffers = {}
local stock = {}
local priceOverrides = {}
local profileCache = {}
local activeMissions = {}
local actionLocks = {}
local databaseReady = false
local checkoutBusy = false

for _, item in ipairs(Config.MarketItems or {}) do
    marketItems[item.item] = item
end
for _, category in ipairs(Config.Categories or {}) do
    categories[category.id] = category
end
for _, warehouse in ipairs(Config.Warehouses or {}) do
    warehouses[warehouse.id] = warehouse
end
for _, offer in ipairs(Config.SellOffers or {}) do
    sellOffers[offer.item] = offer
end

local function DebugPrint(...)
    if Config.Debug then
        print(('^3[%s]^7'):format(RESOURCE), ...)
    end
end

local function LogError(operation, message)
    print(('^1[%s] %s failed: %s^7'):format(RESOURCE, operation, tostring(message)))
end

local function Notify(source, message, kind, duration)
    if source and source > 0 then
        TriggerClientEvent('QBCore:Notify', source, tostring(message or ''), kind or 'primary', duration or 5000)
    end
end

local function DBCall(method, query, values)
    local ok, result = pcall(method, query, values or {})
    if not ok then
        LogError('database query', result)
        return nil
    end
    return result
end

local function DBQuery(query, values)
    return DBCall(MySQL.query.await, query, values)
end

local function DBUpdate(query, values)
    return DBCall(MySQL.update.await, query, values)
end

local function DBSingle(query, values)
    return DBCall(MySQL.single.await, query, values)
end

local function DBScalar(query, values)
    return DBCall(MySQL.scalar.await, query, values)
end

local function DBInsert(query, values)
    return DBCall(MySQL.insert.await, query, values)
end

local function DatabaseInit()
    if Config.Database and Config.Database.AutoCreate ~= false then
        local schema = {
            [[CREATE TABLE IF NOT EXISTS `codex_blackmarket_profiles` (
                `citizenid` varchar(50) NOT NULL,
                `xp` int unsigned NOT NULL DEFAULT 0,
                `respect` int unsigned NOT NULL DEFAULT 0,
                `completed_runs` int unsigned NOT NULL DEFAULT 0,
                `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
            [[CREATE TABLE IF NOT EXISTS `codex_blackmarket_stock` (
                `item` varchar(64) NOT NULL,
                `stock` int unsigned NOT NULL DEFAULT 0,
                `price_override` int unsigned DEFAULT NULL,
                `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`item`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
            [[CREATE TABLE IF NOT EXISTS `codex_blackmarket_warehouse_access` (
                `citizenid` varchar(50) NOT NULL,
                `warehouse_id` varchar(32) NOT NULL,
                `pin` char(6) NOT NULL,
                `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`, `warehouse_id`),
                KEY `idx_codex_bm_warehouse_id` (`warehouse_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]]
        }

        for _, query in ipairs(schema) do
            if DBQuery(query) == nil then
                return false
            end
        end
    end

    for _, item in ipairs(Config.MarketItems or {}) do
        local inserted = DBInsert(
            'INSERT IGNORE INTO `codex_blackmarket_stock` (`item`, `stock`) VALUES (?, ?)',
            { item.item, math.max(0, math.floor(tonumber(item.stock) or 0)) }
        )
        if inserted == nil then
            return false
        end
    end

    local rows = DBQuery('SELECT `item`, `stock`, `price_override` FROM `codex_blackmarket_stock`')
    if type(rows) ~= 'table' then
        return false
    end

    for _, row in ipairs(rows) do
        if marketItems[row.item] then
            stock[row.item] = math.max(0, tonumber(row.stock) or 0)
            priceOverrides[row.item] = row.price_override ~= nil and tonumber(row.price_override) or nil
        end
    end

    for _, item in ipairs(Config.MarketItems or {}) do
        if stock[item.item] == nil then
            stock[item.item] = math.max(0, tonumber(item.stock) or 0)
        end
    end

    databaseReady = true
    return true
end

local function GetPlayer(source)
    if not source or source <= 0 then return nil end
    return QBCore.Functions.GetPlayer(source)
end

local function GetCitizenId(player)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function GetProfile(citizenid)
    if not citizenid then return nil end
    if profileCache[citizenid] then return profileCache[citizenid] end

    local row = DBSingle(
        'SELECT `xp`, `respect`, `completed_runs` FROM `codex_blackmarket_profiles` WHERE `citizenid` = ?',
        { citizenid }
    )
    if row == nil then
        -- A missing row is normal; a failed query is not distinguishable from
        -- no row here, but the following INSERT/SELECT safely resolves it.
        local inserted = DBInsert(
            'INSERT IGNORE INTO `codex_blackmarket_profiles` (`citizenid`) VALUES (?)',
            { citizenid }
        )
        if inserted == nil then return nil end
        row = DBSingle(
            'SELECT `xp`, `respect`, `completed_runs` FROM `codex_blackmarket_profiles` WHERE `citizenid` = ?',
            { citizenid }
        )
    end

    if not row then return nil end
    local profile = {
        citizenid = citizenid,
        xp = math.max(0, tonumber(row.xp) or 0),
        respect = math.max(0, tonumber(row.respect) or 0),
        completedRuns = math.max(0, tonumber(row.completed_runs) or 0)
    }
    profileCache[citizenid] = profile
    return profile
end

local function GetLevel(xp)
    local level = 1
    for index, threshold in ipairs(Config.Progression.LevelThresholds or { 0 }) do
        if (tonumber(xp) or 0) >= threshold then
            level = index
        else
            break
        end
    end
    return math.max(1, level)
end

local function GetProgress(profile)
    local thresholds = Config.Progression.LevelThresholds or { 0 }
    local level = GetLevel(profile.xp)
    local current = tonumber(thresholds[level]) or 0
    local nextValue = thresholds[level + 1]
    local percent = 100
    if nextValue then
        percent = math.floor(math.max(0, math.min(1, (profile.xp - current) / math.max(1, nextValue - current))) * 100)
    end
    return level, current, nextValue, percent
end

local function SaveProfile(profile)
    local result = DBUpdate(
        'UPDATE `codex_blackmarket_profiles` SET `xp` = ?, `respect` = ?, `completed_runs` = ? WHERE `citizenid` = ?',
        { profile.xp, profile.respect, profile.completedRuns, profile.citizenid }
    )
    return result ~= nil
end

local function GetQbItem(itemName)
    local shared = QBCore.Shared and QBCore.Shared.Items
    if not shared then return nil end
    return shared[itemName] or shared[string.lower(itemName)]
end

local function GetItemCount(player, itemName)
    if not player or not player.Functions or not player.Functions.GetItemByName then return 0 end
    local item = player.Functions.GetItemByName(itemName)
    return item and math.max(0, tonumber(item.amount) or 0) or 0
end

local function GetDistance(source, target)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return math.huge end

    local ok, coords = pcall(GetEntityCoords, ped)
    if not ok or not coords then return math.huge end

    local dx = (tonumber(coords.x) or 0) - (tonumber(target.x) or 0)
    local dy = (tonumber(coords.y) or 0) - (tonumber(target.y) or 0)
    local dz = (tonumber(coords.z) or 0) - (tonumber(target.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function GetVendor(vendorId)
    for _, vendor in ipairs(Config.Dealer.Vendors or {}) do
        if vendor.id == vendorId then return vendor end
    end
    return nil
end

local function IsNearVendor(source, vendorId)
    local vendor = GetVendor(vendorId)
    local limit = tonumber(Config.Security.VendorDistance) or 8.0
    if vendor then
        return GetDistance(source, vendor.coords) <= limit
    end
    for _, candidate in ipairs(Config.Dealer.Vendors or {}) do
        if GetDistance(source, candidate.coords) <= limit then return true end
    end
    return false
end

local function IsNearAnyVendor(source)
    for _, vendor in ipairs(Config.Dealer.Vendors or {}) do
        if GetDistance(source, vendor.coords) <= (tonumber(Config.Security.VendorDistance) or 8.0) then
            return true
        end
    end
    return false
end

local function IsNearWarehouse(source, warehouseId)
    local warehouse = warehouses[warehouseId]
    return warehouse ~= nil and GetDistance(source, warehouse.coords) <= (tonumber(Config.Security.WarehouseDistance) or 4.0)
end

local function GeneratePin()
    return ('%06d'):format(math.random(0, 999999))
end

local function GetOrCreatePin(citizenid, warehouseId)
    local pin = DBScalar(
        'SELECT `pin` FROM `codex_blackmarket_warehouse_access` WHERE `citizenid` = ? AND `warehouse_id` = ?',
        { citizenid, warehouseId }
    )
    if pin ~= nil then return tostring(pin) end

    local created = DBInsert(
        'INSERT IGNORE INTO `codex_blackmarket_warehouse_access` (`citizenid`, `warehouse_id`, `pin`) VALUES (?, ?, ?)',
        { citizenid, warehouseId, GeneratePin() }
    )
    if created == nil then return nil end

    pin = DBScalar(
        'SELECT `pin` FROM `codex_blackmarket_warehouse_access` WHERE `citizenid` = ? AND `warehouse_id` = ?',
        { citizenid, warehouseId }
    )
    return pin and tostring(pin) or nil
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function GetPrice(definition)
    local base = priceOverrides[definition.item] or tonumber(definition.price) or 0
    local initial = math.max(1, tonumber(definition.stock) or 1)
    local current = math.max(0, tonumber(stock[definition.item]) or 0)
    local pricing = Config.MarketPricing or {}
    local scarcity = tonumber(pricing.ScarcityMarkup) or 0
    local multiplier = 1 + ((initial - current) / initial) * scarcity
    multiplier = Clamp(multiplier, tonumber(pricing.MinMultiplier) or 0.75, tonumber(pricing.MaxMultiplier) or 1.8)
    return math.max(1, math.floor(base * multiplier + 0.5))
end

local function GetTierList(profile)
    local result = {}
    for tierId, tier in pairs(Config.Cargo.Tiers or {}) do
        local level = GetLevel(profile.xp)
        result[#result + 1] = {
            id = tonumber(tierId),
            label = tier.label,
            minLevel = tonumber(tier.minLevel) or 1,
            available = level >= (tonumber(tier.minLevel) or 1),
            deposit = tonumber(tier.deposit) or 0,
            reward = tonumber(tier.reward) or 0,
            xp = tonumber(tier.xp) or 0,
            respect = tonumber(tier.respect) or 0,
            drops = tonumber(tier.drops) or 1,
            packages = tonumber(tier.packages) or 1,
            description = tier.description or ''
        }
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

local function BuildMarketData(source, context, targetId)
    local player = GetPlayer(source)
    local citizenid = GetCitizenId(player)
    if not player or not citizenid then return nil end

    local profile = GetProfile(citizenid)
    if not profile then return nil end

    local level, currentThreshold, nextThreshold, percent = GetProgress(profile)
    local playerData = player.PlayerData or {}
    local displayedName = tostring((playerData.charinfo and playerData.charinfo.firstname) or '')
    if displayedName == '' then displayedName = ('Player %s'):format(source) end

    local categoryRows = {}
    for _, category in ipairs(Config.Categories or {}) do
        categoryRows[#categoryRows + 1] = {
            id = category.id,
            label = category.label,
            icon = category.icon or '◈',
            minLevel = tonumber(category.minLevel) or 1,
            description = category.description or '',
            locked = level < (tonumber(category.minLevel) or 1)
        }
    end

    local productRows = {}
    for _, definition in ipairs(Config.MarketItems or {}) do
        local shared = GetQbItem(definition.item)
        if shared then
            local category = categories[definition.category]
            local requiredLevel = math.max(tonumber(definition.level) or 1, category and tonumber(category.minLevel) or 1)
            productRows[#productRows + 1] = {
                item = definition.item,
                category = definition.category,
                label = definition.label or shared.label or definition.item,
                icon = definition.icon or '◈',
                description = definition.description or '',
                price = GetPrice(definition),
                stock = tonumber(stock[definition.item]) or 0,
                maxQuantity = math.max(1, math.min(tonumber(definition.maxPurchase) or (shared.unique and 1 or tonumber(Config.Security.MaxQuantityPerItem) or 25), tonumber(Config.Security.MaxQuantityPerItem) or 25)),
                requiredLevel = requiredLevel,
                locked = level < requiredLevel
            }
        end
    end

    local saleRows = {}
    for _, offer in ipairs(Config.SellOffers or {}) do
        local shared = GetQbItem(offer.item)
        if shared then
            saleRows[#saleRows + 1] = {
                item = offer.item,
                label = offer.label or shared.label or offer.item,
                icon = offer.icon or '◈',
                description = offer.description or '',
                price = math.max(0, tonumber(offer.price) or 0),
                owned = GetItemCount(player, offer.item)
            }
        end
    end

    local warehouseRows = {}
    for _, warehouse in ipairs(Config.Warehouses or {}) do
        local unlocked = level >= (tonumber(warehouse.minLevel) or 1)
        local row = {
            id = warehouse.id,
            label = warehouse.label,
            minLevel = tonumber(warehouse.minLevel) or 1,
            unlocked = unlocked,
            slots = tonumber(warehouse.slots) or 40,
            maxWeight = tonumber(warehouse.maxWeight) or 250000
        }
        if unlocked then
            row.pin = GetOrCreatePin(citizenid, warehouse.id)
        end
        warehouseRows[#warehouseRows + 1] = row
    end

    return {
        context = context or 'market',
        targetId = targetId,
        profile = {
            name = displayedName,
            level = level,
            xp = profile.xp,
            respect = profile.respect,
            completedRuns = profile.completedRuns,
            currentThreshold = currentThreshold,
            nextThreshold = nextThreshold,
            progressPercent = percent
        },
        categories = categoryRows,
        products = productRows,
        sellOffers = saleRows,
        missions = GetTierList(profile),
        warehouses = warehouseRows,
        hours = { enabled = Config.MarketHours.Enabled ~= false, open = Config.MarketHours.Open, close = Config.MarketHours.Close }
    }
end

local function IsAdmin(source)
    if IsPlayerAceAllowed(source, Config.Admin.AcePermission or 'codex_blackmarket.admin') then
        return true
    end
    for _, permission in ipairs({ 'admin', 'god' }) do
        local ok, allowed = pcall(QBCore.Functions.HasPermission, source, permission)
        if ok and allowed then return true end
    end
    return false
end

local function AcquireActionLock(source)
    if actionLocks[source] then return false end
    actionLocks[source] = true
    return true
end

local function ReleaseActionLock(source)
    actionLocks[source] = nil
end

local function BuildAdminData()
    local rows = {}
    for _, definition in ipairs(Config.MarketItems or {}) do
        local shared = GetQbItem(definition.item)
        if shared then
            rows[#rows + 1] = {
                item = definition.item,
                label = definition.label or shared.label or definition.item,
                price = tonumber(priceOverrides[definition.item]) or tonumber(definition.price) or 0,
                hasOverride = priceOverrides[definition.item] ~= nil,
                stock = tonumber(stock[definition.item]) or 0,
                maxStock = tonumber(definition.maxStock) or Config.Admin.MaxStock
            }
        end
    end
    return { items = rows }
end

-- ---------------------------------------------------------------------------
-- DATABASE / RESOURCE START
-- ---------------------------------------------------------------------------
CreateThread(function()
    math.randomseed(os.time() + GetGameTimer())

    if Config.Security.RequireOneSync then
        local oneSync = GetConvar('onesync', 'off')
        if oneSync == 'off' or oneSync == '' then
            print(('^3[%s] Warning: OneSync is off. Secure location checks may not work.^7'):format(RESOURCE))
        end
    end

    local ok, result = pcall(DatabaseInit)
    if not ok or not result then
        LogError('startup', ok and 'database initialization did not complete' or result)
        return
    end

    for _, definition in ipairs(Config.MarketItems or {}) do
        if not GetQbItem(definition.item) then
            print(('^3[%s] Catalog item "%s" is not in QBCore.Shared.Items; it will not appear until registered.^7'):format(RESOURCE, definition.item))
        end
    end
    for _, offer in ipairs(Config.SellOffers or {}) do
        if not GetQbItem(offer.item) then
            print(('^3[%s] Sell item "%s" is not in QBCore.Shared.Items; that offer is hidden.^7'):format(RESOURCE, offer.item))
        end
    end

    databaseReady = true
    print(('^2[%s] Ready: %d catalog items, %d warehouses.^7'):format(RESOURCE, #Config.MarketItems, #Config.Warehouses))
end)

-- Stock replenishment. It is intentionally server-side and persisted.
CreateThread(function()
    local interval = math.max(1, tonumber(Config.Database.RestockIntervalMinutes) or 30) * 60000
    while true do
        Wait(interval)
        if databaseReady then
            for _, definition in ipairs(Config.MarketItems or {}) do
                local current = tonumber(stock[definition.item]) or 0
                local maximum = tonumber(definition.maxStock) or current
                local replenished = math.min(maximum, current + math.max(0, tonumber(definition.restock) or 0))
                if replenished > current then
                    local affected = DBUpdate(
                        'UPDATE `codex_blackmarket_stock` SET `stock` = ? WHERE `item` = ?',
                        { replenished, definition.item }
                    )
                    if affected ~= nil then stock[definition.item] = replenished end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- MARKET DATA CALLBACKS
-- ---------------------------------------------------------------------------
QBCore.Functions.CreateCallback('codex_blackmarket:server:getData', function(source, callback, context, targetId)
    if not databaseReady then
        callback({ ok = false, message = 'The market database is still starting.' })
        return
    end

    context = type(context) == 'string' and context or 'market'
    if context == 'market' then
        if not IsNearVendor(source, targetId) then
            callback({ ok = false, message = Config.Notifications.TooFar })
            return
        end
    elseif context == 'warehouse' then
        local warehouse = warehouses[targetId]
        if not warehouse or not IsNearWarehouse(source, targetId) then
            callback({ ok = false, message = Config.Notifications.TooFar })
            return
        end
        local player = GetPlayer(source)
        local profile = GetProfile(GetCitizenId(player))
        if not profile or GetLevel(profile.xp) < (tonumber(warehouse.minLevel) or 1) then
            callback({ ok = false, message = Config.Notifications.NoAccess })
            return
        end
    else
        callback({ ok = false, message = 'Invalid market view.' })
        return
    end

    local data = BuildMarketData(source, context, targetId)
    if not data then
        callback({ ok = false, message = 'Could not load your market profile.' })
        return
    end
    callback({ ok = true, data = data })
end)

QBCore.Functions.CreateCallback('codex_blackmarket:server:checkout', function(source, callback, payload)
    if not databaseReady then callback({ ok = false, message = 'The market is still starting.' }); return end
    if not AcquireActionLock(source) then callback({ ok = false, message = 'Your previous action is still processing.' }); return end
    if checkoutBusy then
        ReleaseActionLock(source)
        callback({ ok = false, message = 'The market is busy. Try again in a moment.' })
        return
    end
    checkoutBusy = true

    local ok, result = pcall(function()
        local player = GetPlayer(source)
        if not player then return { ok = false, message = 'Your character is not ready.' } end
        if not IsNearAnyVendor(source) then return { ok = false, message = Config.Notifications.TooFar } end
        if type(payload) ~= 'table' or type(payload.items) ~= 'table' then return { ok = false, message = 'Invalid basket.' } end

        local requested = {}
        local lines = 0
        for _, entry in ipairs(payload.items) do
            lines = lines + 1
            if lines > (tonumber(Config.Security.MaxCartLines) or 10) then
                return { ok = false, message = 'Your basket has too many different items.' }
            end
            local itemName = type(entry.item) == 'string' and entry.item or ''
            local definition = marketItems[itemName]
            local amount = math.floor(tonumber(entry.amount or entry.count) or 0)
            local shared = definition and GetQbItem(itemName) or nil
            local lineLimit = definition and (tonumber(definition.maxPurchase) or (shared and shared.unique and 1 or tonumber(Config.Security.MaxQuantityPerItem) or 25)) or 0
            lineLimit = math.min(lineLimit, tonumber(Config.Security.MaxQuantityPerItem) or 25)
            if not definition or amount < 1 or amount > lineLimit then
                return { ok = false, message = 'Your basket contains an invalid item or quantity.' }
            end
            requested[itemName] = (requested[itemName] or 0) + amount
        end
        if next(requested) == nil then return { ok = false, message = 'Your basket is empty.' } end
        for itemName, amount in pairs(requested) do
            local definition = marketItems[itemName]
            local shared = GetQbItem(itemName)
            local lineLimit = tonumber(definition.maxPurchase) or (shared and shared.unique and 1 or tonumber(Config.Security.MaxQuantityPerItem) or 25)
            lineLimit = math.min(lineLimit, tonumber(Config.Security.MaxQuantityPerItem) or 25)
            if amount > lineLimit then
                return { ok = false, message = ('The combined quantity for %s exceeds its order limit.'):format(itemName) }
            end
        end

        local citizenid = GetCitizenId(player)
        local profile = GetProfile(citizenid)
        if not profile then return { ok = false, message = 'Could not load your access profile.' } end
        local level = GetLevel(profile.xp)
        local account = type(payload.account) == 'string' and payload.account:lower() or Config.Payment.DefaultAccount
        if not Config.Payment.AllowedAccounts[account] then return { ok = false, message = 'Invalid payment method.' } end

        local total = 0
        local prepared = {}
        for itemName, amount in pairs(requested) do
            local definition = marketItems[itemName]
            local category = categories[definition.category]
            local requiredLevel = math.max(tonumber(definition.level) or 1, category and tonumber(category.minLevel) or 1)
            if level < requiredLevel then return { ok = false, message = 'Your access level is too low for one of those items.' } end
            if not GetQbItem(itemName) then return { ok = false, message = ('Item "%s" is not registered in QBCore.'):format(itemName) } end
            local available = tonumber(stock[itemName]) or 0
            if amount > available then return { ok = false, message = ('Not enough stock for %s.'):format(definition.label or itemName) } end
            local unitPrice = GetPrice(definition)
            total = total + unitPrice * amount
            prepared[#prepared + 1] = { item = itemName, amount = amount, unitPrice = unitPrice }
        end

        table.sort(prepared, function(a, b) return a.item < b.item end)
        if total <= 0 then return { ok = false, message = 'The order total is invalid.' } end
        local balance = tonumber(player.Functions.GetMoney(account)) or 0
        if balance < total then return { ok = false, message = 'You do not have enough funds.' } end

        -- Optional inventory preflight; AddItem below remains authoritative.
        for _, line in ipairs(prepared) do
            local canCall, canAdd = pcall(function()
                return exports['qb-inventory']:CanAddItem(source, line.item, line.amount)
            end)
            if canCall and canAdd == false then
                return { ok = false, message = ('There is not enough inventory space for %s.'):format(line.item) }
            end
        end

        local stockUpdates = {}
        local function RestoreStock()
            for _, updated in ipairs(stockUpdates) do
                DBUpdate('UPDATE `codex_blackmarket_stock` SET `stock` = `stock` + ? WHERE `item` = ?', { updated.amount, updated.item })
            end
        end

        -- Reserve persistent stock before touching the player's money or
        -- inventory. Conditional updates prevent two server processes from
        -- selling the same final unit.
        for _, line in ipairs(prepared) do
            local affected = DBUpdate(
                'UPDATE `codex_blackmarket_stock` SET `stock` = `stock` - ? WHERE `item` = ? AND `stock` >= ?',
                { line.amount, line.item, line.amount }
            )
            if affected ~= 1 then
                RestoreStock()
                return { ok = false, message = 'Stock changed during checkout. Please try again.' }
            end
            stockUpdates[#stockUpdates + 1] = { item = line.item, amount = line.amount }
        end

        if not GetPlayer(source) then
            RestoreStock()
            return { ok = false, message = 'Your character disconnected before checkout completed.' }
        end
        if not player.Functions.RemoveMoney(account, total, 'codex-blackmarket-purchase') then
            RestoreStock()
            return { ok = false, message = 'Payment failed.' }
        end

        local added = {}
        for _, line in ipairs(prepared) do
            local success = player.Functions.AddItem(line.item, line.amount, false, {}, 'codex-blackmarket-purchase')
            if not success then
                for _, rollback in ipairs(added) do
                    player.Functions.RemoveItem(rollback.item, rollback.amount, false, 'codex-blackmarket-rollback')
                end
                player.Functions.AddMoney(account, total, 'codex-blackmarket-refund')
                RestoreStock()
                return { ok = false, message = ('Could not add %s to your inventory. Payment was refunded.'):format(line.item) }
            end
            added[#added + 1] = { item = line.item, amount = line.amount }
        end

        for _, line in ipairs(prepared) do
            stock[line.item] = math.max(0, (tonumber(stock[line.item]) or 0) - line.amount)
        end
        local data = BuildMarketData(source, 'market', nil)
        return { ok = true, message = 'Purchase complete.', total = total, data = data }
    end)

    checkoutBusy = false
    ReleaseActionLock(source)
    if not ok then
        LogError('checkout', result)
        callback({ ok = false, message = 'Checkout failed safely. No order was completed.' })
        return
    end
    callback(result)
end)

QBCore.Functions.CreateCallback('codex_blackmarket:server:sell', function(source, callback, payload)
    if not databaseReady then callback({ ok = false, message = 'The market is still starting.' }); return end
    if not AcquireActionLock(source) then callback({ ok = false, message = 'Your previous action is still processing.' }); return end

    local ok, result = pcall(function()
        local player = GetPlayer(source)
        if not player then return { ok = false, message = 'Your character is not ready.' } end
        if not IsNearAnyVendor(source) then return { ok = false, message = Config.Notifications.TooFar } end
        if type(payload) ~= 'table' then return { ok = false, message = 'Invalid sale.' } end

        local itemName = type(payload.item) == 'string' and payload.item or ''
        local offer = sellOffers[itemName]
        local amount = math.floor(tonumber(payload.amount) or 0)
        if not offer or amount < 1 or amount > (tonumber(Config.Security.MaxSellQuantity) or 100) then
            return { ok = false, message = 'Invalid item or quantity.' }
        end
        if not GetQbItem(itemName) then return { ok = false, message = 'That item is not registered in QBCore.' } end
        if GetItemCount(player, itemName) < amount then return { ok = false, message = 'You do not have enough of that item.' } end

        local account = type(payload.account) == 'string' and payload.account:lower() or Config.Payment.DefaultAccount
        if not Config.Payment.AllowedAccounts[account] then return { ok = false, message = 'Invalid payout account.' } end
        local payout = math.max(0, tonumber(offer.price) or 0) * amount
        if payout <= 0 then return { ok = false, message = 'This item has no current offer.' } end

        if not player.Functions.RemoveItem(itemName, amount, false, 'codex-blackmarket-sale') then
            return { ok = false, message = 'The item could not be removed from your inventory.' }
        end
        if not player.Functions.AddMoney(account, payout, 'codex-blackmarket-sale') then
            player.Functions.AddItem(itemName, amount, false, {}, 'codex-blackmarket-sale-rollback')
            return { ok = false, message = 'Payout failed; your item was returned.' }
        end

        return {
            ok = true,
            message = ('Sold %sx %s for $%s.'):format(amount, offer.label or itemName, payout),
            data = BuildMarketData(source, 'market', nil)
        }
    end)

    ReleaseActionLock(source)
    if not ok then
        LogError('sale', result)
        callback({ ok = false, message = 'Sale failed safely.' })
        return
    end
    callback(result)
end)

QBCore.Functions.CreateCallback('codex_blackmarket:server:startMission', function(source, callback, tierId, vendorId)
    if not databaseReady then callback({ ok = false, message = 'The market is still starting.' }); return end
    if not AcquireActionLock(source) then callback({ ok = false, message = 'Your previous action is still processing.' }); return end

    local ok, result = pcall(function()
        local player = GetPlayer(source)
        if not player then return { ok = false, message = 'Your character is not ready.' } end
        if not IsNearVendor(source, vendorId) then return { ok = false, message = Config.Notifications.TooFar } end
        if not Config.Cargo.Enabled then return { ok = false, message = 'Cargo runs are currently disabled.' } end
        if activeMissions[source] then
            if os.time() > activeMissions[source].expiresAt then
                activeMissions[source] = nil
            else
                return { ok = false, message = Config.Notifications.MissionActive }
            end
        end

        tierId = math.floor(tonumber(tierId) or 0)
        local tier = Config.Cargo.Tiers[tierId]
        if not tier then return { ok = false, message = 'Unknown cargo tier.' } end
        local profile = GetProfile(GetCitizenId(player))
        if not profile or GetLevel(profile.xp) < (tonumber(tier.minLevel) or 1) then
            return { ok = false, message = 'Your access level is too low for this run.' }
        end

        local deposit = math.max(0, tonumber(tier.deposit) or 0)
        if deposit > 0 then
            local cash = tonumber(player.Functions.GetMoney('cash')) or 0
            if cash < deposit then return { ok = false, message = ('You need $%s cash for the refundable cargo deposit.'):format(deposit) } end
            if not player.Functions.RemoveMoney('cash', deposit, 'codex-blackmarket-cargo-deposit') then
                return { ok = false, message = 'Could not take the cargo deposit.' }
            end
        end

        local routeList = Config.Cargo.Routes or {}
        if #routeList == 0 then
            if deposit > 0 then player.Functions.AddMoney('cash', deposit, 'codex-blackmarket-deposit-refund') end
            return { ok = false, message = 'No delivery routes are configured.' }
        end
        local route = routeList[math.random(1, #routeList)]
        local dropCount = math.max(1, math.min(tonumber(tier.drops) or 1, #route.drops))
        local mission = {
            id = ('%s-%s-%04d'):format(GetCitizenId(player), os.time(), math.random(0, 9999)),
            citizenid = GetCitizenId(player),
            tier = tierId,
            tierLabel = tier.label,
            stage = 'pickup',
            currentDrop = 1,
            route = route,
            dropCount = dropCount,
            deposit = deposit,
            reward = math.max(0, tonumber(tier.reward) or 0),
            xpReward = math.max(0, tonumber(tier.xp) or 0),
            respectReward = math.max(0, tonumber(tier.respect) or 0),
            packages = math.max(1, tonumber(tier.packages) or 1),
            createdAt = os.time(),
            lastActionAt = os.time(),
            expiresAt = os.time() + math.max(1, tonumber(Config.Cargo.MissionLifetimeMinutes) or 120) * 60
        }
        activeMissions[source] = mission

        local drops = {}
        for index = 1, dropCount do
            drops[index] = { x = route.drops[index].x, y = route.drops[index].y, z = route.drops[index].z }
        end
        return {
            ok = true,
            message = ('Cargo run accepted: %s. Pick up %s package(s) at the contact.'):format(tier.label, mission.packages),
            mission = {
                id = mission.id,
                tier = mission.tier,
                tierLabel = mission.tierLabel,
                stage = mission.stage,
                currentDrop = mission.currentDrop,
                dropCount = mission.dropCount,
                drops = drops,
                pickup = { x = Config.Cargo.Pickup.x, y = Config.Cargo.Pickup.y, z = Config.Cargo.Pickup.z },
                packages = mission.packages,
                reward = mission.reward,
                deposit = mission.deposit,
                routeLabel = route.label
            }
        }
    end)

    ReleaseActionLock(source)
    if not ok then
        LogError('mission start', result)
        callback({ ok = false, message = 'Could not start the cargo run.' })
        return
    end
    callback(result)
end)

QBCore.Functions.CreateCallback('codex_blackmarket:server:openWarehouse', function(source, callback, warehouseId, pin)
    if not databaseReady then callback({ ok = false, message = 'Warehouse services are still starting.' }); return end
    if not AcquireActionLock(source) then callback({ ok = false, message = 'Your previous action is still processing.' }); return end

    local ok, result = pcall(function()
        local player = GetPlayer(source)
        local citizenid = GetCitizenId(player)
        local warehouse = warehouses[warehouseId]
        if not player or not citizenid or not warehouse then return { ok = false, message = 'Unknown warehouse.' } end
        if not IsNearWarehouse(source, warehouseId) then return { ok = false, message = Config.Notifications.TooFar } end
        local profile = GetProfile(citizenid)
        if not profile or GetLevel(profile.xp) < (tonumber(warehouse.minLevel) or 1) then
            return { ok = false, message = Config.Notifications.NoAccess }
        end

        local expectedPin = GetOrCreatePin(citizenid, warehouseId)
        if not expectedPin or tostring(pin or '') ~= expectedPin then
            return { ok = false, message = Config.Notifications.InvalidPin }
        end

        local stashId = ('codexbm_%s_%s'):format(tostring(citizenid):gsub('[^%w_%-]', ''), warehouseId)
        local stashData = {
            label = warehouse.label,
            maxweight = tonumber(warehouse.maxWeight) or 250000,
            slots = tonumber(warehouse.slots) or 40
        }

        local opened, exportResult = pcall(function()
            return exports['qb-inventory']:OpenInventory(source, stashId, stashData)
        end)
        if not opened or exportResult == false then
            LogError('qb-inventory OpenInventory', exportResult or 'export returned false')
            return { ok = false, message = 'Could not open this storage. Check that qb-inventory is started.' }
        end
        return { ok = true, message = ('Access granted: %s.'):format(warehouse.label) }
    end)

    ReleaseActionLock(source)
    if not ok then
        LogError('warehouse access', result)
        callback({ ok = false, message = 'Could not access the warehouse.' })
        return
    end
    callback(result)
end)

QBCore.Functions.CreateCallback('codex_blackmarket:server:adminData', function(source, callback)
    if not IsAdmin(source) then callback({ ok = false, message = 'You are not authorized to use the admin panel.' }); return end
    if not databaseReady then callback({ ok = false, message = 'The market database is still starting.' }); return end
    callback({ ok = true, data = BuildAdminData() })
end)

QBCore.Functions.CreateCallback('codex_blackmarket:server:adminUpdate', function(source, callback, payload)
    if not IsAdmin(source) then callback({ ok = false, message = 'You are not authorized to change market settings.' }); return end
    if not databaseReady then callback({ ok = false, message = 'The market database is still starting.' }); return end
    if checkoutBusy then callback({ ok = false, message = 'Checkout is in progress. Try again shortly.' }); return end
    if type(payload) ~= 'table' then callback({ ok = false, message = 'Invalid settings.' }); return end

    local itemName = type(payload.item) == 'string' and payload.item or ''
    local definition = marketItems[itemName]
    if not definition then callback({ ok = false, message = 'That item is not in the configured catalog.' }); return end

    local newStock = math.floor(Clamp(payload.stock, 0, tonumber(definition.maxStock) or Config.Admin.MaxStock))
    newStock = math.floor(Clamp(newStock, 0, tonumber(Config.Admin.MaxStock) or 10000))
    local newPrice = math.floor(Clamp(payload.price, 0, tonumber(Config.Admin.MaxPrice) or 1000000))

    local affected
    if newPrice == 0 then
        affected = DBUpdate(
            'UPDATE `codex_blackmarket_stock` SET `stock` = ?, `price_override` = NULL WHERE `item` = ?',
            { newStock, itemName }
        )
    else
        affected = DBUpdate(
            'UPDATE `codex_blackmarket_stock` SET `stock` = ?, `price_override` = ? WHERE `item` = ?',
            { newStock, newPrice, itemName }
        )
    end
    if affected == nil then callback({ ok = false, message = 'Database update failed.' }); return end

    if newPrice == 0 then
        priceOverrides[itemName] = nil
    else
        priceOverrides[itemName] = newPrice
    end
    stock[itemName] = newStock
    callback({ ok = true, message = 'Market settings saved.', data = BuildAdminData() })
end)

-- ---------------------------------------------------------------------------
-- CARGO RUN STATE MACHINE
-- ---------------------------------------------------------------------------
local function MissionForClient(mission)
    if not mission then return nil end
    local drops = {}
    for index = 1, mission.dropCount do
        local point = mission.route.drops[index]
        drops[index] = { x = point.x, y = point.y, z = point.z }
    end
    return {
        id = mission.id,
        tier = mission.tier,
        tierLabel = mission.tierLabel,
        stage = mission.stage,
        currentDrop = mission.currentDrop,
        dropCount = mission.dropCount,
        drops = drops,
        pickup = { x = Config.Cargo.Pickup.x, y = Config.Cargo.Pickup.y, z = Config.Cargo.Pickup.z },
        packages = mission.packages,
        reward = mission.reward,
        deposit = mission.deposit,
        routeLabel = mission.route.label
    }
end

local function IsMissionDriver(source)
    if not Config.Cargo.RequireDriver then return true end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return false end
    return GetPedInVehicleSeat(vehicle, -1) == ped
end

local function SendMissionUpdate(source, mission, action, message)
    TriggerClientEvent('codex_blackmarket:client:missionUpdate', source, {
        mission = MissionForClient(mission),
        action = action,
        message = message
    })
end

RegisterNetEvent('codex_blackmarket:server:missionAction', function(missionId, action)
    local source = source
    if not databaseReady or not AcquireActionLock(source) then return end

    local ok, errorMessage = pcall(function()
        local mission = activeMissions[source]
        if not mission or tostring(missionId or '') ~= mission.id then
            Notify(source, Config.Notifications.NoMission, 'error')
            return
        end
        if os.time() > mission.expiresAt then
            activeMissions[source] = nil
            TriggerClientEvent('codex_blackmarket:client:missionUpdate', source, { action = 'failed', message = 'Cargo run expired.' })
            Notify(source, 'Cargo run expired. The deposit was forfeited.', 'error')
            return
        end
        if not IsMissionDriver(source) then
            Notify(source, Config.Notifications.NeedVehicle, 'error')
            return
        end

        if action == 'pickup' then
            if mission.stage ~= 'pickup' then
                Notify(source, 'Cargo has already been picked up.', 'error')
                return
            end
            if GetDistance(source, Config.Cargo.Pickup) > (tonumber(Config.Security.PickupDistance) or 5.0) then
                Notify(source, Config.Notifications.TooFar, 'error')
                return
            end
            mission.stage = 'delivery'
            mission.currentDrop = 1
            mission.lastActionAt = os.time()
            SendMissionUpdate(source, mission, 'pickedUp', ('Loaded %s package(s). Drive to the first drop.'):format(mission.packages))
            return
        end

        if action ~= 'deliver' or mission.stage ~= 'delivery' then
            Notify(source, 'That cargo action is not available yet.', 'error')
            return
        end

        local destination = mission.route.drops[mission.currentDrop]
        if not destination or GetDistance(source, destination) > (tonumber(Config.Security.DropDistance) or 8.0) then
            Notify(source, Config.Notifications.TooFar, 'error')
            return
        end
        if os.time() - mission.lastActionAt < (tonumber(Config.Cargo.MinimumStopSeconds) or 0) then
            Notify(source, 'Wait a moment before confirming the handoff.', 'error')
            return
        end

        if mission.currentDrop < mission.dropCount then
            mission.currentDrop = mission.currentDrop + 1
            mission.lastActionAt = os.time()
            SendMissionUpdate(source, mission, 'nextDrop', ('Handoff complete. Proceed to stop %s of %s.'):format(mission.currentDrop, mission.dropCount))
            return
        end

        local player = GetPlayer(source)
        local profile = GetProfile(mission.citizenid)
        if not player or not profile then
            Notify(source, 'Could not settle the cargo contract. Contact an administrator.', 'error')
            return
        end

        local payout = mission.reward + mission.deposit
        if not player.Functions.AddMoney('cash', payout, 'codex-blackmarket-cargo-payout') then
            Notify(source, 'Payout failed. Your contract remains active; retry the handoff.', 'error')
            return
        end

        local oldXp = profile.xp
        local oldRespect = profile.respect
        local oldCompletedRuns = profile.completedRuns
        profile.xp = profile.xp + mission.xpReward
        profile.respect = math.min(tonumber(Config.Progression.MaxRespect) or 1000, profile.respect + mission.respectReward)
        profile.completedRuns = profile.completedRuns + 1
        if not SaveProfile(profile) then
            profile.xp = oldXp
            profile.respect = oldRespect
            profile.completedRuns = oldCompletedRuns
            player.Functions.RemoveMoney('cash', payout, 'codex-blackmarket-payout-rollback')
            Notify(source, 'Database error while saving your reputation. No payout was kept; retry the handoff.', 'error')
            return
        end

        local level = GetLevel(profile.xp)
        activeMissions[source] = nil
        TriggerClientEvent('codex_blackmarket:client:missionUpdate', source, {
            action = 'complete',
            message = ('Contract complete. Paid $%s (including deposit) • +%s XP • +%s respect. Access level %s.'):format(payout, mission.xpReward, mission.respectReward, level),
            profile = { xp = profile.xp, respect = profile.respect, level = level, completedRuns = profile.completedRuns }
        })
        Notify(source, 'Cargo contract complete. Payment and reputation delivered.', 'success', 8000)
    end)

    ReleaseActionLock(source)
    if not ok then
        LogError('cargo action', errorMessage)
        Notify(source, 'The cargo action could not be completed.', 'error')
    end
end)

AddEventHandler('playerDropped', function()
    local source = source
    activeMissions[source] = nil
    actionLocks[source] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    activeMissions = {}
    actionLocks = {}
end)

-- ---------------------------------------------------------------------------
-- ADMIN TOOLS
-- ---------------------------------------------------------------------------
RegisterCommand(Config.Admin.Command or 'bmadmin', function(source)
    if source == 0 then
        print(('[%s] The admin panel can only be opened in-game.'):format(RESOURCE))
        return
    end
    if not IsAdmin(source) then
        Notify(source, 'You do not have permission to use the black market admin panel.', 'error')
        return
    end
    TriggerClientEvent('codex_blackmarket:client:openAdmin', source)
end, false)
