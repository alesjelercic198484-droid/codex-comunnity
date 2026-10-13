--[[
    server/trackers.lua - physical GPS trackers that can be stuck on any
    vehicle and followed live from the department office PC.
]]

Trackers = {}

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
        plate = row.plate,
        netId = tonumber(row.net_id) or 0,
        x = tonumber(row.x) or 0.0,
        y = tonumber(row.y) or 0.0,
        z = tonumber(row.z) or 0.0,
        placedBy = row.placed_by or 'Unknown',
        active = tonumber(row.active) == 1,
        createdAt = tonumber(row.created_at) or 0,
        date = Core.FormatTimestamp(tonumber(row.created_at) or 0)
    }
end

--- data: { plate, netId, x, y, z }
function Trackers.Place(src, data)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return nil, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return nil, 'not_found' end
    if not Core.HasPerm(dept, member, 'trackers') then return nil, 'no_permission' end
    if not Duty.Get(citizenid) then return nil, 'off_duty' end

    data = data or {}
    local plate = Core.NormalizePlate(data.plate)
    if plate == '' then return nil, 'no_plate' end

    local item = Config.Trackers.Item
    if item and item ~= '' then
        if not Bridge.HasItem(src, item, 1) then return nil, 'no_item' end
    end

    local limit = tonumber(Config.Trackers.MaxActivePerDept) or 0
    if limit > 0 then
        local active = DB.Scalar(
            ('SELECT COUNT(*) AS c FROM `%strackers` WHERE `dept_id` = ? AND `active` = 1'):format(DB.Prefix),
            { dept.id }
        )
        if active >= limit then return nil, 'limit' end
    end

    if item and item ~= '' and not Bridge.RemoveItem(src, item, 1) then
        return nil, 'no_item'
    end

    local id = DB.Insert(
        ([[INSERT INTO `%strackers` (`dept_id`, `plate`, `net_id`, `x`, `y`, `z`, `placed_by`, `active`, `created_at`)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)]]):format(DB.Prefix),
        {
            dept.id, plate,
            math.floor(tonumber(data.netId) or 0),
            tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0,
            (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''),
            os.time()
        }
    )

    if not id then
        if item and item ~= '' then Bridge.AddItem(src, item, 1) end
        return nil, 'db'
    end

    log(('%s placed tracker on %s'):format(citizenid, plate))
    return tonumber(id)
end

--- The client that placed the tracker keeps sending the vehicle position.
function Trackers.Update(src, trackerId, coords)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false end

    local rows = DB.Fetch(('SELECT * FROM `%strackers` WHERE `id` = ? LIMIT 1'):format(DB.Prefix),
        { tonumber(trackerId) })
    local tracker = rows[1] and mapRow(rows[1])
    if not tracker or tracker.deptId ~= member.deptId or not tracker.active then return false end

    DB.Execute(('UPDATE `%strackers` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?'):format(DB.Prefix),
        { tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0, tracker.id })

    return true
end

function Trackers.List(deptId, onlyActive)
    local query
    if onlyActive then
        query = ('SELECT * FROM `%strackers` WHERE `dept_id` = ? AND `active` = 1 ORDER BY `id` DESC'):format(DB.Prefix)
    else
        query = ('SELECT * FROM `%strackers` WHERE `dept_id` = ? ORDER BY `id` DESC'):format(DB.Prefix)
    end

    local rows = DB.Fetch(query, { tonumber(deptId) })
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = mapRow(row) end
    return out
end

function Trackers.Remove(src, trackerId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'trackers') then return false, 'no_permission' end

    DB.Execute(('UPDATE `%strackers` SET `active` = 0 WHERE `id` = ? AND `dept_id` = ?'):format(DB.Prefix),
        { tonumber(trackerId), dept.id })
    return true
end

--- Gives the tracker item back to whoever placed it when they are online.
function Trackers.Recover(src, trackerId)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false end

    local rows = DB.Fetch(('SELECT * FROM `%strackers` WHERE `id` = ? LIMIT 1'):format(DB.Prefix),
        { tonumber(trackerId) })
    local tracker = rows[1] and mapRow(rows[1])
    if not tracker or tracker.deptId ~= member.deptId or not tracker.active then return false end

    DB.Execute(('UPDATE `%strackers` SET `active` = 0 WHERE `id` = ?'):format(DB.Prefix), { tracker.id })

    local item = Config.Trackers.Item
    if item and item ~= '' then Bridge.AddItem(src, item, 1) end

    Bridge.Notify(src, ('Tracker removed from %s'):format(tracker.plate), 'success')
    return true
end

function Trackers.Expire()
    local hours = tonumber(Config.Trackers.ExpireHours) or 0
    if hours <= 0 then return 0 end

    local cutoff = os.time() - (hours * 3600)
    return DB.Execute(('UPDATE `%strackers` SET `active` = 0 WHERE `active` = 1 AND `created_at` < ?'):format(DB.Prefix),
        { cutoff }) or 0
end
