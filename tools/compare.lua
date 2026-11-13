-- Compares what the Attune addon tracks with what Get Ready tracks: which of its chains
-- have a counterpart here, and which quests it has that none of our chains has.
-- Attune's lists are read only to count and to match by quest ID; nothing is copied.
-- Usage: luajit tools/compare.lua <path to the Attune addon folder> <QuestieDB_Forever.toc>
--   Run it after a build, and after an Attune or QuestieDB update.

local here = arg[0]:gsub("[^/\\]*$", "")
local ourDir = here .. ".."
local attuneDir, toc = arg[1], arg[2]
if not (attuneDir and toc) then
	print("usage: luajit tools/compare.lua <Attune addon folder> <QuestieDB_Forever.toc>")
	os.exit(1)
end
package.path = here .. "lib/?.lua;" .. package.path

-- Attune's data, in a bare environment
local env = setmetatable({ Attune_Data = {} }, { __index = _G })
env.AttuneLang = setmetatable({}, { __index = function(_, k) return k end })
local function run(file)
	local f = assert(io.open(attuneDir .. "/" .. file, "rb"))
	local src = f:read("*a"):gsub("^\239\187\191", "")
	f:close()
	local chunk = assert(loadstring(src, file))
	setfenv(chunk, env)
	local ok, err = pcall(chunk)
	if not ok then print("note: " .. file .. " stopped: " .. tostring(err)) end
end
run("AttuneData.lua")
run("AttuneClassQuests.lua")
local A = env.Attune_Data

-- ours
local ns = {}
assert(loadfile(ourDir .. "/Data/Chains.lua"))("GetReady", ns)
local ourQuest = {} -- quest id -> list of chain ids
local ourItem, ourNpc = {}, {}
for _, c in ipairs(ns.Chains) do
	if c.reward then ourItem[c.reward] = c.id end
	for _, s in ipairs(c.steps) do
		ourQuest[s.quest] = ourQuest[s.quest] or {}
		table.insert(ourQuest[s.quest], c.id)
		for _, id in ipairs(s.items or {}) do ourItem[id] = ourItem[id] or c.id end
		for _, id in ipairs(s.kill or {}) do ourNpc[id] = ourNpc[id] or c.id end
	end
end

local db = require("qdb").open(toc)

-- Attune's steps by attune
local steps = {}
for _, s in ipairs(A.steps or {}) do
	steps[s.ID_ATTUNE] = steps[s.ID_ATTUNE] or {}
	table.insert(steps[s.ID_ATTUNE], s)
end
local QUEST = { ["Quest"] = true, ["Pick Up"] = true, ["Turn In"] = true }

local groups, order = {}, {}
local totalQ, haveQ, inDbQ = 0, 0, 0
local missingQuests = {}
for _, a in ipairs(A.attunes or {}) do
	local list = steps[a.ID] or {}
	local quests, seen, types = {}, {}, {}
	for _, s in ipairs(list) do
		types[s.TYPE] = (types[s.TYPE] or 0) + 1
		local id = tonumber(s.ID_WOWHEAD)
		if QUEST[s.TYPE] and id and id > 0 and not seen[id] then
			seen[id] = true
			quests[#quests + 1] = id
		end
	end
	local have, chains = 0, {}
	for _, id in ipairs(quests) do
		if ourQuest[id] then
			have = have + 1
			for _, c in ipairs(ourQuest[id]) do chains[c] = (chains[c] or 0) + 1 end
		else
			missingQuests[#missingQuests + 1] = { id = id, attune = a.NAME, group = a.GROUP, inDb = db:quest(id) ~= nil }
		end
	end
	-- the chain of ours that shares the most quests
	local best, bestN = nil, 0
	for c, n in pairs(chains) do if n > bestN or (n == bestN and c < (best or "~")) then best, bestN = c, n end end
	local other = {}
	for t, n in pairs(types) do
		if not QUEST[t] and t ~= "Spacer" and t ~= "End" then other[#other + 1] = t .. " " .. n end
	end
	table.sort(other)
	local g = tostring(a.GROUP)
	if not groups[g] then groups[g] = {} order[#order + 1] = g end
	table.insert(groups[g], { id = a.ID, name = a.NAME, faction = a.FACTION, quests = #quests, have = have, best = best, bestN = bestN, other = table.concat(other, ", "), rows = #list })
	totalQ, haveQ = totalQ + #quests, haveQ + have
end

print(("Attune: %d chains, %d step rows. Ours: %d chains."):format(#(A.attunes or {}), #(A.steps or {}), #ns.Chains))
print(("Quest uses in Attune chains: %d, of which in our chains: %d (%.0f%%)"):format(totalQ, haveQ, totalQ > 0 and haveQ / totalQ * 100 or 0))
for _, g in ipairs(order) do
	local isClass = g:find("^CLASS_")
	local n, q, h, none, empty = 0, 0, 0, 0, 0
	for _, a in ipairs(groups[g]) do
		n, q, h = n + 1, q + a.quests, h + a.have
		if a.quests > 0 and a.have == 0 then none = none + 1 end
		if a.rows == 0 then empty = empty + 1 end
	end
	print(("\n== %s: %d chains, %d quests, %d ours (%d chains with none of ours, %d with no steps in Attune)"):format(g, n, q, h, none, empty))
	for _, a in ipairs(groups[g]) do
		if not isClass or a.have < a.quests then
			print(("  %-4s %-34s %-8s quests %2d/%-2d  best: %-22s %s"):format(a.id, tostring(a.name):sub(1, 34), tostring(a.faction), a.have, a.quests,
				a.best and (a.best .. " (" .. a.bestN .. ")") or "-", a.other ~= "" and ("| also: " .. a.other) or ""))
		end
	end
end

print("\n== Quests Attune has that none of our chains has: " .. #missingQuests)
local shown = {}
table.sort(missingQuests, function(x, y) if x.group ~= y.group then return x.group < y.group end if x.attune ~= y.attune then return tostring(x.attune) < tostring(y.attune) end return x.id < y.id end)
for _, m in ipairs(missingQuests) do
	local key = m.id .. "|" .. tostring(m.attune)
	if not shown[key] then
		shown[key] = true
		local q = db:quest(m.id)
		print(("  %6d %-12s %-30s %s"):format(m.id, m.inDb and "in QuestieDB" or "NOT in DB", tostring(m.attune):sub(1, 30), q and q.name or ""))
	end
end
