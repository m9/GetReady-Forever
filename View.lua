local _, ns = ...

-- Decides what the window says: every label, count and line of text, as plain data.
-- No frames here, so it can be tested without the game.

local View = {}
ns.View = View

View.GROUPS = {
	{ kind = "raid", label = "Raids" },
	{ kind = "key", label = "Keys" },
	{ kind = "dungeon", label = "Dungeons" },
	{ kind = "class", label = "Class" }, -- stands for one group per class, see classGroups
	{ kind = "misc", label = "Other" },
}

-- Classes by the bit quest data uses for them, in the game's class order.
View.CLASSES = {
	{ bit = 1, name = "Warrior" }, { bit = 2, name = "Paladin" }, { bit = 4, name = "Hunter" },
	{ bit = 8, name = "Rogue" }, { bit = 16, name = "Priest" }, { bit = 64, name = "Shaman" },
	{ bit = 128, name = "Mage" }, { bit = 256, name = "Warlock" }, { bit = 1024, name = "Druid" },
}

-- The class groups of the list: one per class that has chains to show, named after the
-- class, the player's own class first. Each has its own kind ("class-128"), so each folds
-- on its own. Chains of kind "class" that name no single class share a last group "Class".
local function classGroups(chains)
	local has, loose = {}, false
	for _, chain in ipairs(chains) do
		if chain.kind == "class" then
			if chain.classes then has[chain.classes] = true else loose = true end
		end
	end
	local own = ns.api.ClassBit()
	local groups = {}
	local function add(class)
		if has[class.bit] then
			has[class.bit] = nil
			groups[#groups + 1] = { kind = "class-" .. class.bit, label = class.name, classes = class.bit }
		end
	end
	for _, class in ipairs(View.CLASSES) do
		if class.bit == own then add(class) end
	end
	for _, class in ipairs(View.CLASSES) do add(class) end
	if loose or next(has) then groups[#groups + 1] = { kind = "class", label = "Class" } end
	return groups
end

-- Is this chain in this group of the list?
local function inGroup(chain, group, named)
	if group.classes then return chain.kind == "class" and chain.classes == group.classes end
	if group.kind == "class" then return chain.kind == "class" and not named[chain.classes or false] end
	return chain.kind == group.kind
end

local ART_PATH = "Interface\\Glues\\LoadingScreens\\LoadScreen"

local KIND_LABEL = { raid = "Raid", key = "Key", dungeon = "Dungeon", class = "Class", misc = "Other" }

local function countText(progress)
	if progress.marked then return "Marked" end
	if progress.done then return "Done" end
	if progress.total == 0 then return "" end
	return progress.complete .. "/" .. progress.total
end

local function fraction(progress)
	if progress.done then return 1 end
	if progress.total == 0 then return 0 end
	return progress.complete / progress.total
end

local function questName(step)
	return ns.api.QuestName(step.quest) or step.name or ("Quest " .. step.quest)
end

-- The "what to do now" box: { label, name, lines, target, state }.
-- state is the step state the box is about, for its color: done, active, ready or locked.
local function nextBox(chain, progress)
	local Progress = ns.Progress
	if progress.done then
		-- one word says it; a second line would only repeat it
		return { label = progress.marked and "Marked as done" or "Completed",
			lines = {}, state = "done" }
	end
	if progress.total == 0 then
		local lines = Progress.RewardHints(chain)
		local name = table.remove(lines, 1) or chain.name
		return { label = "To do", name = name, lines = lines, state = "ready" }
	end
	local step, state, i = Progress.Next(chain, progress)
	if step then
		local lines = Progress.Hints(step, state, progress.need[i])
		lines[#lines + 1] = Progress.RewardLine(step)
		lines[#lines + 1] = Progress.GainLine(step)
		return {
			label = state == "active" and (ns.api.QuestComplete(step.quest) and "Ready to turn in" or "In your quest log") or "Next step",
			mark = (state == "active" and ns.api.QuestComplete(step.quest)) and "turnin" or state,
			name = questName(step),
			lines = lines,
			target = Progress.Target(step, state),
			state = state,
		}
	end
	-- Nothing can be started: say why the first open step is locked.
	for j, state in ipairs(progress.states) do
		if state == "locked" and progress.need[j] then
			return {
				label = "Not available yet",
				name = questName(progress.steps[j]),
				lines = Progress.Hints(progress.steps[j], state, progress.need[j]),
				state = "locked",
			}
		end
	end
	return { label = "Not available yet", lines = {}, state = "locked" }
end

-- Where a quest's page is on the web. The game cannot open it, so the window shows the
-- address for the player to copy.
local QUEST_LINK = "https://www.wowhead.com/forever/quest=%d"
local ZONE_LINK = "https://www.wowhead.com/forever/zone=%d"
local ITEM_LINK = "https://www.wowhead.com/forever/item=%d"

-- The page that is about the chain as a whole: its dungeon, else the item it is for, else
-- its one goal quest. Nil when it has none of these.
local function chainLink(chain)
	if chain.at and chain.at.area then return ZONE_LINK:format(chain.at.area) end
	if chain.reward then return ITEM_LINK:format(chain.reward) end
	local goal, goals = nil, 0
	for _, step in ipairs(chain.steps or {}) do
		if step.goal then goal, goals = step.quest, goals + 1 end
	end
	if goals == 1 then return QUEST_LINK:format(goal) end
	return nil
end

local STATUS = {
	done = "Turned in",
	skipped = "Not needed",
	active = "In your quest log",
	turnin = "Ready to turn in",
	ready = "Available",
	locked = "Locked",
}

-- Where each step sits when the chain is drawn as a graph, left to right.
-- Returns nil for a chain with no steps. Else {
--   cols, rows  size of the grid
--   at          { [i] = { col, row } } cell of step i
--   edges       { { from, to, lit } } step indexes; lit when the earlier step is out of the way
--   auto        true when most steps are linked and there are three columns or more
-- }
-- Columns: a step is one past its latest earlier step.
-- Rows: each step hangs under one of its earlier steps (the middle one of the nearest),
-- which makes trees. A step and the branch of it that goes on the furthest share a row, so
-- a long way through the chain is a straight line. Its other branches go on the nearest
-- row that has room for them: those that come before it in the data over it, the others
-- under it. So short side branches of a long way stand right beside it, next to one
-- another, and do not each take a row of their own.
-- Steps that are not joined to one another by any line never share rows.
-- A step nothing leads to, that only another way needs (a side road), goes on the nearest
-- free row beside the step it joins.
-- Room: a row has room when no box stands where the branch's boxes go, and none where a
-- line of it runs along the row to a step more than one column on.
--   byLevel: put the separate parts in order of the level they start at, lowest on top
--            (for a class's "Various" chain, whose quests have no order of their own)
function View.Graph(progress, byLevel)
	local steps = progress.steps
	if #steps < 1 then return nil end
	local index = {}
	for i, step in ipairs(steps) do index[step.quest] = i end

	-- which steps are joined, directly or through others: each points at another of its
	-- part, or at itself
	local group = {}
	for i in ipairs(steps) do group[i] = i end
	local function find(i)
		while group[i] ~= i do
			group[i] = group[group[i]]
			i = group[i]
		end
		return i
	end

	local col, parent, kids, edges, linked = {}, {}, {}, {}, {}
	local leads = {} -- leads[i]: the steps a line runs to from step i
	for i, step in ipairs(steps) do
		local before, seen = {}, {}
		for _, list in ipairs({ step.all or false, step.any or false }) do
			for _, quest in ipairs(list or {}) do
				local j = index[quest]
				-- steps come with earlier quests first; anything else is not drawn
				if j and j < i and not seen[j] then
					seen[j] = true
					before[#before + 1] = j
				end
			end
		end
		table.sort(before)
		local last = 0
		for _, j in ipairs(before) do if col[j] > last then last = col[j] end end
		col[i] = last + 1
		local nearest = {}
		for _, j in ipairs(before) do
			if col[j] == last then nearest[#nearest + 1] = j end
			local state = progress.states[j]
			edges[#edges + 1] = { from = j, to = i, lit = state == "done" or state == "skipped" }
			linked[i], linked[j] = true, true
			group[find(i)] = find(j)
			leads[j] = leads[j] or {}
			leads[j][#leads[j] + 1] = i
		end
		if #nearest > 0 then
			local p = nearest[math.ceil(#nearest / 2)]
			parent[i] = p
			kids[p] = kids[p] or {}
			kids[p][#kids[p] + 1] = i
		end
	end

	-- how far each step's branches go, and which branch goes the furthest (the first of them)
	local reach, main = {}, {}
	local function measure(i)
		local far, best = col[i], nil
		for _, k in ipairs(kids[i] or {}) do
			local r = measure(k)
			if not best or r > reach[best] then best = k end
			if r > far then far = r end
		end
		reach[i], main[i] = far, best
		return far
	end
	-- a step and the steps that follow it along the furthest branch: they share a row
	local function way(i)
		local list = {}
		while i do
			list[#list + 1] = i
			i = main[i]
		end
		return list
	end

	-- What stands in each cell: "box", or "line" where a line runs along the row. Each part
	-- of the chain is laid out by itself, with rows counted from its first way (they can
	-- go below 1), and then moved under the parts before it; top and bottom are the rows
	-- the part uses so far.
	local taken, row, rows = {}, {}, 0
	local top, bottom = 1, 0
	local function cell(r, c) return taken[r] and taken[r][c] end
	local function fits(list, r)
		local own = {}
		for _, n in ipairs(list) do own[col[n]] = true end
		for _, n in ipairs(list) do
			if cell(r, col[n]) then return false end
			for _, to in ipairs(leads[n] or {}) do
				for c = col[n] + 1, col[to] - 1 do
					if not own[c] and cell(r, c) == "box" then return false end
				end
			end
		end
		return true
	end
	-- The nearest row with room for a way, from row r on, going down (by = 1) or up (by = -1).
	local function room(list, r, by)
		while not fits(list, r) do r = r + by end
		return r
	end
	-- Puts a step's way on a row, then its side branches on the nearest rows with room:
	-- the branches that come before the way's own in the data over it, the others under it.
	local function put(i, r)
		local list = way(i)
		taken[r] = taken[r] or {}
		if r > bottom then bottom = r end
		if r < top then top = r end
		for _, n in ipairs(list) do
			row[n] = r
			taken[r][col[n]] = "box"
		end
		for _, n in ipairs(list) do
			for _, to in ipairs(leads[n] or {}) do
				for c = col[n] + 1, col[to] - 1 do taken[r][c] = taken[r][c] or "line" end
			end
		end
		for _, n in ipairs(list) do
			for _, k in ipairs(kids[n] or {}) do
				if k ~= main[n] then
					local by = k < main[n] and -1 or 1
					put(k, room(way(k), r + by, by))
				end
			end
		end
	end

	-- the trees, and which of them lead into another tree or are led into
	local tree, fed, feeds = {}, {}, {}
	local function own(i, root)
		tree[i] = root
		for _, k in ipairs(kids[i] or {}) do own(k, root) end
	end
	local roots = {}
	for i in ipairs(steps) do
		if not parent[i] then
			roots[#roots + 1] = i
			own(i, i)
			measure(i)
		end
	end
	for _, edge in ipairs(edges) do
		local a, b = tree[edge.from], tree[edge.to]
		if a ~= b then
			fed[b] = true
			feeds[a] = feeds[a] or {}
			feeds[a][#feeds[a] + 1] = edge.to
		end
	end

	-- the separate parts of the chain, each with its trees, in the order of their first step
	local parts, byKey = {}, {}
	for _, i in ipairs(roots) do
		local key = find(i)
		local part = byKey[key]
		if not part then
			part = { first = i, level = steps[i].min or 0, roots = {} }
			byKey[key] = part
			parts[#parts + 1] = part
		end
		part.roots[#part.roots + 1] = i
		if (steps[i].min or 0) < part.level then part.level = steps[i].min or 0 end
	end
	table.sort(parts, function(a, b)
		if byLevel and a.level ~= b.level then return a.level < b.level end
		return a.first < b.first
	end)

	for _, part in ipairs(parts) do
		taken, top, bottom = {}, 1, 0
		-- first the trees that stand by themselves or that others lead into, each on a fresh row
		local roads = {}
		for _, i in ipairs(part.roots) do
			if feeds[i] and not fed[i] then roads[#roads + 1] = i else put(i, bottom + 1) end
		end
		-- then the side roads, each beside the earliest step it joins: over it when the
		-- road comes before that step's own tree in the data, else under it
		while #roads > 0 do
			local waiting, moved = {}, false
			for _, i in ipairs(roads) do
				local joins
				for _, to in ipairs(feeds[i]) do
					if row[to] and (not joins or col[to] < col[joins]) then joins = to end
				end
				if joins then
					local by = i < tree[joins] and -1 or 1
					put(i, room(way(i), row[joins] + by, by))
					moved = true
				else
					waiting[#waiting + 1] = i
				end
			end
			-- side roads that only join one another: nothing to stand beside
			if not moved then
				for _, i in ipairs(waiting) do put(i, bottom + 1) end
				waiting = {}
			end
			roads = waiting
		end
		-- move the part under the ones before it
		local by = rows - top + 1
		for i in ipairs(steps) do
			if find(i) == find(part.first) then row[i] = row[i] + by end
		end
		rows = rows + (bottom - top + 1)
	end

	local cols, count, at = 0, 0, {}
	for i in ipairs(steps) do
		at[i] = { col = col[i], row = row[i] }
		if col[i] > cols then cols = col[i] end
		if linked[i] then count = count + 1 end
	end
	return { cols = cols, rows = rows, at = at, edges = edges, auto = cols >= 3 and count * 2 >= #steps }
end

-- What a quest asks for, one entry per thing: the creatures to kill, the objects to use, the
-- items to get. Each is { kind = "kill" | "use" | "item", id, name, place, mark, target }.
--   mark    the picture for it: done once the quest is done, or once the item is in the
--           bags; else as the quest's own
--   place   " (Zone 12.3, 45.6)" or ""; for an item, who drops it
--   target  where to put a map pin, when the place is known
local PART_LABEL = { kill = "Kill", use = "Use", item = "Get" }
local function partsOf(step, state, mark)
	local Progress = ns.Progress
	local parts = {}
	local finished = state == "done" or state == "skipped"
	local complete = finished or mark == "turnin"
	local function add(kind, id, rec, place, target, got)
		if not (rec and rec.name) then return end
		parts[#parts + 1] = {
			kind = kind, id = id, label = PART_LABEL[kind],
			name = (kind == "item" and ns.api.ItemName(id)) or rec.name,
			place = place or "",
			mark = (complete or got) and "done" or mark,
			target = target,
		}
	end
	local function spot(rec)
		if rec and rec.map and rec.x then return { map = rec.map, x = rec.x, y = rec.y, name = rec.name } end
	end
	for _, id in ipairs(step.kill or {}) do
		local npc = ns.Npcs[id]
		add("kill", id, npc, npc and Progress.Place(npc), spot(npc))
	end
	for _, id in ipairs(step.use or {}) do
		local object = ns.Objects[id]
		add("use", id, object, object and Progress.Place(object), spot(object))
	end
	for _, id in ipairs(step.items or {}) do
		local item = ns.Items[id]
		-- who has it: the first creature or object known to
		local from = item and ((item.npc and ns.Npcs[item.npc[1]]) or (item.object and ns.Objects[item.object[1]]))
		local place = (from and from.name) and (" from " .. from.name .. Progress.Place(from)) or ""
		add("item", id, item, place, spot(from), state == "active" and ns.api.ItemCount(id) > 0)
	end
	return parts
end

-- How a level stands to the player's, for the color of "[30]" before a chain or a step:
-- over the player's level, about level with it, below it, or far below.
function View.LevelTone(level, playerLevel)
	if level > playerLevel then return "over" end
	if playerLevel - level <= 2 then return "even" end
	if playerLevel - level <= 9 then return "under" end
	return "far"
end

-- Everything about one chain.
--   modes: { [chain id] = "graph" or "list" } what the player picked for the steps
--   part:   which of the picked step's parts the side panel shows a model of (a number;
--           the first creature to kill when nil). See detail.picked.model.
--   picked: quest ID of the step the player clicked, for the side panel. detail.picked is
--           then { quest, name, state, status, text, objectives = { { text, done } }, lines,
--           rows = { { label, text, tone } }, before, after = { { quest, name, mark } },
--           marked, canMark, rewards, target, link }, and that step has picked = true.
--           before and after are the steps right before and right after it in the chain. text is what the quest asks; objectives is how far the player is,
--           for a quest in the log.
function View.Detail(chain, progress, modes, picked, part)
	local Progress = ns.Progress
	progress = progress or Progress.Chain(chain)

	-- A chain that is only an item ("get this key") has no quest steps. It gets one made-up
	-- step, so the list and the side panel have something to show: the item, and who or
	-- what has it. Its quest number is the item's, negative. A box or chest is taken over
	-- the creatures the database also lists.
	local walk = progress
	if #progress.steps == 0 and chain.reward then
		local item = ns.Items[chain.reward] or {}
		local fake = { quest = -chain.reward, goal = true, items = { chain.reward },
			name = "Get " .. (ns.api.ItemName(chain.reward) or item.name or chain.name) }
		if item.object and #item.object > 0 then fake.use = item.object else fake.kill = item.npc end
		walk = { steps = { fake }, states = { progress.done and "done" or "ready" }, need = {} }
	end

	local parts = { KIND_LABEL[chain.kind] or "" }
	if chain.level then parts[#parts + 1] = "Level " .. chain.level .. "+" end
	if progress.done then
		parts[#parts + 1] = "Done"
	elseif progress.total > 0 then
		parts[#parts + 1] = progress.complete .. " of " .. progress.total .. " done"
	end

	local detail = {
		id = chain.id,
		name = chain.name,
		sub = table.concat(parts, "  -  "),
		tag = table.concat({ KIND_LABEL[chain.kind] or "", chain.level and ("Level " .. chain.level .. "+") or nil }, "  -  "),
		note = chain.note,
		link = chainLink(chain), -- address of the chain's page on the web, or nil
		-- "Mark as done" is offered until the chain is done; a mark can be taken back
		marked = progress.marked,
		canMark = progress.marked or not progress.done,
		art = chain.art and (ART_PATH .. chain.art) or nil, -- picture for the banner
		done = progress.done,
		fraction = fraction(progress),
		ahead = Progress.AheadLines(chain, progress),
		rewards = {}, got = {}, -- filled below: everything the chain's quests give, and what is in hand
		loot = {},
		next = nextBox(chain, progress),
		steps = {},
	}
	local playerLevel = ns.api.Level()
	for i, step in ipairs(walk.steps) do
		local state = walk.states[i]
		local hints = Progress.Hints(step, state, walk.need[i])
		-- Too low a level shows on every step still to do, also on one that waits for an
		-- earlier step first.
		local needLevel
		if state ~= "done" and state ~= "skipped" and step.min and playerLevel < step.min then
			needLevel = step.min
			local line = "Required level: " .. needLevel
			if hints[1] ~= line then hints[#hints + 1] = line end
		end
		-- the picture for the step: its state, or "turnin" for a quest in the log that is complete
		local mark = (state == "active" and ns.api.QuestComplete(step.quest)) and "turnin" or state
		detail.steps[i] = {
			quest = step.quest,
			name = questName(step),
			state = state,
			mark = mark,
			goal = step.goal or false,
			-- the level is worth showing only while the step is still to do
			level = (state == "ready" or state == "active") and step.min or nil,
			status = STATUS[mark],
			parts = partsOf(step, state, mark),
			needLevel = needLevel, -- the level the step asks for, when the player is below it
			-- the level it asks for and how that stands to the player's, for "[30]" before its name
			-- (the quest's own level stands in where the database has no level it asks for)
			min = step.min or (step.level and step.level > 0 and step.level) or nil,
			minTone = (step.min or (step.level and step.level > 0)) and View.LevelTone(step.min or step.level, playerLevel) or nil,
			hints = hints,
			-- what the quest gives, whatever its state
			rewards = step.rewards or {},
			rewardLine = Progress.RewardLine(step),
			gain = Progress.GainLine(step),
			xp = Progress.XpText(step),
			rep = Progress.RepText(step),
			target = Progress.Target(step, state),
		}
	end

	for i, step in ipairs(detail.steps) do
		if picked and step.quest == picked then
			step.picked = true
			local rows = {}
			local src = walk.steps[i]
			if src.min then
				rows[#rows + 1] = { label = "Required level", text = tostring(src.min), tone = step.needLevel and "warn" or "plain" }
			end
			if src.level and src.level > 0 then
				rows[#rows + 1] = { label = "Quest level", text = tostring(src.level), tone = "plain" }
			end
			if step.xp then rows[#rows + 1] = { label = "XP", text = step.xp, tone = "xp" } end
			if step.rep then rows[#rows + 1] = { label = "Reputation", text = step.rep, tone = "rep" } end
			-- the steps of this chain that come right before and right after
			local at, before, after, seen = {}, {}, {}, {}
			for j, other in ipairs(detail.steps) do at[other.quest] = j end
			local function link(j)
				local other = detail.steps[j]
				return { quest = other.quest, name = other.name, mark = other.mark }
			end
			for _, list in ipairs({ src.all or false, src.any or false }) do
				for _, quest in ipairs(list or {}) do
					if at[quest] and not seen[quest] then
						seen[quest] = true
						before[#before + 1] = link(at[quest])
					end
				end
			end
			for j, other in ipairs(walk.steps) do
				for _, list in ipairs({ other.all or false, other.any or false }) do
					for _, quest in ipairs(list or {}) do
						if quest == step.quest and not seen[-j] then
							seen[-j] = true
							after[#after + 1] = link(j)
						end
					end
				end
			end
			-- the level has its own line below ("Required level  20"), so it is left out of the words
			local lines = {}
			for _, line in ipairs(step.hints) do
				-- so do the things to kill, use and get, when the step has them as parts
				local part = #step.parts > 0 and (line:find("^Kill:") or line:find("^Use:") or line:find("^Get:"))
				-- and who starts and takes the quest, see ways below
				local way = line:find("^Start:") or line:find("^Turn in:")
				if not line:find("^Required level") and not part and not way then lines[#lines + 1] = line end
			end
			-- Who starts the quest and who takes it, whatever its state, each with the place
			-- to pin on the map when it is known: { label, text, target }.
			local ways = {}
			for _, def in ipairs({ { "Start", "ready", "^Start: " }, { "Turn in", "active", "^Turn in: " } }) do
				for _, line in ipairs(Progress.Hints(src, def[2])) do
					if line:find(def[3]) then
						ways[#ways + 1] = { label = def[1], text = (line:gsub(def[3], "")), target = Progress.Target(src, def[2]) }
					end
				end
			end
			-- "Mark as done" for a step the game does not count as done; a mark can be taken back
			local marked = ns.StepMarked(step.quest) and not ns.api.QuestDone(step.quest)
			detail.picked = {
				quest = step.quest, name = step.name, state = step.state, mark = step.mark, status = step.status,
				text = src.text,
				objectives = step.state == "active" and ns.api.Objectives(step.quest) or {},
				lines = lines, rows = rows, rewards = step.rewards,
				before = before, after = after,
				ways = ways,
				parts = step.parts,
				-- the creature whose model shows: the part the player picked, else the first to kill
				model = (function()
					local wanted = part and step.parts[part]
					if wanted and wanted.kind == "kill" then return { at = part, id = wanted.id, name = wanted.name } end
					for n, p in ipairs(step.parts) do
						if p.kind == "kill" then return { at = n, id = p.id, name = p.name } end
					end
				end)(),
				marked = marked,
				-- (an item chain is marked as a whole, in the banner)
				canMark = step.quest > 0 and (marked or (step.state ~= "done" and step.state ~= "skipped")),
				-- a step that is still locked can show where it will start
				target = step.target or (step.state == "locked" and Progress.Target(walk.steps[i], "ready")) or nil,
				-- the made-up step of an item chain links to the item
				link = step.quest < 0 and ITEM_LINK:format(-step.quest) or QUEST_LINK:format(step.quest),
			}
		end
	end

	local ahead = Progress.Ahead(chain, progress)
	detail.rewards, detail.got = ahead.rewards, ahead.got

	-- The numbers at a glance, and the facts that need words. tone: plain, good, warn, xp, rep.
	local level = ns.api.Level()
	detail.stats = {
		{ label = "Quests", tone = progress.done and "good" or "plain",
			value = progress.done and "Done" or (progress.total > 0 and (progress.complete .. " / " .. progress.total) or "-") },
		{ label = "XP", tone = "xp",
			value = (not progress.done and not chain.any and ahead.xp > 0) and Progress.Number(ahead.xp) or "-" },
		-- the highest level a step still to do asks for, when the player is below it
		{ label = "Required level to complete", tone = "warn",
			value = (not progress.done and ahead.level) and tostring(ahead.level) or "-" },
	}
	detail.facts = Progress.AheadFacts(chain, progress, ahead)

	-- What may drop on the way, by the creature that drops it. Not quest rewards.
	for _, row in ipairs(chain.loot or {}) do
		local npc = ns.Npcs[row[1]]
		if npc and npc.name then
			local items = {}
			for i = 2, #row do items[#items + 1] = row[i] end
			detail.loot[#detail.loot + 1] = {
				name = npc.name,
				items = items,
				from = "Drops from " .. npc.name .. Progress.Place(npc),
			}
		end
	end

	-- Steps as a graph, when they lead to one another. mode says what to draw.
	local graph = View.Graph(walk, chain.id:find("%-other$") ~= nil)
	detail.mode = "list"
	if graph then
		for i, cell in ipairs(graph.at) do
			detail.steps[i].col, detail.steps[i].row = cell.col, cell.row
		end
		local _, _, focus = Progress.Next(chain, progress)
		detail.graph = { cols = graph.cols, rows = graph.rows, edges = graph.edges, focus = focus }
		local picked = modes and modes[chain.id]
		-- the graph is what a chain opens as; "Show list" is remembered per chain
		if picked ~= "list" then detail.mode = "graph" end
	end

	-- Every chain starts with "Reach level N", N being the level its first quest asks for.
	-- It is a step for the eye only: it has no quest and is not counted, so it is not in
	-- detail.steps but beside it, as detail.reach. The window draws it first.
	if chain.level and chain.level > 1 and #detail.steps > 0 then
		local reached = level >= chain.level
		detail.reach = {
			reach = chain.level,
			name = "Reach level " .. chain.level,
			state = reached and "done" or "ready",
			mark = reached and "done" or "ready",
			goal = false,
			status = reached and "Done" or ("You are level " .. level),
			needLevel = (not reached) and chain.level or nil,
			hints = {}, rewards = {},
		}
		local g = detail.graph
		if g then
			-- in the graph it stands in a column of its own, in front, with a line to every
			-- step that waits for nothing else (g.reach lists them; lit once the level is reached)
			g.reach = { lit = reached }
			for i, step in ipairs(detail.steps) do
				if step.col == 1 then g.reach[#g.reach + 1] = i end
				step.col = step.col + 1
			end
			detail.reach.col, detail.reach.row = 1, detail.steps[g.reach[1] or 1].row
			g.cols = g.cols + 1
		end
	end
	return detail
end

-- The whole window: {
--   groups   { { kind, label, done, total, closed, chains = { { id, kind, name, done, new, count, fraction } } } }
--   selected id of the picked chain
--   detail   View.Detail of that chain, or nil when the character has no chains;
--            detail.mode is "graph" or "list", detail.graph is nil when there is no graph to draw
-- }
--   selected: wanted chain id (falls back to the first one listed)
--   closed:   { [kind] = true } for folded groups
--   modes:    { [chain id] = "graph" or "list" }, see View.Detail
--   search:   text typed over the list. The list then holds only chains whose name has it,
--             every group is open, and model.search is the text. The picked chain stays.
--   step:     quest ID of the step the player clicked, see View.Detail. model.step is that
--             ID while the picked chain has the step, else nil.
function View.Build(selected, closed, modes, search, step, part)
	local Progress = ns.Progress
	local faction = ns.api.Faction()
	closed = closed or {}
	search = type(search) == "string" and search:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
	if search == "" then search = nil end

	local chains, progressOf, current = {}, {}, nil
	for _, chain in ipairs(ns.Chains) do
		if Progress.Visible(chain, faction) then
			chains[#chains + 1] = chain
			progressOf[chain] = Progress.Chain(chain)
			if chain.id == selected then current = chain end
		end
	end
	current = current or chains[1]

	local model = { groups = {}, selected = current and current.id or nil, search = search }
	-- The list's groups, in this order: the player's own class, dungeons, keys, raids, the
	-- other classes (when the options show them), and the rest.
	local groups, named = {}, {}
	local fixed = {}
	for _, group in ipairs(View.GROUPS) do fixed[group.kind] = group end
	local classes, own = classGroups(chains), ns.api.ClassBit()
	for _, made in ipairs(classes) do
		if made.classes then named[made.classes] = true end
		if made.classes == own then groups[#groups + 1] = made end
	end
	groups[#groups + 1] = fixed.dungeon
	groups[#groups + 1] = fixed.key
	groups[#groups + 1] = fixed.raid
	for _, made in ipairs(classes) do
		if made.classes ~= own then groups[#groups + 1] = made end
	end
	groups[#groups + 1] = fixed.misc

	local playerLevel = ns.api.Level()
	local function levelTone(level) return View.LevelTone(level, playerLevel) end
	for _, group in ipairs(groups) do
		local entry = { kind = group.kind, label = group.label, done = 0, total = 0,
			closed = not search and closed[group.kind] and true or false, chains = {} }
		for _, chain in ipairs(chains) do
			if inGroup(chain, group, named) and (not search or chain.name:lower():find(search, 1, true)) then
				local progress = progressOf[chain]
				-- The level on the row: the lowest a step still to do asks for. A chain with
				-- nothing left to do has none.
				local level
				for i, step in ipairs(progress.steps) do
					local state = progress.states[i]
					-- the quest's own level stands in where the database has no level it asks for
					local min = step.min or (step.level and step.level > 0 and step.level) or nil
					if state ~= "done" and state ~= "skipped" and min and (not level or min < level) then level = min end
				end
				if not level and not progress.done and #progress.steps == 0 then level = chain.level end
				entry.total = entry.total + 1
				if progress.done then entry.done = entry.done + 1 end
				entry.chains[#entry.chains + 1] = {
					id = chain.id,
					kind = chain.kind,
					name = chain.name,
					done = progress.done,
					marked = progress.marked,
					new = chain.new or nil, -- new in Forever
					level = level, -- the lowest level a step still to do asks for, or nil
					levelTone = level and levelTone(level) or nil,
					various = chain.id:find("%-other$") ~= nil, -- a class's loose quests: last among its level
					count = countText(progress),
					fraction = fraction(progress),
				}
			end
		end
		-- lowest level first; the same level by name, a class's "Various" chain after the
		-- others; chains with no level (nothing left to do, or only an item) last
		table.sort(entry.chains, function(a, b)
			local la, lb = a.level or 1000, b.level or 1000
			if la ~= lb then return la < lb end
			if a.various ~= b.various then return b.various end
			if a.name ~= b.name then return a.name < b.name end
			return a.id < b.id
		end)
		if entry.total > 0 then model.groups[#model.groups + 1] = entry end
	end
	if current then
		model.detail = View.Detail(current, progressOf[current], modes, step, part)
		model.step = model.detail.picked and model.detail.picked.quest or nil
	end
	return model
end
