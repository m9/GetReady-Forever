# Get Ready

Attunement, key and quest chain tracker for WoW Forever.

## Features

- Chains for raids, keys, dungeons and class quests.
- Steps as a graph or a list.
- Step details: objectives, 3D model, map pin, Wowhead link.
- Rewards and possible loot.
- XP, reputation and level needs.
- Search.
- Chains and steps can be marked as done.
- Shows your faction, race and class. Other classes: optional.

## Tracks

- Raids: Molten Core, Onyxia's Lair, Blackwing Lair, Naxxramas.
- Keys: Dalaran Sewer Key, Tome of Dalaran, Shadowforge Key, Seal of Ascension, Skeleton Key, Scepter of Celebras, The Scarlet Key, Workshop Key, Key to the City, Crescent Key.
- Dungeons: 29, with the five new in Forever.
- Class quests.
- Other: Scepter of the Shifting Sands, Aqual Quintessence, Dungeon Set 2, Quel'Serrar, Thunderfury, Cozy Sleeping Bag.

## Commands

- `/gr`: window.
- `/gr options`: options.
- `/gr size 90`: window size, 40 to 100.
- `/gr minimap`: minimap button on/off.

## Install

Unpack `GetReady-<version>.zip` from the [releases page](https://github.com/m9/GetReady-Forever/releases) into `_forever_\Interface\AddOns`.

WowUp: Install from URL, `https://github.com/m9/GetReady-Forever`.

## Development

Needs LuaJIT and [QuestieDB](https://github.com/Questie/QuestieDB). `Data/Chains.lua` is built from `chains/*.lua`.

- Build: `luajit tools/build.lua <path to QuestieDB_Forever.toc>`
- Test: `luajit tests/addon_test.lua`, `luajit tests/test.lua`

## Credits

Inspired by Attune by CixiDelmont. No code or data is taken from it.
Quest data: QuestieDB.

## License

GPL-3.0. See `LICENSE`.
