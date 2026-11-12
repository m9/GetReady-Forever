local _, ns = ...

-- Works out where the player stands in a chain. No frames here.
--
-- Step states:
--   done     quest turned in
--   skipped  not turned in, but a later step is, so it no longer matters
--   active   quest is in the log
--   ready    can be picked up now
--   locked   needs an earlier step, a higher level or more reputation

local Progress = {}
ns.Progress = Progress

-- Is this step for the player's faction, race and class?
local function forPlayer(step, faction, classBit, raceBit)
	if step.side and step.side ~= faction then return false end
	if step.races and raceBit > 0 and math.floor(step.races / raceBit) % 2 == 0 then return false end
	if step.classes and classBit > 0 and math.floor(step.classes / classBit) % 2 == 0 then return false end
	return true
end

-- Should this chain be listed for the player? Not if it belongs to the other faction or to
-- other classes, and not if none of its goals are for this faction, race and class: quests
-- that only lead up to someone else's goal do not make it the player's chain.
function Progress.Visible(chain, faction)
	if chain.side ~= "Both" and chain.side ~= faction then return false end
	local classBit, raceBit = ns.api.ClassBit(), ns.api.RaceBit()
	if chain.classes and classBit > 0 and math.floor(chain.classes / classBit) % 2 == 0 then return false end
	if not chain.steps or #chain.steps == 0 then return true end
	local goals, mine, any = false, false, false
	for _, step in ipairs(chain.steps) do
		local ok = forPlayer(step, faction, classBit, raceBit)
		any = any or ok
		if step.goal then
			goals = true
			mine = mine or ok
		end
	end
	if goals then return mine end
	return any
end

local function complete(state)
	return state == "done" or state == "skipped"
end

-- Reputation value -> standing (4 neutral .. 8 exalted).
local function standingFor(value)
	if value >= 42000 then return 8 end
	if value >= 21000 then return 7 end
	if value >= 9000 then return 6 end
	if value >= 3000 then return 5 end
	if value >= 0 then return 4 end
	if value >= -3000 then return 3 end
	if value >= -6000 then return 2 end
	return 1
end

-- Returns {
--   steps      the steps this character can do, earlier quests first
--   states     { [i] = state } for those steps
--   need       { [i] = { level = n } or { standing = n, faction = id } } why a step is locked
--   done       whole chain finished
--   marked     the player marked it as done by hand
--   complete, total   counts over steps (0 and 0 for a chain that is only an item)
-- }
function Progress.Chain(chain)
	local api = ns.api
	local faction, classBit, level = api.Faction(), api.ClassBit(), api.Level()
	local raceBit = api.RaceBit()

	local steps, index, known = {}, {}, {}
	for _, step in ipairs(chain.steps) do
		known[step.quest] = true
		if forPlayer(step, faction, classBit, raceBit) then
			steps[#steps + 1] = step
			index[step.quest] = #steps
		end
	end
	local total = #steps

	local flagged, active, covered = {}, {}, {}
	local goals, goalsDone = 0, 0
	for i, step in ipairs(steps) do
		flagged[i] = api.QuestDone(step.quest)
		active[i] = not flagged[i] and api.OnQuest(step.quest)
		if step.goal then
			goals = goals + 1
			if flagged[i] then goalsDone = goalsDone + 1 end
		end
	end

	local owned = chain.reward and api.ItemCount(chain.reward) > 0 or false
	-- the player can also say a chain is done: the game does not know everything
	local marked = ns.Marked and ns.Marked(chain.id) or false
	local chainDone = owned or marked
	if not chainDone and goals > 0 then
		if chain.any then chainDone = goalsDone > 0 else chainDone = goalsDone == goals end
	end

	-- Steps come with earlier quests first, so one pass from the end is enough.
	for i = total, 1, -1 do
		if chainDone then covered[i] = true end
		if flagged[i] or active[i] or covered[i] then
			local step = steps[i]
			for _, quest in ipairs(step.all or {}) do if index[quest] then covered[index[quest]] = true end end
			for _, quest in ipairs(step.any or {}) do if index[quest] then covered[index[quest]] = true end end
		end
	end

	local result = { steps = steps, states = {}, need = {}, done = chainDone, marked = marked, complete = 0, total = total }

	-- Is an earlier quest out of the way? Quests of another class or faction count
	-- only if they are turned in; quests outside the chain are not checked.
	local function cleared(quest)
		local at = index[quest]
		if at then return complete(result.states[at]) end
		if known[quest] then return api.QuestDone(quest) end
		return true
	end

	for i, step in ipairs(steps) do
		local state
		if flagged[i] then
			state = "done"
		elseif active[i] then
			state = "active"
		elseif covered[i] then
			state = "skipped"
		else
			local open = true
			for _, quest in ipairs(step.all or {}) do
				if index[quest] and not cleared(quest) then open = false end
			end
			if open and step.any and #step.any > 0 then
				open = false
				for _, quest in ipairs(step.any) do
					if cleared(quest) then open = true end
				end
			end
			if open and step.min and level < step.min then
				open = false
				result.need[i] = { level = step.min }
			end
			if open and step.rep then
				local wanted = standingFor(step.rep[2])
				local standing = api.Standing(step.rep[1])
				if standing and standing < wanted then
					open = false
					result.need[i] = { standing = wanted, faction = step.rep[1] }
				end
			end
			state = open and "ready" or "locked"
		end
		result.states[i] = state
		if complete(state) then result.complete = result.complete + 1 end
	end
	return result
end

-- Short help lines for a step ------------------------------------------------

-- Names in the player's language when the game knows them, else the English ones in the data.
local function areaName(id)
	return ns.api.AreaName(id) or (ns.Areas and ns.Areas[id])
end

local function factionName(id)
	local _, name = ns.api.Standing(id)
	return name or (ns.Factions and ns.Factions[id])
end

local function where(rec)
	if not rec or not rec.area then return "" end
	local area = areaName(rec.area)
	if rec.inside then
		return area and (" (in " .. area .. ")") or " (in a dungeon)"
	end
	local text = area or ""
	if rec.x then
		text = text .. (text ~= "" and " " or "") .. ("%.1f, %.1f"):format(rec.x, rec.y)
	end
	return text ~= "" and (" (" .. text .. ")") or ""
end

-- " (Badlands 5.8, 47.5)" or " (in Blackrock Spire)" for a creature or object record, else "".
function Progress.Place(rec)
	return where(rec)
end

local function names(list, map)
	local out = {}
	for _, id in ipairs(list) do
		local name = map[id] and map[id].name
		if name then out[#out + 1] = name end
	end
	return #out > 0 and table.concat(out, ", ") or nil
end

-- The first giver we know by name: record and its kind.
local function first(giver)
	if not giver then return nil end
	for _, id in ipairs(giver.npc or {}) do
		if ns.Npcs[id] and ns.Npcs[id].name then return ns.Npcs[id], "npc" end
	end
	for _, id in ipairs(giver.object or {}) do
		if ns.Objects[id] and ns.Objects[id].name then return ns.Objects[id], "object" end
	end
	for _, id in ipairs(giver.item or {}) do
		if ns.Items[id] and ns.Items[id].name then return ns.Items[id], "item" end
	end
end

local function who(giver)
	local rec, kind = first(giver)
	if not rec then return nil end
	if kind == "item" then return rec.name end
	return rec.name .. where(rec)
end

-- Where an item comes from: "Name (place)", or nil.
local function source(item)
	local rec = ns.Items[item]
	if not rec then return nil end
	return who({ npc = rec.npc, object = rec.object })
end

-- Returns a list of lines. Empty for steps that need no help.
--   need: the entry from Progress.Chain(...).need for this step, if any
function Progress.Hints(step, state, need)
	local lines = {}
	if state == "ready" then
		local from = who(step.from)
		if from then lines[#lines + 1] = "Start: " .. from end
	elseif state == "active" then
		local kill = step.kill and names(step.kill, ns.Npcs)
		local use = step.use and names(step.use, ns.Objects)
		local get = step.items and names(step.items, ns.Items)
		if kill then lines[#lines + 1] = "Kill: " .. kill end
		if use then lines[#lines + 1] = "Use: " .. use end
		if get then lines[#lines + 1] = "Get: " .. get end
		local to = who(step.to)
		if to then lines[#lines + 1] = "Turn in: " .. to end
	elseif state == "locked" and need then
		if need.level then
			lines[#lines + 1] = "Needs level " .. need.level
		elseif need.standing then
			local faction = factionName(need.faction)
			lines[#lines + 1] = "Needs " .. ns.api.StandingName(need.standing) .. (faction and (" with " .. faction) or "")
		end
	end
	return lines
end

-- Help lines for a chain that is only "get this item".
function Progress.RewardHints(chain)
	local lines = {}
	local rec = chain.reward and ns.Items[chain.reward]
	if not rec or not rec.name then return lines end
	lines[#lines + 1] = "Get: " .. rec.name
	local from = source(chain.reward)
	if from then lines[#lines + 1] = "From: " .. from end
	return lines
end

-- The map spot that helps most with a step right now: { map, x, y, name } or nil.
function Progress.Target(step, state)
	local giver
	if state == "ready" then giver = step.from elseif state == "active" then giver = step.to end
	local rec, kind = first(giver)
	if rec and kind ~= "item" and rec.map and rec.x then
		return { map = rec.map, x = rec.x, y = rec.y, name = rec.name }
	end
end

-- One line for the list: the next thing to do in a chain, or nil.
function Progress.Next(chain, progress)
	progress = progress or Progress.Chain(chain)
	if progress.done then return nil end
	for _, wanted in ipairs({ "active", "ready" }) do
		for i, step in ipairs(progress.steps) do
			if progress.states[i] == wanted then return step, wanted, i end
		end
	end
end

-- Rewards and what lies ahead -------------------------------------------------------

local function commas(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function itemName(id)
	return ns.api.ItemName(id) or (ns.Items[id] and ns.Items[id].name)
end

-- "Rewards: A, B, C" for a step, or nil. Long lists are cut short.
function Progress.RewardLine(step, max)
	if not step.rewards then return nil end
	max = max or 4
	local out, more = {}, 0
	for _, id in ipairs(step.rewards) do
		local name = itemName(id)
		if name then
			if #out < max then out[#out + 1] = name else more = more + 1 end
		end
	end
	if #out == 0 then return nil end
	return "Rewards: " .. table.concat(out, ", ") .. (more > 0 and (" +" .. more) or "")
end

-- "8,300 XP" for a step, or nil.
function Progress.XpText(step)
	if step.xp and step.xp > 0 then return commas(step.xp) .. " XP" end
end

-- "+150 Orgrimmar, +200 Undercity" for a step, or nil.
function Progress.RepText(step)
	local parts = {}
	for _, gain in ipairs(step.repGain or {}) do
		if gain[2] and gain[2] >= 1 then
			parts[#parts + 1] = "+" .. commas(gain[2]) .. " " .. (factionName(gain[1]) or "reputation")
		end
	end
	if #parts > 0 then return table.concat(parts, ", ") end
end

-- "Gives: 8,300 XP, +150 Orgrimmar" for a step, or nil.
function Progress.GainLine(step)
	local parts = {}
	if step.xp and step.xp > 0 then parts[#parts + 1] = commas(step.xp) .. " XP" end
	for _, gain in ipairs(step.repGain or {}) do
		if gain[2] and gain[2] > 0 then
			local faction = factionName(gain[1])
			parts[#parts + 1] = "+" .. commas(gain[2]) .. " " .. (faction or "reputation")
		end
	end
	if #parts == 0 then return nil end
	return "Gives: " .. table.concat(parts, ", ")
end

-- Is this place inside a dungeon? Returns the dungeon's name.
local function dungeonOf(rec)
	if rec and rec.inside then
		return areaName(rec.area) or "a dungeon"
	end
end

-- What is still in front of the player in this chain. Returns {
--   quests    steps not finished
--   xp        XP from those steps
--   level     highest level those steps ask for, if above the player's
--   standing  { { faction, standing } } reputation those steps ask for and the player lacks
--   dungeons  names of dungeons those steps send you into
--   rewards   item IDs: the chain's own item, then what every step gives, in step order
--   got       { [item] = true } rewards already in hand: the chain's item when owned, a step's when turned in
--   rep       { { faction, value } } reputation those steps give, most first
-- }
function Progress.Ahead(chain, progress)
	progress = progress or Progress.Chain(chain)
	local api = ns.api
	local ahead = { quests = 0, xp = 0, dungeons = {}, rewards = {}, standing = {}, rep = {}, got = {} }
	local open = {} -- rewards a step not yet turned in still gives
	local seenDungeon, seenReward, wanted, gains = {}, {}, {}, {}
	local level = api.Level()

	local function reward(id)
		if id and not seenReward[id] then
			seenReward[id] = true
			ahead.rewards[#ahead.rewards + 1] = id
		end
	end
	local function visit(rec)
		local name = dungeonOf(rec)
		if name and not seenDungeon[name] then
			seenDungeon[name] = true
			ahead.dungeons[#ahead.dungeons + 1] = name
		end
	end
	local function visitAll(list, map)
		for _, id in ipairs(list or {}) do visit(map[id]) end
	end

	reward(chain.reward)
	if chain.reward and api.ItemCount(chain.reward) > 0 then ahead.got[chain.reward] = true end
	for i, step in ipairs(progress.steps) do
		local state = progress.states[i]
		for _, id in ipairs(step.rewards or {}) do
			reward(id)
			if state == "done" then ahead.got[id] = true else open[id] = true end
		end
		if state ~= "done" and state ~= "skipped" then
			ahead.quests = ahead.quests + 1
			ahead.xp = ahead.xp + (step.xp or 0)
			for _, gain in ipairs(step.repGain or {}) do
				if gain[2] and gain[2] > 0 then gains[gain[1]] = (gains[gain[1]] or 0) + gain[2] end
			end
			if step.min and step.min > level and step.min > (ahead.level or 0) then ahead.level = step.min end
			if step.rep then
				local need = standingFor(step.rep[2])
				local have = api.Standing(step.rep[1])
				if have and have < need and need > (wanted[step.rep[1]] or 0) then wanted[step.rep[1]] = need end
			end
			visitAll(step.kill, ns.Npcs)
			visitAll(step.use, ns.Objects)
			for _, item in ipairs(step.items or {}) do
				local rec = ns.Items[item]
				if rec then
					visitAll(rec.npc, ns.Npcs)
					visitAll(rec.object, ns.Objects)
				end
			end
			for _, giver in ipairs({ step.from or false, step.to or false }) do
				if giver then
					visitAll(giver.npc, ns.Npcs)
					visitAll(giver.object, ns.Objects)
				end
			end
		end
	end
	-- With "one goal is enough", the lowest bar is what matters, not every bar.
	if not chain.any then
		for faction, need in pairs(wanted) do ahead.standing[#ahead.standing + 1] = { faction, need } end
		table.sort(ahead.standing, function(a, b) return a[1] < b[1] end)
	end
	for id in pairs(open) do
		if id ~= chain.reward then ahead.got[id] = nil end
	end
	if chain.any then ahead.quests = math.min(ahead.quests, 1) end
	-- With "one goal is enough" the sums would count every way to finish, so leave them out.
	if not chain.any then
		for faction, value in pairs(gains) do ahead.rep[#ahead.rep + 1] = { faction, value } end
		table.sort(ahead.rep, function(a, b)
			if a[2] ~= b[2] then return a[2] > b[2] end
			return a[1] < b[1]
		end)
	end
	return ahead
end

-- The overview in pieces: { { label = "Dungeons", text = "...", tone = "plain" }, ... }.
-- tone says what kind of fact it is: plain, warn (something the player lacks) or rep.
function Progress.AheadFacts(chain, progress, ahead)
	progress = progress or Progress.Chain(chain)
	if progress.done then return {} end
	ahead = ahead or Progress.Ahead(chain, progress)
	local facts = {}
	if #ahead.dungeons > 0 then
		facts[#facts + 1] = { label = "Dungeons", text = table.concat(ahead.dungeons, ", "), tone = "plain" }
	end
	local needs = {}
	if ahead.level then needs[#needs + 1] = "level " .. ahead.level end
	for _, pair in ipairs(ahead.standing) do
		local faction = factionName(pair[1])
		needs[#needs + 1] = ns.api.StandingName(pair[2]) .. (faction and (" with " .. faction) or "")
	end
	if #needs > 0 then facts[#facts + 1] = { label = "Needs", text = table.concat(needs, ", "), tone = "warn" } end
	-- Reputation the steps still to do add up to: the three biggest, by name.
	local gains, more = {}, 0
	for _, pair in ipairs(ahead.rep) do
		local faction = factionName(pair[1])
		if faction and pair[2] >= 1 then
			if #gains < 3 then gains[#gains + 1] = "+" .. commas(pair[2]) .. " " .. faction else more = more + 1 end
		end
	end
	if #gains > 0 then
		facts[#facts + 1] = { label = "Reputation", tone = "rep",
			text = table.concat(gains, ", ") .. (more > 0 and (" +" .. more .. " more") or "") }
	end
	return facts
end

-- The overview as short lines.
function Progress.AheadLines(chain, progress)
	progress = progress or Progress.Chain(chain)
	if progress.done then return {} end
	local ahead = Progress.Ahead(chain, progress)
	local lines = {}
	if ahead.quests > 0 then
		local line = "Left: " .. ahead.quests .. (ahead.quests == 1 and " quest" or " quests")
		if ahead.xp > 0 and not chain.any then line = line .. ", " .. commas(ahead.xp) .. " XP" end
		lines[#lines + 1] = line
	end
	for _, fact in ipairs(Progress.AheadFacts(chain, progress, ahead)) do
		lines[#lines + 1] = fact.label .. ": " .. fact.text
	end
	return lines
end

-- 8300 -> "8,300"
function Progress.Number(n)
	return commas(n)
end
