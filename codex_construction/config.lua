Config = {}
Config.Debug = false
Config.Framework = 'es_extended'
Config.MaxPlayers = 4
Config.JobDuration = 600 -- seconds (10 minutes)
Config.Payout = 12000
Config.Account = 'bank'
Config.RequireItem = 'construction_tools'
Config.ConsumeItem = true
Config.TaskCount = 8
Config.TaskReward = 1
Config.InteractionDistance = 2.2
Config.Foreman = {
    model = 's_m_y_construct_01',
    coords = vec4(-509.42, -1001.61, 23.55, 89.0),
    label = 'Open construction tablet'
}

-- Replace these coordinates with your construction site if desired.
Config.Tasks = {
    { label = 'Secure the steel beam', model = 'prop_beam_01', coords = vec4(-499.83, -1005.66, 24.30, 0.0), scenario = 'WORLD_HUMAN_HAMMERING' },
    { label = 'Inspect the concrete mixer', model = 'prop_cementmixer01a', coords = vec4(-504.85, -1007.14, 23.55, 180.0), scenario = 'WORLD_HUMAN_WELDING' },
    { label = 'Install a support barrier', model = 'prop_barrier_work05', coords = vec4(-514.29, -1005.77, 23.55, 90.0), scenario = 'WORLD_HUMAN_HAMMERING' },
    { label = 'Mark the foundation', model = 'prop_tool_box_04', coords = vec4(-518.18, -1000.63, 23.55, 0.0), scenario = 'WORLD_HUMAN_HAMMERING' },
    { label = 'Check the scaffolding', model = 'prop_scafold_01a', coords = vec4(-513.45, -996.88, 23.55, 270.0), scenario = 'WORLD_HUMAN_WELDING' },
    { label = 'Repair the generator', model = 'prop_generator_03b', coords = vec4(-505.91, -996.25, 23.55, 0.0), scenario = 'WORLD_HUMAN_WELDING' },
    { label = 'Measure the wall', model = 'prop_plywood_box_01', coords = vec4(-498.39, -998.57, 23.55, 90.0), scenario = 'WORLD_HUMAN_HAMMERING' },
    { label = 'Collect the safety tools', model = 'prop_toolchest_05', coords = vec4(-520.08, -1006.43, 23.55, 0.0), scenario = 'WORLD_HUMAN_HAMMERING' }
}
