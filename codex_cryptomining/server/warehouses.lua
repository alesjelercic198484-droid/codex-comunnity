--[[
    Warehouse state: ownership, rigs, production, electricity, keys.
    Everything lives in memory and is flushed to MySQL on a timer and on
    resource stop, so the mining loop never waits on the database.
]]

CodexCryptoWH = CodexCryptoWH or {}

local WH = CodexCryptoWH
local Crypto = CodexCrypto
local DB = CodexCryptoDB
local FW = CodexCryptoFW
local Market = CodexCryptoMarket
local RESOURCE = GetCurrentResourceName()

-- warehouseId -> state
WH.state = {}
WH.loaded = false

local dirtyWarehouses = {}
local dirtyRigs = {}
local deletedRigs = {}

local function MarkWarehouseDirty(warehouseId)
    dirtyWarehouses[warehouseId] = true
end

local function MarkRigDirty(rig)
    if rig and rig.id then
        dirtyRigs[rig.id] = true
    end
end

function WH.Get(warehouseId)
    return WH.state[warehouseId]
end

function WH.GetConfig(warehouseId)
    return Crypto.GetWarehouseConfig(warehouseId)
end

local function NewState(warehouseId)
    return {
        id = warehouseId,
        owner = nil,
        ownerName = nil,
        btc = 0.0,
        bill = 0,
        billFraction = 0.0,
        powered = true,
        locked = true,
        lastTick = os.time(),
        totalMined = 0.0,
        totalEarned = 0,
        robbedAt = 0,
        gpuStock = 0,
        rigs = {},
        keys = {}
    }
end

function WH.CountOwned(identifier)
    local count = 0
    if not identifier then
        return 0
    end

    for _, state in pairs(WH.state) do
        if state.owner == identifier then
            count = count + 1
        end
    end

    return count
end

function WH.HasAccess(identifier, warehouseId)
    local state = WH.state[warehouseId]
    if not state or not identifier then
        return false
    end

    if state.owner == identifier then
        return true
    end

    return state.keys[identifier] ~= nil
end

function WH.IsOwner(identifier, warehouseId)
    local state = WH.state[warehouseId]
    return state ~= nil and identifier ~= nil and state.owner == identifier
end

-- GPU storage: spare GPUs kept inside the warehouse crate (persisted per
-- warehouse when the classic ESX inventory is used; ox_inventory keeps its
-- own stash, so these helpers are only touched by the ESX fallback path).
function WH.GetGpuStock(warehouseId)
    local state = WH.state[warehouseId]
    return state and math.max(0, Crypto.ToInt(state.gpuStock, 0)) or 0
end

function WH.SetGpuStock(warehouseId, amount)
    local state = WH.state[warehouseId]
    if not state then
        return false
    end

    state.gpuStock = math.max(0, Crypto.ToInt(amount, 0))
    MarkWarehouseDirty(warehouseId)
    WH.Sync(warehouseId)
    return true
end

function WH.CountGpus(warehouseId)
    local state = WH.state[warehouseId]
    if not state then
        return 0
    end

    local total = 0
    for _, rig in pairs(state.rigs) do
        total = total + Crypto.ToInt(rig.gpus, 0)
    end

    return total
end

function WH.GetFreeSlot(warehouseId)
    local state = WH.state[warehouseId]
    if not state then
        return nil
    end

    local maxRigs = Crypto.GetMaxRigs(warehouseId)
    local used = {}

    for _, rig in pairs(state.rigs) do
        used[Crypto.ToInt(rig.slot, -1)] = true
    end

    for slot = 1, maxRigs do
        if not used[slot] then
            return slot
        end
    end

    return nil
end

function WH.GetRig(warehouseId, rigId)
    local state = WH.state[warehouseId]
    if not state then
        return nil
    end
    return state.rigs[rigId]
end

-- ---------------------------------------------------------------------------
-- LOADING / SAVING
-- ---------------------------------------------------------------------------
function WH.Load()
    WH.state = {}

    for _, warehouse in ipairs(Config.Warehouses or {}) do
        WH.state[warehouse.id] = NewState(warehouse.id)
    end

    if not DB.ready then
        WH.loaded = true
        return
    end

    local rows = DB.Fetch('SELECT * FROM `codex_crypto_warehouses`')
    for _, row in ipairs(rows or {}) do
        local state = WH.state[row.warehouse_id]
        if state then
            state.owner = (row.owner ~= nil and row.owner ~= '' and row.owner ~= false) and row.owner or nil
            state.ownerName = (row.owner_name ~= nil and row.owner_name ~= '' and row.owner_name ~= false) and row.owner_name or nil
            state.btc = math.max(0.0, Crypto.ToNumber(row.btc, 0))
            state.bill = math.max(0, Crypto.ToInt(row.bill, 0))
            state.powered = Crypto.ToBool(row.powered)
            state.locked = Crypto.ToBool(row.locked)
            state.lastTick = Crypto.ToInt(row.last_tick, os.time())
            state.totalMined = Crypto.ToNumber(row.total_mined, 0)
            state.totalEarned = Crypto.ToInt(row.total_earned, 0)
            state.robbedAt = Crypto.ToInt(row.robbed_at, 0)
            state.gpuStock = math.max(0, Crypto.ToInt(row.gpu_stock, 0))

            if state.lastTick <= 0 then
                state.lastTick = os.time()
            end
        end
    end

    local rigRows = DB.Fetch('SELECT * FROM `codex_crypto_rigs`')
    for _, row in ipairs(rigRows or {}) do
        local state = WH.state[row.warehouse_id]
        if state then
            local id = Crypto.ToInt(row.id, 0)
            local maxGpus = Crypto.GetMaxGpus()

            if id > 0 then
                state.rigs[id] = {
                    id = id,
                    warehouseId = row.warehouse_id,
                    slot = Crypto.ToInt(row.slot, 1),
                    gpus = Crypto.Clamp(Crypto.ToInt(row.gpus, 0), 0, maxGpus),
                    cpu = Crypto.Clamp(Crypto.ToInt(row.cpu, 0), 0, Crypto.ToInt(Config.Mining.Cpu.MaxLevel, 3)),
                    cooler = Crypto.Clamp(Crypto.ToInt(row.cooler, 0), 0, Crypto.ToInt(Config.Mining.Cooler.MaxLevel, 3)),
                    durability = Crypto.Clamp(Crypto.ToNumber(row.durability, 100), 0.0, 100.0),
                    broken = Crypto.ToBool(row.broken)
                }
            end
        end
    end

    WH.loaded = true
    Crypto.DebugPrint(('Loaded %d warehouses.'):format(Crypto.TableCount(WH.state)))
end

local function SaveWarehouse(warehouseId)
    local state = WH.state[warehouseId]
    if not state or not DB.ready then
        return
    end

    DB.Execute([[
        INSERT INTO `codex_crypto_warehouses`
            (`warehouse_id`, `owner`, `owner_name`, `btc`, `bill`, `powered`, `locked`, `last_tick`, `total_mined`, `total_earned`, `robbed_at`, `gpu_stock`)
        VALUES (@id, @owner, @owner_name, @btc, @bill, @powered, @locked, @last_tick, @total_mined, @total_earned, @robbed_at, @gpu_stock)
        ON DUPLICATE KEY UPDATE
            `owner` = VALUES(`owner`),
            `owner_name` = VALUES(`owner_name`),
            `btc` = VALUES(`btc`),
            `bill` = VALUES(`bill`),
            `powered` = VALUES(`powered`),
            `locked` = VALUES(`locked`),
            `last_tick` = VALUES(`last_tick`),
            `total_mined` = VALUES(`total_mined`),
            `total_earned` = VALUES(`total_earned`),
            `robbed_at` = VALUES(`robbed_at`),
            `gpu_stock` = VALUES(`gpu_stock`)
    ]], {
        ['@id'] = state.id,
        -- Empty string instead of nil: a nil parameter would be dropped by the
        -- driver and shift every following column. Load() maps '' back to nil.
        ['@owner'] = state.owner or '',
        ['@owner_name'] = state.ownerName or '',
        ['@btc'] = Crypto.Round(state.btc, 8),
        ['@bill'] = math.floor(state.bill),
        ['@powered'] = state.powered and 1 or 0,
        ['@locked'] = state.locked and 1 or 0,
        ['@last_tick'] = math.floor(state.lastTick),
        ['@total_mined'] = Crypto.Round(state.totalMined, 8),
        ['@total_earned'] = math.floor(state.totalEarned),
        ['@robbed_at'] = math.floor(state.robbedAt),
        ['@gpu_stock'] = math.max(0, Crypto.ToInt(state.gpuStock, 0))
    })
end

local function SaveRig(rig)
    if not rig or not DB.ready then
        return
    end

    DB.Execute([[
        UPDATE `codex_crypto_rigs`
        SET `gpus` = @gpus, `cpu` = @cpu, `cooler` = @cooler, `durability` = @durability, `broken` = @broken
        WHERE `id` = @id
    ]], {
        ['@id'] = rig.id,
        ['@gpus'] = Crypto.ToInt(rig.gpus, 0),
        ['@cpu'] = Crypto.ToInt(rig.cpu, 0),
        ['@cooler'] = Crypto.ToInt(rig.cooler, 0),
        ['@durability'] = Crypto.Round(rig.durability, 2),
        ['@broken'] = rig.broken and 1 or 0
    })
end

function WH.Flush(force)
    if not DB.ready then
        return
    end

    for rigId in pairs(deletedRigs) do
        DB.Execute('DELETE FROM `codex_crypto_rigs` WHERE `id` = @id', { ['@id'] = rigId })
        dirtyRigs[rigId] = nil
    end
    deletedRigs = {}

    for rigId in pairs(dirtyRigs) do
        local found = nil
        for _, state in pairs(WH.state) do
            if state.rigs[rigId] then
                found = state.rigs[rigId]
                break
            end
        end

        if found then
            SaveRig(found)
        end
    end
    dirtyRigs = {}

    for warehouseId in pairs(dirtyWarehouses) do
        SaveWarehouse(warehouseId)
    end
    dirtyWarehouses = {}

    if force then
        for warehouseId in pairs(WH.state) do
            SaveWarehouse(warehouseId)
        end
    end
end

-- ---------------------------------------------------------------------------
-- KEYS
-- ---------------------------------------------------------------------------
function WH.LoadKeys()
    if not DB.ready then
        return
    end

    local rows = DB.Fetch('SELECT * FROM `codex_crypto_keys`')
    for _, row in ipairs(rows or {}) do
        local state = WH.state[row.warehouse_id]
        if state and row.identifier then
            state.keys[row.identifier] = row.name or 'Unknown'
        end
    end
end

function WH.GiveKey(warehouseId, identifier, name)
    local state = WH.state[warehouseId]
    if not state or not identifier then
        return false
    end

    state.keys[identifier] = name or 'Unknown'

    if DB.ready then
        DB.Execute([[
            INSERT INTO `codex_crypto_keys` (`warehouse_id`, `identifier`, `name`)
            VALUES (@warehouse, @identifier, @name)
            ON DUPLICATE KEY UPDATE `name` = VALUES(`name`)
        ]], {
            ['@warehouse'] = warehouseId,
            ['@identifier'] = identifier,
            ['@name'] = name or 'Unknown'
        })
    end

    return true
end

function WH.RemoveKey(warehouseId, identifier)
    local state = WH.state[warehouseId]
    if not state or not identifier then
        return false
    end

    state.keys[identifier] = nil

    if DB.ready then
        DB.Execute('DELETE FROM `codex_crypto_keys` WHERE `warehouse_id` = @warehouse AND `identifier` = @identifier', {
            ['@warehouse'] = warehouseId,
            ['@identifier'] = identifier
        })
    end

    return true
end

function WH.ClearKeys(warehouseId)
    local state = WH.state[warehouseId]
    if not state then
        return
    end

    state.keys = {}

    if DB.ready then
        DB.Execute('DELETE FROM `codex_crypto_keys` WHERE `warehouse_id` = @warehouse', { ['@warehouse'] = warehouseId })
    end
end

-- ---------------------------------------------------------------------------
-- OWNERSHIP
-- ---------------------------------------------------------------------------
function WH.SetOwner(warehouseId, identifier, name)
    local state = WH.state[warehouseId]
    if not state then
        return false
    end

    state.owner = identifier
    state.ownerName = name
    state.lastTick = os.time()
    MarkWarehouseDirty(warehouseId)
    SaveWarehouse(warehouseId)

    return true
end

function WH.Reset(warehouseId, keepOwner)
    local state = WH.state[warehouseId]
    if not state then
        return false
    end

    for rigId in pairs(state.rigs) do
        deletedRigs[rigId] = true
    end

    state.rigs = {}
    state.btc = 0.0
    state.bill = 0
    state.powered = true
    state.locked = true
    state.lastTick = os.time()
    state.robbedAt = 0

    if not keepOwner then
        state.owner = nil
        state.ownerName = nil
        WH.ClearKeys(warehouseId)
    end

    if DB.ready then
        DB.Execute('DELETE FROM `codex_crypto_rigs` WHERE `warehouse_id` = @warehouse', { ['@warehouse'] = warehouseId })
        deletedRigs = {}
    end

    MarkWarehouseDirty(warehouseId)
    SaveWarehouse(warehouseId)
    WH.Sync(warehouseId)

    return true
end

-- ---------------------------------------------------------------------------
-- RIGS
-- ---------------------------------------------------------------------------
function WH.AddRig(warehouseId, slot)
    local state = WH.state[warehouseId]
    if not state then
        return nil
    end

    slot = slot or WH.GetFreeSlot(warehouseId)
    if not slot then
        return nil
    end

    local id = nil

    if DB.ready then
        id = Crypto.ToInt(DB.Insert([[
            INSERT INTO `codex_crypto_rigs` (`warehouse_id`, `slot`, `gpus`, `cpu`, `cooler`, `durability`, `broken`)
            VALUES (@warehouse, @slot, 0, 0, 0, 100, 0)
        ]], {
            ['@warehouse'] = warehouseId,
            ['@slot'] = slot
        }), 0)
    end

    if not id or id <= 0 then
        -- Offline / no database fallback: generate a local id that cannot
        -- collide with auto increment ids already in memory.
        id = 0
        for rigId in pairs(state.rigs) do
            if rigId > id then
                id = rigId
            end
        end
        id = id + 1
    end

    local rig = {
        id = id,
        warehouseId = warehouseId,
        slot = slot,
        gpus = 0,
        cpu = 0,
        cooler = 0,
        durability = 100.0,
        broken = false
    }

    state.rigs[id] = rig
    MarkRigDirty(rig)

    return rig
end

function WH.RemoveRig(warehouseId, rigId)
    local state = WH.state[warehouseId]
    if not state then
        return false
    end

    local rig = state.rigs[rigId]
    if not rig then
        return false
    end

    state.rigs[rigId] = nil
    dirtyRigs[rigId] = nil
    deletedRigs[rigId] = true

    if DB.ready then
        DB.Execute('DELETE FROM `codex_crypto_rigs` WHERE `id` = @id', { ['@id'] = rigId })
        deletedRigs[rigId] = nil
    end

    return true
end

WH.MarkWarehouseDirty = MarkWarehouseDirty
WH.MarkRigDirty = MarkRigDirty
WH.SaveWarehouse = SaveWarehouse

-- ---------------------------------------------------------------------------
-- PRODUCTION TICK
-- ---------------------------------------------------------------------------
local function IsCrewOnline(state)
    if FW.GetPlayerByIdentifier(state.owner) then
        return true
    end

    for identifier in pairs(state.keys) do
        if FW.GetPlayerByIdentifier(identifier) then
            return true
        end
    end

    return false
end

--- Runs the economy for one warehouse over `elapsed` seconds.
function WH.Tick(warehouseId, elapsed)
    local state = WH.state[warehouseId]
    if not state or not state.owner then
        return
    end

    elapsed = math.max(0, math.floor(Crypto.ToNumber(elapsed, 0)))
    if elapsed <= 0 then
        return
    end

    -- Never grant more than one day of offline production in a single tick.
    if elapsed > 86400 then
        elapsed = 86400
    end

    local mining = Config.Mining
    local changed = false

    if not Config.Mining.OfflineMining and not IsCrewOnline(state) then
        state.lastTick = os.time()
        MarkWarehouseDirty(warehouseId)
        return
    end

    local multiplier = 1.0
    if not IsCrewOnline(state) then
        multiplier = Crypto.Clamp(Crypto.ToNumber(mining.OfflineMultiplier, 0.5), 0.0, 1.0)
    end

    -- Electricity is billed even when the rigs are stopped.
    if Config.Electricity.Enabled ~= false then
        local load = Crypto.GetPowerLoad(state.rigs, warehouseId)
        local cost = load * (elapsed / 3600.0) * Crypto.ToNumber(Config.Electricity.PricePerKwh, 0.85)

        if cost > 0 then
            state.billFraction = Crypto.ToNumber(state.billFraction, 0) + cost
            local whole = math.floor(state.billFraction)

            if whole > 0 then
                state.bill = state.bill + whole
                state.billFraction = state.billFraction - whole
                changed = true
            end
        end

        local maxDebt = Crypto.ToNumber(Config.Electricity.MaxDebt, 0)
        if maxDebt > 0 and state.bill >= maxDebt and state.powered then
            state.powered = false
            changed = true

            FW.NotifyIdentifier(state.owner, Crypto.L('power_cut', WH.GetLabel(warehouseId)), 'error')
            FW.Log('warehouse', 'Power cut', ('%s reached the maximum debt.'):format(WH.GetLabel(warehouseId)), {
                { name = 'Bill', value = Crypto.FormatMoney(state.bill) }
            })
        end
    end

    if state.powered then
        local storageLimit = Crypto.ToNumber(mining.StorageLimit, 0)
        local produced = 0.0

        for _, rig in pairs(state.rigs) do
            if not rig.broken and Crypto.ToInt(rig.gpus, 0) > 0 then
                local hashrate = Crypto.GetRigHashrate(rig)
                produced = produced + Crypto.GetProduction(hashrate, elapsed) * multiplier

                -- Wear
                local wear = Crypto.ToNumber(mining.Durability.LossPerTick, 0.35) * (elapsed / math.max(1, Crypto.ToNumber(mining.TickSeconds, 60)))
                local coolerLevel = Crypto.ToInt(rig.cooler, 0)
                wear = wear * math.max(0.0, 1.0 - coolerLevel * Crypto.ToNumber(mining.Cooler.Bonus, 0.25))

                if wear > 0 then
                    rig.durability = Crypto.Clamp(rig.durability - wear, 0.0, 100.0)
                    MarkRigDirty(rig)
                    changed = true
                end

                -- Disaster
                if mining.Disaster.Enabled ~= false then
                    local ticks = elapsed / math.max(1, Crypto.ToNumber(mining.TickSeconds, 60))
                    local chance = Crypto.ToNumber(mining.Disaster.Chance, 0.004)
                    local worn = (1.0 - (rig.durability / 100.0)) * Crypto.ToNumber(mining.Disaster.WornMultiplier, 2.0)
                    chance = chance * (1.0 + worn) * math.max(0.0, 1.0 - coolerLevel * Crypto.ToNumber(mining.Cooler.Bonus, 0.25))
                    chance = Crypto.Clamp(chance * ticks, 0.0, 0.75)

                    if math.random() < chance then
                        rig.broken = true

                        if math.random() < Crypto.ToNumber(mining.Disaster.GpuLossChance, 0.35) and rig.gpus > 0 then
                            rig.gpus = rig.gpus - 1
                        end

                        MarkRigDirty(rig)
                        changed = true

                        FW.NotifyIdentifier(state.owner, Crypto.L('rig_disaster', WH.GetLabel(warehouseId)), 'error')
                    end
                end
            end
        end

        if produced > 0 then
            local newBalance = state.btc + produced

            if storageLimit > 0 and newBalance > storageLimit then
                newBalance = storageLimit

                if state.btc < storageLimit then
                    FW.NotifyIdentifier(state.owner, Crypto.L('storage_full'), 'inform')
                end
            end

            if newBalance ~= state.btc then
                state.totalMined = state.totalMined + (newBalance - state.btc)
                state.btc = newBalance
                changed = true
            end
        end
    end

    state.lastTick = os.time()

    if changed then
        MarkWarehouseDirty(warehouseId)
        WH.Sync(warehouseId)
    else
        MarkWarehouseDirty(warehouseId)
    end
end

function WH.GetLabel(warehouseId)
    local warehouse = Crypto.GetWarehouseConfig(warehouseId)
    return warehouse and warehouse.label or warehouseId
end

function WH.StartLoop()
    CreateThread(function()
        local interval = math.max(10, Crypto.ToInt(Config.Mining.TickSeconds, 60))

        while true do
            Wait(interval * 1000)

            for warehouseId, state in pairs(WH.state) do
                if state.owner then
                    local elapsed = os.time() - Crypto.ToInt(state.lastTick, os.time())
                    if elapsed > 0 then
                        local ok, err = pcall(WH.Tick, warehouseId, elapsed)
                        if not ok then
                            print(('[%s] Tick failed for %s: %s'):format(RESOURCE, warehouseId, err))
                        end
                    end
                end
            end
        end
    end)

    CreateThread(function()
        local interval = math.max(15, Crypto.ToInt(Config.Database.SaveInterval, 60))

        while true do
            Wait(interval * 1000)
            local ok, err = pcall(WH.Flush)
            if not ok then
                print(('[%s] Flush failed: %s'):format(RESOURCE, err))
            end
        end
    end)
end

--- Applies the offline production accumulated while the resource was stopped.
function WH.CatchUp()
    local now = os.time()

    for warehouseId, state in pairs(WH.state) do
        if state.owner then
            local elapsed = now - Crypto.ToInt(state.lastTick, now)
            if elapsed > 0 then
                pcall(WH.Tick, warehouseId, elapsed)
            else
                state.lastTick = now
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- CLIENT SYNC
-- ---------------------------------------------------------------------------
--- Serialisable snapshot of a warehouse for the client / NUI.
function WH.Serialize(warehouseId, identifier)
    local state = WH.state[warehouseId]
    if not state then
        return nil
    end

    local warehouse = Crypto.GetWarehouseConfig(warehouseId)
    local rigs = {}

    for _, rig in pairs(state.rigs) do
        rigs[#rigs + 1] = {
            id = rig.id,
            slot = rig.slot,
            gpus = rig.gpus,
            cpu = rig.cpu,
            cooler = rig.cooler,
            durability = Crypto.Round(rig.durability, 1),
            broken = rig.broken and true or false,
            hashrate = Crypto.GetRigHashrate(rig)
        }
    end

    table.sort(rigs, function(a, b)
        return a.slot < b.slot
    end)

    local keys = {}
    for keyIdentifier, name in pairs(state.keys) do
        keys[#keys + 1] = { identifier = keyIdentifier, name = name }
    end

    table.sort(keys, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)

    local hashrate = Crypto.GetTotalHashrate(state.rigs)
    local price = Market.GetPrice()

    return {
        id = warehouseId,
        label = warehouse and warehouse.label or warehouseId,
        type = warehouse and warehouse.type or 'small',
        owner = state.owner,
        ownerName = state.ownerName,
        isOwner = identifier ~= nil and state.owner == identifier,
        btc = Crypto.Round(state.btc, 8),
        bill = math.floor(state.bill),
        powered = state.powered and true or false,
        locked = state.locked and true or false,
        rigs = rigs,
        keys = keys,
        maxRigs = Crypto.GetMaxRigs(warehouseId),
        maxGpus = Crypto.GetMaxGpus(),
        hashrate = hashrate,
        perHour = Crypto.Round(Crypto.GetProduction(hashrate, 3600), 8),
        load = Crypto.GetPowerLoad(state.rigs, warehouseId),
        value = Crypto.GetSellValue(state.btc, price),
        totalMined = Crypto.Round(state.totalMined, 6),
        totalEarned = math.floor(state.totalEarned),
        storageLimit = Crypto.ToNumber(Config.Mining.StorageLimit, 0),
        gpuStock = math.max(0, Crypto.ToInt(state.gpuStock, 0)),
        prices = {
            rig = Crypto.ToInt(Config.Mining.RigPrice, 9000),
            cpu = Crypto.ToInt(Config.Mining.Cpu.Price, 4500),
            cooler = Crypto.ToInt(Config.Mining.Cooler.Price, 3800)
        },
        market = Market.GetState()
    }
end

--- Pushes a fresh snapshot to everyone currently inside the warehouse.
function WH.Sync(warehouseId)
    local viewers = WH.viewers and WH.viewers[warehouseId]
    if not viewers then
        return
    end

    for source in pairs(viewers) do
        local identifier = FW.GetIdentifier(source)
        local payload = WH.Serialize(warehouseId, identifier)

        if payload then
            TriggerClientEvent(RESOURCE .. ':warehouseUpdate', source, payload)
        end
    end
end

WH.viewers = {}

function WH.AddViewer(warehouseId, source)
    -- Assigning a nil table index raises a hard Lua error, so both values are
    -- validated before touching the table.
    if warehouseId == nil or source == nil then
        return
    end

    WH.viewers[warehouseId] = WH.viewers[warehouseId] or {}
    WH.viewers[warehouseId][source] = true
end

function WH.RemoveViewer(source)
    if source == nil then
        return
    end

    for _, viewers in pairs(WH.viewers) do
        viewers[source] = nil
    end
end

-- ---------------------------------------------------------------------------
-- ROUTING BUCKETS
-- ---------------------------------------------------------------------------
-- Several warehouses share the same base game interior. Without a dedicated
-- bucket, two owners standing in "their" warehouse would see each other and
-- each other's rig props. Every warehouse therefore gets a stable bucket id.
local bucketByWarehouse = nil

function WH.GetBucket(warehouseId)
    if not bucketByWarehouse then
        bucketByWarehouse = {}
        local base = Crypto.ToInt(Config.Routing and Config.Routing.BaseBucket, 4100)

        for index, warehouse in ipairs(Config.Warehouses or {}) do
            bucketByWarehouse[warehouse.id] = base + index
        end
    end

    return bucketByWarehouse[warehouseId]
end

--- Moves a player into the bucket of a warehouse, or back to the main world.
function WH.SetPlayerBucket(source, warehouseId)
    if not Config.Routing or Config.Routing.Enabled == false then
        return
    end

    source = tonumber(source)

    if not source or source <= 0 then
        return
    end

    local bucket = warehouseId and WH.GetBucket(warehouseId) or 0

    if not bucket then
        bucket = 0
    end

    local ok, err = pcall(function()
        SetPlayerRoutingBucket(source, bucket)

        if bucket ~= 0 then
            SetRoutingBucketEntityLockdownMode(bucket, Crypto.ToInt(Config.Routing.LockdownMode, 1) == 0 and 'strict' or 'relaxed')
            SetRoutingBucketPopulationEnabled(bucket, false)
        end
    end)

    if not ok then
        print(('[%s] Routing bucket failed: %s'):format(RESOURCE, err))
    end
end
