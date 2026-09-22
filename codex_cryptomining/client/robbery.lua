--[[
    Client side of the robbery: minigames and loot interaction.
    The client never decides the outcome, it only reports the result of the
    minigame and asks the server to loot a rig.
]]

CodexCryptoRobClient = CodexCryptoRobClient or {}

local RobClient = CodexCryptoRobClient
local Crypto = CodexCrypto

RobClient.active = nil
RobClient.looted = {}

local function IsStarted(resourceName)
    return GetResourceState(resourceName) == 'started'
end

--- Runs the configured lockpick / hacking minigame. Returns a boolean.
function RobClient.PlayMinigame(kind)
    local settings = Config.Robbery.Minigames or {}
    local mode = kind == 'door' and (settings.Door or 'builtin') or (settings.Rig or 'builtin')

    if mode == 'none' then
        return true
    end

    local difficulty = settings.Difficulty or { 'easy' }

    -- Built-in skillcheck: our own NUI minigame, zero dependency (default).
    if mode == 'builtin' then
        if type(CodexCryptoSkillcheck) == 'function' then
            local title = kind == 'door' and Crypto.L('skillcheck_door') or Crypto.L('skillcheck_rig')
            local ok, result = pcall(CodexCryptoSkillcheck, difficulty, title)
            return ok and result == true
        end

        -- Should never happen (main.lua defines it), but stay non-blocking.
        return true
    end

    if mode == 'ox_skillcheck' and IsStarted('ox_lib') then
        local ok, result = pcall(function()
            return lib.skillCheck(difficulty, { 'w', 'a', 's', 'd' })
        end)
        return ok and result == true
    end

    if mode == 'lockpick' and IsStarted('t3_lockpick') then
        local ok, result = pcall(function()
            return exports['t3_lockpick']:startLockpick(4, 3)
        end)
        return ok and result == true
    end

    if mode == 'lockpick' and IsStarted('qb-lockpick') then
        local promiseObject = promise.new()

        TriggerEvent('qb-lockpick:client:openLockpick', function(success)
            promiseObject:resolve(success == true)
        end)

        return Citizen.Await(promiseObject) == true
    end

    if mode == 'hack' and IsStarted('howdy-hackminigame') then
        local ok, result = pcall(function()
            return exports['howdy-hackminigame']:Begin(6, 20)
        end)
        return ok and result == true
    end

    if mode == 'hack' and IsStarted('memorygame') then
        local promiseObject = promise.new()

        exports['memorygame']:thermiteminigame(10, 5, 10, 3, function()
            promiseObject:resolve(true)
        end, function()
            promiseObject:resolve(false)
        end)

        return Citizen.Await(promiseObject) == true
    end

    -- Configured resource missing: fall back to the built-in skillcheck so the
    -- robbery still has a challenge without pulling in any dependency.
    if type(CodexCryptoSkillcheck) == 'function' then
        local title = kind == 'door' and Crypto.L('skillcheck_door') or Crypto.L('skillcheck_rig')
        local ok, result = pcall(CodexCryptoSkillcheck, difficulty, title)
        return ok and result == true
    end

    -- Absolutely nothing available: do not block the player.
    Crypto.DebugPrint(('Minigame "%s" is not available, skipping.'):format(tostring(mode)))
    return true
end

function RobClient.Start(warehouseId)
    RobClient.active = warehouseId
    RobClient.looted = {}
end

function RobClient.Stop()
    RobClient.active = nil
    RobClient.looted = {}
end

function RobClient.IsActive(warehouseId)
    if not RobClient.active then
        return false
    end

    if warehouseId then
        return RobClient.active == warehouseId
    end

    return true
end

function RobClient.MarkLooted(rigId)
    RobClient.looted[rigId] = true
end

function RobClient.IsLooted(rigId)
    return RobClient.looted[rigId] == true
end
