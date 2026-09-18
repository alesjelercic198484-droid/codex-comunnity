# Required p_policejob integration

`p_policejob` is a separate escrow resource. Another resource cannot safely rewrite its private job checks or cancel an internal cuff event after it has fired. Apply the following small **configuration and call-site guard** so `gouv` gets p_policejob access and protected officials can never be cuffed.

## 1. Add `gouv` to p_policejob

Merge the lines from `p_policejob_config.lua` into `p_policejob/shared/config.lua`:

```lua
Config.Jobs['gouv'] = 0
Config.OutfitsAccess['gouv'] = 0
```

Also add `['gouv'] = 0` to each station/feature `allowedJobs` table and `['gouv'] = true` to the desired radio channels. The City Hall armory in this resource already contains the standard p_policejob items.

## 2. Guard every cuff action

The documented p_policejob actions are:

```lua
TriggerEvent('p_policejob/hardCuff')
TriggerEvent('p_policejob/softCuff')
```

Where your menu/radial/target calls those events, replace them with:

```lua
TriggerEvent('codex_government:client:protectedHardCuff')
TriggerEvent('codex_government:client:protectedSoftCuff')
```

These wrappers find the closest target and call:

```lua
exports['codex_government']:CanCuff(targetServerId)
```

before p_policejob starts its animation. A protected `gouv` target returns `false`; the server rechecks both jobs and distance, blocks the restraint, and applies the configured tase/ragdoll penalty to a police attacker.

If your p_policejob version exposes the target ID directly, this equivalent guard can be inserted before its cuff logic:

```lua
if not exports['codex_government']:CanCuff(targetServerId) then
    return
end
```

## 3. ox_inventory police group

Before `ensure ox_inventory` in `server.cfg`, include `gouv` in ox_inventory's police job list (merge with your existing list):

```cfg
setr inventory:police ["police", "gouv"]
```

## Defense in depth

`codex_government` also sets a replicated `codexGovernmentProtected` state and runs a lightweight client safety net that removes native/state-bag cuff state. That is a fallback only. The guard above is the correct way to stop p_policejob before its private cuff state and animation begin.
