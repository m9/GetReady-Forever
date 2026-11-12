-- Mocked test. Runs the data tools against a small fake QuestieDB store.
-- Usage: luajit tests/test.lua [QuestieDB_Forever.toc]
--   With a path, also checks the real database.

local here = arg[0]:gsub("[^/\\]*$", "")
package.path = here .. "../tools/lib/?.lua;" .. package.path

local base64 = require("base64")
local cbor = require("cbor")
local qdb = require("qdb")
local chain = require("chain")

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

-- base64 --------------------------------------------------------------------
eq("base64 decode", base64.decode("SGVsbG8="), "Hello")
eq("base64 encode", base64.encode("Hello"), "SGVsbG8=")
for _, s in ipairs({ "", "a", "ab", "abc", "\0\255\1\254" }) do
	eq("base64 round trip " .. #s, base64.decode(base64.encode(s)), s)
end

-- cbor ----------------------------------------------------------------------
eq("cbor uint", cbor.decode("\24\55"), 55)
eq("cbor uint16", cbor.decode("\25\1\0"), 256)
eq("cbor negative", cbor.decode("\56\99"), -100)
eq("cbor text", cbor.decode("\99abc"), "abc")
eq("cbor half float", cbor.decode("\249\62\0"), 1.5)
eq("cbor double", cbor.decode("\251\63\248\0\0\0\0\0\0"), 1.5)
do
	local t = cbor.decode(cbor.encode({ 1, { 2, 3 }, "x", 70000, -5 }))
	eq("cbor array len", #t, 5)
	eq("cbor nested", t[2][2], 3)
	eq("cbor uint32", t[4], 70000)
	eq("cbor neg round trip", t[5], -5)
	local m = cbor.decode(cbor.encode({ [1] = "name", [4] = 55, p = 4096 }))
	eq("cbor map int key", m[4], 55)
	eq("cbor map string key", m.p, 4096)
	check("cbor trailing bytes rejected", not pcall(cbor.decode, "\1\1"))
end

-- fake store ----------------------------------------------------------------
local lines = { "## Interface: 16001", "## X-Flavor: Forever", "src\\config.lua" }
local function field(id, index, value)
	lines[#lines + 1] = ("## X-Quest-%d-%s: %s"):format(id, tostring(index), base64.encode(cbor.encode(value)))
end
local function quest(id, name, level, minLevel, tables)
	local mask = 0
	for index, value in pairs(tables or {}) do
		mask = mask + 2 ^ (index - 1)
		field(id, index, value)
	end
	field(id, "S", { [1] = name, [4] = minLevel, [5] = level, p = mask })
end

-- 1 -> 2 -> (3, 4 both need 2) -> 5 needs all of 3 and 4 -> 6 needs any of 5 or 99
quest(1, "First", 10, 8)
quest(2, "Second", 11, 8, { [13] = { 1 } })
quest(3, "Left", 12, 9, { [13] = { 2 } })
quest(4, "Right", 12, 9, { [13] = { 2 } })
quest(5, "Both", 13, 10, { [12] = { 3, -4 } })
quest(6, "Goal", 14, 10, { [13] = { 5, 99 } })

-- one quest stored in parts
do
	local s = base64.encode(cbor.encode({ [1] = "Chunked quest name", [4] = 1, [5] = 2, p = 0 }))
	local half = math.floor(#s / 2)
	lines[#lines + 1] = "## X-Quest-7-S: ~2~"
	lines[#lines + 1] = "## X-Quest-7-S-1: " .. s:sub(1, half)
	lines[#lines + 1] = "## X-Quest-7-S-2: " .. s:sub(half + 1) .. "\r"
end

-- records for the build test
local function record(prefix, id, scalars, tables)
	local mask = 0
	for index, value in pairs(tables or {}) do
		mask = mask + 2 ^ (index - 1)
		lines[#lines + 1] = ("## X-%s-%d-%d: %s"):format(prefix, id, index, base64.encode(cbor.encode(value)))
	end
	scalars.p = mask
	lines[#lines + 1] = ("## X-%s-%d-S: %s"):format(prefix, id, base64.encode(cbor.encode(scalars)))
end
-- Horde quest 20 -> 21: given by npc 500, kill npc 501, collect item 700 (drops from npc 501)
record("Quest", 20, { [1] = "Horde start", [4] = 30, [5] = 32, [6] = 178 },
	{ [2] = { { 500 } }, [3] = { { 500 } }, [10] = { [1] = { { 501, false, 0 } }, [3] = { { 700, false, 0 } } } })
record("Quest", 21, { [1] = "Horde goal", [4] = 31, [5] = 33, [6] = 178 },
	{ [2] = { { 500 } }, [3] = { [2] = { 600 } }, [13] = { 20 } })
record("Quest", 22, { [1] = "Alliance only", [4] = 31, [5] = 33, [6] = 77 }, {})
record("Quest", 23, { [1] = "Mixed goal", [4] = 31, [5] = 33, [6] = 178 }, { [13] = { 22 } })
-- druid quests (class mask 1024): 30 -> 31 lead to one another, 32 stands alone, 33 can be repeated
record("Quest", 30, { [1] = "Druid start", [4] = 10, [5] = 10, [7] = 1024 }, {})
record("Quest", 31, { [1] = "Druid form", [4] = 10, [5] = 12, [6] = 32, [7] = 1024 }, { [13] = { 30 } })
record("Quest", 32, { [1] = "Druid errand", [4] = 20, [5] = 20, [7] = 1024 }, {})
record("Quest", 33, { [1] = "Druid daily", [4] = 20, [5] = 20, [7] = 1024, [24] = 1 }, {})
record("Npc", 500, { [1] = "Giver", [9] = 14 }, { [7] = { [14] = { { 45, 12 } }, [17] = { { 1, 2 } } } })
record("Npc", 501, { [1] = "Target" }, {})
record("Object", 600, { [1] = "Stone" }, { [4] = { [25] = { { -1, -1 } } } })
record("Item", 700, { [1] = "Trophy" }, { [2] = { 501 } })
record("Item", 701, { [1] = "Key" }, {})
-- loot: a sword and a helm from npc 501; a cloak that drops everywhere; a herb (not gear)
record("Item", 710, { [1] = "Sword", [12] = 2 }, { [2] = { 501 } })
record("Item", 711, { [1] = "Helm", [12] = 4 }, { [2] = { 501 } })
record("Item", 712, { [1] = "Cloak", [12] = 4 }, { [2] = { 501, 502, 503, 504, 505, 506 } })
record("Item", 713, { [1] = "Herb", [12] = 7 }, { [2] = { 501 } })

local i = 0
local db = qdb.fromLines(function() i = i + 1 return lines[i] end)

eq("meta", db:meta("Flavor"), "Forever")
eq("quest count", #db:questIds(), 15)
eq("npc name", db:npc(500).name, "Giver")
eq("npc spawn", db:npc(500).spawns[14][1][1], 45)
eq("item drop", db:item(700).npcDrops[1], 501)
eq("object name", db:object(600).name, "Stone")
eq("npc count", #db:ids("npc"), 2)
eq("quest name", db:quest(2).name, "Second")
eq("quest level", db:quest(2).questLevel, 11)
eq("quest min level", db:quest(2).requiredLevel, 8)
eq("pre single", db:quest(2).preQuestSingle[1], 1)
eq("no pre", db:quest(1).preQuestSingle, nil)
eq("unknown quest", db:quest(12345), nil)
eq("chunked quest", db:quest(7).name, "Chunked quest name")

-- chain ---------------------------------------------------------------------
do
	local steps = chain.build(db, 6)
	local order, at = {}, {}
	for n, step in ipairs(steps) do order[n] = step.id; at[step.id] = n end
	eq("chain size", #steps, 7)
	eq("chain ends at goal", order[#order], 6)
	eq("chain starts at root", order[1], 1)
	check("prerequisites first", at[2] < at[3] and at[2] < at[4] and at[3] < at[5] and at[4] < at[5] and at[5] < at[6])
	eq("no duplicates", #steps, 7)
	local both = steps[at[5]]
	eq("all group size", #both.all, 2)
	eq("all group sign dropped", both.all[2], 4)
	eq("any group", steps[at[6]].any[2], 99)
	check("missing quest marked", steps[at[99]].missing == true)
end

-- build ---------------------------------------------------------------------
local build = require("build")
eq("side none", build.side(nil), "Both")
eq("side horde", build.side(178), "Horde")
eq("side alliance", build.side(77), "Alliance")
eq("side horde, new race bit", build.side(8589934770), "Horde")
eq("side alliance, new race bit", build.side(4294967373), "Alliance")
eq("side all", build.side(255), "Both")
do
	local defs = { { id = "test", name = "Test chain", kind = "key", goal = 21, reward = 701 } }
	local result = build.run(db, defs)
	eq("build: no problems", #result.problems, 0)
	local c = result.chains[1]
	eq("build: side from goal", c.side, "Horde")
	eq("build: level", c.level, 30)
	eq("build: steps", #c.steps, 2)
	eq("build: kill", c.steps[1].kill[1], 501)
	eq("build: items", c.steps[1].items[1], 700)
	eq("build: giver npc", c.steps[1].from.npc[1], 500)
	eq("build: turn in at object", c.steps[2].to.object[1], 600)
	eq("build: prerequisite", c.steps[2].any[1], 20)
	eq("build: npc place", result.npcs[500].area, 14)
	eq("build: npc x", result.npcs[500].x, 45)
	eq("build: drop npc listed", result.npcs[501].name, "Target")
	eq("build: item drop", result.items[700].npc[1], 501)
	eq("build: reward item", result.items[701].name, "Key")

	local text = build.render(result, "mock")
	eq("build: same output twice", build.render(build.run(db, defs), "mock"), text)
	local ns = {}
	local chunk, err = loadstring(text)
	check("build: output loads", chunk ~= nil, err)
	if chunk then
		chunk("GetReady", ns)
		eq("output: chain id", ns.Chains[1].id, "test")
		eq("output: reward", ns.Chains[1].reward, 701)
		eq("output: step quest", ns.Chains[1].steps[2].quest, 21)
		eq("output: npc name", ns.Npcs[500].name, "Giver")
		eq("output: no position inside an instance", ns.Objects[600].x, nil)
		eq("output: area kept", ns.Objects[600].area, 25)
		eq("output: item name", ns.Items[700].name, "Trophy")
	end

	local function problems(def) return build.run(db, { def }).problems end
	eq("problem: missing goal", #problems({ id = "a", name = "A", kind = "raid", goal = 9999 }), 1)
	eq("problem: bad kind", #problems({ id = "a", name = "A", kind = "nope", goal = 21 }), 1)
	eq("problem: missing reward", #problems({ id = "a", name = "A", kind = "raid", goal = 21, reward = 9999 }), 1)
	eq("problem: missing quest in chain", #problems({ id = "a", name = "A", kind = "raid", goal = 6 }), 1)
	eq("problem: mixed sides", #problems({ id = "a", name = "A", kind = "raid", goal = 23 }), 1)
	local twice = build.run(db, { defs[1], defs[1] }).problems
	eq("problem: id used twice", #twice, 1)
end

-- build: zones, several goals, dungeon zones --------------------------------
do
	local zones = require("zones")
	-- area 14 is on map 1411; area 25 is a dungeon (other area 26) entered from area 14
	local z = zones.from({ [14] = 1411, [17] = 1413 }, {
		{ id = 25, name = "Deep Hole", areas = { 25, 26 }, entrances = { { 14, 50, 60 } } },
	})
	local p = z:place(14, 45, 12)
	eq("place: map", p.map, 1411)
	eq("place: x", p.x, 45)
	eq("place: not inside", p.inside, nil)
	p = z:place(26, -1, -1)
	eq("place: dungeon area", p.area, 25)
	eq("place: inside", p.inside, true)
	eq("place: dungeon name", z.areaName[25], "Deep Hole")
	eq("place: entrance map", p.map, 1411)
	eq("place: entrance x", p.x, 50)
	eq("place: unknown area keeps area", z:place(99, 1, 2).area, 99)
	eq("place: unknown area has no map", z:place(99, 1, 2).map, nil)

	local result = build.run(db, { { id = "test", name = "Test chain", kind = "key", goal = 21 } }, z)
	eq("zones: npc map", result.npcs[500].map, 1411)
	eq("zones: object inside", result.objects[600].inside, true)
	eq("zones: object entrance", result.objects[600].y, 60)

	-- several goals, one enough
	result = build.run(db, { { id = "multi", name = "Multi", kind = "raid", goals = { 3, 4 }, any = true } })
	eq("goals: no problems", #result.problems, 0)
	local c = result.chains[1]
	eq("goals: any flag", c.any, true)
	eq("goals: steps", #c.steps, 4)
	eq("goals: marked", (c.steps[3].goal and "y" or "n") .. (c.steps[4].goal and "y" or "n") .. (c.steps[1].goal and "y" or "n"), "yyn")
	eq("goals: side both", c.side, "Both")

	-- per-step side in a chain for both sides
	result = build.run(db, { { id = "both", name = "Both", kind = "misc", goals = { 21, 22 } } })
	c = result.chains[1]
	eq("step side: horde", c.steps[1].side, "Horde")
	eq("step side: alliance", c.steps[3].side, "Alliance")
	check("step side: output keeps it", build.render(result, "mock"):find('side = "Alliance"', 1, true) ~= nil)
end

-- dungeon zone: quests 30, 31 are in area 25/26, 32 is repeatable, 33 leads to 31
do
	local zones = require("zones")
	local extra = {}
	local function rec(prefix, id, scalars, tables)
		local mask = 0
		for index, value in pairs(tables or {}) do
			mask = mask + 2 ^ (index - 1)
			extra[#extra + 1] = ("## X-%s-%d-%d: %s"):format(prefix, id, index, base64.encode(cbor.encode(value)))
		end
		scalars.p = mask
		extra[#extra + 1] = ("## X-%s-%d-S: %s"):format(prefix, id, base64.encode(cbor.encode(scalars)))
	end
	rec("Quest", 30, { [1] = "In the hole", [4] = 20, [5] = 22, [17] = 25, [7] = 128 }, { [19] = { 529, 3000 } })
	rec("Quest", 31, { [1] = "Deeper", [4] = 18, [5] = 22, [17] = 26 }, { [13] = { 33 } })
	rec("Quest", 32, { [1] = "Again and again", [4] = 18, [5] = 22, [17] = 25, [24] = 1 }, {})
	rec("Quest", 33, { [1] = "Lead-in", [4] = 16, [5] = 20, [17] = 14 }, {})
	rec("Quest", 34, { [1] = "Key quest", [4] = 20, [5] = 22, [17] = 25 }, { [3] = { [2] = { 601 } } })
	local n = 0
	local zdb = qdb.fromLines(function() n = n + 1 return extra[n] end)
	local z = zones.from({ [14] = 1411 }, { { id = 25, name = "Deep Hole", areas = { 25, 26 }, entrances = { { 14, 50, 60 } } } })

	local result = build.run(zdb, {
		{ id = "hole", name = "Deep Hole", kind = "dungeon", zone = 25 },
		{ id = "hole-key", name = "Hole Key", kind = "key", goal = 34 },
	}, z)
	eq("zone: no problems", #result.problems, 0, result.problems[1])
	eq("zone: order kept", result.chains[1].id, "hole")
	local c = result.chains[1]
	local order = {}
	for i, step in ipairs(c.steps) do order[i] = step.quest end
	eq("zone: quests", table.concat(order, ","), "33,31,30")
	eq("zone: repeatable left out", order[4], nil)
	eq("zone: lead-in is not a goal", c.steps[1].goal, nil)
	eq("zone: dungeon quest is a goal", c.steps[2].goal, true)
	eq("zone: class kept", c.steps[3].classes, 128)
	eq("zone: reputation kept", c.steps[3].rep[2], 3000)
	eq("zone: entrance map", c.at.map, 1411)
	eq("zone: entrance x", c.at.x, 50)
	eq("zone: quest of another chain left out", #result.chains[2].steps, 1)
	eq("warning: unknown object", #result.warnings, 1)
	eq("unknown object has no name", result.objects[601].name, nil)

	eq("problem: empty zone", #build.run(zdb, { { id = "x", name = "X", kind = "dungeon", zone = 77 } }, z).problems, 1)
	eq("problem: nothing to do", #build.run(zdb, { { id = "x", name = "X", kind = "key" } }, z).problems, 1)
	eq("item-only chain builds", #build.run(db, { { id = "x", name = "X", kind = "key", reward = 701 } }).chains, 1)

	-- race limits: a mask that picks races is kept, a whole side or everyone is not
	eq("races: tauren only", build.races(32), 32)
	eq("races: new race only", build.races(2 ^ 33), 2 ^ 33)
	eq("races: classic horde is the whole side", build.races(178), nil)
	eq("races: horde with its new race", build.races(178 + 2 ^ 33), nil)
	eq("races: everyone", build.races(0), nil)
	eq("side: new alliance race", build.side(2 ^ 32), "Alliance")
	eq("side: new horde race", build.side(2 ^ 33), "Horde")

	-- class chains: one definition, a chain per group of quests that lead to one another
	local classy = build.run(db, {
		{ id = "x", name = "X", kind = "key", reward = 701 },
		{ class = 1024, id = "c-druid", name = "Druid" },
	})
	eq("class: no problems", #classy.problems, 0)
	eq("class: chains made", #classy.chains, 3)
	local form, other = classy.chains[2], classy.chains[3]
	eq("class: named after the last quest", form.id .. " " .. form.name, "c-druid-31 Druid form")
	eq("class: kind and class", form.kind .. " " .. tostring(form.classes), "class 1024")
	eq("class: steps in order", form.steps[1].quest .. ">" .. form.steps[2].quest, "30>31")
	check("class: the last quest is the goal", form.steps[2].goal and not form.steps[1].goal)
	eq("class: race limit kept on the step", form.steps[2].races, 32)
	eq("class: loose quests share a chain", other.id .. " " .. other.name .. " " .. #other.steps, "c-druid-other Other Druid quests 1")
	eq("class: repeatable quests are left out", other.steps[1].quest, 32)
	check("class: written to the file", build.render(classy, "mock"):find('kind = "class", side = "Horde", classes = 1024', 1, true) ~= nil)
	eq("class: needs an id and a name", #build.run(db, { { class = 1024 } }).problems, 1)

	-- loot: gear from the creatures a chain sends you to kill
	local looted = build.run(db, { { id = "test", name = "Test chain", kind = "key", goal = 21 } })
	local loot = looted.chains[1].loot
	eq("loot: one source", loot and #loot, 1)
	eq("loot: creature, then its gear", loot and table.concat(loot[1], ","), "501,710,711")
	check("loot: written to the file", build.render(looted, "mock"):find("loot = { { 501, 710, 711 } }", 1, true) ~= nil)
	eq("loot: none for a chain without kills", build.run(db, { { id = "x", name = "X", kind = "key", reward = 701 } }).chains[1].loot, nil)
end

-- real database (optional) --------------------------------------------------
if arg[1] then
	local real = qdb.open(arg[1])
	local ids = real:questIds()
	check("real: has quests", #ids > 1000, #ids)
	local bad = 0
	for _, id in ipairs(ids) do
		if not pcall(real.quest, real, id) then bad = bad + 1 end
	end
	eq("real: decode failures", bad, 0)
	local zones = require("zones")
	local z = zones.load((arg[1]:gsub("[^/\\]*$", "")), real:meta("Flavor"))
	eq("real: badlands map", z.map[3], 1418)
	eq("real: badlands name", z.areaName[3], "Badlands")
	eq("real: dungeon name", z.areaName[1583], "Blackrock Spire")
	eq("real: faction name", z.faction[529], "Argent Dawn")
	eq("real: faction name with small words", z.faction[910], "Brood of Nozdormu")
	check("real: quest xp", (z.xp[7848] or 0) > 0)
	eq("real: blackrock spire is a dungeon", z.dungeonOf[1583] and z.dungeonOf[1583].name, "Blackrock Spire")
	eq("real: scholomance other areas are not entrances", #z.dungeon[2057].entrances, 1)
	local mc = real:quest(7848)
	eq("real: quest 7848 name", mc and mc.name, "Attunement to the Core")
	print(("real database: %d quests read"):format(#ids))
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
