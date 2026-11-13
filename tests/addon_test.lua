-- Mocked test for the addon itself. Loads the files the TOC lists, with fake game calls.
-- Usage: luajit tests/addon_test.lua

local here = arg[0]:gsub("[^/\\]*$", "")
local root = here .. "../"

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		io.write("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "") .. "\n")
	end
end
local function eq(name, got, want) check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end

-- Fake game ------------------------------------------------------------------
local world = { done = {}, log = {}, items = {}, standing = {}, level = 60, faction = "Horde", classId = 1 }
local pins, printed = {}, {}

local function Mock(kind, name)
	local o = { kind = kind, scripts = {}, shown = true }
	setmetatable(o, { __index = function(_, k)
		if k == "SetScript" or k == "HookScript" then return function(self, event, fn) self.scripts[event] = fn end end
		if k == "SetAlpha" then return function(self, v) self.alpha = v end end
		if k == "SetText" then return function(self, v) self.text = v end end
		if k == "GetText" then return function(self) return rawget(self, "text") end end
		if k == "Show" then return function(self) self.shown = true end end
		if k == "Hide" then return function(self) self.shown = false end end
		if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
		if k == "IsShown" then return function(self) return self.shown end end
		if k == "SetHeight" then return function(self, v) self.height = v end end
		if k == "SetSize" then return function(self, w, h) self.sizeW, self.sizeH = w, h end end
		if k == "SetWidth" then return function(self, v) self.widthSet = v end end
		if k == "SetPoint" then return function(self, ...) self.point = { ... } end end
		if k == "SetColorTexture" then return function(self, r, g, b, a) self.color = { r, g, b, a } end end
		if k == "SetScale" then return function(self, v) self.scale = v end end
		if k == "SetTexture" then return function(self, v) self.texture = v end end
		if k == "SetHorizontalScroll" then return function(self, v) self.scrollX = v end end
		if k == "SetVerticalScroll" then return function(self, v) self.scrollY = v end end
		if k == "GetPoint" then return function(self) return "CENTER", UIParent, "CENTER", 12, -34 end end
		if k == "SetFont" then return function() return true end end
		if k == "CreateTexture" or k == "CreateFontString" or k == "CreateMaskTexture" then return function() return Mock(k) end end
		return function() end
	end })
	if name then _G[name] = o end
	return o
end

local frames = {}
function CreateFrame(kind, name, parent, template)
	local f = Mock(kind, name)
	f.parent, f.template = parent, template
	frames[#frames + 1] = f
	return f
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
UIParent = Mock("Frame")
Minimap = Mock("Frame")
Minimap.GetWidth = function() return 140 end
Minimap.GetCenter = function() return 500, 400 end
Minimap.GetEffectiveScale = function() return 2 end
local cursor = { 0, 0 }
function GetCursorPosition() return cursor[1], cursor[2] end
UISpecialFrames = {}
SlashCmdList = {}
tinsert = table.insert
C_Timer = { After = function(_, fn) fn() end }
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
function UnitLevel() return world.level end
function UnitFactionGroup() return world.faction, world.faction end
function UnitRace() return "Race", "RACE", world.raceId end -- nil race: no race filter
function UnitName() return world.name or "Tester" end
function GetRealmName() return "Realm" end
local CLASS_FILE = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", nil, "SHAMAN", "MAGE", "WARLOCK", nil, "DRUID" }
function UnitClass() return "Class", CLASS_FILE[world.classId] or "CLASS", world.classId end
-- item id -> { class, subclass, slot }; skills the character has trained
world.kinds, world.skills = {}, {}
function IsPlayerSpell(id) return world.skills[id] or false end
function GetSpellInfo(id) return "Skill " .. id end
C_QuestLog = {
	IsQuestFlaggedCompleted = function(id) return world.done[id] or false end,
	IsOnQuest = function(id) return world.log[id] or false end,
	GetTitleForQuestID = function() return nil end,
}
local tips = {}
C_Item = {
	GetItemCount = function(id) return world.items[id] or 0 end,
	GetItemNameByID = function(id) return world.itemNames and world.itemNames[id] end,
	GetItemIconByID = function(id) return "icon" .. id end,
	GetItemQualityByID = function(id) return id == 70 and 4 or nil end,
	GetItemInfoInstant = function(id)
		local k = world.kinds[id]
		if k then return id, "", "", k[3] or "", "icon" .. id, k[1], k[2] end
	end,
}
ITEM_QUALITY_COLORS = { [4] = { r = 0.64, g = 0.21, b = 0.93 } }
GameTooltip = {
	SetOwner = function(self, owner) tips.owner = owner end,
	SetItemByID = function(self, id) tips.item, tips.lines = id, {} end,
	SetText = function(self, text) tips.title, tips.lines = text, {} end,
	AddLine = function(self, text) tips.lines[#tips.lines + 1] = text end,
	Show = function() tips.shown = true end,
	Hide = function() tips.shown = false end,
}
C_Map = {
	GetAreaInfo = function(id) if id < 10000 then return "Area " .. id end end,
	CanSetUserWaypointOnMap = function(map) return map ~= 999 end,
	SetUserWaypoint = function(point) pins[#pins + 1] = point end,
}
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) pins.tracked = v end }
C_Reputation = { GetFactionDataByID = function(id)
	if world.standing[id] then return { reaction = world.standing[id], name = "Faction " .. id } end
end }
FACTION_STANDING_LABEL4, FACTION_STANDING_LABEL6, FACTION_STANDING_LABEL7 = "Neutral", "Honored", "Revered"

-- Load the files the TOC lists -------------------------------------------------
local ns = {}
local loaded, savedVars, tocIcon = 0, nil, nil
for line in io.lines(root .. "GetReady.toc") do
	line = line:gsub("\r$", "")
	savedVars = savedVars or line:match("^## SavedVariables: (.+)$")
	tocIcon = tocIcon or line:match("^## IconTexture: (.+)$")
	if line ~= "" and not line:match("^#") then
		local path = root .. line:gsub("\\", "/")
		local chunk, err = loadfile(path)
		check("loads " .. line, chunk ~= nil, err)
		if chunk then chunk("GetReady", ns) loaded = loaded + 1 end
	end
end
eq("toc file count", loaded, 8)
eq("toc icon is the addon's icon", tocIcon, ns.ICON)
eq("toc saved variable", savedVars, "GetReadyDB")

-- Settings load on ADDON_LOADED
local eventFrame = frames[1]
check("event handler set", type(eventFrame.scripts.OnEvent) == "function")
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "SomethingElse")
check("other addon ignored", GetReadyDB == nil)
GetReadyDB = { selected = "ony-horde" }
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "GetReady")
check("settings table used", ns.db == GetReadyDB)
check("settings get defaults", type(ns.db.closed) == "table")
-- the first time, every section of the list is folded
check("first run: sections start folded", ns.db.closed.raid and ns.db.closed.dungeon and ns.db.closed.key and ns.db.closed.misc and ns.db.closed["class-1"] and ns.db.closed["class-1024"])
check("first run: remembered as done", ns.db.folded == true)
do
	local allClosed = true
	for _, g in ipairs(ns.View.Build(nil, ns.db.closed, {}).groups) do if not g.closed then allClosed = false end end
	check("first run: the list shows only headings", allClosed)
	-- the player opens one; a later load leaves it as it is
	ns.db.closed.raid = nil
	eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "GetReady")
	check("later runs: sections stay as the player left them", ns.db.closed.raid == nil and ns.db.closed.dungeon == true)
end
for k in pairs(ns.db.closed) do ns.db.closed[k] = nil end -- the tests below want the whole list

-- the minimap button
do
	local b = GetReadyMinimapButton
	check("minimap: button made when the settings load", b ~= nil and b.shown)
	eq("minimap: on the minimap", b and b.parent, Minimap)
	eq("minimap: shows the addon's icon", b.icon.texture, ns.ICON)
	-- 215 degrees on a circle of 75: lower left
	check("minimap: default place is lower left", b.point[4] < -60 and b.point[5] < -40, b.point[4] .. "," .. b.point[5])
	-- dragged to straight above the minimap's middle
	cursor = { 1000, 1000 }
	b.scripts.OnDragStart(b)
	b.scripts.OnUpdate(b)
	b.scripts.OnDragStop(b)
	eq("minimap: drag saves the angle", ns.db.minimap.angle, 90)
	check("minimap: drag moves it to the top", math.abs(b.point[4]) < 0.001 and b.point[5] == 75, b.point[4] .. "," .. b.point[5])
	check("minimap: drag ends", rawget(b.scripts, "OnUpdate") == nil)
	SlashCmdList.GETREADY("minimap")
	check("minimap: slash hides", ns.db.minimap.hide == true and not b.shown)
	check("minimap: says how to get it back", printed[#printed]:find("/gr minimap", 1, true) ~= nil)
	SlashCmdList.GETREADY(" Minimap ")
	check("minimap: slash shows again", ns.db.minimap.hide == nil and b.shown)
	b.scripts.OnEnter(b)
	check("minimap: tooltip", tips.title == "Get Ready" and tips.lines[1] == "Click to open or close.")
	check("minimap: window not open yet", not ns.Window.IsShown())
	b.scripts.OnClick(b)
	check("minimap: click opens the window", ns.Window.IsShown())
	b.scripts.OnClick(b)
	check("minimap: click closes it again", not ns.Window.IsShown())
end

local Progress = ns.Progress
local realData = { Chains = ns.Chains, Npcs = ns.Npcs, Objects = ns.Objects, Items = ns.Items, Areas = ns.Areas, Factions = ns.Factions }

-- Engine, small made-up chain ---------------------------------------------------
-- 1 -> 2 -> (3, 4) -> 5 needs all of 3 and 4 -> 6 needs any of 5 or 99 (99 is outside the chain)
local chain = { id = "t", name = "T", kind = "key", side = "Both", reward = 900, steps = {
	{ quest = 1, name = "One", min = 10, from = { npc = { 50 } }, to = { npc = { 50 } } },
	{ quest = 2, name = "Two", min = 10, any = { 1 }, kill = { 51 }, items = { 70 }, use = { 60 }, to = { object = { 60 } } },
	{ quest = 3, name = "Three", min = 10, any = { 2 } },
	{ quest = 4, name = "Four", min = 10, any = { 2 } },
	{ quest = 5, name = "Five", min = 20, all = { 3, 4 } },
	{ quest = 6, name = "Six", min = 20, goal = true, any = { 5, 99 }, from = { item = { 70 } } },
} }
ns.Npcs = {
	[50] = { name = "Giver", area = 3, map = 1418, x = 5.81, y = 47.52 },
	[51] = { name = "Boss", area = 1583, inside = true, map = 1428, x = 29.4, y = 38.3 },
	[52] = {},
}
ns.Objects = { [60] = { name = "Stone" } }
ns.Items = { [70] = { name = "Trophy" }, [900] = { name = "Big Key", npc = { 51 } }, [901] = { name = "Lost Key" } }

local function reset(level)
	world.done, world.log, world.items, world.standing = {}, {}, {}, {}
	world.level, world.faction, world.classId = level or 60, "Horde", 1
end
local function states(c)
	local p = Progress.Chain(c or chain)
	return table.concat(p.states, " "), p
end

reset()
do
	local s, p = states()
	eq("fresh", s, "ready locked locked locked locked ready")
	eq("fresh count", p.complete, 0)
	eq("fresh not done", p.done, false)
	eq("fresh total", p.total, 6)
end

reset(5)
do
	local s, p = states()
	eq("low level", s, "locked locked locked locked locked locked")
	eq("low level reason", p.need[1].level, 10)
	eq("low level hint", Progress.Hints(chain.steps[1], "locked", p.need[1])[1], "Required level: 10")
end

reset()
world.done[1] = true
world.log[2] = true
eq("one done, two in log", (states()), "done active locked locked locked ready")

reset()
world.done[1], world.done[2] = true, true
eq("branch opens", (states()), "done done ready ready locked ready")
world.done[3] = true
eq("all-group waits", (states()), "done done done ready locked ready")
world.done[4] = true
eq("all-group opens", (states()), "done done done done ready ready")

reset(15)
world.done[1], world.done[2], world.done[3], world.done[4] = true, true, true, true
do
	local s, p = states()
	eq("level gate inside chain", s, "done done done done locked locked")
	eq("level gate reason", p.need[5].level, 20)
end

reset()
world.log[3] = true
eq("later quest in log covers earlier", (states()), "skipped skipped active ready locked ready")

reset()
world.done[6] = true
do
	local s, p = states()
	eq("goal done covers all", s, "skipped skipped skipped skipped skipped done")
	eq("goal done", p.done, true)
	eq("goal done count", p.complete, 6)
end

reset()
world.items[900] = 1
do
	local s, p = states()
	eq("reward owned", p.done, true)
	eq("reward owned states", s, "skipped skipped skipped skipped skipped skipped")
end

-- Faction and class filters, per step
local mixed = { id = "m", name = "M", kind = "dungeon", side = "Both", steps = {
	{ quest = 11, name = "Horde only", side = "Horde", goal = true },
	{ quest = 12, name = "Alliance only", side = "Alliance", goal = true },
	{ quest = 13, name = "Warrior", classes = 1 },
	{ quest = 14, name = "Mage", classes = 128 },
	{ quest = 15, name = "After class quest", any = { 13, 14 }, goal = true },
} }
reset()
do
	local s, p = states(mixed)
	eq("filter: horde warrior sees 3 steps", p.total, 3)
	eq("filter: step names", p.steps[1].name .. "/" .. p.steps[2].name .. "/" .. p.steps[3].name, "Horde only/Warrior/After class quest")
	eq("filter: follow-up waits for own class quest", s, "ready ready locked")
	world.done[14] = true -- the mage version is done on this character (should not happen, but counts)
	eq("filter: hidden quest turned in counts", (states(mixed)), "ready ready ready")
end
reset()
world.faction, world.classId = "Alliance", 8 -- mage
do
	local _, p = states(mixed)
	eq("filter: alliance mage steps", p.steps[1].name .. "/" .. p.steps[2].name, "Alliance only/Mage")
end

-- Several goals: all needed
reset()
world.done[11] = true
do
	local s, p = states(mixed)
	eq("goals: one of two done", p.done, false)
	world.done[13], world.done[15] = true, true
	s, p = states(mixed)
	eq("goals: all visible done", p.done, true)
	eq("goals: all states", s, "done done done")
end

-- Several goals: one is enough
local pick = { id = "p", name = "P", kind = "raid", side = "Both", any = true, steps = {
	{ quest = 21, name = "Cheap", goal = true, rep = { 529, 0 } },
	{ quest = 22, name = "Mid", goal = true, rep = { 529, 21000 } },
} }
reset()
world.standing[529] = 6 -- honored
do
	local s, p = states(pick)
	eq("rep: honored opens the first only", s, "ready locked")
	eq("rep: reason standing", p.need[2].standing, 7)
	eq("rep: hint", Progress.Hints(pick.steps[2], "locked", p.need[2])[1], "Needs Revered with Faction 529")
	world.done[21] = true
	s, p = states(pick)
	eq("any-goal: done with one", p.done, true)
	eq("any-goal: other skipped", s, "done skipped")
end
reset()
eq("rep: unknown faction does not lock", (states(pick)), "ready ready")

-- Chain that is only an item
local itemOnly = { id = "i", name = "I", kind = "key", side = "Both", reward = 900, steps = {} }
reset()
do
	local p = Progress.Chain(itemOnly)
	eq("item chain: not done", p.done, false)
	eq("item chain: no steps", p.total, 0)
	local h = Progress.RewardHints(itemOnly)
	eq("item chain: get line", h[1], "Get: Big Key")
	eq("item chain: source line", h[2], "From: Boss (in Area 1583)")
	eq("item chain: no source known", #Progress.RewardHints({ reward = 901 }), 1)
	world.items[900] = 1
	eq("item chain: done when owned", Progress.Chain(itemOnly).done, true)
end

-- Hints, targets, next step
reset()
eq("hint start", Progress.Hints(chain.steps[1], "ready")[1], "Start: Giver (Area 3 5.8, 47.5)")
eq("hint start from item", Progress.Hints(chain.steps[6], "ready")[1], "Start: Trophy")
ns.Npcs[53] = { name = "Imp", area = 10026, inside = true }
ns.Areas = { [10026] = "Dire Maul" }
ns.Factions = { [76] = "Orgrimmar" }
eq("hint uses the stored dungeon name", Progress.Hints({ from = { npc = { 53 } } }, "ready")[1], "Start: Imp (in Dire Maul)")
do
	local h = Progress.Hints(chain.steps[2], "active")
	eq("hint kill", h[1], "Kill: Boss")
	eq("hint use", h[2], "Use: Stone")
	eq("hint get", h[3], "Get: Trophy")
	eq("hint turn in", h[4], "Turn in: Stone")
	eq("hint none when done", #Progress.Hints(chain.steps[2], "done"), 0)
	eq("hint skips unknown names", #Progress.Hints({ from = { npc = { 52 } } }, "ready"), 0)

	local t = Progress.Target(chain.steps[1], "ready")
	eq("target map", t and t.map, 1418)
	eq("target x", t and t.x, 5.81)
	eq("no target without position", Progress.Target(chain.steps[2], "active"), nil)
	eq("no target when locked", Progress.Target(chain.steps[1], "locked"), nil)

	local step, state = Progress.Next(chain)
	eq("next: first ready", step.quest, 1)
	eq("next: state", state, "ready")
	world.log[6] = true
	step, state = Progress.Next(chain)
	eq("next: quest in log wins", step.quest, 6)
	world.done[6], world.log[6] = true, nil
	eq("next: none when done", Progress.Next(chain), nil)
end

-- Waypoint call
reset()
check("waypoint set", ns.api.SetWaypoint(1418, 5.81, 47.52))
eq("waypoint map", pins[1].map, 1418)
eq("waypoint x is a fraction", pins[1].x, 0.0581)
eq("waypoint tracked", pins.tracked, true)
check("waypoint refused map", not ns.api.SetWaypoint(999, 1, 1))
check("waypoint without position", not ns.api.SetWaypoint(nil, 1, 1))

-- Rewards and what lies ahead
do
	local rc = { id = "r", name = "R", kind = "raid", side = "Both", reward = 900, note = "Opens a door.", steps = {
		{ quest = 31, name = "Start", min = 10, xp = 1200, repGain = { { 76, 150 } }, rewards = { 70 }, kill = { 51 } },
		{ quest = 32, name = "Middle", min = 62, any = { 31 }, xp = 800, rep = { 529, 21000 }, items = { 900 } },
		{ quest = 33, name = "End", min = 20, any = { 32 }, goal = true, xp = 5000, rewards = { 70, 901, 902, 903, 904, 905 } },
	} }
	ns.Items[902], ns.Items[903], ns.Items[904], ns.Items[905] = { name = "B" }, { name = "C" }, { name = "D" }, { name = "E" }
	reset()
	world.standing[529], world.standing[76] = 6, 5
	eq("reward line", Progress.RewardLine(rc.steps[1]), "Rewards: Trophy")
	eq("reward line cut short", Progress.RewardLine(rc.steps[3]), "Rewards: Trophy, Lost Key, B, C +2")
	eq("reward line none", Progress.RewardLine(rc.steps[2]), nil)
	world.itemNames = { [70] = "Trofey" }
	eq("reward line uses the game's name", Progress.RewardLine(rc.steps[1]), "Rewards: Trofey")
	world.itemNames = nil
	eq("gain line", Progress.GainLine(rc.steps[1]), "Gives: 1,200 XP, +150 Faction 76")
	eq("gain line xp only", Progress.GainLine(rc.steps[3]), "Gives: 5,000 XP")
	eq("gain line none", Progress.GainLine({ quest = 1 }), nil)
	world.standing[76] = nil
	eq("gain line falls back to the stored faction name", Progress.GainLine(rc.steps[1]), "Gives: 1,200 XP, +150 Orgrimmar")
	ns.Factions = {}
	eq("gain line unknown faction", Progress.GainLine(rc.steps[1]), "Gives: 1,200 XP, +150 reputation")

	local ahead = Progress.Ahead(rc)
	eq("ahead: quests", ahead.quests, 3)
	eq("ahead: xp", ahead.xp, 7000)
	eq("ahead: level above the player", ahead.level, 62)
	eq("ahead: standing needed", ahead.standing[1] and ahead.standing[1][2], 7)
	eq("ahead: dungeons", table.concat(ahead.dungeons, ","), "Area 1583")
	eq("ahead: rewards start with the chain item", ahead.rewards[1], 900)
	eq("ahead: then goal rewards, no repeats", #ahead.rewards, 7)
	eq("ahead: rewards of steps on the way come before the goal's", ahead.rewards[2], 70)
	check("ahead: nothing in hand yet", next(ahead.got) == nil)
	local lines = Progress.AheadLines(rc)
	eq("ahead line 1", lines[1], "Left: 3 quests, 7,000 XP")
	eq("ahead line 2", lines[2], "Dungeons: Area 1583")
	eq("ahead line 3", lines[3], "Needs: Revered with Faction 529")
	eq("ahead: no reputation line without a faction name", lines[4], nil)
	world.standing[76] = 5
	eq("ahead: reputation sum", Progress.Ahead(rc).rep[1][1] .. ":" .. Progress.Ahead(rc).rep[1][2], "76:150")
	eq("ahead: reputation line", Progress.AheadLines(rc)[4], "Reputation: +150 Faction 76")
	world.standing[76] = nil
	eq("xp text", Progress.XpText(rc.steps[1]), "1,200 XP")
	eq("xp text none", Progress.XpText({ quest = 1 }), nil)
	local dv = ns.View.Detail(rc)
	eq("view: step gain", dv.steps[3].gain, "Gives: 5,000 XP")
	eq("view: step xp", dv.steps[1].xp, "1,200 XP")
	eq("view: step reward line", dv.steps[3].rewardLine, "Rewards: Trophy, Lost Key, B, C +2")
	rc.level = 10
	dv = ns.View.Detail(rc)
	eq("view: step reputation", dv.steps[1].rep, "+150 reputation")
	eq("view: numbers", dv.stats[1].label .. "=" .. dv.stats[1].value .. " " .. dv.stats[2].label .. "=" .. dv.stats[2].value, "Quests=0 / 3 XP=7,000")
	eq("view: three numbers, no min level and no quests left", #dv.stats, 3)
	eq("view: XP has its own tone", dv.stats[2].tone, "xp")
	eq("view: facts", dv.facts[1].label .. "/" .. dv.facts[2].label .. "/" .. dv.facts[2].tone, "Dungeons/Needs/warn")
	eq("view: next box knows its state", dv.next.state, "ready")
	eq("view: tag", dv.tag, "Raid  -  Level 10+")
	world.level = 5
	eq("view: level too low is a warning", ns.View.Detail(rc).stats[3].tone, "warn")
	do
		-- level 5: step 1 asks for 10, step 2 for 62 and also waits for step 1, step 3 for 20
		local low = ns.View.Detail(rc)
		eq("level: every open step says what it asks for", low.steps[1].needLevel .. "/" .. low.steps[2].needLevel .. "/" .. low.steps[3].needLevel, "10/62/20")
		eq("level: line on a step locked by level", table.concat(low.steps[1].hints, "|"), "Required level: 10")
		eq("level: line on a step that also waits for an earlier one", table.concat(low.steps[2].hints, "|"), "Required level: 62")
		world.level = 15
		low = ns.View.Detail(rc)
		eq("level: none once the player is high enough", low.steps[1].needLevel, nil)
		eq("level: still on later steps", low.steps[3].needLevel, 20)
		world.done[31] = true
		eq("level: none on a finished step", ns.View.Detail(rc).steps[1].needLevel, nil)
		world.done[31] = nil
		world.level = 5
	end
	eq("view: next box locked", ns.View.Detail(rc).next.state, "locked")
	world.level = 60
	world.done[33] = true
	eq("view: done numbers", ns.View.Detail(rc).stats[1].value .. "/" .. ns.View.Detail(rc).stats[1].tone .. "/" .. ns.View.Detail(rc).next.state, "Done/good/done")
	world.done[33] = nil

	world.done[31] = true
	ahead = Progress.Ahead(rc)
	eq("ahead: fewer after a turn-in", ahead.quests, 2)
	eq("ahead: xp after a turn-in", ahead.xp, 5800)
	check("ahead: a reward the goal gives again is not in hand yet", not ahead.got[70])
	world.items[900] = 1
	check("ahead: owned chain item is in hand", Progress.Ahead(rc).got[900])
	world.items[900] = nil
	world.done[33] = true
	eq("ahead: nothing when done", #Progress.AheadLines(rc), 0)

	reset()
	eq("ahead: any-goal counts one quest", Progress.Ahead(pick).quests, 1)
	eq("ahead: any-goal line", Progress.AheadLines(pick)[1], "Left: 1 quest")
end

-- Steps as a graph
do
	reset()
	local g = ns.View.Graph(Progress.Chain(chain))
	local function cells()
		local out = {}
		for i, cell in ipairs(g.at) do out[i] = cell.col .. ":" .. cell.row end
		return table.concat(out, " ")
	end
	-- 1 -> 2 -> (3, 4) -> 5 -> 6: the fork takes a second row, the rest stays on the first
	eq("graph: cells", cells(), "1:1 2:1 3:1 3:2 4:1 5:1")
	eq("graph: size", g.cols .. "x" .. g.rows, "5x2")
	eq("graph: lines", #g.edges, 6)
	check("graph: quest outside the chain draws no line", g.edges[6].from == 5 and g.edges[6].to == 6)
	check("graph: nothing lit when nothing is done", not g.edges[1].lit)
	check("graph: linked chain opens as a graph", g.auto)
	world.done[1], world.done[2] = true, true
	g = ns.View.Graph(Progress.Chain(chain))
	check("graph: lit behind finished steps", g.edges[1].lit and g.edges[2].lit and g.edges[3].lit and not g.edges[4].lit)

	local d = ns.View.Detail(chain)
	eq("graph: detail mode", d.mode, "graph")
	eq("graph: detail steps carry cells", d.steps[4].col .. ":" .. d.steps[4].row, "3:2")
	eq("graph: starts at the next step", d.graph.focus, 3)
	eq("graph: step status", d.steps[1].status .. "/" .. d.steps[3].status .. "/" .. d.steps[5].status, "Turned in/Available/Locked")
	eq("graph: player picks the list", ns.View.Detail(chain, nil, { t = "list" }).mode, "list")

	reset()
	-- steps that do not lead to one another still have a graph: one column, one under the other
	local loose = ns.View.Graph(Progress.Chain(pick))
	check("graph: steps without links stand in one column", loose ~= nil and loose.cols == 1 and #loose.edges == 0 and loose.rows == #Progress.Chain(pick).steps)
	check("graph: but the list is what opens first", loose.auto == false)
	eq("graph: is what a chain opens as", ns.View.Detail(pick).mode, "graph")
	eq("graph: the list, once picked, is remembered", ns.View.Detail(pick, nil, { p = "list" }).mode, "list")
	d = ns.View.Detail(pick, nil, { p = "graph" })
	check("graph: the player can pick it", d.mode == "graph" and d.graph ~= nil)
	local single = ns.View.Graph(Progress.Chain({ id = "one", name = "One", kind = "misc", side = "Both", steps = { { quest = 9701, name = "Only", goal = true } } }))
	check("graph: a single step has one too", single ~= nil and single.cols == 1 and single.rows == 1)
	-- so does a chain that is only an item, through its made-up step
	local itemGraph = ns.View.Detail({ id = "ig", name = "IG", kind = "key", side = "Both", reward = 70, steps = {} }, nil, { ig = "graph" })
	check("graph: an item chain has one", itemGraph.graph ~= nil and itemGraph.mode == "graph" and itemGraph.steps[1].col == 1)
	-- a step with no level of its own in the data takes the quest's level for its bracket
	local noMin = ns.View.Detail({ id = "nm", name = "NM", kind = "misc", side = "Both", steps = { { quest = 9702, name = "Grudge", level = 15, goal = true }, { quest = 9703, name = "None", goal = true } } })
	eq("step level: the quest's level stands in", noMin.steps[1].min, 15)
	check("step level: none when there is neither", noMin.steps[2].min == nil)

	-- a step that waits for two branches of different length sits one past the longer one
	local join = { id = "j", name = "J", kind = "misc", side = "Both", steps = {
		{ quest = 41, name = "A" },
		{ quest = 42, name = "B", any = { 41 } },
		{ quest = 43, name = "C" },
		{ quest = 44, name = "D", all = { 42, 43 }, goal = true },
		{ quest = 45, name = "Alone" },
	} }
	g = ns.View.Graph(Progress.Chain(join))
	eq("graph: join cells", cells(), "1:1 2:1 1:2 3:1 1:3")
	check("graph: mostly linked steps open as a graph", g.auto)
	local loose = { id = "l", name = "L", kind = "dungeon", side = "Both", steps = {
		{ quest = 51, name = "A" }, { quest = 52, name = "B", any = { 51 } },
		{ quest = 53, name = "C" }, { quest = 54, name = "D" }, { quest = 55, name = "E" },
	} }
	g = ns.View.Graph(Progress.Chain(loose))
	check("graph: mostly loose quests open as a list", g ~= nil and not g.auto)
	eq("graph: but the player can pick the graph", ns.View.Detail(loose, nil, { l = "graph" }).mode, "graph")
end

-- Steps as a graph: side branches stand right beside the long way, and share rows
do
	reset()
	local function grid(c)
		local g = ns.View.Graph(Progress.Chain(c))
		local out = {}
		for i, cell in ipairs(g.at) do out[i] = cell.col .. ":" .. cell.row end
		return table.concat(out, " "), g
	end
	-- a long way M1..M6 with a one-step side branch off M1, M3 and M4
	local long = { id = "cp", name = "CP", kind = "misc", side = "Both", steps = {
		{ quest = 9001, name = "M1" }, { quest = 9002, name = "M2", all = { 9001 } }, { quest = 9003, name = "S1", all = { 9001 } },
		{ quest = 9004, name = "M3", all = { 9002 } }, { quest = 9005, name = "M4", all = { 9004 } }, { quest = 9006, name = "S3", all = { 9004 } },
		{ quest = 9007, name = "M5", all = { 9005 } }, { quest = 9008, name = "S4", all = { 9005 } }, { quest = 9009, name = "M6", all = { 9007 }, goal = true },
	} }
	local cells, g = grid(long)
	eq("compact: the long way is one row, the side steps share the row under it", cells, "1:1 2:1 2:2 3:1 4:1 4:2 5:1 5:2 6:1")
	eq("compact: two rows, not four", g.rows, 2)

	-- a branch that comes before the long way in the data stands over it, one after it under it
	local both = { id = "ab", name = "AB", kind = "misc", side = "Both", steps = {
		{ quest = 9011, name = "A" }, { quest = 9012, name = "Up", all = { 9011 } },
		{ quest = 9013, name = "B", all = { 9011 } }, { quest = 9014, name = "Down", all = { 9011 } },
		{ quest = 9015, name = "C", all = { 9013 } }, { quest = 9016, name = "D", all = { 9015 }, goal = true },
	} }
	eq("compact: one branch over the long way, one under", (grid(both)), "1:2 2:1 2:2 2:3 3:2 4:2")

	-- a branch does not go where another box stands: it takes the next row
	local deep = { id = "dp", name = "DP", kind = "misc", side = "Both", steps = {
		{ quest = 9021, name = "A" }, { quest = 9022, name = "B", all = { 9021 } }, { quest = 9023, name = "C", all = { 9022 }, goal = true },
		{ quest = 9024, name = "S", all = { 9021 } }, { quest = 9025, name = "S2", all = { 9024 } }, { quest = 9026, name = "S3", all = { 9025 } },
		{ quest = 9027, name = "T", all = { 9022 } },
	} }
	-- A B C on row 1 would be the shorter way; the longer A S S2 S3 takes the row, and B C, T go under
	local dcells, dg = grid(deep)
	local seen, clash = {}, false
	for cell in dcells:gmatch("%S+") do if seen[cell] then clash = true end seen[cell] = true end
	check("compact: no two boxes in one place", not clash, dcells)
	check("compact: the way that goes on furthest is the straight one", dg.at[1].row == dg.at[4].row and dg.at[4].row == dg.at[5].row and dg.at[5].row == dg.at[6].row, dcells)
	check("compact: the shorter way, earlier in the data, is over it", dg.at[2].row < dg.at[1].row and dg.at[3].row == dg.at[2].row, dcells)

	-- a line that runs along a row to a step further on keeps that row free of boxes
	local far = { id = "fr", name = "FR", kind = "misc", side = "Both", steps = {
		{ quest = 9031, name = "A" }, { quest = 9032, name = "B", all = { 9031 } }, { quest = 9033, name = "Far", all = { 9031 } },
		{ quest = 9034, name = "C", all = { 9032 } }, { quest = 9035, name = "Side", all = { 9032 } },
		{ quest = 9036, name = "D", all = { 9034 } }, { quest = 9037, name = "E", all = { 9036, 9033 }, goal = true },
	} }
	local fcells, fg = grid(far)
	-- "Far" (column 2) has a line to E (column 5) along its row; "Side" (column 3) must not stand in it
	check("compact: no box on a row where a line runs past", fg.at[5].row ~= fg.at[3].row, fcells)
	local through = 0
	local box = {}
	for i, c in ipairs(fg.at) do box[c.row .. ":" .. c.col] = i end
	for _, e in ipairs(fg.edges) do
		local a, b = fg.at[e.from], fg.at[e.to]
		for c = a.col + 1, b.col - 1 do if box[a.row .. ":" .. c] then through = through + 1 end end
	end
	eq("compact: so no line runs through a box", through, 0)

	-- parts that no line joins keep their own rows
	local parts = { id = "pt2", name = "PT", kind = "dungeon", side = "Both", steps = {
		{ quest = 9041, name = "X1" }, { quest = 9042, name = "X2", all = { 9041 } }, { quest = 9043, name = "X3", all = { 9042 } },
		{ quest = 9044, name = "Y1" }, { quest = 9045, name = "Z1" }, { quest = 9046, name = "Z2", all = { 9045 } },
	} }
	eq("compact: separate parts, one under the other", (grid(parts)), "1:1 2:1 3:1 1:2 1:3 2:3")

	-- a step only a later step needs stands beside that step, not at the bottom
	local road = { id = "rd", name = "RD", kind = "misc", side = "Both", steps = {
		{ quest = 9051, name = "M1" }, { quest = 9052, name = "M2", all = { 9051 } }, { quest = 9053, name = "Side", all = { 9051 } },
		{ quest = 9054, name = "M3", all = { 9052 } }, { quest = 9055, name = "Needed" }, { quest = 9056, name = "M4", all = { 9054, 9055 }, goal = true },
	} }
	local rcells, rg = grid(road)
	-- "Side" stands right under the way; "Needed" has a line along its row to M4, so it
	-- cannot share that row and takes the next one
	eq("compact: the side step is right under the way", rg.at[3].col .. ":" .. rg.at[3].row, "2:2")
	eq("compact: the needed quest on the nearest row its line has to itself", rg.at[5].col .. ":" .. rg.at[5].row, "1:3")
	eq("compact: three rows in all", rg.rows, 3)

	-- the real chain that showed the trouble: many one-quest side branches off one long way
	for _, c in ipairs(ns.Chains) do
		if c.id == "d-kroldok" then
			world.faction = "Horde"
			local kg = ns.View.Graph(Progress.Chain(c))
			check("compact: Krol'dok is a few rows, not one for every side quest", kg.rows <= 4, kg.rows)
		end
	end
	reset()
end

-- Can the character use an item?
do
	reset()
	world.kinds = {
		[1] = { 2, 8 }, -- two-handed sword
		[2] = { 2, 19 }, -- wand
		[3] = { 4, 4, "INVTYPE_CHEST" }, -- plate
		[4] = { 4, 1, "INVTYPE_CLOAK" }, -- cloak
		[5] = { 4, 0, "INVTYPE_FINGER" }, -- ring
		[6] = { 4, 7, "INVTYPE_RELIC" }, -- libram
		[7] = { 4, 1, "INVTYPE_ROBE" }, -- cloth robe
		[8] = { 0, 0 }, -- a potion
	}
	local use = ns.api.Usable
	world.skills = { [9078] = true }
	eq("usable: warrior without the skill can learn two-handed swords", (use(1)), "learn")
	eq("usable: names the skill", select(2, use(1)), "Skill 202")
	world.skills[202] = true
	eq("usable: warrior with the skill", use(1), "yes")
	eq("usable: no class but casters use wands", use(2), "no")
	eq("usable: plate before it is trained", (use(3)), "learn")
	eq("usable: cloak whatever the class", use(4), "yes")
	eq("usable: rings are not judged", use(5), nil)
	eq("usable: libram is for paladins", use(6), "no")
	eq("usable: cloth when trained", use(7), "yes")
	eq("usable: not gear", use(8), nil)
	eq("usable: unknown item", use(999), nil)
	world.classId = 8 -- mage
	eq("usable: mage and two-handed swords", use(1), "no")
	eq("usable: mage and plate", use(3), "no")
	world.skills[5009] = true
	eq("usable: mage and wands", use(2), "yes")
	world.classId = 2
	eq("usable: paladin and libram", use(6), "yes")

	-- the tooltip says so
	world.classId, world.skills = 8, {}
	ns.api.ItemTooltip("owner", 1, "Drops from Boss")
	eq("usable: tooltip keeps the note", tips.lines[1], "Drops from Boss")
	eq("usable: tooltip says the class cannot", tips.lines[2], "Your class cannot use this.")
	ns.api.ItemTooltip("owner", 2)
	eq("usable: tooltip says it can be learned", tips.lines[1], "You can learn to use this: Skill 5009.")
	ns.api.HideTooltip()
	world.kinds, world.skills = {}, {}
	reset()
end

-- Item calls
eq("item icon", ns.api.ItemIcon(70), "icon70")
eq("item quality color", (ns.api.ItemQualityColor(70)), 0.64)
eq("item quality unknown", ns.api.ItemQualityColor(71), nil)
ns.api.ItemTooltip("owner", 70)
eq("tooltip item", tips.item, 70)
check("tooltip shown", tips.shown)
ns.api.HideTooltip()
check("tooltip hidden", tips.shown == false)

-- Races, class chains, and whose chain it is
do
	local raced = { id = "rc", name = "RC", kind = "class", side = "Both", classes = 1024, steps = {
		{ quest = 61, name = "Shared start" },
		{ quest = 62, name = "Tauren goal", goal = true, races = 32, any = { 61 } },
		{ quest = 63, name = "Night elf goal", goal = true, races = 8, any = { 61 } },
		{ quest = 64, name = "New race goal", goal = true, races = 2 ^ 33, any = { 61 } },
	} }
	reset()
	world.classId, world.raceId = 11, 6 -- tauren druid
	local _, p = states(raced)
	eq("race: steps for a tauren", p.steps[1].name .. "/" .. p.steps[2].name .. "/" .. tostring(p.steps[3]), "Shared start/Tauren goal/nil")
	check("race: chain listed", Progress.Visible(raced, "Horde"))
	world.done[62] = true
	eq("race: done with the one goal that is hers", Progress.Chain(raced).done, true)
	world.raceId = 34
	eq("race: high race bits work", Progress.Chain(raced).steps[2].name, "New race goal")
	world.raceId = 2 -- an orc: no goal is for him, only the shared start
	check("race: lead-up quests alone do not list the chain", not Progress.Visible(raced, "Horde"))
	world.raceId = nil
	eq("race: unknown race sees everything", Progress.Chain(raced).total, 4)
	world.classId = 1
	check("class chain hidden from other classes, whatever its steps say", not Progress.Visible(raced, "Horde"))
	world.classId = 11
	check("class chain shown to its class", Progress.Visible(raced, "Horde"))
end

-- Marking a chain as done by hand
do
	reset()
	check("mark: nothing marked", not ns.Marked("t"))
	eq("mark: not done", Progress.Chain(chain).done, false)
	ns.Mark("t", true)
	local s, p = states()
	check("mark: chain done", p.done and p.marked)
	eq("mark: steps no longer needed", s, "skipped skipped skipped skipped skipped skipped")
	local d = ns.View.Detail(chain)
	eq("mark: the box says who said so", d.next.label .. "/" .. tostring(d.next.name), "Marked as done/nil")
	check("mark: can be taken back", d.marked and d.canMark)
	world.name = "Alt"
	eq("mark: another character is not marked", Progress.Chain(chain).done, false)
	world.name = nil
	ns.Mark("t", false)
	eq("mark: taken back", Progress.Chain(chain).done, false)
	check("mark: offered while not done", ns.View.Detail(chain).canMark and not ns.View.Detail(chain).marked)
	world.done[6] = true
	check("mark: not offered once the game says done", not ns.View.Detail(chain).canMark)
	reset()
end

-- Sides
check("visible both", Progress.Visible({ side = "Both" }, "Horde"))
check("visible own side", Progress.Visible({ side = "Horde" }, "Horde"))
check("hidden other side", not Progress.Visible({ side = "Alliance" }, "Horde"))
check("hidden when no step is for this faction", not Progress.Visible({ side = "Both", steps = { { quest = 1, side = "Alliance" } } }, "Horde"))
check("hidden when no step is for this class", not Progress.Visible({ side = "Both", steps = { { quest = 1, classes = 128 } } }, "Horde"))
check("item-only chain visible", Progress.Visible({ side = "Both", steps = {}, reward = 1 }, "Horde"))

-- Real data ------------------------------------------------------------------------
ns.Chains, ns.Npcs, ns.Objects, ns.Items = realData.Chains, realData.Npcs, realData.Objects, realData.Items
ns.Areas, ns.Factions = realData.Areas, realData.Factions
check("data has chains", #ns.Chains >= 40, #ns.Chains)
local ids = {}
for _, c in ipairs(ns.Chains) do
	check("chain id unique " .. c.id, not ids[c.id])
	ids[c.id] = true
	check("chain " .. c.id .. " has steps or a reward", #c.steps > 0 or c.reward ~= nil)
	-- every state of every step builds its lines without error, for both factions
	for _, faction in ipairs({ "Horde", "Alliance" }) do
		reset()
		world.faction = faction
		local ok, p = pcall(Progress.Chain, c)
		check(c.id .. " progress " .. faction, ok, p)
		if ok then
			for i, step in ipairs(p.steps) do
				for _, state in ipairs({ "ready", "active", "locked", "done" }) do
					local ok2, err = pcall(Progress.Hints, step, state, { level = 60 })
					if not ok2 then check(c.id .. " hints " .. i .. " " .. state, false, err) end
					local ok3, err3 = pcall(Progress.Target, step, state)
					if not ok3 then check(c.id .. " target " .. i .. " " .. state, false, err3) end
				end
			end
		end
	end
end
do
	-- graph: no two steps in one cell, every line runs left to right; all chains, both factions, all classes
	local bad = {}
	for _, faction in ipairs({ "Horde", "Alliance" }) do
		for _, classId in ipairs({ 1, 2, 3, 4, 5, 7, 8, 9, 11 }) do
			reset()
			world.faction, world.classId = faction, classId
			for _, c in ipairs(ns.Chains) do
				local g = ns.View.Graph(Progress.Chain(c))
				local taken = {}
				for _, cell in ipairs(g and g.at or {}) do
					local key = cell.col .. ":" .. cell.row
					if taken[key] or cell.col > g.cols or cell.row > g.rows then bad[#bad + 1] = c.id .. " " .. key end
					taken[key] = true
				end
				for _, edge in ipairs(g and g.edges or {}) do
					if g.at[edge.from].col >= g.at[edge.to].col then bad[#bad + 1] = c.id .. " line " .. edge.from .. ">" .. edge.to end
				end
			end
		end
	end
	eq("graph: real chains lay out cleanly", table.concat(bad, ", "), "")
end
do
	-- nothing done at 60: every chain with steps has something to start, unless reputation blocks it
	reset()
	local stuck = {}
	for _, c in ipairs(ns.Chains) do
		if Progress.Visible(c, "Horde") and #c.steps > 0 and not Progress.Next(c) then stuck[#stuck + 1] = c.id end
	end
	eq("fresh level 60 horde: chains with nothing to start", table.concat(stuck, ","), "")
end

-- Window -----------------------------------------------------------------------------
local function texts()
	local out = {}
	for _, f in ipairs(frames) do
		if f.shown then
			for _, v in pairs(f) do
				if type(v) == "table" and rawget(v, "text") and v.shown then out[#out + 1] = v.text end
				-- also lines kept in a list on the frame
				if type(v) == "table" and getmetatable(v) == nil then
					for _, e in ipairs(v) do
						if type(e) == "table" and rawget(e, "text") and rawget(e, "kind") == "CreateFontString" and e.shown then out[#out + 1] = e.text end
					end
				end
			end
		end
	end
	-- without the color codes
	return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local function button(pred)
	for _, f in ipairs(frames) do
		if f.kind == "Button" and f.shown and pred(f) then return f end
	end
end

reset()
check("slash command registered", type(SlashCmdList.GETREADY) == "function")
eq("slash text", SLASH_GETREADY1, "/gr")
SlashCmdList.GETREADY("")
check("window made", GetReadyFrame ~= nil)
check("window shown", ns.Window.IsShown())
check("esc closes", UISpecialFrames[1] == "GetReadyFrame")
do
	local t = texts()
	check("group headings", t:find("Raids", 1, true) and t:find("Keys", 1, true) and t:find("Dungeons", 1, true) and t:find("Other", 1, true))
	check("saved selection opens", t:find("Blood of the Black Dragon Champion", 1, true) ~= nil)
	check("list shows count", t:find("0/14", 1, true) ~= nil)
	check("alliance chain hidden", not t:find("0/16", 1, true))
	check("next box", t:find("Next", 1, true) and t:find("Start: Warlord Goretooth", 1, true))
	check("chain note", t:find("The amulet lets you enter Onyxia's Lair.", 1, true) ~= nil)
	check("numbers under the banner", t:find("Quests:", 1, true) ~= nil and t:find("Quests left", 1, true) == nil and t:find("XP", 1, true) ~= nil and t:find(ns.View.Build("ony-horde", {}, {}).detail.stats[2].value, 1, true) ~= nil and t:find("0 / 17", 1, true) ~= nil, t)
	check("facts under the numbers", t:find("Dungeons", 1, true) ~= nil and t:find("Blackrock Spire", 1, true) ~= nil, t)
	check("banner says what kind of chain", t:find("Raid  -  Level 55+", 1, true) ~= nil, t)
	check("ahead: reputation the chain gives", t:find("Reputation", 1, true) ~= nil and t:find(" Orgrimmar", 1, true) ~= nil, t)
	check("next box rewards", t:find("Rewards: Wyrmthalak's Shackles", 1, true) ~= nil)
	check("next box gains", t:find("Gives: 8,300 XP", 1, true) ~= nil)
	check("rewards heading", t:find("Rewards", 1, true) ~= nil)
	local icon
	for _, f in ipairs(frames) do if rawget(f, "item") == 16309 and f.shown then icon = f end end
	check("chain reward icon: Drakefire Amulet", icon ~= nil)
	if icon then
		icon.scripts.OnEnter(icon)
		eq("icon tooltip", tips.item, 16309)
		icon.scripts.OnLeave(icon)
	end
	check("dungeon listed", t:find("Blackrock Depths", 1, true) ~= nil)
end

-- banner: the place's loading screen behind the chain's name
local function bannerArt()
	for _, f in ipairs(frames) do
		local art = rawget(f, "art")
		if art then return art end
	end
end
do
	local art = bannerArt()
	check("banner made", art ~= nil)
	if art then
		eq("banner picture", art.texture, "Interface\\Glues\\LoadingScreens\\LoadScreenRaid")
		check("banner picture shown", art.shown)
	end
	for _, c in ipairs(ns.Chains) do
		if c.art then check("banner name is one word " .. c.id, c.art:match("^%w+$") ~= nil, c.art) end
	end
	eq("banner: view gives the full path", ns.View.Detail(ns.Chains[1]).art, "Interface\\Glues\\LoadingScreens\\LoadScreenMoltenCore")
	eq("banner: none for a chain without a picture", ns.View.Detail({ id = "x", name = "X", kind = "misc", side = "Both", steps = {} }).art, nil)

	-- every reward of the chain under the banner, and loot in its own column
	local dv = ns.View.Detail(ns.Chains[2])
	eq("rewards: the chain item first", dv.rewards[1], 16309)
	check("rewards: rewards along the way are listed", #dv.rewards > 5, #dv.rewards)
	check("loot: grouped by creature", dv.loot[1] and dv.loot[1].name == "Overlord Wyrmthalak" and #dv.loot[1].items > 0)
	eq("loot: says where it drops", dv.loot[1] and dv.loot[1].from, "Drops from Overlord Wyrmthalak (in Area 1583)")
	local lootIcon
	for _, f in ipairs(frames) do
		if f.kind == "Button" and f.shown and rawget(f, "note") and rawget(f, "item") == dv.loot[1].items[1] then lootIcon = f end
	end
	check("loot: icon in the window", lootIcon ~= nil)
	if lootIcon then
		local function over() return lootIcon.over.shown and lootIcon.over.texture or "none" end
		local function rim() -- how many white copies show, and the shape they are cut to
			local n, shape = 0, nil
			for _, copy in ipairs(lootIcon.rim or {}) do
				if copy.white.shown then n, shape = n + 1, copy.mask.texture end
			end
			return n .. " " .. tostring(shape)
		end
		check("usable: nothing over the icon when the game says nothing", lootIcon.usable == false and over() == "none")
		eq("usable: no outline made for an item without a mark", lootIcon.rim, false)
		world.kinds[lootIcon.item] = { 2, 19 } -- make it a wand; the character is a warrior
		ns.Window.Refresh()
		eq("usable: red cross over an item the class cannot use", over(), "Interface\\RaidFrame\\ReadyCheck-NotReady")
		check("usable: no", lootIcon.usable == "no")
		eq("usable: white outline in the shape of the cross", rim(), "8 Interface\\RaidFrame\\ReadyCheck-NotReady")
		eq("usable: outline is white", table.concat(lootIcon.rim[1].white.color, " "), "1 1 1 1")
		world.kinds[lootIcon.item] = { 2, 8 }
		ns.Window.Refresh()
		eq("usable: question mark over an item the class can learn", over(), "Interface\\RaidFrame\\ReadyCheck-Waiting")
		check("usable: learn", lootIcon.usable == "learn")
		eq("usable: outline follows the picture", rim(), "8 Interface\\RaidFrame\\ReadyCheck-Waiting")
		world.kinds = {}
		ns.Window.Refresh()
		eq("usable: gone again", over(), "none")
		eq("usable: outline gone too", rim(), "0 nil")
	end
	check("loot: pop-up made", GetReadyLoot ~= nil and GetReadyLoot.kind == "Frame")
	local rewardIcons = 0
	for _, f in ipairs(frames) do
		if f.kind == "Button" and f.shown and rawget(f, "note") == false and rawget(f, "item") and f.parent and rawget(f.parent, "parent") == GetReadyLootScroll then rewardIcons = rewardIcons + 1 end
	end
	eq("rewards: every one has an icon", rewardIcons, #dv.rewards)
end

-- "Show on map" sets a pin
do
	local pin = button(function(f) local l = rawget(f, "label") return l and rawget(l, "text") == "Show on map" end)
	check("show on map button", pin ~= nil)
	local before = #pins
	if pin then pin.scripts.OnClick(pin) end
	eq("pin set", #pins, before + 1)
	check("pin said", printed[#printed] and printed[#printed]:find("Map pin: Warlord Goretooth", 1, true) ~= nil, printed[#printed])
end

-- steps as a graph
do
	local function onScreen(f)
		while f do
			if not f.shown then return false end
			f = rawget(f, "parent")
		end
		return true
	end
	local function boxes()
		local n = 0
		for _, f in ipairs(frames) do if f.kind == "Button" and rawget(f, "step") and onScreen(f) then n = n + 1 end end
		return n
	end
	local function labelled(text)
		return button(function(f) local l = rawget(f, "label") return l and rawget(l, "text") == text and onScreen(f) end)
	end
	eq("graph: a box per step", boxes(), 18) -- 17 quests and "Reach level"
	local box = button(function(f) local s = rawget(f, "step") return s and s.quest == 4903 end)
	check("graph: first step box", box ~= nil)
	if box then
		check("graph: box name", box.name.text:find("Warlord's Command", 1, true) ~= nil, box.name.text)
		box.scripts.OnEnter(box)
		eq("graph: tooltip title", tips.title, "Warlord's Command")
		eq("graph: tooltip says the state", tips.lines[1], "Available")
		check("graph: tooltip has the hint", tips.lines[2] and tips.lines[2]:find("Start: Warlord Goretooth", 1, true) ~= nil)
		check("graph: tooltip has the rewards", tips.lines[3] and tips.lines[3]:find("Rewards: Wyrmthalak's Shackles", 1, true) ~= nil, tips.lines[3])
		eq("graph: tooltip has XP and reputation", tips.lines[4], "Gives: 8,300 XP, +150 Orgrimmar")
		eq("graph: box shows the XP", box.xp.text, "8,300 XP")
		local icons = 0
		for _, icon in ipairs(box.icons) do if icon.shown and rawget(icon, "item") then icons = icons + 1 end end
		eq("graph: box shows reward icons", icons, 3)
		box.scripts.OnLeave(box)
		local before = #pins
		box.scripts.OnClick(box)
		eq("graph: a click sets no pin", #pins, before)
		check("graph: a click shows the step in the side panel", GetReadyLink.shown and GetReadyLink.text == "https://www.wowhead.com/forever/quest=" .. box.step.quest, GetReadyLink.text)
		box.scripts.OnClick(box)
		check("graph: a second click closes the side panel again", not GetReadyLink.parent.parent.parent.shown)
	end

	-- the graph is wider than the window: wheel and drag move it
	local scroll
	for _, f in ipairs(frames) do if f.kind == "ScrollFrame" and f.scripts.OnMouseWheel and f.scripts.OnMouseDown then scroll = f end end
	check("graph: scroll area", scroll ~= nil)
	if scroll then
		eq("graph: starts with the next step and the column before it in view", scroll.scrollX, 0)
		scroll.scripts.OnMouseWheel(scroll, -1)
		eq("graph: wheel moves sideways", scroll.scrollX, 111)
		scroll.scripts.OnMouseWheel(scroll, 1)
		scroll.scripts.OnMouseWheel(scroll, 1)
		eq("graph: stops at the left end", scroll.scrollX, 0)
		local cursor = 500
		GetCursorPosition = function() return cursor, 300 end
		scroll.scripts.OnMouseDown(scroll, "LeftButton")
		cursor = 380
		scroll.scripts.OnUpdate(scroll)
		eq("graph: drag moves it", scroll.scrollX, 120)
		scroll.scripts.OnMouseUp(scroll)
		check("graph: drag ends", scroll.scripts.OnUpdate == nil)
		eventFrame.scripts.OnEvent(eventFrame, "BAG_UPDATE_DELAYED")
		eq("graph: a redraw keeps the place", scroll.scrollX, 120)
		for _ = 1, 40 do scroll.scripts.OnMouseWheel(scroll, -1) end
		-- every column side by side: 15 of quests for this chain, and "Reach level" before them
		local xs = {}
		for _, f in ipairs(frames) do
			if f.kind == "Button" and f.shown and rawget(f, "stripe") and rawget(f, "step") then xs[f.point[2]] = true end
		end
		local columns = 0
		for _ in pairs(xs) do columns = columns + 1 end
		eq("graph: all its columns side by side", columns, 16)
		eq("graph: stops at the right end", scroll.scrollX, 16 * 196 + 15 * 26 - (1480 - 290 - 22 - 18 * 3 - 12))
		local _ = ( 16 * 196 + 15 * 26 - (1480 - 290 - 22 - 18 * 3 - 12))
	end

	local toList = labelled("Show list")
	check("graph: list button", toList ~= nil)
	if toList then toList.scripts.OnClick(toList) end
	eq("graph: choice saved", ns.db.modes["ony-horde"], "list")
	eq("graph: boxes gone", boxes(), 0)
	check("graph: list rows back", button(function(f)
		return rawget(f, "hint") and rawget(f, "mark") and f.name.text and f.name.text:find("Warlord's Command", 1, true)
	end) ~= nil)
	check("list: every step says what it gives", button(function(f)
		local hint = rawget(f, "hint")
		return hint and rawget(f, "mark") and f.name.text and f.name.text:find("Eitrigg's Wisdom", 1, true)
			and rawget(hint, "text") and hint.text:find("+100 Orgrimmar", 1, true) and f.xp.text == "6,600 XP"
	end) ~= nil)
	local toGraph = labelled("Show graph")
	check("graph: graph button", toGraph ~= nil)
	if toGraph then toGraph.scripts.OnClick(toGraph) end
	eq("graph: back to the graph", boxes(), 18)
	eq("graph: choice saved again", ns.db.modes["ony-horde"], "graph")
end

-- an event while open redraws
world.done[4903] = true
local ok, err = pcall(eventFrame.scripts.OnEvent, eventFrame, "QUEST_TURNED_IN")
check("event refresh runs", ok, err)
check("count moved", texts():find("1/17", 1, true) ~= nil)

-- pick another chain, selection is saved
do
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "mc" end)
	check("molten core row", row ~= nil)
	if row then row.scripts.OnClick(row) end
	eq("selection saved", ns.db.selected, "mc")
	check("molten core steps shown", texts():find("Attunement to the Core", 1, true) ~= nil)
	check("one step: the graph button is there too", button(function(f)
		local l = rawget(f, "label")
		return l and (rawget(l, "text") == "Show graph" or rawget(l, "text") == "Show list")
	end) ~= nil)
	world.done[7848] = true
	eventFrame.scripts.OnEvent(eventFrame, "QUEST_TURNED_IN")
	check("molten core done", texts():find("Completed", 1, true) ~= nil and texts():find("Nothing left to do.", 1, true) == nil)
end

-- item-only chain
do
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "dm-key" end)
	check("crescent key row", row ~= nil)
	if row then row.scripts.OnClick(row) end
	check("crescent key shows item", texts():find("Get: Crescent Key", 1, true) ~= nil, texts())
	eq("banner follows the chain", bannerArt().texture, "Interface\\Glues\\LoadingScreens\\LoadScreenDireMaul")
	local bag = button(function(f) return rawget(f, "chain") and f.chain.id == "sleeping-bag" end)
	if bag then bag.scripts.OnClick(bag) end
	check("banner: no picture, plain banner", bag ~= nil and not bannerArt().shown and rawget(bannerArt(), "texture") == nil)
	if row then row.scripts.OnClick(row) end
end

-- collapse a group
do
	local head = button(function(f) local l = rawget(f, "label") return l and rawget(l, "text") == "Dungeons" end)
	check("dungeon heading", head ~= nil)
	if head then head.scripts.OnClick(head) end
	eq("group closed saved", ns.db.closed.dungeon, true)
	check("dungeon rows hidden", button(function(f) return rawget(f, "chain") and f.chain.kind == "dungeon" end) == nil)
	if head then head.scripts.OnClick(head) end
	eq("group reopened", ns.db.closed.dungeon, nil)
end

-- the window fills a share of the screen, whatever its size
do
	check("size: untouched when the screen size is unknown", rawget(GetReadyFrame, "scale") == nil)
	UIParent.GetWidth = function() return 2960 end
	UIParent.GetHeight = function() return 1245 end -- 1.5 times the window's own height
	SlashCmdList.GETREADY("size 80")
	eq("size: saved", ns.db.size, 80)
	eq("size: 80% of the screen's height", GetReadyFrame.scale, 0.8 * 1.5)
	check("size: said", printed[#printed]:find("Window size: 80% of the screen.", 1, true) ~= nil)
	check("size: the window stays open", ns.Window.IsShown())
	SlashCmdList.GETREADY("size 500")
	eq("size: not more than the screen", ns.db.size, 100)
	SlashCmdList.GETREADY("SIZE 10")
	eq("size: not too small to read", ns.db.size, 40)
	ns.db.size = nil
	ns.Window.Resize()
	eq("size: default share", GetReadyFrame.scale, 0.8 * 1.5)
end

-- mark a chain as done from the window, and take it back
do
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	if row then row.scripts.OnClick(row) end
	local function mark(text)
		return button(function(f) local l = rawget(f, "label") return l and rawget(l, "text") == text end)
	end
	local b = mark("Mark as done")
	check("mark: button", b ~= nil)
	if b then b.scripts.OnClick(b) end
	check("mark: saved for this character", ns.db.marked["Tester-Realm"] and ns.db.marked["Tester-Realm"]["ubrs-key"] == true)
	check("mark: window says so", texts():find("Marked as done", 1, true) ~= nil)
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	check("mark: list shows the check and the word", row and row.check.shown and row.count.text == "Marked")
	b = mark("Not done after all")
	check("mark: undo button", b ~= nil)
	if b then b.scripts.OnClick(b) end
	check("mark: undone", ns.db.marked["Tester-Realm"]["ubrs-key"] == nil and mark("Mark as done") ~= nil)
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	check("mark: list back to the count", row and not row.check.shown and row.count.text == "0/2")

	-- a dungeon new in Forever has a blue infinity sign after its name
	local newChain
	for _, c in ipairs(ns.Chains) do if c.id == "ubrs-key" then newChain = c end end
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	check("new: no sign on an old chain", row and not row.new.shown)
	newChain.new = true
	ns.Window.Refresh()
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	check("new: sign shown", row and row.new.shown and row.new.text == "\226\136\158")
	check("new: sign hangs on the right of the name", row.new.point[1] == "LEFT" and row.new.point[2] == row.name and row.new.point[3] == "RIGHT")
	eq("new: count unchanged", row.count.text, "0/2")
	newChain.new = nil
	ns.Window.Refresh()
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	check("new: gone without the flag", row and not row.new.shown)
end

-- class quest chains: only the character's class
do
	local own, other = 0, 0
	for _, f in ipairs(frames) do
		local c = f.kind == "Button" and f.shown and rawget(f, "chain")
		if c and c.kind == "class" then
			if c.id:find("^c%-warrior") then own = own + 1 else other = other + 1 end
		end
	end
	check("class chains: the warrior sees warrior chains", own >= 3, own)
	eq("class chains: and no other class's", other, 0)
	check("class chains: group heading is the class name", texts():find("Warrior", 1, true) ~= nil)
end

-- drag saves the position
GetReadyFrame.scripts.OnDragStop(GetReadyFrame)
eq("position saved", ns.db.point and ns.db.point[3], 12)

SlashCmdList.GETREADY("")
check("toggle hides", not ns.Window.IsShown())

world.faction = "Alliance"
SlashCmdList.GETREADY("")
check("alliance sees alliance chain", texts():find("0/16", 1, true) ~= nil)

-- every chain draws for both factions and a few classes without error
for _, faction in ipairs({ "Horde", "Alliance" }) do
	for _, classId in ipairs({ 1, 3, 8, 11 }) do
		world.faction, world.classId = faction, classId
		for _, c in ipairs(ns.Chains) do
			if Progress.Visible(c, faction) then
				ns.db.selected = c.id
				local row = button(function(f) local e = rawget(f, "chain") return e and e.id == c.id end)
				if row then
					local ok2, err2 = pcall(row.scripts.OnClick, row)
					if not ok2 then check("draw " .. c.id .. " " .. faction .. " " .. classId, false, err2) end
				end
			end
		end
		local ok2, err2 = pcall(ns.Window.Refresh)
		check("redraw " .. faction .. " class " .. classId, ok2, err2)
	end
end

-- the side panel: chain details, step details, loot; "Show on map" opens the map in front
do
	reset()
	ns.db.tab = nil
	if not ns.Window.IsShown() then ns.Window.Toggle() end
	for k in pairs(ns.db.closed) do ns.db.closed[k] = nil end
	ns.Window.Refresh()
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "ony-horde" end)
	row.scripts.OnClick(row)
	ns.db.modes["ony-horde"] = "list"
	ns.Window.Refresh()
	local function sideText()
		local out = {}
		for _, f in ipairs(frames) do
			if f.shown then
				for _, k in ipairs({ "kicker", "name", "body", "label", "text", "sub" }) do
					local v = rawget(f, k)
					if type(v) == "table" and rawget(v, "text") and v.shown then out[#out + 1] = v.text end
				end
			end
		end
		return table.concat(out, "\n")
	end
	check("side: no tabs", button(function(f) return rawget(f, "tab") ~= nil end) == nil)

	-- the chain, while no step is picked
	local model = ns.View.Build("ony-horde", {}, { ["ony-horde"] = "list" })
	eq("side: no step picked at first", model.step, nil)
	eq("side: chain has no picked step", model.detail.picked, nil)
	-- closed until something is clicked; the chain's own facts are in the header
	local panel = button(function(f) return rawget(f, "closeSide") end).parent
	check("side: closed at first", not panel.shown)
	check("header: numbers on one line", texts():find("Quests:", 1, true) ~= nil and texts():find("XP:", 1, true) ~= nil and texts():find("Min level", 1, true) == nil)
	check("header: it says XP, not XP to earn", texts():find("XP to earn", 1, true) == nil)
	check("steps: no legend for the quest marks", texts():find("In progress", 1, true) == nil and texts():find("Available", 1, true) == nil)
	check("header: the facts are there too", texts():find("Dungeons", 1, true) ~= nil, texts())
	eq("header: the chain's Wowhead address is the item it is for", GetReadyChainLink.text, "https://www.wowhead.com/forever/item=16309")
	eq("link: one goal quest and no item", ns.View.Detail({ id = "g", name = "G", kind = "raid", side = "Both", steps = { { quest = 5, name = "A" }, { quest = 7848, name = "B", goal = true } } }).link, "https://www.wowhead.com/forever/quest=7848")
	check("header: address shown", GetReadyChainLink.shown)
	eq("link: a dungeon's zone page", ns.View.Detail({ id = "z", name = "Z", kind = "dungeon", side = "Both", at = { area = 2017 }, steps = {} }).link, "https://www.wowhead.com/forever/zone=2017")
	eq("link: a key's item page", ns.View.Detail({ id = "k", name = "K", kind = "key", side = "Both", reward = 12344, steps = { { quest = 1, name = "A", goal = true } } }).link, "https://www.wowhead.com/forever/item=12344")
	eq("link: none for many goals and no place", ns.View.Detail({ id = "m", name = "M", kind = "misc", side = "Both", steps = { { quest = 1, name = "A", goal = true }, { quest = 2, name = "B", goal = true } } }).link, nil)

	-- a step
	local first = model.detail.steps[1]
	local stepRow = button(function(f) return rawget(f, "quest") == first.quest and rawget(f, "mark") end)
	check("side: step row found", stepRow ~= nil)
	local before = #pins
	stepRow.scripts.OnClick(stepRow)
	eq("side: a click on a step sets no pin", #pins, before)
	check("side: the step's row is marked", stepRow.pick.shown and stepRow.pickEdge.shown)
	local picked = ns.View.Build("ony-horde", {}, { ["ony-horde"] = "list" }, nil, first.quest)
	eq("side: model names the step", picked.step, first.quest)
	eq("side: step name", picked.detail.picked.name, first.name)
	eq("side: step link", picked.detail.picked.link, "https://www.wowhead.com/forever/quest=" .. first.quest)
	-- who starts and who takes the quest are lines of their own, with a pin when the place is known
	local ways = picked.detail.picked.ways
	eq("ways: start and turn in", #ways .. " " .. ways[1].label .. "/" .. ways[2].label, "2 Start/Turn in")
	check("ways: the start has a place to pin", ways[1].target and ways[1].target.map ~= nil and ways[1].text:find("Warlord Goretooth", 1, true) ~= nil, ways[1].text)
	check("ways: not repeated in the words", not table.concat(picked.detail.picked.lines, "|"):find("Start:", 1, true))
	local startLine = button(function(f) return rawget(f, "wayLink") == 1 end)
	check("ways: a line in the panel", startLine ~= nil and startLine.name.text:find("Warlord Goretooth", 1, true) ~= nil)
	local pinsBefore = #pins
	startLine.scripts.OnClick(startLine)
	eq("ways: a click puts the pin there", #pins, pinsBefore + 1)
	check("ways: the window stays open", ns.Window.IsShown())
	-- the Wowhead box sits right under the name
	check("link: under the name, over the rest", GetReadyLink.point[3] > startLine.point[3], GetReadyLink.point[3] .. " vs " .. startLine.point[3])
	-- a step below the player's level: the level is on its own row, not in the words as well
	world.level = 10
	local lowPick = ns.View.Build("ony-horde", {}, {}, nil, first.quest).detail
	check("side: the list still says the level", table.concat(lowPick.steps[1].hints, "|"):find("Required level: ", 1, true) ~= nil)
	check("side: the details say it once, as a row", not table.concat(lowPick.picked.lines, "|"):find("Required level", 1, true) and lowPick.picked.rows[1].label == "Required level" and lowPick.picked.rows[1].tone == "warn")
	world.level = 60
	check("side: step has a level line", picked.detail.picked.rows[1].label == "Required level")
	-- more words: what the quest asks, and the steps around it
	check("side: step says what the quest asks", type(picked.detail.picked.text) == "string" and #picked.detail.picked.text > 10, picked.detail.picked.text)
	check("side: the quest's words show", sideText():find(picked.detail.picked.text, 1, true) ~= nil)
	local pk = picked.detail.picked
	check("side: the first step leads somewhere and follows nothing", #pk.after >= 1 and #pk.before == 0)
	local second = pk.after[1]
	check("side: a link has the step's quest, name and mark", type(second.quest) == "number" and type(second.name) == "string" and second.mark ~= nil)
	local pk2 = ns.View.Build("ony-horde", {}, {}, nil, second.quest).detail.picked
	eq("side: the next step names the first one as before it", pk2.before[1].quest, first.quest)

	-- the links in the panel: a click shows that step
	local function link(quest) return button(function(f) return rawget(f, "stepLink") and rawget(f, "quest") == quest end) end
	check("nav: no back or forward buttons", button(function(f) return rawget(f, "trail") ~= nil end) == nil)
	local toSecond = link(second.quest)
	check("nav: the next step is a line to click", toSecond ~= nil and toSecond.name.text == second.name)
	toSecond.scripts.OnClick(toSecond)
	eq("nav: the click shows that step", GetReadyLink.text, "https://www.wowhead.com/forever/quest=" .. second.quest)
	check("nav: its row is the marked one now", not stepRow.pick.shown)
	local toFirst = link(first.quest)
	check("nav: the step before is a line to click too", toFirst ~= nil)
	toFirst.scripts.OnClick(toFirst)
	eq("nav: and leads back", GetReadyLink.text, "https://www.wowhead.com/forever/quest=" .. first.quest)

	-- the chain's first row is "Reach level N"; it has nothing to show in the panel
	local reachRow = button(function(f) return rawget(f, "pickEdge") and rawget(f, "name") and f.name.text and f.name.text:find("^Reach level 55") end)
	check("reach: first row of the list", reachRow ~= nil and reachRow.point[3] == 0, reachRow and reachRow.point[3])
	check("reach: the first quest comes after it", stepRow.point[3] < 0)
	reachRow.scripts.OnClick(reachRow)
	eq("reach: a click on it changes nothing", GetReadyLink.text, "https://www.wowhead.com/forever/quest=" .. first.quest)
	check("reach: the panel stays", panel.shown)

	-- mark a step as done by hand, and take it back
	local markStep = button(function(f) return rawget(f, "markStep") end)
	check("mark step: button for a step that is not done", markStep ~= nil and markStep.label.text == "Mark as done")
	local doneBefore = ns.View.Build("ony-horde", {}, {}).detail.steps[1].state
	markStep.scripts.OnClick(markStep)
	check("mark step: saved for this character", ns.db.steps["Tester-Realm"][first.quest] == true)
	eq("mark step: the step counts as done", ns.View.Build("ony-horde", {}, {}).detail.steps[1].state, "done")
	eq("mark step: the chain's count moves", ns.View.Build("ony-horde", {}, {}).detail.stats[1].value, "1 / 17")
	markStep = button(function(f) return rawget(f, "markStep") end)
	eq("mark step: the button takes it back", markStep and markStep.label.text, "Not done after all")
	markStep.scripts.OnClick(markStep)
	check("mark step: undone", ns.db.steps["Tester-Realm"][first.quest] == nil)
	eq("mark step: the step is as before", ns.View.Build("ony-horde", {}, {}).detail.steps[1].state, doneBefore)
	-- a step the game itself counts as done has no button
	world.done[first.quest] = true
	ns.Window.Refresh()
	check("mark step: no button for a step the game knows is done", button(function(f) return rawget(f, "markStep") end) == nil)
	world.done[first.quest] = nil
	ns.Window.Refresh()

	-- a quest in the log shows how far the player is
	eq("side: no progress lines for a quest not in the log", #picked.detail.picked.objectives, 0)
	world.log[first.quest] = true
	C_QuestLog.GetQuestObjectives = function() return { { text = "3/5 Bones", finished = false }, { text = "Head taken", finished = true }, { text = "" } } end
	local inLog = ns.View.Build("ony-horde", {}, {}, nil, first.quest).detail.picked
	eq("side: progress lines for a quest in the log", #inLog.objectives, 2)
	check("side: a finished part is marked", inLog.objectives[2].done and not inLog.objectives[1].done)
	world.log[first.quest] = nil
	C_QuestLog.GetQuestObjectives = nil
	check("side: opens for the step", panel.shown)
	check("side: its content scrolls", GetReadyInfoScroll ~= nil and GetReadyLink.parent.parent == GetReadyInfoScroll)
	check("side: the content has a height for the scroll bar", type(GetReadyLink.parent.height) == "number" and GetReadyLink.parent.height > 100, GetReadyLink.parent.height)
	eq("side: a step starts at its top", GetReadyInfoScroll.scrollY, 0)
	eq("side: titled Details", panel.title.text, "Details")
	check("side: step shows", sideText():find(first.status, 1, true) ~= nil and sideText():find(first.name, 1, true) ~= nil, sideText())
	eq("side: the middle gets narrower beside it", stepRow.widthSet, 1480 - 290 - 22 - (320 + 40) - 18 * 4 - 26)
	check("side: link shown", GetReadyLink.shown and GetReadyLink.text == "https://www.wowhead.com/forever/quest=" .. first.quest)
	-- typing in the address box does not change it
	GetReadyLink:SetText("oops")
	GetReadyLink.scripts.OnTextChanged(GetReadyLink, true)
	eq("side: the address cannot be edited", GetReadyLink.text, "https://www.wowhead.com/forever/quest=" .. first.quest)
	eq("side: a step that is not in the chain is dropped", ns.View.Build("ony-horde", {}, {}, nil, 1).step, nil)

	-- "Show on map": pin and the game's map, in front of the window, which stays open
	local pin = button(function(f) return rawget(f, "pin") == true end)
	check("side: map button for a step that has a place", pin ~= nil and pin.target ~= nil)
	local opened, raised
	function OpenWorldMap(map) opened = map end
	WorldMapFrame = { Raise = function() raised = true end }
	before = #pins
	pin.scripts.OnClick(pin)
	eq("map: pin set", #pins, before + 1)
	eq("map: the game's map opens on the zone", opened, pin.target.map)
	check("map: comes in front", raised == true)
	check("map: the window stays open", ns.Window.IsShown())
	-- in a fight the map cannot open: only the pin is set
	function InCombatLockdown() return true end
	opened, raised = nil, nil
	before = #pins
	pin.scripts.OnClick(pin)
	check("map: no map in a fight", opened == nil and raised == nil)
	eq("map: the pin is still set in a fight", #pins, before + 1)
	InCombatLockdown = nil
	OpenWorldMap = nil
	WorldMapFrame = nil

	-- a second click on the step closes the panel
	stepRow.scripts.OnClick(stepRow)
	check("side: a second click closes it", not panel.shown and not stepRow.pick.shown)
	eq("side: the middle is wide again", stepRow.widthSet, 1480 - 290 - 22 - 18 * 3 - 26)

	-- "Rewards and loot" in the header opens a pop-up, and closes it again
	local lootButton = button(function(f) return rawget(f, "lootToggle") end)
	check("header: loot button", lootButton ~= nil)
	check("loot: pop-up closed at first", not GetReadyLoot.shown)
	lootButton.scripts.OnClick(lootButton)
	check("loot: the button opens the pop-up", GetReadyLoot.shown)
	check("loot: the side panel stays closed", not panel.shown)
	eq("loot: the middle keeps its width", stepRow.widthSet, 1480 - 290 - 22 - 18 * 3 - 26)
	eq("loot: hangs under its button", GetReadyLoot.point[2], lootButton)
	check("loot: both sections", texts():find("Quest rewards", 1, true) ~= nil and texts():find("Possible loot", 1, true) ~= nil)
	-- a step can be looked at while the pop-up is open
	stepRow.scripts.OnClick(stepRow)
	check("loot: stays open beside a step", GetReadyLoot.shown and panel.shown)
	stepRow.scripts.OnClick(stepRow)
	lootButton.scripts.OnClick(lootButton)
	check("loot: the button closes it again", not GetReadyLoot.shown)
	lootButton.scripts.OnClick(lootButton)
	local lootX = button(function(f) return rawget(f, "closeLoot") end)
	lootX.scripts.OnClick(lootX)
	check("loot: its x closes it", not GetReadyLoot.shown)

	-- the side panel's x closes it
	stepRow.scripts.OnClick(stepRow)
	local x = button(function(f) return rawget(f, "closeSide") end)
	x.scripts.OnClick(x)
	check("side: the x closes it", not panel.shown and not stepRow.pick.shown)
	stepRow.scripts.OnClick(stepRow)
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	row.scripts.OnClick(row)
	check("side: another chain, no step", not GetReadyLink.shown)
	ns.db.tab = nil
end

-- a reputation line cut short shows the whole list when pointed at
do
	reset()
	local many = { id = "rp", name = "RP", kind = "misc", side = "Both", steps = { { quest = 9101, name = "Rep", goal = true,
		repGain = { { 76, 500 }, { 530, 400 }, { 68, 300 }, { 81, 200 }, { 67, 100 } } } } }
	ns.Factions[76], ns.Factions[530], ns.Factions[68], ns.Factions[81], ns.Factions[67] = "Orgrimmar", "Darkspear Trolls", "Undercity", "Thunder Bluff", "Horde"
	local fact
	for _, f in ipairs(ns.View.Detail(many).facts) do if f.label == "Reputation" then fact = f end end
	check("rep: short text ends in the count of the rest", fact and fact.text:find("%+2 more$") ~= nil, fact and fact.text)
	eq("rep: the full list has every faction", fact.full and #fact.full, 5)
	eq("rep: biggest first", fact.full[1], "+500 Orgrimmar")
	local few = { id = "rf", name = "RF", kind = "misc", side = "Both", steps = { { quest = 9102, name = "Rep", goal = true, repGain = { { 76, 500 } } } } }
	for _, f in ipairs(ns.View.Detail(few).facts) do
		if f.label == "Reputation" then check("rep: nothing more to show for a short list", f.full == nil and not f.text:find("more", 1, true)) end
	end
	-- wording
	world.level = 10
	local low = ns.View.Detail({ id = "lv", name = "LV", kind = "misc", side = "Both", level = 30, steps = { { quest = 9103, name = "High", min = 30, goal = true } } })
	eq("text: required level", low.steps[1].hints[1], "Required level: 30")
	eq("text: not available yet", low.next.label, "Not available yet")
	eq("text: the level still needed, always in full", low.stats[3].label .. ": " .. low.stats[3].value, "Required level to complete: 30")
	eq("text: and is a warning", low.stats[3].tone, "warn")
	for _, s in ipairs(low.stats) do check("text: no min level among the numbers", s.label ~= "Min level" and s.label ~= "Quests left") end
	-- the chain starts with a step to reach its level
	eq("reach: first step", low.reach and low.reach.name, "Reach level 30")
	eq("reach: not there yet", low.reach.state .. "/" .. low.reach.mark .. "/" .. low.reach.status, "ready/ready/You are level 10")
	eq("reach: it is not one of the quest steps", #low.steps, 1)
	eq("reach: not counted", low.stats[1].value, "0 / 1")
	check("reach: no quest", low.reach.quest == nil)
	for _, f in ipairs(low.facts) do check("text: the level is no longer on the Needs line", not (f.label == "Needs" and f.text:find("level", 1, true))) end
	world.level = 60
	local high = ns.View.Detail({ id = "lv", name = "LV", kind = "misc", side = "Both", level = 30, steps = { { quest = 9103, name = "High", min = 30, goal = true } } })
	eq("text: no needed level once the player has it", high.stats[3].value, "-")
	eq("reach: done once the player has the level", high.reach.state .. "/" .. high.reach.status, "done/Done")
	check("reach: none for a chain with no level", ns.View.Detail({ id = "nl", name = "NL", kind = "misc", side = "Both", steps = { { quest = 9106, name = "Any", goal = true } } }).reach == nil)
	-- a chain that is only an item gets one made-up step: the item, and who or what has it
	ns.Npcs[9401] = { name = "Key Keeper", map = 1434, x = 30, y = 40 }
	ns.Objects[9402] = { name = "Locked Chest", map = 1434, x = 31, y = 41 }
	ns.Items[9403] = { name = "Old Key", npc = { 9401 } }
	ns.Items[9404] = { name = "Chest Key", npc = { 9401 }, object = { 9402 } }
	local key = ns.View.Detail({ id = "ik", name = "IK", kind = "key", side = "Both", reward = 9403, steps = {} }, nil, nil, -9403)
	eq("item chain: one step to show", #key.steps .. " " .. key.steps[1].name, "1 Get Old Key")
	eq("item chain: it is not counted", key.stats[1].value, "-")
	eq("item chain: who has it is a kill line, then the item", key.steps[1].parts[1].kind .. "/" .. key.steps[1].parts[1].name .. " " .. key.steps[1].parts[2].kind, "kill/Key Keeper item")
	eq("item chain: the side panel shows that creature", key.picked.model.id, 9401)
	eq("item chain: its link is the item's", key.picked.link, "https://www.wowhead.com/forever/item=9403")
	check("item chain: no mark button on the step", key.picked.canMark == false)
	check("item chain: no level step without a level", key.reach == nil)
	local chest = ns.View.Detail({ id = "ic", name = "IC", kind = "key", side = "Both", reward = 9404, steps = {} })
	eq("item chain: a chest is taken over the creatures", chest.steps[1].parts[1].kind .. "/" .. chest.steps[1].parts[1].name, "use/Locked Chest")
	world.items[9403] = 1
	eq("item chain: done once the item is in the bags", ns.View.Detail({ id = "ik", name = "IK", kind = "key", side = "Both", reward = 9403, steps = {} }).steps[1].state, "done")
	world.items[9403] = nil
	check("item chain: nothing known, still a step", #ns.View.Detail({ id = "iu", name = "IU", kind = "key", side = "Both", reward = 9499, steps = {} }).steps == 1)
	ns.Npcs[9401], ns.Objects[9402], ns.Items[9403], ns.Items[9404] = nil, nil, nil, nil
	-- in a graph it has its own first column and a line to each step that waits for nothing
	local gd = ns.View.Detail({ id = "gr", name = "GR", kind = "misc", side = "Both", level = 30, steps = {
		{ quest = 9111, name = "A", min = 30 }, { quest = 9112, name = "B", all = { 9111 } }, { quest = 9113, name = "C", all = { 9112 }, goal = true },
	} }, nil, { gr = "graph" })
	eq("reach: graph has one more column", gd.graph.cols, 4)
	eq("reach: the quest steps move right", gd.steps[1].col .. gd.steps[2].col .. gd.steps[3].col, "234")
	eq("reach: stands first, on the first step's row", gd.reach.col .. "/" .. gd.reach.row, "1/" .. gd.steps[1].row)
	eq("reach: a line to the step that waits for nothing", #gd.graph.reach .. "/" .. gd.graph.reach[1], "1/1")
	check("reach: the line is lit once the level is reached", gd.graph.reach.lit == true)
	world.level = 10
	world.level = 60
end

-- the list: section order, order inside a section, and the level on each row
do
	reset()
	ns.db.allClasses = nil
	local function kinds()
		local out = {}
		for _, g in ipairs(ns.View.Build(nil, {}, {}).groups) do out[#out + 1] = g.label end
		return table.concat(out, ",")
	end
	eq("list: own class, dungeons, keys, raids, other", kinds(), "Warrior,Dungeons,Keys,Raids,Other")
	ns.db.allClasses = true
	eq("list: other classes come after the raids", kinds(), "Warrior,Dungeons,Keys,Raids,Paladin,Hunter,Rogue,Priest,Shaman,Mage,Warlock,Druid,Other")
	ns.db.allClasses = nil
	-- inside a section: by level, then by name; no level goes last
	local sorted, levels = true, {}
	for _, g in ipairs(ns.View.Build(nil, {}, {}).groups) do
		local prev
		for _, c in ipairs(g.chains) do
			if prev then
				local la, lb = prev.level or 1000, c.level or 1000
				if la > lb or (la == lb and prev.name > c.name) then sorted = false end
			end
			prev = c
		end
		if g.label == "Dungeons" then for _, c in ipairs(g.chains) do if c.level then levels[#levels + 1] = c.level end end end
	end
	check("list: sorted by level, then name", sorted)
	-- the level on a row is the lowest a step still to do asks for
	local saved = ns.Chains
	ns.Chains = {
		{ id = "lv-a", name = "Alpha", kind = "misc", side = "Both", level = 10, steps = { { quest = 9501, name = "One", min = 10 }, { quest = 9502, name = "Two", min = 30, goal = true } } },
		{ id = "lv-b", name = "Beta", kind = "misc", side = "Both", level = 20, steps = { { quest = 9503, name = "Three", min = 20, goal = true } } },
		{ id = "c-x-other", name = "Various X Quests", kind = "misc", side = "Both", level = 20, steps = { { quest = 9504, name = "Four", min = 20, goal = true } } },
		{ id = "lv-z", name = "Zeta", kind = "misc", side = "Both", level = 20, steps = { { quest = 9505, name = "Five", min = 20, goal = true } } },
	}
	local function rows()
		local out = {}
		for _, c in ipairs(ns.View.Build(nil, {}, {}).groups[1].chains) do out[#out + 1] = c.name .. "=" .. tostring(c.level) end
		return table.concat(out, " ")
	end
	eq("list level: lowest step first", rows(), "Alpha=10 Beta=20 Zeta=20 Various X Quests=20")
	world.done[9501] = true
	eq("list level: moves up as steps get done, and the order with it", rows(), "Beta=20 Zeta=20 Various X Quests=20 Alpha=30")
	world.done[9502] = true
	eq("list level: a finished chain has none and goes last", rows(), "Beta=20 Zeta=20 Various X Quests=20 Alpha=nil")
	world.done[9501], world.done[9502] = nil, nil
	ns.Chains = saved
	check("list: dungeons start low and end high", levels[1] < levels[#levels], levels[1] .. " " .. levels[#levels])
	-- the level's color follows the player's level
	local function tone(playerLevel)
		world.level = playerLevel
		for _, g in ipairs(ns.View.Build(nil, {}, {}).groups) do
			for _, c in ipairs(g.chains) do if c.id == "mc" then return c.level .. "/" .. c.levelTone end end
		end
	end
	eq("level: over the player", tone(40), "55/over")
	eq("level: about even", tone(56), "55/even")
	eq("level: below", tone(60), "55/under")
	world.level = 60
	-- on the row
	if not ns.Window.IsShown() then ns.Window.Toggle() end
	for k in pairs(ns.db.closed) do ns.db.closed[k] = nil end
	ns.Window.Refresh()
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "mc" end)
	check("level: shown on the row in brackets", row.name.text:find("[55]", 1, true) ~= nil and row.name.text:find("Molten Core", 1, true) ~= nil, row.name.text)
	-- a section folds on a click on its heading
	local head = button(function(f) return rawget(f, "group") == "raid" end)
	check("list: section heading", head ~= nil)
	head.scripts.OnClick(head)
	check("list: a click folds the section", ns.db.closed.raid == true and button(function(f) return rawget(f, "chain") and f.chain.id == "mc" end) == nil)
	head.scripts.OnClick(head)
	check("list: another click opens it", not ns.db.closed.raid and button(function(f) return rawget(f, "chain") and f.chain.id == "mc" end) ~= nil)
end

-- a "Various" chain as a graph: its first column goes by level
do
	reset()
	local steps = {
		{ quest = 9601, name = "High", min = 40 }, { quest = 9602, name = "Low", min = 10 },
		{ quest = 9603, name = "After low", min = 12, all = { 9602 } }, { quest = 9604, name = "Mid", min = 20, goal = true },
	}
	local function rowsOf(id)
		local d = ns.View.Detail({ id = id, name = "V", kind = "class", side = "Both", steps = steps }, nil, { [id] = "graph" })
		local out = {}
		for _, s in ipairs(d.steps) do out[#out + 1] = s.name .. "=" .. s.col .. "/" .. s.row end
		return table.concat(out, " ")
	end
	eq("various graph: first column by level", rowsOf("c-x-other"), "High=1/3 Low=1/1 After low=2/1 Mid=1/2")
	eq("other chains keep their own order", rowsOf("c-x-1"), "High=1/1 Low=1/2 After low=2/2 Mid=1/3")
end

-- the level before a step's name, in the list and on the graph's boxes
do
	reset()
	world.level = 30
	local c = { id = "lt", name = "LT", kind = "misc", side = "Both", level = 10, steps = {
		{ quest = 9801, name = "Far below", min = 10 }, { quest = 9802, name = "Below", min = 25 },
		{ quest = 9803, name = "Even", min = 29 }, { quest = 9804, name = "Over", min = 40, goal = true },
		{ quest = 9805, name = "No level" },
	} }
	local d = ns.View.Detail(c)
	eq("step level: tones", d.steps[1].minTone .. " " .. d.steps[2].minTone .. " " .. d.steps[3].minTone .. " " .. d.steps[4].minTone, "far under even over")
	check("step level: none for a step that asks for no level", d.steps[5].min == nil and d.steps[5].minTone == nil)
	check("step level: none on the reach step", d.reach ~= nil and d.reach.min == nil)
	table.insert(ns.Chains, 1, c)
	if not ns.Window.IsShown() then ns.Window.Toggle() end
	for k in pairs(ns.db.closed) do ns.db.closed[k] = nil end
	ns.db.modes.lt = "list"
	ns.Window.Refresh()
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "lt" end)
	row.scripts.OnClick(row)
	local function stepRow(quest) return button(function(f) return rawget(f, "quest") == quest and rawget(f, "pickEdge") end) end
	check("step level: in brackets before the name", stepRow(9804).name.text:find("[40]|r Over", 1, true) ~= nil, stepRow(9804).name.text)
	check("step level: red when over the player's level", stepRow(9804).name.text:find("|cffff4033", 1, true) ~= nil, stepRow(9804).name.text)
	check("step level: no words about the level after the name", not stepRow(9804).name.text:find("level", 1, true))
	eq("step level: a step with no level has no brackets", stepRow(9805).name.text, "No level")
	local reach = button(function(f) return rawget(f, "pickEdge") and rawget(f, "name") and (f.name.text or ""):find("^Reach level") end)
	eq("step level: Reach level has no brackets", reach and reach.name.text, "Reach level 10")
	-- on the graph
	ns.db.modes.lt = "graph"
	ns.Window.Refresh()
	local box = button(function(f) return rawget(f, "step") and f.step.quest == 9804 and rawget(f, "stripe") end)
	check("step level: on the box too", box and box.name.text:find("[40]|r Over", 1, true) ~= nil, box and box.name.text)
	check("step level: no red Lvl on the box", box and not (box.xp.text or ""):find("Lvl", 1, true))
	ns.db.modes.lt = nil
	table.remove(ns.Chains, 1)
	world.level = 60
	ns.Window.Refresh()
end

-- the banner shows what the chain's quests give, as icons under its name
do
	reset()
	if not ns.Window.IsShown() then ns.Window.Toggle() end
	for k in pairs(ns.db.closed) do ns.db.closed[k] = nil end
	ns.Window.Refresh()
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "ony-horde" end)
	row.scripts.OnClick(row)
	local d = ns.View.Build("ony-horde", {}, {}).detail
	local holder
	for _, f in ipairs(frames) do if f.kind == "Frame" and rawget(f, "icons") and rawget(f, "more") and f.parent and rawget(f.parent, "shade") then holder = f end end
	check("banner rewards: a row in the banner", holder ~= nil and holder.shown)
	local n = 0
	for _, b in ipairs(holder.icons) do if b.shown then n = n + 1 end end
	check("banner rewards: an icon each, as many as fit", n >= 1 and n <= #d.rewards, n .. " of " .. #d.rewards)
	eq("banner rewards: the first is the chain's own item", holder.icons[1].item, d.rewards[1])
	-- a chain whose quests give nothing has no row
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "dalaran-tome" end)
	if row then
		row.scripts.OnClick(row)
		check("banner rewards: none, no row", #ns.View.Build("dalaran-tome", {}, {}).detail.rewards > 0 or not holder.shown)
	end
end

-- the window's own thin scroll bars
do
	if not ns.Window.IsShown() then ns.Window.Toggle() end
	local s = GetReadyListScroll
	check("scroll: no stock scroll bar", s ~= nil and rawget(s, "template") == nil and rawget(GetReadyStepScroll, "template") == nil and rawget(GetReadyInfoScroll, "template") == nil and rawget(GetReadyLootScroll, "template") == nil)
	check("scroll: a bar and a thumb of its own", rawget(s, "bar") ~= nil and rawget(s, "thumb") ~= nil)
	-- a list twice as tall as its area
	local at = 0
	s.GetVerticalScrollRange = function() return 400 end
	s.GetHeight = function() return 400 end
	s.GetVerticalScroll = function() return at end
	s.SetVerticalScroll = function(_, v) at = v end
	s:Sync()
	check("scroll: bar shows when the list is longer than its area", s.bar.shown)
	eq("scroll: thumb is half the area", s.thumb.height, 200)
	s.scripts.OnMouseWheel(s, -1)
	eq("scroll: a notch of the wheel", at, 70)
	eq("scroll: the thumb follows", s.thumb.point[3], -(400 - 200) * 70 / 400)
	for _ = 1, 20 do s.scripts.OnMouseWheel(s, -1) end
	eq("scroll: stops at the end", at, 400)
	for _ = 1, 20 do s.scripts.OnMouseWheel(s, 1) end
	eq("scroll: stops at the start", at, 0)
	-- dragging the thumb
	local y = 300
	GetCursorPosition = function() return 0, y end
	s.thumb.GetHeight = function() return 200 end
	s.thumb.GetEffectiveScale = function() return 1 end
	s.thumb.scripts.OnMouseDown(s.thumb)
	y = 200
	s.thumb.scripts.OnUpdate(s.thumb)
	eq("scroll: dragging the thumb half way down", at, 200)
	s.thumb.scripts.OnMouseUp(s.thumb)
	check("scroll: drag ends", s.thumb.scripts.OnUpdate == nil)
	-- everything fits: no bar
	s.GetVerticalScrollRange = function() return 0 end
	s:Sync()
	check("scroll: bar hides when everything fits", not s.bar.shown)
	s.GetVerticalScrollRange, s.GetHeight, s.GetVerticalScroll, s.SetVerticalScroll = nil, nil, nil, nil
end

-- what a quest asks for, a line each: kill, use, get; and the creature's model in the side panel
do
	reset()
	ns.Npcs[9301] = { name = "Old Boss", area = 25, map = 1434, x = 10, y = 20 }
	ns.Npcs[9302] = { name = "Second Boss" }
	ns.Objects[9303] = { name = "Strange Altar" }
	ns.Items[9304] = { name = "Boss Tooth", npc = { 9301 } }
	local c = { id = "pt", name = "PT", kind = "misc", side = "Both", art = "Raid", steps = {
		{ quest = 9310, name = "Hunt", goal = true, kill = { 9301, 9302 }, use = { 9303 }, items = { 9304 } },
		{ quest = 9311, name = "Talk", goal = true },
	} }
	local d = ns.View.Detail(c)
	local parts = d.steps[1].parts
	eq("parts: one per thing", #parts, 4)
	eq("parts: kinds in order", parts[1].kind .. " " .. parts[2].kind .. " " .. parts[3].kind .. " " .. parts[4].kind, "kill kill use item")
	eq("parts: words", parts[1].label .. "/" .. parts[3].label .. "/" .. parts[4].label, "Kill/Use/Get")
	check("parts: a creature has its place and a pin", parts[1].place:find("10", 1, true) ~= nil and parts[1].target and parts[1].target.map == 1434, parts[1].place)
	check("parts: no place, no pin", parts[2].place == "" and parts[2].target == nil)
	check("parts: an item says who has it", parts[4].place:find("from Old Boss", 1, true) ~= nil, parts[4].place)
	eq("parts: as the quest's own mark before it is done", parts[1].mark, "ready")
	eq("parts: none for a quest that asks for nothing", #d.steps[2].parts, 0)
	-- in the log: the item counts once it is in the bags
	world.log[9310] = true
	world.items[9304] = 1
	parts = ns.View.Detail(c).steps[1].parts
	eq("parts: kill still to do", parts[1].mark, "active")
	eq("parts: item in the bags", parts[4].mark, "done")
	C_QuestLog.IsComplete = function() return true end
	eq("parts: all done once the quest is complete", ns.View.Detail(c).steps[1].parts[1].mark, "done")
	C_QuestLog.IsComplete = nil
	world.log[9310], world.items[9304] = nil, nil
	world.done[9310] = true
	eq("parts: all done with the quest", ns.View.Detail(c).steps[1].parts[2].mark, "done")
	world.done[9310] = nil

	-- the model: the first creature to kill, or the one picked
	local pk = ns.View.Detail(c, nil, nil, 9310).picked
	eq("model: first creature by default", pk.model.id .. "/" .. pk.model.name .. "/" .. pk.model.at, "9301/Old Boss/1")
	eq("model: the picked creature", ns.View.Detail(c, nil, nil, 9310, 2).picked.model.id, 9302)
	eq("model: an item part picked, still the first creature", ns.View.Detail(c, nil, nil, 9310, 4).picked.model.id, 9301)
	check("model: none for a step with nothing to kill", ns.View.Detail(c, nil, nil, 9311).picked.model == nil)

	-- in the window
	table.insert(ns.Chains, 1, c)
	if not ns.Window.IsShown() then ns.Window.Toggle() end
	for k in pairs(ns.db.closed) do ns.db.closed[k] = nil end
	ns.db.modes.pt = "list"
	ns.Window.Refresh()
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "pt" end)
	row.scripts.OnClick(row)
	local function partRow(at) return button(function(f) return rawget(f, "partRow") and rawget(f, "quest") == 9310 and rawget(f, "at") == at end) end
	check("parts: a row each under the step", partRow(1) ~= nil and partRow(4) ~= nil and partRow(5) == nil)
	check("parts: row text", partRow(1).name.text:find("Kill", 1, true) ~= nil and partRow(1).name.text:find("Old Boss", 1, true) ~= nil, partRow(1).name.text)
	-- a skull marks what has you kill something
	check("skull: on a kill line", partRow(1).skull.shown and partRow(1).skull.texture:find("Skull", 1, true) ~= nil)
	check("skull: not on a use or get line", not partRow(3).skull.shown and not partRow(4).skull.shown)
	local killStep = button(function(f) return rawget(f, "quest") == 9310 and rawget(f, "pickEdge") end)
	local talkStep = button(function(f) return rawget(f, "quest") == 9311 and rawget(f, "pickEdge") end)
	check("skull: on the step with something to kill", killStep.skull.shown)
	check("skull: not on a step with nothing to kill", not talkStep.skull.shown)
	local stepRow = button(function(f) return rawget(f, "quest") == 9310 and rawget(f, "pickEdge") end)
	check("parts: the step's own row no longer repeats them", not (stepRow.hint.text or ""):find("Kill:", 1, true))
	local models = {}
	for _, f in ipairs(frames) do
		if f.kind == "PlayerModel" then
			f.SetCreature = function(_, id) models[#models + 1] = id end
		end
	end
	-- opening the chain got its creatures loaded ahead, unseen
	local pre
	for _, f in ipairs(frames) do if f.kind == "PlayerModel" and rawget(f, "preloader") then pre = f end end
	check("model: creatures are loaded ahead", pre ~= nil and rawget(pre, "alpha") == 0)
	partRow(2).scripts.OnClick(partRow(2))
	check("model: a click on a creature's line opens the step", GetReadyLink.shown and GetReadyLink.text:find("quest=9310", 1, true) ~= nil)
	eq("model: and shows that creature", models[#models], 9302)
	-- the model takes the mouse: the wheel zooms, the left button turns, the right button moves
	local shown
	for _, f in ipairs(frames) do if f.kind == "PlayerModel" and not rawget(f, "preloader") then shown = f end end
	check("model: takes the mouse", shown and shown.scripts.OnMouseWheel ~= nil and shown.scripts.OnMouseDown ~= nil)
	local zoom
	shown.SetCamDistanceScale = function(_, v) zoom = v end
	shown.scripts.OnMouseWheel(shown, 1)
	check("model: wheel up comes closer", zoom and zoom < 1.7, zoom)
	for _ = 1, 40 do shown.scripts.OnMouseWheel(shown, 1) end
	eq("model: not closer than the limit", zoom, 0.3)
	for _ = 1, 60 do shown.scripts.OnMouseWheel(shown, -1) end
	eq("model: not further than the limit", zoom, 4)
	local facing, moved
	shown.SetFacing = function(_, v) facing = v end
	shown.SetPosition = function(_, _, x, y) moved = { x, y } end
	shown.GetEffectiveScale = function() return 1 end
	local at = { 100, 100 }
	GetCursorPosition = function() return at[1], at[2] end
	shown.scripts.OnMouseDown(shown, "LeftButton")
	at = { 150, 100 }
	shown.scripts.OnUpdate(shown)
	check("model: left drag turns it", facing and facing > 0.35, facing)
	shown.scripts.OnMouseUp(shown)
	check("model: drag ends", shown.scripts.OnUpdate == nil)
	shown.scripts.OnMouseDown(shown, "RightButton")
	at = { 150, 160 }
	shown.scripts.OnUpdate(shown)
	check("model: right drag moves it", moved and moved[2] > 0, moved and moved[2])
	shown.scripts.OnMouseUp(shown)
	local link = button(function(f) return rawget(f, "partLink") and rawget(f, "at") == 1 end)
	check("model: the panel lists the parts too", link ~= nil and link.name.text:find("Old Boss", 1, true) ~= nil)
	link.scripts.OnClick(link)
	eq("model: a click there changes the creature", models[#models], 9301)
	stepRow.scripts.OnClick(stepRow)
	check("model: a click on the step keeps the panel, back to the first creature", GetReadyLink.shown)
	stepRow.scripts.OnClick(stepRow)
	check("model: a second click closes it", not GetReadyLink.parent.parent.parent.shown)
	table.remove(ns.Chains, 1)
	ns.Npcs[9301], ns.Npcs[9302], ns.Objects[9303], ns.Items[9304] = nil, nil, nil, nil
	ns.Window.Refresh()
end

-- quests around a chain: one that only points the way, and one that comes after the goal
do
	reset()
	local c = { id = "ar", name = "AR", kind = "misc", side = "Both", steps = {
		{ quest = 9201, name = "Go see him", optional = true, leads = 9202 },
		{ quest = 9202, name = "The task", goal = true },
		{ quest = 9203, name = "A reward", extra = true, all = { 9202 } },
	} }
	eq("around: fresh", table.concat(Progress.Chain(c).states, " "), "ready ready locked")
	world.log[9202] = true
	eq("around: the pointer is not needed once its quest is in the log", table.concat(Progress.Chain(c).states, " "), "skipped active locked")
	world.log[9202] = nil
	world.done[9202] = true
	local p = Progress.Chain(c)
	eq("around: the goal done, the chain is done", p.done, true)
	eq("around: the quest after it is open, not skipped", table.concat(p.states, " "), "skipped done ready")
	world.done[9203] = true
	eq("around: and can be done", table.concat(Progress.Chain(c).states, " "), "skipped done done")
	world.done[9202], world.done[9203] = nil, nil
	world.done[9201] = true
	eq("around: the pointer done first", table.concat(Progress.Chain(c).states, " "), "done ready locked")
	world.done[9201] = nil
end

-- step marks: the game's own quest pictures
do
	reset()
	local c = { id = "ic", name = "IC", kind = "misc", side = "Both", steps = {
		{ quest = 9001, name = "One" }, { quest = 9002, name = "Two" }, { quest = 9003, name = "Three" },
		{ quest = 9004, name = "Four", all = { 9005 } }, { quest = 9005, name = "Five", goal = true },
	} }
	world.done[9001] = true
	world.log[9002], world.log[9003] = true, true
	C_QuestLog.IsComplete = function(id) return id == 9003 end
	local d = ns.View.Detail(c)
	local marks, states = {}, {}
	for i, s in ipairs(d.steps) do marks[i], states[i] = s.mark, s.state end
	eq("marks: one per kind", table.concat(marks, " "), "done active turnin locked ready")
	eq("marks: a complete quest is still an active step", states[3], "active")
	eq("marks: its status says to turn in", d.steps[3].status, "Ready to turn in")
	eq("marks: a quest in progress", d.steps[2].status, "In your quest log")
	-- the "Next" box says so when the first quest in the log is complete
	C_QuestLog.IsComplete = function() return true end
	eq("marks: next box for a complete quest", ns.View.Detail(c).next.label, "Ready to turn in")
	C_QuestLog.IsComplete = function() return false end
	eq("marks: next box for a quest in progress", ns.View.Detail(c).next.label, "In your quest log")
	-- a client without the call: nothing is ever "turnin"
	C_QuestLog.IsComplete = nil
	eq("marks: no call, no turn-in mark", ns.View.Detail(c).steps[3].mark, "active")
	world.done[9001], world.log[9002], world.log[9003] = nil, nil, nil
end

-- other classes: off by default, the option lists what they can do too
do
	reset()
	ns.db.allClasses = nil
	local function classRows()
		local n = 0
		for _, g in ipairs(ns.View.Build(nil, {}, {}).groups) do
			if g.kind:find("^class") then n = n + #g.chains end
		end
		return n
	end
	local function classLabels()
		local out = {}
		for _, g in ipairs(ns.View.Build(nil, {}, {}).groups) do
			if g.kind:find("^class") then out[#out + 1] = g.label end
		end
		return table.concat(out, ",")
	end
	eq("classes: one group, named after the player's class", classLabels(), "Warrior")
	local mine = classRows()
	local mageOnly = { id = "m", name = "M", kind = "class", side = "Both", classes = 128, steps = { { quest = 1, name = "Q", classes = 128 } } }
	check("classes: a mage chain is hidden from a warrior", not Progress.Visible(mageOnly, "Horde"))
	ns.Options.SetAllClasses(true)
	eq("classes: option saved", ns.db.allClasses, true)
	check("classes: the mage chain shows", Progress.Visible(mageOnly, "Horde"))
	eq("classes: its step counts", Progress.Chain(mageOnly).total, 1)
	check("classes: more class chains listed", classRows() > mine, classRows() .. " vs " .. mine)
	eq("classes: one group per class, the player's own first", classLabels(), "Warrior,Paladin,Hunter,Rogue,Priest,Shaman,Mage,Warlock,Druid")
	world.classId = 8 -- a mage
	check("classes: a mage's list starts with Mage", classLabels():find("^Mage,Warrior,") ~= nil, classLabels())
	world.classId = 1
	-- each class group folds on its own
	local folded = ns.View.Build(nil, { ["class-128"] = true }, {})
	for _, g in ipairs(folded.groups) do
		if g.label == "Mage" then check("classes: Mage folded", g.closed) end
		if g.label == "Druid" then check("classes: Druid still open", not g.closed) end
	end
	-- every chain of a class group is that class's
	local clean = true
	for _, g in ipairs(folded.groups) do
		if g.label == "Druid" then
			for _, c in ipairs(g.chains) do if not c.id:find("^c%-druid") then clean = false end end
		end
	end
	check("classes: Druid holds druid chains only", clean)
	check("classes: the other faction stays hidden", not Progress.Visible({ id = "a", name = "A", kind = "class", side = "Alliance", steps = {} }, "Horde"))
	ns.Options.SetAllClasses(false)
	eq("classes: off is not saved as false", ns.db.allClasses, nil)
	eq("classes: back to the player's own", classRows(), mine)
end

-- search over the list
do
	reset()
	local all = ns.View.Build(nil, {}, {})
	local found = ns.View.Build(nil, { dungeon = true }, {}, "  STRAT ")
	eq("search: text is trimmed and lowered", found.search, "strat")
	local names, closed = {}, false
	for _, g in ipairs(found.groups) do
		closed = closed or g.closed
		for _, c in ipairs(g.chains) do names[#names + 1] = c.name end
	end
	check("search: finds by a part of the name", #names >= 1 and #names < 10, #names)
	local onlyMatches = true
	for _, n in ipairs(names) do
		if not n:lower():find("strat", 1, true) then onlyMatches = false end
	end
	check("search: only chains that have the text", onlyMatches, table.concat(names, ", "))
	check("search: a folded group opens", not closed)
	eq("search: the picked chain stays", found.selected, all.selected)
	eq("search: nothing found, no groups", #ns.View.Build(nil, {}, {}, "zzzz").groups, 0)
	eq("search: only spaces is no search", ns.View.Build(nil, {}, {}, "   ").search, nil)

	-- the box in the window
	if not ns.Window.IsShown() then ns.Window.Toggle() end
	local box = GetReadySearch
	check("search: box made", box ~= nil and box.kind == "EditBox")
	local function rowCount()
		local n = 0
		for _, f in ipairs(frames) do
			if f.kind == "Button" and f.shown and rawget(f, "chain") and rawget(f, "bar") then n = n + 1 end
		end
		return n
	end
	local before = rowCount()
	box:SetText("strat")
	box.scripts.OnTextChanged(box)
	eq("search: the list shows the matches", rowCount(), #names)
	box:SetText("zzzz")
	box.scripts.OnTextChanged(box)
	eq("search: no rows", rowCount(), 0)
	check("search: says nothing was found", ns.Window.NothingFound())
	box.scripts.OnEscapePressed(box)
	box.scripts.OnTextChanged(box)
	eq("search: Esc clears the box", box.text, "")
	eq("search: the whole list is back", rowCount(), before)
	check("search: the note is gone", not ns.Window.NothingFound())
end

-- options: the cog in the window, the page in the game's options, the slash command
do
	ns.db.size = nil
	local cog = button(function(f) return rawget(f, "options") end)
	check("options: cog in the window", cog ~= nil)
	check("options: panel closed at first", not ns.Options.IsShown())
	cog.scripts.OnClick(cog)
	check("options: cog opens the panel", ns.Options.IsShown() and GetReadyOptions.shown)
	local function opt(name)
		return button(function(f) return rawget(f, "option") == name end)
	end
	eq("options: default size", ns.Options.Size(), 80)
	local more, less, all = opt("more"), opt("less"), opt("allClasses")
	check("options: controls made", more ~= nil and less ~= nil and all ~= nil)
	more.scripts.OnClick(more)
	eq("options: plus adds 5", ns.db.size, 85)
	eq("options: the window grows", GetReadyFrame.scale, 0.85 * 1.5)
	eq("options: value shown", more.parent and less.parent and ns.Options.Size() .. "%", "85%")
	for _ = 1, 10 do more.scripts.OnClick(more) end
	eq("options: not more than the screen", ns.db.size, 100)
	eq("options: plus dims at the top", more.alpha, 0.35)
	for _ = 1, 20 do less.scripts.OnClick(less) end
	eq("options: not too small to read", ns.db.size, 40)
	eq("options: minus dims at the bottom", less.alpha, 0.35)
	ns.db.size = nil
	ns.Window.Resize()
	all.scripts.OnClick(all)
	eq("options: other classes on", ns.db.allClasses, true)
	check("options: check mark shown", all.check.shown)
	all.scripts.OnClick(all)
	eq("options: other classes off", ns.db.allClasses, nil)
	check("options: check mark hidden", not all.check.shown)
	cog.scripts.OnClick(cog)
	check("options: cog closes the panel", not ns.Options.IsShown())
	check("options: page for the game's options", GetReadyOptionsPage ~= nil and GetReadyOptionsPage.name == "Get Ready")
	SlashCmdList.GETREADY("options")
	check("options: slash opens the panel", ns.Window.IsShown() and ns.Options.IsShown())
	SlashCmdList.GETREADY("options")
	check("options: slash again leaves it open", ns.Options.IsShown())
	cog.scripts.OnClick(cog)
end

-- "/gr dump": saves the place, the dungeon doors and what quests give
do
	-- a client without the calls: nothing breaks, the parts stay empty
	ns.db.dump = nil
	SlashCmdList.GETREADY("dump")
	local d = ns.db.dump
	check("dump: made", type(d) == "table")
	eq("dump: one place", #d.places, 1)
	eq("dump: no doors without the call", #d.entrances, 0)
	local some
	for _, c in ipairs(ns.Chains) do
		if c.steps[1] then some = c.steps[1].quest break end
	end
	check("dump: every chain quest has a record", type(d.quests[some]) == "table")
	check("dump: says to reload", printed[#printed - 1]:find("/reload", 1, true) ~= nil)
	check("dump: says to run again when quests are still unknown", printed[#printed]:find("/gr dump again", 1, true) ~= nil)

	-- a client with them
	local function vec(x, y) return { GetXY = function() return x, y end } end
	C_Map.GetBestMapForUnit = function() return 1434 end
	C_Map.GetMapInfo = function(map) if map == 1434 then return { name = "Stranglethorn Vale", parentMapID = 1415 } end end
	C_Map.GetPlayerMapPosition = function() return vec(0.2541, 0.7312) end
	function GetRealZoneText() return "Stranglethorn Vale" end
	function GetSubZoneText() return "The Vile Reef" end
	function GetInstanceInfo() return "Eastern Kingdoms", "none", 0, "", 0, 0, false, 0 end
	C_EncounterJournal = { GetDungeonEntrancesForMap = function(map)
		return { { name = "The Drowned City", position = vec(0.25, 0.73), areaPoiID = 9001, journalInstanceID = 77 } }
	end }
	C_QuestLog.RequestLoadQuestByID = function() end
	C_QuestLog.GetTitleForQuestID = function(id) return "Quest " .. id end
	function GetNumQuestLogRewards() return 1 end
	function GetQuestLogRewardInfo(i, id) return "Coin", "icon", 3, 1, true, 500 end
	function GetNumQuestLogChoices() return 2 end
	function GetQuestLogChoiceInfo(i, id) return "Pick", "icon", 1, 2, true, 600 + i end
	function GetQuestLogRewardXP() return 1200 end
	SlashCmdList.GETREADY("dump")
	eq("dump: a second run adds a place", #d.places, 2)
	local here = d.places[2]
	eq("dump: place map", here.map, 1434)
	eq("dump: place x in percent", here.x, 25.41)
	eq("dump: place sub zone", here.sub, "The Vile Reef")
	eq("dump: door found", #d.entrances, 1)
	eq("dump: door name", d.entrances[1].name, "The Drowned City")
	eq("dump: door y in percent", d.entrances[1].y, 73)
	local q = d.quests[some]
	eq("dump: quest title", q.title, "Quest " .. some)
	eq("dump: fixed reward", q.fixed[1][1], 500)
	eq("dump: fixed count", q.fixed[1][2], 3)
	eq("dump: choice rewards", #q.choice, 2)
	eq("dump: quest xp", q.xp, 1200)
	check("dump: all known, no ask to run again", printed[#printed]:find("/reload", 1, true) ~= nil)
	check("dump: notes which calls the client has", d.has.entrances == true and d.has.rewards == true)
	-- a third run asks the game for nothing: every quest is known
	local asked = 0
	C_QuestLog.RequestLoadQuestByID = function() asked = asked + 1 end
	SlashCmdList.GETREADY("dump")
	eq("dump: known quests are not asked for again", asked, 0)
	C_Map.GetBestMapForUnit, C_Map.GetMapInfo, C_Map.GetPlayerMapPosition = nil, nil, nil
	C_EncounterJournal = nil
	C_QuestLog.GetTitleForQuestID = function() return nil end
end

print = realPrint
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
