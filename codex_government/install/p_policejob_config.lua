-- MERGE these entries into p_policejob/shared/config.lua.
-- Do not replace the whole p_policejob Config table with this snippet.

-- 1. Authorize gouv as a law-enforcement-capable job.
Config.Jobs['gouv'] = 0
Config.OutfitsAccess['gouv'] = 0

-- 2. Add gouv to every p_policejob station feature you want it to use.
-- Examples (actual station keys/structure depend on your p_policejob version):
-- Config.Shops.Armory.allowedJobs['gouv'] = 0
-- Config.Stations.MissionRow.trashes[1].allowedJobs['gouv'] = 0
-- Config.Stations.MissionRow.bodycams[1].allowedJobs['gouv'] = 0

-- 3. Permit government users on the desired p_policejob radio channels.
-- Repeat for each channel that should be available:
-- Config.Radio[1].jobs['gouv'] = true
-- Config.Radio[2].jobs['gouv'] = true
-- Config.Radio[3].jobs['gouv'] = true

-- This resource already creates its own grade-secured City Hall armory with all
-- standard p_policejob items, so editing Config.Shops is optional for armory use.
