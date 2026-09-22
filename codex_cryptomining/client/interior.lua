--[[
    Interior & prop manager.
    Loads the IPLs (or nothing at all for an MLO), spawns every prop of the
    warehouse and keeps them in sync with the server state.
    All entities are tracked so nothing is ever left behind.
]]

CodexCryptoInterior = CodexCryptoInterior or {}

local Interior = CodexCryptoInterior
local Crypto = CodexCrypto
local RESOURCE = GetCurrentResourceName()

Interior.current = nil      -- warehouse id the player is inside
Interior.data = nil         -- last serialized warehouse
Interior.entities = {}      -- every spawned entity
Interior.rigEntities = {}   -- rigId -> { chassis, gpus = {}, cooler }
Interior.targetHandles = {} -- target ids to clean up
Interior.loadedIpls = {}

local function LoadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return nil
    end

    RequestModel(hash)

    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(10)
    end

    if not HasModelLoaded(hash) then
        return nil
    end

    return hash
end

Interior.LoadModel = LoadModel

--- Creates a prop and registers it for cleanup. Returns nil on failure.
local function SpawnProp(model, coords, heading, fallback)
    local hash = LoadModel(model)

    if not hash and fallback then
        hash = LoadModel(fallback)
    end

    if not hash then
        Crypto.DebugPrint(('Model not available: %s'):format(tostring(model)))
        return nil
    end

    local object = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)

    if not object or object == 0 or not DoesEntityExist(object) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    SetEntityHeading(object, heading or 0.0)
    FreezeEntityPosition(object, true)
    SetEntityInvincible(object, true)
    SetEntityAsMissionEntity(object, true, true)
    SetModelAsNoLongerNeeded(hash)

    Interior.entities[#Interior.entities + 1] = object

    return object
end

Interior.SpawnProp = SpawnProp

local function DeleteEntitySafe(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

-- ---------------------------------------------------------------------------
-- IPL
-- ---------------------------------------------------------------------------
function Interior.LoadIpls(interiorConfig)
    if not interiorConfig or interiorConfig.mlo == true then
        return
    end

    for _, ipl in ipairs(interiorConfig.ipls or {}) do
        if not IsIplActive(ipl) then
            RequestIpl(ipl)
            Interior.loadedIpls[ipl] = true

            -- Wait for the shell to actually come online. The base game
            -- Import/Export warehouse only becomes solid once the IPL is
            -- active, otherwise the player would drop through the floor.
            local timeout = GetGameTimer() + 3000
            while not IsIplActive(ipl) and GetGameTimer() < timeout do
                Wait(10)
            end
        end
    end

    -- Refresh the interior instance at the entrance so its rooms / portals are
    -- rebuilt. Without this the interior can render as an empty void the first
    -- time a player enters after the IPL was requested.
    local enter = interiorConfig.enter
    if enter then
        local interiorId = GetInteriorAtCoords(enter.x, enter.y, enter.z)
        if interiorId and interiorId ~= 0 then
            RefreshInterior(interiorId)
        end
    end
end

function Interior.UnloadIpls()
    -- IPLs are shared with the rest of the map, only remove the ones we
    -- explicitly requested and only when no other warehouse needs them.
    for ipl in pairs(Interior.loadedIpls) do
        if IsIplActive(ipl) then
            RemoveIpl(ipl)
        end
    end

    Interior.loadedIpls = {}
end

-- ---------------------------------------------------------------------------
-- SLOTS
-- ---------------------------------------------------------------------------
function Interior.GetSlotCoords(warehouseType, slot)
    local interiorConfig = Crypto.GetInteriorConfig(warehouseType)
    if not interiorConfig then
        return nil
    end

    local slots = interiorConfig.slots or {}
    local entry = slots[slot]

    if not entry then
        return nil
    end

    return entry
end

-- ---------------------------------------------------------------------------
-- RIG PROPS
-- ---------------------------------------------------------------------------
local function ClearRigEntities(rigId)
    local bundle = Interior.rigEntities[rigId]
    if not bundle then
        return
    end

    DeleteEntitySafe(bundle.chassis)
    DeleteEntitySafe(bundle.base)
    DeleteEntitySafe(bundle.cooler)

    for _, gpu in ipairs(bundle.gpus or {}) do
        DeleteEntitySafe(gpu)
    end

    if bundle.particle then
        StopParticleFxLooped(bundle.particle, false)
    end

    Interior.rigEntities[rigId] = nil
end

Interior.ClearRigEntities = ClearRigEntities

local function StartBrokenEffect(entity)
    if not Config.Props.BrokenEffect or not entity or not DoesEntityExist(entity) then
        return nil
    end

    local dict = 'core'
    RequestNamedPtfxAsset(dict)

    local timeout = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(dict) and GetGameTimer() < timeout do
        Wait(10)
    end

    if not HasNamedPtfxAssetLoaded(dict) then
        return nil
    end

    UseParticleFxAssetNextCall(dict)

    return StartParticleFxLoopedOnEntity('ent_amb_smoke_factory', entity, 0.0, 0.0, 0.4, 0.0, 0.0, 0.0, 0.35, false, false, false)
end

--- Spawns (or refreshes) every prop of a single rig.
function Interior.BuildRig(warehouseType, rig)
    if not rig or not rig.id then
        return
    end

    ClearRigEntities(rig.id)

    local slot = Interior.GetSlotCoords(warehouseType, Crypto.ToInt(rig.slot, 0))
    if not slot then
        Crypto.DebugPrint(('No slot coordinates for slot %s'):format(tostring(rig.slot)))
        return
    end

    local propConfig = Config.Props or {}
    local rigConfig = propConfig.Rig or {}
    local bundle = { gpus = {} }

    if rigConfig.base and rigConfig.base.enabled then
        bundle.base = SpawnProp(rigConfig.base.model, {
            x = slot.x,
            y = slot.y,
            z = slot.z + Crypto.ToNumber(rigConfig.base.zOffset, 0)
        }, slot.w, propConfig.Fallback)
    end

    -- A broken rig uses the damaged variant when one is configured.
    local chassisModel = rigConfig.model

    if rig.broken and propConfig.BrokenModel then
        chassisModel = propConfig.BrokenModel
    end

    bundle.chassis = SpawnProp(chassisModel, {
        x = slot.x,
        y = slot.y,
        z = slot.z + Crypto.ToNumber(rigConfig.zOffset, 0)
    }, slot.w, rigConfig.model or propConfig.Fallback)

    if not bundle.chassis then
        Interior.rigEntities[rig.id] = bundle
        return
    end

    -- GPUs stacked on top of the chassis.
    local gpuConfig = propConfig.Gpu or {}
    if gpuConfig.enabled and Crypto.ToInt(rig.gpus, 0) > 0 then
        local count = math.min(Crypto.ToInt(rig.gpus, 0), math.max(1, Crypto.ToInt(gpuConfig.maxVisual, 8)))
        local startOffset = gpuConfig.startOffset or vector3(0.0, 0.0, 0.6)
        local perGpu = gpuConfig.perGpuOffset or vector3(0.0, 0.0, 0.1)

        for index = 1, count do
            local offsetX = startOffset.x + perGpu.x * (index - 1)
            local offsetY = startOffset.y + perGpu.y * (index - 1)
            local offsetZ = startOffset.z + perGpu.z * (index - 1)

            local position = GetOffsetFromEntityInWorldCoords(bundle.chassis, offsetX, offsetY, offsetZ)
            local gpu = SpawnProp(gpuConfig.model, position, slot.w, propConfig.Fallback)

            if gpu then
                bundle.gpus[#bundle.gpus + 1] = gpu
            end
        end
    end

    -- Cooler prop when the upgrade is installed.
    local coolerConfig = propConfig.Cooler or {}
    if coolerConfig.enabled and Crypto.ToInt(rig.cooler, 0) > 0 then
        local offset = coolerConfig.offset or vector3(0.0, -0.4, 0.0)
        local position = GetOffsetFromEntityInWorldCoords(bundle.chassis, offset.x, offset.y, offset.z)
        bundle.cooler = SpawnProp(coolerConfig.model, position, slot.w, propConfig.Fallback)
    end

    if rig.broken then
        bundle.particle = StartBrokenEffect(bundle.chassis)
    end

    Interior.rigEntities[rig.id] = bundle
end

-- ---------------------------------------------------------------------------
-- STATIC PROPS
-- ---------------------------------------------------------------------------
function Interior.BuildStatic(interiorConfig)
    local propConfig = Config.Props or {}

    local function place(definition, coords)
        if not definition or not definition.enabled or not coords then
            return nil
        end

        return SpawnProp(definition.model, {
            x = coords.x,
            y = coords.y,
            z = coords.z + Crypto.ToNumber(definition.zOffset, 0)
        }, coords.w, propConfig.Fallback)
    end

    Interior.terminalProp = place(propConfig.Terminal, interiorConfig.terminal)
    Interior.powerProp = place(propConfig.PowerBox, interiorConfig.power)
    Interior.storageProp = place(propConfig.Storage, interiorConfig.storage)
end

-- ---------------------------------------------------------------------------
-- BUILD / CLEAR
-- ---------------------------------------------------------------------------
function Interior.Build(warehouseData)
    if not warehouseData then
        return
    end

    Interior.Clear(true)

    Interior.current = warehouseData.id
    Interior.data = warehouseData

    local interiorConfig = Crypto.GetInteriorConfig(warehouseData.type)
    if not interiorConfig then
        return
    end

    Interior.LoadIpls(interiorConfig)
    Interior.BuildStatic(interiorConfig)

    for _, rig in ipairs(warehouseData.rigs or {}) do
        Interior.BuildRig(warehouseData.type, rig)
    end
end

--- Rebuilds only what changed between two snapshots.
function Interior.Refresh(warehouseData)
    if not warehouseData or Interior.current ~= warehouseData.id then
        return
    end

    local previous = {}
    for _, rig in ipairs((Interior.data and Interior.data.rigs) or {}) do
        previous[rig.id] = rig
    end

    local seen = {}

    for _, rig in ipairs(warehouseData.rigs or {}) do
        seen[rig.id] = true
        local old = previous[rig.id]

        local changed = not old
            or old.gpus ~= rig.gpus
            or old.cooler ~= rig.cooler
            or old.broken ~= rig.broken
            or old.slot ~= rig.slot

        if changed then
            Interior.BuildRig(warehouseData.type, rig)
        end
    end

    -- Rigs that no longer exist.
    for rigId in pairs(previous) do
        if not seen[rigId] then
            ClearRigEntities(rigId)
        end
    end

    Interior.data = warehouseData
end

function Interior.Clear(keepIpls)
    for rigId in pairs(Interior.rigEntities) do
        ClearRigEntities(rigId)
    end

    Interior.rigEntities = {}

    for _, entity in ipairs(Interior.entities) do
        DeleteEntitySafe(entity)
    end

    Interior.entities = {}
    Interior.terminalProp = nil
    Interior.powerProp = nil
    Interior.storageProp = nil

    if not keepIpls then
        Interior.UnloadIpls()
        Interior.current = nil
        Interior.data = nil
    end
end

function Interior.IsInside()
    return Interior.current ~= nil
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE then
        Interior.Clear(false)
    end
end)
