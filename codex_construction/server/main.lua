local ESX

-- Supports both modern ESX exports and older servers using the shared-object event.
if GetResourceState('es_extended') == 'started' then
    pcall(function() ESX = exports.es_extended:getSharedObject() end)
end
if not ESX then
    TriggerEvent('esx:getSharedObject', function(object) ESX = object end)
end
if not ESX then
    error('[codex_construction] ESX could not be loaded. Start es_extended before this resource.')
end

local session = nil
local locks = {}

local function notify(src, message, kind)
    TriggerClientEvent('codex_construction:notify', src, message, kind or 'inform')
end

local function nearForeman(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local position = GetEntityCoords(ped)
    local c = Config.Foreman.coords
    return #(position - vector3(c.x, c.y, c.z)) <= 5.0
end

local function countCrew()
    local n = 0
    if session then for _ in pairs(session.crew) do n = n + 1 end end
    return n
end

local function publicState(src)
    if not session then return { active = false, players = 0, myId = src } end
    local crew = {}
    for id, member in pairs(session.crew) do
        crew[#crew + 1] = { id = id, name = member.name, completed = member.completed or 0 }
    end
    return {
        active = true, leader = session.leader, myId = src, players = countCrew(), maxPlayers = Config.MaxPlayers,
        started = session.started, endsAt = session.endsAt, crew = crew,
        mine = session.crew[src] ~= nil, myCompleted = session.crew[src] and session.crew[src].completed or 0
    }
end

local function broadcast()
    if not session then return end
    for id in pairs(session.crew) do TriggerClientEvent('codex_construction:state', id, publicState(id)) end
end

local function finishJob()
    if not session then return end
    local completed = session
    session = nil
    for id, member in pairs(completed.crew) do
        if GetPlayerName(id) then
            local xPlayer = ESX.GetPlayerFromId(id)
            if xPlayer then
                xPlayer.addAccountMoney(Config.Account, Config.Payout, 'Construction contract')
                notify(id, ('Contract complete: €%s has been paid into your %s account.'):format(Config.Payout, Config.Account), 'success')
            end
        end
        TriggerClientEvent('codex_construction:jobEnded', id)
    end
end

local function startTimer()
    CreateThread(function()
        local ends = session and session.endsAt or 0
        while session and os.time() < ends do
            Wait(1000)
            if session then
                for id in pairs(session.crew) do TriggerClientEvent('codex_construction:tick', id, session.endsAt) end
            end
        end
        if session then finishJob() end
    end)
end

ESX.RegisterServerCallback('codex_construction:getState', function(src, cb)
    cb(publicState(src))
end)

RegisterNetEvent('codex_construction:open', function()
    local src = source
    if not nearForeman(src) then return end
    TriggerClientEvent('codex_construction:openTablet', src, publicState(src), ESX.GetPlayerFromId(src) and ESX.GetPlayerFromId(src).getName() or GetPlayerName(src))
end)

RegisterNetEvent('codex_construction:create', function()
    local src = source
    if not nearForeman(src) then return notify(src, 'You must be at the foreman to manage a contract.', 'error') end
    if locks[src] then return end
    locks[src] = true
    if session then notify(src, 'A contract is already recruiting. Join it or wait until it is finished.', 'error')
    else
        session = { leader = src, started = false, endsAt = 0, crew = {} }
        session.crew[src] = { name = ESX.GetPlayerFromId(src).getName(), completed = 0, tasks = {} }
        notify(src, 'Crew created. Invite up to three people, then start the contract.', 'success')
    end
    locks[src] = nil
    TriggerClientEvent('codex_construction:state', src, publicState(src))
end)

RegisterNetEvent('codex_construction:join', function()
    local src = source
    if not nearForeman(src) then return notify(src, 'You must be at the foreman to manage a contract.', 'error') end
    if locks[src] or not session or session.started then return notify(src, 'This contract is no longer accepting crew members.', 'error') end
    if session.crew[src] then return notify(src, 'You are already in this crew.', 'error') end
    if countCrew() >= Config.MaxPlayers then return notify(src, 'This crew is full (maximum four players).', 'error') end
    local player = ESX.GetPlayerFromId(src)
    session.crew[src] = { name = player.getName(), completed = 0, tasks = {} }
    broadcast()
    notify(src, 'You joined the construction crew.', 'success')
end)

RegisterNetEvent('codex_construction:leave', function()
    local src = source
    if not nearForeman(src) then return notify(src, 'You must be at the foreman to manage a contract.', 'error') end
    if not session or not session.crew[src] or session.started then return end
    session.crew[src] = nil
    if countCrew() == 0 then session = nil else if session.leader == src then for id in pairs(session.crew) do session.leader = id break end end broadcast() end
end)

RegisterNetEvent('codex_construction:start', function()
    local src = source
    if not nearForeman(src) then return notify(src, 'You must be at the foreman to manage a contract.', 'error') end
    if not session or session.leader ~= src or session.started then return notify(src, 'Only the crew leader can start a waiting contract.', 'error') end
    session.started, session.endsAt = true, os.time() + Config.JobDuration
    local index = 0
    for id, member in pairs(session.crew) do
        index = index + 1
        member.tasks = {}
        -- Different task order per player, while keeping the shared physical site.
        for i = 1, math.min(Config.TaskCount, #Config.Tasks) do member.tasks[((i + index - 2) % #Config.Tasks) + 1] = true end
        TriggerClientEvent('codex_construction:jobStarted', id, session.endsAt, member.tasks)
    end
    broadcast()
    startTimer()
end)

RegisterNetEvent('codex_construction:completeTask', function(taskId)
    local src = source
    taskId = tonumber(taskId)
    if not session or not session.started or not session.crew[src] or not session.crew[src].tasks[taskId] then return end
    local task = Config.Tasks[taskId]
    if not task or session.crew[src].done and session.crew[src].done[taskId] then return end
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local target = vector3(task.coords.x, task.coords.y, task.coords.z)
    if #(coords - target) > 4.0 then return notify(src, 'You are too far from that work point.', 'error') end
    local count = exports.ox_inventory:Search(src, 'count', Config.RequireItem) or 0
    if count < 1 then return notify(src, ('You need a %s.'):format(Config.RequireItem), 'error') end
    if Config.ConsumeItem and not exports.ox_inventory:RemoveItem(src, Config.RequireItem, 1) then
        return notify(src, 'Your tools could not be removed. Try again.', 'error')
    end
    session.crew[src].done = session.crew[src].done or {}
    session.crew[src].done[taskId] = true
    session.crew[src].completed = session.crew[src].completed + 1
    TriggerClientEvent('codex_construction:taskDone', src, taskId)
    broadcast()
end)

AddEventHandler('playerDropped', function()
    local src = source
    if session and session.crew[src] then
        session.crew[src] = nil
        if countCrew() == 0 then session = nil else broadcast() end
    end
end)
