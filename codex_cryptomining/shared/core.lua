--[[
    Shared helpers. Loaded on both sides so client previews and server
    authority always use the exact same formulas.
]]

CodexCrypto = CodexCrypto or {}

local Crypto = CodexCrypto

Crypto.ResourceName = GetCurrentResourceName()

function Crypto.Round(value, decimals)
    local multiplier = 10 ^ (decimals or 0)
    local number = tonumber(value) or 0
    if number >= 0 then
        return math.floor(number * multiplier + 0.5) / multiplier
    end
    return -math.floor(-number * multiplier + 0.5) / multiplier
end

function Crypto.ToNumber(value, fallback)
    local number = tonumber(value)
    if number == nil then
        return fallback or 0
    end
    return number
end

function Crypto.ToInt(value, fallback)
    local number = tonumber(value)
    if number == nil then
        return math.floor(fallback or 0)
    end
    return math.floor(number)
end

function Crypto.ToBool(value)
    return value == true or value == 1 or value == '1' or value == 'true'
end

function Crypto.Clamp(value, minimum, maximum)
    local number = tonumber(value) or 0
    if number < minimum then
        return minimum
    end
    if number > maximum then
        return maximum
    end
    return number
end

function Crypto.TableCount(tbl)
    local count = 0
    if type(tbl) ~= 'table' then
        return 0
    end
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function Crypto.DeepCopy(value)
    if type(value) ~= 'table' then
        return value
    end

    local copy = {}
    for key, nested in pairs(value) do
        copy[key] = Crypto.DeepCopy(nested)
    end
    return copy
end

--- Interior definition of a warehouse, never nil for a valid warehouse.
function Crypto.GetInteriorConfig(warehouseType)
    local interiors = Config and Config.Interiors or {}
    return interiors[warehouseType or 'small'] or interiors.small
end

function Crypto.GetWarehouseConfig(warehouseId)
    for _, warehouse in ipairs(Config and Config.Warehouses or {}) do
        if warehouse.id == warehouseId then
            return warehouse
        end
    end
    return nil
end

function Crypto.GetMaxRigs(warehouseId)
    local warehouse = Crypto.GetWarehouseConfig(warehouseId)
    if not warehouse then
        return 0
    end

    local interior = Crypto.GetInteriorConfig(warehouse.type)
    if not interior then
        return 0
    end

    local slotCount = #(interior.slots or {})
    local maximum = Crypto.ToInt(interior.maxRigs, slotCount)

    if slotCount > 0 and maximum > slotCount then
        maximum = slotCount
    end

    return math.max(0, maximum)
end

function Crypto.GetMaxGpus()
    return math.max(1, Crypto.ToInt(Config.Mining and Config.Mining.MaxGpusPerRig, 8))
end

--- Effective hashrate of a single rig, in MH/s.
function Crypto.GetRigHashrate(rig)
    if not rig or Crypto.ToInt(rig.gpus, 0) <= 0 then
        return 0.0
    end

    if Crypto.ToBool(rig.broken) then
        return 0.0
    end

    local mining = Config.Mining
    local gpus = Crypto.ToInt(rig.gpus, 0)
    local base = gpus * Crypto.ToNumber(mining.HashPerGpu, 25.0)

    local cpuLevel = Crypto.Clamp(Crypto.ToInt(rig.cpu, 0), 0, Crypto.ToInt(mining.Cpu.MaxLevel, 3))
    base = base * (1.0 + cpuLevel * Crypto.ToNumber(mining.Cpu.Bonus, 0.15))

    local durability = Crypto.Clamp(Crypto.ToNumber(rig.durability, 100.0), 0.0, 100.0)
    local minFactor = Crypto.Clamp(Crypto.ToNumber(mining.Durability.MinFactor, 0.45), 0.05, 1.0)
    local factor = minFactor + (1.0 - minFactor) * (durability / 100.0)

    return Crypto.Round(base * factor, 2)
end

--- Total hashrate of a list of rigs.
function Crypto.GetTotalHashrate(rigs)
    local total = 0.0
    for _, rig in pairs(rigs or {}) do
        total = total + Crypto.GetRigHashrate(rig)
    end
    return Crypto.Round(total, 2)
end

--- BTC produced by a hashrate during `seconds`.
function Crypto.GetProduction(hashrate, seconds)
    local perHash = Crypto.ToNumber(Config.Mining.BtcPerHashHour, 0.0000045)
    return Crypto.ToNumber(hashrate, 0) * perHash * (Crypto.ToNumber(seconds, 0) / 3600.0)
end

--- Power draw of a warehouse in kW.
function Crypto.GetPowerLoad(rigs, warehouseId)
    local electricity = Config.Electricity or {}
    if electricity.Enabled == false then
        return 0.0
    end

    local load = Crypto.ToNumber(electricity.BaseLoad, 0.0)
    local rigLoad = Crypto.ToNumber(electricity.RigLoad, 0.0)
    local gpuLoad = Crypto.ToNumber(electricity.GpuLoad, 0.0)

    for _, rig in pairs(rigs or {}) do
        if not Crypto.ToBool(rig.broken) then
            load = load + rigLoad + (Crypto.ToInt(rig.gpus, 0) * gpuLoad)
        end
    end

    local warehouse = Crypto.GetWarehouseConfig(warehouseId)
    local multiplier = warehouse and Crypto.ToNumber(warehouse.electricity, 1.0) or 1.0

    return Crypto.Round(load * multiplier, 3)
end

--- Money value of an amount of BTC at a given price, fee included.
function Crypto.GetSellValue(amount, price)
    local fee = Crypto.Clamp(Crypto.ToNumber(Config.Market.SellFee, 0), 0.0, 0.9)
    local gross = Crypto.ToNumber(amount, 0) * Crypto.ToNumber(price, 0)
    return math.floor(gross * (1.0 - fee))
end

function Crypto.FormatMoney(amount)
    local symbol = (Config.Money and Config.Money.Symbol) or '$'
    local number = math.floor(Crypto.ToNumber(amount, 0) + 0.5)
    local formatted = tostring(math.abs(number))
    local left, num, right = formatted:match('^([^%d]*%d)(%d*)(.-)$')

    if num then
        formatted = left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
    end

    if number < 0 then
        return '-' .. symbol .. formatted
    end

    return symbol .. formatted
end

function Crypto.FormatBtc(amount)
    return string.format('%.6f', Crypto.ToNumber(amount, 0))
end

function Crypto.FormatHash(hashrate)
    local value = Crypto.ToNumber(hashrate, 0)
    if value >= 1000 then
        return string.format('%.2f GH/s', value / 1000)
    end
    return string.format('%.1f MH/s', value)
end

--- Translation helper. Falls back to English, then to the raw key, so a
--- missing entry can never crash the resource.
function Crypto.L(key, ...)
    local locales = rawget(_G, 'Locales') or {}
    local selected = locales[(Config and Config.Locale) or 'en'] or {}
    local template = selected[key]

    if template == nil then
        local english = locales.en or {}
        template = english[key]
    end

    if template == nil then
        return tostring(key)
    end

    local count = select('#', ...)
    if count == 0 then
        return template
    end

    local ok, formatted = pcall(string.format, template, ...)
    if ok then
        return formatted
    end

    return template
end

function Crypto.DebugPrint(...)
    if Config and Config.Debug then
        print(('[%s]'):format(Crypto.ResourceName), ...)
    end
end
