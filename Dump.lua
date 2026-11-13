local ADDON, ns = ...

-- "/gr dump": writes what the game itself knows into the saved settings, for the data build.
-- The quest database lacks some things: where the new dungeons are, and which quest rewards
-- you choose between. Stand at a dungeon door (or inside) and run it; each run adds the place.
-- Every game call is guarded: a call this client lacks leaves its part empty.

local Dump = {}
ns.Dump = Dump

local BATCH, PAUSE, WAIT = 10, 0.2, 6 -- quests per step, seconds between steps, seconds for the last ones to load
local MAX_MAP = 3000

local function try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if ok then return a, b, c, d, e, f, g, h end
	return nil
end

local function round(n) return n and math.floor(n * 10000 + 0.5) / 100 or nil end

-- Where the character stands now.
function Dump.Here()
	local rec = { zone = try(GetRealZoneText), sub = try(GetSubZoneText) }
	local map = C_Map and try(C_Map.GetBestMapForUnit, "player")
	if map then
		rec.map = map
		local info = try(C_Map.GetMapInfo, map)
		rec.mapName = info and info.name
		rec.parent = info and info.parentMapID
		local pos = try(C_Map.GetPlayerMapPosition, map, "player")
		if pos and pos.GetXY then
			local x, y = pos:GetXY()
			rec.x, rec.y = round(x), round(y)
		end
	end
	local name, kind, _, _, _, _, _, instance = try(GetInstanceInfo)
	rec.instanceName, rec.instanceKind, rec.instance = name, kind, instance
	return rec
end

-- Dungeon doors the game shows on its maps.
function Dump.Entrances()
	local list = {}
	local get = C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap
	if not (get and C_Map and C_Map.GetMapInfo) then return list end
	for map = 1, MAX_MAP do
		local info = try(C_Map.GetMapInfo, map)
		if info then
			for _, e in ipairs(try(get, map) or {}) do
				local x, y
				if e.position and e.position.GetXY then x, y = e.position:GetXY() end
				list[#list + 1] = { map = map, mapName = info.name, name = e.name, x = round(x), y = round(y),
					poi = e.areaPoiID, journal = e.journalInstanceID }
			end
		end
	end
	return list
end

-- What one quest gives, as the game tells it: items you get, items you choose from.
function Dump.Quest(id)
	local rec = { title = C_QuestLog and try(C_QuestLog.GetTitleForQuestID, id) }
	local fixed, choice = {}, {}
	for i = 1, try(GetNumQuestLogRewards, id) or 0 do
		local _, _, count, _, _, item = try(GetQuestLogRewardInfo, i, id)
		if item then fixed[#fixed + 1] = { item, count } end
	end
	for i = 1, try(GetNumQuestLogChoices, id, true) or 0 do
		local _, _, count, _, _, item = try(GetQuestLogChoiceInfo, i, id)
		if item then choice[#choice + 1] = { item, count } end
	end
	if #fixed > 0 then rec.fixed = fixed end
	if #choice > 0 then rec.choice = choice end
	rec.xp = try(GetQuestLogRewardXP, id)
	rec.money = try(GetQuestLogRewardMoney, id)
	return rec
end

local function questIds()
	local ids, seen = {}, {}
	for _, chain in ipairs(ns.Chains or {}) do
		for _, step in ipairs(chain.steps or {}) do
			if step.quest and not seen[step.quest] then
				seen[step.quest] = true
				ids[#ids + 1] = step.quest
			end
		end
	end
	return ids
end

-- Runs fn(id) over the list a few at a time, then calls done.
local function each(ids, fn, done)
	local at = 0
	local function step()
		for _ = 1, BATCH do
			at = at + 1
			if at > #ids then return done() end
			fn(ids[at])
		end
		C_Timer.After(PAUSE, step)
	end
	step()
end

local running, listener = false, nil

function Dump.Run()
	if running then return ns.Print("Dump is still running.") end
	running = true
	local dump = type(ns.db.dump) == "table" and ns.db.dump or {}
	ns.db.dump = dump
	dump.version = C_AddOns and try(C_AddOns.GetAddOnMetadata, ADDON, "Version")
	local version, number = try(GetBuildInfo)
	dump.build = version and (tostring(version) .. " " .. tostring(number)) or nil
	dump.places = type(dump.places) == "table" and dump.places or {}
	dump.places[#dump.places + 1] = Dump.Here()
	dump.entrances = Dump.Entrances()
	dump.quests = type(dump.quests) == "table" and dump.quests or {}
	-- which of the calls this client has
	dump.has = {
		entrances = C_EncounterJournal ~= nil and C_EncounterJournal.GetDungeonEntrancesForMap ~= nil,
		load = C_QuestLog ~= nil and C_QuestLog.RequestLoadQuestByID ~= nil,
		rewards = GetQuestLogRewardInfo ~= nil, choices = GetQuestLogChoiceInfo ~= nil,
		xp = GetQuestLogRewardXP ~= nil, money = GetQuestLogRewardMoney ~= nil,
	}

	-- The game answers a few quests at a time, so a run only asks for those still unknown
	-- and keeps what earlier runs found.
	local all, ids = questIds(), {}
	for _, id in ipairs(all) do
		if not (dump.quests[id] and dump.quests[id].title) then ids[#ids + 1] = id end
	end
	ns.Print(("Dump: place %d saved, %d dungeon doors. Reading %d quests..."):format(#dump.places, #dump.entrances, #ids))

	-- Take each quest as soon as the game says it has loaded.
	local failed = {}
	listener = listener or CreateFrame("Frame")
	listener:RegisterEvent("QUEST_DATA_LOAD_RESULT")
	listener:SetScript("OnEvent", function(_, _, id, ok)
		if ok then dump.quests[id] = Dump.Quest(id) else failed[id] = true end
	end)

	local load = C_QuestLog and C_QuestLog.RequestLoadQuestByID
	each(ids, function(id) try(load, id) end, function()
		C_Timer.After(WAIT, function()
			each(ids, function(id)
				if not (dump.quests[id] and dump.quests[id].title) then
					dump.quests[id] = Dump.Quest(id)
					if failed[id] then dump.quests[id].failed = true end
				end
			end, function()
				listener:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
				running = false
				local known = 0
				for _, id in ipairs(all) do
					if dump.quests[id] and dump.quests[id].title then known = known + 1 end
				end
				ns.Print(("Dump done: %d of %d quests known. Type /reload to save it."):format(known, #all))
				if known < #all then ns.Print("Run /gr dump again for more.") end
			end)
		end)
	end)
end
