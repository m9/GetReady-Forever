-- Chain definitions. The build fills in the quests before each goal.
--
--   id      short unique key, never change it once released (saved progress uses it)
--   name    shown in the list
--   kind    raid, key, dungeon, class or misc
--
-- What ends the chain, one of:
--   goal    one quest ID
--   goals   a list of quest IDs
--   zone    a dungeon area ID: every quest of that dungeon is a goal
--   (none)  only a reward item: the chain is "get this item"
--
-- Optional:
--   any     true = one of the goals is enough
--   reward  item ID you hold when the chain is done
--   side    Alliance, Horde or Both (taken from the goal quest if left out)
--   note    one short line: what the chain is for
--   art     picture for the banner: a loading screen of the game, the part of its file name after
--           Interface\Glues\LoadingScreens\LoadScreen (Strathome is how the game spells that one)

return {
	-- Raids
	{ id = "mc", name = "Molten Core", kind = "raid", art = "MoltenCore", goal = 7848,
		note = "Enter Molten Core from Blackrock Mountain, without the run through Blackrock Depths." },
	{ id = "ony-horde", name = "Onyxia's Lair", kind = "raid", art = "Raid", goal = 6602, reward = 16309,
		note = "The amulet lets you enter Onyxia's Lair." },
	{ id = "ony-alliance", name = "Onyxia's Lair", kind = "raid", art = "Raid", goal = 6502, reward = 16309,
		note = "The amulet lets you enter Onyxia's Lair." },
	{ id = "bwl", name = "Blackwing Lair", kind = "raid", art = "BlackwingLair", goal = 7761,
		note = "Enter Blackwing Lair through the orb in Blackrock Mountain." },
	{ id = "naxx", name = "Naxxramas", kind = "raid", art = "Naxxramas", goals = { 9121, 9122, 9123 }, any = true,
		note = "Lets you enter Naxxramas. Higher Argent Dawn reputation makes it cheaper." },

	-- Keys
	{ id = "brd-key", name = "Shadowforge Key", kind = "key", art = "BlackrockDepths", goal = 3802, reward = 11000,
		note = "Opens the locked doors in Blackrock Depths." },
	{ id = "ubrs-key", name = "Seal of Ascension", kind = "key", art = "BlackrockSpire", goal = 4743, reward = 12344,
		note = "Opens Upper Blackrock Spire." },
	{ id = "scholo-key-alliance", name = "Skeleton Key", kind = "key", art = "Scholomance", goal = 5505, reward = 13704,
		note = "Opens Scholomance." },
	{ id = "scholo-key-horde", name = "Skeleton Key", kind = "key", art = "Scholomance", goal = 5511, reward = 13704,
		note = "Opens Scholomance." },
	{ id = "mara-scepter", name = "Scepter of Celebras", kind = "key", art = "Maraudon", goal = 7046, reward = 17191,
		note = "Opens the portal to the inner part of Maraudon." },
	{ id = "sm-key", name = "The Scarlet Key", kind = "key", art = "Monastery", reward = 7146,
		note = "Opens the Armory and Cathedral in Scarlet Monastery." },
	{ id = "gnomer-key", name = "Workshop Key", kind = "key", art = "Gnomeregan", reward = 6893,
		note = "Opens the back door of Gnomeregan." },
	{ id = "strat-key", name = "Key to the City", kind = "key", art = "Strathome", reward = 12382,
		note = "Opens the gates inside Stratholme." },
	{ id = "dm-key", name = "Crescent Key", kind = "key", art = "DireMaul", reward = 18249,
		note = "Opens the doors of Dire Maul." },

	-- Other
	{ id = "aq-scepter", name = "Scepter of the Shifting Sands", kind = "misc", art = "AhnQiraj40man", goal = 8743,
		note = "The long road to ringing the gong at the gates of Ahn'Qiraj." },
	{ id = "mc-quintessence", name = "Aqual Quintessence", kind = "misc", art = "MoltenCore", goal = 6824,
		note = "Needed to douse the runes in Molten Core." },
	{ id = "dungeon-set-2", name = "Dungeon Set 2", kind = "misc", art = "Dungeon", goals = {
		8999, 9000, 9001, 9002, 9003, 9004, 9005, 9006, 9007, 9008, 9009, 9010, 9011, 9012, 9013, 9014,
	}, note = "Upgrades your first dungeon set, piece by piece." },
	{ id = "quel-serrar", name = "Quel'Serrar", kind = "misc", art = "DireMaul", goal = 7509 },
	{ id = "thunderfury", name = "Thunderfury", kind = "misc", art = "MoltenCore", goal = 7787 },
	{ id = "sleeping-bag", name = "Cozy Sleeping Bag", kind = "misc", goal = 79976, reward = 211527 },
}
