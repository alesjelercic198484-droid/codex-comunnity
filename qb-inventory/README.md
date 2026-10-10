# CodeX Roleplay Inventory

A **drop-in replacement for `qb-inventory`** for **qb-core**, with a completely new NUI.

The resource keeps the name `qb-inventory`, keeps the stock qb-core data model
(items stay in `PlayerData.items`, keyed by slot number) and reproduces the full
public API of the original resource, so **every other qb-core script keeps
working without touching a single line of their code**.

![CodeX Roleplay](https://img.shields.io/badge/CodeX%20Roleplay-inventory-10b981)
![qb-core](https://img.shields.io/badge/framework-qb--core-38bdf8)

---

## Install (copy & paste)

1. **Remove / disable** your current `qb-inventory`.
2. Copy this folder into your resources folder **named exactly `qb-inventory`**
   (for example `resources/[qb]/qb-inventory`).
3. Add it to your `server.cfg` **after** `qb-core`:

   ```cfg
   ensure qb-core
   ensure qb-weapons
   ensure qb-inventory
   ```

4. *(Optional but recommended for persistent stashes)* run
   `install/qb_inventory_codex.sql` in your database.
5. Restart the server and press **TAB**.

That is it. No script has to be edited, no export has to be renamed, no config
has to be merged.

> The folder name is not cosmetic. qb-core itself calls
> `exports['qb-inventory']:HasItem(...)` and `exports['qb-inventory']:UseItem(...)`.
> If the folder is renamed, qb-core stops finding the inventory.

---

## What it looks like

The interface is modelled after the modern "inventory redesign" style:

- **"CodeX Roleplay" header** sitting directly above the inventory.
- **4 layout templates** - `Showcase` (live 3D character), `Classic`, `Grid`, `Tarkov`.
- **5 theme skins** - Glass, Tactical, Neon, Minimal, Luxe.
- **17 accent colours** plus a free colour picker.
- **Item rarity** - 6 tiers with a colour wash, outline and a breathing aura on
  legendary / mythic items.
- **Live search**, weight bar, hotbar, money cards and cash / bank display.
- **Toasts** for pick up / drop / use, colour coded per action.
- **Interface sounds** synthesised with the WebAudio API (no audio files).
- **In-game settings studio** where every player can change the look live, with a
  real time preview, plus an **admin lock** that pushes one look to the whole server.
- **Live text editor** - rewrite or hide any interface text in game.
- **7 languages** - EN, SL, PT, ES, FR, DE, IT.

### 3D character preview

In the `Showcase` layout the left column is a transparent window: the resource
clones your ped locally (nobody else can see it), frames it with a scripted
camera and the game renders it through the NUI. If anything about that fails the
preview switches itself off silently and the inventory keeps working.

---

## Features

### Inventory

| Feature | Notes |
| --- | --- |
| Player inventory | 40 slots, 120 kg by default (`config.lua`) |
| Hotbar | slots 1-5, keys `1`-`5` |
| Move / swap / split | drag & drop, right click → Split |
| Use | double click, or right click → Use |
| Drop | right click → Drop, picks how many |
| Give | right click → Give, lists nearby players |
| Stashes | `stash-<name>`, optional SQL persistence |
| Drops | ground drops with markers, `[E]` to open |
| Vehicles | `trunk-<plate>` and `glovebox-<plate>` |
| Shops | `CreateShop` / `OpenShop`, stock and money handled server side |
| Other players | `OpenInventoryById` (search / rob) |

### Compatibility surface

Everything below is provided so third party scripts keep working:

**Exports** (30): `LoadInventory`, `SaveInventory`, `SetInventory`, `SetItemData`,
`UseItem`, `GetSlotsByItem`, `GetFirstSlotByItem`, `GetItemBySlot`,
`GetTotalWeight`, `GetItemByName`, `GetItemsByName`, `GetSlots`, `GetItemCount`,
`CanAddItem`, `GetFreeWeight`, `ClearInventory`, `HasItem`, `CloseInventory`,
`OpenInventoryById`, `ClearStash`, `CreateShop`, `OpenShop`, `OpenInventory`,
`CreateInventory`, `GetInventory`, `RemoveInventory`, `AddItem`, `RemoveItem`,
`AddHook`, `RemoveHook`, `AddListener`, `RemoveListener`.

**Events** (modern `qb-inventory:*` **and** legacy `inventory:*`):
`SetInventoryData`, `openInventory`, `closeInventory`, `useItem`, `openDrop`,
`updateDrop`, `openVending`, `snowball`, `OpenInventory`, `UseItemSlot`,
`OpenTrunk`, `OpenGlovebox`, `SaveInventory`, `ItemBox`, `hotbar`,
`requiredItems`, `CheckWeapon`, `giveAnim`, `closeInv`.

**Callbacks**: `GetCurrentDrops`, `createDrop`, `attemptPurchase`, `giveItem`,
`openStash`.

---

## Configuration

Everything lives in `config.lua`. The most important values:

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.Brand.Text` | `CodeX Roleplay` | The text above the inventory |
| `Config.Brand.Logo` | `''` | Optional logo inside `html/images/` |
| `Config.MaxSlots` | `40` | Inventory slots |
| `Config.MaxWeight` | `120000` | Grams (120 kg) |
| `Config.HotbarSlots` | `5` | Hotbar size |
| `Config.Keys.Open` | `TAB` | Open / close key |
| `Config.Rarity.Items` | `{}` | Force a rarity per item name |
| `Config.Defaults` | - | Layout / theme / accent every new player starts with |
| `Config.Stashes.Persist` | `true` | Save stashes to SQL |
| `Config.Drops.DespawnTime` | `0` | Minutes before a drop vanishes (`0` = never) |

### Rarity

Rarity is resolved in this order:

1. `Config.Rarity.Items['item_name']`
2. the `rarity` field inside `QBCore.Shared.Items`
3. `Config.Rarity.Default`

Tiers: `common`, `uncommon`, `rare`, `epic`, `legendary`, `mythic`.

```lua
Config.Rarity.Items = {
    ['weapon_pistol'] = 'rare',
    ['goldbar']       = 'legendary',
}
```

### Item images

Icons are loaded from `html/images/<image>` using the `image` field of
`QBCore.Shared.Items` (for example `water_bottle.png`). Items without an image
automatically get a generated tile coloured by their rarity, so the inventory
looks finished even on a fresh install.

---

## Admin

- `/giveitem [id] [item] [amount]` - give an item (needs `inventory.admin`)
- `/clearinv [id]` - clear an inventory (needs `inventory.admin`)

Grant the ace:

```cfg
add_ace group.admin inventory.admin allow
```

With it, the **Admin** tab of the settings studio can push your layout, theme,
accent and text overrides to every player on the server.

---

## Tests

The resource ships an automated suite that boots the real server scripts against
a FiveM + qb-core emulator and asserts on the actual behaviour (adding,
stacking, weight limits, moving, swapping, splitting, drops, stashes, shops,
giving items and the legacy event aliases).

```bash
pip install lupa
python3 tests/run_lua_tests.py
```

or, with a system Lua 5.4:

```bash
lua tests/run_tests.lua
```

---

## Credits

Built for the **CodeX Roleplay** community. UI design language inspired by the
modern inventory redesign showcases.
