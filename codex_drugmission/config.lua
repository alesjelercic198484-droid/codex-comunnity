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
Config.HurrySound = 'hurry.mp3'
Config.Text = {
    start = 'Is that you? They said you would come... have you got the courage?',
    brave = 'I do not need courage. I have everything I need on me.',
    question = 'Oh, really... you do not need courage?',
    challenge = 'We will see about that.',
    decline = 'I knew you were not ready for this.',
    loaded = 'It is packed with drugs. I hope you stay alive.',
    success = 'MISSION SUCCESSFUL!',
    dead = 'Mission failed – you died.',
    hurry = 'Move quickly, or we are dead.',
    final = 'Sir... this is for you.'
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
