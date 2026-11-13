# Get Ready

A new attunement and quest chain tracker for WoW Forever. Early work.

## Use

`/gr` or `/getready` opens the window, and so does a click on the Get Ready button at the minimap. Drag that button to move it around the minimap; `/gr minimap` hides it or brings it back.

The window fills 80% of the screen. The cog at its top right opens the options: window size (40 to 100), and "Show other classes". The same options are in the game's own options under Get Ready; `/gr options` opens them too, and `/gr size 90` sets the size.

- Left: your chains, in groups. Click a group name to fold it. Type in the box over the list to search by name; Esc clears it. A blue infinity sign after a name marks a dungeon that is new in Forever.
- Middle: the picked chain. A banner with a picture of the place has its name, its numbers (quests done, XP, and the level you still need), then its dungeons, needs and reputation on a line each, and its Wowhead address to copy. Under it is what to do next, and then the steps, which get most of the window.
- Right: a side panel, closed until you need it. Click a step to open it on that step: what the quest asks, how far you are, who and where, its level, XP, reputation, rewards, the steps before and after, a "Show on map" button and its Wowhead address to copy. Click the step again or the x to close it. "Rewards and loot" in the banner opens a pop-up: every reward the chain's quests give, then weapons and armor that may drop from the enemies on the way (not quest rewards; point at an icon to see who drops it).
- Under a step are the things its quest asks for, a line each: what to kill, use and get, with the place when it is known. Click a creature's line to see its 3D model in the side panel.
- Every step shows what it gives: XP, reputation and reward items. Reward icons show the game's item tooltip on mouse-over.
- "Show on map" puts a map pin on the place to go and opens the game's map there. The map comes in front; the window stays open behind it.
- Every chain opens as a graph: earlier steps on the left, lines to the steps they open. "Show list" switches to a list, and that is remembered per chain. Move the graph with the mouse wheel (Shift for sideways) or by dragging its background. Point at a box for the details.

Each step has a mark for its state, the same marks the game shows over quest givers:

- Green check: done. Dimmer: no longer needed, because a later step is done.
- Yellow exclamation mark: you can start it now.
- Grey question mark: in your quest log, not finished yet.
- Yellow question mark: ready to turn in.
- Grey lock: needs an earlier step, a higher level or more reputation.

Other colors mean one thing everywhere: violet is XP, teal is reputation, red is something you lack.
A step whose level you have not reached shows that level in red, in the list and on its box in the graph.
An item icon has a red cross over it when your class can never use the item, and a yellow question mark when your class can learn to but your character has not yet. The item tooltip says which. The edge of every icon is the item's quality color.

You only see chains and steps for your faction, race and class. "Show other classes" in the options also lists what other classes can do.

"Mark as done" on the banner marks a chain as done by hand, for this character, when the game cannot tell or you do not want to do it. "Not done after all" takes it back.

## What it tracks

- Raids: Molten Core, Onyxia's Lair, Blackwing Lair, Naxxramas.
- Keys: Dalaran Sewer Key, Tome of Dalaran, Shadowforge Key, Seal of Ascension, Skeleton Key, Scepter of Celebras, The Scarlet Key, Workshop Key, Key to the City, Crescent Key.
- Dungeons: quests for 29 dungeons (Blackrock Spire is two: Lower and Upper), with the quests that lead to them and the ones that follow. That includes the five new ones: The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold and The Shaper's Terrace.
- Class: the quests only your class can do, as one chain per quest line, plus one "Various" chain for the loose ones.
- Other: Scepter of the Shifting Sands, Aqual Quintessence, Dungeon Set 2, Quel'Serrar, Thunderfury, Cozy Sleeping Bag.

## Install

Download `GetReady-<version>.zip` from the [releases page](https://github.com/m9/GetReady-Forever/releases) and unpack it into `_forever_\Interface\AddOns`. The folder name must be `GetReady`.

## How the data is made

- `chains/*.lua` holds short definitions we write: a goal quest, a list of goals, a dungeon zone, or just an item.
- A build tool fills in the rest from [QuestieDB](https://github.com/Questie/QuestieDB): the quests before each goal, who gives them, what to kill and collect, map positions, rewards, XP, possible loot, and faction, class, level and reputation needs.
- The result is `Data/Chains.lua`. The addon only reads that file.
- `View.lua` decides every line of text the window shows and where each step sits in the graph. `Window.lua` only draws it.
- The addon's icon is one of the game's key item icons, named once in `Core.lua` and once in the TOC.
- The banner picture is one of the game's own loading screens, named per chain in `chains/*.lua` (`art`). No image files ship with the addon.

## Tools

Need LuaJIT and the QuestieDB addon.

Build the addon data:

`luajit tools/build.lua <path to QuestieDB_Forever.toc>`

Add `--check` to only see if `Data/Chains.lua` is out of date.
After a QuestieDB update, run the build and read the diff of that file.

The quest database has no zone for the dungeons new in Forever. Their lines in `chains/dungeons.lua` use `mentions`: every quest whose name or objective text holds the dungeon's name is a goal.

`/gr dump` in the game saves what the game itself knows and the database lacks: where you stand (run it at a dungeon door or inside), the dungeon doors on the maps, and for every quest which rewards are fixed and which you choose from. `/reload` after it; the result is in `GetReadyDB.dump` in the saved settings file.

Add a chain: put one line in `chains/vanilla.lua` or `chains/dungeons.lua`. Class chains come from `chains/classes.lua`, one line per class. The top of `chains/vanilla.lua` lists the fields.

A chain also takes the quests around its own: one that only sends you to one of its quests goes in front of it as an optional step, and quests that open after a goal come last. `chains/fixes.lua` lists the quests the database calls repeatable that you do once.

Compare with the Attune addon, by quest ID only:

`luajit tools/compare.lua <path to the Attune addon folder> <path to QuestieDB_Forever.toc>`

It lists Attune's chains with how many of their quests ours have, and the quests none of our chains has.

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
