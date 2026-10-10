fx_version 'cerulean'
game 'gta5'
lua54 'yes'

-- IMPORTANT: the folder MUST be named `qb-inventory` and it must REPLACE the
-- stock qb-inventory resource. That is what makes it a drop-in: every other
-- qb-core script that calls `exports['qb-inventory']` or triggers an
-- `inventory:server:*` / `inventory:client:*` event keeps working untouched.

name 'qb-inventory'
author 'CodeX Roleplay Development'
description 'CodeX Roleplay Inventory - drop-in qb-inventory replacement for qb-core with a modern NUI: 4 layouts, 5 themes, 17 accents, item rarity, live search, 3D ped preview, toasts, sounds and an in-game settings studio.'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/pedpreview.lua',
    'client/main.lua'
}

server_scripts {
    'server/core.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/locales.js',
    'html/images/*.png',
    'html/images/*.svg'
}

dependencies {
    'qb-core'
}
