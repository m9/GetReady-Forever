-- Builds Data/Chains.lua from chains/*.lua and the quest database.
-- Usage: luajit tools/build.lua [--check] [--questiedb <version>]
--   --check      build but do not write; fail if Data/Chains.lua would change.
--   --questiedb  build against this QuestieDB version, not the one deps.lua records.
--   The database is downloaded into .cache/ when it is not there (tools/lib/deps.lua).
--   A path to a QuestieDB_Forever.toc as the first argument reads that file instead.

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "lib/?.lua;" .. package.path

local qdb = require("qdb")
local build = require("build")
local zones = require("zones")
local deps = require("deps")

local root = here .. "../"
local tocPath, rest, other = deps.questiedb(arg, root)
local check = false
for _, word in ipairs(rest) do
	if word ~= "--check" then
		print("usage: luajit tools/build.lua [--check] [--questiedb <version>]")
		os.exit(1)
	end
	check = true
end
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
	if other then print("Built against QuestieDB " .. other .. ", which may not be the version deps.lua records.") end
end
