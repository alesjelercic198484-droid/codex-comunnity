fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'codex_drugmission'
author 'CodeX Roleplay'
description 'Server-authoritative ESX Legacy drug delivery missions'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/cleanup.lua',
    'client/nui.lua',
    'client/npc.lua',
    'client/enemies.lua',
    'client/mission.lua',
    'client/main.lua'
}

server_scripts {
    'server/database.lua',
    'server/rewards.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'data/missions.json',
    'sounds/hurry.mp3',
    'sounds/dialogue_start.mp3',
    'sounds/player_brave.mp3',
    'sounds/player_not_ready.mp3',
    'sounds/dialogue_challenge.mp3',
    'sounds/dialogue_decline.mp3'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_target',
    'ox_inventory'
}
