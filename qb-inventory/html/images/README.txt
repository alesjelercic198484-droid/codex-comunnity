Item icons
==========

Drop your item PNGs in this folder, named exactly like the `image` field in
qb-core/shared/items.lua. For example:

    qb-core/shared/items.lua:   ['water_bottle'] = { image = 'water_bottle.png', ... }
    this folder:                water_bottle.png

You do not need any images: every item without a PNG automatically gets a
generated tile coloured by its rarity (common / uncommon / rare / epic /
legendary / mythic), so the inventory looks finished on a fresh install.
Add the real icons whenever you like - the real image always wins.
