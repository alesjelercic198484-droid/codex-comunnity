fx_version 'cerulean'
game 'gta5'

name 'codex_government'
author 'Codex Community'
description 'Professional ESX government job integration for ox_inventory, ox_target and p_policejob'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/images/seal.svg'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target'
}
