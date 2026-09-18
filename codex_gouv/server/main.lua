local RESOURCE = GetCurrentResourceName()

local ESX
local callbacksRegistered = false
local lastTazeAt = {}
local lastActionAt = {}
local positions = {}
local armoryItems = {}
local armoryWeapons = {}

local function DebugPrint(message, ...)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message:format(...)))
    end
end

local function TryGetESX()
    if ESX then
        return ESX
    end

    if Config.ESX and Config.ESX.UseExport ~= false then
        local ok, object = pcall(function()
            return exports[Config.ESX.ExportName or 'es_extended']:getSharedObject()
        end)
        if ok and object then
            ESX = object
            return ESX
        end
    end

    TriggerEvent((Config.ESX and Config.ESX.SharedObjectEvent) or 'esx:getSharedObject', function(object)
        ESX = object
    end)

    return ESX
end

local function GetXPlayer(source)
    local esx = TryGetESX()
    return esx and esx.GetPlayerFromId(tonumber(source)) or nil
end

local function GetJob(xPlayer)
    if not xPlayer then
        return nil
    end

    local job = xPlayer.job
    if type(xPlayer.getJob) == 'function' then
        local ok, result = pcall(function()
            return xPlayer.getJob()
        end)
        if ok and result then
            job = result
        end
    end

    return job
end

local function GetJobName(xPlayer)
    local job = GetJob(xPlayer)
    return job and tostring(job.name or ''):lower() or ''
end

local function GetGrade(xPlayer)
    local job = GetJob(xPlayer)
    return tonumber(job and (job.grade or job.grade_level)) or 0
end

local function IsGouv(sourceOrPlayer)
    local xPlayer = type(sourceOrPlayer) == 'table' and sourceOrPlayer or GetXPlayer(sourceOrPlayer)
    if not xPlayer or GetJobName(xPlayer) ~= tostring(Config.Job.Name):lower() then
        return false
    end

    local grade = GetGrade(xPlayer)
    return grade >= tonumber(Config.Job.MinimumGrade or 0) and grade <= tonumber(Config.Job.MaximumGrade or 5)
end

local function IsPolice(sourceOrPlayer)
    local xPlayer = type(sourceOrPlayer) == 'table' and sourceOrPlayer or GetXPlayer(sourceOrPlayer)
    return xPlayer and Config.PoliceJobs[GetJobName(xPlayer)] == true or false
end

local function IsAmbulance(sourceOrPlayer)
    local xPlayer = type(sourceOrPlayer) == 'table' and sourceOrPlayer or GetXPlayer(sourceOrPlayer)
    return xPlayer and Config.AmbulanceJobs[GetJobName(xPlayer)] == true or false
end

local function Notify(source, message, notificationType)
    if source and message and message ~= '' then
        TriggerClientEvent(RESOURCE .. ':notify', tonumber(source), message, notificationType or 'info')
    end
end

local function ToFiniteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function ExtractPlayerId(value)
    if type(value) == 'number' then
        return math.floor(value)
    end

    if type(value) ~= 'string' then
        return nil
    end

    local direct = tonumber(value)
    if direct then
        return math.floor(direct)
    end

    local id = value:match('player[:/]([0-9]+)') or value:match('^char[0-9]*:([0-9]+)$')
    return id and tonumber(id) or nil
end

local function FindPlayerIdInValue(value, depth)
    depth = depth or 0
    if depth > 2 then
        return nil
    end

    local direct = ExtractPlayerId(value)
    if direct then
        return direct
    end

    if type(value) == 'table' then
        for _, key in ipairs({ 'target', 'targetId', 'player', 'playerId', 'serverId', 'source', 'id' }) do
            local candidate = ExtractPlayerId(value[key])
            if candidate then
                return candidate
            end
        end
        for _, nested in pairs(value) do
            local candidate = FindPlayerIdInValue(nested, depth + 1)
            if candidate then
                return candidate
            end
        end
    end

    return nil
end

local function IsOnlinePlayer(source)
    source = tonumber(source)
    return source and GetPlayerName(source) ~= nil and GetXPlayer(source) ~= nil
end

local function GetCoords(source)
    local ped = GetPlayerPed(tonumber(source))
    if not ped or ped == 0 then
        return positions[tonumber(source)]
    end

    local ok, coords = pcall(function()
        return GetEntityCoords(ped)
    end)
    if ok and coords then
        return { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
    end

    return positions[tonumber(source)]
end

local function Distance(a, b)
    if not a or not b then
        return 999999.0
    end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function IsRateLimited(source, action, cooldown)
    local key = ('%s:%s'):format(source, action)
    local now = os.time()
    if lastActionAt[key] and now - lastActionAt[key] < cooldown then
        return true
    end
    lastActionAt[key] = now
    return false
end

local function TazePolice(source, reason)
    source = tonumber(source)
    if not source or not IsPolice(source) then
        return false
    end

    local now = os.time()
    if lastTazeAt[source] and now - lastTazeAt[source] < tonumber(Config.Security.TazeCooldownSeconds or 4) then
        return false
    end

    lastTazeAt[source] = now
    TriggerClientEvent(RESOURCE .. ':forceTaze', source, reason or 'Unauthorized government interaction')
    Notify(source, 'ACCESS DENIED: government immunity protocol activated. You have been tazed.', 'error')
    DebugPrint('Tazed police player %s (%s)', source, reason or 'unknown reason')
    return true
end

local function PunishPoliceInteraction(actor, target, reason)
    actor = tonumber(actor)
    target = tonumber(target)
    if not actor or not target or actor == target then
        return false
    end
    if not IsPolice(actor) or not IsGouv(target) then
        return false
    end

    -- Searching through ox_inventory is denied by the hook regardless of distance.
    -- Cuff events also pass through here, so a police client cannot use a second
    -- script to bypass the target options supplied by this resource.
    TazePolice(actor, reason)
    Notify(target, 'A police officer attempted an unauthorized restraint or search. Protocol enforced.', 'warning')
    return true
end

local function BuildJobInfo(xPlayer)
    local job = GetJob(xPlayer) or {}
    local grade = GetGrade(xPlayer)
    local gradeConfig = Config.Job.Grades[grade] or {}
    return {
        name = tostring(job.name or ''),
        grade = grade,
        gradeName = tostring(job.grade_name or gradeConfig.name or ''),
        gradeLabel = tostring(job.grade_label or gradeConfig.label or job.label or ''),
        label = tostring(job.label or Config.Job.Label)
    }
end

local function BuildPlayerList()
    local players = {}
    for _, rawSource in ipairs(GetPlayers()) do
        local source = tonumber(rawSource)
        local xPlayer = GetXPlayer(source)
        if source and xPlayer then
            local jobName = GetJobName(xPlayer)
            local color = 'civilian'
            if Config.PoliceJobs[jobName] then
                color = 'police'
            elseif Config.AmbulanceJobs[jobName] then
                color = 'ambulance'
            end

            players[#players + 1] = {
                id = source,
                name = GetPlayerName(source) or ('Player ' .. source),
                job = jobName,
                jobLabel = tostring((GetJob(xPlayer) or {}).label or jobName),
                grade = GetGrade(xPlayer),
                color = color,
                coords = GetCoords(source) or { x = 0.0, y = 0.0, z = 0.0 }
            }
        end
    end
    return players
end

local function PublicArmory()
    local items, weapons = {}, {}
    for index, item in ipairs(Config.Armory.Items or {}) do
        items[#items + 1] = {
            index = index,
            name = item.name,
            label = item.label or item.name,
            count = math.min(math.max(1, tonumber(item.count) or 1), tonumber(Config.Armory.MaxItemCount or 50)),
            icon = item.icon or '📦'
        }
    end
    for index, weapon in ipairs(Config.Armory.Weapons or {}) do
        weapons[#weapons + 1] = {
            index = index,
            name = weapon.name,
            label = weapon.label or weapon.name,
            icon = weapon.icon or '🔫'
        }
    end
    return { items = items, weapons = weapons }
end

local function BuildDashboard(source, mode)
    local xPlayer = GetXPlayer(source)
    if not IsGouv(xPlayer) then
        return { ok = false, error = 'This government tablet is restricted to the gouv job.' }
    end

    local players = BuildPlayerList()
    local counts = { total = #players, police = 0, ambulance = 0, civilian = 0 }
    for _, player in ipairs(players) do
        counts[player.color] = (counts[player.color] or 0) + 1
    end

    return {
        ok = true,
        mode = mode or 'mdt',
        title = Config.UI.Title,
        subtitle = Config.UI.Subtitle,
        accent = Config.UI.Accent,
        serverTime = os.date('%H:%M:%S'),
        me = {
            id = tonumber(source),
            name = GetPlayerName(source) or 'Government official',
            job = BuildJobInfo(xPlayer)
        },
        players = players,
        counts = counts,
        map = {
            bounds = Config.Satellite.MapBounds,
            showNames = Config.Satellite.ShowNames,
            showCoordinates = Config.Satellite.ShowCoordinates
        },
        armory = PublicArmory(),
        bridgeEnabled = Config.MDT.Bridge.Enabled == true
    }
end

local function BuildArmoryMaps()
    for _, item in ipairs(Config.Armory.Items or {}) do
        if item.name and item.name ~= '' then
            armoryItems[tostring(item.name):lower()] = item
        end
    end
    for _, weapon in ipairs(Config.Armory.Weapons or {}) do
        if weapon.name and weapon.name ~= '' then
            armoryWeapons[tostring(weapon.name):upper()] = weapon
        end
    end
end

local function CanCarry(source, itemName, count, metadata)
    local ok, result = pcall(function()
        return exports.ox_inventory:CanCarryItem(source, itemName, count, metadata)
    end)
    if not ok then
        return false, 'ox_inventory could not validate the item.'
    end
    if result == false then
        return false, 'There is not enough inventory space.'
    end
    return true
end

local function AddItem(source, itemName, count, metadata)
    local ok, success, response = pcall(function()
        return exports.ox_inventory:AddItem(source, itemName, count, metadata)
    end)
    if not ok then
        return false, 'ox_inventory rejected this item.'
    end
    if success then
        return true
    end
    return false, tostring(response or 'Item is not installed in ox_inventory.')
end

local function RegisterCallbacks()
    if callbacksRegistered or not ESX or type(ESX.RegisterServerCallback) ~= 'function' then
        return
    end

    callbacksRegistered = true

    ESX.RegisterServerCallback(RESOURCE .. ':getDashboard', function(source, callback, mode)
        callback(BuildDashboard(source, tostring(mode or 'mdt')))
    end)

    ESX.RegisterServerCallback(RESOURCE .. ':armoryGive', function(source, callback, data)
        if not IsGouv(source) then
            callback({ ok = false, error = 'Government access required.' })
            return
        end
        if Config.Armory.Enabled == false or IsRateLimited(source, 'armory', 1) then
            callback({ ok = false, error = 'Please wait before requesting another item.' })
            return
        end
        if type(data) ~= 'table' or (data.kind ~= 'item' and data.kind ~= 'weapon') then
            callback({ ok = false, error = 'Invalid arsenal request.' })
            return
        end

        local itemName, count, metadata, displayName
        if data.kind == 'item' then
            local item = armoryItems[tostring(data.name or ''):lower()]
            if not item then
                callback({ ok = false, error = 'That item is not authorized for the government arsenal.' })
                return
            end
            itemName = item.name
            count = math.min(math.max(1, tonumber(item.count) or 1), tonumber(Config.Armory.MaxItemCount or 50))
            displayName = item.label or item.name
        else
            local weapon = armoryWeapons[tostring(data.name or ''):upper()]
            if not weapon then
                callback({ ok = false, error = 'That weapon is not authorized for the government arsenal.' })
                return
            end
            itemName = weapon.name
            count = 1
            metadata = { ammo = math.max(0, math.floor(tonumber(Config.Armory.WeaponAmmo or 250))) }
            displayName = weapon.label or weapon.name
        end

        local canCarry, carryError = CanCarry(source, itemName, count, metadata)
        if not canCarry then
            callback({ ok = false, error = carryError })
            return
        end

        local success, addError = AddItem(source, itemName, count, metadata)
        if not success then
            callback({ ok = false, error = addError })
            return
        end

        Notify(source, ('Issued: %s'):format(displayName), 'success')
        callback({ ok = true, message = ('Issued %s.'):format(displayName) })
    end)
end

RegisterNetEvent(RESOURCE .. ':requestCuff', function(target, mode)
    local source = source
    if not IsGouv(source) or IsRateLimited(source, 'cuff', 1) then
        return
    end

    target = ExtractPlayerId(target)
    mode = mode == 'hard' and 'hard' or 'soft'
    if not target or target == source or not IsOnlinePlayer(target) then
        Notify(source, 'That player is not available.', 'error')
        return
    end
    if Distance(GetCoords(source), GetCoords(target)) > tonumber(Config.Security.MaxInteractionDistance or 8.0) then
        Notify(source, 'Move closer to the person you want to restrain.', 'error')
        return
    end

    TriggerClientEvent(RESOURCE .. ':applyCuff', target, mode, source, Config.Cuffs.AutoReleaseSeconds or false)
    Notify(source, ('%s cuff applied.'):format(mode == 'hard' and 'Hard' or 'Soft'), 'success')
    Notify(target, ('You have been placed in %s cuffs by a government official.'):format(mode == 'hard' and 'hard' or 'soft'), 'warning')
end)

RegisterNetEvent(RESOURCE .. ':removeCuff', function(target)
    local source = source
    if not IsGouv(source) or IsRateLimited(source, 'uncuff', 1) then
        return
    end
    target = ExtractPlayerId(target)
    if not target or target == source or not IsOnlinePlayer(target) then
        return
    end
    if Distance(GetCoords(source), GetCoords(target)) > tonumber(Config.Security.MaxInteractionDistance or 8.0) then
        Notify(source, 'Move closer to remove the cuffs.', 'error')
        return
    end

    TriggerClientEvent(RESOURCE .. ':removeCuff', target)
    Notify(source, 'Cuffs removed.', 'success')
    Notify(target, 'Your cuffs were removed by a government official.', 'info')
end)

RegisterNetEvent(RESOURCE .. ':fine', function(target, amount)
    local source = source
    if not IsGouv(source) or IsRateLimited(source, 'fine', 1) then
        return
    end

    target = ExtractPlayerId(target)
    amount = math.floor(tonumber(amount) or 0)
    if not target or target == source or not IsOnlinePlayer(target) then
        Notify(source, 'That player is not available.', 'error')
        return
    end
    if amount < tonumber(Config.Fines.Minimum or 1) or amount > tonumber(Config.Fines.Maximum or 500000) then
        Notify(source, 'That fine is outside the permitted range.', 'error')
        return
    end
    if Distance(GetCoords(source), GetCoords(target)) > tonumber(Config.Security.MaxInteractionDistance or 8.0) then
        Notify(source, 'Move closer to issue a fine.', 'error')
        return
    end

    local xTarget = GetXPlayer(target)
    if not xTarget then
        return
    end

    local account = tostring(Config.Fines.Account or 'bank')
    local accountData = type(xTarget.getAccount) == 'function' and xTarget.getAccount(account) or nil
    local balance = accountData and tonumber(accountData.money) or nil
    if Config.Fines.RequireFunds and balance and balance < amount then
        Notify(source, 'The target does not have enough money in the selected account.', 'error')
        return
    end

    if type(xTarget.removeAccountMoney) == 'function' then
        xTarget.removeAccountMoney(account, amount, ('Government fine by %s'):format(GetPlayerName(source) or source))
    elseif type(xTarget.removeMoney) == 'function' and account == 'money' then
        xTarget.removeMoney(amount, 'Government fine')
    else
        Notify(source, 'This ESX account configuration cannot issue fines.', 'error')
        return
    end

    Notify(source, ('Fine issued: $%s.'):format(amount), 'success')
    Notify(target, ('You received a government fine of $%s.'):format(amount), 'warning')
end)

-- Called by the protected player's client if a police script managed to set the
-- local cuff flag. It clears on that client and tazes nearby police server-side.
RegisterNetEvent(RESOURCE .. ':unauthorizedRestraint', function()
    local source = source
    if not IsGouv(source) or IsRateLimited(source, 'unauthorized-restraint', tonumber(Config.Security.TazeCooldownSeconds or 4)) then
        return
    end

    local victimCoords = GetCoords(source)
    for _, rawPolice in ipairs(GetPlayers()) do
        local police = tonumber(rawPolice)
        if police and IsPolice(police) and Distance(victimCoords, GetCoords(police)) <= tonumber(Config.Security.UnauthorizedTazeRadius or 10.0) then
            TazePolice(police, 'Unauthorized restraint attempt')
        end
    end
end)

RegisterNetEvent(RESOURCE .. ':updatePosition', function(coords)
    local source = source
    if type(coords) ~= 'table' then
        return
    end
    local x, y, z = ToFiniteNumber(coords.x), ToFiniteNumber(coords.y), ToFiniteNumber(coords.z)
    if not x or not y or not z or math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 5000 then
        return
    end
    positions[source] = { x = x, y = y, z = z, updatedAt = os.time() }
end)

local function InventoryPlayerId(value)
    if type(value) == 'table' then
        return ExtractPlayerId(value.id or value.owner or value.playerId or value.inventoryId)
    end
    return ExtractPlayerId(value)
end

local function RegisterInventoryProtection()
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(500)
    end

    local ok, errorMessage = pcall(function()
        exports.ox_inventory:registerHook('openInventory', function(payload)
            if type(payload) ~= 'table' then
                return
            end
            local actor = tonumber(payload.source)
            local inventoryType = tostring(payload.inventoryType or ''):lower()
            local target = InventoryPlayerId(payload.inventoryId or payload.targetId or payload.playerId)
            if actor and target and actor ~= target and (inventoryType == '' or inventoryType == 'player') and PunishPoliceInteraction(actor, target, 'Attempted to search a gouv inventory') then
                return false
            end
        end, { print = false })

        exports.ox_inventory:registerHook('swapItems', function(payload)
            if type(payload) ~= 'table' then
                return
            end
            local actor = tonumber(payload.source)
            local from = InventoryPlayerId(payload.fromInventory)
            local to = InventoryPlayerId(payload.toInventory)
            local target = from and IsGouv(from) and from or (to and IsGouv(to) and to or nil)
            if actor and target and actor ~= target and PunishPoliceInteraction(actor, target, 'Attempted to take or place an item in a gouv inventory') then
                return false
            end
        end, { print = false })
    end)

    if not ok then
        print(('[%s] Could not register ox_inventory protection hooks: %s'):format(RESOURCE, tostring(errorMessage)))
    else
        print(('[%s] ox_inventory search and transfer protection enabled.'):format(RESOURCE))
    end
end

-- Common ESX/QBCore-style police server events are observed as a second line of
-- defence. The ox_target actions above are the supported API; these hooks punish
-- configured police resources if they try to bypass it.
local blockedPoliceEvents = {
    'esx_policejob:handcuff',
    'esx_policejob:search',
    'esx_policejob:drag',
    'police:server:CuffPlayer',
    'police:server:SearchPlayer',
    'police:server:EscortPlayer'
}

for _, eventName in ipairs(blockedPoliceEvents) do
    RegisterNetEvent(eventName)
    AddEventHandler(eventName, function(...)
        local actor = source
        if not IsPolice(actor) then
            return
        end
        local target = FindPlayerIdInValue({ ... })
        if target then
            PunishPoliceInteraction(actor, target, ('Blocked police event: %s'):format(eventName))
        end
    end)
end

AddEventHandler('playerDropped', function()
    local source = source
    positions[source] = nil
    lastTazeAt[source] = nil
end)

CreateThread(function()
    BuildArmoryMaps()
    while not TryGetESX() do
        Wait(500)
    end
    RegisterCallbacks()
    RegisterInventoryProtection()
end)
