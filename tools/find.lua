-- Searches the quest database by name.
-- Usage: luajit tools/find.lua [--questiedb <version>] <quest|item|npc|object> <text> [more text ...]
--   Each text is searched on its own. Matching ignores case.
--   Reads the QuestieDB version deps.lua records, or the one given.

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "lib/?.lua;" .. package.path

local qdb = require("qdb")
local build = require("build")
local deps = require("deps")

local function usage()
	print("usage: luajit tools/find.lua [--questiedb <version>] <quest|item|npc|object> <text> [more text ...]")
	os.exit(1)
end
if not arg[2] then usage() end
local tocPath, words = deps.questiedb(arg, here .. "../")
local kind = table.remove(words, 1)
if not kind or not words[1] then usage() end

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

for _, word in ipairs(words) do
	local needle = word:lower()
	print("== " .. word)
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
