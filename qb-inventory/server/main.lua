--[============================================================================[
    CodeX Roleplay Inventory - server

    A drop-in replacement for qb-inventory 2.x. It reproduces the complete
    public surface of the original resource:

        exports['qb-inventory']  -> 30 exports (AddItem, RemoveItem, HasItem ...)
        qb-inventory:server:*    -> events and callbacks
        qb-inventory:client:*    -> events consumed by client/main.lua
        inventory:server:*       -> legacy aliases used by older scripts
        inventory:client:*       -> legacy aliases used by older scripts

    The item data itself stays exactly where qb-core keeps it: in
    `PlayerData.items`, keyed by slot number. That is what makes every other
    qb-core script (qb-shops, qb-ambulancejob, qb-truckerjob, ...) work without
    touching a single line of their code.

    Everything is written in English.
]============================================================================]

local Inventories = {}       -- [identifier] = { label, maxweight, slots, items, isOpen }
local Drops = {}             -- [dropId]     = { name, label, items, coords, maxweight, slots, isOpen, createdTime }
local RegisteredShops = {}   -- [name]       = { name, label, coords, slots, items, type }
local OpenInventories = {}   -- [src]        = identifier currently open as the second panel
local Viewers = {}           -- [targetId]   = source that is searching / robbing him
local dropCounter = 0

local SECOND = 1000
local MINUTE = 60 * SECOND

-- ===========================================================================
-- Small helpers
-- ===========================================================================
local function TableSize(t)
    local count = 0
    for _ in pairs(t or {}) do count = count + 1 end
    return count
end

local function IsArray(t)
    if type(t) ~= 'table' then return false end

    local count = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        count = count + 1
    end
    return count > 0
end

local function SanitizeSlot(slot)
    local value = tonumber(slot)
    if not value then return nil end
    value = math.floor(value)
    if value < 1 then return nil end
    return value
end

local function SanitizeAmount(amount)
    local value = tonumber(amount)
    if not value then return 1 end
    value = math.floor(value)
    if value < 1 then return 1 end
    return value
end

--- Splits `stash-mybox` into ('stash', 'mybox'). Plates may contain spaces.
local function ParseIdentifier(identifier)
    if type(identifier) ~= 'string' then return nil, nil end

    local kind, value = identifier:match('^(%a+)%-?(.*)$')
    return kind, value
end

local function RarityOf(name)
    if type(name) ~= 'string' then return 'common' end

    local key = name:lower()

    if Config.Rarity and type(Config.Rarity.Items) == 'table' then
        local forced = Config.Rarity.Items[key]
        if type(forced) == 'string' then return forced end
    end

    local shared = Core.SharedItem(key)
    if shared and type(shared.rarity) == 'string' then
        return shared.rarity
    end

    if Config.Rarity and type(Config.Rarity.Default) == 'string' then
        return Config.Rarity.Default
    end

    return 'common'
end

--- Builds an item table with every field the UI (and qb-core) expects.
local function BuildItem(name, amount, slot, info)
    local itemInfo = Core.SharedItem(name)
    if not itemInfo then return nil end

    amount = SanitizeAmount(amount)
    slot = SanitizeSlot(slot)

    local item = {
        name = itemInfo.name or name:lower(),
        amount = amount,
        info = type(info) == 'table' and info or {},
        label = itemInfo.label or itemInfo.name or name,
        description = itemInfo.description or '',
        weight = tonumber(itemInfo.weight) or 0,
        type = itemInfo.type or 'item',
        unique = itemInfo.unique == true,
        useable = itemInfo.useable == true,
        image = itemInfo.image or (itemInfo.name or name) .. '.png',
        shouldClose = itemInfo.shouldClose == true,
        slot = slot,
        combinable = itemInfo.combinable,
    }

    if item.type == 'weapon' then
        if not item.info.serie then
            item.info.serie = tostring(math.random(10000, 99999) ..
                                       math.random(10000, 99999))
        end
        if item.info.quality == nil then
            item.info.quality = 100
        end
    end

    item.rarity = RarityOf(item.name)

    return item
end

--- Normalises whatever is stored in PlayerData.items into a slot keyed table.
local function NormalizeItems(rawItems)
    local items = {}

    for key, value in pairs(rawItems or {}) do
        local index = SanitizeSlot(key)

        if index and type(value) == 'table' and type(value.name) == 'string' then
            local rebuilt = BuildItem(value.name, value.amount, index, value.info)

            if rebuilt then
                items[index] = rebuilt
            end
        end
    end

    return items
end

-- ===========================================================================
-- Target resolution
-- ===========================================================================
local function GetPlayerItems(source)
    local player = Core.GetPlayer(source)
    if not player or not player.PlayerData then return nil end
    return player.PlayerData.items
end

--- Resolves an identifier to (items, maxweight, slots, player).
local function ResolveTarget(identifier, requireCapacity)
    if type(identifier) == 'number' then
        local player = Core.GetPlayer(identifier)
        if not player then return nil end
        return player.PlayerData.items, Config.MaxWeight, Config.MaxSlots, player
    end

    if type(identifier) ~= 'string' then return nil end

    local kind, value = ParseIdentifier(identifier)

    if kind == 'otherplayer' then
        local target = Core.GetPlayer(tonumber(value))
        if not target then return nil end
        return target.PlayerData.items, Config.MaxWeight, Config.MaxSlots, target
    end

    if kind == 'shop' then
        local shop = RegisteredShops[value]
        if not shop then return nil end
        return shop.items, 1000000000, shop.slots or TableSize(shop.items), nil
    end

    local inventory = Inventories[identifier] or Drops[identifier]
    if not inventory then return nil end

    if requireCapacity and (not inventory.maxweight or not inventory.slots) then
        return nil
    end

    return inventory.items, inventory.maxweight, inventory.slots, nil
end

local function GetInventory(identifier)
    return Inventories[identifier]
end

local function EnsureInventory(identifier, data)
    local inventory = Inventories[identifier]

    if not inventory then
        inventory = {
            label = (data and data.label) or identifier,
            maxweight = (data and data.maxweight) or Config.Stashes.DefaultMaxWeight or 1000000,
            slots = (data and data.slots) or Config.Stashes.DefaultSlots or 50,
            items = {},
            isOpen = false,
        }
        Inventories[identifier] = inventory

        -- Lazy load from SQL the first time the stash is touched.
        if Config.Stashes.Persist then
            local row = Core.SqlQuery(
                'SELECT items, label, slots, maxweight FROM `' .. Config.Stashes.Table ..
                '` WHERE identifier = ? LIMIT 1', { identifier })

            if row then
                if type(row.items) == 'string' and row.items ~= '' then
                    local ok, decoded = pcall(json.decode, row.items)
                    if ok and type(decoded) == 'table' then
                        inventory.items = NormalizeItems(decoded)
                    end
                end
                inventory.label = row.label or inventory.label
                inventory.slots = tonumber(row.slots) or inventory.slots
                inventory.maxweight = tonumber(row.maxweight) or inventory.maxweight
            end
        end
    end

    if type(data) == 'table' then
        inventory.label = data.label or inventory.label
        inventory.maxweight = data.maxweight or inventory.maxweight
        inventory.slots = data.slots or inventory.slots
    end

    return inventory
end

local function SaveInventoryItems(identifier)
    if not Config.Stashes.Persist then return false end

    local inventory = Inventories[identifier]
    if not inventory then return false end

    return Core.SqlExecute(
        'INSERT INTO `' .. Config.Stashes.Table ..
        '` (identifier, label, slots, maxweight, items) VALUES (?, ?, ?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE label = VALUES(label), slots = VALUES(slots), ' ..
        'maxweight = VALUES(maxweight), items = VALUES(items)',
        { identifier, inventory.label, inventory.slots, inventory.maxweight,
          json.encode(inventory.items) })
end

-- ===========================================================================
-- Item helpers
-- ===========================================================================
local function GetFirstFreeSlot(items, maxSlots)
    for i = 1, (maxSlots or Config.MaxSlots) do
        if items[i] == nil then return i end
    end
    return nil
end

local function itemWeight(item)
    if type(item) ~= 'table' then return 0 end

    local each = tonumber(item.weight)

    if not each then
        local shared = Core.SharedItem(item.name)
        each = tonumber(shared and shared.weight) or 0
    end

    return each * (tonumber(item.amount) or 1)
end

function GetTotalWeight(items)
    if not items then return 0 end

    local weight = 0

    for _, item in pairs(items) do
        if type(item) == 'table' then
            weight = weight + itemWeight(item)
        end
    end

    return weight
end

local function GetItemAt(identifier, slot)
    local items = ResolveTarget(identifier)
    if not items then return nil end

    slot = SanitizeSlot(slot)
    if not slot then return nil end

    return items[slot]
end

--- Pushes the current state of a player inventory + optional second panel.
local function FormatForClient(identifier, source)
    local items, maxweight, slots = ResolveTarget(identifier)

    if not items then return nil end

    local dense = {}
    for i = 1, (slots or Config.MaxSlots) do
        dense[i] = items[i] or false
    end

    local kind = ParseIdentifier(identifier)

    return {
        name = tostring(identifier),
        label = tostring(identifier),
        type = kind or 'player',
        maxweight = maxweight or Config.MaxWeight,
        slots = slots or Config.MaxSlots,
        inventory = dense,
    }
end

--- Sends the current state of one player's inventory (plus his second panel).
local function RefreshClient(source)
    local player = Core.GetPlayer(source)
    if not player then return end

    local other = nil
    local identifier = OpenInventories[source]

    if identifier then
        other = FormatForClient(identifier, source)
    end

    TriggerClientEvent('qb-inventory:client:refreshInventory', source,
        FormatForClient(source, source), other)
end

--- Refreshes every player that currently has `identifier` open.
--- `source` may be a player id (his own inventory changed) or an inventory id.
local function RefreshHolder(source)
    if type(source) == 'number' then
        RefreshClient(source)

        -- He may also be the "other player" panel of somebody searching him.
        for viewer, identifier in pairs(OpenInventories) do
            if identifier == ('otherplayer-' .. source) then
                RefreshClient(viewer)
            end
        end

        return
    end

    for viewer, identifier in pairs(OpenInventories) do
        if identifier == source then
            RefreshClient(viewer)
        end
    end
end

--- Notifies qb-weapons (and legacy scripts) that a weapon was removed.
local function CheckWeapon(source, item)
    if type(item) ~= 'table' or item.type ~= 'weapon' then return end

    TriggerClientEvent('qb-inventory:client:CheckWeapon', source, item.name)
    TriggerClientEvent('inventory:client:CheckWeapon', source, item.name)
end

-- ===========================================================================
-- Exported functions
-- ===========================================================================
function LoadInventory(source, citizenid)
    if citizenid then
        local player = Core.GetPlayer(citizenid) or Core.GetPlayer(source)
        if player then return NormalizeItems(player.PlayerData.items) end
    end

    local items = GetPlayerItems(source)
    if items then return NormalizeItems(items) end

    return {}
end

function SaveInventory(source)
    -- qb-core persists PlayerData.items itself on logout / save. This export
    -- only exists for compatibility with scripts that call it explicitly.
    local player = Core.GetPlayer(source)
    if not player then return false end

    if player.Functions and player.Functions.Save then
        pcall(function() player.Functions.Save() end)
    end

    RefreshClient(source)
    return true
end

function SetInventory(identifier, items, reason)
    local target, maxweight, slots, player = ResolveTarget(identifier, true)
    if not target then return false end

    local cleaned = NormalizeItems(items)

    for slot, item in pairs(cleaned) do
        if slot > (slots or Config.MaxSlots) then
            cleaned[slot] = nil
        end
    end

    if type(identifier) == 'number' then
        if player then
            player.PlayerData.items = cleaned
            Core.SetPlayerData(identifier, 'items', cleaned)
        end
    else
        local inventory = EnsureInventory(identifier)
        inventory.items = cleaned
        SaveInventoryItems(identifier)
    end

    RefreshHolder(identifier)
    return true
end

function SetItemData(source, itemName, key, val, slot)
    if not itemName or not key then return false end

    local player = Core.GetPlayer(source)
    if not player then return false end

    local items = player.PlayerData.items

    for index, item in pairs(items) do
        if type(item) == 'table' and item.name == itemName then
            if slot == nil or index == slot then
                item.info = type(item.info) == 'table' and item.info or {}
                item.info[key] = val
                items[index] = item
            end
        end
    end

    Core.SetPlayerData(source, 'items', items)
    RefreshClient(source)

    return true
end

--- Runs the callback registered with `QBCore.Functions.CreateUseableItem`.
---
--- Two call orders exist in the wild and BOTH have to work:
---   * qb-inventory style:  UseItem(itemName, source, item, ...)
---   * qb-core style:       UseItem(source, item)   <- QBCore.Functions.UseItem
---                          delegates to this export
---
--- Note: we must NOT call QBCore.Functions.UseItem from here - that function
--- calls this same export again, which would recurse forever.
function UseItem(itemName, source, item, ...)
    if itemName == nil or source == nil then return false end

    -- Normalise the qb-core ordering (source first, item second).
    if type(itemName) == 'number' then
        local realSource = itemName
        local realItem = (type(source) == 'table') and source or nil

        itemName = (realItem and realItem.name) or itemName
        source = realSource
        item = realItem
    end

    if type(itemName) ~= 'string' or type(source) ~= 'number' then return false end

    local QBCore = Core.Object()
    if not QBCore or not QBCore.Functions then return false end

    if not QBCore.Functions.CanUseItem then return false end

    local itemData = QBCore.Functions.CanUseItem(itemName)

    if type(itemData) ~= 'table' or type(itemData.func) ~= 'function' then
        return false
    end

    if type(item) ~= 'table' then
        item = GetItemByName(source, itemName) or
               { name = itemName, amount = 1, info = {} }
    end

    local ok, err = pcall(itemData.func, source, item, ...)

    if not ok then
        print(('^1[qb-inventory]^7 UseItem failed for "%s": %s'):format(itemName, tostring(err)))
        return false
    end

    RefreshHolder(source)
    return true
end

function GetSlotsByItem(items, itemName)
    local slots = {}
    if type(items) ~= 'table' or not itemName then return slots end

    local index = 1

    for slot, item in pairs(items) do
        if type(item) == 'table' and item.name == itemName then
            slots[index] = slot
            index = index + 1
        end
    end

    return slots
end

function GetFirstSlotByItem(items, itemName)
    if type(items) ~= 'table' or not itemName then return nil end

    local best = nil

    for slot, item in pairs(items) do
        if type(item) == 'table' and item.name == itemName then
            local numeric = SanitizeSlot(slot)
            if numeric and (best == nil or numeric < best) then
                best = numeric
            end
        end
    end

    return best
end

function GetItemBySlot(source, slot)
    return GetItemAt(source, slot)
end

function GetItemByName(source, item)
    if not item then return nil end

    local items = ResolveTarget(source)
    if not items then return nil end

    for _, value in pairs(items) do
        if type(value) == 'table' and value.name == item then
            return value
        end
    end

    return nil
end

function GetItemsByName(source, item)
    local found = {}

    local items = ResolveTarget(source)
    if not items then return found end

    for _, value in pairs(items) do
        if type(value) == 'table' and value.name == item then
            found[#found + 1] = value
        end
    end

    return found
end

function GetSlots(identifier)
    local items, _, slots = ResolveTarget(identifier, true)
    if not items then return 0, 0 end

    local used = 0
    for slot in pairs(items) do
        if SanitizeSlot(slot) then used = used + 1 end
    end

    return used, slots or Config.MaxSlots
end

function GetItemCount(source, items)
    local target = ResolveTarget(source)
    if not target then return 0 end

    if type(items) ~= 'table' then
        local total = 0

        for _, item in pairs(target) do
            if type(item) == 'table' and item.name == items then
                total = total + (tonumber(item.amount) or 1)
            end
        end

        return total
    end

    local total = 0

    if IsArray(items) then
        for _, name in ipairs(items) do
            for _, item in pairs(target) do
                if type(item) == 'table' and item.name == name then
                    total = total + (tonumber(item.amount) or 1)
                end
            end
        end
    else
        for name in pairs(items) do
            for _, item in pairs(target) do
                if type(item) == 'table' and item.name == name then
                    total = total + (tonumber(item.amount) or 1)
                end
            end
        end
    end

    return total
end

function CanAddItem(identifier, item, amount)
    local itemInfo = Core.SharedItem(item)
    if not itemInfo then return false end

    local items, maxweight, slots = ResolveTarget(identifier, true)
    if not items then return false end

    amount = SanitizeAmount(amount)

    if GetTotalWeight(items) + ((tonumber(itemInfo.weight) or 0) * amount) > (maxweight or Config.MaxWeight) then
        return false, 'weight'
    end

    local used, total = GetSlots(identifier)

    if used >= (total or Config.MaxSlots) then
        -- Still fine when the item can stack into an existing slot. Unique
        -- items (weapons, ...) never stack, so they need a genuinely free slot.
        local canStack = (itemInfo.unique ~= true) and
                         (GetFirstSlotByItem(items, itemInfo.name) ~= nil)

        if not canStack then
            return false, 'slots'
        end
    end

    return true
end

function GetFreeWeight(source)
    local items = ResolveTarget(source)
    if not items then return 0 end

    return math.max(0, Config.MaxWeight - GetTotalWeight(items))
end

function ClearInventory(source, filterItems)
    local target, _, _, player = ResolveTarget(source)
    if not target then return false end

    if filterItems == nil then
        if player then
            player.PlayerData.items = {}
            Core.SetPlayerData(source, 'items', {})
        end
    else
        if type(filterItems) == 'string' then
            filterItems = { filterItems }
        end

        for slot, item in pairs(target) do
            if type(item) == 'table' then
                for _, name in pairs(filterItems) do
                    if item.name == name then
                        target[slot] = nil
                        break
                    end
                end
            end
        end

        if player then
            Core.SetPlayerData(source, 'items', target)
        end
    end

    RefreshClient(source)
    return true
end

function HasItem(source, items, amount)
    local player = Core.GetPlayer(source)
    if not player or not player.PlayerData then return false end

    local inventory = player.PlayerData.items

    if type(items) == 'table' then
        local isArray = IsArray(items)
        local total = isArray and #items or TableSize(items)
        local count = 0

        for _, itemData in pairs(inventory) do
            if type(itemData) == 'table' then
                for key, value in pairs(items) do
                    local name = isArray and value or key

                    if itemData.name == name then
                        if (amount and (tonumber(itemData.amount) or 0) >= amount) or
                           (not isArray and (tonumber(itemData.amount) or 0) >= value) or
                           (not amount and isArray) then
                            count = count + 1
                            if count >= total then return true end
                        end
                    end
                end
            end
        end

        return false
    end

    for _, itemData in pairs(inventory) do
        if type(itemData) == 'table' and itemData.name == items then
            if not amount or (tonumber(itemData.amount) or 0) >= amount then
                return true
            end
        end
    end

    return false
end

function CloseInventory(source, identifier)
    OpenInventories[source] = nil

    if identifier and Inventories[identifier] then
        Inventories[identifier].isOpen = false
        SaveInventoryItems(identifier)
    end

    if Drops[identifier] then
        Drops[identifier].isOpen = false
    end

    local kind, value = ParseIdentifier(identifier)

    if kind == 'otherplayer' and value then
        local target = tonumber(value)
        Viewers[target] = nil
    end

    TriggerClientEvent('qb-inventory:client:closeInv', source)
end

function OpenInventoryById(source, targetId)
    local player = Core.GetPlayer(source)
    local target = Core.GetPlayer(tonumber(targetId))

    if not player or not target then return end

    local identifier = 'otherplayer-' .. tostring(targetId)

    if Viewers[tonumber(targetId)] and Viewers[tonumber(targetId)] ~= source then
        CloseInventory(Viewers[tonumber(targetId)], identifier)
    end

    Viewers[tonumber(targetId)] = source
    OpenInventories[source] = identifier

    TriggerClientEvent('qb-inventory:client:openInventory', source,
        player.PlayerData.items, FormatForClient(identifier, source))
end

function ClearStash(identifier)
    if not identifier then return false end

    local inventory = Inventories[identifier]
    if not inventory then return false end

    inventory.items = {}
    SaveInventoryItems(identifier)

    return true
end

function CreateShop(shopData)
    if type(shopData) ~= 'table' then return end

    local function register(name, data)
        local items = {}

        for index, item in pairs(data.items or {}) do
            if type(item) == 'table' and type(item.name) == 'string' then
                local shared = Core.SharedItem(item.name)

                if shared then
                    local slot = #items + 1
                    items[slot] = {
                        name = shared.name,
                        amount = tonumber(item.amount) or 1,
                        info = item.info or {},
                        label = shared.label,
                        description = shared.description or '',
                        weight = shared.weight,
                        type = shared.type,
                        unique = shared.unique,
                        useable = shared.useable,
                        price = tonumber(item.price) or 0,
                        image = shared.image,
                        slot = slot,
                        rarity = RarityOf(shared.name),
                    }
                end
            end
        end

        RegisteredShops[name] = {
            name = name,
            label = data.label or name,
            coords = data.coords,
            slots = data.slots or #items,
            items = items,
            type = data.type,
        }
    end

    if shopData.name then
        register(shopData.name, shopData)
        return
    end

    for key, data in pairs(shopData) do
        if type(data) == 'table' then
            if data.name then
                register(type(key) == 'number' and data.name or key, data)
            elseif type(key) == 'string' then
                register(key, data)
            end
        end
    end
end

function OpenShop(source, name)
    if not name then return end

    local player = Core.GetPlayer(source)
    if not player or not RegisteredShops[name] then return end

    local shop = RegisteredShops[name]

    if shop.coords then
        local ped = GetPlayerPed(source)

        if ped and ped > 0 then
            local coords = GetEntityCoords(ped)
            local distance = Core.Distance(
                { x = coords.x, y = coords.y, z = coords.z }, shop.coords)

            if distance > 10.0 then return end
        end
    end

    local identifier = 'shop-' .. name
    OpenInventories[source] = identifier

    TriggerClientEvent('qb-inventory:client:openInventory', source,
        player.PlayerData.items, FormatForClient(identifier, source))
end

function OpenInventory(source, identifier, data)
    local player = Core.GetPlayer(source)
    if not player then return end

    if identifier == nil then
        OpenInventories[source] = nil
        TriggerClientEvent('qb-inventory:client:openInventory', source,
            player.PlayerData.items, nil)
        return
    end

    if type(identifier) ~= 'string' then
        print('^1[qb-inventory]^7 OpenInventory called with an invalid identifier.')
        return
    end

    local kind, value = ParseIdentifier(identifier)

    if kind == 'otherplayer' and value then
        OpenInventoryById(source, tonumber(value))
        return
    end

    if kind == 'shop' and value then
        OpenShop(source, value)
        return
    end

    if kind == 'drop' and value then
        OpenDrop(source, identifier)
        return
    end

    local inventory = EnsureInventory(identifier, data)

    if inventory.isOpen and inventory.isOpen ~= source then
        Core.Notify(source, 'This inventory is already in use.', 'error')
        return
    end

    inventory.isOpen = source
    OpenInventories[source] = identifier

    TriggerClientEvent('qb-inventory:client:openInventory', source,
        player.PlayerData.items, FormatForClient(identifier, source))
end

function CreateInventory(identifier, data)
    if type(identifier) ~= 'string' then return end
    EnsureInventory(identifier, data)
end

function RemoveInventory(identifier)
    if not identifier then return end
    Inventories[identifier] = nil
end

function AddItem(identifier, item, amount, slot, info, reason, isInternalMove)
    if not item then return false end

    -- Forgiving signature: some scripts call AddItem(src, item, amount, info).
    if type(slot) == 'table' and info == nil then
        info = slot
        slot = nil
    end

    local itemInfo = Core.SharedItem(item)
    if not itemInfo then
        print(('^1[qb-inventory]^7 AddItem: unknown item "%s".'):format(tostring(item)))
        return false
    end

    local target, maxweight, slots, player = ResolveTarget(identifier, true)
    if not target then
        print(('^1[qb-inventory]^7 AddItem: inventory "%s" not found.'):format(tostring(identifier)))
        return false
    end

    amount = SanitizeAmount(amount)
    slot = SanitizeSlot(slot)

    if GetTotalWeight(target) + ((tonumber(itemInfo.weight) or 0) * amount) > (maxweight or Config.MaxWeight) then
        return false
    end

    if not slot and not itemInfo.unique then
        slot = GetFirstSlotByItem(target, itemInfo.name)
    end

    local existing = slot and target[slot]

    if existing and existing.name == itemInfo.name and not existing.unique then
        existing.amount = (tonumber(existing.amount) or 0) + amount

        if type(info) == 'table' and type(existing.info) ~= 'table' then
            existing.info = info
        end

        target[slot] = existing

        if player then Core.SetPlayerData(identifier, 'items', target) end

        RefreshHolder(identifier)
        return true
    end

    if not slot then
        slot = GetFirstFreeSlot(target, slots or Config.MaxSlots)
    end

    if not slot or target[slot] ~= nil then
        local free = GetFirstFreeSlot(target, slots or Config.MaxSlots)
        if not free then return false end
        slot = free
    end

    local built = BuildItem(itemInfo.name, amount, slot, info)
    if not built then return false end

    target[slot] = built

    if player then
        Core.SetPlayerData(identifier, 'items', target)
    else
        if Inventories[identifier] then
            SaveInventoryItems(identifier)
        end
    end

    RefreshHolder(identifier)
    return true
end

function RemoveItem(identifier, item, amount, slot, reason, isInternalMove)
    if not item then return false end

    local target, _, _, player = ResolveTarget(identifier)
    if not target then return false end

    amount = SanitizeAmount(amount)
    slot = SanitizeSlot(slot)

    if slot then
        local current = target[slot]

        if not current or current.name ~= item then return false end

        local left = (tonumber(current.amount) or 1) - amount

        if left > 0 then
            current.amount = left
            target[slot] = current
        else
            target[slot] = nil
        end

        if player then
            Core.SetPlayerData(identifier, 'items', target)
            CheckWeapon(identifier, current)
        elseif Inventories[identifier] then
            SaveInventoryItems(identifier)
        end

        RefreshHolder(identifier)
        return true
    end

    -- No slot: remove from any slot until the amount is satisfied.
    local remaining = amount
    local removed = false

    local ordered = {}
    for index, value in pairs(target) do
        local numeric = SanitizeSlot(index)
        if numeric then ordered[#ordered + 1] = { slot = numeric, item = value } end
    end

    table.sort(ordered, function(a, b) return a.slot < b.slot end)

    for _, entry in ipairs(ordered) do
        if remaining <= 0 then break end

        local current = entry.item

        if type(current) == 'table' and current.name == item then
            local available = tonumber(current.amount) or 1
            local take = math.min(available, remaining)

            if available - take > 0 then
                current.amount = available - take
                target[entry.slot] = current
            else
                target[entry.slot] = nil
            end

            remaining = remaining - take
            removed = true

            if player then CheckWeapon(identifier, current) end
        end
    end

    if removed then
        if player then
            Core.SetPlayerData(identifier, 'items', target)
        elseif Inventories[identifier] then
            SaveInventoryItems(identifier)
        end

        RefreshHolder(identifier)
    end

    return remaining <= 0
end

-- ===========================================================================
-- Drops
-- ===========================================================================
function CreateDrop(source, item, amount, slot, info)
    local player = Core.GetPlayer(source)
    if not player then return nil end

    local ped = GetPlayerPed(source)
    local coords = ped and ped > 0 and GetEntityCoords(ped) or nil
    if not coords then return nil end

    amount = SanitizeAmount(amount)

    local current = slot and player.PlayerData.items[SanitizeSlot(slot)] or nil
    local built

    if current and type(current) == 'table' then
        if amount > (tonumber(current.amount) or 1) then amount = tonumber(current.amount) or 1 end
        built = Core.DeepCopy(current)
        built.amount = amount
        built.info = Core.DeepCopy(current.info)
    else
        built = BuildItem(item, amount, 1, info)
    end

    if not built then return nil end

    if not RemoveItem(source, built.name, amount, SanitizeSlot(slot), 'dropped item') then
        return nil
    end

    dropCounter = dropCounter + 1

    local dropId = 'drop-' .. tostring(dropCounter)

    Drops[dropId] = {
        name = dropId,
        label = 'Drop',
        items = { [1] = built },
        coords = { x = coords.x, y = coords.y, z = coords.z - 0.9 },
        maxweight = Config.Drops.MaxWeight or 1000000,
        slots = Config.Drops.Slots or 10,
        isOpen = false,
        createdTime = os.time(),
    }

    TriggerClientEvent('qb-inventory:client:addDrop', -1, dropId, Drops[dropId])
    RefreshClient(source)

    return dropId
end

function OpenDrop(source, identifier)
    local player = Core.GetPlayer(source)
    if not player then return end

    local drop = Drops[identifier]
    if not drop or drop.isOpen then return end

    local ped = GetPlayerPed(source)
    local coords = ped and ped > 0 and GetEntityCoords(ped) or nil

    if coords then
        local distance = Core.Distance(
            { x = coords.x, y = coords.y, z = coords.z }, drop.coords)

        if distance > (Config.Drops.InteractRange + 1.5) then return end
    end

    drop.isOpen = source
    OpenInventories[source] = identifier

    TriggerClientEvent('qb-inventory:client:openInventory', source,
        player.PlayerData.items, FormatForClient(identifier, source))
end

local function RemoveDrop(identifier)
    if not Drops[identifier] then return end

    Drops[identifier] = nil
    TriggerClientEvent('qb-inventory:client:removeDrop', -1, identifier)
end

-- ===========================================================================
-- Export registrations
-- ===========================================================================
exports('LoadInventory', LoadInventory)
exports('SaveInventory', SaveInventory)
exports('SetInventory', SetInventory)
exports('SetItemData', SetItemData)
exports('UseItem', UseItem)
exports('GetSlotsByItem', GetSlotsByItem)
exports('GetFirstSlotByItem', GetFirstSlotByItem)
exports('GetItemBySlot', GetItemBySlot)
exports('GetTotalWeight', GetTotalWeight)
exports('GetItemByName', GetItemByName)
exports('GetItemsByName', GetItemsByName)
exports('GetSlots', GetSlots)
exports('GetItemCount', GetItemCount)
exports('CanAddItem', CanAddItem)
exports('GetFreeWeight', GetFreeWeight)
exports('ClearInventory', ClearInventory)
exports('HasItem', HasItem)
exports('CloseInventory', CloseInventory)
exports('OpenInventoryById', OpenInventoryById)
exports('ClearStash', ClearStash)
exports('CreateShop', CreateShop)
exports('OpenShop', OpenShop)
exports('OpenInventory', OpenInventory)
exports('CreateInventory', CreateInventory)
exports('GetInventory', GetInventory)
exports('RemoveInventory', RemoveInventory)
exports('AddItem', AddItem)
exports('RemoveItem', RemoveItem)

-- Hooks / listeners (lightweight: scripts may subscribe to inventory events).
local Hooks = {}
local Listeners = {}

function AddHook(hookType, callback)
    if type(hookType) ~= 'string' or type(callback) ~= 'function' then return nil end

    Hooks[hookType] = Hooks[hookType] or {}
    local index = #Hooks[hookType] + 1
    Hooks[hookType][index] = callback

    return index
end

function RemoveHook(hookType, hookIdx)
    if Hooks[hookType] then Hooks[hookType][hookIdx] = nil end
end

function AddListener(listenerType, callback)
    if type(listenerType) ~= 'string' or type(callback) ~= 'function' then return nil end

    Listeners[listenerType] = Listeners[listenerType] or {}
    local index = #Listeners[listenerType] + 1
    Listeners[listenerType][index] = callback

    return index
end

function RemoveListener(listenerType, listenerIdx)
    if Listeners[listenerType] then Listeners[listenerType][listenerIdx] = nil end
end

exports('AddHook', AddHook)
exports('RemoveHook', RemoveHook)
exports('AddListener', AddListener)
exports('RemoveListener', RemoveListener)

-- ===========================================================================
-- Move / split / swap (used by the NUI through SetInventoryData)
-- ===========================================================================
local function CanAccess(identifier, source)
    if type(identifier) == 'number' then
        return identifier == source
    end

    if type(identifier) ~= 'string' then return false end

    local kind, value = ParseIdentifier(identifier)

    if kind == 'otherplayer' then
        return Viewers[tonumber(value)] == source
    end

    if kind == 'shop' then
        return false   -- purchases go through the purchase callback
    end

    local inventory = Inventories[identifier] or Drops[identifier]

    return inventory ~= nil and inventory.isOpen == source
end

local function ResolveName(name, source)
    if name == nil or name == 'player' or name == 'self' then
        return source
    end
    return name
end

--- Moves `amount` items from one slot to another, inside one inventory or
--- between two inventories. Handles the four cases the UI can produce:
---   stack   - target slot holds the same stackable item
---   swap    - target slot holds a different item (they trade places)
---   move    - target slot is empty and the whole stack moves
---   split   - target slot is empty and only part of the stack moves
---
--- Both tables may be the SAME table (moving inside one inventory), so the
--- writes are ordered to stay correct in that case.
local function MoveItems(fromItems, fromSlot, toItems, toSlot, amount)
    local item = fromItems[fromSlot]
    if type(item) ~= 'table' then return false end

    local total = tonumber(item.amount) or 1
    if amount > total then amount = total end
    if amount < 1 then return false end

    local target = toItems[toSlot]

    -- 1) stack into an existing, non unique stack of the same item
    if target and target.name == item.name and not target.unique then
        if total - amount > 0 then
            item.amount = total - amount
            fromItems[fromSlot] = item
        else
            fromItems[fromSlot] = nil
        end

        target.amount = (tonumber(target.amount) or 0) + amount
        toItems[toSlot] = target
        return true
    end

    -- 2) swap with a different item - only whole stacks can be swapped
    if target then
        amount = total

        fromItems[fromSlot] = target
        target.slot = fromSlot

        item.amount = amount
        item.slot = toSlot
        toItems[toSlot] = item
        return true
    end

    -- 3) empty target - move everything
    if amount >= total then
        fromItems[fromSlot] = nil
        item.slot = toSlot
        toItems[toSlot] = item
        return true
    end

    -- 4) empty target - split the stack
    local moved = Core.DeepCopy(item)
    moved.amount = amount
    moved.slot = toSlot

    item.amount = total - amount
    fromItems[fromSlot] = item
    toItems[toSlot] = moved

    return true
end

local function DoSetInventoryData(source, fromInventory, toInventory, fromSlot, toSlot, fromAmount, toAmount)
    fromSlot, toSlot = SanitizeSlot(fromSlot), SanitizeSlot(toSlot)
    fromAmount, toAmount = SanitizeAmount(fromAmount), SanitizeAmount(toAmount)

    if not fromSlot or not toSlot then return false end

    local fromId = ResolveName(fromInventory, source)
    local toId = ResolveName(toInventory, source)

    if not CanAccess(fromId, source) or not CanAccess(toId, source) then
        return false
    end

    local fromItems, _, _ = ResolveTarget(fromId)
    local toItems, toMaxWeight, toSlots = ResolveTarget(toId)

    if not fromItems or not toItems then return false end

    -- Dropping onto itself is a no-op.
    if fromId == toId and fromSlot == toSlot then return false end

    local fromItem = fromItems[fromSlot]
    if type(fromItem) ~= 'table' then return false end

    local total = tonumber(fromItem.amount) or 1
    if toAmount > total then toAmount = total end

    local sameInventory = (fromId == toId)
    local target = toItems[toSlot]

    -- Capacity checks (only meaningful when moving into a different container).
    if not sameInventory then
        local weight = (tonumber(fromItem.weight) or 0) * toAmount
        local stacks = (target and target.name == fromItem.name and not target.unique)

        -- In a swap the displaced item moves back into the source container,
        -- so only the difference counts against the target's capacity.
        if target and not stacks then
            weight = weight - itemWeight(target)
        end

        if GetTotalWeight(toItems) + weight > (toMaxWeight or Config.MaxWeight) then
            Core.Notify(source, 'That container is too heavy.', 'error')
            return false
        end

        if not stacks and not target then
            local used, capacity = GetSlots(toId)
            if used >= (capacity or toSlots or Config.MaxSlots) then
                Core.Notify(source, 'That container is full.', 'error')
                return false
            end
        end
    end

    if not MoveItems(fromItems, fromSlot, toItems, toSlot, toAmount) then
        return false
    end

    -- Persist / sync both sides.
    if type(fromId) == 'number' then
        local player = Core.GetPlayer(fromId)
        if player then Core.SetPlayerData(fromId, 'items', player.PlayerData.items) end
    elseif Inventories[fromId] then
        SaveInventoryItems(fromId)
    end

    if type(toId) == 'number' then
        local player = Core.GetPlayer(toId)
        if player then Core.SetPlayerData(toId, 'items', player.PlayerData.items) end
    elseif Inventories[toId] then
        SaveInventoryItems(toId)
    end

    if Drops[fromId] and TableSize(Drops[fromId].items) == 0 then
        RemoveDrop(fromId)
    end

    RefreshClient(source)
    RefreshHolder(fromId)
    RefreshHolder(toId)

    return true
end

-- ===========================================================================
-- Shared handlers
--
-- These take the source explicitly instead of reading the `source` global, so
-- the legacy `inventory:server:*` aliases can reuse them without depending on
-- `TriggerEvent` propagating `source` to the next handler.
-- ===========================================================================
local function HandleSetInventoryData(src, fromInventory, toInventory, fromSlot, toSlot, fromAmount, toAmount)
    if type(fromInventory) ~= 'string' or type(toInventory) ~= 'string' then return end
    if toInventory:find('^shop%-') or fromInventory:find('^shop%-') then return end

    local moved = DoSetInventoryData(src, fromInventory, toInventory, fromSlot, toSlot, fromAmount, toAmount)

    if not moved then
        -- Tell the UI to redraw so a rejected move never looks like it worked.
        TriggerClientEvent('qb-inventory:client:updateInventory', src,
            fromInventory, toInventory, nil, nil, fromSlot)
    end
end

local function HandleCloseInventory(src, inventory)
    if type(inventory) == 'string' then
        if inventory:find('^otherplayer%-') then
            local target = tonumber(inventory:match('^otherplayer%-(.+)'))
            if target then Viewers[target] = nil end
        end

        if Drops[inventory] then
            Drops[inventory].isOpen = false

            if TableSize(Drops[inventory].items) == 0 then
                RemoveDrop(inventory)
            end
        end

        if Inventories[inventory] then
            Inventories[inventory].isOpen = false
            SaveInventoryItems(inventory)
        end
    end

    OpenInventories[src] = nil
end

local function HandleUseItem(src, item)
    if type(item) ~= 'table' then return end

    local slot = SanitizeSlot(item.slot)
    if not slot then return end

    local itemData = GetItemBySlot(src, slot)
    if not itemData then return end

    local itemInfo = Core.SharedItem(itemData.name)

    if itemData.type == 'weapon' then
        TriggerClientEvent('qb-weapons:client:UseWeapon', src, itemData,
            itemData.info and itemData.info.quality and itemData.info.quality > 0)
        TriggerClientEvent('qb-inventory:client:ItemBox', src, itemInfo or itemData, 'use')
        return
    end

    if not itemData.useable then return end

    if UseItem(itemData.name, src, itemData) then
        TriggerClientEvent('qb-inventory:client:ItemBox', src, itemInfo or itemData, 'use')
    end
end

-- ===========================================================================
-- Events
-- ===========================================================================
RegisterNetEvent('qb-inventory:server:SetInventoryData', function(fromInventory, toInventory, fromSlot, toSlot, fromAmount, toAmount)
    HandleSetInventoryData(source, fromInventory, toInventory, fromSlot, toSlot, fromAmount, toAmount)
end)

RegisterNetEvent('qb-inventory:server:closeInventory', function(inventory)
    HandleCloseInventory(source, inventory)
end)

RegisterNetEvent('qb-inventory:server:useItem', function(item)
    HandleUseItem(source, item)
end)

RegisterNetEvent('qb-inventory:server:openDrop', function(dropId)
    OpenDrop(source, dropId)
end)

RegisterNetEvent('qb-inventory:server:updateDrop', function(dropId, coords)
    if type(dropId) ~= 'string' or type(coords) ~= 'table' then return end
    if not Drops[dropId] then return end

    Drops[dropId].coords = coords
end)

RegisterNetEvent('qb-inventory:server:snowball', function(action)
    if action == 'add' then
        AddItem(source, 'weapon_snowball', 1, nil, nil, 'snowball')
    elseif action == 'remove' then
        RemoveItem(source, 'weapon_snowball', 1, nil, 'snowball')
    end
end)

RegisterNetEvent('qb-inventory:server:openVending', function(data)
    local src = source

    if not Config.Shops.Enabled then return end

    local identifier = 'shop-vending'

    if not RegisteredShops['vending'] then
        CreateShop({
            name = 'vending',
            label = 'Vending Machine',
            items = Config.VendingItems or {
                { name = 'water_bottle', price = 4, amount = 50 },
                { name = 'kurkakola', price = 4, amount = 50 },
            },
        })
    end

    local player = Core.GetPlayer(src)
    if not player then return end

    OpenInventories[src] = identifier

    TriggerClientEvent('qb-inventory:client:openInventory', src,
        player.PlayerData.items, FormatForClient(identifier, src))
end)

-- Legacy `inventory:server:*` aliases ---------------------------------------
RegisterNetEvent('inventory:server:SetInventoryData', function(fromInventory, toInventory, fromSlot, toSlot, fromAmount, toAmount)
    HandleSetInventoryData(source, fromInventory, toInventory, fromSlot, toSlot, fromAmount, toAmount)
end)

RegisterNetEvent('inventory:server:OpenInventory', function(kind, id, other)
    local src = source

    if kind == 'stash' then
        OpenInventory(src, 'stash-' .. tostring(id), other)
    elseif kind == 'trunk' then
        OpenInventory(src, 'trunk-' .. tostring(id), other)
    elseif kind == 'glovebox' then
        OpenInventory(src, 'glovebox-' .. tostring(id), other)
    elseif kind == 'drop' then
        OpenInventory(src, tostring(id), other)
    elseif kind == 'shop' then
        OpenShop(src, tostring(id))
    elseif kind == 'otherplayer' then
        OpenInventoryById(src, tonumber(id))
    else
        OpenInventory(src, nil)
    end
end)

RegisterNetEvent('inventory:server:UseItemSlot', function(slot)
    local src = source
    local slotNumber = SanitizeSlot(slot)
    if not slotNumber then return end

    local itemData = GetItemBySlot(src, slotNumber)
    if not itemData then return end

    HandleUseItem(src, { slot = slotNumber, name = itemData.name })
end)

RegisterNetEvent('inventory:server:SaveInventory', function()
    SaveInventory(source)
end)

RegisterNetEvent('inventory:server:closeInventory', function(inventory)
    HandleCloseInventory(source, inventory)
end)

-- ===========================================================================
-- Callbacks
-- ===========================================================================
Core.CreateCallback('qb-inventory:server:GetCurrentDrops', function(_, cb)
    cb(Drops)
end)

Core.CreateCallback('qb-inventory:server:createDrop', function(source, cb, item)
    local dropId = CreateDrop(source, item and item.name, item and item.amount,
        item and item.fromSlot or item and item.slot)

    cb(dropId or false)
end)

Core.CreateCallback('qb-inventory:server:attemptPurchase', function(source, cb, data)
    if type(data) ~= 'table' or type(data.item) ~= 'table' then cb(false) return end

    local itemInfo = data.item
    local amount = SanitizeAmount(data.amount)
    local shopName = tostring(data.shop or ''):gsub('^shop%-', '')

    local player = Core.GetPlayer(source)
    if not player then cb(false) return end

    local shop = RegisteredShops[shopName]
    if not shop then cb(false) return end

    local slot = SanitizeSlot(itemInfo.slot)
    local stock = slot and shop.items[slot]

    if not stock or stock.name ~= itemInfo.name then cb(false) return end
    if amount > (tonumber(stock.amount) or 0) or (tonumber(stock.amount) or 0) <= 0 then
        Core.Notify(source, 'Not enough stock.', 'error')
        cb(false) return
    end

    local canAdd, blockedBy = CanAddItem(source, itemInfo.name, amount)
    if not canAdd then
        Core.Notify(source, blockedBy == 'weight' and 'Your inventory is too heavy.'
            or 'Your inventory is full.', 'error')
        cb(false) return
    end

    local price = (tonumber(stock.price) or 0) * amount
    local account = (shop.type == 'bank') and 'bank' or 'cash'

    if Core.GetMoney(source, account) < price then
        Core.Notify(source, 'You do not have enough money.', 'error')
        cb(false) return
    end

    if not Core.RemoveMoney(source, account, price, 'shop-purchase') then
        cb(false) return
    end

    AddItem(source, itemInfo.name, amount, nil, stock.info, 'shop-purchase')

    stock.amount = (tonumber(stock.amount) or 0) - amount
    shop.items[slot] = stock

    TriggerEvent('qb-shops:server:UpdateShopItems', shopName, itemInfo, amount)

    RefreshClient(source)
    cb(true)
end)

Core.CreateCallback('qb-inventory:server:giveItem', function(source, cb, target, item, amount, slot, info)
    local player = Core.GetPlayer(source)
    local targetPlayer = Core.GetPlayer(tonumber(target))

    if not player or not targetPlayer then cb(false) return end
    if tonumber(target) == source then cb(false) return end

    amount = SanitizeAmount(amount)

    local ped = GetPlayerPed(source)
    local targetPed = GetPlayerPed(tonumber(target))
    local distance = 9999.0

    if ped and targetPed and ped > 0 and targetPed > 0 then
        local a, b = GetEntityCoords(ped), GetEntityCoords(targetPed)
        distance = Core.Distance({ x = a.x, y = a.y, z = a.z }, { x = b.x, y = b.y, z = b.z })
    end

    if distance > (Config.OtherPlayer.Range + 1.5) then
        Core.Notify(source, 'Nobody is close enough.', 'error')
        cb(false) return
    end

    local slotNumber = SanitizeSlot(slot)
    local current = slotNumber and player.PlayerData.items[slotNumber]

    if not current or current.name ~= item then cb(false) return end
    if amount > (tonumber(current.amount) or 1) then amount = tonumber(current.amount) or 1 end

    local canAdd, blockedBy = CanAddItem(tonumber(target), item, amount)
    if not canAdd then
        Core.Notify(source, blockedBy == 'weight' and 'Their inventory is too heavy.'
            or 'Their inventory is full.', 'error')
        cb(false) return
    end

    local takenInfo = Core.DeepCopy(current.info)

    if not RemoveItem(source, item, amount, slotNumber, 'given to player') then
        cb(false) return
    end

    AddItem(tonumber(target), item, amount, nil, takenInfo, 'received from player')

    RefreshClient(source)
    RefreshClient(tonumber(target))

    cb(true)
end)

Core.CreateCallback('qb-inventory:server:openStash', function(source, cb, identifier, data)
    OpenInventory(source, identifier, data)
    cb(true)
end)

-- ===========================================================================
-- Vehicle helpers (legacy API kept alive for qb-vehiclekeys / trunk scripts)
-- ===========================================================================
local function VehicleInventory(identifier, kind, data)
    local inventory = EnsureInventory(identifier, data)
    return inventory
end

RegisterNetEvent('qb-inventory:server:OpenTrunk', function(plate, class, model)
    local src = source
    if type(plate) ~= 'string' then return end

    local settings = (Config.Vehicles.Trunk.ClassOverrides and
        Config.Vehicles.Trunk.ClassOverrides[tonumber(class)]) or
        Config.Vehicles.Trunk.Default

    VehicleInventory('trunk-' .. plate, 'trunk', {
        label = 'Trunk - ' .. plate,
        slots = settings.slots or settings.Slots or 50,
        maxweight = settings.maxweight or settings.MaxWeight or 60000,
    })

    OpenInventory(src, 'trunk-' .. plate)
end)

RegisterNetEvent('qb-inventory:server:OpenGlovebox', function(plate)
    local src = source
    if type(plate) ~= 'string' then return end

    local settings = Config.Vehicles.Glovebox

    VehicleInventory('glovebox-' .. plate, 'glovebox', {
        label = 'Glovebox - ' .. plate,
        slots = settings.Slots or 5,
        maxweight = settings.MaxWeight or 10000,
    })

    OpenInventory(src, 'glovebox-' .. plate)
end)

RegisterNetEvent('inventory:server:OpenTrunk', function(plate, class, model)
    TriggerEvent('qb-inventory:server:OpenTrunk', plate, class, model)
end)

RegisterNetEvent('inventory:server:OpenGlovebox', function(plate)
    TriggerEvent('qb-inventory:server:OpenGlovebox', plate)
end)

-- ===========================================================================
-- Opening your own inventory / dropping / settings
-- ===========================================================================
RegisterNetEvent('qb-inventory:server:openSelf', function()
    OpenInventory(source, nil)
end)

RegisterNetEvent('qb-inventory:server:dropItem', function(slot, amount)
    local src = source

    local slotNumber = SanitizeSlot(slot)
    if not slotNumber then return end

    local item = GetItemBySlot(src, slotNumber)
    if type(item) ~= 'table' then return end

    local amountNumber = SanitizeAmount(amount)
    if amountNumber > (tonumber(item.amount) or 1) then
        amountNumber = tonumber(item.amount) or 1
    end

    if not Config.Drops.Enabled then
        Core.Notify(src, 'Dropping items is disabled.', 'error')
        return
    end

    CreateDrop(src, item.name, amountNumber, slotNumber, item.info)
end)

-- Server wide look ("admin lock"). Players store their own profile in the
-- browser, this only pushes one shared profile to everybody.
local ServerSettings = nil

RegisterNetEvent('qb-inventory:server:adminPush', function(settings)
    local src = source

    if not Core.HasPermission(src, Config.Permissions.AdminLock) then
        Core.Notify(src, 'You do not have permission to do that.', 'error')
        return
    end

    if type(settings) ~= 'table' then return end

    ServerSettings = settings

    TriggerClientEvent('qb-inventory:client:applySettings', -1, settings, true)
    Core.Notify(src, 'Inventory look pushed to the whole server.', 'success')
end)

RegisterNetEvent('qb-inventory:server:resetSettings', function()
    TriggerClientEvent('qb-inventory:client:applySettings', source,
        ServerSettings or Config.Defaults, ServerSettings ~= nil)
end)

-- ===========================================================================
-- Player lifecycle
-- ===========================================================================
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source

    OpenInventories[src] = nil

    SetTimeout(1000, function()
        if Config.Drops.Enabled then
            TriggerClientEvent('qb-inventory:client:syncDrops', src, Drops)
        end

        if ServerSettings then
            TriggerClientEvent('qb-inventory:client:applySettings', src, ServerSettings, true)
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local identifier = OpenInventories[src]

    if identifier then
        if Inventories[identifier] then
            Inventories[identifier].isOpen = false
            SaveInventoryItems(identifier)
        end

        if Drops[identifier] then
            Drops[identifier].isOpen = false
        end

        local kind, value = ParseIdentifier(identifier)
        if kind == 'otherplayer' and value then
            Viewers[tonumber(value)] = nil
        end
    end

    OpenInventories[src] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for identifier in pairs(Inventories) do
        SaveInventoryItems(identifier)
    end
end)

-- ===========================================================================
-- Background threads
-- ===========================================================================
CreateThread(function()
    while true do
        Wait(5 * MINUTE)

        for identifier in pairs(Inventories) do
            local inventory = Inventories[identifier]

            if inventory and inventory.isOpen == false then
                SaveInventoryItems(identifier)
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1 * MINUTE)

        if Config.Drops.DespawnTime and Config.Drops.DespawnTime > 0 then
            local now = os.time()

            for identifier, drop in pairs(Drops) do
                if drop.isOpen == false and (now - (drop.createdTime or now)) > (Config.Drops.DespawnTime * 60) then
                    RemoveDrop(identifier)
                end
            end
        end
    end
end)

-- ===========================================================================
-- Admin commands
-- ===========================================================================
RegisterCommand('clearinv', function(source, args)
    if source == 0 then
        print('^1[qb-inventory]^7 Run /clearinv in game or pass a player id.')
        return
    end

    if not Core.HasPermission(source, Config.Permissions.AdminLock) then
        Core.Notify(source, 'You do not have permission to do that.', 'error')
        return
    end

    local target = tonumber(args[1]) or source
    ClearInventory(target)
    Core.Notify(source, 'Inventory cleared.', 'success')
end, false)

RegisterCommand('giveitem', function(source, args)
    if source == 0 then
        print('^1[qb-inventory]^7 Run /giveitem in game.')
        return
    end

    if not Core.HasPermission(source, Config.Permissions.AdminLock) then
        Core.Notify(source, 'You do not have permission to do that.', 'error')
        return
    end

    local target = tonumber(args[1]) or source
    local item = args[2]
    local amount = tonumber(args[3]) or 1

    if not item then
        Core.Notify(source, 'Usage: /giveitem [id] [item] [amount]', 'error')
        return
    end

    if AddItem(target, item, amount, nil, nil, 'admin command') then
        Core.Notify(source, ('Gave %dx %s.'):format(amount, item), 'success')
    else
        Core.Notify(source, 'Could not give that item.', 'error')
    end
end, false)

Core.Log('Server side ready - ' .. tostring(TableSize(RegisteredShops)) .. ' shops registered.')
