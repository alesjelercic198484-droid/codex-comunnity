fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CodeX Community'
description 'Gouv government / justice / secret service job for ESX, ox_inventory and ox_target.'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js',
    'html/style.css'
}

dependencies {
    'es_extended',
    'ox_inventory',
    'ox_target'
}
