-- PROPS MANAGEMENT
function GetPropsByCategory(category)
    local props = {}
    for _, prop in ipairs(Config.Props) do
        if prop.category == category then table.insert(props, prop) end
    end
    return props
end

function SearchProps(query)
    local results = {}
    local queryLower = string.lower(query)
    for _, prop in ipairs(Config.Props) do
        if string.find(string.lower(prop.label), queryLower) or string.find(string.lower(prop.model), queryLower) then
            table.insert(results, prop)
        end
    end
    return results
end

function GetFormattedPropList()
    local formatted = {}
    for _, category in ipairs(Config.PropCategories) do
        local categoryProps = GetPropsByCategory(category)
        if #categoryProps > 0 then
            local catData = {
                name = category,
                label = string.upper(category:sub(1, 1)) .. category:sub(2),
                count = #categoryProps,
                props = {}
            }
            for _, prop in ipairs(categoryProps) do
                table.insert(catData.props, { model = prop.model, label = prop.label })
            end
            table.insert(formatted, catData)
        end
    end
    return formatted
end

function GetFormattedColorList()
    local formatted = {}
    for i, color in ipairs(Config.Colors) do
        table.insert(formatted, { id = i, label = color.label, hex = color.hex })
    end
    return formatted
end

function GetFormattedTemplates()
    local formatted = {}
    for key, template in pairs(Config.ShellTemplates) do
        table.insert(formatted, { id = key, label = template.label, description = template.description })
    end
    table.sort(formatted, function(a, b) return a.label < b.label end)
    return formatted
end

function GetFormattedSlots()
    local formatted = {}
    for _, slot in ipairs(Config.ShellSlots) do
        local isOccupied = loadedShells[slot.id] ~= nil
        table.insert(formatted, {
            id = slot.id, label = slot.label, occupied = isOccupied,
            coords = { x = string.format('%.1f', slot.coords.x), y = string.format('%.1f', slot.coords.y), z = string.format('%.1f', slot.coords.z) },
        })
    end
    return formatted
end

function GetCurrentFloor() return currentFloor end

function SetCurrentFloor(floor)
    if floor < 1 then floor = 1 end
    if floor > Config.Editor.maxFloors then floor = Config.Editor.maxFloors end
    currentFloor = floor
    RefreshFloorVisibility()
    QBCore.Functions.Notify('Nadstropje ' .. floor, 'primary')
end

function AddFloor()
    if not editingShellData then return end
    if not editingShellData.floors then editingShellData.floors = {} end
    if #editingShellData.floors >= Config.Editor.maxFloors then
        QBCore.Functions.Notify('Max nadstropij dosežen!', 'error')
        return
    end
    local floorHeight = currentFloor * Config.Editor.floorHeight
    table.insert(editingShellData.floors, { height = floorHeight, color = Config.Colors[1] })
    local slot = GetSlotById(editingSlotId)
    if slot then CreateFloorEntity(slot.coords, slot.heading, editingShellData.floors[#editingShellData.floors]) end
    QBCore.Functions.Notify('Nadstropje dodano!', 'success')
end

function RefreshFloorVisibility()
    if not editingShellData or not editingShellData.props then return end
    for i, propData in ipairs(editingShellData.props) do
        local propFloor = propData.floor or 1
        if propData._entity and DoesEntityExist(propData._entity) then
            if propFloor == currentFloor then
                SetEntityVisible(propData._entity, true, false)
                SetEntityCollision(propData._entity, true, true)
            else
                SetEntityVisible(propData._entity, false, false)
                SetEntityCollision(propData._entity, false, false)
            end
        end
    end
end

function ApplyColorToWall(colorIndex)
    if not editingShellData then return end
    if not editingShellData.colors then editingShellData.colors = {} end
    editingShellData.colors.wall = colorIndex
    QBCore.Functions.Notify('Barva stene uporabljena', 'success')
end

function ApplyColorToFloor(colorIndex)
    if not editingShellData then return end
    if not editingShellData.colors then editingShellData.colors = {} end
    editingShellData.colors.floor = colorIndex
    QBCore.Functions.Notify('Barva tal uporabljena', 'success')
end

exports('GetFormattedPropList', GetFormattedPropList)
exports('GetFormattedColorList', GetFormattedColorList)
exports('GetFormattedTemplates', GetFormattedTemplates)
exports('GetFormattedSlots', GetFormattedSlots)
exports('SearchProps', SearchProps)
exports('SetCurrentFloor', SetCurrentFloor)
exports('AddFloor', AddFloor)
