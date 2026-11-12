# Get Ready

A new attunement and quest chain tracker for WoW Forever. Early work.

## Use

`/gr` or `/getready` opens the window. It fills most of the screen; `/gr size 80` makes it fill 80% (40 to 100).

- Left: your chains, in groups. Click a group name to fold it.
- Middle: the picked chain under a banner with a picture of the place, then what is still ahead, every reward its quests give, what to do next, and all its steps.
- Right: possible loot. Weapons and armor that may drop from the enemies the chain sends you to kill, and for a dungeon from its other bosses. These are not quest rewards. Point at an icon to see who drops it.
- Every step shows what it gives: XP, reputation and reward items. Reward icons show the game's item tooltip on mouse-over.
- "Show on map", or a click on a step, puts a map pin on the place to go.
- Chains whose steps lead to one another open as a graph: earlier steps on the left, lines to the steps they open. "Show list" switches back, per chain. Move the graph with the mouse wheel (Shift for sideways) or by dragging its background. Point at a box for the details.

Each step has a mark and a color for its state:

- Green check: done. Dimmer: no longer needed, because a later step is done.
- Gold question mark: in your quest log.
- Blue square: you can start it now.
- Grey lock: needs an earlier step, a higher level or more reputation.

Other colors mean one thing everywhere: violet is XP, teal is reputation, red is something you lack.
A step whose level you have not reached shows that level in red, in the list and on its box in the graph.
An item icon has a red cross over it when your class can never use the item, and a yellow question mark when your class can learn to but your character has not yet. The item tooltip says which. The edge of every icon is the item's quality color.
Under the banner, four tiles give the numbers: progress, quests left, XP to earn, and the level the chain starts at.

You only see chains and steps for your faction, race and class.

"Mark as done" on the banner marks a chain as done by hand, for this character, when the game cannot tell or you do not want to do it. "Not done after all" takes it back.

## What it tracks

- Raids: Molten Core, Onyxia's Lair, Blackwing Lair, Naxxramas.
- Keys: Shadowforge Key, Seal of Ascension, Skeleton Key, Scepter of Celebras, The Scarlet Key, Workshop Key, Key to the City, Crescent Key.
- Dungeons: quests for 23 dungeons, with the quests that lead to them.
- Class: the quests only your class can do, as one chain per quest line, plus one chain for the loose ones.
- Other: Scepter of the Shifting Sands, Aqual Quintessence, Dungeon Set 2, Quel'Serrar, Thunderfury, Cozy Sleeping Bag.

## Install

Download `GetReady-<version>.zip` from the [releases page](https://github.com/m9/GetReady-Forever/releases) and unpack it into `_forever_\Interface\AddOns`. The folder name must be `GetReady`.

## How the data is made

- `chains/*.lua` holds short definitions we write: a goal quest, a list of goals, a dungeon zone, or just an item.
- A build tool fills in the rest from [QuestieDB](https://github.com/Questie/QuestieDB): the quests before each goal, who gives them, what to kill and collect, map positions, rewards, XP, possible loot, and faction, class, level and reputation needs.
- The result is `Data/Chains.lua`. The addon only reads that file.
- `View.lua` decides every line of text the window shows and where each step sits in the graph. `Window.lua` only draws it.
- The banner picture is one of the game's own loading screens, named per chain in `chains/*.lua` (`art`). No image files ship with the addon.

## Tools

Need LuaJIT and the QuestieDB addon.

Build the addon data:

`luajit tools/build.lua <path to QuestieDB_Forever.toc>`

Add `--check` to only see if `Data/Chains.lua` is out of date.
After a QuestieDB update, run the build and read the diff of that file.

Add a chain: put one line in `chains/vanilla.lua` or `chains/dungeons.lua`. Class chains come from `chains/classes.lua`, one line per class. The top of `chains/vanilla.lua` lists the fields.

Find IDs by name:

`luajit tools/find.lua <path to QuestieDB_Forever.toc> quest "Attunement"`

Works for `quest`, `item`, `npc` and `object`.

Show the quest chain that leads to a quest:

`luajit tools/chain.lua <path to QuestieDB_Forever.toc> 6602`

## Test

`luajit tests/addon_test.lua` - runs the addon against a mock game.

`luajit tests/test.lua` - runs the data tools against a mock.

`luajit tests/test.lua <path to QuestieDB_Forever.toc>` - also checks the real database.

## Credits

Inspired by Attune by CixiDelmont. No code or data is taken from it.
Quest data comes from QuestieDB.

## License

GPL-3.0. See `LICENSE`.
