-- Dungeon quest chains. Each takes every quest of the dungeon's zone, plus the quests
-- that lead to them. Order here is the order in the list.
--
-- Five dungeons new in Forever have no zone in the quest database. They use `mentions`:
-- every quest whose name or objective text holds one of the phrases is a goal.
-- `skip` lists quest IDs that match but do not belong.
--
-- `new` marks a dungeon that is new in Forever: the list shows an infinity sign by its name.

return {
	{ id = "d-hall-of-thanes", name = "The Hall of Thanes", kind = "dungeon", art = "Dungeon", zone = 16919, new = true },
	{ id = "d-ragefire", name = "Ragefire Chasm", kind = "dungeon", art = "RagefireChasm", zone = 2437 },
	{ id = "d-lordaeron", name = "Ruins of Lordaeron", kind = "dungeon", art = "RuinsOfLordaeronBattlegrounds", zone = 16611, new = true },
	{ id = "d-deadmines", name = "The Deadmines", kind = "dungeon", art = "Deadmines", zone = 1581 },
	{ id = "d-wailing-caverns", name = "Wailing Caverns", kind = "dungeon", art = "WailingCaverns", zone = 718 },
	{ id = "d-shadowfang", name = "Shadowfang Keep", kind = "dungeon", art = "ShadowFangKeep", zone = 209 },
	{ id = "d-excavation", name = "Excavation Site", kind = "dungeon", art = "Dungeon", zone = 16732, new = true },
	{ id = "d-blackfathom", name = "Blackfathom Deeps", kind = "dungeon", art = "BlackfathomDeeps", zone = 719 },
	{ id = "d-stockade", name = "The Stockade", kind = "dungeon", art = "StormwindStockade", zone = 717 },
	{ id = "d-dalaran", name = "City of Dalaran", kind = "dungeon", art = "Dungeon", zone = 16544, new = true },
	{ id = "d-drowned-city", name = "The Drowned City", kind = "dungeon", art = "Dungeon", mentions = { "Drowned City" }, new = true, note = "Work in progress: this information may still be incomplete." },
	{ id = "d-razorfen-kraul", name = "Razorfen Kraul", kind = "dungeon", art = "RazorfenKraul", zone = 491 },
	{ id = "d-gnomeregan", name = "Gnomeregan", kind = "dungeon", art = "Gnomeregan", zone = 721 },
	{ id = "d-scarlet-monastery", name = "Scarlet Monastery", kind = "dungeon", art = "Monastery", zone = 796 },
	{ id = "d-razorfen-downs", name = "Razorfen Downs", kind = "dungeon", art = "RazorfenDowns", zone = 722 },
	{ id = "d-uldaman", name = "Uldaman", kind = "dungeon", art = "Uldaman", zone = 1337 },
	{ id = "d-kroldok", name = "Krol'dok Stronghold", kind = "dungeon", art = "Dungeon", mentions = { "Krol'dok" }, new = true, note = "Work in progress: this information may still be incomplete." },
	{ id = "d-zulfarrak", name = "Zul'Farrak", kind = "dungeon", art = "ZulFarrak", zone = 1176 },
	{ id = "d-maraudon", name = "Maraudon", kind = "dungeon", art = "Maraudon", zone = 2100 },
	{ id = "d-sunken-temple", name = "The Temple of Atal'Hakkar", kind = "dungeon", art = "SunkenTemple", zone = 1477 },
	{ id = "d-alcaz", name = "Alcaz Prison", kind = "dungeon", art = "Dungeon", mentions = { "Alcaz" }, skip = { 8970 }, new = true, note = "Work in progress: this information may still be incomplete." },
	{ id = "d-blackmaw", name = "Blackmaw Hold", kind = "dungeon", art = "Dungeon", mentions = { "Blackmaw" }, new = true, note = "Work in progress: this information may still be incomplete." },
	{ id = "d-blackrock-depths", name = "Blackrock Depths", kind = "dungeon", art = "BlackrockDepths", zone = 1584 },
	{ id = "d-dire-maul", name = "Dire Maul", kind = "dungeon", art = "DireMaul", zone = 2557 },
	-- The database has one zone for the whole spire. The upper half is the quests named
	-- here; the lower half is the rest of the zone. (The id is older than the split.)
	{ id = "d-blackrock-spire", name = "Lower Blackrock Spire", kind = "dungeon", art = "BlackrockSpire", zone = 1583 },
	{ id = "d-ubrs", name = "Upper Blackrock Spire", kind = "dungeon", art = "BlackrockSpire",
		goals = { 5102, 5127, 4734, 4735, 4764, 4768, 5160, 5047 } },
	{ id = "d-scholomance", name = "Scholomance", kind = "dungeon", art = "Scholomance", zone = 2057 },
	{ id = "d-shapers-terrace", name = "The Shaper's Terrace", kind = "dungeon", art = "Dungeon", mentions = { "Shaper's Terrace" }, new = true, note = "Work in progress: this information may still be incomplete." },
	{ id = "d-stratholme", name = "Stratholme", kind = "dungeon", art = "Strathome", zone = 2017 },
}
