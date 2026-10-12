fx_version 'cerulean'
game 'gta5'

name 'codex_wallet'
author 'Codex Community'
description 'CodeX Wallet - advanced QBCore wallet system. Store ID cards and cash in a premium wallet with full logging.'
version '1.0.0'

lua54 'yes'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/logger.lua',
    'server/storage.lua',
    'server/main.lua'
}

client_script 'client/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/images/wallet_hero.jpg',
    'html/images/leather.jpg'
}

dependencies {
    'qb-core',
    'oxmysql'
}
