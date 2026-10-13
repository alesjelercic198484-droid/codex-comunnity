--[[
    server/main.lua - startup, events, commands and exports.
]]

local RESOURCE = GetCurrentResourceName()

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

-- ---------------------------------------------------------------------------
-- CONTEXT HELPERS
-- ---------------------------------------------------------------------------

--- Returns ctx or nil + error. ctx = { src, citizenid, member, dept, rank }
local function ctx(src)
    src = tonumber(src)
    if not src then return nil, 'invalid_source' end

    local citizenid = Bridge.GetIdentifier(src)
    if not citizenid then return nil, 'no_character' end

    local member = Members.Get(citizenid)
    if not member then return nil, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return nil, 'not_found' end

    return {
        src = src,
        citizenid = citizenid,
        member = member,
        dept = dept,
        rank = Core.FindRankById(dept, member.rankId)
    }
end

local function withPerm(src, perm)
    local context, err = ctx(src)
    if not context then return nil, err end
    if not Core.HasPerm(context.dept, context.member, perm) then return nil, 'no_permission' end
    return context
end

local function fail(src, err)
    TriggerClientEvent(RESOURCE .. ':client:notify', tonumber(src),
        'Action failed: ' .. tostring(err or 'unknown'), 'error')
end

local function refreshMenu(src)
    TriggerClientEvent(RESOURCE .. ':client:menuData', tonumber(src), Main.MenuPayload(src))
end

Main = {}

-- ---------------------------------------------------------------------------
-- PAYLOADS
-- ---------------------------------------------------------------------------

--- Data every client needs to draw nodes and blips.
function Main.SyncPayload(src)
    local context = ctx(src)
    local isCreator = Bridge.CanCreate(src) or Bridge.IsAdmin(src)

    local departments = {}
    for id, dept in pairs(Departments.All()) do
        local member = context and context.member.deptId == id and context.member or nil
        local showBlips = (not Config.ShowNodeBlipsToMembersOnly) or member ~= nil or isCreator

        local nodes = {}
        if showBlips then
            for _, node in ipairs(dept.nodes) do
                nodes[#nodes + 1] = node
            end
        end

        departments[#departments + 1] = {
            id = id,
            name = dept.name,
            label = dept.label,
            type = dept.type,
            color = dept.color,
            blipSprite = dept.blipSprite,
            blipColor = dept.blipColor,
            blipScale = dept.blipScale,
            nodes = nodes
        }
    end

    return {
        version = Config.Version,
        canCreate = isCreator,
        deptId = context and context.member.deptId or nil,
        member = context and context.member or nil,
        rank = context and context.rank or nil,
        departments = departments
    }
end

--- Full boss menu payload.
function Main.MenuPayload(src)
    local context, err = ctx(src)
    if not context then return { error = err } end

    local dept, member = context.dept, context.member
    local perms = {}
    for _, perm in ipairs({ 'manage', 'finance', 'ranks', 'divisions', 'applications', 'bolo',
                            'cameras', 'trackers', 'dispatch', 'evidence', 'garage', 'armory', 'creator' }) do
        perms[perm] = Core.HasPerm(dept, member, perm)
    end
    perms.boss = context.rank and (context.rank.boss == true) or false

    return {
        error = nil,
        dept = dept,
        member = member,
        rank = context.rank,
        perms = perms,
        maxGrade = Core.MaxAssignableGrade(dept, member),
        funds = dept.funds,
        members = Members.Payload(dept.id),
        finance = Finance.Logs(dept.id, 40),
        dutyLogs = Duty.Logs(dept.id, 25),
        applications = Members.Applications(dept.id, 30),
        calls = Dispatch.List(dept.id, 30),
        bolos = Bolo.List(dept.id, false),
        evidence = Evidence.List(dept.id, 60),
        vehicles = Garage.List(dept.id),
        cameras = Cameras.ForMember(dept.id, member),
        trackers = Trackers.List(dept.id, true),
        armory = Armory.Catalog(dept, member),
        codes = Config.Dispatch.Codes,
        boloTypes = Config.Bolo.Types,
        nodeTypes = Config.NodeTypes,
        animations = Config.Animations,
        templates = Config.DepartmentTemplates
    }
end

-- ---------------------------------------------------------------------------
-- STARTUP
-- ---------------------------------------------------------------------------
CreateThread(function()
    Bridge.Init()
    DB.CreateTables()
    Departments.Load()
    Members.Load()
    Garage.Load()
    Duty.CloseOrphans()
    Armory.Restock()

    local memberCount = Members.Count()
    Departments.SeedDefaults()

    -- every department starts with at least one garage node worth of vehicles
    for id in pairs(Departments.All()) do
        Garage.Seed(id)
    end

    -- hand out the useable items
    Bridge.RegisterUsableItem(Config.Trackers.Item, function(source)
        TriggerClientEvent(RESOURCE .. ':client:useTracker', source)
    end)

    Bridge.RegisterUsableItem(Config.Evidence.BagItem, function(source)
        TriggerClientEvent(RESOURCE .. ':client:useEvidenceBag', source)
    end)

    Bridge.OnPlayerLoaded(function(source)
        Members.SyncNameFromSource(source)
        TriggerClientEvent(RESOURCE .. ':client:sync', source, Main.SyncPayload(source))
    end)

    print(('[%s] started (%s departments, %s members)'):format(RESOURCE,
        tostring(Departments.Count()), tostring(memberCount)))
end)

-- keep every client's node/blip list up to date
CreateThread(function()
    while true do
        Wait(2000)

        local changed = Departments.TakeDirty()
        if #changed > 0 then
            for _, src in ipairs(Bridge.GetPlayers()) do
                TriggerClientEvent(RESOURCE .. ':client:sync', src, Main.SyncPayload(src))
            end
        end
    end
end)

-- housekeeping
CreateThread(function()
    while true do
        Wait(60000)
        Finance.PayoutAll(false)
        Evidence.Expire()
        Trackers.Expire()
        Dispatch.Cleanup()
    end
end)

-- ---------------------------------------------------------------------------
-- PLAYER LIFECYCLE
-- ---------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return end

    Members.PlayerDropped(citizenid)
    local returned = Garage.ReturnByCitizen(citizenid)
    if returned > 0 then
        log(('%s dropped, %d vehicles stored'):format(citizenid, returned))
    end
end)

-- ---------------------------------------------------------------------------
-- MENU DATA / DUTY
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:requestMenuData', function()
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:requestSync', function()
    TriggerClientEvent(RESOURCE .. ':client:sync', source, Main.SyncPayload(source))
end)

--- Shared by the /duty command and the NUI button so `source` is never lost.
function Main.ToggleDuty(src)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return fail(src, 'not_a_member') end

    local updated = Duty.SetDuty(citizenid, not member.onDuty)
    if not updated then return fail(src, 'duty') end

    TriggerClientEvent(RESOURCE .. ':client:sync', tonumber(src), Main.SyncPayload(src))
    return updated
end

RegisterNetEvent(RESOURCE .. ':server:toggleDuty', function()
    Main.ToggleDuty(source)
end)

-- ---------------------------------------------------------------------------
-- FINANCE
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:deposit', function(amount)
    local ok, err = Finance.Deposit(source, amount)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:withdraw', function(amount)
    local ok, err = Finance.Withdraw(source, amount)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:bonus', function(citizenid, amount)
    local ok, err = Finance.Bonus(source, citizenid, amount)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

-- ---------------------------------------------------------------------------
-- MEMBERS
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:hire', function(citizenid, firstName, lastName, rankId)
    local context, err = withPerm(source, 'manage')
    if not context then return fail(source, err) end

    local member, hireError = Members.Hire(context.dept.id, citizenid, firstName, lastName, rankId)
    if not member then return fail(source, hireError) end
    refreshMenu(source)
end)

--- Hire somebody standing next to you without typing a citizenid.
RegisterNetEvent(RESOURCE .. ':server:hireNearby', function(rankId)
    local context, err = withPerm(source, 'manage')
    if not context then return fail(source, err) end

    local myCoords = Bridge.GetCoords(source)
    if not myCoords then return fail(source, 'no_coords') end

    for _, other in ipairs(Bridge.GetPlayers()) do
        if other ~= context.src then
            local otherCoords = Bridge.GetCoords(other)
            if otherCoords and Core.DistanceVec(myCoords, otherCoords) <= 3.0 then
                local citizenid = Bridge.GetIdentifier(other)
                local first, last = Bridge.GetCharName(other)
                local member, hireError = Members.Hire(context.dept.id, citizenid, first, last, rankId)
                if not member then return fail(source, hireError) end
                refreshMenu(source)
                return
            end
        end
    end

    fail(source, 'nobody_nearby')
end)

RegisterNetEvent(RESOURCE .. ':server:fire', function(citizenid)
    local context, err = withPerm(source, 'manage')
    if not context then return fail(source, err) end

    local target = Members.Get(citizenid)
    if not target or target.deptId ~= context.dept.id then return fail(source, 'not_in_department') end

    local myGrade = context.rank and tonumber(context.rank.grade) or -1
    local targetRank = Core.FindRankById(context.dept, target.rankId)
    local targetGrade = targetRank and tonumber(targetRank.grade) or -1
    if targetGrade >= myGrade and not (context.rank and context.rank.boss) then
        return fail(source, 'rank_too_low')
    end

    local ok = Members.Fire(citizenid)
    if not ok then return fail(source, 'fire') end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:setRank', function(citizenid, rankId)
    local context, err = withPerm(source, 'manage')
    if not context then return fail(source, err) end

    local target = Members.Get(citizenid)
    if not target or target.deptId ~= context.dept.id then return fail(source, 'not_in_department') end

    local rank = Core.FindRankById(context.dept, rankId)
    if not rank then return fail(source, 'no_rank') end

    if tonumber(rank.grade) > Core.MaxAssignableGrade(context.dept, context.member)
        and not (context.rank and context.rank.boss) then
        return fail(source, 'rank_too_low')
    end

    local updated = Members.SetRank(citizenid, rankId)
    if not updated then return fail(source, 'set_rank') end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:setDivision', function(citizenid, divisionId)
    local context, err = withPerm(source, 'manage')
    if not context then return fail(source, err) end

    local target = Members.Get(citizenid)
    if not target or target.deptId ~= context.dept.id then return fail(source, 'not_in_department') end

    local updated, divError = Members.SetDivision(citizenid, divisionId)
    if not updated then return fail(source, divError) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:setSalary', function(citizenid, salary)
    local context, err = withPerm(source, 'finance')
    if not context then return fail(source, err) end

    local target = Members.Get(citizenid)
    if not target or target.deptId ~= context.dept.id then return fail(source, 'not_in_department') end

    local updated = Members.SetSalary(citizenid, salary)
    if not updated then return fail(source, 'set_salary') end
    refreshMenu(source)
end)

-- ---------------------------------------------------------------------------
-- RANKS / DIVISIONS
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:createRank', function(data)
    local context, err = withPerm(source, 'ranks')
    if not context then return fail(source, err) end

    local id, rankError = Departments.CreateRank(context.dept.id, data)
    if not id then return fail(source, rankError) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:updateRank', function(rankId, data)
    local context, err = withPerm(source, 'ranks')
    if not context then return fail(source, err) end

    local rank = Core.FindRankById(context.dept, rankId)
    if not rank then return fail(source, 'no_rank') end
    if rank.boss and not (context.rank and context.rank.boss) then
        -- only a boss may demote the boss rank
        if data.boss == false then return fail(source, 'boss_only') end
    end

    local updated = Departments.UpdateRank(rankId, data)
    if not updated then return fail(source, 'update_rank') end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:deleteRank', function(rankId)
    local context, err = withPerm(source, 'ranks')
    if not context then return fail(source, err) end

    local rank = Core.FindRankById(context.dept, rankId)
    if not rank then return fail(source, 'no_rank') end
    if rank.boss and not (context.rank and context.rank.boss) then return fail(source, 'boss_only') end

    local ok, deleteError = Departments.DeleteRank(rankId)
    if not ok then return fail(source, deleteError) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:createDivision', function(name, label)
    local context, err = withPerm(source, 'divisions')
    if not context then return fail(source, err) end

    local id, divError = Departments.CreateDivision(context.dept.id, name, label)
    if not id then return fail(source, divError) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:deleteDivision', function(divisionId)
    local context, err = withPerm(source, 'divisions')
    if not context then return fail(source, err) end

    Departments.DeleteDivision(context.dept.id, divisionId)
    refreshMenu(source)
end)

-- ---------------------------------------------------------------------------
-- APPLICATIONS
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:apply', function(deptId, message)
    local citizenid = Bridge.GetIdentifier(source)
    if not citizenid then return fail(source, 'no_character') end

    local id, applyError = Members.Apply(deptId, citizenid, message)
    if not id then return fail(source, applyError) end
    Bridge.Notify(source, 'Application sent', 'success')
end)

RegisterNetEvent(RESOURCE .. ':server:resolveApplication', function(applicationId, decision)
    local context, err = withPerm(source, 'applications')
    if not context then return fail(source, err) end

    if decision ~= 'accepted' and decision ~= 'denied' then return fail(source, 'invalid_decision') end

    local row = Members.ResolveApplication(applicationId, decision)
    if not row then return fail(source, 'application') end
    refreshMenu(source)
end)

-- ---------------------------------------------------------------------------
-- ARMORY
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:armoryTake', function(itemIndex)
    local ok, err = Armory.Take(source, itemIndex)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:armoryStore', function(itemIndex)
    local ok, err = Armory.Store(source, itemIndex)
    if not ok then return fail(source, err) end
end)

-- ---------------------------------------------------------------------------
-- GARAGE
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:garageAdd', function(data)
    local context, err = withPerm(source, 'manage')
    if not context then return fail(source, err) end

    local vehicle, addError = Garage.Add(context.dept.id, data)
    if not vehicle then return fail(source, addError) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:garageRemove', function(vehicleId)
    local context, err = withPerm(source, 'manage')
    if not context then return fail(source, err) end

    local ok = Garage.Remove(context.dept.id, vehicleId)
    if not ok then return fail(source, 'garage_remove') end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:garageImpound', function(vehicleId, impounded)
    local context, err = withPerm(source, 'manage')
    if not context then return fail(source, err) end

    local vehicle = Garage.Find(vehicleId)
    if not vehicle or vehicle.deptId ~= context.dept.id then return fail(source, 'invalid_vehicle') end

    Garage.SetImpound(vehicleId, impounded)
    refreshMenu(source)
end)

--- Called by the client right before it spawns the vehicle.
RegisterNetEvent(RESOURCE .. ':server:garageSpawn', function(vehicleId, nodeId, coords)
    local payload, spawnError = Garage.Spawn(source, vehicleId, nodeId, coords)
    if not payload then return fail(source, spawnError) end

    TriggerClientEvent(RESOURCE .. ':client:spawnVehicle', source, payload)
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:garageReturn', function(vehicleId, state)
    local ok, err = Garage.Return(source, vehicleId, state)
    if not ok then return fail(source, err) end
    Bridge.Notify(source, 'Vehicle stored', 'success')
    refreshMenu(source)
end)

-- ---------------------------------------------------------------------------
-- EVIDENCE
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:evidenceCreate', function(data)
    local id, err = Evidence.Create(source, data)
    if not id then return fail(source, err) end
    Bridge.Notify(source, 'Evidence stored', 'success')
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:evidenceTake', function(evidenceId)
    local ok, err = Evidence.Take(source, evidenceId)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:evidenceDelete', function(evidenceId)
    local ok, err = Evidence.Delete(source, evidenceId)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

-- ---------------------------------------------------------------------------
-- DISPATCH
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:createCall', function(data)
    local payload, err = Dispatch.Create(source, data)
    if not payload then return fail(source, err) end
    Bridge.Notify(source, ('Dispatch notified: %s'):format(payload.code), 'success')
end)

RegisterNetEvent(RESOURCE .. ':server:acceptCall', function(callId)
    local ok, err = Dispatch.Accept(source, callId)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:releaseCall', function(callId)
    local ok, err = Dispatch.Release(source, callId)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:closeCall', function(callId)
    local ok, err = Dispatch.Close(source, callId)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

-- ---------------------------------------------------------------------------
-- BOLO / ALPR
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:boloCreate', function(data)
    local id, err = Bolo.Create(source, data)
    if not id then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:boloToggle', function(boloId, active)
    local ok, err = Bolo.SetActive(source, boloId, active)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:boloDelete', function(boloId)
    local ok, err = Bolo.Delete(source, boloId)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

--- ALPR scan from a client. Rate limited server side.
local alprCooldown = {}

RegisterNetEvent(RESOURCE .. ':server:alprScan', function(plate, vehicleLabel)
    if not Config.ALPR.Enabled then return end

    local citizenid = Bridge.GetIdentifier(source)
    local member = Members.Get(citizenid)
    if not member then return end
    if not Duty.Get(citizenid) then return end

    local key = tostring(plate)
    local now = os.time()
    if alprCooldown[key] and (now - alprCooldown[key]) < (tonumber(Config.ALPR.NotifyCooldown) or 30) then
        return
    end

    local hit = Bolo.MatchPlate(plate)
    if not hit then return end

    alprCooldown[key] = now

    local dept = Departments.Get(member.deptId)
    Bolo.Alert(dept and dept.type or 'police', {
        plate = Core.NormalizePlate(plate),
        label = vehicleLabel or 'Unknown vehicle',
        bolo = hit
    })
end)

-- ---------------------------------------------------------------------------
-- K9
-- ---------------------------------------------------------------------------
local function k9Allowed(src)
    if not Config.K9.Enabled then return nil, 'disabled' end

    local context, err = ctx(src)
    if not context then return nil, err end
    if not Duty.Get(context.citizenid) then return nil, 'off_duty' end

    local grade = context.rank and tonumber(context.rank.grade) or -1
    if grade < (tonumber(Config.K9.MinRank) or 0) then return nil, 'rank_too_low' end

    return context
end

local function sniffPlayer(targetSrc)
    for _, item in ipairs(Config.K9.Contraband or {}) do
        local has = Bridge.HasItem(targetSrc, item, 1)
        if has then return true, item end
    end
    return false
end

RegisterNetEvent(RESOURCE .. ':server:k9SniffPlayer', function(targetSrc)
    local context, err = k9Allowed(source)
    if not context then return fail(source, err) end

    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == source then return end
    if not Bridge.PlayerExists(targetSrc) then return end

    local found, item = sniffPlayer(targetSrc)
    TriggerClientEvent(RESOURCE .. ':client:k9Result', source, {
        found = found,
        label = found and ('scent of ' .. tostring(item)) or nil
    })
end)

RegisterNetEvent(RESOURCE .. ':server:k9SniffVehicle', function(netId)
    local context, err = k9Allowed(source)
    if not context then return fail(source, err) end

    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not vehicle or vehicle <= 0 then return end

    local coords = GetEntityCoords(vehicle)
    if not coords then return end

    local found, item, who = false, nil, nil

    for _, other in ipairs(Bridge.GetPlayers()) do
        local otherCoords = Bridge.GetCoords(other)
        if otherCoords and Core.DistanceVec(coords, otherCoords) <= (tonumber(Config.K9.VehicleSniffRange) or 3.5) + 1.5 then
            local hit, itemName = sniffPlayer(other)
            if hit then
                found, item, who = true, itemName, Bridge.GetFullName(other)
                break
            end
        end
    end

    TriggerClientEvent(RESOURCE .. ':client:k9Result', source, {
        found = found,
        label = found and ('scent of ' .. tostring(item) .. ' near ' .. tostring(who)) or nil
    })
end)

-- ---------------------------------------------------------------------------
-- CAMERAS
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:cameraAdd', function(data)
    local context, err = withPerm(source, 'cameras')
    if not context then return fail(source, err) end

    local id = Cameras.Add(context.dept.id, data)
    if not id then return fail(source, 'camera_add') end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:cameraRemove', function(cameraId)
    local ok, err = Cameras.Remove(source, cameraId)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:viewCamera', function(cameraId)
    local context, err = withPerm(source, 'cameras')
    if not context then return fail(source, err) end

    for _, camera in ipairs(Cameras.List(context.dept.id)) do
        if camera.id == tonumber(cameraId) then
            TriggerClientEvent(RESOURCE .. ':client:viewCamera', source, camera)
            return
        end
    end

    fail(source, 'not_found')
end)

-- ---------------------------------------------------------------------------
-- TRACKERS
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:trackerPlace', function(data)
    local id, err = Trackers.Place(source, data)
    if not id then return fail(source, err) end

    TriggerClientEvent(RESOURCE .. ':client:trackerPlaced', source, id)
    Bridge.Notify(source, 'GPS tracker attached', 'success')
end)

RegisterNetEvent(RESOURCE .. ':server:trackerUpdate', function(trackerId, coords)
    Trackers.Update(source, trackerId, coords)
end)

RegisterNetEvent(RESOURCE .. ':server:trackerRemove', function(trackerId)
    local ok, err = Trackers.Remove(source, trackerId)
    if not ok then return fail(source, err) end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:trackerRecover', function(trackerId)
    local ok = Trackers.Recover(source, trackerId)
    if not ok then return fail(source, 'tracker') end
    refreshMenu(source)
end)

-- ---------------------------------------------------------------------------
-- CREATOR (admin)
-- ---------------------------------------------------------------------------
local function creatorOnly(src)
    if Bridge.CanCreate(src) or Bridge.IsAdmin(src) then return true end
    return false
end

RegisterNetEvent(RESOURCE .. ':server:creatorCreate', function(data)
    if not creatorOnly(source) then return fail(source, 'no_permission') end

    local id, err = Departments.Create(data)
    if not id then return fail(source, err) end

    Garage.Seed(id)
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:creatorUpdate', function(deptId, data)
    if not creatorOnly(source) then return fail(source, 'no_permission') end

    local dept = Departments.Update(deptId, data)
    if not dept then return fail(source, 'not_found') end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:creatorDelete', function(deptId)
    if not creatorOnly(source) then return fail(source, 'no_permission') end

    if not Departments.Delete(deptId) then return fail(source, 'not_found') end
    Bridge.Notify(source, 'Department deleted', 'success')
end)

RegisterNetEvent(RESOURCE .. ':server:creatorAddNode', function(deptId, data)
    if not creatorOnly(source) then return fail(source, 'no_permission') end

    local id, err = Departments.AddNode(deptId, data)
    if not id then return fail(source, err) end
    Bridge.Notify(source, ('%s node placed'):format(data.type), 'success')
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:creatorUpdateNode', function(nodeId, data)
    if not creatorOnly(source) then return fail(source, 'no_permission') end

    local id = Departments.UpdateNode(nodeId, data)
    if not id then return fail(source, 'not_found') end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:creatorDeleteNode', function(nodeId)
    if not creatorOnly(source) then return fail(source, 'no_permission') end

    if not Departments.DeleteNode(nodeId) then return fail(source, 'not_found') end
    refreshMenu(source)
end)

RegisterNetEvent(RESOURCE .. ':server:creatorWipe', function()
    if not Bridge.IsAdmin(source) then return fail(source, 'no_permission') end
    DB.Wipe()
    Departments.Load()
    Members.Load()
    Garage.Load()
    Bridge.Notify(source, 'All department data wiped', 'error')
end)

-- ---------------------------------------------------------------------------
-- NODE INTERACTION (single entry point, validated server side)
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':server:useNode', function(deptId, nodeId, nodeType)
    local context, err = ctx(source)
    if not context then return fail(source, err) end
    if tonumber(deptId) ~= context.dept.id then return fail(source, 'wrong_department') end

    local node
    for _, candidate in ipairs(context.dept.nodes) do
        if candidate.id == tonumber(nodeId) and candidate.type == nodeType then
            node = candidate
            break
        end
    end
    if not node then return fail(source, 'invalid_node') end

    local coords = Bridge.GetCoords(source)
    if coords then
        local distance = Core.Distance(coords.x, coords.y, coords.z, node.x, node.y, node.z)
        if distance > (tonumber(Config.NodeRange) or 2.0) + 4.0 then
            return fail(source, 'too_far')
        end
    end

    if nodeType == 'boss' or nodeType == 'computer' or nodeType == 'evidence' then
        refreshMenu(source)
        return
    end

    if nodeType == 'armory' then
        TriggerClientEvent(RESOURCE .. ':client:openArmory', source, Main.MenuPayload(source))
        return
    end

    if nodeType == 'garage' or nodeType == 'impound' then
        TriggerClientEvent(RESOURCE .. ':client:openGarage', source, {
            nodeId = node.id,
            vehicles = Garage.List(context.dept.id),
            grade = context.rank and tonumber(context.rank.grade) or -1,
            impound = nodeType == 'impound'
        })
        return
    end

    if nodeType == 'locker' then
        TriggerClientEvent(RESOURCE .. ':client:openLocker', source)
    end
end)

-- ---------------------------------------------------------------------------
-- COMMANDS
-- ---------------------------------------------------------------------------
RegisterCommand(Config.Commands.Menu or 'dept', function(source)
    local context, err = ctx(source)
    if not context then return fail(source, err) end
    refreshMenu(source)
end, false)

RegisterCommand(Config.Commands.Duty or 'duty', function(source)
    Main.ToggleDuty(source)
end, false)

RegisterCommand(Config.Commands.Creator or 'deptcreator', function(source)
    if not creatorOnly(source) then return fail(source, 'no_permission') end
    TriggerClientEvent(RESOURCE .. ':client:openCreator', source, {
        departments = Departments.All(),
        templates = Config.DepartmentTemplates,
        nodeTypes = Config.NodeTypes
    })
end, false)

RegisterCommand(Config.Commands.Call or '911', function(source, args)
    local description = table.concat(args or {}, ' ')
    Dispatch.Create(source, { code = '10-31', description = description })
end, false)

RegisterCommand(Config.Commands.CallMedic or '912', function(source, args)
    local description = table.concat(args or {}, ' ')
    Dispatch.Create(source, { code = '10-54', description = description })
end, false)

RegisterCommand(Config.Commands.K9 or 'k9', function(source, args)
    local argument = args and args[1]

    if argument then
        TriggerClientEvent(RESOURCE .. ':client:k9Command', source, tostring(argument))
        return
    end

    TriggerClientEvent(RESOURCE .. ':client:k9Command', source, 'deploy')
end, false)

if IsDuplicityVersion and IsDuplicityVersion() then
    RegisterCommand('paysalary', function(source)
        if source ~= 0 and not Bridge.IsAdmin(source) then return end
        local paid, total = Finance.PayoutAll(true)
        print(('[%s] salaries paid to %d members (%s)'):format(RESOURCE, paid, Core.FormatMoney(total)))
    end, true)

    RegisterCommand('deptlist', function(source)
        if source ~= 0 and not Bridge.IsAdmin(source) then return end
        for id, dept in pairs(Departments.All()) do
            print(('[%s] #%s %s (%s) - %d members, funds %s'):format(RESOURCE, tostring(id), dept.label,
                dept.name, Members.CountByDept(id), Core.FormatMoney(dept.funds)))
        end
    end, true)

    RegisterCommand('deptsync', function(source)
        for _, src in ipairs(Bridge.GetPlayers()) do
            TriggerClientEvent(RESOURCE .. ':client:sync', src, Main.SyncPayload(src))
        end
        print(('[%s] re-synced all clients'):format(RESOURCE))
    end, true)
end

-- ---------------------------------------------------------------------------
-- EXPORTS (for phone scripts, MDTs, other resources)
-- ---------------------------------------------------------------------------
exports('IsMember', function(citizenid)
    return Members.Get(citizenid) ~= nil
end)

exports('GetMember', function(citizenid)
    return Members.Get(citizenid)
end)

exports('IsOnDuty', function(citizenid)
    return Duty.Get(citizenid)
end)

exports('GetDepartment', function(idOrName)
    return Departments.Get(idOrName) or Departments.GetByName(idOrName)
end)

exports('GetDepartments', function()
    return Departments.All()
end)

exports('CreateDepartment', function(data)
    return Departments.Create(data)
end)

exports('Hire', function(deptIdOrName, citizenid, firstName, lastName, rankId)
    local dept = Departments.Get(deptIdOrName) or Departments.GetByName(deptIdOrName)
    if not dept then return nil, 'not_found' end
    return Members.Hire(dept.id, citizenid, firstName, lastName, rankId)
end)

exports('Fire', function(citizenid)
    return Members.Fire(citizenid)
end)

exports('CreateCall', function(src, data)
    return Dispatch.Create(src, data)
end)

exports('AddFunds', function(deptIdOrName, amount, logType, name, citizenid)
    local dept = Departments.Get(deptIdOrName) or Departments.GetByName(deptIdOrName)
    if not dept then return nil, 'not_found' end
    return Departments.AddFunds(dept.id, amount, logType, name, citizenid)
end)

exports('AddBolo', function(src, data)
    return Bolo.Create(src, data)
end)

exports('OnDutyByType', function(departmentType)
    return Duty.OnDutyByType(departmentType)
end)
