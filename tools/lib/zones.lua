-- Reads QuestieDB's support files: area -> map, the dungeon list, and quest XP.
-- These are Lua files written for the game, so they are read as text.

local zones = {}

local Z = {}
Z.__index = Z

local function index(self, list)
	for _, d in ipairs(list) do
		self.dungeon[d.id] = d
		for _, area in ipairs(d.areas) do self.dungeonOf[area] = d end
	end
	return self
end

-- dir: the QuestieDB folder, with a trailing slash.
function zones.load(dir, flavor)
	local base = dir .. "support/" .. (flavor or "Forever") .. "/Zones/"
	local self = setmetatable({ map = {}, dungeon = {}, dungeonOf = {}, xp = {}, areaName = {}, faction = {} }, Z)

	-- [area] = uiMapId, -- Zone name. The override table comes first in the file and wins.
	for line in io.lines(base .. "areaIdToUiMapId.lua") do
		local area, map, note = line:match("^%s*%[(%d+)%]%s*=%s*(%d+)%s*,%s*%-*%s*(.-)%s*$")
		if area then
			area = tonumber(area)
			if self.map[area] == nil then self.map[area] = tonumber(map) end
			-- Plain comments are zone names; notes about the data itself are not.
			if note ~= "" and not self.areaName[area] and not note:find("[:;,]") and not note:find("area", 1, true)
				and not note:find("fail", 1, true) then
				self.areaName[area] = note
			end
		end
	end

	-- [area] = {"Name", {other areas} or nil, parent, {{area, x, y}, ...}}
	local list = {}
	for line in io.lines(base .. "dungeons.lua") do
		if line:match("^%s*if%s") then break end -- later blocks are for other game versions
		local id, name, rest = line:match('^%s*%[(%d+)%]%s*=%s*{"([^"]+)",(.*)$')
		if id then
			id = tonumber(id)
			local d = { id = id, name = name, areas = { id }, entrances = {} }
			local alts = rest:match("^{([^}]*)}")
			if alts then
				for a in alts:gmatch("%d+") do d.areas[#d.areas + 1] = tonumber(a) end
				rest = rest:sub(#alts + 3) -- the entrances come after the list of other areas
			end
			for area, x, y in rest:gmatch("{%s*(%d+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*}") do
				d.entrances[#d.entrances + 1] = { tonumber(area), tonumber(x), tonumber(y) }
			end
			list[#list + 1] = d
		end
	end
	-- Quest XP: "[id] = {level, xp}" in the base file, "QuestXP.db[id] = {level, xp}" in the
	-- newer one, which is read second and wins.
	self.xp = {}
	local xpBase = dir .. "support/" .. (flavor or "Forever") .. "/QuestXP/"
	for _, name in ipairs({ "xpDB-classic.lua", "xpDB-traces.lua" }) do
		local f = io.open(xpBase .. name, "r")
		if f then
			for line in f:lines() do
				local id, xp = line:match("%[(%d+)%]%s*=%s*{%s*%d+%s*,%s*(%d+)%s*}")
				if id then self.xp[tonumber(id)] = tonumber(xp) end
			end
			f:close()
		end
	end
	-- Faction names, from the list of constants: ARGENT_DAWN = 529 -> "Argent Dawn".
	local f = io.open(dir .. "src/corrections/enum/factions.lua", "r")
	if f then
		local small = { of = true, the = true, ["and"] = true }
		for line in f:lines() do
			local key, id = line:match("^%s*([%u%d_]+)%s*=%s*(%d+)%s*,")
			if key then
				local words = {}
				for word in key:gmatch("[^_]+") do
					word = word:lower()
					if #words > 0 and small[word] then
						words[#words + 1] = word
					else
						words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
					end
				end
				id = tonumber(id)
				if not self.faction[id] then self.faction[id] = table.concat(words, " ") end
			end
		end
		f:close()
	end

	index(self, list)
	for id, d in pairs(self.dungeon) do self.areaName[id] = d.name end
	return self
end

-- For tests: build from plain tables.
--   map: { [area] = uiMapId }, dungeons: { { id, name, areas = {..}, entrances = { {area, x, y} } } }
function zones.from(map, dungeons, xp, areaName, faction)
	local self = setmetatable({ map = map or {}, dungeon = {}, dungeonOf = {}, xp = xp or {},
		areaName = areaName or {}, faction = faction or {} }, Z)
	index(self, dungeons or {})
	for id, d in pairs(self.dungeon) do self.areaName[id] = self.areaName[id] or d.name end
	return self
end

-- Turns a spawn (area, x, y) into something the game can point at.
-- Returns { area, map, x, y, inside }. inside = true means "in this dungeon";
-- the position is then the dungeon entrance. English names are in self.areaName
-- (some dungeon areas are QuestieDB's own IDs, which the game cannot name).
function Z:place(area, x, y)
	if not area then return nil end
	local d = self.dungeonOf[area]
	if d then
		local rec = { area = d.id, inside = true }
		local e = d.entrances[1]
		local map = e and self.map[e[1]]
		if map and map ~= 0 then rec.map, rec.x, rec.y = map, e[2], e[3] end
		return rec
	end
	local rec = { area = area }
	local map = self.map[area]
	if x and x >= 0 and map and map ~= 0 then rec.map, rec.x, rec.y = map, x, y end
	return rec
end

return zones
