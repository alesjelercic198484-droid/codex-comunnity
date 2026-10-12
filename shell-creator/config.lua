Config = {}

-- PERMISSIONS
Config.AdminPermission = 'admin'
Config.UseAcePerms = true
Config.AcePermission = 'shellcreator.admin'

-- SHELL SLOTS (locations where shells exist in world)
Config.ShellSlots = {
    [1] = { id = 'slot_1', label = 'Shell Slot 1', coords = vector3(1234.5, -234.1, 67.89), heading = 0.0 },
    [2] = { id = 'slot_2', label = 'Shell Slot 2', coords = vector3(1250.0, -234.1, 67.89), heading = 0.0 },
    [3] = { id = 'slot_3', label = 'Shell Slot 3', coords = vector3(1265.0, -234.1, 67.89), heading = 0.0 },
    [4] = { id = 'slot_4', label = 'Shell Slot 4', coords = vector3(1280.0, -234.1, 67.89), heading = 0.0 },
    [5] = { id = 'slot_5', label = 'Shell Slot 5', coords = vector3(1295.0, -234.1, 67.89), heading = 0.0 },
}

-- PROP CATEGORIES
Config.PropCategories = {
    'furniture', 'lighting', 'decoration', 'kitchen', 'bathroom',
    'bedroom', 'office', 'outdoor', 'walls', 'floors', 'stairs',
    'windows', 'doors', 'clutter', 'electronics', 'plants',
}

-- PROPS
Config.Props = {
    -- FURNITURE
    { model = 'v_corp_offchair', label = 'Office Chair', category = 'furniture' },
    { model = 'v_corp_desk', label = 'Office Desk', category = 'furniture' },
    { model = 'v_corp_bookcase', label = 'Bookcase', category = 'furniture' },
    { model = 'v_res_fa_armchair', label = 'Arm Chair', category = 'furniture' },
    { model = 'v_res_fa_sofa', label = 'Sofa', category = 'furniture' },
    { model = 'v_res_fa_coffeetable', label = 'Coffee Table', category = 'furniture' },
    { model = 'v_res_fa_diningtable', label = 'Dining Table', category = 'furniture' },
    { model = 'v_res_fa_diningchair', label = 'Dining Chair', category = 'furniture' },
    { model = 'v_res_tre_sideboard', label = 'Sideboard', category = 'furniture' },
    { model = 'v_res_tre_tvstand', label = 'TV Stand', category = 'furniture' },
    { model = 'v_res_tre_shelf', label = 'Shelf Unit', category = 'furniture' },
    { model = 'v_res_tre_wardrobe', label = 'Wardrobe', category = 'furniture' },
    { model = 'v_res_tre_bed', label = 'Bed', category = 'furniture' },
    { model = 'v_res_tre_bed_table', label = 'Bedside Table', category = 'furniture' },
    { model = 'v_res_tre_dresser', label = 'Dresser', category = 'furniture' },
    { model = 'prop_rub_couch_01', label = 'Old Couch', category = 'furniture' },
    { model = 'prop_rub_couch_02', label = 'Old Couch 2', category = 'furniture' },
    { model = 'v_ind_cs_crate', label = 'Crate', category = 'furniture' },
    { model = 'v_corp_desklamp', label = 'Desk Lamp', category = 'furniture' },
    { model = 'v_res_m_housedoor', label = 'Interior Door', category = 'doors' },

    -- KITCHEN
    { model = 'v_res_tt_fridge', label = 'Fridge', category = 'kitchen' },
    { model = 'v_res_tt_stove', label = 'Stove', category = 'kitchen' },
    { model = 'v_res_tt_micro', label = 'Microwave', category = 'kitchen' },
    { model = 'v_res_tt_toaster', label = 'Toaster', category = 'kitchen' },
    { model = 'prop_washer_01', label = 'Washing Machine', category = 'kitchen' },
    { model = 'prop_sink_02', label = 'Sink', category = 'kitchen' },
    { model = 'v_res_tre_kitchencounter', label = 'Kitchen Counter', category = 'kitchen' },
    { model = 'v_res_tre_kitchencounter2', label = 'Kitchen Counter 2', category = 'kitchen' },
    { model = 'v_res_tre_kitchendrawer', label = 'Kitchen Drawer', category = 'kitchen' },

    -- BATHROOM
    { model = 'prop_toilet_01', label = 'Toilet', category = 'bathroom' },
    { model = 'prop_toilet_02', label = 'Toilet 2', category = 'bathroom' },
    { model = 'prop_sink_01', label = 'Bathroom Sink', category = 'bathroom' },
    { model = 'prop_bath_01', label = 'Bathtub', category = 'bathroom' },
    { model = 'prop_mirror_01', label = 'Mirror', category = 'bathroom' },

    -- LIGHTING
    { model = 'prop_lightceiling_01', label = 'Ceiling Light', category = 'lighting' },
    { model = 'prop_lightceiling_02', label = 'Ceiling Light 2', category = 'lighting' },
    { model = 'prop_wall_light_01a', label = 'Wall Light', category = 'lighting' },
    { model = 'prop_wall_light_02a', label = 'Wall Light 2', category = 'lighting' },
    { model = 'prop_wall_light_03a', label = 'Wall Light 3', category = 'lighting' },
    { model = 'prop_floorlamp_01', label = 'Floor Lamp', category = 'lighting' },
    { model = 'v_res_fa_lamp1', label = 'Floor Lamp 2', category = 'lighting' },

    -- DECORATION
    { model = 'v_res_fa_vase', label = 'Vase', category = 'decoration' },
    { model = 'v_res_fa_bowl', label = 'Bowl', category = 'decoration' },
    { model = 'v_res_fa_picture', label = 'Picture Frame', category = 'decoration' },
    { model = 'v_res_m_donkeys', label = 'Donkey Figurine', category = 'decoration' },
    { model = 'v_res_r_figcat', label = 'Cat Figurine', category = 'decoration' },
    { model = 'v_res_r_fighorsestnd', label = 'Horse Figurine', category = 'decoration' },

    -- ELECTRONICS
    { model = 'prop_tv_01', label = 'TV Small', category = 'electronics' },
    { model = 'prop_tv_flat', label = 'TV Flat', category = 'electronics' },
    { model = 'prop_monitor_01', label = 'Monitor', category = 'electronics' },
    { model = 'prop_keyboard_01', label = 'Keyboard', category = 'electronics' },
    { model = 'prop_speaker_01', label = 'Speaker', category = 'electronics' },
    { model = 'prop_console_01', label = 'Game Console', category = 'electronics' },

    -- PLANTS
    { model = 'prop_fern_01a', label = 'Fern', category = 'plants' },
    { model = 'prop_plant_int_01a', label = 'Indoor Plant', category = 'plants' },
    { model = 'prop_plant_int_02a', label = 'Plant 2', category = 'plants' },
    { model = 'prop_plant_int_03a', label = 'Plant 3', category = 'plants' },
    { model = 'prop_pot_plant_01a', label = 'Potted Plant', category = 'plants' },
    { model = 'prop_pot_plant_02a', label = 'Potted Plant 2', category = 'plants' },
    { model = 'prop_pot_plant_03a', label = 'Potted Plant 3', category = 'plants' },
    { model = 'prop_pot_plant_04a', label = 'Potted Plant 4', category = 'plants' },

    -- CLUTTER
    { model = 'prop_cs_book_01', label = 'Book', category = 'clutter' },
    { model = 'prop_cs_magazine_01', label = 'Magazine', category = 'clutter' },
    { model = 'prop_cs_newspaper_01', label = 'Newspaper', category = 'clutter' },
    { model = 'prop_cs_cup_01', label = 'Cup', category = 'clutter' },
    { model = 'prop_cs_plate_01', label = 'Plate', category = 'clutter' },
    { model = 'prop_rub_box_01', label = 'Box', category = 'clutter' },

    -- WALLS
    { model = 'v_corp_partition', label = 'Partition Wall', category = 'walls' },
    { model = 'v_corp_wallseg', label = 'Wall Segment', category = 'walls' },

    -- FLOORS
    { model = 'v_corp_floor', label = 'Floor Panel', category = 'floors' },

    -- STAIRS
    { model = 'prop_test_stairs_01', label = 'Staircase', category = 'stairs' },

    -- WINDOWS
    { model = 'prop_window_01', label = 'Window', category = 'windows' },
    { model = 'prop_window_02', label = 'Window 2', category = 'windows' },

    -- OUTDOOR
    { model = 'prop_bench_01a', label = 'Bench', category = 'outdoor' },
    { model = 'prop_bin_01a', label = 'Trash Bin', category = 'outdoor' },
    { model = 'prop_table_01', label = 'Outdoor Table', category = 'outdoor' },
    { model = 'prop_chair_01a', label = 'Outdoor Chair', category = 'outdoor' },
}

-- COLORS
Config.Colors = {
    { label = 'White',       hex = '#FFFFFF', r = 255, g = 255, b = 255 },
    { label = 'Light Gray',  hex = '#D3D3D3', r = 211, g = 211, b = 211 },
    { label = 'Gray',        hex = '#808080', r = 128, g = 128, b = 128 },
    { label = 'Dark Gray',   hex = '#404040', r = 64,  g = 64,  b = 64 },
    { label = 'Black',       hex = '#000000', r = 0,   g = 0,   b = 0 },
    { label = 'Red',         hex = '#FF0000', r = 255, g = 0,   b = 0 },
    { label = 'Dark Red',    hex = '#8B0000', r = 139, g = 0,   b = 0 },
    { label = 'Orange',      hex = '#FF8C00', r = 255, g = 140, b = 0 },
    { label = 'Yellow',      hex = '#FFD700', r = 255, g = 215, b = 0 },
    { label = 'Green',       hex = '#228B22', r = 34,  g = 139, b = 34 },
    { label = 'Dark Green',  hex = '#006400', r = 0,   g = 100, b = 0 },
    { label = 'Cyan',        hex = '#00CED1', r = 0,   g = 206, b = 209 },
    { label = 'Blue',        hex = '#0000FF', r = 0,   g = 0,   b = 255 },
    { label = 'Dark Blue',   hex = '#00008B', r = 0,   g = 0,   b = 139 },
    { label = 'Purple',      hex = '#800080', r = 128, g = 0,   b = 128 },
    { label = 'Pink',        hex = '#FF69B4', r = 255, g = 105, b = 180 },
    { label = 'Brown',       hex = '#8B4513', r = 139, g = 69,  b = 19 },
    { label = 'Light Brown', hex = '#D2B48C', r = 210, g = 180, b = 140 },
    { label = 'Beige',       hex = '#F5DEB3', r = 245, g = 222, b = 179 },
    { label = 'Cream',       hex = '#FFFDD0', r = 255, g = 253, b = 208 },
    { label = 'Tan',         hex = '#D2B48C', r = 210, g = 180, b = 140 },
    { label = 'Olive',       hex = '#808000', r = 128, g = 128, b = 0 },
    { label = 'Maroon',      hex = '#800000', r = 128, g = 0,   b = 0 },
    { label = 'Navy',        hex = '#000080', r = 0,   g = 0,   b = 128 },
    { label = 'Teal',        hex = '#008080', r = 0,   g = 128, b = 128 },
    { label = 'Coral',       hex = '#FF7F50', r = 255, g = 127, b = 80 },
    { label = 'Salmon',      hex = '#FA8072', r = 250, g = 128, b = 114 },
    { label = 'Turquoise',   hex = '#40E0D0', r = 64,  g = 224, b = 208 },
    { label = 'Gold',        hex = '#FFD700', r = 255, g = 215, b = 0 },
    { label = 'Silver',      hex = '#C0C0C0', r = 192, g = 192, b = 192 },
    { label = 'Lavender',    hex = '#E6E6FA', r = 230, g = 230, b = 250 },
    { label = 'Mint',        hex = '#98FF98', r = 152, g = 255, b = 152 },
}

-- SHELL TEMPLATES
Config.ShellTemplates = {
    ['apartment_small'] = { label = 'Small Apartment', description = 'Cozy small apartment', shellModel = 'v_apart_midspaz', size = { x = 10.0, y = 8.0, z = 3.0 } },
    ['apartment_large'] = { label = 'Large Apartment', description = 'Spacious apartment', shellModel = 'v_apart_highspaz', size = { x = 15.0, y = 12.0, z = 3.5 } },
    ['garage']          = { label = 'Garage',          description = 'Vehicle garage',     shellModel = 'v_garageshell',     size = { x = 20.0, y = 15.0, z = 4.0 } },
    ['office']          = { label = 'Office',          description = 'Corporate office',   shellModel = 'v_corpshell',       size = { x = 12.0, y = 10.0, z = 3.0 } },
    ['warehouse']       = { label = 'Warehouse',       description = 'Large warehouse',    shellModel = 'v_warehouse',       size = { x = 25.0, y = 20.0, z = 6.0 } },
    ['shop']            = { label = 'Shop/Store',      description = 'Retail shop',        shellModel = 'v_shopshell',       size = { x = 10.0, y = 8.0, z = 3.0 } },
    ['nightclub']       = { label = 'Nightclub',       description = 'Nightclub venue',    shellModel = 'v_nightclub',       size = { x = 20.0, y = 15.0, z = 5.0 } },
    ['studio']          = { label = 'Studio',          description = 'Small studio',       shellModel = 'v_studio',          size = { x = 6.0, y = 5.0, z = 3.0 } },
    ['garage_tuner']    = { label = 'Tuner Garage',    description = 'Tuner garage w/ lifts', shellModel = 'v_tunergarage', size = { x = 25.0, y = 20.0, z = 5.0 } },
    ['empty']           = { label = 'Empty Shell',     description = 'Start from scratch', shellModel = 'v_empty',           size = { x = 15.0, y = 15.0, z = 4.0 } },
}

-- EDITOR SETTINGS
Config.Editor = {
    moveSpeed = 0.1,
    moveSpeedFast = 0.5,
    rotateSpeed = 2.0,
    rotateSpeedFast = 10.0,
    gridSize = 0.1,
    useGridSnap = false,
    maxPropsPerShell = 200,
    maxFloors = 5,
    floorHeight = 3.0,
    teleporterMarker = true,
    markerType = 2,
    markerColor = { r = 255, g = 100, b = 0, a = 150 },
}

-- DATABASE
Config.Database = {
    tableName = 'shell_creator',
    teleporterTable = 'shell_teleporters',
}

-- QB-CORE
Config.QBCore = {
    commandName = 'shellcreator',
    teleportCommand = 'shelltp',
    itemEnabled = false,
    itemName = 'shell_remote',
}

-- KEYS
Config.Keys = {
    openMenu = 'F6',
    confirm = 'E',
    cancel = 'X',
    moveUp = 'PAGEUP',
    moveDown = 'PAGEDOWN',
    rotateLeft = 'LEFT',
    rotateRight = 'RIGHT',
    toggleFast = 'LSHIFT',
    toggleGrid = 'G',
    deleteProp = 'DELETE',
    duplicateProp = 'INSERT',
    saveShell = 'F5',
    exitEditor = 'BACKSPACE',
}
