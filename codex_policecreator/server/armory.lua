--[[
    server/armory.lua - rank restricted armory issue / return.
]]

Armory = {}

local RESOURCE = GetCurrentResourceName()
local serialCounter = 0

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

local function nextSerial(dept)
    serialCounter = serialCounter + 1
    local prefix = (Config.Armory.Serials and Config.Armory.Serials.Prefix) or 'PC'
    local tag = (dept and tostring(dept.name) or 'XX'):upper():gsub('[^%u]', ''):sub(1, 3)
    return ('%s-%s-%06d'):format(prefix, tag, (os.time() % 1000000) * 100 + serialCounter % 100)
end

--- Items the member is allowed to see, with an `allowed` flag for the NUI.
function Armory.Catalog(dept, member)
    local list = {}
    local grade = -1

    if dept and member then
        local rank = Core.FindRankById(dept, member.rankId)
        grade = rank and tonumber(rank.grade) or -1
    end

    for index, item in ipairs(Config.Armory.Items or {}) do
        local allowed = grade >= (tonumber(item.rank) or 0)
        list[#list + 1] = {
            index = index,
            item = item.item,
            label = item.label or item.item,
            rank = tonumber(item.rank) or 0,
            ammo = tonumber(item.ammo) or 0,
            amount = tonumber(item.amount) or 1,
            allowed = allowed,
            stock = Config.Armory.LimitedStock and (Config.Armory.Stock[item.item] or 0) or -1
        }
    end

    return list
end

--- Give one catalogue entry to the player.
function Armory.Take(src, itemIndex)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'armory') then return false, 'no_permission' end

    local entry = (Config.Armory.Items or {})[tonumber(itemIndex)]
    if not entry then return false, 'invalid_item' end

    local rank = Core.FindRankById(dept, member.rankId)
    local grade = rank and tonumber(rank.grade) or -1
    if grade < (tonumber(entry.rank) or 0) then return false, 'rank_too_low' end

    if Config.Armory.LimitedStock then
        local stock = Config.Armory.Stock[entry.item] or 0
        if stock <= 0 then return false, 'out_of_stock' end
        Config.Armory.Stock[entry.item] = stock - 1
    end

    local amount = tonumber(entry.amount) or 1
    local metadata

    if Config.Armory.Serials and Config.Armory.Serials.Enabled and tostring(entry.item):upper():sub(1, 7) == 'WEAPON_' then
        metadata = { [Config.Armory.Serials.MetadataKey] = nextSerial(dept) }
    end

    local ok = Bridge.AddItem(src, entry.item, amount, metadata)
    if not ok then
        if Config.Armory.LimitedStock then
            Config.Armory.Stock[entry.item] = (Config.Armory.Stock[entry.item] or 0) + 1
        end
        return false, 'inventory_full'
    end

    -- Ammunition for weapons is issued together with the weapon.
    if tonumber(entry.ammo) and entry.ammo > 0 then
        pcall(function()
            local ped = GetPlayerPed(src)
            if ped and ped > 0 then
                GiveWeaponToPed(ped, joaat(entry.item), tonumber(entry.ammo), false, true)
            end
        end)
    end

    Bridge.Notify(src, ('Took %s from the armory'):format(entry.label or entry.item), 'success')
    log(('%s took %s'):format(citizenid, entry.item))
    return true
end

--- Put an item back (returns stock when LimitedStock is on).
function Armory.Store(src, itemIndex)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local entry = (Config.Armory.Items or {})[tonumber(itemIndex)]
    if not entry then return false, 'invalid_item' end

    local amount = tonumber(entry.amount) or 1
    if not Bridge.RemoveItem(src, entry.item, amount) then return false, 'no_item' end

    if Config.Armory.LimitedStock then
        Config.Armory.Stock[entry.item] = (Config.Armory.Stock[entry.item] or 0) + amount
    end

    Bridge.Notify(src, ('Returned %s'):format(entry.label or entry.item), 'primary')
    return true
end

--- Refill the stock table from config when LimitedStock is enabled.
function Armory.Restock()
    if not Config.Armory.LimitedStock then return end
    Config.Armory.Stock = {}
    for _, item in ipairs(Config.Armory.Items or {}) do
        Config.Armory.Stock[item.item] = tonumber(item.stock) or 25
    end
end
