fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'codex_banking'
author 'CodeX Community'
description 'CodeX Banking - a multi-bank QBCore resource with cards, ATMs, accounts, transfers, savings, loans and invoices.'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'sql/codex_banking.sql'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/core.lua',
    'server/actions.lua',
    'server/maintenance.lua',
    'server/admin.lua'
}

dependencies {
    'qb-core',
    'oxmysql'
}
