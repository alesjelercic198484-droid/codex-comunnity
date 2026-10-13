--[[
    client/main.lua - state, node markers/blips, prompts and the NUI bridge.
]]

local RESOURCE = GetCurrentResourceName()

State = {
    ready = false,
    sync = nil,          -- payload from the server
    deptId = nil,
    member = nil,
    rank = nil,
    canCreate = false,
    departments = {},    -- id -> dept
    menuOpen = false,
    menuMode = 'menu',   -- 'menu' | 'creator'
    activeNode = nil,
    blips = {},
    busy = false
}

local function debugPrint(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':client:notify', function(message, kind)
    if not message then return end

    if GetResourceState('ox_lib') == 'started' then
        exports.ox_lib:notify({ title = 'Department', description = tostring(message), type = kind or 'inform' })
        return
    end

    SetNotificationTextEntry('STRING')
    AddTextComponentString(tostring(message))
    DrawNotification(false, false)
end)

-- ---------------------------------------------------------------------------
-- BLIPS
-- ---------------------------------------------------------------------------
local function clearBlips()
    for _, blip in pairs(State.blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    State.blips = {}
end

local function createBlip(coords, sprite, color, scale, label, radius)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 1)
    SetBlipColour(blip, color or 0)
    SetBlipScale(blip, scale or 0.8)
    SetBlipAsShortRange(blip, radius == nil)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Department')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function rebuildBlips()
    clearBlips()
    if not State.sync then return end

    for _, dept in ipairs(State.sync.departments) do
        local blipConfig = Config.NodeBlips

        for _, node in ipairs(dept.nodes) do
            if node.blip then
                local config = blipConfig[node.type] or { sprite = 1, color = 0, scale = 0.8 }
                local label = ('%s - %s'):format(dept.label, node.label)

                State.blips[#State.blips + 1] = createBlip(
                    { x = node.x, y = node.y, z = node.z },
                    config.sprite, config.color, config.scale, label
                )
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- SYNC
-- ---------------------------------------------------------------------------
RegisterNetEvent(RESOURCE .. ':client:sync', function(payload)
    State.sync = payload
    State.canCreate = payload.canCreate == true
    State.deptId = payload.deptId
    State.member = payload.member
    State.rank = payload.rank

    State.departments = {}
    for _, dept in ipairs(payload.departments or {}) do
        State.departments[dept.id] = dept
    end

    rebuildBlips()
    State.ready = true
    debugPrint('synced')
end)

-- ---------------------------------------------------------------------------
-- NODE MARKERS + PROMPT
-- ---------------------------------------------------------------------------
local function nearestNode()
    if not State.ready or not State.sync then return nil end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local best, bestDistance = nil, math.huge

    for _, dept in ipairs(State.sync.departments) do
        local isMember = dept.id == State.deptId

        for _, node in ipairs(dept.nodes) do
            local distance = #(coords - vector3(node.x, node.y, node.z))
            if distance < bestDistance and (isMember or State.canCreate) then
                bestDistance = distance
                best = { dept = dept, node = node, distance = distance }
            end
        end
    end

    if best and bestDistance <= 20.0 then
        return best
    end
    return nil
end

local function drawText3D(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z + 1.0, 0)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(0.0, 0.35)
    SetTextColour(255, 255, 255, 215)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        local wait = 1000
        local target = nearestNode()
        State.activeNode = target

        if target then
            wait = 0
            local node = target.node
            local marker = Config.NodeTypes[node.type] and Config.NodeTypes[node.type].marker
                or { type = 1, color = { 255, 255, 255 } }

            DrawMarker(marker.type, node.x, node.y, node.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.8, 0.8, 0.8, marker.color[1], marker.color[2], marker.color[3], 120, false, true, 2, false, nil, nil, false)

            if target.distance <= 8.0 then
                drawText3D({ x = node.x, y = node.y, z = node.z }, ('~b~%s~s~\n%s'):format(target.dept.label, node.label))
            end

            if target.distance <= (Config.NodeRange or 2.0) then
                if target.dept.id ~= State.deptId then
                    drawText3D({ x = node.x, y = node.y, z = node.z - 0.4 }, '~r~Not your department')
                elseif IsControlJustReleased(0, Config.Keys.Interact or 38) then
                    TriggerServerEvent(RESOURCE .. ':server:useNode', target.dept.id, node.id, node.type)
                    wait = 500
                end
            end
        end

        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- NUI
-- ---------------------------------------------------------------------------
local function sendNui(action, data)
    SendNUIMessage({ action = action, data = data })
end

function State.OpenMenu(mode, payload)
    State.menuOpen = true
    State.menuMode = mode or 'menu'
    SetNuiFocus(true, true)
    sendNui('open', { mode = State.menuMode, payload = payload })
end

function State.CloseMenu()
    State.menuOpen = false
    SetNuiFocus(false, false)
    sendNui('close', {})
end

RegisterNetEvent(RESOURCE .. ':client:menuData', function(payload)
    if not payload then return end

    if payload.error then
        TriggerEvent(RESOURCE .. ':client:notify', tostring(payload.error), 'error')
        return
    end

    State.OpenMenu('menu', payload)
end)

RegisterNetEvent(RESOURCE .. ':client:openCreator', function(payload)
    State.OpenMenu('creator', payload)
end)

RegisterNetEvent(RESOURCE .. ':client:menuUpdate', function(payload)
    if State.menuOpen then
        sendNui('update', payload)
    end
end)

--- Boss menu hotkey (optional, Config.Keys.BossMenu).
if (Config.Keys.BossMenu or 0) > 0 then
    CreateThread(function()
        while true do
            Wait(0)
            if IsControlJustReleased(0, Config.Keys.BossMenu) and not State.menuOpen then
                TriggerServerEvent(RESOURCE .. ':server:requestMenuData')
                Wait(500)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- NUI CALLBACKS
-- ---------------------------------------------------------------------------
local actions = {}

function actions.close()
    State.CloseMenu()
end

function actions.refresh()
    TriggerServerEvent(RESOURCE .. ':server:requestMenuData')
end

function actions.sync()
    TriggerServerEvent(RESOURCE .. ':server:requestSync')
end

function actions.toggleDuty()
    TriggerServerEvent(RESOURCE .. ':server:toggleDuty')
end

function actions.deposit(data)   TriggerServerEvent(RESOURCE .. ':server:deposit', tonumber(data.amount)) end
function actions.withdraw(data)  TriggerServerEvent(RESOURCE .. ':server:withdraw', tonumber(data.amount)) end
function actions.bonus(data)     TriggerServerEvent(RESOURCE .. ':server:bonus', data.citizenid, tonumber(data.amount)) end

function actions.hire(data)
    TriggerServerEvent(RESOURCE .. ':server:hire', data.citizenid, data.firstName, data.lastName, tonumber(data.rankId))
end
function actions.hireNearby(data) TriggerServerEvent(RESOURCE .. ':server:hireNearby', tonumber(data.rankId)) end
function actions.fire(data)      TriggerServerEvent(RESOURCE .. ':server:fire', data.citizenid) end
function actions.setRank(data)   TriggerServerEvent(RESOURCE .. ':server:setRank', data.citizenid, tonumber(data.rankId)) end
function actions.setDivision(data) TriggerServerEvent(RESOURCE .. ':server:setDivision', data.citizenid, tonumber(data.divisionId)) end
function actions.setSalary(data) TriggerServerEvent(RESOURCE .. ':server:setSalary', data.citizenid, tonumber(data.salary)) end

function actions.createRank(data)   TriggerServerEvent(RESOURCE .. ':server:createRank', data) end
function actions.updateRank(data)   TriggerServerEvent(RESOURCE .. ':server:updateRank', tonumber(data.rankId), data) end
function actions.deleteRank(data)   TriggerServerEvent(RESOURCE .. ':server:deleteRank', tonumber(data.rankId)) end
function actions.createDivision(data) TriggerServerEvent(RESOURCE .. ':server:createDivision', data.name, data.label) end
function actions.deleteDivision(data) TriggerServerEvent(RESOURCE .. ':server:deleteDivision', tonumber(data.divisionId)) end

function actions.apply(data) TriggerServerEvent(RESOURCE .. ':server:apply', tonumber(data.deptId), data.message) end
function actions.resolveApplication(data)
    TriggerServerEvent(RESOURCE .. ':server:resolveApplication', tonumber(data.applicationId), data.decision)
end

function actions.armoryTake(data)  TriggerServerEvent(RESOURCE .. ':server:armoryTake', tonumber(data.index)) end
function actions.armoryStore(data) TriggerServerEvent(RESOURCE .. ':server:armoryStore', tonumber(data.index)) end

function actions.garageAdd(data)    TriggerServerEvent(RESOURCE .. ':server:garageAdd', data) end
function actions.garageRemove(data) TriggerServerEvent(RESOURCE .. ':server:garageRemove', tonumber(data.vehicleId)) end
function actions.garageImpound(data) TriggerServerEvent(RESOURCE .. ':server:garageImpound', tonumber(data.vehicleId), data.impounded and true or false) end
function actions.garageSpawn(data)
    local coords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent(RESOURCE .. ':server:garageSpawn', tonumber(data.vehicleId), tonumber(data.nodeId),
        { x = coords.x, y = coords.y, z = coords.z })
end

function actions.evidenceCreate(data) TriggerServerEvent(RESOURCE .. ':server:evidenceCreate', data) end
function actions.evidenceTake(data)   TriggerServerEvent(RESOURCE .. ':server:evidenceTake', tonumber(data.evidenceId)) end
function actions.evidenceDelete(data) TriggerServerEvent(RESOURCE .. ':server:evidenceDelete', tonumber(data.evidenceId)) end

function actions.createCall(data)
    local coords = GetEntityCoords(PlayerPedId())
    data.x, data.y, data.z = coords.x, coords.y, coords.z
    TriggerServerEvent(RESOURCE .. ':server:createCall', data)
end
function actions.acceptCall(data)  TriggerServerEvent(RESOURCE .. ':server:acceptCall', tonumber(data.callId)) end
function actions.releaseCall(data) TriggerServerEvent(RESOURCE .. ':server:releaseCall', tonumber(data.callId)) end
function actions.closeCall(data)   TriggerServerEvent(RESOURCE .. ':server:closeCall', tonumber(data.callId)) end

function actions.boloCreate(data) TriggerServerEvent(RESOURCE .. ':server:boloCreate', data) end
function actions.boloToggle(data) TriggerServerEvent(RESOURCE .. ':server:boloToggle', tonumber(data.boloId), data.active and true or false) end
function actions.boloDelete(data) TriggerServerEvent(RESOURCE .. ':server:boloDelete', tonumber(data.boloId)) end

function actions.cameraAdd(data)    TriggerServerEvent(RESOURCE .. ':server:cameraAdd', data) end
function actions.cameraRemove(data) TriggerServerEvent(RESOURCE .. ':server:cameraRemove', tonumber(data.cameraId)) end
function actions.viewCamera(data)
    State.CloseMenu()
    TriggerServerEvent(RESOURCE .. ':server:viewCamera', tonumber(data.cameraId))
end

function actions.trackerRemove(data)  TriggerServerEvent(RESOURCE .. ':server:trackerRemove', tonumber(data.trackerId)) end
function actions.trackerRecover(data) TriggerServerEvent(RESOURCE .. ':server:trackerRecover', tonumber(data.trackerId)) end

function actions.creatorCreate(data)     TriggerServerEvent(RESOURCE .. ':server:creatorCreate', data) end
function actions.creatorUpdate(data)     TriggerServerEvent(RESOURCE .. ':server:creatorUpdate', tonumber(data.deptId), data) end
function actions.creatorDelete(data)     TriggerServerEvent(RESOURCE .. ':server:creatorDelete', tonumber(data.deptId)) end
function actions.creatorAddNode(data)    TriggerServerEvent(RESOURCE .. ':server:creatorAddNode', tonumber(data.deptId), data) end
function actions.creatorUpdateNode(data) TriggerServerEvent(RESOURCE .. ':server:creatorUpdateNode', tonumber(data.nodeId), data) end
function actions.creatorDeleteNode(data) TriggerServerEvent(RESOURCE .. ':server:creatorDeleteNode', tonumber(data.nodeId)) end
function actions.creatorWipe()           TriggerServerEvent(RESOURCE .. ':server:creatorWipe') end

function actions.playAnim(data)
    Anims.Play(data.index)
end

function actions.k9Command(data)
    TriggerEvent(RESOURCE .. ':client:k9Command', tostring(data.name or ''))
end

--- Used by the creator to read where the player is standing.
function actions.currentPosition()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    return { x = coords.x, y = coords.y, z = coords.z, heading = heading }
end

RegisterNUICallback('action', function(body, cb)
    local handler = actions[body and body.name]
    if not handler then
        cb({ ok = false, error = 'unknown_action' })
        return
    end

    local result = handler(body.data or {})
    cb({ ok = true, result = result })
end)

RegisterNUICallback('close', function(_, cb)
    State.CloseMenu()
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    clearBlips()
    if State.menuOpen then SetNuiFocus(false, false) end
end)
