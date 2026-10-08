--[[
    QC Vehicle Keys - Client Bridge
    Replaces p_bridge with direct qb-core / qb-inventory / ox_lib calls.
    Detects available resources at runtime for maximum compatibility.
]]

Bridge = {}

-- ── Framework Detection ──────────────────────────────────────────────────────
local QBCore = exports['qb-core']:GetCoreObject()

Bridge.Config = {
    Language = 'en',
    Debug = false,
}

-- ── Framework ────────────────────────────────────────────────────────────────
Bridge.Framework = {}

function Bridge.Framework.getPlayerData()
    return QBCore.Functions.GetPlayerData()
end

function Bridge.Framework.getPlayerJob()
    local pd = QBCore.Functions.GetPlayerData()
    return pd and pd.job or { name = 'unemployed', onduty = false, grade = { level = 0 } }
end

function Bridge.Framework.fetchPlayerJob()
    return Bridge.Framework.getPlayerJob()
end

local _useItemCallbacks = {}

RegisterNetEvent('QBCore:Client:UseItem', function(item)
    if item and item.name and _useItemCallbacks[item.name] then
        _useItemCallbacks[item.name](item)
    end
end)

function Bridge.Framework.registerItem(itemName, cb)
    _useItemCallbacks[itemName] = cb
end

function Bridge.Framework.getPlayerIdentifier()
    local pd = QBCore.Functions.GetPlayerData()
    return pd and pd.citizenid or nil
end

-- ── Inventory ────────────────────────────────────────────────────────────────
Bridge.Inventory = {}

--- Get count of an item with optional metadata filter
function Bridge.Inventory.getItemCount(itemName, metadata)
    local pd = QBCore.Functions.GetPlayerData()
    if not pd or not pd.items then return 0 end

    local count = 0
    for _, item in pairs(pd.items) do
        if item and item.name == itemName then
            if metadata then
                local itemInfo = item.info or item.metadata or {}
                local match = true
                for k, v in pairs(metadata) do
                    if itemInfo[k] ~= v then
                        match = false
                        break
                    end
                end
                if match then
                    count = count + (item.amount or item.count or 1)
                end
            else
                count = count + (item.amount or item.count or 1)
            end
        end
    end

    return count
end

--- Get all player items
function Bridge.Inventory.getPlayerItems()
    local pd = QBCore.Functions.GetPlayerData()
    return pd and pd.items or {}
end

--- Add item to player inventory (server-only export wrapper)
function Bridge.Inventory.addItem(itemName, count, metadata)
    -- Client-side: trigger server event
    TriggerServerEvent('qc_vehiclekeys/server/addItem', itemName, count or 1, metadata)
end

--- Remove item from player inventory (server-only export wrapper)
function Bridge.Inventory.removeItem(itemName, count)
    -- Client-side: trigger server event
    TriggerServerEvent('qc_vehiclekeys/server/removeItem', itemName, count or 1)
end

-- ── Notifications ────────────────────────────────────────────────────────────
Bridge.Notify = {}

function Bridge.Notify.showNotify(message, type)
    -- Use ox_lib notification (recommended, always available since ox_lib is a dependency)
    lib.notify({
        title = 'Vehicle Keys',
        description = message,
        type = type or 'inform',
        duration = 4000,
        position = 'top',
    })
end

-- ── Progress Bar ─────────────────────────────────────────────────────────────
Bridge.Progress = {}

function Bridge.Progress.Start(data)
    if lib.progressCircle({
        duration = data.duration,
        label = data.label,
        useWhileDead = data.useWhileDead or false,
        canCancel = data.canCancel or false,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = data.anim,
        prop = data.prop,
    }) then
        return true
    end
    return false
end

-- ── Dispatch ─────────────────────────────────────────────────────────────────
Bridge.Dispatch = {}

function Bridge.Dispatch.SendAlert(data)
    -- ps-dispatch (primary)
    if GetResourceState('ps-dispatch') == 'started' then
        local coords = GetEntityCoords(cache.ped)
        exports['ps-dispatch']:CustomAlert({
            coords = coords,
            message = data.title or 'Vehicle Theft',
            dispatchCode = data.code or '10-90',
            description = data.title or 'Vehicle Theft',
            radius = 0,
            sprite = data.blip and data.blip.sprite or 225,
            color = data.blip and data.blip.color or 3,
            scale = data.blip and data.blip.scale or 1.1,
            length = data.time or 5,
            firstColor = data.blip and data.blip.color or 3,
        })
        return
    end

    -- cd_dispatch fallback
    if GetResourceState('cd_dispatch') == 'started' then
        local coords = GetEntityCoords(cache.ped)
        exports['cd_dispatch']:SendAlert(coords, data.title, data.code, data.title)
        return
    end

    -- qs-dispatch fallback
    if GetResourceState('qs-dispatch') == 'started' then
        local coords = GetEntityCoords(cache.ped)
        exports['qs-dispatch']:CreateDispatchCall({
            job = { 'police' },
            coords = coords,
            title = data.title,
            message = data.title,
            flash = false,
            uniqueId = tostring(coords),
            blip = {
                sprite = data.blip and data.blip.sprite or 225,
                color = data.blip and data.blip.color or 3,
                scale = data.blip and data.blip.scale or 1.1,
            },
        })
        return
    end
end

-- ── Target ───────────────────────────────────────────────────────────────────
Bridge.Target = {}

function Bridge.Target.addVehicle(options)
    -- ox_target (preferred)
    if GetResourceState('ox_target') == 'started' then
        local oxOptions = {}
        for _, opt in ipairs(options) do
            table.insert(oxOptions, {
                name = opt.name,
                icon = opt.icon,
                label = opt.label,
                distance = opt.distance or 2.0,
                groups = opt.groups,
                canInteract = opt.canInteract,
                onSelect = opt.onSelect,
            })
        end
        exports.ox_target:addGlobalVehicle(oxOptions)
        return
    end

    -- qb-target
    if GetResourceState('qb-target') == 'started' then
        for _, opt in ipairs(options) do
            exports['qb-target']:AddGlobalVehicle({
                options = {
                    {
                        type = 'client',
                        name = opt.name,
                        icon = opt.icon,
                        label = opt.label,
                        job = opt.groups,
                        canInteract = opt.canInteract,
                        action = function(entity)
                            opt.onSelect(entity)
                        end,
                    },
                },
                distance = opt.distance or 2.0,
            })
        end
        return
    end
end

return Bridge