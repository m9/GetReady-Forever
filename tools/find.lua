-- Searches the quest database by name.
-- Usage: luajit tools/find.lua <QuestieDB_Forever.toc> <quest|item|npc|object> <text> [more text ...]
--   Each text is searched on its own. Matching ignores case.

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "lib/?.lua;" .. package.path

local qdb = require("qdb")
local build = require("build")

local tocPath, kind = arg[1], arg[2]
if not tocPath or not kind or not arg[3] then
	print("usage: luajit tools/find.lua <QuestieDB_Forever.toc> <quest|item|npc|object> <text> [more text ...]")
	os.exit(1)
end

local db = qdb.open(tocPath)
local ids = db:ids(kind)
local names = {}
for _, id in ipairs(ids) do
	local rec = db:record(kind, id)
	names[id] = rec.name and tostring(rec.name) or ""
end

local function list(t)
	local out = {}
	for i, v in ipairs(t or {}) do out[i] = tostring(type(v) == "table" and v[1] or v) end
	return table.concat(out, ",")
end

for i = 3, #arg do
	local needle = arg[i]:lower()
	print("== " .. arg[i])
	for _, id in ipairs(ids) do
		if names[id]:lower():find(needle, 1, true) then
			local rec = db:record(kind, id)
			if kind == "quest" then
				print(("%6d %s [%s, min %s, zone %s] pre any=%s all=%s rep=%s"):format(id, names[id],
					build.side(rec.requiredRaces), tostring(rec.requiredLevel), tostring(rec.zoneOrSort),
					list(rec.preQuestSingle), list(rec.preQuestGroup), list(rec.requiredMinRep)))
			elseif kind == "item" then
				print(("%6d %s  reward of quests=%s  npc drops=%d  object drops=%d  starts quest=%s"):format(id, names[id],
					list(rec.questRewards), #(rec.npcDrops or {}), #(rec.objectDrops or {}), tostring(rec.startQuest)))
			else
				print(("%6d %s  starts=%s ends=%s"):format(id, names[id], list(rec.questStarts), list(rec.questEnds)))
			end
		end
	end
end
