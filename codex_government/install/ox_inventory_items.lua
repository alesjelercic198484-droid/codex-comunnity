-- Paste this entry INSIDE the table in ox_inventory/data/items.lua.
-- Then copy government_id.png into ox_inventory/web/images/.
-- Do not paste a second copy if the item already exists.

['government_id'] = {
    label = 'Government ID',
    description = 'Official government identification credential.',
    weight = 50,
    stack = false,
    close = true,
    consume = 0,
    client = {
        export = 'codex_government.governmentId',
        usetime = 800
    },
    server = {
        export = 'codex_government.useGovernmentId'
    }
},
