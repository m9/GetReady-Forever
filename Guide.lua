local _, ns = ...

-- A chain as a walk-through: every thing to do, in an order that works, a line each,
-- grouped by the place it is done in. No frames here.
--
-- Each quest gives lines: accept it, kill, use and get what it asks for, turn it in. The
-- order is made by walking the chain: a line can come once the lines it waits for have
-- (a quest's earlier quests turned in, the quest accepted, its things done). Of the lines
-- that can come, the next is picked so the player travels little:
--   1. what is in the place the player stands in: accept, then things to do, then turn in
--   2. else what is outdoors elsewhere: things to do and quests to accept, then turn-ins
--   3. else what is inside a dungeon
-- So everything that can be picked up is in the log before a dungeon, and a dungeon's
-- quests are handed in after it, together.
-- The order does not change with what the player has done; done lines are only marked.
-- A place is a zone or a dungeon: the data knows no smaller one.

local Guide = {}
ns.Guide = Guide

local LABEL = { accept = "Accept", turnin = "Turn in", kill = "Kill", find = "Find", use = "Use",
	loot = "Loot", take = "Take", get = "Get" }

-- Words that make a creature a quest names one to kill. Without them it is one to find:
-- the database also lists creatures to free, to talk to or to follow.
local KILL_WORDS = { "slay", "kill", "defeat", "destroy", "eliminate", "slaughter", "exterminate",
	"dispatch", "hunt", "assassinate", "vanquish", "execute", "put an end", "to rest", "subdue", "thin " }

local function killing(text)
	text = (text or ""):lower()
	if text == "" then return true end
	for _, word in ipairs(KILL_WORDS) do
		if text:find(word, 1, true) then return true end
	end
	return false
end

local function questName(step)
	return (step.quest > 0 and ns.api.QuestName(step.quest)) or step.name or ("Quest " .. step.quest)
end

-- The first record with a name: a quest giver, or who has an item.
local function first(ids, map)
	for _, id in ipairs(ids or {}) do
		if map[id] and map[id].name then return map[id] end
	end
end

-- Dungeons by their English name, as quest text has them: { { name, area } }, long names
-- first. Read from the creatures and objects that stand inside one. Made once per data set.
local dungeonsOf, dungeonList
local function dungeons()
	if dungeonsOf == ns.Npcs then return dungeonList end
	local seen, list = {}, {}
	for _, map in ipairs({ ns.Npcs or {}, ns.Objects or {} }) do
		for _, rec in pairs(map) do
			local name = rec.inside and rec.area and ns.Areas and ns.Areas[rec.area]
			if name and not seen[name] then
				seen[name] = true
				list[#list + 1] = { name = name, area = rec.area }
			end
		end
	end
	table.sort(list, function(a, b)
		if #a.name ~= #b.name then return #a.name > #b.name end
		return a.name < b.name
	end)
	dungeonsOf, dungeonList = ns.Npcs, list
	return list
end

-- The dungeon a quest's words send the player into, for a thing whose place the database
-- does not have: the chain's own dungeon first, then any other. Returns its name, or nil.
local function dungeonInText(chain, text)
	if not text or text == "" then return nil end
	if chain.kind == "dungeon" or chain.kind == "raid" then
		local own = chain.at and chain.at.area and ns.Areas and ns.Areas[chain.at.area]
		if own and text:find(own, 1, true) then return ns.Progress.AreaName(chain.at.area) or own end
		if text:find(chain.name, 1, true) then return chain.name end
	end
	for _, d in ipairs(dungeons()) do
		if text:find(d.name, 1, true) then return ns.Progress.AreaName(d.area) or d.name end
	end
end

-- Where a creature or object is: place name, inside a dungeon?, "12.3, 45.6", map pin.
local function locate(rec)
	if not rec or not rec.area then return nil end
	local name = ns.Progress.AreaName(rec.area)
	if not name then
		if not rec.inside then return nil end
		name = "Dungeon"
	end
	if rec.inside then return name, true end
	local at, target
	if rec.x then
		at = ("%.1f, %.1f"):format(rec.x, rec.y)
		if rec.map then target = { map = rec.map, x = rec.x, y = rec.y, name = rec.name } end
	end
	return name, false, at, target
end

-- Returns {
--   blocks  { { place, inside, done, lines = { line } } }  place is nil when it is not known
--   total, left   lines in all, and lines still to do
-- }
-- line: {
--   n        its number, counted through the whole guide
--   kind     accept, turnin, kill, find, use, loot, take or get
--   label    the word for the kind: "Accept", "Kill", ...
--   name     the quest, creature, object or item
--   tail     " from Giver", " to Taker", " from Boss" or ""
--   at       "12.3, 45.6" or nil
--   of       for a thing to do: the name of the quest that asks for it
--   part     for a thing to do: which of the step's parts it is (View.lua's step.parts)
--   note     for accept: what the quest asks, in the quest's own words
--   level    the level the quest asks for, when the player is below it (accept only)
--   optional true for a quest that only leads to another (accept only)
--   quest    the step's quest ID
--   done     behind the player
--   now      the first line still to do
--   target   { map, x, y, name } for a map pin, or nil
-- }
--   progress: from Progress.Chain, or a table with steps and states
function Guide.Build(chain, progress)
	local api = ns.api
	progress = progress or ns.Progress.Chain(chain)
	local steps = progress.steps
	local playerLevel = api.Level()

	local index, known = {}, {}
	for _, step in ipairs(chain.steps or {}) do known[step.quest] = true end
	for i, step in ipairs(steps) do index[step.quest] = i end

	-- Quests of one name that a later quest needs any one of are the same quest in several
	-- forms. One is kept: the one in the log or done, else the first. twin[i] is the kept
	-- step that stands for step i.
	local twin = {}
	for _, step in ipairs(steps) do
		local byName = {}
		for _, quest in ipairs(step.any or {}) do
			local at = index[quest]
			if at then
				local name = steps[at].name or quest
				byName[name] = byName[name] or {}
				table.insert(byName[name], at)
			end
		end
		for _, list in pairs(byName) do
			if #list > 1 then
				table.sort(list)
				local keep = list[1]
				for _, at in ipairs(list) do
					local state = progress.states[at]
					if state == "done" or state == "active" then keep = at break end
				end
				for _, at in ipairs(list) do
					if at ~= keep then twin[at] = keep end
				end
			end
		end
	end

	local acts, todo = {}, {}
	local function add(act)
		act.order = #acts + 1
		acts[#acts + 1] = act
		return act
	end

	for i, step in ipairs(steps) do
		local state = progress.states[i]
		local finished = state == "done" or state == "skipped"
		local inLog = state == "active"
		local complete = inLog and step.quest > 0 and api.QuestComplete(step.quest) or false
		local name = questName(step)
		local real = step.quest > 0 -- the made-up step of an item chain has no quest to accept
		local shown = not twin[i]
		todo[i] = 0

		local function place(act, rec)
			act.place, act.inside, act.at, act.target = locate(rec)
			return act
		end
		-- The things a step asks for are counted as View.lua counts a step's parts (kill, use,
		-- then items, those with a name), so a line can say which part it is.
		local part = 0
		local function thing(kind, thingName, rec, tail, done)
			local act = place({ phase = "do", kind = kind, name = thingName, tail = tail or "", of = real and name or nil,
				part = part, done = finished or complete or done or false }, rec)
			if not act.place then
				act.place = dungeonInText(chain, step.text)
				act.inside = act.place ~= nil
			end
			act.step = i
			todo[i] = todo[i] + 1
			add(act)
		end

		if real and shown then
			local giver = first(step.from and step.from.npc, ns.Npcs) or first(step.from and step.from.object, ns.Objects)
			local tail = giver and (" from " .. giver.name) or ""
			if not giver then
				-- a quest an item starts: the place is where the item drops
				local item = first(step.from and step.from.item, ns.Items)
				if item then
					giver = first(item.npc, ns.Npcs) or first(item.object, ns.Objects)
					tail = " from the item " .. item.name .. (giver and (" (" .. giver.name .. ")") or "")
				end
			end
			local act = place({ phase = "accept", kind = "accept", name = name, tail = tail, note = step.text,
				optional = step.optional or nil, done = finished or inLog }, giver)
			act.step = i
			if not act.done and step.min and playerLevel < step.min then act.needLevel = step.min end
			add(act)
		end

		local kill = killing(step.text) and "kill" or "find"
		-- (an item chain's made-up step lists who has the item as things to kill or use; the
		-- item's own line says that already)
		for _, id in ipairs(shown and step.kill or {}) do
			local npc = ns.Npcs[id]
			if npc and npc.name then
				part = part + 1
				if real then thing(kill, npc.name, npc) end
			end
		end
		for _, id in ipairs(shown and step.use or {}) do
			local object = ns.Objects[id]
			if object and object.name then
				part = part + 1
				if real then thing("use", object.name, object) end
			end
		end
		for _, id in ipairs(shown and step.items or {}) do
			local item = ns.Items[id]
			if item and item.name then
				part = part + 1
				local npc = first(item.npc, ns.Npcs)
				local from = npc or first(item.object, ns.Objects)
				thing(npc and "loot" or (from and "take" or "get"), api.ItemName(id) or item.name, from,
					from and (" from " .. from.name) or "",
					(inLog or not real) and api.ItemCount(id) > 0)
			end
		end

		if real and shown then
			local taker = first(step.to and step.to.npc, ns.Npcs) or first(step.to and step.to.object, ns.Objects)
			local act = place({ phase = "turnin", kind = "turnin", name = name, tail = taker and (" to " .. taker.name) or "",
				done = finished }, taker)
			act.step = i
			add(act)
		end
	end

	-- The walk.
	local accepted, turned = {}, {}
	local function cleared(quest)
		local at = index[quest]
		if at then return turned[twin[at] or at] or false end
		if known[quest] then return api.QuestDone(quest) or ns.StepMarked(quest) end
		return true
	end
	local function ready(act)
		local step = steps[act.step]
		if act.phase == "accept" then
			for _, quest in ipairs(step.all or {}) do
				if index[quest] and not cleared(quest) then return false end
			end
			if step.any and #step.any > 0 then
				for _, quest in ipairs(step.any) do
					if cleared(quest) then return true end
				end
				return false
			end
			return true
		end
		if step.quest > 0 and not accepted[act.step] then return false end
		if act.phase == "turnin" then return todo[act.step] == 0 end
		return true
	end

	local HERE = { accept = 1, ["do"] = 2, turnin = 3 }
	local guide = { blocks = {}, total = #acts, left = 0 }
	local here, block, hasNow = nil, nil, false
	for n = 1, #acts do
		local best, bestRank
		for _, act in ipairs(acts) do
			if not act.used and ready(act) then
				local rank
				if (act.place and act.place == here) or (not act.place and here) then
					rank = HERE[act.phase]
				elseif not act.place then
					rank = 50 + HERE[act.phase] -- no place known and none to stay in yet: after a line that has one
				elseif act.inside then
					rank = 20
				else
					rank = act.phase == "turnin" and 11 or 10
				end
				if not bestRank or rank < bestRank then best, bestRank = act, rank end
			end
		end
		if not best then
			-- nothing can come: a quest waits for one the character cannot do. Take it anyway.
			for _, act in ipairs(acts) do
				if not act.used then best = act break end
			end
		end
		best.used = true
		if best.phase == "accept" then accepted[best.step] = true
		elseif best.phase == "turnin" then turned[best.step] = true
		else todo[best.step] = todo[best.step] - 1 end

		local place = best.place or here
		if not block or place ~= block.place then
			block = { place = place, inside = best.inside or false, done = true, lines = {} }
			guide.blocks[#guide.blocks + 1] = block
		end
		here = place
		local line = {
			n = n, kind = best.kind, label = LABEL[best.kind], name = best.name, tail = best.tail or "",
			at = best.at, of = best.of, part = best.part, note = best.note, level = best.needLevel, optional = best.optional,
			quest = steps[best.step].quest, done = best.done, target = best.target,
		}
		if not line.done then
			guide.left = guide.left + 1
			block.done = false
			if not hasNow then line.now, hasNow = true, true end
		end
		block.lines[#block.lines + 1] = line
	end
	return guide
end
