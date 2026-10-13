--[[
    server/bolo.lua - BOLOs and the ALPR plate lookup.

    Plate BOLOs are shared between every department (police intelligence), so an
    ALPR hit from the Sheriff's Office also alerts LSPD units. Person and
    vehicle-model BOLOs stay inside the department that created them.
]]

Bolo = {}

local RESOURCE = GetCurrentResourceName()

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

local function mapRow(row)
    return {
        id = tonumber(row.id),
        deptId = tonumber(row.dept_id),
        type = row.type,
        value = row.value,
        description = row.description or '',
        createdBy = row.created_by or 'Unknown',
        active = tonumber(row.active) == 1,
        createdAt = tonumber(row.created_at) or 0,
        date = Core.FormatTimestamp(tonumber(row.created_at) or 0)
    }
end

local function isValidType(boloType)
    for _, entry in ipairs(Config.Bolo.Types or {}) do
        if entry.type == boloType then return true end
    end
    return false
end

--- data: { type, value, description }
function Bolo.Create(src, data)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return nil, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return nil, 'not_found' end
    if not Core.HasPerm(dept, member, 'bolo') then return nil, 'no_permission' end

    data = data or {}
    if not isValidType(data.type) then return nil, 'invalid_type' end

    local value = Core.SanitizeLabel(data.value, 48)
    if value == '' then return nil, 'invalid_value' end

    if data.type == 'plate' then
        value = Core.NormalizePlate(value)
        if value == '' then return nil, 'invalid_value' end
    end

    local id = DB.Insert(
        ([[INSERT INTO `%sbolos` (`dept_id`, `type`, `value`, `description`, `created_by`, `active`, `created_at`)
            VALUES (?, ?, ?, ?, ?, 1, ?)]]):format(DB.Prefix),
        {
            dept.id, data.type, value,
            Core.SanitizeText(data.description, 300),
            (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''),
            os.time()
        }
    )

    if not id then return nil, 'db' end

    local entry = { id = tonumber(id), type = data.type, value = value }
    for _, target in ipairs(Duty.OnDutyByType(dept.type)) do
        if target.source then
            TriggerClientEvent(RESOURCE .. ':client:newBolo', target.source, entry)
        end
    end

    log(('%s created %s BOLO %s'):format(citizenid, data.type, value))
    return tonumber(id)
end

function Bolo.List(deptId, onlyActive)
    local query
    if onlyActive then
        query = ('SELECT * FROM `%sbolos` WHERE `dept_id` = ? AND `active` = 1 ORDER BY `id` DESC'):format(DB.Prefix)
    else
        query = ('SELECT * FROM `%sbolos` WHERE `dept_id` = ? ORDER BY `id` DESC'):format(DB.Prefix)
    end

    local rows = DB.Fetch(query, { tonumber(deptId) })
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = mapRow(row) end
    return out
end

function Bolo.SetActive(src, boloId, active)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'bolo') then return false, 'no_permission' end

    local rows = DB.Fetch(('SELECT * FROM `%sbolos` WHERE `id` = ? LIMIT 1'):format(DB.Prefix), { tonumber(boloId) })
    local row = rows[1]
    if not row then return false, 'not_found' end

    -- plate BOLOs are shared, everything else is department owned
    if row.type ~= 'plate' and tonumber(row.dept_id) ~= dept.id then
        return false, 'no_permission'
    end

    DB.Execute(('UPDATE `%sbolos` SET `active` = ? WHERE `id` = ?'):format(DB.Prefix),
        { active and 1 or 0, tonumber(boloId) })
    return true
end

function Bolo.Delete(src, boloId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'bolo') then return false, 'no_permission' end

    local rows = DB.Fetch(('SELECT * FROM `%sbolos` WHERE `id` = ? LIMIT 1'):format(DB.Prefix), { tonumber(boloId) })
    local row = rows[1]
    if not row then return false, 'not_found' end

    if row.type ~= 'plate' and tonumber(row.dept_id) ~= dept.id then
        return false, 'no_permission'
    end

    DB.Execute(('DELETE FROM `%sbolos` WHERE `id` = ?'):format(DB.Prefix), { tonumber(boloId) })
    return true
end

--- ALPR entry point. Returns the matching BOLO row (or nil).
function Bolo.MatchPlate(plate)
    local normalized = Core.NormalizePlate(plate)
    if normalized == '' then return nil end

    local rows = DB.Fetch(
        ([[SELECT * FROM `%sbolos` WHERE `type` = 'plate' AND `active` = 1 AND `value` = ? ORDER BY `id` DESC LIMIT 1]]):format(DB.Prefix),
        { normalized }
    )

    return rows[1] and mapRow(rows[1]) or nil
end

--- Person BOLO lookup, used by the MDT-style person search.
function Bolo.MatchPerson(name)
    local target = Core.SanitizeLabel(name, 64):lower()
    if target == '' then return nil end

    local rows = DB.Fetch(
        ([[SELECT * FROM `%sbolos` WHERE `type` = 'person' AND `active` = 1 ORDER BY `id` DESC LIMIT 50]]):format(DB.Prefix),
        {}
    )

    for _, row in ipairs(rows) do
        if tostring(row.value):lower() == target then return mapRow(row) end
    end
    return nil
end

--- Alert everybody on duty in every department of the given type.
function Bolo.Alert(deptType, payload)
    for _, entry in ipairs(Duty.OnDutyByType(deptType)) do
        if entry.source then
            TriggerClientEvent(RESOURCE .. ':client:alprHit', entry.source, payload)
        end
    end
end
