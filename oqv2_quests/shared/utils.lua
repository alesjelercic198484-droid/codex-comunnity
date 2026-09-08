--[[ OQV2 QUESTS — Shared helpers | Made with CodeX Dev. ]]

OQ = OQ or {}
OQ.resource   = GetCurrentResourceName()
OQ.version    = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '2.0.0'
OQ.isServer   = IsDuplicityVersion()
OQ.branding   = {
    brand    = Config.UI.brand,
    subtitle = Config.UI.subtitle,
    author   = Config.UI.author,
    footer   = Config.UI.footer,
    version  = OQ.version,
}

-------------------------------------------------------------------------------
-- CONSOLE
-------------------------------------------------------------------------------
local PREFIX = '^5[OQV2]^7 '

function OQ.print(...)
    print(PREFIX .. table.concat({ ... }, ' '))
end

function OQ.debug(...)
    if not Config.Debug then return end
    local parts = {}
    for i = 1, select('#', ...) do
        local v = select(i, ...)
        parts[#parts + 1] = type(v) == 'table' and json.encode(v) or tostring(v)
    end
    print(PREFIX .. '^3[debug]^7 ' .. table.concat(parts, ' '))
end

function OQ.warn(msg)
    print(PREFIX .. '^3[warn]^7 ' .. tostring(msg))
end

function OQ.error(msg)
    print(PREFIX .. '^1[error]^7 ' .. tostring(msg))
end

-------------------------------------------------------------------------------
-- LOCALES
-------------------------------------------------------------------------------
OQ.locale = {}

local function loadLocale(code)
    local raw = LoadResourceFile(OQ.resource, ('locales/%s.json'):format(code))
    if not raw then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil end
    return decoded
end

do
    local data = loadLocale(Config.Locale or 'en')
    if not data then
        OQ.warn(('locale "%s" not found, falling back to "en"'):format(tostring(Config.Locale)))
        data = loadLocale('en') or {}
    end
    OQ.locale = data
end

--- Translate a key with optional {placeholders}.
---@param key string
---@param vars table|nil
---@return string
function OQ.L(key, vars)
    local str = OQ.locale[key]
    if type(str) ~= 'string' then return key end
    if vars then
        str = str:gsub('{(%w+)}', function(k)
            local v = vars[k]
            return v ~= nil and tostring(v) or ('{' .. k .. '}')
        end)
    end
    return str
end

-------------------------------------------------------------------------------
-- TABLE / GENERIC HELPERS
-------------------------------------------------------------------------------
function OQ.deepCopy(orig)
    if type(orig) ~= 'table' then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[OQ.deepCopy(k)] = OQ.deepCopy(v)
    end
    return copy
end

--- Fill missing keys of `target` from `defaults` (recursive, non-destructive).
function OQ.defaults(target, defaultsTbl)
    target = type(target) == 'table' and target or {}
    for k, v in pairs(defaultsTbl) do
        if target[k] == nil then
            target[k] = OQ.deepCopy(v)
        elseif type(v) == 'table' and type(target[k]) == 'table' and not OQ.isArray(v) then
            OQ.defaults(target[k], v)
        end
    end
    return target
end

function OQ.isArray(t)
    if type(t) ~= 'table' then return false end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        n = n + 1
    end
    return n == #t
end

function OQ.count(t)
    local n = 0
    if type(t) ~= 'table' then return 0 end
    for _ in pairs(t) do n = n + 1 end
    return n
end

function OQ.includes(list, value)
    if type(list) ~= 'table' then return false end
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function OQ.trim(s)
    return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

function OQ.round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

function OQ.clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
end

-------------------------------------------------------------------------------
-- IDENTIFIERS
-------------------------------------------------------------------------------
local uidCounter = 0

--- Deterministic-ish unique id: oq_<prefix>_<time36><counter36><rand36>
function OQ.uid(prefix)
    uidCounter = uidCounter + 1
    local function b36(n)
        local chars, out = '0123456789abcdefghijklmnopqrstuvwxyz', ''
        n = math.floor(n)
        repeat
            local d = (n % 36) + 1
            out = chars:sub(d, d) .. out
            n = math.floor(n / 36)
        until n == 0
        return out
    end
    return ('%s_%s%s%s'):format(prefix or 'oq', b36(os.time()), b36(uidCounter), b36(math.random(0, 46655)))
end

function OQ.slug(str)
    return (tostring(str or ''):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''))
end

-------------------------------------------------------------------------------
-- TIME
-------------------------------------------------------------------------------
function OQ.now()
    return os.time()
end

--- Human readable "2h 14m" style duration.
function OQ.humanDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds == 0 then return '0s' end
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    local out = {}
    if d > 0 then out[#out + 1] = d .. 'd' end
    if h > 0 then out[#out + 1] = h .. 'h' end
    if m > 0 and d == 0 then out[#out + 1] = m .. 'm' end
    if s > 0 and d == 0 and h == 0 then out[#out + 1] = s .. 's' end
    return table.concat(out, ' ')
end

--- Is the current in-game hour inside [from, to) ? Handles wrap-around (22 → 5).
function OQ.hourInRange(hour, from, to)
    from, to = tonumber(from) or 0, tonumber(to) or 24
    if from == to then return true end
    if from < to then
        return hour >= from and hour < to
    end
    return hour >= from or hour < to
end

-------------------------------------------------------------------------------
-- MATH / VECTORS
-------------------------------------------------------------------------------
function OQ.toVec3(t)
    if type(t) == 'vector3' then return t end
    if type(t) == 'table' then
        return vec3(tonumber(t.x) or 0.0, tonumber(t.y) or 0.0, tonumber(t.z) or 0.0)
    end
    return vec3(0.0, 0.0, 0.0)
end

function OQ.vecToTable(v)
    if type(v) == 'table' then
        return { x = tonumber(v.x) or 0.0, y = tonumber(v.y) or 0.0, z = tonumber(v.z) or 0.0 }
    end
    return { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 }
end

function OQ.dist(a, b)
    return #(OQ.toVec3(a) - OQ.toVec3(b))
end

-------------------------------------------------------------------------------
-- PROGRESSION MATH  (shared so client & server agree)
-------------------------------------------------------------------------------
--- XP required to go from `level` to `level + 1`.
function OQ.xpForLevel(level)
    local p = Config.Progression
    if level < 1 then level = 1 end
    return math.floor(p.baseXP * (p.curve ^ (level - 1)))
end

--- Resolve a total XP amount into { level, xp, need, percent, total }.
function OQ.resolveXP(totalXP)
    local p = Config.Progression
    totalXP = math.max(0, math.floor(tonumber(totalXP) or 0))
    local level, remaining = 1, totalXP
    while level < p.maxLevel do
        local need = OQ.xpForLevel(level)
        if remaining < need then break end
        remaining = remaining - need
        level = level + 1
    end
    local need = level >= p.maxLevel and 0 or OQ.xpForLevel(level)
    return {
        level   = level,
        xp      = remaining,
        need    = need,
        total   = totalXP,
        percent = need > 0 and OQ.round((remaining / need) * 100, 1) or 100.0,
        max     = level >= p.maxLevel,
    }
end

-------------------------------------------------------------------------------
-- SAFE JSON
-------------------------------------------------------------------------------
function OQ.decode(str, fallback)
    if type(str) == 'table' then return str end
    if type(str) ~= 'string' or str == '' then return fallback end
    local ok, res = pcall(json.decode, str)
    if ok and res ~= nil then return res end
    return fallback
end

function OQ.encode(tbl)
    local ok, res = pcall(json.encode, tbl)
    return ok and res or '{}'
end
