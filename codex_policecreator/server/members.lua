--[[
    server/members.lua - who works where, ranks, divisions and applications.
]]

Members = {}

local RESOURCE = GetCurrentResourceName()
local cache = {}       -- citizenid -> member record
local byDepartment = {} -- deptId -> { member, ... }

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

local function mapRow(row)
    return {
        id = tonumber(row.id),
        deptId = tonumber(row.dept_id),
        citizenid = tostring(row.citizenid),
        firstName = row.first_name or 'Unknown',
        lastName = row.last_name or '',
        rankId = tonumber(row.rank_id) or 0,
        divisionId = tonumber(row.division_id) or 0,
        salary = tonumber(row.salary) or 0,
        onDuty = tonumber(row.on_duty) == 1,
        dutySeconds = tonumber(row.duty_seconds) or 0,
        hiredAt = tonumber(row.hired_at) or 0,
        dutySince = tonumber(row.duty_since) or 0
    }
end

local function index(member)
    cache[member.citizenid] = member
    byDepartment[member.deptId] = byDepartment[member.deptId] or {}

    local list = byDepartment[member.deptId]
    for index_, existing in ipairs(list) do
        if existing.citizenid == member.citizenid then
            list[index_] = member
            return
        end
    end
    list[#list + 1] = member
end

local function unindex(member)
    cache[member.citizenid] = nil
    local list = byDepartment[member.deptId]
    if not list then return end

    for i, existing in ipairs(list) do
        if existing.citizenid == member.citizenid then
            table.remove(list, i)
            break
        end
    end
end

function Members.Load()
    cache = {}
    byDepartment = {}

    local rows = DB.Fetch(('SELECT * FROM `%smembers` ORDER BY `id` ASC'):format(DB.Prefix), {})
    for _, row in ipairs(rows) do
        index(mapRow(row))
    end

    log(('loaded %d members'):format(Core.TableCount(cache)))
    return cache
end

function Members.Get(citizenid)
    if not citizenid then return nil end
    return cache[tostring(citizenid)]
end

function Members.ById(memberId)
    for _, member in pairs(cache) do
        if member.id == tonumber(memberId) then return member end
    end
    return nil
end

function Members.ListByDept(deptId)
    return byDepartment[tonumber(deptId or 0)] or {}
end

function Members.CountByDept(deptId)
    return #(byDepartment[tonumber(deptId or 0)] or {})
end

--- Total number of members across every department.
function Members.Count()
    local total = 0
    for _, list in pairs(byDepartment) do
        total = total + #list
    end
    return total
end

--- citizenid -> server id for everybody currently connected.
function Members.OnlineMap()
    local map = {}
    for _, src in ipairs(Bridge.GetPlayers()) do
        local citizenid = Bridge.GetIdentifier(src)
        if citizenid then map[citizenid] = src end
    end
    return map
end

function Members.OnlineSource(citizenid)
    for _, src in ipairs(Bridge.GetPlayers()) do
        if Bridge.GetIdentifier(src) == tostring(citizenid) then return src end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- HIRE / FIRE / PROMOTE
-- ---------------------------------------------------------------------------
--- rankId defaults to the lowest rank of the department.
function Members.Hire(deptId, citizenid, firstName, lastName, rankId)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end

    citizenid = tostring(citizenid or '')
    if citizenid == '' then return nil, 'invalid_citizenid' end
    if cache[citizenid] then return nil, 'already_member' end

    local rank
    if rankId then
        rank = Core.FindRankById(dept, rankId)
    end
    if not rank then
        rank = Core.SortedRanks(dept)[1]
    end
    if not rank then return nil, 'no_ranks' end

    local id = DB.Insert(
        ([[INSERT INTO `%smembers` (`dept_id`, `citizenid`, `first_name`, `last_name`, `rank_id`, `division_id`, `salary`, `on_duty`, `duty_seconds`, `hired_at`)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?)]]):format(DB.Prefix),
        {
            dept.id, citizenid,
            Core.SanitizeLabel(firstName or 'Unknown', 48),
            Core.SanitizeLabel(lastName or '', 48),
            tonumber(rank.id), 0,
            math.floor(tonumber(rank.salary) or dept.defaultSalary),
            os.time()
        }
    )

    if not id then return nil, 'db' end

    local member = {
        id = tonumber(id),
        deptId = dept.id,
        citizenid = citizenid,
        firstName = Core.SanitizeLabel(firstName or 'Unknown', 48),
        lastName = Core.SanitizeLabel(lastName or '', 48),
        rankId = tonumber(rank.id),
        divisionId = 0,
        salary = math.floor(tonumber(rank.salary) or dept.defaultSalary),
        onDuty = false,
        dutySeconds = 0,
        hiredAt = os.time(),
        dutySince = 0
    }
    index(member)

    local src = Members.OnlineSource(citizenid)
    if src then Bridge.Notify(src, ('You were hired by the %s as %s'):format(dept.label, rank.label), 'success') end

    log(('hired %s into %s'):format(citizenid, dept.name))
    return member
end

function Members.Fire(citizenid, reason)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_found' end

    if member.onDuty then
        Duty.SetDuty(citizenid, false)
    end

    DB.Execute(('DELETE FROM `%smembers` WHERE `id` = ?'):format(DB.Prefix), { member.id })
    unindex(member)

    local src = Members.OnlineSource(citizenid)
    if src then
        Bridge.Notify(src, ('You were removed from your department%s'):format(reason and (' (' .. reason .. ')') or ''), 'error')
    end

    return true
end

function Members.SetRank(citizenid, rankId)
    local member = Members.Get(citizenid)
    if not member then return nil, 'not_found' end

    local dept = Departments.Get(member.deptId)
    if not dept then return nil, 'not_found' end

    local rank = Core.FindRankById(dept, rankId)
    if not rank then return nil, 'no_rank' end

    DB.Execute(('UPDATE `%smembers` SET `rank_id` = ?, `salary` = ? WHERE `id` = ?'):format(DB.Prefix),
        { tonumber(rank.id), math.floor(tonumber(rank.salary) or member.salary), member.id })

    member.rankId = tonumber(rank.id)
    member.salary = math.floor(tonumber(rank.salary) or member.salary)

    local src = Members.OnlineSource(citizenid)
    if src then Bridge.Notify(src, ('Your rank is now %s'):format(rank.label), 'success') end

    return member
end

function Members.SetDivision(citizenid, divisionId)
    local member = Members.Get(citizenid)
    if not member then return nil, 'not_found' end

    divisionId = tonumber(divisionId) or 0
    if divisionId > 0 then
        local dept = Departments.Get(member.deptId)
        local found = false
        for _, division in ipairs(dept and dept.divisions or {}) do
            if tonumber(division.id) == divisionId then found = true break end
        end
        if not found then return nil, 'no_division' end
    end

    DB.Execute(('UPDATE `%smembers` SET `division_id` = ? WHERE `id` = ?'):format(DB.Prefix), { divisionId, member.id })
    member.divisionId = divisionId
    return member
end

function Members.SetSalary(citizenid, salary)
    local member = Members.Get(citizenid)
    if not member then return nil, 'not_found' end

    salary = Core.Clamp(math.floor(tonumber(salary) or 0), 0, 100000)
    DB.Execute(('UPDATE `%smembers` SET `salary` = ? WHERE `id` = ?'):format(DB.Prefix), { salary, member.id })
    member.salary = salary
    return member
end

function Members.SetName(citizenid, firstName, lastName)
    local member = Members.Get(citizenid)
    if not member then return nil end

    member.firstName = Core.SanitizeLabel(firstName or member.firstName, 48)
    member.lastName = Core.SanitizeLabel(lastName or member.lastName, 48)

    DB.Execute(('UPDATE `%smembers` SET `first_name` = ?, `last_name` = ? WHERE `id` = ?'):format(DB.Prefix),
        { member.firstName, member.lastName, member.id })
    return member
end

--- Convenience used by main.lua when a member joins and their name changed.
function Members.SyncNameFromSource(src)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return nil end

    local first, last = Bridge.GetCharName(src)
    if first ~= member.firstName or (last or '') ~= member.lastName then
        Members.SetName(citizenid, first, last)
    end
    return member
end

-- ---------------------------------------------------------------------------
-- APPLICATIONS
-- ---------------------------------------------------------------------------
function Members.Apply(deptId, citizenid, message)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end
    if Members.Get(citizenid) then return nil, 'already_member' end

    local p = DB.Prefix
    local existing = DB.Fetch(
        ([[SELECT * FROM `%sapplications` WHERE `dept_id` = ? AND `citizenid` = ? AND `status` = 'pending' LIMIT 1]]):format(p),
        { dept.id, tostring(citizenid) }
    )
    if existing[1] then return nil, 'pending' end

    local first, last = Bridge.GetCharName(Members.OnlineSource(citizenid) or 0)

    local id = DB.Insert(
        ([[INSERT INTO `%sapplications` (`dept_id`, `citizenid`, `first_name`, `last_name`, `message`, `status`, `created_at`)
            VALUES (?, ?, ?, ?, ?, 'pending', ?)]]):format(p),
        { dept.id, tostring(citizenid), first, last, Core.SanitizeText(message, 500), os.time() }
    )

    return tonumber(id)
end

function Members.Applications(deptId, limit)
    limit = Core.Clamp(tonumber(limit) or 50, 1, 200)
    return DB.Fetch(
        ([[SELECT * FROM `%sapplications` WHERE `dept_id` = ? ORDER BY `id` DESC LIMIT %d]]):format(DB.Prefix, limit),
        { tonumber(deptId) }
    )
end

--- decision: 'accepted' | 'denied'
function Members.ResolveApplication(applicationId, decision)
    local p = DB.Prefix
    local rows = DB.Fetch(('SELECT * FROM `%sapplications` WHERE `id` = ?'):format(p), { tonumber(applicationId) })
    local row = rows[1]
    if not row then return nil, 'not_found' end
    if row.status ~= 'pending' then return nil, 'resolved' end

    DB.Execute(('UPDATE `%sapplications` SET `status` = ? WHERE `id` = ?'):format(p),
        { tostring(decision), tonumber(applicationId) })

    if decision == 'accepted' then
        Members.Hire(tonumber(row.dept_id), row.citizenid, row.first_name, row.last_name, nil)
    end

    local src = Members.OnlineSource(row.citizenid)
    if src then
        Bridge.Notify(src, decision == 'accepted' and 'Your department application was accepted'
            or 'Your department application was denied',
            decision == 'accepted' and 'success' or 'error')
    end

    return row
end

--- Payload for the NUI member list, enriched with online state.
function Members.Payload(deptId)
    local dept = Departments.Get(deptId)
    if not dept then return {} end

    local online = Members.OnlineMap()
    local list = {}

    for _, member in ipairs(Members.ListByDept(deptId)) do
        local rank = Core.FindRankById(dept, member.rankId)
        list[#list + 1] = {
            id = member.id,
            citizenid = member.citizenid,
            name = (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''),
            firstName = member.firstName,
            lastName = member.lastName,
            rankId = member.rankId,
            rank = rank and rank.label or 'Unknown',
            grade = rank and rank.grade or 0,
            divisionId = member.divisionId,
            salary = member.salary,
            onDuty = member.onDuty,
            online = online[member.citizenid] ~= nil,
            dutySeconds = member.dutySeconds,
            hiredAt = member.hiredAt
        }
    end

    table.sort(list, function(a, b)
        if a.grade ~= b.grade then return a.grade > b.grade end
        return tostring(a.name) < tostring(b.name)
    end)

    return list
end

--- Called on playerDropped so nobody stays "on duty" forever.
function Members.PlayerDropped(citizenid)
    local member = Members.Get(citizenid)
    if not member then return end

    if member.onDuty then
        Duty.SetDuty(citizenid, false, true)
    end
end
