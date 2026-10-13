--[[
    server/departments.lua - department registry, ranks, divisions and nodes.

    Departments are completely independent from qb-core/shared/jobs.lua. A
    player belongs to a department through the members table (citizenid), so a
    server can run LSPD, BCSO, FIB, EMS and a private security company at the
    same time without touching the framework job list.
]]

Departments = {}

local RESOURCE = GetCurrentResourceName()
local cache = {}      -- id -> department record
local byName = {}     -- lowercase name -> id
local dirty = {}      -- ids that need to be pushed to clients again

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

-- ---------------------------------------------------------------------------
-- ROW MAPPERS
-- ---------------------------------------------------------------------------
local function mapRank(row)
    return {
        id = tonumber(row.id),
        deptId = tonumber(row.dept_id),
        grade = tonumber(row.grade) or 0,
        label = row.label,
        salary = tonumber(row.salary) or 0,
        boss = tonumber(row.boss) == 1,
        perms = row.perms or ''
    }
end

local function mapNode(row)
    return {
        id = tonumber(row.id),
        deptId = tonumber(row.dept_id),
        type = row.type,
        label = row.label,
        x = tonumber(row.x) or 0.0,
        y = tonumber(row.y) or 0.0,
        z = tonumber(row.z) or 0.0,
        heading = tonumber(row.heading) or 0.0,
        blip = tonumber(row.blip) == 1
    }
end

local function mapDivision(row)
    return {
        id = tonumber(row.id),
        deptId = tonumber(row.dept_id),
        name = row.name,
        label = row.label
    }
end

local function mapDepartment(row)
    return {
        id = tonumber(row.id),
        name = row.name,
        label = row.label,
        type = row.type or 'police',
        color = row.color or '#2f6df6',
        blipSprite = tonumber(row.blip_sprite) or 60,
        blipColor = tonumber(row.blip_color) or 29,
        blipScale = tonumber(row.blip_scale) or 0.9,
        funds = tonumber(row.funds) or 0,
        defaultSalary = tonumber(row.default_salary) or 200,
        createdAt = tonumber(row.created_at) or 0,
        ranks = {},
        nodes = {},
        divisions = {}
    }
end

-- ---------------------------------------------------------------------------
-- LOADING
-- ---------------------------------------------------------------------------
function Departments.Load()
    local p = DB.Prefix
    cache = {}
    byName = {}

    local rows = DB.Fetch(('SELECT * FROM `%sdepartments` ORDER BY `id` ASC'):format(p), {})
    for _, row in ipairs(rows) do
        local dept = mapDepartment(row)
        cache[dept.id] = dept
        byName[tostring(dept.name):lower()] = dept.id
    end

    for _, row in ipairs(DB.Fetch(('SELECT * FROM `%sranks` ORDER BY `grade` ASC'):format(p), {})) do
        local rank = mapRank(row)
        local dept = cache[rank.deptId]
        if dept then
            dept.ranks[#dept.ranks + 1] = rank
        end
    end

    for _, row in ipairs(DB.Fetch(('SELECT * FROM `%snodes` ORDER BY `id` ASC'):format(p), {})) do
        local node = mapNode(row)
        local dept = cache[node.deptId]
        if dept then
            dept.nodes[#dept.nodes + 1] = node
        end
    end

    for _, row in ipairs(DB.Fetch(('SELECT * FROM `%sdivisions` ORDER BY `id` ASC'):format(p), {})) do
        local division = mapDivision(row)
        local dept = cache[division.deptId]
        if dept then
            dept.divisions[#dept.divisions + 1] = division
        end
    end

    log(('loaded %d departments'):format(Core.TableCount(cache)))
    return cache
end

--- Reload a single department from the database and mark it dirty.
function Departments.Refresh(deptId)
    deptId = tonumber(deptId)
    if not deptId then return nil end

    local p = DB.Prefix
    local rows = DB.Fetch(('SELECT * FROM `%sdepartments` WHERE `id` = ?'):format(p), { deptId })
    local dept = rows[1] and mapDepartment(rows[1])

    if not dept then
        cache[deptId] = nil
        dirty[deptId] = 'removed'
        return nil
    end

    for _, row in ipairs(DB.Fetch(('SELECT * FROM `%sranks` WHERE `dept_id` = ? ORDER BY `grade` ASC'):format(p), { deptId })) do
        dept.ranks[#dept.ranks + 1] = mapRank(row)
    end

    for _, row in ipairs(DB.Fetch(('SELECT * FROM `%snodes` WHERE `dept_id` = ? ORDER BY `id` ASC'):format(p), { deptId })) do
        dept.nodes[#dept.nodes + 1] = mapNode(row)
    end

    for _, row in ipairs(DB.Fetch(('SELECT * FROM `%sdivisions` WHERE `dept_id` = ? ORDER BY `id` ASC'):format(p), { deptId })) do
        dept.divisions[#dept.divisions + 1] = mapDivision(row)
    end

    cache[deptId] = dept
    byName[tostring(dept.name):lower()] = deptId
    dirty[deptId] = true
    return dept
end

function Departments.Get(deptId)
    return cache[tonumber(deptId or 0)]
end

function Departments.GetByName(name)
    if not name then return nil end
    return cache[byName[tostring(name):lower()] or 0]
end

function Departments.All()
    return cache
end

function Departments.Count()
    return Core.TableCount(cache)
end

function Departments.IsDirty(deptId)
    return dirty[tonumber(deptId or 0)] ~= nil
end

--- Called by main.lua once per second-ish; returns the ids that changed.
function Departments.TakeDirty()
    local list = {}
    for id, state in pairs(dirty) do
        list[#list + 1] = { id = id, state = state }
    end
    dirty = {}
    return list
end

function Departments.MarkDirty(deptId, state)
    dirty[tonumber(deptId or 0)] = state or true
end

-- ---------------------------------------------------------------------------
-- CREATE / UPDATE / DELETE
-- ---------------------------------------------------------------------------
local function normalizeName(name)
    local cleaned = Core.SanitizeText(name, 48):gsub('[^%w%_%-]', '')
    return (cleaned:lower())
end

--- data: { name, label, template, color, blipSprite, blipColor, blipScale, funds }
function Departments.Create(data)
    data = data or {}
    local template = Config.DepartmentTemplates[data.template or 'custom'] or Config.DepartmentTemplates.custom

    local name = normalizeName(data.name)
    if name == '' then return nil, 'invalid_name' end
    if byName[name] then return nil, 'exists' end
    if Departments.Count() >= (Config.Creator.MaxDepartments or 50) then return nil, 'limit' end

    local label = Core.SanitizeLabel(data.label or template.Label, 64)
    if label == '' then label = template.Label end

    local p = DB.Prefix
    local id = DB.Insert(
        ([[INSERT INTO `%sdepartments` (`name`, `label`, `type`, `color`, `blip_sprite`, `blip_color`, `blip_scale`, `funds`, `default_salary`, `created_at`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]]):format(p),
        {
            name,
            label,
            data.type or template.Type or 'police',
            data.color or template.Color or '#2f6df6',
            tonumber(data.blipSprite) or template.BlipSprite or 60,
            tonumber(data.blipColor) or template.BlipColor or 29,
            tonumber(data.blipScale) or template.BlipScale or 0.9,
            math.floor(tonumber(data.funds) or template.StartingFunds or 0),
            math.floor(tonumber(data.defaultSalary) or template.DefaultSalary or 200),
            os.time()
        }
    )

    if not id then return nil, 'db' end

    -- ranks from the template
    for index, rank in ipairs(template.Ranks or {}) do
        DB.Insert(
            ([[INSERT INTO `%sranks` (`dept_id`, `grade`, `label`, `salary`, `boss`, `perms`) VALUES (?, ?, ?, ?, ?, ?)]]):format(p),
            { tonumber(id), index - 1, Core.SanitizeLabel(rank.label, 48),
              math.floor(tonumber(rank.salary) or 200), rank.boss and 1 or 0,
              Core.EncodePerms(rank.perms or {}) }
        )
    end

    log(('created department %s (id %s)'):format(name, tostring(id)))
    return tonumber(id), Departments.Refresh(id)
end

--- Allowed keys: label, color, blipSprite, blipColor, blipScale, defaultSalary.
function Departments.Update(deptId, data)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end
    data = data or {}

    local p = DB.Prefix
    DB.Execute(
        ([[UPDATE `%sdepartments` SET `label` = ?, `color` = ?, `blip_sprite` = ?, `blip_color` = ?, `blip_scale` = ?, `default_salary` = ?
            WHERE `id` = ?]]):format(p),
        {
            Core.SanitizeLabel(data.label or dept.label, 64),
            tostring(data.color or dept.color):sub(1, 16),
            math.floor(tonumber(data.blipSprite) or dept.blipSprite),
            math.floor(tonumber(data.blipColor) or dept.blipColor),
            tonumber(data.blipScale) or dept.blipScale,
            math.floor(tonumber(data.defaultSalary) or dept.defaultSalary),
            dept.id
        }
    )

    return Departments.Refresh(deptId)
end

function Departments.Delete(deptId)
    local dept = Departments.Get(deptId)
    if not dept then return false end

    local p = DB.Prefix
    local tables = { 'ranks', 'divisions', 'nodes', 'members', 'finance_logs', 'duty_logs',
                     'evidence', 'calls', 'bolos', 'vehicles', 'cameras', 'trackers', 'applications' }

    for _, table_ in ipairs(tables) do
        DB.Execute(('DELETE FROM `%s%s` WHERE `dept_id` = ?'):format(p, table_), { dept.id })
    end

    DB.Execute(('DELETE FROM `%sdepartments` WHERE `id` = ?'):format(p), { dept.id })

    cache[dept.id] = nil
    byName[tostring(dept.name):lower()] = nil
    dirty[dept.id] = 'removed'
    log(('deleted department %s'):format(dept.name))
    return true
end

-- ---------------------------------------------------------------------------
-- RANKS
-- ---------------------------------------------------------------------------
function Departments.CreateRank(deptId, data)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end
    if #dept.ranks >= (Config.Creator.MaxRanks or 20) then return nil, 'limit' end

    data = data or {}
    local grade = tonumber(data.grade)
    if not grade then grade = Core.HighestGrade(dept) + 1 end

    -- keep grades unique, shift the occupant up when needed
    for _, rank in ipairs(dept.ranks) do
        if tonumber(rank.grade) == grade then
            DB.Execute(('UPDATE `%sranks` SET `grade` = ? WHERE `id` = ?'):format(DB.Prefix),
                { grade + 1, rank.id })
        end
    end

    local p = DB.Prefix
    local id = DB.Insert(
        ([[INSERT INTO `%sranks` (`dept_id`, `grade`, `label`, `salary`, `boss`, `perms`) VALUES (?, ?, ?, ?, ?, ?)]]):format(p),
        {
            dept.id, grade,
            Core.SanitizeLabel(data.label or ('Rank ' .. grade), 48),
            math.floor(tonumber(data.salary) or dept.defaultSalary),
            data.boss and 1 or 0,
            Core.EncodePerms(data.perms or {})
        }
    )

    Departments.Refresh(deptId)
    return tonumber(id)
end

function Departments.UpdateRank(rankId, data)
    data = data or {}
    local p = DB.Prefix
    local rows = DB.Fetch(('SELECT * FROM `%sranks` WHERE `id` = ?'):format(p), { tonumber(rankId) })
    local row = rows[1]
    if not row then return nil, 'not_found' end

    DB.Execute(
        ([[UPDATE `%sranks` SET `grade` = ?, `label` = ?, `salary` = ?, `boss` = ?, `perms` = ? WHERE `id` = ?]]):format(p),
        {
            math.floor(tonumber(data.grade) or tonumber(row.grade) or 0),
            Core.SanitizeLabel(data.label or row.label, 48),
            math.floor(tonumber(data.salary) or tonumber(row.salary) or 0),
            (data.boss == nil and tonumber(row.boss) or (data.boss and 1 or 0)),
            data.perms and Core.EncodePerms(data.perms) or (row.perms or ''),
            tonumber(rankId)
        }
    )

    Departments.Refresh(tonumber(row.dept_id))
    return tonumber(rankId)
end

function Departments.DeleteRank(rankId)
    local p = DB.Prefix
    local rows = DB.Fetch(('SELECT * FROM `%sranks` WHERE `id` = ?'):format(p), { tonumber(rankId) })
    local row = rows[1]
    if not row then return false, 'not_found' end

    local dept = Departments.Get(tonumber(row.dept_id))
    if dept and #dept.ranks <= 1 then return false, 'last_rank' end

    -- move members of this rank to the next lowest rank
    local target = nil
    if dept then
        for _, rank in ipairs(Core.SortedRanks(dept)) do
            if tonumber(rank.id) ~= tonumber(rankId) then target = rank end
        end
    end

    DB.Execute(('UPDATE `%smembers` SET `rank_id` = ? WHERE `rank_id` = ?'):format(p),
        { target and tonumber(target.id) or 0, tonumber(rankId) })
    DB.Execute(('DELETE FROM `%sranks` WHERE `id` = ?'):format(p), { tonumber(rankId) })
    Departments.Refresh(tonumber(row.dept_id))
    return true
end

-- ---------------------------------------------------------------------------
-- DIVISIONS
-- ---------------------------------------------------------------------------
function Departments.CreateDivision(deptId, name, label)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end
    if #dept.divisions >= (Config.Creator.MaxDivisions or 25) then return nil, 'limit' end

    name = Core.SanitizeLabel(name, 32):gsub('%s+', ''):lower()
    if name == '' then return nil, 'invalid_name' end

    for _, division in ipairs(dept.divisions) do
        if division.name == name then return nil, 'exists' end
    end

    local id = DB.Insert(('INSERT INTO `%sdivisions` (`dept_id`, `name`, `label`) VALUES (?, ?, ?)'):format(DB.Prefix),
        { dept.id, name, Core.SanitizeLabel(label or name:upper(), 48) })

    Departments.Refresh(deptId)
    return tonumber(id)
end

function Departments.DeleteDivision(deptId, divisionId)
    local p = DB.Prefix
    DB.Execute(('UPDATE `%smembers` SET `division_id` = 0 WHERE `division_id` = ?'):format(p), { tonumber(divisionId) })
    DB.Execute(('DELETE FROM `%sdivisions` WHERE `id` = ? AND `dept_id` = ?'):format(p),
        { tonumber(divisionId), tonumber(deptId) })
    Departments.Refresh(deptId)
    return true
end

-- ---------------------------------------------------------------------------
-- NODES (the "link" points placed in game)
-- ---------------------------------------------------------------------------
--- data: { type, label, x, y, z, heading, blip }
function Departments.AddNode(deptId, data)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end
    if not Core.IsValidNodeType(data and data.type) then return nil, 'invalid_type' end
    if #dept.nodes >= (Config.Creator.MaxNodesPerDepartment or 40) then return nil, 'limit' end

    local nodeConfig = Config.NodeTypes[data.type]
    if nodeConfig.unique then
        for _, node in ipairs(dept.nodes) do
            if node.type == data.type then return nil, 'unique' end
        end
    end

    for _, node in ipairs(dept.nodes) do
        local distance = Core.Distance(node.x, node.y, node.z, data.x, data.y, data.z)
        if distance < (Config.Creator.MinDistanceBetweenNodes or 3.0) then
            return nil, 'too_close'
        end
    end

    local id = DB.Insert(
        ([[INSERT INTO `%snodes` (`dept_id`, `type`, `label`, `x`, `y`, `z`, `heading`, `blip`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)]]):format(DB.Prefix),
        {
            dept.id,
            data.type,
            Core.SanitizeLabel(data.label or nodeConfig.label, 48),
            tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0,
            tonumber(data.heading) or 0.0,
            (data.blip == nil or data.blip) and 1 or 0
        }
    )

    Departments.Refresh(deptId)
    return tonumber(id)
end

function Departments.UpdateNode(nodeId, data)
    local p = DB.Prefix
    local rows = DB.Fetch(('SELECT * FROM `%snodes` WHERE `id` = ?'):format(p), { tonumber(nodeId) })
    local row = rows[1]
    if not row then return nil, 'not_found' end

    DB.Execute(
        ([[UPDATE `%snodes` SET `label` = ?, `x` = ?, `y` = ?, `z` = ?, `heading` = ?, `blip` = ? WHERE `id` = ?]]):format(p),
        {
            Core.SanitizeLabel(data.label or row.label, 48),
            tonumber(data.x) or tonumber(row.x) or 0.0,
            tonumber(data.y) or tonumber(row.y) or 0.0,
            tonumber(data.z) or tonumber(row.z) or 0.0,
            tonumber(data.heading) or tonumber(row.heading) or 0.0,
            (data.blip == nil and tonumber(row.blip) or (data.blip and 1 or 0)),
            tonumber(nodeId)
        }
    )

    Departments.Refresh(tonumber(row.dept_id))
    return tonumber(nodeId)
end

function Departments.DeleteNode(nodeId)
    local p = DB.Prefix
    local rows = DB.Fetch(('SELECT * FROM `%snodes` WHERE `id` = ?'):format(p), { tonumber(nodeId) })
    local row = rows[1]
    if not row then return false end

    DB.Execute(('UPDATE `%svehicles` SET `spawn_node` = 0 WHERE `spawn_node` = ?'):format(p), { tonumber(nodeId) })
    DB.Execute(('DELETE FROM `%snodes` WHERE `id` = ?'):format(p), { tonumber(nodeId) })
    Departments.Refresh(tonumber(row.dept_id))
    return true
end

-- ---------------------------------------------------------------------------
-- FUNDS
-- ---------------------------------------------------------------------------
--- Adds (or subtracts with a negative amount) money and logs it.
function Departments.AddFunds(deptId, amount, logType, name, citizenid)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end

    amount = math.floor(tonumber(amount) or 0)
    local balance = dept.funds + amount
    if balance < 0 then return nil, 'insufficient' end

    DB.Execute(('UPDATE `%sdepartments` SET `funds` = ? WHERE `id` = ?'):format(DB.Prefix),
        { balance, dept.id })

    DB.Insert(
        ([[INSERT INTO `%sfinance_logs` (`dept_id`, `citizenid`, `name`, `type`, `amount`, `balance_after`, `timestamp`)
            VALUES (?, ?, ?, ?, ?, ?, ?)]]):format(DB.Prefix),
        { dept.id, citizenid or nil, name or 'System', logType or 'adjust', amount, balance, os.time() }
    )

    Departments.Refresh(deptId)
    return balance
end

function Departments.SetFunds(deptId, amount)
    local dept = Departments.Get(deptId)
    if not dept then return nil end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 then amount = 0 end

    DB.Execute(('UPDATE `%sdepartments` SET `funds` = ? WHERE `id` = ?'):format(DB.Prefix), { amount, dept.id })
    DB.Insert(
        ([[INSERT INTO `%sfinance_logs` (`dept_id`, `citizenid`, `name`, `type`, `amount`, `balance_after`, `timestamp`)
            VALUES (?, ?, ?, ?, ?, ?, ?)]]):format(DB.Prefix),
        { dept.id, nil, 'System', 'set', amount - dept.funds, amount, os.time() }
    )
    Departments.Refresh(deptId)
    return amount
end

function Departments.FinanceLogs(deptId, limit)
    limit = Core.Clamp(tonumber(limit) or 50, 1, 500)
    return DB.Fetch(
        ([[SELECT * FROM `%sfinance_logs` WHERE `dept_id` = ? ORDER BY `id` DESC LIMIT %d]]):format(DB.Prefix, limit),
        { tonumber(deptId) }
    )
end

-- ---------------------------------------------------------------------------
-- SEED
-- ---------------------------------------------------------------------------
function Departments.SeedDefaults()
    if Departments.Count() > 0 then return false end
    if not (Config.Creator and Config.Creator.SeedDefaults) then return false end

    local id = Departments.Create({
        name = 'lspd',
        label = 'Los Santos Police Department',
        template = 'police'
    })

    if not id then return false end
    log('seeded default LSPD department')
    return true
end
