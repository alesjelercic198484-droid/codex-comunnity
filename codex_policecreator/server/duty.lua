--[[
    server/duty.lua - on/off duty state, accrued duty time and duty logs.
]]

Duty = {}

local RESOURCE = GetCurrentResourceName()
local activeLogs = {} -- citizenid -> duty_logs row id

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

--- on = true/false. silent skips the notification (used on playerDropped).
function Duty.SetDuty(citizenid, on, silent)
    local member = Members.Get(citizenid)
    if not member then return nil, 'not_a_member' end

    on = on and true or false
    if member.onDuty == on then return member, 'unchanged' end

    local now = os.time()

    if on then
        member.onDuty = true
        member.dutySince = now

        if Config.Duty.LogToDatabase then
            local id = DB.Insert(
                ([[INSERT INTO `%sduty_logs` (`dept_id`, `citizenid`, `name`, `went_on`, `went_off`, `duration`)
                    VALUES (?, ?, ?, ?, 0, 0)]]):format(DB.Prefix),
                { member.deptId, member.citizenid,
                  (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''), now }
            )
            activeLogs[member.citizenid] = tonumber(id)
        end

        DB.Execute(('UPDATE `%smembers` SET `on_duty` = 1 WHERE `id` = ?'):format(DB.Prefix), { member.id })
    else
        local duration = member.dutySince > 0 and math.max(0, now - member.dutySince) or 0
        member.dutySeconds = (member.dutySeconds or 0) + duration
        member.onDuty = false
        member.dutySince = 0

        DB.Execute(('UPDATE `%smembers` SET `on_duty` = 0, `duty_seconds` = ? WHERE `id` = ?'):format(DB.Prefix),
            { member.dutySeconds, member.id })

        if Config.Duty.LogToDatabase then
            local logId = activeLogs[member.citizenid]
            if logId then
                DB.Execute(('UPDATE `%sduty_logs` SET `went_off` = ?, `duration` = ? WHERE `id` = ?'):format(DB.Prefix),
                    { now, duration, logId })
            end
            activeLogs[member.citizenid] = nil
        end
    end

    local src = Members.OnlineSource(citizenid)
    if src and not silent then
        Bridge.Notify(src, on and 'You are now on duty' or 'You are now off duty', on and 'success' or 'primary')
    end

    -- Tell the rest of the server (dispatch, ALPR, radio bridge).
    TriggerEvent(RESOURCE .. ':server:dutyChanged', citizenid, member.deptId, on)
    log(('%s went %s duty'):format(member.citizenid, on and 'on' or 'off'))

    return member
end

function Duty.Get(citizenid)
    local member = Members.Get(citizenid)
    if not member then return false end
    return member.onDuty == true
end

--- Members of a department that are on duty right now, with their server id.
function Duty.OnDuty(deptId)
    local online = Members.OnlineMap()
    local out = {}

    for _, member in ipairs(Members.ListByDept(deptId)) do
        if member.onDuty then
            out[#out + 1] = {
                citizenid = member.citizenid,
                name = (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''),
                rankId = member.rankId,
                source = online[member.citizenid]
            }
        end
    end

    return out
end

--- Every on-duty member across every department (used by dispatch routing).
function Duty.OnDutyByType(departmentType)
    local out = {}

    for deptId, dept in pairs(Departments.All()) do
        if not departmentType or dept.type == departmentType then
            for _, entry in ipairs(Duty.OnDuty(deptId)) do
                entry.deptId = deptId
                entry.deptLabel = dept.label
                out[#out + 1] = entry
            end
        end
    end

    return out
end

function Duty.Logs(deptId, limit)
    limit = Core.Clamp(tonumber(limit) or 50, 1, 500)
    local rows = DB.Fetch(
        ([[SELECT * FROM `%sduty_logs` WHERE `dept_id` = ? ORDER BY `id` DESC LIMIT %d]]):format(DB.Prefix, limit),
        { tonumber(deptId) }
    )

    local out = {}
    for _, row in ipairs(rows) do
        local duration = tonumber(row.duration) or 0
        out[#out + 1] = {
            id = tonumber(row.id),
            citizenid = row.citizenid,
            name = row.name,
            wentOn = tonumber(row.went_on) or 0,
            wentOff = tonumber(row.went_off) or 0,
            duration = duration,
            clock = Core.SecondsToClock(duration),
            date = Core.FormatTimestamp(tonumber(row.went_on) or 0)
        }
    end
    return out
end

--- Total accrued duty time for one member (stored + current shift).
function Duty.TotalSeconds(member)
    if not member then return 0 end
    local total = tonumber(member.dutySeconds) or 0
    if member.onDuty and member.dutySince and member.dutySince > 0 then
        total = total + math.max(0, os.time() - member.dutySince)
    end
    return total
end

--- Safety net: a resource restart must not leave people flagged on duty.
function Duty.CloseOrphans()
    local rows = DB.Fetch(('SELECT * FROM `%sduty_logs` WHERE `went_off` = 0'):format(DB.Prefix), {})
    local now = os.time()

    for _, row in ipairs(rows) do
        local duration = math.max(0, now - (tonumber(row.went_on) or now))
        DB.Execute(('UPDATE `%sduty_logs` SET `went_off` = ?, `duration` = ? WHERE `id` = ?'):format(DB.Prefix),
            { now, duration, tonumber(row.id) })
    end

    DB.Execute(('UPDATE `%smembers` SET `on_duty` = 0'):format(DB.Prefix), {})

    -- reset the in-memory member cache as well
    for deptId in pairs(Departments.All()) do
        for _, member in ipairs(Members.ListByDept(deptId)) do
            member.onDuty = false
            member.dutySince = 0
        end
    end

    if #rows > 0 then
        log(('closed %d orphaned duty logs'):format(#rows))
    end
end
