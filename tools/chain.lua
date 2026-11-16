-- Prints the quest chain that leads to a goal quest.
-- Usage: luajit tools/chain.lua [--questiedb <version>] <questId> [questId ...]
--   Reads the QuestieDB version deps.lua records, or the one given.

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "lib/?.lua;" .. package.path

local qdb = require("qdb")
local chain = require("chain")
local deps = require("deps")

if not arg[1] then
	print("usage: luajit tools/chain.lua [--questiedb <version>] <questId> [questId ...]")
	os.exit(1)
end
local tocPath, ids = deps.questiedb(arg, here .. "../")

local db = qdb.open(tocPath)
print(("QuestieDB %s, %d quests"):format(db:meta("Flavor") or "?", #db:questIds()))

for _, word in ipairs(ids) do
	local goal = tonumber(word) or error("not a quest id: " .. word)
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
