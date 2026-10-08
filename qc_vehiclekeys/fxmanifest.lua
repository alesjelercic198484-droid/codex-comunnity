fx_version 'cerulean'
game 'gta5'
author 'QC Community'
description 'Advanced Vehicle Keys System - QB-Core Standalone'
lua54 'yes'
version '1.0.0'

ui_page 'web/build/index.html'

client_scripts {
    'bridge/client.lua',
    'client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server.lua',
}

shared_scripts {
    '@ox_lib/init.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

files {
    'web/build/index.html',
    'web/build/**/*',
    'locales/*.json',
    'config/shared.lua',
    'modules/**/client.lua',
    'modules/**/server.lua',
}