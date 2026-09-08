--[[ OQV2 QUESTS — HUD mission tracker feed | Made with CodeX Dev. ]]

local lastPayload = ''

local function buildTracker()
    local active = OQ.State.active
    local p = OQ.State.player or {}

    if not active then
        return { visible = false, player = { level = p.level or 1, percent = p.percent or 0, xp = p.xp or 0, need = p.need or 0 } }
    end

    local objectives = {}
    for _, obj in ipairs(active.objectives or {}) do
        objectives[#objectives + 1] = {
            id       = obj.id,
            label    = obj.label,
            type     = obj.type,
            done     = obj.done and true or false,
            have     = obj.have or 0,
            need     = obj.need or 1,
            optional = obj.optional and true or false,
        }
    end

    return {
        visible = true,
        mission = {
            uid        = active.uid,
            name       = active.name,
            icon       = active.icon or 'scroll',
            objectives = objectives,
        },
        player = {
            level   = p.level or 1,
            percent = p.percent or 0,
            xp      = p.xp or 0,
            need    = p.need or 0,
        },
    }
end

function OQ.Client.pushTracker(force)
    local data = buildTracker()
    local encoded = OQ.encode(data)
    if not force and encoded == lastPayload then return end
    lastPayload = encoded
    SendNUIMessage({ action = 'tracker', data = data })
end

AddEventHandler('oqv2:client:trackerUpdate', function()
    OQ.Client.pushTracker(true)
end)

AddEventHandler('oqv2:client:playerUpdated', function()
    OQ.Client.pushTracker(false)
end)

-- periodic refresh keeps the HUD in sync after a UI reload / resource restart
CreateThread(function()
    while true do
        Wait(5000)
        if OQ.State.ready then
            OQ.Client.pushTracker(false)
        end
    end
end)

-- hide the tracker while the big NUI is open or the player is dead
CreateThread(function()
    local hidden = false
    while true do
        Wait(750)
        local shouldHide = OQ.State.nuiOpen or IsPedDeadOrDying(PlayerPedId(), true) or IsPauseMenuActive()
        if shouldHide ~= hidden then
            hidden = shouldHide
            SendNUIMessage({ action = 'trackerVisibility', data = { hidden = hidden } })
        end
    end
end)
