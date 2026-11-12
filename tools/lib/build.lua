-- Turns chain definitions into the data the addon loads.
--
-- A definition names its goal quests, or a dungeon zone. Everything else comes from the
-- quest database: the quests before each goal, who gives them, what to kill, use and
-- collect, and what faction, class, level or reputation they need.

local chain = require("chain")

local build = { MAX_SOURCES = 5, MAX_REWARDS = 12, WEAPON = 2, ARMOR = 4 } -- the game's item classes

-- Race bits that tell the two sides apart: the classic races, and the one race each side
-- got in Forever (bits 33 and 34).
local ALLIANCE_BITS = { 1, 4, 8, 64, 2 ^ 32 }
local HORDE_BITS = { 2, 16, 32, 128, 2 ^ 33 }
-- Masks that mean "the whole side" or "everyone", not a choice of races. The classic-only
-- masks count too: old quests were written before the new races and still use them.
local WHOLE = {}
do
	local a, h, a2, h2 = 77, 178, 77 + 2 ^ 32, 178 + 2 ^ 33
	for _, mask in ipairs({ a, h, a2, h2, a + h, a2 + h2 }) do WHOLE[mask] = true end
end

-- The race mask of a quest, when it picks some races of a side. Nil when it does not.
function build.races(raceMask)
	if not raceMask or raceMask == 0 or WHOLE[raceMask] then return nil end
	return raceMask
end

local function hasAny(mask, bits)
	for _, b in ipairs(bits) do
		if math.floor(mask / b) % 2 == 1 then return true end
	end
	return false
end

function build.side(raceMask)
	if not raceMask or raceMask == 0 then return "Both" end
	local a, h = hasAny(raceMask, ALLIANCE_BITS), hasAny(raceMask, HORDE_BITS)
	if a and not h then return "Alliance" end
	if h and not a then return "Horde" end
	return "Both"
end

local KINDS = { raid = true, key = true, dungeon = true, class = true, misc = true }

local function ids(list)
	local out = {}
	for _, entry in ipairs(list or {}) do
		out[#out + 1] = type(entry) == "table" and entry[1] or entry
	end
	return out
end

-- startedBy / finishedBy: { npcIds, objectIds, itemIds }
local function giver(t)
	if not t then return nil end
	local out = {}
	if t[1] and #t[1] > 0 then out.npc = ids(t[1]) end
	if t[2] and #t[2] > 0 then out.object = ids(t[2]) end
	if t[3] and #t[3] > 0 then out.item = ids(t[3]) end
	return next(out) and out or nil
end

local function firstSpawn(spawns)
	if not spawns then return nil end
	local areas = {}
	for area in pairs(spawns) do areas[#areas + 1] = area end
	table.sort(areas)
	local area = areas[1]
	local point = area and spawns[area][1]
	if not point then return nil end
	return area, point[1], point[2]
end

local function repeatable(q)
	return q.specialFlags ~= nil and q.specialFlags % 2 == 1
end

-- Returns { chains, npcs, objects, items, problems }.
--   zones (optional): from zones.lua; gives map positions and dungeon areas.
function build.run(db, defs, zones)
	local out = { chains = {}, npcs = {}, objects = {}, items = {}, areas = {}, factions = {}, problems = {}, warnings = {} }
	local function faction(id)
		if zones and zones.faction[id] then out.factions[id] = zones.faction[id] end
	end
	local function problem(def, text)
		out.problems[#out.problems + 1] = ("%s: %s"):format(tostring(def.id), text)
	end

	local function located(rec, spawns)
		local area, x, y = firstSpawn(spawns)
		if not area then return rec end
		local p = zones and zones:place(area, x, y) or { area = area, x = x and x >= 0 and x or nil, y = x and x >= 0 and y or nil }
		rec.area, rec.map, rec.x, rec.y, rec.inside = p.area, p.map, p.x, p.y, p.inside
		if zones and zones.areaName[p.area] then out.areas[p.area] = zones.areaName[p.area] end
		return rec
	end

	local function unknown(kind, id)
		out.warnings[#out.warnings + 1] = ("%s %d is not in the database"):format(kind, id)
		return {}
	end

	local function addNpc(id)
		if out.npcs[id] then return end
		local n = db:npc(id)
		out.npcs[id] = n and located({ name = n.name }, n.spawns) or unknown("npc", id)
	end
	local function addObject(id)
		if out.objects[id] then return end
		local o = db:object(id)
		out.objects[id] = o and located({ name = o.name }, o.spawns) or unknown("object", id)
	end
	local function addItem(id)
		if out.items[id] then return end
		local it = db:item(id)
		if not it then out.items[id] = unknown("item", id) return end
		local rec = { name = it.name }
		-- Zone-wide drops have dozens of sources; listing them helps nobody.
		if it.npcDrops and #it.npcDrops > 0 and #it.npcDrops <= build.MAX_SOURCES then rec.npc = ids(it.npcDrops) end
		if it.objectDrops and #it.objectDrops > 0 and #it.objectDrops <= build.MAX_SOURCES then rec.object = ids(it.objectDrops) end
		out.items[id] = rec
		for _, npc in ipairs(rec.npc or {}) do addNpc(npc) end
		for _, object in ipairs(rec.object or {}) do addObject(object) end
	end
	local function addGiver(g)
		if not g then return end
		for _, id in ipairs(g.npc or {}) do addNpc(id) end
		for _, id in ipairs(g.object or {}) do addObject(id) end
		for _, id in ipairs(g.item or {}) do addItem(id) end
	end

	-- Reward items by quest. The database lists them on the item, so turn that around.
	local rewardsOf
	local function rewards(quest)
		if not rewardsOf then
			rewardsOf = {}
			for _, id in ipairs(db:ids("item")) do
				local it = db:item(id)
				for _, q in ipairs(it.questRewards or {}) do
					rewardsOf[q] = rewardsOf[q] or {}
					table.insert(rewardsOf[q], id)
				end
			end
		end
		return rewardsOf[quest]
	end

	-- Quests by zone, made on first use.
	local byZone
	local function questsIn(areas)
		if not byZone then
			byZone = {}
			for _, id in ipairs(db:questIds()) do
				local q = db:quest(id)
				if q.zoneOrSort then
					byZone[q.zoneOrSort] = byZone[q.zoneOrSort] or {}
					table.insert(byZone[q.zoneOrSort], q)
				end
			end
		end
		local list = {}
		for _, area in ipairs(areas) do
			for _, q in ipairs(byZone[area] or {}) do
				if not repeatable(q) then list[#list + 1] = q end
			end
		end
		table.sort(list, function(a, b)
			local la, lb = a.requiredLevel or 0, b.requiredLevel or 0
			if la ~= lb then return la < lb end
			return a.id < b.id
		end)
		local out = {}
		for i, q in ipairs(list) do out[i] = q.id end
		return out
	end

	-- Weapons and armor by the creature that drops them, and those creatures by dungeon.
	-- Made on first use. Zone-wide drops are left out, as for quest items.
	local lootOf, insideOf
	local function lootIndex()
		if lootOf then return end
		lootOf, insideOf = {}, {}
		for _, id in ipairs(db:ids("item")) do
			local it = db:item(id)
			local gear = it.class == build.WEAPON or it.class == build.ARMOR
			if gear and it.npcDrops and #it.npcDrops > 0 and #it.npcDrops <= build.MAX_SOURCES then
				for _, npc in ipairs(ids(it.npcDrops)) do
					lootOf[npc] = lootOf[npc] or {}
					table.insert(lootOf[npc], id)
				end
			end
		end
		for npc, list in pairs(lootOf) do
			table.sort(list)
			local n = zones and db:npc(npc)
			for area in pairs(n and n.spawns or {}) do
				local d = zones.dungeonOf[area]
				if d then
					insideOf[d.id] = insideOf[d.id] or {}
					insideOf[d.id][npc] = true
				end
			end
		end
	end

	-- What may drop along the way: gear from the creatures the steps send you to kill, and for
	-- a dungeon chain from everything else in that dungeon that drops at least two pieces.
	-- Returns { { npc, item, item, ... }, ... } or nil.
	local function loot(c, dungeon)
		lootIndex()
		local order, taken = {}, {}
		local function take(npc)
			if lootOf[npc] and not taken[npc] then
				taken[npc] = true
				order[#order + 1] = npc
			end
		end
		for _, step in ipairs(c.steps) do
			for _, npc in ipairs(step.kill or {}) do take(npc) end
			for _, item in ipairs(step.items or {}) do
				for _, npc in ipairs(out.items[item] and out.items[item].npc or {}) do take(npc) end
			end
		end
		if dungeon then
			local rest = {}
			for npc in pairs(insideOf[dungeon.id] or {}) do
				if not taken[npc] and #lootOf[npc] >= 2 then rest[#rest + 1] = npc end
			end
			table.sort(rest, function(a, b)
				if #lootOf[a] ~= #lootOf[b] then return #lootOf[a] > #lootOf[b] end
				return a < b
			end)
			for _, npc in ipairs(rest) do take(npc) end
		end
		if #order == 0 then return nil end
		local list = {}
		for _, npc in ipairs(order) do
			addNpc(npc)
			local row = { npc }
			for _, item in ipairs(lootOf[npc]) do row[#row + 1] = item end
			list[#list + 1] = row
		end
		return list
	end

	local seen, claimed, slots = {}, {}, {}
	local function one(def, slot)
		if type(def.id) ~= "string" or def.id == "" then
			problem(def, "needs an id")
		elseif seen[def.id] then
			problem(def, "id used twice")
		end
		seen[def.id or false] = true
		if type(def.name) ~= "string" then problem(def, "needs a name") end
		if not KINDS[def.kind] then problem(def, "unknown kind " .. tostring(def.kind)) end

		-- Goals: one quest, a list, or every quest of a dungeon zone.
		local goals, ok = {}, true
		local dungeon
		if def.zone then
			dungeon = zones and zones.dungeon[def.zone]
			for _, id in ipairs(questsIn(dungeon and dungeon.areas or { def.zone })) do
				if not claimed[id] then goals[#goals + 1] = id end
			end
			if #goals == 0 then problem(def, "no quests found for zone " .. tostring(def.zone)) ok = false end
		elseif def.goals then
			goals = def.goals
		elseif def.goal then
			goals = { def.goal }
		elseif not def.reward then
			problem(def, "needs a goal, goals, zone or reward")
			ok = false
		end
		for _, goal in ipairs(goals) do
			if type(goal) ~= "number" or not db:quest(goal) then
				problem(def, "goal quest " .. tostring(goal) .. " is not in the database")
				ok = false
			end
		end

		if ok then
			local c = { id = def.id, name = def.name, kind = def.kind, steps = {} }
			if def.any then c.any = true end
			if def.note then c.note = def.note end
			if def.art then c.art = def.art end
			if def.classes then c.classes = def.classes end -- the whole chain is for these classes
			if def.side then
				c.side = def.side
			elseif #goals == 1 then
				c.side = build.side(db:quest(goals[1]).requiredRaces)
			else
				c.side = "Both"
			end
			if def.zone then
				local p = zones and zones:place(def.zone)
				c.at = p and { area = p.area, map = p.map, x = p.x, y = p.y } or { area = def.zone }
				if zones and zones.areaName[c.at.area] then out.areas[c.at.area] = zones.areaName[c.at.area] end
			end

			for _, node in ipairs(chain.build(db, goals)) do
				if node.missing then
					problem(def, "quest " .. node.id .. " is not in the database")
				else
					local q = db:quest(node.id)
					local side = build.side(q.requiredRaces)
					if side ~= "Both" and c.side ~= "Both" and c.side ~= side then
						problem(def, ("quest %d is %s only, chain is %s"):format(node.id, side, c.side))
					end
					local step = { quest = node.id, name = q.name, min = q.requiredLevel, level = q.questLevel }
					if node.goal then step.goal = true end
					if side ~= "Both" and c.side == "Both" then step.side = side end
					step.races = build.races(q.requiredRaces)
					if q.requiredClasses and q.requiredClasses > 0 then step.classes = q.requiredClasses end
					if q.requiredMinRep and q.requiredMinRep[1] then
						step.rep = { q.requiredMinRep[1], q.requiredMinRep[2] or 0 }
						faction(step.rep[1])
					end
					if #node.all > 0 then step.all = node.all end
					if #node.any > 0 then step.any = node.any end
					step.from, step.to = giver(q.startedBy), giver(q.finishedBy)
					addGiver(step.from)
					addGiver(step.to)
					local o = q.objectives or {}
					local kill, use, items = ids(o[1]), ids(o[2]), ids(o[3])
					if #kill > 0 then step.kill = kill end
					if #use > 0 then step.use = use end
					if #items > 0 then step.items = items end
					for _, id in ipairs(kill) do addNpc(id) end
					for _, id in ipairs(use) do addObject(id) end
					for _, id in ipairs(items) do addItem(id) end
					-- What the quest gives.
					local gives = rewards(node.id)
					if gives and #gives > 0 and #gives <= build.MAX_REWARDS then
						step.rewards = gives
						for _, id in ipairs(gives) do addItem(id) end
					end
					if q.reputationReward and #q.reputationReward > 0 then
						step.repGain = {}
						for _, pair in ipairs(q.reputationReward) do
							step.repGain[#step.repGain + 1] = { pair[1], pair[2] }
							faction(pair[1])
						end
					end
					if zones and zones.xp and zones.xp[node.id] then step.xp = zones.xp[node.id] end
					if step.min and (not c.level or step.min < c.level) then c.level = step.min end
					c.steps[#c.steps + 1] = step
					if not def.zone then claimed[node.id] = true end
				end
			end
			if def.reward then
				local it = db:item(def.reward)
				if not it then
					problem(def, "reward item " .. tostring(def.reward) .. " is not in the database")
				else
					c.reward = def.reward
					addItem(def.reward)
				end
			end
			c.loot = loot(c, dungeon)
			slots[slot] = c
		end
	end

	-- A class definition ({ class = bit, id = prefix, name = "Druid" }) stands for many chains:
	-- the quests only that class can do, split where they do not lead to one another. Each
	-- group that has more than one quest is a chain named after its last quest; the loose
	-- quests share one chain. Returns a list of plain definitions.
	local function classChains(def)
		local list, set = {}, {}
		for _, id in ipairs(db:questIds()) do
			local q = db:quest(id)
			if q.requiredClasses == def.class and not repeatable(q) and not claimed[id] then
				list[#list + 1] = q
				set[id] = true
			end
		end
		-- group quests joined by "comes before"
		local root, leads = {}, {}
		local function find(id)
			while root[id] ~= id do
				root[id] = root[root[id]]
				id = root[id]
			end
			return id
		end
		for _, q in ipairs(list) do root[q.id] = q.id end
		for _, q in ipairs(list) do
			for _, field in ipairs({ "preQuestGroup", "preQuestSingle" }) do
				for _, pre in ipairs(q[field] or {}) do
					pre = math.abs(pre)
					if set[pre] then
						leads[pre] = true
						root[find(q.id)] = find(pre)
					end
				end
			end
		end
		local groups, order = {}, {}
		for _, q in ipairs(list) do
			local key = find(q.id)
			if not groups[key] then
				groups[key] = {}
				order[#order + 1] = key
			end
			table.insert(groups[key], q)
		end

		local made, loose = {}, {}
		for _, key in ipairs(order) do
			local group = groups[key]
			if #group == 1 then
				loose[#loose + 1] = group[1].id
			else
				-- the goals are the quests nothing in the group comes after
				local goals, last, from = {}, nil, nil
				for _, q in ipairs(group) do
					local level = q.requiredLevel or 0
					if not from or level < from then from = level end
					if not leads[q.id] then
						goals[#goals + 1] = q.id
						if not last or level > (last.requiredLevel or 0) or (level == (last.requiredLevel or 0) and q.id > last.id) then last = q end
					end
				end
				table.sort(goals)
				made[#made + 1] = { id = def.id .. "-" .. last.id, name = last.name, kind = "class", goals = goals,
					classes = def.class, art = def.art, from = from }
			end
		end
		table.sort(made, function(a, b)
			if a.from ~= b.from then return a.from < b.from end
			return a.id < b.id
		end)
		if #loose > 0 then
			table.sort(loose)
			made[#made + 1] = { id = def.id .. "-other", name = "Other " .. def.name .. " quests", kind = "class",
				goals = loose, classes = def.class, art = def.art }
		end
		return made
	end

	-- Chains with named goals go first, so class and dungeon lists can leave their quests out.
	-- Then the classes, then the dungeons.
	local madeFor = {}
	for _, def in ipairs(defs) do
		if not def.zone and not def.class then one(def, def) end
	end
	for _, def in ipairs(defs) do
		if def.class then
			if type(def.id) ~= "string" or type(def.name) ~= "string" then
				problem(def, "a class definition needs an id and a name")
			else
				madeFor[def] = classChains(def)
				for _, made in ipairs(madeFor[def]) do one(made, made) end
			end
		end
	end
	for _, def in ipairs(defs) do
		if def.zone then one(def, def) end
	end
	for _, def in ipairs(defs) do
		for _, made in ipairs(madeFor[def] or { def }) do
			if slots[made] then out.chains[#out.chains + 1] = slots[made] end
		end
	end
	return out
end

-- Lua writer with a fixed key order, so the same input always gives the same file.

local function isArray(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	for i = 1, n do
		if t[i] == nil then return false end
	end
	return true
end

local function value(v)
	local tv = type(v)
	if tv == "string" then return ("%q"):format(v) end
	if tv == "number" then
		if v == math.floor(v) then return ("%.0f"):format(v) end
		return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
	end
	if tv == "boolean" then return tostring(v) end
	if tv == "table" then
		local parts = {}
		if isArray(v) then
			for i, x in ipairs(v) do parts[i] = value(x) end
		else
			local keys = {}
			for k in pairs(v) do keys[#keys + 1] = k end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, k in ipairs(keys) do
				local key = type(k) == "number" and ("[%d]"):format(k) or k
				parts[#parts + 1] = key .. " = " .. value(v[k])
			end
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	error("build: cannot write " .. tv)
end

local CHAIN_KEYS = { "id", "name", "kind", "side", "classes", "level", "reward", "any", "note", "art", "at", "loot" }
local STEP_KEYS = { "quest", "name", "goal", "min", "level", "side", "races", "classes", "rep", "all", "any", "from", "to", "kill", "use", "items", "rewards", "repGain", "xp" }

local function fields(rec, keys)
	local parts = {}
	for _, key in ipairs(keys) do
		if rec[key] ~= nil then parts[#parts + 1] = key .. " = " .. value(rec[key]) end
	end
	return table.concat(parts, ", ")
end

local function lookup(lines, name, map)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "ns." .. name .. " = {"
	local keys = {}
	for id in pairs(map) do keys[#keys + 1] = id end
	table.sort(keys)
	for _, id in ipairs(keys) do
		lines[#lines + 1] = ("\t[%d] = %s,"):format(id, value(map[id]))
	end
	lines[#lines + 1] = "}"
end

function build.render(result, source)
	local lines = {
		"-- Generated by tools/build.lua. Do not edit.",
		"-- Quest data: " .. (source or "QuestieDB") .. " (GPL-3.0).",
		"",
		"local _, ns = ...",
		"",
		"ns.Chains = {",
	}
	for _, c in ipairs(result.chains) do
		lines[#lines + 1] = "\t{"
		lines[#lines + 1] = "\t\t" .. fields(c, CHAIN_KEYS) .. ","
		lines[#lines + 1] = "\t\tsteps = {"
		for _, step in ipairs(c.steps) do
			lines[#lines + 1] = "\t\t\t{ " .. fields(step, STEP_KEYS) .. " },"
		end
		lines[#lines + 1] = "\t\t},"
		lines[#lines + 1] = "\t},"
	end
	lines[#lines + 1] = "}"
	lookup(lines, "Npcs", result.npcs)
	lookup(lines, "Objects", result.objects)
	lookup(lines, "Items", result.items)
	-- English names, used only when the game cannot give its own.
	lookup(lines, "Areas", result.areas)
	lookup(lines, "Factions", result.factions)
	lines[#lines + 1] = ""
	return table.concat(lines, "\n")
end

return build
