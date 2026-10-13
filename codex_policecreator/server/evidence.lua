--[[
    server/evidence.lua - crime scene evidence, bagging and the evidence board.
]]

Evidence = {}

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
        label = row.label,
        description = row.description or '',
        grade = tonumber(row.grade) or 1,
        x = tonumber(row.x) or 0.0,
        y = tonumber(row.y) or 0.0,
        z = tonumber(row.z) or 0.0,
        officer = row.officer or 'Unknown',
        owner = row.owner or '',
        bagged = tonumber(row.bagged) == 1,
        takenBy = row.taken_by,
        createdAt = tonumber(row.created_at) or 0,
        date = Core.FormatTimestamp(tonumber(row.created_at) or 0)
    }
end

--- data: { label, description, grade, x, y, z, owner }
function Evidence.Create(src, data)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return nil, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return nil, 'not_found' end
    if not Core.HasPerm(dept, member, 'evidence') then return nil, 'no_permission' end
    if not Duty.Get(citizenid) then return nil, 'off_duty' end

    data = data or {}
    if Config.Evidence.RequireBag then
        local has = Bridge.HasItem(src, Config.Evidence.BagItem, 1)
        if not has then return nil, 'no_bags' end
    end

    local grade = Core.Clamp(math.floor(tonumber(data.grade) or 1), 1, #(Config.Evidence.Grades or { 1, 2, 3, 4 }))
    local label = Core.SanitizeLabel(data.label, 64)
    if label == '' then return nil, 'invalid_label' end

    if Config.Evidence.RequireBag and not Bridge.RemoveItem(src, Config.Evidence.BagItem, 1) then
        return nil, 'no_bags'
    end

    local id = DB.Insert(
        ([[INSERT INTO `%sevidence` (`dept_id`, `label`, `description`, `grade`, `x`, `y`, `z`, `officer`, `owner`, `bagged`, `created_at`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)]]):format(DB.Prefix),
        {
            dept.id, label,
            Core.SanitizeText(data.description, 500),
            grade,
            tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0,
            (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''),
            Core.SanitizeLabel(data.owner, 64),
            os.time()
        }
    )

    if not id then
        Bridge.AddItem(src, Config.Evidence.BagItem, 1)
        return nil, 'db'
    end

    log(('%s stored evidence %s'):format(citizenid, label))
    return tonumber(id)
end

function Evidence.List(deptId, limit)
    limit = Core.Clamp(tonumber(limit) or 100, 1, 500)
    local rows = DB.Fetch(
        ([[SELECT * FROM `%sevidence` WHERE `dept_id` = ? ORDER BY `id` DESC LIMIT %d]]):format(DB.Prefix, limit),
        { tonumber(deptId) }
    )

    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = mapRow(row) end
    return out
end

local function find(deptId, evidenceId)
    local rows = DB.Fetch(
        ('SELECT * FROM `%sevidence` WHERE `id` = ? AND `dept_id` = ? LIMIT 1'):format(DB.Prefix),
        { tonumber(evidenceId), tonumber(deptId) }
    )
    return rows[1] and mapRow(rows[1]) or nil
end

--- Take the physical bag out of the board and remove the record.
function Evidence.Take(src, evidenceId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'evidence') then return false, 'no_permission' end

    local entry = find(member.deptId, evidenceId)
    if not entry then return false, 'not_found' end
    if entry.takenBy then return false, 'taken' end

    DB.Execute(('UPDATE `%sevidence` SET `taken_by` = ? WHERE `id` = ?'):format(DB.Prefix),
        { citizenid, entry.id })

    Bridge.AddItem(src, Config.Evidence.BagItem, 1, { evidence = entry.label, id = entry.id })
    Bridge.Notify(src, ('Checked out evidence: %s'):format(entry.label), 'success')
    return true
end

function Evidence.Delete(src, evidenceId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'manage') then return false, 'no_permission' end

    local entry = find(member.deptId, evidenceId)
    if not entry then return false, 'not_found' end

    DB.Execute(('DELETE FROM `%sevidence` WHERE `id` = ?'):format(DB.Prefix), { entry.id })
    log(('%s destroyed evidence %s'):format(citizenid, entry.label))
    return true
end

--- Deletes expired evidence (Config.Evidence.ExpireHours). Returns count.
function Evidence.Expire()
    local hours = tonumber(Config.Evidence.ExpireHours) or 0
    if hours <= 0 then return 0 end

    local cutoff = os.time() - (hours * 3600)
    return DB.Execute(('DELETE FROM `%sevidence` WHERE `created_at` < ? AND `taken_by` IS NULL'):format(DB.Prefix),
        { cutoff }) or 0
end
