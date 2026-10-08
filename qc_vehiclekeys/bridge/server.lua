--[[
    QC Vehicle Keys - Server Bridge
    Replaces p_bridge with direct qb-core / qb-inventory / ox_lib calls.
]]

Bridge = {}

local QBCore = exports['qb-core']:GetCoreObject()

Bridge.Config = {
    Language = 'en',
    Debug = false,
}

-- ── Framework ────────────────────────────────────────────────────────────────
Bridge.Framework = {}

function Bridge.Framework.getPlayerJob(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return { name = 'unemployed' } end
    return Player.PlayerData.job
end

local _useItemCallbacks = {}

function Bridge.Framework.registerItem(itemName, cb)
    _useItemCallbacks[itemName] = cb
    QBCore.Functions.CreateUseableItem(itemName, function(source, item)
        if _useItemCallbacks[item.name] then
            _useItemCallbacks[item.name](source, item)
        end
    end)
end

function Bridge.Framework.getPlayerIdentifier(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    return Player and Player.PlayerData.citizenid or nil
end

-- ── Inventory ────────────────────────────────────────────────────────────────
Bridge.Inventory = {}

--- Get item count for a player with optional metadata filter
function Bridge.Inventory.getItemCount(playerId, itemName, metadata)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return 0 end

    -- Try ox_inventory first
    if GetResourceState('ox_inventory') == 'started' then
        local count = exports.ox_inventory:Search(playerId, 'count', itemName, metadata)
        return count or 0
    end

    -- QB-based inventory (qb-inventory, ps-inventory, etc.)
    local items = Player.PlayerData.items
    if not items then return 0 end

    local count = 0
    for _, item in pairs(items) do
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

--- Get all items for a player
function Bridge.Inventory.getPlayerItems(playerId)
    -- ox_inventory
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:GetInventoryItems(playerId) or {}
    end

    local Player = QBCore.Functions.GetPlayer(playerId)
    return Player and Player.PlayerData.items or {}
end

--- Add item to player inventory
function Bridge.Inventory.addItem(playerId, itemName, count, metadata)
    -- ox_inventory
    if GetResourceState('ox_inventory') == 'started' then
        local success = exports.ox_inventory:AddItem(playerId, itemName, count or 1, metadata)
        return success
    end

    -- QB-based inventory
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end
    return Player.Functions.AddItem(itemName, count or 1, false, metadata)
end

--- Remove item from player inventory
function Bridge.Inventory.removeItem(playerId, itemName, count, metadata)
    -- ox_inventory
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:RemoveItem(playerId, itemName, count or 1, nil, metadata)
    end

    -- QB-based inventory
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end
    return Player.Functions.RemoveItem(itemName, count or 1)
end

-- ── Notifications (Server-side, forwarded to client) ─────────────────────────
Bridge.Notify = {}

function Bridge.Notify.showNotify(playerId, message, type)
    TriggerClientEvent('qc_vehiclekeys/client/notify', playerId, message, type)
end

return Bridge