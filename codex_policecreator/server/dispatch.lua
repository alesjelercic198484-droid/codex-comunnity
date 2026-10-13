--[[
    server/dispatch.lua - emergency calls, routing to departments and call logs.
]]

Dispatch = {}

local RESOURCE = GetCurrentResourceName()
local cooldowns = {} -- citizenid -> last call time

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

local function mapRow(row)
    return {
        id = tonumber(row.id),
        deptId = tonumber(row.dept_id),
        code = row.code,
        label = row.label,
        description = row.description or '',
        x = tonumber(row.x) or 0.0,
        y = tonumber(row.y) or 0.0,
        z = tonumber(row.z) or 0.0,
        callerId = tonumber(row.caller_id) or 0,
        callerName = row.caller_name or 'Anonymous',
        status = row.status or 'pending',
        assignedId = tonumber(row.assigned_id) or 0,
        assignedName = row.assigned_name,
        createdAt = tonumber(row.created_at) or 0,
        closedAt = tonumber(row.closed_at) or 0,
        date = Core.FormatTimestamp(tonumber(row.created_at) or 0)
    }
end

local function findCode(code)
    for _, entry in ipairs(Config.Dispatch.Codes or {}) do
        if entry.code == code then return entry end
    end
    return nil
end

--- Push a call to every on-duty member of the receiving departments.
local function broadcast(call, departments)
    for _, deptId in ipairs(departments) do
        for _, entry in ipairs(Duty.OnDuty(deptId)) do
            if entry.source then
                TriggerClientEvent(RESOURCE .. ':client:newCall', entry.source, call)
            end
        end
    end
end

--- data: { code, description, x, y, z, anonymous }
--- departmentType defaults to the code's type ('police' / 'ems').
---
--- A call is routed to every department of the matching type. Each department
--- gets its OWN row, so the payload sent to a department always carries that
--- department's call id - otherwise "accept" would target another dept's row.
function Dispatch.Create(src, data)
    data = data or {}
    src = tonumber(src)

    local code = findCode(data.code)
    if not code then return nil, 'invalid_code' end

    local citizenid = Bridge.GetIdentifier(src)
    local cooldownKey = citizenid or ('src' .. tostring(src))
    local cooldown = tonumber(Config.Dispatch.CallCooldown) or 60
    local last = cooldowns[cooldownKey]

    if Config.Dispatch.CivilianCall and last and (os.time() - last) < cooldown then
        return nil, 'cooldown'
    end

    local coords = data.coords or Bridge.GetCoords(src)
    if data.x then coords = { x = tonumber(data.x), y = tonumber(data.y), z = tonumber(data.z) } end
    if not coords then return nil, 'no_coords' end

    local callerName = data.anonymous and 'Anonymous' or Bridge.GetFullName(src)
    local description = Core.SanitizeText(data.description, 300)

    -- route to every department of the matching type
    local targets = {}
    for deptId, dept in pairs(Departments.All()) do
        if dept.type == code.type then targets[#targets + 1] = deptId end
    end

    if #targets == 0 then return nil, 'no_departments' end

    cooldowns[cooldownKey] = os.time()

    local firstPayload
    local created = 0

    for _, deptId in ipairs(targets) do
        local id = DB.Insert(
            ([[INSERT INTO `%scalls` (`dept_id`, `code`, `label`, `description`, `x`, `y`, `z`, `caller_id`, `caller_name`, `status`, `created_at`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)]]):format(DB.Prefix),
            {
                deptId, code.code, code.label, description,
                tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0,
                src or 0, callerName,
                os.time()
            }
        )

        if id then
            created = created + 1

            local payload = {
                id = tonumber(id),
                deptId = deptId,
                code = code.code,
                label = code.label,
                description = description,
                x = tonumber(coords.x) or 0.0,
                y = tonumber(coords.y) or 0.0,
                z = tonumber(coords.z) or 0.0,
                callerName = callerName,
                status = 'pending',
                priority = code.priority or 1,
                createdAt = os.time(),
                date = Core.FormatTimestamp(os.time())
            }

            firstPayload = firstPayload or payload
            broadcast(payload, { deptId })
        end
    end

    if created == 0 then return nil, 'db' end

    log(('call %s created for %d departments'):format(code.code, created))
    return firstPayload
end

--- Every open call for a department, newest first.
function Dispatch.List(deptId, limit)
    limit = Core.Clamp(tonumber(limit) or 30, 1, 200)
    local rows = DB.Fetch(
        ([[SELECT * FROM `%scalls` WHERE `dept_id` = ? ORDER BY `id` DESC LIMIT %d]]):format(DB.Prefix, limit),
        { tonumber(deptId) }
    )

    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = mapRow(row) end
    return out
end

function Dispatch.Open(deptId)
    local out = {}
    for _, call in ipairs(Dispatch.List(deptId, 60)) do
        if call.status ~= 'closed' then out[#out + 1] = call end
    end
    return out
end

--- status: 'active' | 'pending' | 'closed'
local function setStatus(callId, deptId, status, assignedId, assignedName)
    if status == 'closed' then
        DB.Execute(('UPDATE `%scalls` SET `status` = ?, `assigned_id` = ?, `assigned_name` = ?, `closed_at` = ? WHERE `id` = ? AND `dept_id` = ?'):format(DB.Prefix),
            { status, tonumber(assignedId) or 0, assignedName, os.time(), tonumber(callId), tonumber(deptId) })
    else
        DB.Execute(('UPDATE `%scalls` SET `status` = ?, `assigned_id` = ?, `assigned_name` = ? WHERE `id` = ? AND `dept_id` = ?'):format(DB.Prefix),
            { status, tonumber(assignedId) or 0, assignedName, tonumber(callId), tonumber(deptId) })
    end
end

function Dispatch.Accept(src, callId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'dispatch') then return false, 'no_permission' end
    if not Duty.Get(citizenid) then return false, 'off_duty' end

    local rows = DB.Fetch(('SELECT * FROM `%scalls` WHERE `id` = ? AND `dept_id` = ? LIMIT 1'):format(DB.Prefix),
        { tonumber(callId), dept.id })
    local call = rows[1] and mapRow(rows[1])
    if not call then return false, 'not_found' end
    if call.status == 'closed' then return false, 'closed' end
    if call.status == 'active' and call.assignedId ~= tonumber(src) then return false, 'taken' end

    local name = (member.firstName .. ' ' .. member.lastName):gsub('%s+$', '')
    setStatus(callId, dept.id, 'active', src, name)

    call.status = 'active'
    call.assignedId = tonumber(src)
    call.assignedName = name

    for _, entry in ipairs(Duty.OnDuty(dept.id)) do
        if entry.source then
            TriggerClientEvent(RESOURCE .. ':client:callUpdate', entry.source, call)
        end
    end

    Bridge.Notify(src, ('You are responding to %s - %s'):format(call.code, call.label), 'success')
    return true
end

function Dispatch.Release(src, callId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end

    local rows = DB.Fetch(('SELECT * FROM `%scalls` WHERE `id` = ? AND `dept_id` = ? LIMIT 1'):format(DB.Prefix),
        { tonumber(callId), dept.id })
    local call = rows[1] and mapRow(rows[1])
    if not call then return false, 'not_found' end
    if call.status ~= 'active' then return false, 'not_active' end

    local dept2 = Departments.Get(member.deptId)
    if not Core.HasPerm(dept2, member, 'manage') and call.assignedId ~= tonumber(src) then
        return false, 'not_yours'
    end

    setStatus(callId, dept.id, 'pending', 0, nil)
    call.status = 'pending'
    call.assignedId = 0
    call.assignedName = nil

    for _, entry in ipairs(Duty.OnDuty(dept.id)) do
        if entry.source then
            TriggerClientEvent(RESOURCE .. ':client:callUpdate', entry.source, call)
        end
    end
    return true
end

function Dispatch.Close(src, callId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'dispatch') then return false, 'no_permission' end

    local rows = DB.Fetch(('SELECT * FROM `%scalls` WHERE `id` = ? AND `dept_id` = ? LIMIT 1'):format(DB.Prefix),
        { tonumber(callId), dept.id })
    local call = rows[1] and mapRow(rows[1])
    if not call then return false, 'not_found' end

    setStatus(callId, dept.id, 'closed', call.assignedId, call.assignedName)

    for _, entry in ipairs(Duty.OnDuty(dept.id)) do
        if entry.source then
            TriggerClientEvent(RESOURCE .. ':client:callClosed', entry.source, tonumber(callId))
        end
    end
    return true
end

--- Removes calls older than Config.Dispatch.KeepLogsDays.
function Dispatch.Cleanup()
    local days = tonumber(Config.Dispatch.KeepLogsDays) or 30
    if days <= 0 then return 0 end

    local cutoff = os.time() - (days * 86400)
    return DB.Execute(('DELETE FROM `%scalls` WHERE `closed_at` > 0 AND `closed_at` < ?'):format(DB.Prefix),
        { cutoff }) or 0
end
