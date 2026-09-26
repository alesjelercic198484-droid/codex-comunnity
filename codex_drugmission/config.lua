Config = {}

Config.Debug = false
Config.AdminGroups = { admin = true, superadmin = true }
Config.AdminAce = 'codex.drugmission'
Config.DistanceToStart = 8.0
Config.LeaveVehicleSeconds = 120
Config.FirstWaveDelay = 20
Config.SecondWaveDelay = 180
Config.EnemyCleanupDistance = 700.0
Config.Blips = { destination = true, missionVehicle = true, enemies = false }
Config.HurrySound = 'hurry.ogg'
Config.Text = {
    start = 'A si to ti? Govorili so, da boš prišel... ali si zbral pogum?',
    brave = 'Jaz ne potrebujem poguma, imam na sebi vse kar potrebujem.',
    question = 'A tako... ne potrebuješ poguma?',
    challenge = 'To bomo pa še videli.',
    decline = 'Sem vedel, da nisi za to.',
    loaded = 'V njem je polno droge. Upam, da ostaneš živ.',
    success = 'MISIJA JE BILA USPEŠNA!',
    dead = 'Misija neuspešna – umrl si.',
    hurry = 'Gremo hitro, če ne smo mrtvi.',
    final = 'Gospod... to je za vas.'
}
Config.DefaultMission = {
    id = 'dock_drug_run', name = 'Dock Drug Run',
    npc = { model = 'g_m_m_mexboss_01', coords = { x = 120.0, y = -3125.0, z = 5.5, w = 90.0 } },
    vehicleSpawn = { x = 108.0, y = -3120.0, z = 5.9, w = 90.0 },
    destination = { x = 1725.0, y = 3290.0, z = 41.2 },
    rewardNpc = { model = 'g_m_m_mexboss_01', coords = { x = 1728.0, y = 3294.0, z = 41.2, w = 180.0 } },
    vehicle = { model = 'speedo', color = { 20, 20, 20 }, warpInto = true },
    enemyWaves = {
        { vehicles = { 'granger', 'granger' }, weapon = 'WEAPON_MICROSMG', ped = 'g_m_y_mexgoon_02', count = 4, spawnDistance = 90.0 },
        { vehicles = { 'schafter2', 'schafter2' }, weapon = 'WEAPON_MICROSMG', ped = 'g_m_y_mexgoon_01', count = 4, spawnDistance = 110.0 }
    },
    rewards = { { type = 'item', name = 'black_money', amount = 50000 } }
}
