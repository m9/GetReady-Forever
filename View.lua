local _, ns = ...

-- Decides what the window says: every label, count and line of text, as plain data.
-- No frames here, so it can be tested without the game.

local View = {}
ns.View = View

View.GROUPS = {
	{ kind = "raid", label = "Raids" },
	{ kind = "key", label = "Keys" },
	{ kind = "dungeon", label = "Dungeons" },
	{ kind = "class", label = "Class" },
	{ kind = "misc", label = "Other" },
}

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
		return { label = "Done", name = progress.marked and "You marked this chain as done." or "Nothing left to do.",
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
			label = state == "active" and "In your quest log" or "Next",
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
				label = "Not yet",
				name = questName(progress.steps[j]),
				lines = Progress.Hints(progress.steps[j], state, progress.need[j]),
				state = "locked",
			}
		end
	end
	return { label = "Not yet", name = "Nothing to start right now.", lines = {}, state = "locked" }
end

local STATUS = {
	done = "Turned in",
	skipped = "Not needed",
	active = "In your quest log",
	ready = "Can start now",
	locked = "Locked",
}

-- Where each step sits when the chain is drawn as a graph, left to right.
-- Returns nil for a chain whose steps do not lead to one another. Else {
--   cols, rows  size of the grid
--   at          { [i] = { col, row } } cell of step i
--   edges       { { from, to, lit } } step indexes; lit when the earlier step is out of the way
--   auto        true when the graph says more than the list (three columns or more, most steps linked)
-- }
-- A step's column is one past its latest earlier step. Each step hangs under one of those
-- (the middle one), which makes a tree; a branch gets its own rows, and a step sits on the
-- row of its middle branch. So no two steps share a cell.
function View.Graph(progress)
	local steps = progress.steps
	local index = {}
	for i, step in ipairs(steps) do index[step.quest] = i end

	local col, parent, kids, edges, linked = {}, {}, {}, {}, {}
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
		end
		if #nearest > 0 then
			local p = nearest[math.ceil(#nearest / 2)]
			parent[i] = p
			kids[p] = kids[p] or {}
			kids[p][#kids[p] + 1] = i
		end
	end
	if #edges == 0 then return nil end

	local row, rows = {}, 0
	local function place(i)
		local list = kids[i]
		if not list then
			rows = rows + 1
			row[i] = rows
			return
		end
		for _, k in ipairs(list) do place(k) end
		row[i] = row[list[math.ceil(#list / 2)]]
	end
	local cols, count, at = 0, 0, {}
	for i in ipairs(steps) do
		if not parent[i] then place(i) end
	end
	for i in ipairs(steps) do
		at[i] = { col = col[i], row = row[i] }
		if col[i] > cols then cols = col[i] end
		if linked[i] then count = count + 1 end
	end
	return { cols = cols, rows = rows, at = at, edges = edges, auto = cols >= 3 and count * 2 >= #steps }
end

-- Everything about one chain.
--   modes: { [chain id] = "graph" or "list" } what the player picked for the steps
function View.Detail(chain, progress, modes)
	local Progress = ns.Progress
	progress = progress or Progress.Chain(chain)

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
	for i, step in ipairs(progress.steps) do
		local state = progress.states[i]
		local hints = Progress.Hints(step, state, progress.need[i])
		-- Too low a level shows on every step still to do, also on one that waits for an
		-- earlier step first.
		local needLevel
		if state ~= "done" and state ~= "skipped" and step.min and playerLevel < step.min then
			needLevel = step.min
			local line = "Needs level " .. needLevel
			if hints[1] ~= line then hints[#hints + 1] = line end
		end
		detail.steps[i] = {
			quest = step.quest,
			name = questName(step),
			state = state,
			goal = step.goal or false,
			-- the level is worth showing only while the step is still to do
			level = (state == "ready" or state == "active") and step.min or nil,
			status = STATUS[state],
			needLevel = needLevel, -- the level the step asks for, when the player is below it
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

	local ahead = Progress.Ahead(chain, progress)
	detail.rewards, detail.got = ahead.rewards, ahead.got

	-- The numbers at a glance, and the facts that need words. tone: plain, good, warn, xp, rep.
	local level = ns.api.Level()
	detail.stats = {
		{ label = "Progress", tone = progress.done and "good" or "plain",
			value = progress.done and "Done" or (progress.total > 0 and (progress.complete .. " / " .. progress.total) or "-") },
		{ label = "Quests left", tone = "plain", value = progress.done and "0" or tostring(ahead.quests) },
		{ label = "XP to earn", tone = "xp",
			value = (not progress.done and not chain.any and ahead.xp > 0) and Progress.Number(ahead.xp) or "-" },
		{ label = "From level", tone = (chain.level and level < chain.level) and "warn" or "plain",
			value = chain.level and tostring(chain.level) or "-" },
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
	local graph = View.Graph(progress)
	detail.mode = "list"
	if graph then
		for i, cell in ipairs(graph.at) do
			detail.steps[i].col, detail.steps[i].row = cell.col, cell.row
		end
		local _, _, focus = Progress.Next(chain, progress)
		detail.graph = { cols = graph.cols, rows = graph.rows, edges = graph.edges, focus = focus }
		local picked = modes and modes[chain.id]
		if picked == "graph" or (picked ~= "list" and graph.auto) then detail.mode = "graph" end
	end
	return detail
end

-- The whole window: {
--   groups   { { kind, label, done, total, closed, chains = { { id, kind, name, done, count, fraction } } } }
--   selected id of the picked chain
--   detail   View.Detail of that chain, or nil when the character has no chains;
--            detail.mode is "graph" or "list", detail.graph is nil when there is no graph to draw
-- }
--   selected: wanted chain id (falls back to the first one listed)
--   closed:   { [kind] = true } for folded groups
--   modes:    { [chain id] = "graph" or "list" }, see View.Detail
function View.Build(selected, closed, modes)
	local Progress = ns.Progress
	local faction = ns.api.Faction()
	closed = closed or {}

	local chains, progressOf, current = {}, {}, nil
	for _, chain in ipairs(ns.Chains) do
		if Progress.Visible(chain, faction) then
			chains[#chains + 1] = chain
			progressOf[chain] = Progress.Chain(chain)
			if chain.id == selected then current = chain end
		end
	end
	current = current or chains[1]

	local model = { groups = {}, selected = current and current.id or nil }
	for _, group in ipairs(View.GROUPS) do
		local entry = { kind = group.kind, label = group.label, done = 0, total = 0,
			closed = closed[group.kind] and true or false, chains = {} }
		for _, chain in ipairs(chains) do
			if chain.kind == group.kind then
				local progress = progressOf[chain]
				entry.total = entry.total + 1
				if progress.done then entry.done = entry.done + 1 end
				entry.chains[#entry.chains + 1] = {
					id = chain.id,
					kind = chain.kind,
					name = chain.name,
					done = progress.done,
					marked = progress.marked,
					count = countText(progress),
					fraction = fraction(progress),
				}
			end
		end
		if entry.total > 0 then model.groups[#model.groups + 1] = entry end
	end
	if current then model.detail = View.Detail(current, progressOf[current], modes) end
	return model
end
