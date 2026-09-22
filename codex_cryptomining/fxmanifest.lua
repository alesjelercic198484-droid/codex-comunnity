fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CodeX Community'
description 'Advanced ESX crypto mining economy: warehouses, mining rigs with real props, GPU market, electricity billing, heists and a live BTC market. Built-in UI (notifications, progress, skillcheck) - only es_extended + oxmysql are required, ox_inventory & ox_target are optional.'
version '1.1.0'

shared_scripts {
    'config.lua',
    'shared/core.lua',
    'locales/*.lua'
}

client_scripts {
    'client/interior.lua',
    'client/robbery.lua',
    'client/main.lua'
}

server_scripts {
    'server/database.lua',
    'server/framework.lua',
    'server/market.lua',
    'server/warehouses.lua',
    'server/shops.lua',
    'server/robbery.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependencies {
    'es_extended'
}
