-- Class quests. One line per class: the build finds every quest only that class can do and
-- splits them into chains where they do not lead to one another (see classChains in
-- tools/lib/build.lua). A chain is named after its last quest.
--
--   class   the class as the quest data stores it: warrior 1, paladin 2, hunter 4, rogue 8,
--           priest 16, shaman 64, mage 128, warlock 256, druid 1024
--   id      start of the chain IDs: "c-druid" gives "c-druid-6002"
--   name    used for the chain of loose quests: "Other Druid quests"

return {
	{ class = 1, id = "c-warrior", name = "Warrior" },
	{ class = 2, id = "c-paladin", name = "Paladin" },
	{ class = 4, id = "c-hunter", name = "Hunter" },
	{ class = 8, id = "c-rogue", name = "Rogue" },
	{ class = 16, id = "c-priest", name = "Priest" },
	{ class = 64, id = "c-shaman", name = "Shaman" },
	{ class = 128, id = "c-mage", name = "Mage" },
	{ class = 256, id = "c-warlock", name = "Warlock" },
	{ class = 1024, id = "c-druid", name = "Druid" },
}
