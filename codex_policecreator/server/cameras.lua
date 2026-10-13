--[[
    server/cameras.lua - manually placed CCTV cameras, viewable from the office PC.
]]

Cameras = {}

local function mapRow(row)
    return {
        id = tonumber(row.id),
        deptId = tonumber(row.dept_id),
        label = row.label,
        x = tonumber(row.x) or 0.0,
        y = tonumber(row.y) or 0.0,
        z = tonumber(row.z) or 0.0,
        heading = tonumber(row.heading) or 0.0,
        rankMin = tonumber(row.rank_min) or 0
    }
end

--- data: { label, x, y, z, heading, rankMin }
function Cameras.Add(deptId, data)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end
    data = data or {}

    local count = DB.Scalar(('SELECT COUNT(*) AS c FROM `%scameras` WHERE `dept_id` = ?'):format(DB.Prefix), { dept.id })
    if count >= (tonumber(Config.Cameras.MaxCams) or 200) then return nil, 'limit' end

    local id = DB.Insert(
        ([[INSERT INTO `%scameras` (`dept_id`, `label`, `x`, `y`, `z`, `heading`, `rank_min`)
            VALUES (?, ?, ?, ?, ?, ?, ?)]]):format(DB.Prefix),
        {
            dept.id,
            Core.SanitizeLabel(data.label or ('Camera ' .. (count + 1)), 48),
            tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0,
            tonumber(data.heading) or 0.0,
            math.floor(tonumber(data.rankMin) or 0)
        }
    )

    return tonumber(id)
end

function Cameras.List(deptId)
    local rows = DB.Fetch(('SELECT * FROM `%scameras` WHERE `dept_id` = ? ORDER BY `id` ASC'):format(DB.Prefix),
        { tonumber(deptId) })

    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = mapRow(row) end
    return out
end

--- Filtered by the member's grade (for the NUI list).
function Cameras.ForMember(deptId, member)
    local dept = Departments.Get(deptId)
    local rank = Core.FindRankById(dept, member and member.rankId)
    local grade = rank and tonumber(rank.grade) or -1

    local out = {}
    for _, camera in ipairs(Cameras.List(deptId)) do
        if grade >= (camera.rankMin or 0) then out[#out + 1] = camera end
    end
    return out
end

function Cameras.Remove(src, cameraId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'cameras') then return false, 'no_permission' end

    DB.Execute(('DELETE FROM `%scameras` WHERE `id` = ? AND `dept_id` = ?'):format(DB.Prefix),
        { tonumber(cameraId), dept.id })
    return true
end
