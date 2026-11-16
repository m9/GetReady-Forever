-- Manages the outside data the tools work with (see tools/lib/deps.lua).
-- Usage: luajit tools/deps.lua [command]
--   status                  what deps.lua records and whether it is in the cache (default)
--   fetch [name] [version]  download into .cache/; without a name, the recorded QuestieDB
--   check [name]            ask GitHub whether a newer version exists
--   use <name> [version]    record a version in deps.lua; without a version, the newest
--   path <name> [version]   print the folder of a version, downloading it when needed
-- Names: questiedb (version like 1.1.1), attune (a commit of its wow-forever branch).

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "lib/?.lua;" .. package.path

local deps = require("deps")
local d = deps.new(here .. "../")

local function label(info)
	if not info then return "none" end
	local commit = info.commit and info.commit:sub(1, 8)
	if info.version and commit then return info.version .. " (" .. commit .. ")" end
	return info.version or commit or "?"
end

local function names(name)
	return name and { name } or deps.NAMES
end

local commands = {}

function commands.status()
	local pins = d:pins()
	for _, name in ipairs(deps.NAMES) do
		local pin = pins[name]
		local id = pin and (name == "attune" and pin.commit or pin.version)
		print(("%-10s %-28s %s"):format(name, label(pin), id and d:kept(name, id) and "in the cache" or "not downloaded"))
	end
end

function commands.fetch(name, version)
	name = name or "questiedb"
	local dir, info = d:fetch(name, version)
	print(("%s %s is in %s"):format(name, label(info), dir))
end

function commands.check(name)
	for _, n in ipairs(names(name)) do
		local pin, latest, differs = d:check(n)
		print(("%-10s recorded %s, newest %s: %s"):format(n, label(pin), label(latest),
			differs and ("newer version available (luajit tools/deps.lua use " .. n .. ")") or "up to date"))
	end
end

function commands.use(name, version)
	if not name then error("deps: use needs a name: questiedb or attune", 0) end
	local info, checked = d:use(name, version)
	print(("deps.lua now records %s %s."):format(name, label(info)))
	if not checked then
		print("No checksum was known for it beforehand; deps.lua records the one of this download.")
	end
	if name == "questiedb" then print("Rebuild the data: luajit tools/build.lua") end
end

function commands.path(name, version)
	if not name then error("deps: path needs a name: questiedb or attune", 0) end
	print((d:fetch(name, version)))
end

local command = commands[arg[1] or "status"]
if not command then
	print("usage: luajit tools/deps.lua [status | fetch [name] [version] | check [name] | use <name> [version] | path <name> [version]]")
	os.exit(1)
end
deps.guard(command, arg[2], arg[3])
