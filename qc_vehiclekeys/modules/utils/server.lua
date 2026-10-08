local Utils = {}

lib.locale(Bridge.Config.Language or 'en')

function Utils:trim(str)
    if type(str) ~= 'string' then return str end
    return str:match('^%s*(.-)%s*$')
end

-- Handle item add/remove requests from client bridge
RegisterNetEvent('qc_vehiclekeys/server/addItem', function(itemName, count, metadata)
    local src = source
    Bridge.Inventory.addItem(src, itemName, count, metadata)
end)

RegisterNetEvent('qc_vehiclekeys/server/removeItem', function(itemName, count, metadata)
    local src = source
    Bridge.Inventory.removeItem(src, itemName, count, metadata)
end)

return Utils