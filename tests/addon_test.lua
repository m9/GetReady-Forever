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
		if k == "SetScript" then return function(self, event, fn) self.scripts[event] = fn end end
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
eq("toc file count", loaded, 6)
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
	eq("low level hint", Progress.Hints(chain.steps[1], "locked", p.need[1])[1], "Needs level 10")
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
	eq("ahead line 3", lines[3], "Needs: level 62, Revered with Faction 529")
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
	eq("view: numbers", dv.stats[1].label .. "=" .. dv.stats[1].value .. " " .. dv.stats[2].value .. " " .. dv.stats[3].value .. " " .. dv.stats[4].value, "Progress=0 / 3 3 7,000 10")
	eq("view: XP has its own tone", dv.stats[3].tone, "xp")
	eq("view: facts", dv.facts[1].label .. "/" .. dv.facts[2].label .. "/" .. dv.facts[2].tone, "Dungeons/Needs/warn")
	eq("view: next box knows its state", dv.next.state, "ready")
	eq("view: tag", dv.tag, "Raid  -  Level 10+")
	world.level = 5
	eq("view: level too low is a warning", ns.View.Detail(rc).stats[4].tone, "warn")
	do
		-- level 5: step 1 asks for 10, step 2 for 62 and also waits for step 1, step 3 for 20
		local low = ns.View.Detail(rc)
		eq("level: every open step says what it asks for", low.steps[1].needLevel .. "/" .. low.steps[2].needLevel .. "/" .. low.steps[3].needLevel, "10/62/20")
		eq("level: line on a step locked by level", table.concat(low.steps[1].hints, "|"), "Needs level 10")
		eq("level: line on a step that also waits for an earlier one", table.concat(low.steps[2].hints, "|"), "Needs level 62")
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
	eq("graph: step status", d.steps[1].status .. "/" .. d.steps[3].status .. "/" .. d.steps[5].status, "Turned in/Can start now/Locked")
	eq("graph: player picks the list", ns.View.Detail(chain, nil, { t = "list" }).mode, "list")

	reset()
	eq("graph: none without links", ns.View.Graph(Progress.Chain(pick)), nil)
	d = ns.View.Detail(pick, nil, { p = "graph" })
	check("graph: no links, so a list whatever was picked", d.mode == "list" and d.graph == nil)

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
	eq("mark: the box says who said so", d.next.name, "You marked this chain as done.")
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
	check("numbers under the banner", t:find("Quests left", 1, true) ~= nil and t:find("XP to earn", 1, true) ~= nil and t:find("86,610", 1, true) ~= nil and t:find("0 / 14", 1, true) ~= nil, t)
	check("facts under the numbers", t:find("Dungeons", 1, true) ~= nil and t:find("Blackrock Spire", 1, true) ~= nil, t)
	check("banner says what kind of chain", t:find("Raid  -  Level 55+", 1, true) ~= nil, t)
	check("ahead: reputation the chain gives", t:find("Reputation", 1, true) ~= nil and t:find("+450 Orgrimmar", 1, true) ~= nil, t)
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
	check("loot: heading", texts():find("Possible loot", 1, true) ~= nil and texts():find("May drop from enemies on the way.", 1, true) ~= nil)
	local rewardIcons = 0
	for _, f in ipairs(frames) do
		if f.kind == "Button" and f.shown and rawget(f, "note") == false and rawget(f, "item") and f.parent and rawget(f.parent, "more") and rawget(f.parent, "label") then rewardIcons = rewardIcons + 1 end
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
	eq("graph: a box per step", boxes(), 14)
	local box = button(function(f) local s = rawget(f, "step") return s and s.quest == 4903 end)
	check("graph: first step box", box ~= nil)
	if box then
		eq("graph: box name", box.name.text, "Warlord's Command")
		box.scripts.OnEnter(box)
		eq("graph: tooltip title", tips.title, "Warlord's Command")
		eq("graph: tooltip says the state", tips.lines[1], "Can start now")
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
		eq("graph: click sets a pin", #pins, before + 1)
	end

	-- the graph is wider than the window: wheel and drag move it
	local scroll
	for _, f in ipairs(frames) do if f.kind == "ScrollFrame" and f.scripts.OnMouseWheel then scroll = f end end
	check("graph: scroll area", scroll ~= nil)
	if scroll then
		eq("graph: starts at the next step", scroll.scrollX, 0)
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
		eq("graph: stops at the right end", scroll.scrollX, 12 * 196 + 11 * 26 - (1480 - 290 - 270 - 18 * 4 - 22 * 2 - 12))
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
	eq("graph: back to the graph", boxes(), 14)
	eq("graph: choice saved again", ns.db.modes["ony-horde"], "graph")
end

-- an event while open redraws
world.done[4903] = true
local ok, err = pcall(eventFrame.scripts.OnEvent, eventFrame, "QUEST_TURNED_IN")
check("event refresh runs", ok, err)
check("count moved", texts():find("1/14", 1, true) ~= nil)

-- pick another chain, selection is saved
do
	local row = button(function(f) return rawget(f, "chain") and f.chain.id == "mc" end)
	check("molten core row", row ~= nil)
	if row then row.scripts.OnClick(row) end
	eq("selection saved", ns.db.selected, "mc")
	check("molten core steps shown", texts():find("Attunement to the Core", 1, true) ~= nil)
	check("one step: no graph button", button(function(f)
		local l = rawget(f, "label")
		return l and (rawget(l, "text") == "Show graph" or rawget(l, "text") == "Show list")
	end) == nil)
	world.done[7848] = true
	eventFrame.scripts.OnEvent(eventFrame, "QUEST_TURNED_IN")
	check("molten core done", texts():find("Nothing left to do.", 1, true) ~= nil)
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
	eq("size: default share", GetReadyFrame.scale, 0.96 * 1.5)
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
	check("mark: window says so", texts():find("You marked this chain as done.", 1, true) ~= nil)
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	check("mark: list shows the check and the word", row and row.check.shown and row.count.text == "Marked")
	b = mark("Not done after all")
	check("mark: undo button", b ~= nil)
	if b then b.scripts.OnClick(b) end
	check("mark: undone", ns.db.marked["Tester-Realm"]["ubrs-key"] == nil and mark("Mark as done") ~= nil)
	row = button(function(f) return rawget(f, "chain") and f.chain.id == "ubrs-key" end)
	check("mark: list back to the count", row and not row.check.shown and row.count.text == "0/2")
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
	check("class chains: group heading", texts():find("Class", 1, true) ~= nil)
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

print = realPrint
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
