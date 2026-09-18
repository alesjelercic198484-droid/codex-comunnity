-- PASTE THIS AT THE END of p_policejob/shared/config.lua, after Config.Jobs,
-- Config.OutfitsAccess, Config.Shops, Config.Stations and Config.Radio exist.
-- This is an install snippet; do not `ensure` it as a separate resource.

-- Core p_policejob authorization. This is the important line that makes the
-- p_policejob item callbacks/interactions recognize gouv as an authorized job.
Config.Jobs = Config.Jobs or {}
Config.Jobs['gouv'] = 0

-- Outfit creator/access.
Config.OutfitsAccess = Config.OutfitsAccess or {}
Config.OutfitsAccess['gouv'] = 0

-- Authorize gouv in every configured p_policejob shop.
for _, shop in pairs(Config.Shops or {}) do
    shop.allowedJobs = shop.allowedJobs or {}
    shop.allowedJobs['gouv'] = 0
end

-- Authorize supported station features used by current p_policejob versions.
for _, station in pairs(Config.Stations or {}) do
    local featureNames = {
        'trashes',
        'bodycams',
        'toggleDuty'
    }

    for i = 1, #featureNames do
        for _, feature in pairs(station[featureNames[i]] or {}) do
            feature.allowedJobs = feature.allowedJobs or {}
            feature.allowedJobs['gouv'] = 0
        end
    end

    -- Government users will receive station-bell alerts where bells exist.
    for _, bell in pairs(station.bells or {}) do
        bell.jobs = bell.jobs or {}
        bell.jobs['gouv'] = true
    end
end

-- Permit gouv on all configured p_policejob radio channels. Delete this loop
-- and add gouv only to selected channels if your radio traffic is separated.
for _, channel in pairs(Config.Radio or {}) do
    channel.jobs = channel.jobs or {}
    channel.jobs['gouv'] = true
end

-- The codex_government City Hall armory is independent and already contains
-- all standard p_policejob items. In codex_government/config.lua this setting:
--
--   Config.Armory.AllowAllItemsForGovernment = true
--
-- makes every armory entry available from grade 0, so every gouv rank can take
-- every configured police item.
