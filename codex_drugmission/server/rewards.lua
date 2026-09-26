local ESX = exports.es_extended:getSharedObject()

function GiveMissionRewards(source, rewards)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end
    for _, reward in ipairs(rewards) do
        local amount = math.floor(tonumber(reward.amount) or 0)
        if reward.type == 'item' then
            if reward.name == '' or not exports.ox_inventory:CanCarryItem(source, reward.name, amount) then return false end
        end
    end
    for _, reward in ipairs(rewards) do
        if reward.type == 'item' then
            if not exports.ox_inventory:AddItem(source, reward.name, reward.amount) then return false end
        elseif reward.type == 'cash' then xPlayer.addAccountMoney('money', reward.amount, 'drug mission')
        elseif reward.type == 'bank' then xPlayer.addAccountMoney('bank', reward.amount, 'drug mission')
        elseif reward.type == 'black_money' then xPlayer.addAccountMoney('black_money', reward.amount, 'drug mission') end
    end
    return true
end
