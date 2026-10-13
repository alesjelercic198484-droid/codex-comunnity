fx_version 'cerulean'
game 'gta5'

name 'codex_policecreator'
author 'Codex Community'
description 'In-game department creator: unlimited police/EMS departments with boss menu, armory, garage, evidence, dispatch, ALPR/BOLO, cameras and GPS trackers. QBCore / ESX.'
version '1.0.0'

lua54 'yes'

shared_scripts {
    'config.lua',
    'shared/core.lua',
    'shared/bridge.lua'
}

client_scripts {
    'client/main.lua',
    'client/creator.lua',
    'client/armory.lua',
    'client/garage.lua',
    'client/evidence.lua',
    'client/dispatch.lua',
    'client/alpr.lua',
    'client/gps.lua',
    'client/camera.lua',
    'client/siren.lua',
    'client/anims.lua',
    'client/k9.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/departments.lua',
    'server/members.lua',
    'server/finance.lua',
    'server/duty.lua',
    'server/armory.lua',
    'server/garage.lua',
    'server/evidence.lua',
    'server/dispatch.lua',
    'server/bolo.lua',
    'server/cameras.lua',
    'server/trackers.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependencies {
    'oxmysql'
}
