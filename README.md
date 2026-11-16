# Get Ready

## Attunements, Dungeons, Keys, Class Quests, Loot and Rewards Tracker

[![Buy me a coffee](<https://img.shields.io/badge/Buy me a coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black>)](https://buymeacoffee.com/m9addons)

![Get Ready window: Krol'dok Stronghold](https://media.forgecdn.net/attachments/2216/8/gr3-png.png)

## Commands

- `/gr`: window.
- `/gr options`: options.
- `/gr size 90`: window size, 40% to 100%.
- `/gr minimap`: minimap button on/off.

## Tracks

- Raids and Keys.
- Dungeons: 29, with the five new in Forever.
- Class quests.
- Loot and rewards.
- Other: Scepter of the Shifting Sands, Aqual Quintessence, Dungeon Set 2, Quel'Serrar, Thunderfury, Cozy Sleeping Bag.

## Install

Unpack `GetReady-<version>.zip` from the [releases page](https://github.com/m9/GetReady-Forever/releases) into `_forever_\Interface\AddOns`.

WowUp: Install from URL, `https://github.com/m9/GetReady-Forever`.

## Development

Needs LuaJIT, `curl` and `tar`. `Data/Chains.lua` is built from `chains/*.lua` and [QuestieDB](https://github.com/Questie/QuestieDB). The build downloads the QuestieDB release recorded in `deps.lua` into `.cache/`.

- Build: `luajit tools/build.lua`
- Test: `luajit tests/addon_test.lua`, `luajit tests/test.lua`, `luajit tests/deps_test.lua`
- Newer QuestieDB: `luajit tools/deps.lua check`, then `luajit tools/deps.lua use questiedb` and a build.
- Another version for one run: `luajit tools/build.lua --check --questiedb 1.1.0`

## Credits

Inspired by Attune by CixiDelmont.
Quest data: QuestieDB.

## License

GPL-3.0. See `LICENSE`.
