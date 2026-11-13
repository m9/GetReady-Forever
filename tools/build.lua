-- Builds Data/Chains.lua from chains/*.lua and the quest database.
-- Usage: luajit tools/build.lua <QuestieDB_Forever.toc> [--check]
--   --check  build but do not write; fail if Data/Chains.lua would change.

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "lib/?.lua;" .. package.path

local qdb = require("qdb")
local build = require("build")
local zones = require("zones")

local tocPath, check = nil, false
for i = 1, #arg do
	if arg[i] == "--check" then check = true else tocPath = tocPath or arg[i] end
end
if not tocPath then
	print("usage: luajit tools/build.lua <QuestieDB_Forever.toc> [--check]")
	os.exit(1)
end

local root = here .. "../"
local SOURCES = { "chains/vanilla.lua", "chains/dungeons.lua", "chains/classes.lua" }
local OUT = root .. "Data/Chains.lua"

local defs = {}
for _, file in ipairs(SOURCES) do
	for _, def in ipairs(assert(dofile(root .. file), file .. " must return a list")) do
		defs[#defs + 1] = def
	end
end

local db = qdb.open(tocPath)
local dbDir = tocPath:gsub("[^/\\]*$", "")
local result = build.run(db, defs, zones.load(dbDir, db:meta("Flavor")), dofile(root .. "chains/fixes.lua"))

for _, text in ipairs(result.problems) do print("PROBLEM " .. text) end
for _, text in ipairs(result.warnings) do print("warning: " .. text) end
for _, c in ipairs(result.chains) do
	print(("%-20s %-9s %3d steps  %s"):format(c.id, c.side, #c.steps, c.name))
end
if #result.problems > 0 then
	print(#result.problems .. " problems. Nothing written.")
	os.exit(1)
end

local version = db:meta("BUILD-COMMIT")
local text = build.render(result, "QuestieDB " .. (db:meta("Flavor") or "?")
	.. (version and (" " .. version:sub(1, 8)) or ""))

local old
local f = io.open(OUT, "rb")
if f then old = f:read("*a") f:close() end

if old == text then
	print("Data/Chains.lua is up to date.")
elseif check then
	print("Data/Chains.lua is out of date. Run the build.")
	os.exit(1)
else
	f = assert(io.open(OUT, "wb"))
	f:write(text)
	f:close()
	print("Wrote Data/Chains.lua.")
end
