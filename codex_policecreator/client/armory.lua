--[[
    client/armory.lua - armory presentation and the armory NUI.
]]

local RESOURCE = GetCurrentResourceName()
local props = {}

local function clearProps()
    for _, entity in pairs(props) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    props = {}
end

--- Spawn the display case next to the armory node when you walk up to it.
local function updateDisplay()
    if not Config.Armory.Display3D then return end
    if not State.sync then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local model = joaat(Config.Armory.DisplayModel)
    local wanted = {}

    for _, dept in ipairs(State.sync.departments) do
        if dept.id == State.deptId then
            for _, node in ipairs(dept.nodes) do
                if node.type == 'armory' then
                    local distance = #(coords - vector3(node.x, node.y, node.z))
                    if distance <= 15.0 then
                        wanted[#wanted + 1] = node
                    end
                end
            end
        end
    end

    if #wanted == 0 then
        clearProps()
        return
    end

    RequestModel(model)
    local waited = 0
    while not HasModelLoaded(model) and waited < 100 do
        Wait(10)
        waited = waited + 1
    end

    if not HasModelLoaded(model) then return end

    if #props < #wanted then
        for index, node in ipairs(wanted) do
            if not props[index] then
                local offset = Config.Armory.DisplayOffset or vector3(0.0, 0.9, 0.0)
                local entity = CreateObject(model,
                    node.x + offset.x, node.y + offset.y, node.z + offset.z - 1.0, false, false, false)

                if entity and entity ~= 0 then
                    SetEntityHeading(entity, node.heading or 0.0)
                    PlaceObjectOnGroundProperly(entity)
                    FreezeEntityPosition(entity, true)
                    SetEntityAsMissionEntity(entity, true, true)
                    props[index] = entity
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        local ok, err = pcall(updateDisplay)
        if not ok and Config.Debug then
            print(('[%s] armory display error: %s'):format(RESOURCE, err))
        end
    end
end)

RegisterNetEvent(RESOURCE .. ':client:openArmory', function(payload)
    if not payload then return end
    State.OpenMenu('armory', payload)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then clearProps() end
end)
