--[[
    server/garage.lua - department vehicles, spawn points and impound.

    Vehicles are owned by the department (not by a citizenid), restricted by
    rank, and their fuel/health is saved when they are returned.
]]

Garage = {}

local RESOURCE = GetCurrentResourceName()
local cache = {} -- deptId -> { vehicle, ... }

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

local function mapRow(row)
    return {
        id = tonumber(row.id),
        deptId = tonumber(row.dept_id),
        model = row.model,
        label = row.label,
        plate = row.plate,
        spawnNode = tonumber(row.spawn_node) or 0,
        rankMin = tonumber(row.rank_min) or 0,
        divisionId = tonumber(row.division_id) or 0,
        livery = tonumber(row.livery) or -1,
        fuel = tonumber(row.fuel) or 100,
        bodyHealth = tonumber(row.body_health) or 1000,
        engineHealth = tonumber(row.engine_health) or 1000,
        stored = tonumber(row.stored) == 1,
        impounded = tonumber(row.impounded) == 1,
        outBy = row.out_by
    }
end

function Garage.Load()
    cache = {}
    local rows = DB.Fetch(('SELECT * FROM `%svehicles` ORDER BY `id` ASC'):format(DB.Prefix), {})

    for _, row in ipairs(rows) do
        local vehicle = mapRow(row)
        cache[vehicle.deptId] = cache[vehicle.deptId] or {}
        cache[vehicle.deptId][#cache[vehicle.deptId] + 1] = vehicle
    end

    log(('loaded %d departments with vehicles'):format(Core.TableCount(cache)))
    return cache
end

function Garage.List(deptId)
    return cache[tonumber(deptId or 0)] or {}
end

function Garage.Find(vehicleId)
    for _, list in pairs(cache) do
        for _, vehicle in ipairs(list) do
            if vehicle.id == tonumber(vehicleId) then return vehicle end
        end
    end
    return nil
end

--- Generate a unique plate for a department (max 8 characters).
local function generatePlate(dept)
    local tag = tostring(dept.name or 'PC'):upper():gsub('[^%A]', ''):sub(1, 4)
    if tag == '' then tag = 'PC' end

    for attempt = 1, 50 do
        local candidate = ('%s%03d'):format(tag, math.random(0, 999)):sub(1, 8)
        local existing = DB.Fetch(('SELECT `id` FROM `%svehicles` WHERE `plate` = ? LIMIT 1'):format(DB.Prefix), { candidate })
        if not existing[1] then return candidate end
        _ = attempt
    end

    return ('%s%04d'):format(tag, math.random(1000, 9999)):sub(1, 8)
end

--- data: { model, label, spawnNode, rankMin, divisionId, livery }
function Garage.Add(deptId, data)
    local dept = Departments.Get(deptId)
    if not dept then return nil, 'not_found' end
    data = data or {}

    local model = Core.SanitizeLabel(data.model, 48):lower()
    if model == '' then return nil, 'invalid_model' end

    local spawnNode = tonumber(data.spawnNode) or 0
    if spawnNode > 0 then
        local found = false
        for _, node in ipairs(dept.nodes) do
            if node.id == spawnNode and node.type == 'garage' then found = true break end
        end
        if not found then return nil, 'invalid_node' end
    end

    local id = DB.Insert(
        ([[INSERT INTO `%svehicles` (`dept_id`, `model`, `label`, `plate`, `spawn_node`, `rank_min`, `division_id`, `livery`, `fuel`, `body_health`, `engine_health`, `stored`, `impounded`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 100, 1000, 1000, 1, 0)]]):format(DB.Prefix),
        {
            dept.id, model,
            Core.SanitizeLabel(data.label or model:upper(), 64),
            generatePlate(dept),
            spawnNode,
            math.floor(tonumber(data.rankMin) or 0),
            math.floor(tonumber(data.divisionId) or 0),
            math.floor(tonumber(data.livery) or -1)
        }
    )

    if not id then return nil, 'db' end

    local rows = DB.Fetch(('SELECT * FROM `%svehicles` WHERE `id` = ?'):format(DB.Prefix), { tonumber(id) })
    if not rows[1] then return nil, 'db' end

    local vehicle = mapRow(rows[1])
    cache[dept.id] = cache[dept.id] or {}
    cache[dept.id][#cache[dept.id] + 1] = vehicle
    return vehicle
end

function Garage.Remove(deptId, vehicleId)
    local vehicle = Garage.Find(vehicleId)
    if not vehicle then return false end
    if not vehicle.stored then return false, 'out' end

    DB.Execute(('DELETE FROM `%svehicles` WHERE `id` = ?'):format(DB.Prefix), { vehicle.id })

    local list = cache[tonumber(deptId)] or {}
    for i, entry in ipairs(list) do
        if entry.id == vehicle.id then
            table.remove(list, i)
            break
        end
    end
    return true
end

function Garage.SetImpound(vehicleId, impounded)
    local vehicle = Garage.Find(vehicleId)
    if not vehicle then return false end

    vehicle.impounded = impounded and true or false
    vehicle.stored = true
    vehicle.outBy = nil

    DB.Execute(('UPDATE `%svehicles` SET `impounded` = ?, `stored` = 1, `out_by` = NULL WHERE `id` = ?'):format(DB.Prefix),
        { vehicle.impounded and 1 or 0, vehicle.id })
    return true
end

--- Marks a vehicle as taken. Returns the row the client should spawn.
function Garage.Spawn(src, vehicleId, nodeId, coords)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return nil, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return nil, 'not_found' end
    if not Core.HasPerm(dept, member, 'garage') then return nil, 'no_permission' end

    local vehicle = Garage.Find(vehicleId)
    if not vehicle or vehicle.deptId ~= dept.id then return nil, 'invalid_vehicle' end
    if vehicle.impounded then return nil, 'impounded' end
    if not vehicle.stored then return nil, 'already_out' end

    local rank = Core.FindRankById(dept, member.rankId)
    local grade = rank and tonumber(rank.grade) or -1
    if grade < (vehicle.rankMin or 0) then return nil, 'rank_too_low' end

    -- spawn point: the garage node the player is standing at
    local node
    for _, candidate in ipairs(dept.nodes) do
        if candidate.id == tonumber(nodeId) then node = candidate break end
    end
    if not node then return nil, 'invalid_node' end

    if coords then
        local distance = Core.Distance(coords.x, coords.y, coords.z, node.x, node.y, node.z)
        if distance > 12.0 then return nil, 'too_far' end
    end

    local maxOut = tonumber(Config.Garage.MaxOutPerPlayer) or 0
    if maxOut > 0 then
        local out = 0
        for _, entry in ipairs(Garage.List(dept.id)) do
            if entry.outBy == citizenid then out = out + 1 end
        end
        if out >= maxOut then return nil, 'too_many_out' end
    end

    vehicle.stored = false
    vehicle.outBy = citizenid

    DB.Execute(('UPDATE `%svehicles` SET `stored` = 0, `out_by` = ? WHERE `id` = ?'):format(DB.Prefix),
        { citizenid, vehicle.id })

    log(('%s spawned %s (%s)'):format(citizenid, vehicle.model, vehicle.plate))

    return {
        id = vehicle.id,
        model = vehicle.model,
        label = vehicle.label,
        plate = vehicle.plate,
        livery = vehicle.livery,
        fuel = vehicle.fuel,
        bodyHealth = vehicle.bodyHealth,
        engineHealth = vehicle.engineHealth,
        coords = { x = node.x, y = node.y, z = node.z, heading = node.heading }
    }
end

--- Saves fuel/health and marks the vehicle stored again.
function Garage.Return(src, vehicleId, state)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local vehicle = Garage.Find(vehicleId)
    if not vehicle or vehicle.deptId ~= member.deptId then return false, 'invalid_vehicle' end

    state = state or {}
    vehicle.stored = true
    vehicle.outBy = nil

    if Config.Garage.SaveStateOnReturn then
        vehicle.fuel = Core.Clamp(math.floor(tonumber(state.fuel) or vehicle.fuel), 0, 100)
        vehicle.bodyHealth = Core.Clamp(math.floor(tonumber(state.bodyHealth) or vehicle.bodyHealth), -4000, 1000)
        vehicle.engineHealth = Core.Clamp(math.floor(tonumber(state.engineHealth) or vehicle.engineHealth), -4000, 1000)
    end

    DB.Execute(
        ([[UPDATE `%svehicles` SET `stored` = 1, `out_by` = NULL, `fuel` = ?, `body_health` = ?, `engine_health` = ?
            WHERE `id` = ?]]):format(DB.Prefix),
        { vehicle.fuel, vehicle.bodyHealth, vehicle.engineHealth, vehicle.id }
    )

    log(('%s returned %s'):format(citizenid, vehicle.plate))
    return true
end

--- A player dropped while a vehicle was out: put it back automatically.
function Garage.ReturnByCitizen(citizenid)
    local removed = 0

    for _, list in pairs(cache) do
        for _, vehicle in ipairs(list) do
            if vehicle.outBy == citizenid then
                vehicle.stored = true
                vehicle.outBy = nil
                DB.Execute(('UPDATE `%svehicles` SET `stored` = 1, `out_by` = NULL WHERE `id` = ?'):format(DB.Prefix),
                    { vehicle.id })
                removed = removed + 1
            end
        end
    end

    return removed
end

--- Fills an empty department garage with the config defaults.
function Garage.Seed(deptId)
    local dept = Departments.Get(deptId)
    if not dept then return 0 end
    if #Garage.List(deptId) > 0 then return 0 end

    local garageNode = Core.FindNode(dept, 'garage')
    local created = 0

    for _, entry in ipairs(Config.Garage.Defaults or {}) do
        local typeOk = (not entry.type) or entry.type == dept.type
        if typeOk then
            local vehicle = Garage.Add(deptId, {
                model = entry.model,
                label = entry.label,
                rankMin = entry.rank,
                livery = entry.livery,
                spawnNode = garageNode and garageNode.id or 0
            })
            if vehicle then created = created + 1 end
        end
    end

    return created
end
