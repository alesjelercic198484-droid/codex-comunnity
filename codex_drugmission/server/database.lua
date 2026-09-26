local RESOURCE = GetCurrentResourceName()
local path = 'data/missions.json'

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

local function validNumber(v) return type(v) == 'number' and v == v and math.abs(v) < 1000000 end
local function validCoords(c, headingRequired)
    return type(c) == 'table' and validNumber(c.x) and validNumber(c.y) and validNumber(c.z)
        and (not headingRequired or validNumber(c.w or c.heading))
end

function LoadMissions()
    local raw = LoadResourceFile(RESOURCE, path)
    local decoded = raw and json.decode(raw) or nil
    if decoded and type(decoded.missions) == 'table' and #decoded.missions > 0 then return decoded.missions end
    return { copy(Config.DefaultMission) }
end

function SaveMissions(missions)
    return SaveResourceFile(RESOURCE, path, json.encode({ missions = missions }), -1)
end

function SanitizeMission(input)
    if type(input) ~= 'table' then return nil, 'Invalid mission' end
    local id = tostring(input.id or ''):lower():gsub('[^%w_-]', ''):sub(1, 40)
    if id == '' or #id < 2 then return nil, 'Mission ID is required' end
    if not validCoords(input.npc and input.npc.coords, true) or not validCoords(input.vehicleSpawn, true)
        or not validCoords(input.destination, false) or not validCoords(input.rewardNpc and input.rewardNpc.coords, true) then
        return nil, 'All locations must be set' end
    local function model(v, fallback) return tostring(v or fallback):lower():gsub('[^%w_]', ''):sub(1, 32) end
    local m = {
        id = id, name = tostring(input.name or id):sub(1, 80),
        npc = { model = model(input.npc.model, 'g_m_m_mexboss_01'), coords = input.npc.coords },
        vehicleSpawn = input.vehicleSpawn, destination = input.destination,
        rewardNpc = { model = model(input.rewardNpc.model, 'g_m_m_mexboss_01'), coords = input.rewardNpc.coords },
        vehicle = { model = model(input.vehicle and input.vehicle.model, 'speedo'), color = input.vehicle and input.vehicle.color or { 20, 20, 20 }, warpInto = input.vehicle and input.vehicle.warpInto ~= false },
        enemyWaves = {}, rewards = {}
    }
    for _, reward in ipairs(input.rewards or {}) do
        local amount = math.floor(tonumber(reward.amount) or 0)
        local typ = tostring(reward.type or ''):lower()
        if amount > 0 and amount <= 100000000 and (typ == 'item' or typ == 'cash' or typ == 'bank' or typ == 'black_money') then
            m.rewards[#m.rewards + 1] = { type = typ, name = tostring(reward.name or ''):sub(1, 50), amount = amount }
        end
    end
    for i = 1, 4 do
        local w = input.enemyWaves and input.enemyWaves[i]
        if w then
            local vehicles = {}
            for _, vehicle in ipairs(w.vehicles or {}) do vehicles[#vehicles + 1] = model(vehicle, 'granger') end
            if #vehicles > 0 then
                m.enemyWaves[#m.enemyWaves + 1] = { vehicles = vehicles, weapon = model(w.weapon, 'WEAPON_MICROSMG'), ped = model(w.ped, 'g_m_y_mexgoon_02'), count = math.min(4, math.max(1, math.floor(tonumber(w.count) or 4))), spawnDistance = math.min(300, math.max(40, tonumber(w.spawnDistance) or 90)) }
            end
        end
    end
    if #m.enemyWaves == 0 then return nil, 'At least one enemy wave is required' end
    if #m.rewards == 0 then return nil, 'At least one reward is required' end
    return m
end
