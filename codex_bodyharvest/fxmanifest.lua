fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CodeX Roleplay Development'
description 'ESX body harvesting - cut a finger, an ear or the tongue from dead players with a knife and sell the parts to a hidden dealer. Built for ox_target, ox_inventory and ox_lib.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_target',
    'ox_inventory'
}
