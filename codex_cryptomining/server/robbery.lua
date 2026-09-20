--[[
    Robbery / heist manager.
    Several robberies can run at the same time. Every loot action is checked
    server side: access, distance, state of the rig, tools and cooldowns.
]]

CodexCryptoRob = CodexCryptoRob or {}

local Rob = CodexCryptoRob
local Crypto = CodexCrypto
local FW = CodexCryptoFW
local WH = CodexCryptoWH
local RESOURCE = GetCurrentResourceName()

-- warehouseId -> { source, identifier, startedAt, looted = { [rigId] = true } }
Rob.active = {}
-- identifier -> timestamp
Rob.cooldowns = {}

function Rob.CountActive()
    return Crypto.TableCount(Rob.active)
end

function Rob.IsActive(warehouseId)
    return Rob.active[warehouseId] ~= nil
end

function Rob.GetBySource(source)
    for warehouseId, robbery in pairs(Rob.active) do
        if robbery.source == source then
            return warehouseId, robbery
        end
    end
    return nil, nil
end

local function Finish(warehouseId, reason)
    local robbery = Rob.active[warehouseId]
    if not robbery then
        return
    end

    Rob.active[warehouseId] = nil

    local state = WH.Get(warehouseId)
    if state then
        state.robbedAt = os.time()
        WH.MarkWarehouseDirty(warehouseId)
    end

    if robbery.source and GetPlayerName(robbery.source) then
        TriggerClientEvent(RESOURCE .. ':robberyEnded', robbery.source, warehouseId, reason)
    end

    Crypto.DebugPrint(('Robbery on %s ended (%s).'):format(warehouseId, reason or 'done'))
end

Rob.Finish = Finish

--- Validates that a player may start a robbery, without consuming anything.
function Rob.CanStart(source, warehouseId)
    if Config.Robbery.Enabled == false then
        return false, Crypto.L('invalid_action')
    end

    local identifier = FW.GetIdentifier(source)
    local state = WH.Get(warehouseId)
    local warehouse = Crypto.GetWarehouseConfig(warehouseId)

    if not identifier or not state or not warehouse then
        return false, Crypto.L('invalid_action')
    end

    if not state.owner then
        return false, Crypto.L('robbery_empty')
    end

    if WH.HasAccess(identifier, warehouseId) then
        return false, Crypto.L('robbery_own')
    end

    if Rob.IsActive(warehouseId) then
        return false, Crypto.L('robbery_busy')
    end

    local maxSimultaneous = math.max(1, Crypto.ToInt(Config.Robbery.MaxSimultaneous, 2))
    if Rob.CountActive() >= maxSimultaneous then
        return false, Crypto.L('robbery_busy')
    end

    local now = os.time()
    local readyAt = Rob.cooldowns[identifier] or 0

    if now < readyAt then
        return false, Crypto.L('robbery_cooldown', math.ceil((readyAt - now) / 60))
    end

    local warehouseCooldown = math.max(0, Crypto.ToInt(Config.Robbery.WarehouseCooldown, 3600))
    if warehouseCooldown > 0 and (now - Crypto.ToInt(state.robbedAt, 0)) < warehouseCooldown then
        return false, Crypto.L('robbery_warehouse_cooldown')
    end

    if WH.CountGpus(warehouseId) < math.max(1, Crypto.ToInt(Config.Robbery.MinGpus, 4)) then
        return false, Crypto.L('robbery_empty')
    end

    if FW.CountPolice() < Crypto.ToInt(Config.Robbery.MinPolice, 0) then
        return false, Crypto.L('robbery_police')
    end

    if Config.Robbery.RequireLockpick and FW.GetItemCount(source, 'lockpick') < 1 then
        return false, Crypto.L('robbery_need_lockpick')
    end

    if Config.Robbery.RequireUsb and FW.GetItemCount(source, 'usb') < 1 then
        return false, Crypto.L('robbery_need_usb')
    end

    -- The player must physically stand at the entrance.
    if not FW.IsNear(source, warehouse.entrance, 8.0) then
        return false, Crypto.L('too_far')
    end

    return true, nil
end

--- Called after the client succeeded the door minigame.
function Rob.Start(source, warehouseId)
    local ok, reason = Rob.CanStart(source, warehouseId)
    if not ok then
        return false, reason
    end

    local identifier = FW.GetIdentifier(source)
    local warehouse = Crypto.GetWarehouseConfig(warehouseId)
    local state = WH.Get(warehouseId)

    if Config.Robbery.RequireLockpick and Config.Robbery.ConsumeLockpick then
        if not FW.RemoveItem(source, 'lockpick', 1) then
            return false, Crypto.L('robbery_need_lockpick')
        end
    end

    if Config.Robbery.RequireUsb and Config.Robbery.ConsumeUsb then
        if not FW.RemoveItem(source, 'usb', 1) then
            return false, Crypto.L('robbery_need_usb')
        end
    end

    Rob.active[warehouseId] = {
        source = source,
        identifier = identifier,
        startedAt = os.time(),
        looted = {}
    }

    Rob.cooldowns[identifier] = os.time() + math.max(0, Crypto.ToInt(Config.Robbery.PlayerCooldown, 1800))

    if Config.Robbery.NotifyOwner and state.owner then
        FW.NotifyIdentifier(state.owner, Crypto.L('robbery_owner_alert', warehouse.label), 'error')
    end

    if Config.Robbery.Dispatch then
        FW.Dispatch(warehouse.entrance, warehouse.label)
    end

    FW.Log('robbery', 'Robbery started', ('%s broke into %s'):format(FW.GetName(source), warehouse.label), {
        { name = 'Owner', value = tostring(state.ownerName or state.owner) },
        { name = 'GPUs inside', value = tostring(WH.CountGpus(warehouseId)) }
    })

    -- Automatic timeout.
    local timeout = math.max(60, Crypto.ToInt(Config.Robbery.Timeout, 900))
    local startedAt = Rob.active[warehouseId].startedAt

    CreateThread(function()
        Wait(timeout * 1000)

        local robbery = Rob.active[warehouseId]
        if robbery and robbery.startedAt == startedAt then
            Finish(warehouseId, 'timeout')
        end
    end)

    return true, Crypto.L('robbery_started')
end

--- Loots a single rig.
function Rob.LootRig(source, warehouseId, rigId)
    local robbery = Rob.active[warehouseId]

    if not robbery or robbery.source ~= source then
        return false, Crypto.L('invalid_action')
    end

    rigId = Crypto.ToInt(rigId, 0)

    if robbery.looted[rigId] then
        return false, Crypto.L('robbery_nothing_left')
    end

    local state = WH.Get(warehouseId)
    local rig = state and state.rigs[rigId]

    if not rig then
        return false, Crypto.L('rig_not_found')
    end

    local available = Crypto.ToInt(rig.gpus, 0)
    if available <= 0 then
        robbery.looted[rigId] = true
        return false, Crypto.L('robbery_nothing_left')
    end

    local ratio = Crypto.Clamp(Crypto.ToNumber(Config.Robbery.LootRatio, 1.0), 0.1, 1.0)
    local amount = math.max(1, math.floor(available * ratio + 0.5))
    amount = math.min(amount, available)

    if not FW.CanCarry(source, 'gpu', amount) then
        return false, Crypto.L('no_space')
    end

    rig.gpus = available - amount
    robbery.looted[rigId] = true
    WH.MarkRigDirty(rig)
    WH.MarkWarehouseDirty(warehouseId)

    if not FW.AddItem(source, 'gpu', amount) then
        -- Roll back so nothing disappears into thin air.
        rig.gpus = available
        robbery.looted[rigId] = nil
        WH.MarkRigDirty(rig)
        return false, Crypto.L('failed')
    end

    WH.Sync(warehouseId)

    FW.Log('robbery', 'Rig looted', ('%s stole %sx GPU'):format(FW.GetName(source), amount), {
        { name = 'Warehouse', value = WH.GetLabel(warehouseId) },
        { name = 'Rig', value = tostring(rigId) }
    })

    -- Every rig emptied: the job is over.
    if WH.CountGpus(warehouseId) <= 0 then
        Finish(warehouseId, 'cleared')
    end

    return true, Crypto.L('robbery_looted', amount)
end

function Rob.Cancel(source)
    local warehouseId = Rob.GetBySource(source)
    if warehouseId then
        Finish(warehouseId, 'cancelled')
    end
end

function Rob.OnPlayerDropped(source)
    Rob.Cancel(source)
end

--- Rigs a client may loot, used to build the target list inside the interior.
function Rob.GetLootableRigs(source, warehouseId)
    local robbery = Rob.active[warehouseId]
    if not robbery or robbery.source ~= source then
        return {}
    end

    local state = WH.Get(warehouseId)
    if not state then
        return {}
    end

    local list = {}
    for _, rig in pairs(state.rigs) do
        list[#list + 1] = {
            id = rig.id,
            slot = rig.slot,
            gpus = rig.gpus,
            cpu = rig.cpu,
            cooler = rig.cooler,
            durability = Crypto.Round(rig.durability, 1),
            broken = rig.broken and true or false,
            looted = robbery.looted[rig.id] and true or false
        }
    end

    table.sort(list, function(a, b)
        return a.slot < b.slot
    end)

    return list
end
