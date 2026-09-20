--[[
    Dynamic bitcoin market.
    The price is generated server side only, persisted in MySQL and pushed to
    every client so the UI and the NUI chart stay in sync.
]]

CodexCryptoMarket = CodexCryptoMarket or {}

local Market = CodexCryptoMarket
local Crypto = CodexCrypto
local DB = CodexCryptoDB
local RESOURCE = GetCurrentResourceName()

Market.price = 0
Market.history = {}
Market.lastUpdate = 0
Market.started = false

local function ClampPrice(price)
    return math.floor(Crypto.Clamp(price, Crypto.ToNumber(Config.Market.MinPrice, 1000), Crypto.ToNumber(Config.Market.MaxPrice, 100000)) + 0.5)
end

function Market.GetPrice()
    if Market.price <= 0 then
        return ClampPrice(Crypto.ToNumber(Config.Market.StartPrice, 42000))
    end
    return Market.price
end

function Market.GetTrend()
    local size = #Market.history
    if size < 2 then
        return 0.0
    end

    local previous = Crypto.ToNumber(Market.history[size - 1], 0)
    local current = Crypto.ToNumber(Market.history[size], 0)

    if previous <= 0 then
        return 0.0
    end

    return Crypto.Round(((current - previous) / previous) * 100.0, 2)
end

function Market.GetState()
    return {
        price = Market.GetPrice(),
        trend = Market.GetTrend(),
        history = Market.history,
        min = Crypto.ToNumber(Config.Market.MinPrice, 0),
        max = Crypto.ToNumber(Config.Market.MaxPrice, 0),
        fee = Crypto.ToNumber(Config.Market.SellFee, 0),
        nextUpdate = Market.lastUpdate + Crypto.ToNumber(Config.Market.UpdateInterval, 300)
    }
end

local function PushHistory(price)
    Market.history[#Market.history + 1] = price

    local limit = math.max(2, Crypto.ToInt(Config.Market.HistorySize, 48))
    while #Market.history > limit do
        table.remove(Market.history, 1)
    end
end

local function Broadcast()
    TriggerClientEvent(RESOURCE .. ':marketUpdate', -1, Market.GetState())
end

local function Roll()
    local price = Market.GetPrice()
    local volatility = Crypto.Clamp(Crypto.ToNumber(Config.Market.Volatility, 0.045), 0.0, 0.5)
    local reversion = Crypto.Clamp(Crypto.ToNumber(Config.Market.MeanReversion, 0.08), 0.0, 1.0)

    local minPrice = Crypto.ToNumber(Config.Market.MinPrice, 1000)
    local maxPrice = Crypto.ToNumber(Config.Market.MaxPrice, 100000)
    local middle = (minPrice + maxPrice) * 0.5

    -- Random walk between -volatility and +volatility.
    local change = (math.random() * 2.0 - 1.0) * volatility

    -- Pull back toward the middle of the range to avoid sticking to a bound.
    if middle > 0 then
        change = change + ((middle - price) / middle) * reversion
    end

    return ClampPrice(price * (1.0 + change))
end

function Market.Update(force)
    local newPrice = force and Market.GetPrice() or Roll()

    Market.price = newPrice
    Market.lastUpdate = os.time()
    PushHistory(newPrice)

    if DB.ready then
        DB.Execute('INSERT INTO `codex_crypto_market` (`price`) VALUES (@price)', { ['@price'] = newPrice })

        -- Keep the table small, we only need the recent history.
        DB.Execute([[
            DELETE FROM `codex_crypto_market`
            WHERE `id` < (
                SELECT `keep_id` FROM (
                    SELECT MIN(`id`) AS `keep_id` FROM (
                        SELECT `id` FROM `codex_crypto_market` ORDER BY `id` DESC LIMIT @limit
                    ) AS recent
                ) AS boundary
            )
        ]], { ['@limit'] = math.max(2, Crypto.ToInt(Config.Market.HistorySize, 48)) })
    end

    Broadcast()
    Crypto.DebugPrint(('Market updated: %s'):format(newPrice))

    return newPrice
end

function Market.Load()
    Market.history = {}

    if DB.ready then
        local rows = DB.Fetch(('SELECT `price` FROM `codex_crypto_market` ORDER BY `id` DESC LIMIT %d'):format(math.max(2, Crypto.ToInt(Config.Market.HistorySize, 48))))

        for index = #rows, 1, -1 do
            local price = Crypto.ToInt(rows[index].price, 0)
            if price > 0 then
                Market.history[#Market.history + 1] = ClampPrice(price)
            end
        end
    end

    if #Market.history > 0 then
        Market.price = Market.history[#Market.history]
    else
        Market.price = ClampPrice(Crypto.ToNumber(Config.Market.StartPrice, 42000))
        PushHistory(Market.price)
    end

    Market.lastUpdate = os.time()
end

function Market.Start()
    if Market.started then
        return
    end
    Market.started = true

    CreateThread(function()
        local interval = math.max(30, Crypto.ToInt(Config.Market.UpdateInterval, 300))

        while true do
            Wait(interval * 1000)

            local ok, err = pcall(Market.Update)
            if not ok then
                print(('[%s] Market update failed: %s'):format(RESOURCE, err))
            end
        end
    end)
end
