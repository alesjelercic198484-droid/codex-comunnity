fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CodeX Roleplay Development'
description 'Multiplayer construction contracts for ESX with ox_target, ox_inventory and a tablet NUI.'
version '1.0.0'

shared_scripts { 'config.lua' }
client_scripts { 'client/main.lua' }
server_scripts { 'server/main.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }

dependencies { 'es_extended', 'ox_target', 'ox_inventory' }
