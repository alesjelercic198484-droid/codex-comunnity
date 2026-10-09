fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'codex_blackmarket'
author 'CodeX Community'
description 'QBCore black market with a custom NUI, dynamic stock, reputation levels, cargo runs and private qb-inventory warehouses.'
version '1.0.0'

shared_script 'config.lua'

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependencies {
    'qb-core',
    'qb-target',
    'qb-inventory',
    'oxmysql'
}
