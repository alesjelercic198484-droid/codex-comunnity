local ESX = exports.es_extended:getSharedObject()
local foreman, props = nil, {}
local active, taskMap, endsAt, working = false, {}, 0, false

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(20) end
    return HasModelLoaded(hash) and hash or nil
end

local function addTarget(entity, label, event, distance)
    exports.ox_target:addLocalEntity(entity, {{ name = 'codex_construction_' .. entity, icon = 'fa-solid fa-helmet-safety', label = label, distance = distance or Config.InteractionDistance, onSelect = function() TriggerEvent(event) end }})
end

CreateThread(function()
    local hash = loadModel(Config.Foreman.model)
    if not hash then print('[codex_construction] Foreman model could not be loaded.') return end
    local c = Config.Foreman.coords
    foreman = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityInvincible(foreman, true); FreezeEntityPosition(foreman, true); SetBlockingOfNonTemporaryEvents(foreman, true)
    addTarget(foreman, Config.Foreman.label, 'codex_construction:open')
    SetModelAsNoLongerNeeded(hash)

    for i, task in ipairs(Config.Tasks) do
        local h = loadModel(task.model)
        if h then
            local p = task.coords
            local object = CreateObject(h, p.x, p.y, p.z, false, false, false)
            SetEntityHeading(object, p.w); FreezeEntityPosition(object, true); SetEntityAsMissionEntity(object, true, true)
            props[i] = object
            exports.ox_target:addLocalEntity(object, {{ name = 'codex_construction_task_' .. i, icon = 'fa-solid fa-screwdriver-wrench', label = task.label, distance = Config.InteractionDistance, onSelect = function() TriggerEvent('codex_construction:work', i) end }})
            SetModelAsNoLongerNeeded(h)
        end
    end
end)

RegisterNetEvent('codex_construction:openTablet', function(state, playerName)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', state = state, player = playerName, payout = Config.Payout, duration = Config.JobDuration })
end)

RegisterNetEvent('codex_construction:state', function(state)
    SendNUIMessage({ action = 'state', state = state })
end)

RegisterNetEvent('codex_construction:jobStarted', function(serverEnds, tasks)
    active, endsAt, taskMap = true, serverEnds, tasks
    SendNUIMessage({ action = 'started', endsAt = serverEnds, tasks = tasks })
end)

RegisterNetEvent('codex_construction:taskDone', function(taskId)
    taskMap[taskId] = nil
    SendNUIMessage({ action = 'taskDone', task = taskId })
end)

RegisterNetEvent('codex_construction:jobEnded', function()
    active, taskMap, endsAt = false, {}, 0
    SendNUIMessage({ action = 'ended' })
end)

RegisterNetEvent('codex_construction:tick', function(serverEnds)
    endsAt = serverEnds
    SendNUIMessage({ action = 'tick', endsAt = serverEnds })
end)

RegisterNetEvent('codex_construction:notify', function(message, kind)
    SendNUIMessage({ action = 'toast', message = message, kind = kind })
end)

RegisterNetEvent('codex_construction:work', function(taskId)
    if working then return end
    if not active or not taskMap[taskId] then return TriggerEvent('codex_construction:notify', 'This work point is not assigned to you.', 'error') end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return TriggerEvent('codex_construction:notify', 'Leave your vehicle first.', 'error') end
    working = true
    local task = Config.Tasks[taskId]
    local duration = 5500
    TaskTurnPedToFaceCoord(ped, task.coords.x, task.coords.y, task.coords.z, 700)
    Wait(500)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, task.scenario or 'WORLD_HUMAN_HAMMERING', 0, true)
    SendNUIMessage({ action = 'progress', label = task.label, duration = duration })
    Wait(duration)
    ClearPedTasks(ped); FreezeEntityPosition(ped, false)
    working = false
    TriggerServerEvent('codex_construction:completeTask', taskId)
end)

RegisterNUICallback('close', function(_, cb) SetNuiFocus(false, false); cb({ ok = true }) end)
RegisterNUICallback('create', function(_, cb) TriggerServerEvent('codex_construction:create'); cb({ ok = true }) end)
RegisterNUICallback('join', function(_, cb) TriggerServerEvent('codex_construction:join'); cb({ ok = true }) end)
RegisterNUICallback('leave', function(_, cb) TriggerServerEvent('codex_construction:leave'); cb({ ok = true }) end)
RegisterNUICallback('start', function(_, cb) TriggerServerEvent('codex_construction:start'); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(_, cb) ESX.TriggerServerCallback('codex_construction:getState', function(state) SendNUIMessage({ action = 'state', state = state }); cb(state) end); end)

CreateThread(function()
    while true do
        Wait(1000)
        if active and endsAt > 0 and os.time() >= endsAt then active = false end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if foreman then DeleteEntity(foreman) end
    for _, object in pairs(props) do if DoesEntityExist(object) then DeleteEntity(object) end end
    SetNuiFocus(false, false)
end)
