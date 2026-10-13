--[[
    shared/core.lua - pure helpers shared by client, server and the test suite.
    No natives in here so it can be executed headless.
]]

Core = {}
Core.Version = '1.0.0'

--- Squared distance between two coordinate tables ({x=,y=,z=} or vector3).
function Core.Distance(ax, ay, az, bx, by, bz)
    local dx = (ax or 0) - (bx or 0)
    local dy = (ay or 0) - (by or 0)
    local dz = (az or 0) - (bz or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Core.DistanceVec(a, b)
    return Core.Distance(a and a.x, a and a.y, a and a.z, b and b.x, b and b.y, b and b.z)
end

--- Plates arrive from different sources with random padding/case.
function Core.NormalizePlate(plate)
    if type(plate) ~= 'string' then return '' end
    local cleaned = plate:upper():gsub('[^%w]', '')
    return cleaned
end

function Core.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Core.TableCount(tbl)
    local count = 0
    if tbl then
        for _ in pairs(tbl) do count = count + 1 end
    end
    return count
end

function Core.TableContains(list, value)
    if type(list) ~= 'table' then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

--- Permissions are stored as a comma separated string: 'dispatch,evidence'.
--- 'all' grants everything.
function Core.DecodePerms(perms)
    local out = {}
    if type(perms) ~= 'string' or perms == '' then return out end

    for chunk in perms:gmatch('[^,]+') do
        local word = chunk:match('^%s*(.-)%s*$')
        if word and word ~= '' then out[word] = true end
    end
    return out
end

function Core.EncodePerms(perms)
    if type(perms) == 'string' then return perms end
    if type(perms) ~= 'table' then return '' end

    local list = {}

    -- set form: { dispatch = true, finance = true }
    for key, value in pairs(perms) do
        if value == true or value == 1 then list[#list + 1] = tostring(key) end
    end

    -- array form: { 'dispatch', 'finance' } (used by Config.DepartmentTemplates)
    for _, value in ipairs(perms) do
        if type(value) == 'string' and value ~= '' then list[#list + 1] = value end
    end

    local seen, out = {}, {}
    for _, item in ipairs(list) do
        if not seen[item] then
            seen[item] = true
            out[#out + 1] = item
        end
    end

    table.sort(out)
    return table.concat(out, ',')
end

--- Find a rank row by its database id.
function Core.FindRankById(department, rankId)
    if not department or not department.ranks then return nil end
    rankId = tonumber(rankId)

    for _, rank in pairs(department.ranks) do
        if tonumber(rank.id) == rankId then return rank end
    end
    return nil
end

--- Find a rank row by its grade number (0 based).
function Core.FindRankByGrade(department, grade)
    if not department or not department.ranks then return nil end
    grade = tonumber(grade)
    if not grade then return nil end

    for _, rank in pairs(department.ranks) do
        if tonumber(rank.grade) == grade then return rank end
    end
    return nil
end

--- Highest grade currently defined for a department.
function Core.HighestGrade(department)
    local highest = -1
    if department and department.ranks then
        for _, rank in pairs(department.ranks) do
            local grade = tonumber(rank.grade) or -1
            if grade > highest then highest = grade end
        end
    end
    return highest
end

--- Does `member` (a codex_pc_members row) hold `perm` in `department`?
function Core.HasPerm(department, member, perm)
    if not department or not member or not perm then return false end

    local rank = Core.FindRankById(department, member.rankId)
    if not rank then return false end

    if rank.boss == 1 or rank.boss == true then return true end

    local perms = Core.DecodePerms(rank.perms)
    if perms.all then return true end

    return perms[perm] == true
end

--- Highest rank a member may promote somebody to (their own grade - 1).
function Core.MaxAssignableGrade(department, member)
    local rank = Core.FindRankById(department, member and member.rankId)
    if not rank then return -1 end
    if rank.boss == 1 or rank.boss == true then return Core.HighestGrade(department) end
    return (tonumber(rank.grade) or 0) - 1
end

--- First node of a given type, or nil.
function Core.FindNode(department, nodeType)
    if not department or not department.nodes then return nil end
    for _, node in pairs(department.nodes) do
        if node.type == nodeType then return node end
    end
    return nil
end

function Core.IsValidNodeType(nodeType)
    return Config and Config.NodeTypes and Config.NodeTypes[nodeType] ~= nil
end

--- Sorted rank list (grade ascending) - handy for the NUI.
function Core.SortedRanks(department)
    local out = {}
    if department and department.ranks then
        for _, rank in pairs(department.ranks) do out[#out + 1] = rank end
    end
    table.sort(out, function(a, b) return (tonumber(a.grade) or 0) < (tonumber(b.grade) or 0) end)
    return out
end

function Core.RankLabel(department, rankId)
    local rank = Core.FindRankById(department, rankId)
    return rank and rank.label or 'Unknown'
end

--- Human readable money, used by the NUI and notifications.
function Core.FormatMoney(amount)
    amount = math.floor(tonumber(amount) or 0)
    local negative = amount < 0
    local formatted = tostring(math.abs(amount)):reverse():gsub('(%d%d%d)', '%1,'):reverse()
    formatted = formatted:gsub('^,', '')
    return (negative and '-$' or '$') .. formatted
end

--- '2026-10-13 09:12:00' from a unix timestamp (local time).
function Core.FormatTimestamp(timestamp)
    return os.date('%Y-%m-%d %H:%M:%S', tonumber(timestamp) or os.time())
end

function Core.SecondsToClock(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return ('%02d:%02d'):format(hours, minutes)
end

--- Deterministic short id (call numbers, evidence tags). Not cryptographic.
local sequence = 0
function Core.NextSequence()
    sequence = sequence + 1
    return sequence
end

function Core.ZeroPad(number, length)
    local value = tostring(math.floor(tonumber(number) or 0))
    while #value < length do value = '0' .. value end
    return value
end

--- Shallow copy used before mutating a cached department.
function Core.Clone(table_)
    if type(table_) ~= 'table' then return table_ end
    local copy = {}
    for key, value in pairs(table_) do copy[key] = Core.Clone(value) end
    return copy
end

--- Trim + collapse whitespace for user entered text.
function Core.SanitizeText(input, maxLength)
    if type(input) ~= 'string' then return '' end
    local cleaned = input:gsub('[%c]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    if maxLength and #cleaned > maxLength then
        cleaned = cleaned:sub(1, maxLength)
    end
    return cleaned
end

--- Blocks obvious SQL/control characters in free text that ends up in the DB.
function Core.SanitizeLabel(input, maxLength)
    local text = Core.SanitizeText(input, maxLength)
    return (text:gsub('[\'"\\;]', ''))
end
