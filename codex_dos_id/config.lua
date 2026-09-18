Config = {}

-- Enable extra prints in the server console.
Config.Debug = false

Config.ESX = {
    -- ESX Legacy export is preferred. If your server uses old ESX, set UseExport = false.
    UseExport = true,
    ExportName = 'es_extended',
    SharedObjectEvent = 'esx:getSharedObject'
}

-- ---------------------------------------------------------------------------
-- Item
-- ---------------------------------------------------------------------------
-- Item name as it must exist in the `items` table (ESX) or ox_inventory's
-- `data/items.lua`. See the README / SQL file included with this resource.
Config.Item = 'dos_id_card'

-- Job(s) allowed to own / use this ID card.
-- The primary job requested is 'gouv' (Government / Department of Defense).
Config.Job = 'gouv'

-- If you want several jobs to be able to use the same card (e.g. sub-grades),
-- list them here. Leave empty to only allow Config.Job.
Config.AllowedJobs = {
    -- 'gouv',
    -- 'dos'
}

-- ---------------------------------------------------------------------------
-- Card branding
-- ---------------------------------------------------------------------------
Config.Card = {
    Agency = 'DEPARTMENT OF DEFENSE',
    Division = 'SECRET SERVICES',
    Footer = 'This credential certifies that the bearer is an active federal agent authorized under national security statutes.',
    -- Shown as the "job title" line if the player job label from ESX is empty.
    FallbackJobLabel = 'Federal Agent'
}

-- ---------------------------------------------------------------------------
-- Presenting the ID to nearby officers
-- ---------------------------------------------------------------------------
Config.Presentation = {
    -- When the card owner uses the item, nearby players whose job matches one
    -- of these jobs will automatically see the card pop up on their screen
    -- (read-only), just like handing over an ID card in real life.
    ViewerJobs = {
        'police'
    },

    -- Radius (GTA units) around the card owner that is scanned for viewers.
    Radius = 4.0,

    -- How long (ms) the presented card stays open on the viewer's screen
    -- before it auto-closes.
    AutoCloseMs = 12000
}

-- ---------------------------------------------------------------------------
-- Fallback command (in case no inventory usable-item hook is available)
-- ---------------------------------------------------------------------------
-- Set to false to disable entirely and rely only on the inventory item.
Config.Command = 'dosid'

Config.Notifications = {
    NoPermission = 'You are not authorized to carry this credential.',
    NotReady = 'Your data is still loading, try again in a moment.',
    Shown = 'You presented your ID card.',
    Received = '%s presented their ID card to you.'
}
