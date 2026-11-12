-- Reads QuestieDB's baked data (the QuestieDB_<Flavor>.toc file) outside the game.
--
-- Store format, as read by QuestieDB's own src/read/baked.lua:
--   ## X-Quest-<id>-S: base64(CBOR)  scalar row: [fieldIndex] = value, p = bitmask of table fields
--   ## X-Quest-<id>-<n>: base64(CBOR) table field n
--   A value of the form ~N~ means the real value is split over <key>-1 .. <key>-N.
--   Npc, Object and Item records use the same layout.
--
-- Not applied here: QuestieDB's runtime fixes (src/corrections).

local base64 = require("base64")
local cbor = require("cbor")

local qdb = {}

-- Per record type: field names by index, and which fields are stored as tables.
local function schema(prefix, names, tables)
	local isTable = {}
	for _, i in ipairs(tables) do isTable[i] = true end
	return { prefix = prefix, names = names, isTable = isTable }
end

local SCHEMA = {
	quest = schema("X-Quest-", {
		"name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces",
		"requiredClasses", "objectivesText", "triggerEnd", "objectives", "sourceItemId",
		"preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo",
		"zoneOrSort", "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSourceItems",
		"nextQuestInChain", "questFlags", "specialFlags", "parentQuest", "reputationReward",
		"breadcrumbForQuestId", "breadcrumbs", "extraObjectives", "requiredSpell",
		"requiredSpecialization", "requiredMaxLevel", "availableUntilCompleted",
		"availableStartingWith", "requiredRanks", "disabledByQuest",
	}, { 2, 3, 8, 9, 10, 12, 13, 14, 15, 16, 18, 19, 20, 21, 26, 28, 29, 35 }),
	npc = schema("X-Npc-", {
		"name", "minLevelHealth", "maxLevelHealth", "minLevel", "maxLevel", "rank", "spawns",
		"waypoints", "zoneID", "questStarts", "questEnds", "factionID", "friendlyToFaction",
		"subName", "npcFlags",
	}, { 7, 8, 10, 11 }),
	object = schema("X-Object-", {
		"name", "questStarts", "questEnds", "spawns", "zoneID", "factionID", "waypoints",
	}, { 2, 3, 4, 7 }),
	item = schema("X-Item-", {
		"name", "npcDrops", "objectDrops", "itemDrops", "startQuest", "questRewards", "flags",
		"foodType", "itemLevel", "requiredLevel", "ammoType", "class", "subClass", "vendors",
		"relatedQuests", "teachesSpell",
	}, { 2, 3, 4, 6, 14, 15 }),
}

local DB = {}
DB.__index = DB

-- Open from an iterator of text lines.
function qdb.fromLines(lines)
	local store = {}
	for line in lines do
		local key, value = line:match("^## (X%-[^:]+): (.*)$")
		if key then store[key] = (value:gsub("\r$", "")) end
	end
	return setmetatable({ store = store }, DB)
end

function qdb.open(tocPath)
	local f = assert(io.open(tocPath, "r"))
	local db = qdb.fromLines(f:lines())
	f:close()
	return db
end

function DB:stored(key)
	local value = self.store[key]
	if not value then return nil end
	local parts = value:match("^~(%d+)~$")
	if not parts then return value end
	local buf = {}
	for i = 1, tonumber(parts) do
		buf[i] = self.store[key .. "-" .. i] or error("qdb: missing part " .. i .. " of " .. key)
	end
	return table.concat(buf)
end

function DB:meta(key)
	return self.store["X-" .. key]
end

-- One record as a table of named fields, or nil.
function DB:record(kind, id)
	local s = SCHEMA[kind] or error("qdb: unknown record type " .. tostring(kind))
	local raw = self:stored(s.prefix .. id .. "-S")
	if not raw then return nil end
	local row = cbor.decode(base64.decode(raw))
	local rec = { id = id }
	for index, name in ipairs(s.names) do
		if s.isTable[index] then
			local present = row.p and math.floor(row.p / 2 ^ (index - 1)) % 2 == 1
			if present then
				local field = self:stored(s.prefix .. id .. "-" .. index)
				if field then rec[name] = cbor.decode(base64.decode(field)) end
			end
		else
			rec[name] = row[index]
		end
	end
	return rec
end

function DB:quest(id) return self:record("quest", id) end
function DB:npc(id) return self:record("npc", id) end
function DB:object(id) return self:record("object", id) end
function DB:item(id) return self:record("item", id) end

-- Sorted list of all IDs of one record type.
function DB:ids(kind)
	local s = SCHEMA[kind] or error("qdb: unknown record type " .. tostring(kind))
	local pattern = "^" .. s.prefix:gsub("%-", "%%-") .. "(%d+)%-S$"
	local ids = {}
	for key in pairs(self.store) do
		local id = key:match(pattern)
		if id then ids[#ids + 1] = tonumber(id) end
	end
	table.sort(ids)
	return ids
end

function DB:questIds() return self:ids("quest") end

return qdb
