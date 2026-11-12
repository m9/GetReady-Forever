-- Prints the quest chain that leads to a goal quest.
-- Usage: luajit tools/chain.lua <QuestieDB_Forever.toc> <questId> [questId ...]

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "lib/?.lua;" .. package.path

local qdb = require("qdb")
local chain = require("chain")

local tocPath = arg[1]
if not tocPath or not arg[2] then
	print("usage: luajit tools/chain.lua <QuestieDB_Forever.toc> <questId> [questId ...]")
	os.exit(1)
end

local db = qdb.open(tocPath)
print(("QuestieDB %s, %d quests"):format(db:meta("Flavor") or "?", #db:questIds()))

for i = 2, #arg do
	local goal = tonumber(arg[i]) or error("not a quest id: " .. arg[i])
	print("")
	print("Chain to " .. goal .. ":")
	for n, step in ipairs(chain.build(db, goal)) do
		local needs = ""
		if #step.all > 0 then needs = needs .. "  after all of " .. table.concat(step.all, ", ") end
		if #step.any > 0 then needs = needs .. "  after any of " .. table.concat(step.any, ", ") end
		if step.missing then
			print(("%3d. %d (not in database)"):format(n, step.id))
		else
			print(("%3d. %d %s [level %s, min %s]%s"):format(n, step.id, step.name or "?",
				tostring(step.level), tostring(step.minLevel), needs))
		end
	end
end
