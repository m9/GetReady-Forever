-- Outside data the tools work with: which version, where it comes from, and a local copy.
--
-- deps.lua in the repo root records one version of each. Copies are kept in .cache/, which git
-- ignores, as .cache/<name>/<id>/. A copy is complete once the file "ok" is in it.
--   questiedb  The Forever zip of a QuestieDB release (github.com/Questie/QuestieDB).
--              Its id is the version, "1.1.1".
--   attune     Three files of the Attune addon at one commit of its wow-forever branch
--              (github.com/CixiDelmont/Attune; the repo has no releases or tags).
--              Its id is the commit. Only tools/compare.lua reads it, and nothing of it
--              goes into the repo.
-- A download is checked against the SHA-256 in deps.lua. For a version that is not recorded,
-- QuestieDB's zip is checked against the checksum GitHub publishes for it.

local sha256 = require("sha256")
local json = require("json")

local deps = {}

local WINDOWS = package.config:sub(1, 1) == "\\"

local function quote(s)
	if WINDOWS then return '"' .. s .. '"' end
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run(command)
	local status = os.execute(command)
	return status == 0 or status == true
end

-- Everything that touches the disk or the network. Tests pass their own.
local system = {}

function system.download(url, path)
	return run("curl -fsSL --retry 2 -o " .. quote(path) .. " " .. quote(url))
end

-- bsdtar (macOS, Windows) reads zip files; GNU tar does not, so unzip is tried after it.
function system.extract(archive, dir)
	return run("tar -xf " .. quote(archive) .. " -C " .. quote(dir))
		or run("unzip -q -o " .. quote(archive) .. " -d " .. quote(dir))
end

function system.mkdir(path)
	if WINDOWS then
		path = quote((path:gsub("/", "\\")))
		return run("if not exist " .. path .. " mkdir " .. path)
	end
	return run("mkdir -p " .. quote(path))
end

function system.read(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

function system.write(path, data)
	local f = assert(io.open(path, "wb"))
	f:write(data)
	f:close()
end

function system.remove(path)
	os.remove(path)
end

function system.log(text)
	io.stderr:write(text .. "\n")
end

local API = "https://api.github.com/repos/"
local ATTUNE_RAW = "https://raw.githubusercontent.com/CixiDelmont/Attune/"
local ATTUNE_BRANCH = "wow-forever"

-- Per dependency: the field that names a version (key), the files of one version, and how to
-- ask GitHub about a version (lookup; without a spec, the newest one).
local SOURCES = {}

SOURCES.questiedb = {
	title = "QuestieDB",
	key = "version",
	files = function(info)
		local name = "QuestieDB-" .. info.version .. "-Forever.zip"
		return { {
			name = name,
			url = "https://github.com/Questie/QuestieDB/releases/download/v" .. info.version .. "/" .. name,
			unpack = true,
		} }
	end,
	lookup = function(self, spec)
		local release = self:api("Questie/QuestieDB/releases/" .. (spec and ("tags/v" .. spec) or "latest"))
		local version = tostring(release.tag_name):match("^v(.+)$")
			or error("deps: unexpected QuestieDB release tag " .. tostring(release.tag_name), 0)
		local info = { version = version, files = {} }
		if tostring(release.target_commitish):match("^%x+$") then info.commit = release.target_commitish end
		local zip = "QuestieDB-" .. version .. "-Forever.zip"
		for _, asset in ipairs(release.assets or {}) do
			local sum = type(asset.digest) == "string" and asset.digest:match("^sha256:(%x+)$")
			if asset.name == zip and sum then info.files[zip] = sum:lower() end
		end
		return info
	end,
}

SOURCES.attune = {
	title = "Attune",
	key = "commit",
	files = function(info)
		local list = {}
		for i, name in ipairs({ "Attune.toc", "AttuneData.lua", "AttuneClassQuests.lua" }) do
			list[i] = { name = name, url = ATTUNE_RAW .. info.commit .. "/" .. name }
		end
		return list
	end,
	lookup = function(self, spec)
		local commit = self:api("CixiDelmont/Attune/commits/" .. (spec or ATTUNE_BRANCH)).sha
		if type(commit) ~= "string" or not commit:match("^%x+$") then
			error("deps: GitHub gave no commit for Attune " .. (spec or ATTUNE_BRANCH), 0)
		end
		local toc = self:text(ATTUNE_RAW .. commit .. "/Attune.toc")
		return { version = toc:match("## Version:%s*([^\r\n]+)"), commit = commit, files = {} }
	end,
}

deps.NAMES = { "questiedb", "attune" }

local D = {}
D.__index = D

-- root: the repo folder, with a trailing slash. sys: replacements for the functions above.
function deps.new(root, sys)
	return setmetatable({
		root = root,
		cache = (os.getenv("GETREADY_CACHE") or (root .. ".cache")):gsub("[/\\]$", "") .. "/",
		sys = setmetatable(sys or {}, { __index = system }),
	}, D)
end

local function source(name)
	return SOURCES[name] or error("deps: unknown dependency " .. tostring(name) .. " (known: questiedb, attune)", 0)
end

local function entry(info, indent)
	local lines = { "{" }
	if info.version then lines[#lines + 1] = ('\tversion = "%s",'):format(info.version) end
	if info.commit then lines[#lines + 1] = ('\tcommit = "%s",'):format(info.commit) end
	local names = {}
	for name in pairs(info.files or {}) do names[#names + 1] = name end
	table.sort(names)
	lines[#lines + 1] = "\tfiles = {"
	for _, name in ipairs(names) do
		lines[#lines + 1] = ('\t\t["%s"] = "%s",'):format(name, info.files[name])
	end
	lines[#lines + 1] = "\t},"
	lines[#lines + 1] = "}"
	return table.concat(lines, "\n" .. indent)
end

-- The text of deps.lua for a table of recorded versions.
function deps.render(pins)
	local out = {
		"-- The versions of outside data the tools work with, and the SHA-256 of each download.",
		"-- Change it with: luajit tools/deps.lua use <name> [version]",
		"return {",
	}
	for _, name in ipairs(deps.NAMES) do
		if pins[name] then out[#out + 1] = "\t" .. name .. " = " .. entry(pins[name], "\t") .. "," end
	end
	out[#out + 1] = "}"
	return table.concat(out, "\n") .. "\n"
end

local function load(text, name)
	if not text then return nil end
	local chunk = loadstring(text, name) or error("deps: cannot read " .. name, 0)
	return setfenv(chunk, {})()
end

function D:pins()
	return load(self.sys.read(self.root .. "deps.lua"), "deps.lua") or {}
end

function D:dir(name, id)
	return self.cache .. name .. "/" .. id .. "/"
end

-- What is in the cache under this id: { version, commit, files }, or nil.
function D:kept(name, id)
	return load(self.sys.read(self:dir(name, id) .. "ok"), "ok")
end

function D:text(url)
	local path = self.cache .. "request.tmp"
	self.sys.mkdir(self.cache)
	if not self.sys.download(url, path) then error("deps: could not download " .. url, 0) end
	local text = self.sys.read(path) or ""
	self.sys.remove(path)
	return text
end

function D:api(path)
	local ok, data = pcall(json.decode, self:text(API .. path))
	if not ok or type(data) ~= "table" then error("deps: unexpected answer from " .. API .. path, 0) end
	return data
end

-- The version a spec stands for. No spec: the recorded one. "latest": the newest.
-- Asks GitHub only when the version is neither recorded nor in the cache.
function D:resolve(name, spec)
	local src = source(name)
	local pin = self:pins()[name]
	if spec == nil then
		return pin or error("deps: deps.lua records no version of " .. name, 0)
	end
	if not spec:match("^[%w%._%-]+$") then error("deps: not a version: " .. spec, 0) end
	if spec == "latest" then return src.lookup(self) end
	if pin and pin[src.key] == spec then return pin end
	return self:kept(name, spec) or src.lookup(self, spec)
end

-- Makes sure a version is in the cache. Returns its folder, what is in it, and whether
-- every file was checked against a checksum known beforehand.
function D:fetch(name, spec)
	local src = source(name)
	local info = self:resolve(name, spec)
	local id = info[src.key]
	local dir = self:dir(name, id)
	local known = info.files or {}

	local kept = self:kept(name, id)
	if kept then
		for file, sum in pairs(known) do
			if kept.files[file] ~= sum then
				error(("deps: the copy of %s in %s is not the recorded one (%s). Delete that folder and run again.")
					:format(src.title, dir, file), 0)
			end
		end
		return dir, kept, true
	end

	self.sys.log(("Downloading %s %s"):format(src.title, info.version or id))
	self.sys.mkdir(dir)
	local sums, checked = {}, true
	for _, file in ipairs(src.files(info)) do
		local path = dir .. file.name
		if not self.sys.download(file.url, path) then error("deps: could not download " .. file.url, 0) end
		local sum = sha256.sum(self.sys.read(path) or "")
		if known[file.name] and known[file.name] ~= sum then
			self.sys.remove(path)
			error(("deps: %s has SHA-256 %s, expected %s"):format(file.url, sum, known[file.name]), 0)
		end
		checked = checked and known[file.name] ~= nil
		sums[file.name] = sum
		if file.unpack then
			if not self.sys.extract(path, dir) then error("deps: could not unpack " .. path, 0) end
			self.sys.remove(path)
		end
	end
	local done = { version = info.version, commit = info.commit, files = sums }
	self.sys.write(dir .. "ok", "return " .. entry(done, "") .. "\n")
	return dir, done, checked
end

-- Records a version in deps.lua, after fetching it. No spec means the newest.
function D:use(name, spec)
	local _, info, checked = self:fetch(name, spec or "latest")
	local pins = self:pins()
	pins[name] = info
	self.sys.write(self.root .. "deps.lua", deps.render(pins))
	return info, checked
end

-- Compares the recorded version with the newest. Returns both and whether they differ.
function D:check(name)
	local src = source(name)
	local pin = self:pins()[name]
	local latest = src.lookup(self)
	return pin, latest, not pin or pin[src.key] ~= latest[src.key]
end

local TOC = "QuestieDB/QuestieDB_Forever.toc"

-- Path of the QuestieDB TOC of a version, downloading it when it is not in the cache.
function D:toc(spec)
	return self:fetch("questiedb", spec) .. TOC
end

-- The same for the recorded version, but nil when it is not in the cache. Never downloads.
function D:cachedToc()
	local pin = self:pins().questiedb
	if pin and self:kept("questiedb", pin.version) then return self:dir("questiedb", pin.version) .. TOC end
end

-- Splits a tool's arguments into "--questiedb <version>" and "--attune <commit>" and the rest.
function deps.split(arg)
	local rest, opts = {}, {}
	local i = 1
	while i <= #arg do
		local name = arg[i]:match("^%-%-(%a+)$")
		if name and SOURCES[name] then
			opts[name] = arg[i + 1] or error("deps: --" .. name .. " needs a version", 0)
			i = i + 2
		else
			rest[#rest + 1] = arg[i]
			i = i + 1
		end
	end
	return rest, opts
end

-- Runs fn; on an error prints it and exits.
function deps.guard(fn, ...)
	local result = { xpcall(fn, function(err)
		return type(err) == "string" and err:find("^deps: ") and err or debug.traceback(err, 2)
	end, ...) }
	if not result[1] then
		io.stderr:write(tostring(result[2]) .. "\n")
		os.exit(1)
	end
	return unpack(result, 2)
end

-- For the tools that read QuestieDB. Returns the TOC path, the arguments that are left, and
-- the version asked for with --questiedb (nil for the recorded one).
--   An argument that ends in .toc is that path, and nothing is downloaded.
function deps.questiedb(arg, root)
	return deps.guard(function()
		local rest, opts = deps.split(arg)
		for i, word in ipairs(rest) do
			if word:lower():find("%.toc$") then return table.remove(rest, i), rest, nil end
		end
		return deps.new(root):toc(opts.questiedb), rest, opts.questiedb
	end)
end

return deps
