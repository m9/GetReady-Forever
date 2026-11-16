-- Tests for the download side of the tools (tools/lib/deps.lua, sha256.lua, json.lua).
-- The disk and the network are fakes, so nothing is downloaded or written.
-- Usage: luajit tests/deps_test.lua

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "../tools/lib/?.lua;" .. package.path

local sha256 = require("sha256")
local json = require("json")
local deps = require("deps")

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end
local function eq(name, got, want) check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end
local function fails(name, fn, text)
	local ok, err = pcall(fn)
	check(name, not ok and tostring(err):find(text, 1, true) ~= nil, ok and "no error" or err)
end

-- sha256 --------------------------------------------------------------------
eq("sha256 empty", sha256.sum(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
eq("sha256 abc", sha256.sum("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
eq("sha256 two blocks", sha256.sum("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
	"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
eq("sha256 a million a", sha256.sum(("a"):rep(1000000)), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
eq("sha256 55 bytes", sha256.sum(("a"):rep(55)), "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318")
eq("sha256 56 bytes", sha256.sum(("a"):rep(56)), "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a")
eq("sha256 64 bytes", sha256.sum(("a"):rep(64)), "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")

-- json ----------------------------------------------------------------------
do
	local v = json.decode('{"a": [1, -2.5, 1e3, true, false, "x\\n\\"y\\u00e9"], "b": {"c": null, "d": "e"}, "f": []}')
	eq("json number", v.a[1], 1)
	eq("json negative", v.a[2], -2.5)
	eq("json exponent", v.a[3], 1000)
	eq("json true", v.a[4], true)
	eq("json false", v.a[5], false)
	eq("json string escapes", v.a[6], 'x\n"y\195\169')
	eq("json null", v.b.c, nil)
	eq("json nested", v.b.d, "e")
	eq("json empty list", #v.f, 0)
	fails("json rejects a cut text", function() json.decode('{"a": [1, 2') end, "json:")
	fails("json rejects text after the value", function() json.decode("1 2") end, "json:")
end

-- a fake disk and network ---------------------------------------------------
local ZIP = "zip bytes of 1.1.1"
local ZIP2 = "zip bytes of 1.2.0"
local C1, C2 = ("1"):rep(40), ("2"):rep(40)

local function world(pin)
	local w = { files = {}, web = {}, asked = {}, logged = {} }
	w.sys = {
		download = function(url, path)
			w.asked[#w.asked + 1] = url
			if not w.web[url] then return false end
			w.files[path] = w.web[url]
			return true
		end,
		extract = function(archive, dir)
			w.files[dir .. "QuestieDB/QuestieDB_Forever.toc"] = "unpacked " .. w.files[archive]
			return true
		end,
		mkdir = function() return true end,
		read = function(path) return w.files[path] end,
		write = function(path, data) w.files[path] = data end,
		remove = function(path) w.files[path] = nil end,
		log = function(text) w.logged[#w.logged + 1] = text end,
	}
	w.files["/r/deps.lua"] = pin
	w.web["https://github.com/Questie/QuestieDB/releases/download/v1.1.1/QuestieDB-1.1.1-Forever.zip"] = ZIP
	w.web["https://github.com/Questie/QuestieDB/releases/download/v1.2.0/QuestieDB-1.2.0-Forever.zip"] = ZIP2
	local function release(version, commit, zip)
		return ('{"tag_name": "v%s", "target_commitish": "%s", "assets": ['
			.. '{"name": "QuestieDB-%s-all.zip", "digest": "sha256:%s"},'
			.. '{"name": "QuestieDB-%s-Forever.zip", "digest": "sha256:%s"},'
			.. '{"name": "release.json", "digest": null}]}')
			:format(version, commit, version, ("0"):rep(64), version, sha256.sum(zip))
	end
	w.web["https://api.github.com/repos/Questie/QuestieDB/releases/latest"] = release("1.2.0", C2, ZIP2)
	w.web["https://api.github.com/repos/Questie/QuestieDB/releases/tags/v1.2.0"] = release("1.2.0", C2, ZIP2)
	w.web["https://api.github.com/repos/Questie/QuestieDB/releases/tags/v1.1.1"] = release("1.1.1", C1, ZIP)
	for commit, version in pairs({ [C1] = "16001-40", [C2] = "16001-41" }) do
		local raw = "https://raw.githubusercontent.com/CixiDelmont/Attune/" .. commit .. "/"
		w.web[raw .. "Attune.toc"] = "## Title: Attune\r\n## Version: " .. version .. "\r\n"
		w.web[raw .. "AttuneData.lua"] = "data " .. version
		w.web[raw .. "AttuneClassQuests.lua"] = "class quests " .. version
		w.web["https://api.github.com/repos/CixiDelmont/Attune/commits/" .. commit] = '{"sha": "' .. commit .. '"}'
	end
	w.web["https://api.github.com/repos/CixiDelmont/Attune/commits/wow-forever"] = '{"sha": "' .. C2 .. '"}'
	w.d = deps.new("/r/", w.sys)
	return w
end

local PIN = deps.render({
	questiedb = { version = "1.1.1", commit = C1, files = { ["QuestieDB-1.1.1-Forever.zip"] = sha256.sum(ZIP) } },
	attune = { version = "16001-40", commit = C1, files = {
		["Attune.toc"] = sha256.sum("## Title: Attune\r\n## Version: 16001-40\r\n"),
		["AttuneData.lua"] = sha256.sum("data 16001-40"),
		["AttuneClassQuests.lua"] = sha256.sum("class quests 16001-40"),
	} },
})

-- the recorded versions -----------------------------------------------------
do
	local w = world(PIN)
	local pins = w.d:pins()
	eq("pins: questiedb version", pins.questiedb.version, "1.1.1")
	eq("pins: attune commit", pins.attune.commit, C1)
	eq("render: the same text again", deps.render(pins), PIN)
	eq("cache folder", w.d:dir("questiedb", "1.1.1"), "/r/.cache/questiedb/1.1.1/")
	eq("cachedToc: nothing yet", w.d:cachedToc(), nil)
	eq("cachedToc: asks nobody", #w.asked, 0)

	-- 1. the recorded version is downloaded, checked and unpacked
	local dir, info, checked = w.d:fetch("questiedb")
	eq("fetch: folder", dir, "/r/.cache/questiedb/1.1.1/")
	eq("fetch: one download", #w.asked, 1)
	eq("fetch: from the release, without asking the API", w.asked[1],
		"https://github.com/Questie/QuestieDB/releases/download/v1.1.1/QuestieDB-1.1.1-Forever.zip")
	eq("fetch: unpacked", w.files[dir .. "QuestieDB/QuestieDB_Forever.toc"], "unpacked " .. ZIP)
	eq("fetch: zip removed", w.files[dir .. "QuestieDB-1.1.1-Forever.zip"], nil)
	eq("fetch: checked", checked, true)
	eq("fetch: says what it has", info.version, "1.1.1")
	eq("fetch: says so once", #w.logged, 1)
	eq("toc path", w.d:toc(), "/r/.cache/questiedb/1.1.1/QuestieDB/QuestieDB_Forever.toc")
	eq("cachedToc: now there", w.d:cachedToc(), "/r/.cache/questiedb/1.1.1/QuestieDB/QuestieDB_Forever.toc")
	eq("second fetch downloads nothing", #w.asked, 1)

	-- 3. another version on request: looked up, checked against GitHub's checksum, pin untouched
	local dir2, info2, checked2 = w.d:fetch("questiedb", "1.2.0")
	eq("chosen version: folder", dir2, "/r/.cache/questiedb/1.2.0/")
	eq("chosen version: commit from the release", info2.commit, C2)
	eq("chosen version: checked", checked2, true)
	eq("chosen version: unpacked", w.files[dir2 .. "QuestieDB/QuestieDB_Forever.toc"], "unpacked " .. ZIP2)
	eq("chosen version: deps.lua untouched", w.files["/r/deps.lua"], PIN)
	local before = #w.asked
	w.d:fetch("questiedb", "1.2.0")
	eq("chosen version: in the cache, asks nobody", #w.asked, before)

	-- 2. is there a newer one
	local pin, latest, differs = w.d:check("questiedb")
	eq("check: recorded", pin.version, "1.1.1")
	eq("check: newest", latest.version, "1.2.0")
	eq("check: differs", differs, true)
	eq("check: deps.lua untouched", w.files["/r/deps.lua"], PIN)

	-- recording the newest
	local used = w.d:use("questiedb")
	eq("use: newest by default", used.version, "1.2.0")
	local now = w.d:pins()
	eq("use: recorded version", now.questiedb.version, "1.2.0")
	eq("use: recorded commit", now.questiedb.commit, C2)
	eq("use: recorded checksum", now.questiedb.files["QuestieDB-1.2.0-Forever.zip"], sha256.sum(ZIP2))
	eq("use: the other entry stays", now.attune.commit, C1)
	eq("check: up to date after use", select(3, w.d:check("questiedb")), false)
	w.d:use("questiedb", "1.1.1")
	eq("use: back to the old version gives the old file", w.files["/r/deps.lua"], PIN)
end

-- attune --------------------------------------------------------------------
do
	local w = world(PIN)
	local dir, info, checked = w.d:fetch("attune")
	eq("attune: folder is the commit", dir, "/r/.cache/attune/" .. C1 .. "/")
	eq("attune: three downloads", #w.asked, 3)
	eq("attune: data file", w.files[dir .. "AttuneData.lua"], "data 16001-40")
	eq("attune: class quests file", w.files[dir .. "AttuneClassQuests.lua"], "class quests 16001-40")
	eq("attune: checked", checked, true)
	eq("attune: version", info.version, "16001-40")
	for path in pairs(w.files) do
		check("attune: nothing outside the cache (" .. path .. ")", path == "/r/deps.lua" or path:find("/r/.cache/", 1, true) == 1)
	end

	local _, latest, differs = w.d:check("attune")
	eq("attune check: newest commit", latest.commit, C2)
	eq("attune check: newest version", latest.version, "16001-41")
	eq("attune check: differs", differs, true)

	local used, known = w.d:use("attune")
	eq("attune use: commit", used.commit, C2)
	eq("attune use: version read from its TOC", used.version, "16001-41")
	eq("attune use: no checksum was known beforehand", known, false)
	eq("attune use: checksum recorded", w.d:pins().attune.files["AttuneData.lua"], sha256.sum("data 16001-41"))
	eq("attune use: questiedb entry stays", w.d:pins().questiedb.version, "1.1.1")
end

-- what must fail ------------------------------------------------------------
do
	local w = world(PIN)
	w.web["https://github.com/Questie/QuestieDB/releases/download/v1.1.1/QuestieDB-1.1.1-Forever.zip"] = "tampered"
	fails("wrong checksum stops the fetch", function() w.d:fetch("questiedb") end, "expected " .. sha256.sum(ZIP))
	eq("wrong checksum: nothing unpacked", w.files["/r/.cache/questiedb/1.1.1/QuestieDB/QuestieDB_Forever.toc"], nil)
	eq("wrong checksum: download removed", w.files["/r/.cache/questiedb/1.1.1/QuestieDB-1.1.1-Forever.zip"], nil)
	eq("wrong checksum: not marked complete", w.d:kept("questiedb", "1.1.1"), nil)

	w = world(PIN)
	w.web["https://github.com/Questie/QuestieDB/releases/download/v1.2.0/QuestieDB-1.2.0-Forever.zip"] = "tampered"
	fails("a chosen version is checked against GitHub's checksum", function() w.d:fetch("questiedb", "1.2.0") end, "expected")

	w = world(PIN)
	fails("a version that does not exist", function() w.d:fetch("questiedb", "9.9.9") end, "could not download")
	fails("an unknown name", function() w.d:fetch("questie") end, "unknown dependency")
	fails("a version with odd characters", function() w.d:fetch("questiedb", "1.1.1/../x") end, "not a version")
	fails("nothing recorded", function() world(nil).d:fetch("questiedb") end, "records no version")

	-- a cached copy that is not the recorded one
	w = world(PIN)
	w.d:fetch("questiedb")
	w.files["/r/deps.lua"] = PIN:gsub(sha256.sum(ZIP), ("f"):rep(64))
	fails("cache differs from the record", function() w.d:fetch("questiedb") end, "not the recorded one")
end

-- arguments of the tools ----------------------------------------------------
do
	local rest, opts = deps.split({ "--check", "--questiedb", "1.1.0", "quest", "--attune", "abc", "text" })
	eq("split: rest", table.concat(rest, " "), "--check quest text")
	eq("split: questiedb", opts.questiedb, "1.1.0")
	eq("split: attune", opts.attune, "abc")
	fails("split: option without a value", function() deps.split({ "--questiedb" }) end, "needs a version")
	local toc, left, other = deps.questiedb({ "--check", "some/QuestieDB_Forever.toc" }, "/nowhere/")
	eq("a TOC path is used as it is", toc, "some/QuestieDB_Forever.toc")
	eq("a TOC path: the rest", table.concat(left, " "), "--check")
	eq("a TOC path: no version", other, nil)
end

-- the repo's own deps.lua ---------------------------------------------------
do
	local real = deps.new(here .. "../")
	local pins = real:pins()
	check("deps.lua records a QuestieDB version", pins.questiedb and pins.questiedb.version ~= nil)
	check("deps.lua has a checksum for its zip", pins.questiedb
		and #(pins.questiedb.files["QuestieDB-" .. pins.questiedb.version .. "-Forever.zip"] or "") == 64)
	check("deps.lua records an Attune commit", pins.attune and #(pins.attune.commit or "") == 40)
	local f = assert(io.open(here .. "../deps.lua", "rb"))
	local text = f:read("*a")
	f:close()
	eq("deps.lua is as the tool writes it", text, deps.render(pins))
	local ignore = assert(io.open(here .. "../.gitignore", "rb"))
	check(".gitignore covers the cache", ("\n" .. ignore:read("*a")):find("\n/.cache/", 1, true) ~= nil)
	ignore:close()
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
