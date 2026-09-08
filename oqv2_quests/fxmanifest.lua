--[[
    ╔══════════════════════════════════════════════════════════════════════╗
    ║   OQV2 QUESTS — Unlimited Mission System                             ║
    ║   Origen Quest V2 inspired  •  ESX / ox_lib / ox_inventory / ox_target║
    ║                                                                      ║
    ║   Author : Codex Dev: #Alesh48 5654                                  ║
    ║   Made with CodeX Dev.                                               ║
    ╚══════════════════════════════════════════════════════════════════════╝
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'oqv2_quests'
author 'Codex Dev: #Alesh48 5654'
description 'OQV2 Quests — Unlimited Mission System with in-game admin NUI creator. Made with CodeX Dev.'
version '2.0.0'
repository 'https://github.com/alesjelercic198484-droid/codex-comunnity'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/missions.lua',
    'config/locations.lua',
    'config/npcs.lua',
    'shared/utils.lua',
    'shared/schema.lua',
}

client_scripts {
    'client/cl_core.lua',
    'client/cl_locations.lua',
    'client/cl_missions.lua',
    'client/cl_npcs.lua',
    'client/cl_tracker.lua',
    'client/cl_nui.lua',
    'client/cl_editor.lua',
    'client/cl_commands.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_database.lua',
    'server/sv_core.lua',
    'server/sv_progression.lua',
    'server/sv_missions.lua',
    'server/sv_npcs.lua',
    'server/sv_admin.lua',
    'server/sv_commands.lua',
}

files {
    'web/index.html',
    'web/assets/css/*.css',
    'web/assets/js/*.js',
    'locales/*.json',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
}

provide 'oqv2_quests'
