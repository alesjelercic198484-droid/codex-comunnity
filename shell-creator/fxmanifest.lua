fx_version 'cerulean'
game 'gta5'

name 'Shell Creator'
description 'In-game Shell Creator tool for qb-core'
author 'Shell Creator'
version '1.0.0'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/editor.lua',
    'client/props.lua',
    'client/ui.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/shells.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

ui_page 'html/index.html'

dependencies {
    'qb-core',
}

lua54 'yes'
