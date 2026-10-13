# codex_policecreator

An in-game **department creator** for FiveM: build as many Police / Sheriff / FIB / Highway Patrol / EMS (or fully custom) departments as you want, entirely in game, with **no edits to `qb-core/shared/jobs.lua`**.

Each department gets its own ranks, salaries, divisions, society funds, boss menu, armory, garage, evidence board, dispatch, ALPR/BOLO, cameras and GPS trackers.

Written for **QBCore** (ESX is auto-detected as a fallback) and built as an original, editable community resource.

---

## Features

| System | What it does |
|---|---|
| **Department creator** | `/deptcreator` - create a department from a template, then stand in the world and place boss menu / armory / garage / impound / evidence / computer / locker nodes. No coding, no restart. |
| **Ranks & permissions** | Create, rename, delete ranks in game. Each rank carries its own permission set (`dispatch`, `evidence`, `garage`, `armory`, `bolo`, `cameras`, `trackers`, `manage`, `applications`, `finance`, `divisions`, `ranks`) and salary. One rank can be flagged as the boss rank. |
| **Members** | Hire by citizenid or hire the player standing next to you, fire, promote/demote, assign to divisions, override salaries. Promotions are capped at one grade below your own unless you are the boss. |
| **Divisions** | Create K9, Traffic, Detective... and assign members to them. |
| **Society funds** | Deposit from a player's bank, withdraw with the `finance` permission, one-off bonuses, and automatic salary payouts on a timer. Every movement is written to a transaction log. |
| **Applications** | Players apply, staff accept/deny from the boss menu; accepting hires them at the lowest rank. |
| **Boss menu / NUI** | A single desktop-style terminal (vanilla JS, no build step, no external UI lib) with a tab per system, filtered by the logged-in officer's permissions. |
| **3D armory** | Rank-gated issue/return of weapons and gear, weapon serial numbers in the item metadata, optional limited stock, and a display case spawned at the armory node. |
| **Garage** | Department-owned vehicles with per-vehicle minimum grade, spawn from the garage node, fuel + body/engine health saved on return, impound/release, automatic storage when the driver disconnects. |
| **Evidence** | Use an evidence bag at a scene, set a label/description/owner/severity, then check out or destroy entries from the evidence board. |
| **Dispatch** | `/911` and `/912` civilian calls, plus officer-created calls. Calls are routed to *every* department of the matching type, each with its own row, and are broadcast as blips + sound to on-duty units. Accept / release / close, with a stored call history. |
| **ALPR & BOLO** | While driving on duty the client scans plates in a cone in front of the vehicle; the server matches them against active plate BOLOs and alerts every on-duty unit of that department type. Plate BOLOs are shared between departments; person/vehicle BOLOs stay inside the creating department. |
| **Cameras** | Place cameras from the boss menu, then watch a live feed rendered at that position (mouse look, scanline filter, ESC to exit). |
| **GPS trackers** | Use a tracker item on a vehicle; the placing client keeps its position fresh and the department can follow it from the boss menu. Trackers expire and can be recovered. |
| **Unmarked sirens** | Turn any civilian car into an unmarked unit - cycle light/siren stages with a key, no modded vehicle needed. |
| **Animations** | 36 bundled roleplay animations (police / medical / civilian / casual) playable from the boss menu or `/anims`. |
| **K9** | Deploy a dog with follow / sit / attack / search. The contraband sniff is validated server-side against the target's inventory. |
| **Duty** | `/duty`, duty state stored per member, per-shift duty logs with total hours, automatic off-duty on disconnect, orphaned shifts closed on restart. |
| **Exports** | `IsMember`, `GetMember`, `IsOnDuty`, `GetDepartment`, `GetDepartments`, `CreateDepartment`, `Hire`, `Fire`, `CreateCall`, `AddFunds`, `AddBolo`, `OnDutyByType`. |

### Optional / integration points

- **`ox_inventory`** is used automatically when it is running; otherwise the native QBCore/ESX inventory functions are used.
- **`ox_target` / `qb-target`**: `Config.Target` is prepared but the resource ships with a plain `E` prompt so it has **zero hard dependencies** beyond `oxmysql`.
- **Radio**: `Config.Radio` reserves a per-department channel offset for `pma-voice`. It is disabled by default because wiring depends on your voice setup.

---

## Installation

1. Copy `codex_policecreator` into `resources/`.
2. Add the two items from `install/ox_inventory_items.lua` to your inventory data.
3. (Optional) import `sql/codex_policecreator.sql`. The resource creates the tables itself on first start, so this step is only needed if you prefer manual control.
4. Start order:

```cfg
ensure oxmysql
ensure qb-core
ensure ox_inventory
ensure codex_policecreator
```

5. Give yourself the creator permission:

```cfg
add_ace group.admin codex_policecreator.creator allow
add_ace group.admin codex_policecreator.admin allow
```

   or put your admin job name into `Config.CreatorJobs`.

6. Run `/deptcreator`, create a department, and place at least a **Boss menu** and a **Garage** node.
7. Open the boss menu from the boss node (or `/dept`) and hire your first members.

A default `lspd` department is seeded on the very first start (`Config.Creator.SeedDefaults`).

---

## Commands

| Command | Who | What |
|---|---|---|
| `/deptcreator` | ACE `codex_policecreator.creator` | Department + node editor |
| `/dept` | members | Boss menu |
| `/duty` | members | Toggle on/off duty |
| `/911 [text]` | anyone | Police emergency call |
| `/912 [text]` | anyone | EMS emergency call |
| `/k9 [follow\|sit\|attack\|search\|dismiss]` | members (rank gated) | K9 menu / command |
| `/anims` | anyone | Animation list |
| `deptlist` (console) | admin | List departments |
| `deptsync` (console) | admin | Re-sync every client |
| `paysalary` (console) | admin | Pay all salaries now |

While the creator is open, press **X** standing on a node to delete it.

---

## How permissions work

A player belongs to **exactly one** department, keyed by `citizenid` in `codex_pc_members`. Their QBCore job is untouched - that is what makes "create any department without editing jobs" possible.

- The rank row holds a comma separated permission string, e.g. `dispatch,evidence,garage,armory`.
- `boss = 1` on a rank grants every permission.
- Promotions are limited to `your grade - 1`, unless you hold the boss rank.
- Every NUI action is re-validated server side: the client only ever *requests* something, it never decides.

Server-side validation includes: membership, department match, permission, on-duty state, rank thresholds, distance to the node the client claims to be at, call ownership, BOLO type, tracker item consumption and inventory space.

---

## Configuration

Everything tunable lives in `config.lua`:

- `Config.Framework` - `'auto'` / `'qbcore'` / `'esx'`
- `Config.DepartmentTemplates` - the presets the creator offers (police, sheriff, fib, highway, ems, custom), each with its own ranks, salaries, permissions, blip and starting funds
- `Config.NodeTypes` / `Config.NodeBlips` - what can be placed and how it looks
- `Config.Armory.Items` - item, label, minimum grade, ammo, amount
- `Config.Dispatch.Codes` - call codes and which department type receives them
- `Config.Garage.Defaults` - starter vehicles for a new department
- `Config.ALPR` / `Config.Bolo` / `Config.Cameras` / `Config.Trackers` / `Config.Sirens` / `Config.Animations` / `Config.K9`
- `Config.Duty.SalaryInterval` - payout frequency
- `Config.Creator` - limits (max departments, nodes per department, ranks, divisions, minimum node spacing)

---

## Testing

The server logic runs against a small FiveM/QBCore/oxmysql emulator, so the real modules (departments, members, finance, duty, armory, garage, evidence, dispatch, BOLO, cameras, trackers and the event/command layer) are executed and asserted - not re-implemented.

```bash
pip install lupa
python3 tests/run_lua_tests.py
```

```
codex_policecreator test suite: 215 passed, 0 failed
all tests passed
```

With a system Lua 5.4 you can also run `lua tests/run_tests.lua` from the resource folder.

---

## Notes and known limits

- **No escrow, no external paid dependency.** Everything here is editable.
- **Vehicle ownership** is per department, not per player. If you want personal ownership, extend `codex_pc_vehicles`.
- **Tracker positions** are reported by the client that attached the tracker. When that officer disconnects the last known position stays until the tracker expires.
- **Cameras** render a free-look camera at the stored position; there is no recorded footage.
- **The `duty` command** is a common name - change `Config.Commands.Duty` if another script already uses it.
- **Radio** needs a `pma-voice` hookup; the config slot is there, the wiring is not.
