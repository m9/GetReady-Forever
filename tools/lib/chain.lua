-- Builds a quest chain from one or more goal quests by walking prerequisites.
--
-- QuestieDB fields used:
--   preQuestSingle = any one of these must be done
--   preQuestGroup  = all of these must be done (sign is dropped)

local chain = {}

-- goals: a quest ID or a list of them.
-- Returns a list of steps, prerequisites first:
--   { id, name, level, minLevel, all = {ids}, any = {ids}, goal = true?, missing = true? }
function chain.build(db, goals)
	if type(goals) == "number" then goals = { goals } end
	local steps, state, byId = {}, {}, {}

	local function visit(id)
		if state[id] == "done" then return end
		if state[id] == "open" then error("chain: cycle at quest " .. id) end
		state[id] = "open"
		local q = db:quest(id)
		local step = { id = id, all = {}, any = {} }
		if q then
			step.name, step.level, step.minLevel = q.name, q.questLevel, q.requiredLevel
			for _, pre in ipairs(q.preQuestGroup or {}) do step.all[#step.all + 1] = math.abs(pre) end
			for _, pre in ipairs(q.preQuestSingle or {}) do step.any[#step.any + 1] = pre end
			for _, pre in ipairs(step.all) do visit(pre) end
			for _, pre in ipairs(step.any) do visit(pre) end
		else
			step.missing = true
		end
		state[id] = "done"
		steps[#steps + 1] = step
		byId[id] = step
	end

	for _, goal in ipairs(goals) do
		visit(goal)
		byId[goal].goal = true
	end
	return steps
end

return chain
