local ADDON, ns = ...

-- The addon's picture: a key. The TOC names the same one for the game's addon list.
ns.ICON = "Interface\\Icons\\INV_Misc_Key_15"

-- Game calls in one place, so tests can swap them out.
local api = {}
ns.api = api

function api.QuestDone(id)
	local fn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
	return fn and fn(id) and true or false
end

function api.OnQuest(id)
	return C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) and true or false
end

function api.QuestName(id)
	return C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id) or nil
end

function api.ItemCount(id)
	local fn = C_Item and C_Item.GetItemCount or GetItemCount
	return fn and fn(id, true) or 0
end

-- Name in the player's language. Nil until the game has loaded the item.
function api.ItemName(id)
	return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or nil
end

function api.ItemIcon(id)
	local fn = C_Item and C_Item.GetItemIconByID or GetItemIcon
	return fn and fn(id) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Quality color as r, g, b. Nil until the game has loaded the item.
function api.ItemQualityColor(id)
	local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then return color.r, color.g, color.b end
end

-- The game's item tooltip. note: one more line under it, such as where the item drops.
function api.ItemTooltip(owner, id, note)
	if not GameTooltip then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(id)
	else
		GameTooltip:SetHyperlink("item:" .. id)
	end
	if note then GameTooltip:AddLine(note, 0.85, 0.68, 0.3, true) end
	local usable, skill = api.Usable(id)
	if usable == "no" then
		GameTooltip:AddLine("Your class cannot use this.", 0.96, 0.45, 0.36, true)
	elseif usable == "learn" then
		GameTooltip:AddLine("You can learn to use this" .. (skill and (": " .. skill) or "") .. ".", 1, 0.82, 0, true)
	end
	GameTooltip:Show()
end

-- Plain tooltip: a gold title and a few lines under it.
function api.TextTooltip(owner, title, lines)
	if not GameTooltip then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 0.82, 0)
	for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, 0.95, 0.91, 0.8, true) end
	GameTooltip:Show()
end

function api.HideTooltip()
	if GameTooltip then GameTooltip:Hide() end
end

function api.Level()
	return UnitLevel("player") or 1
end

function api.Faction()
	return (UnitFactionGroup("player"))
end

-- Race as a bit, the way quest data stores it: human 1, orc 2, dwarf 4, ... 0 if unknown.
function api.RaceBit()
	if not UnitRace then return 0 end
	local _, _, raceId = UnitRace("player")
	return raceId and 2 ^ (raceId - 1) or 0
end

-- "Name-Realm": progress and marks belong to one character.
function api.Character()
	local name = UnitName and UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or "?"
	return tostring(name) .. "-" .. tostring(realm)
end

-- Class as a bit, the way quest data stores it: warrior 1, paladin 2, hunter 4, ...
function api.ClassBit()
	local _, _, classId = UnitClass("player")
	return classId and 2 ^ (classId - 1) or 0
end

function api.AreaName(id)
	return C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id) or nil
end

-- Returns standing (1 hated .. 8 exalted) and the faction name, or nil if unknown.
function api.Standing(factionId)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local data = C_Reputation.GetFactionDataByID(factionId)
		if data then return data.reaction, data.name end
	elseif GetFactionInfoByID then
		local name, _, standing = GetFactionInfoByID(factionId)
		if name then return standing, name end
	end
end

function api.StandingName(standing)
	return _G["FACTION_STANDING_LABEL" .. standing] or ("standing " .. standing)
end

-- Puts the map pin on a spot. x, y in percent. Returns true if it worked.
function api.SetWaypoint(map, x, y)
	if not (map and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return false end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then return false end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	return true
end

-- Can this character use an item? ---------------------------------------------------
-- For weapons and armor only. What a class can ever train is the classic rule set, written
-- out here; whether the skill is trained right now comes from the game.

local WEAPON, ARMOR = 2, 4 -- the game's item classes
-- item subclass -> the spell that is the skill
local WEAPON_SKILL = {
	[0] = 196, [1] = 197, -- axes, two-handed axes
	[2] = 264, [3] = 266, [18] = 5011, -- bows, guns, crossbows
	[4] = 198, [5] = 199, -- maces, two-handed maces
	[6] = 200, -- polearms
	[7] = 201, [8] = 202, -- swords, two-handed swords
	[10] = 227, -- staves
	[13] = 15590, -- fist weapons
	[15] = 1180, -- daggers
	[16] = 2567, -- thrown
	[19] = 5009, -- wands
}
local ARMOR_SKILL = { [1] = 9078, [2] = 9077, [3] = 8737, [4] = 750, [6] = 9116 } -- cloth, leather, mail, plate, shields
local RELIC = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" } -- librams, idols, totems

local function set(...)
	local out = {}
	for i = 1, select("#", ...) do out[select(i, ...)] = true end
	return out
end
local CAN_WEAPON = {
	WARRIOR = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
	PALADIN = set(0, 1, 4, 5, 6, 7, 8),
	HUNTER = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
	ROGUE = set(2, 3, 4, 7, 13, 15, 16, 18),
	PRIEST = set(4, 10, 15, 19),
	SHAMAN = set(0, 1, 4, 5, 10, 13, 15),
	MAGE = set(7, 10, 15, 19),
	WARLOCK = set(7, 10, 15, 19),
	DRUID = set(4, 5, 10, 13, 15),
}
local CAN_ARMOR = {
	WARRIOR = set(1, 2, 3, 4, 6),
	PALADIN = set(1, 2, 3, 4, 6),
	HUNTER = set(1, 2, 3),
	SHAMAN = set(1, 2, 3, 6),
	ROGUE = set(1, 2),
	DRUID = set(1, 2),
	PRIEST = set(1),
	MAGE = set(1),
	WARLOCK = set(1),
}

-- Item class, subclass and slot. Known at once, without waiting for the item to load.
function api.ItemKind(id)
	local fn = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	if not fn then return nil end
	local _, _, _, slot, _, classId, subclassId = fn(id)
	return classId, subclassId, slot
end

-- true or false; nil when the game cannot say.
function api.SkillKnown(spell)
	local fn = IsPlayerSpell or IsSpellKnown
	if not fn then return nil end
	return fn(spell) and true or false
end

function api.SkillName(spell)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spell) end
	return GetSpellInfo and (GetSpellInfo(spell)) or nil
end

-- Returns "yes", "learn" (the class can train it but this character has not; second value
-- is the skill's name), "no" (the class never can), or nil: not a weapon or armor, a kind
-- every class wears (rings, trinkets), or the game does not say.
function api.Usable(id)
	local classId, subclass, slot = api.ItemKind(id)
	local _, class = UnitClass("player")
	local can, skill
	if classId == WEAPON then
		can, skill = CAN_WEAPON[class], WEAPON_SKILL[subclass]
	elseif classId == ARMOR then
		if slot == "INVTYPE_CLOAK" then return "yes" end -- cloaks are cloth that everyone wears
		if RELIC[subclass] then return RELIC[subclass] == class and "yes" or "no" end
		can, skill = CAN_ARMOR[class], ARMOR_SKILL[subclass]
	end
	if not can or not skill then return nil end
	if not can[subclass] then return "no" end
	if api.SkillKnown(skill) == false then return "learn", api.SkillName(skill) end
	return "yes"
end

function ns.Print(text)
	print("|cffffd100Get Ready:|r " .. text)
end

-- Saved settings --------------------------------------------------------------

ns.db = { closed = {}, modes = {}, marked = {}, minimap = {} } -- replaced by the saved table once it has loaded

-- Chains the player marked as done by hand, per character.
function ns.Marked(id)
	local mine = ns.db.marked and ns.db.marked[api.Character()]
	return mine and mine[id] or false
end

function ns.Mark(id, on)
	local who = api.Character()
	ns.db.marked[who] = ns.db.marked[who] or {}
	ns.db.marked[who][id] = on and true or nil
end

local function LoadSettings()
	if type(GetReadyDB) ~= "table" then GetReadyDB = {} end
	ns.db = GetReadyDB
	if type(ns.db.closed) ~= "table" then ns.db.closed = {} end
	if type(ns.db.marked) ~= "table" then ns.db.marked = {} end -- [character][chain id] = true
	if type(ns.db.modes) ~= "table" then ns.db.modes = {} end -- steps as graph or list, per chain
	if type(ns.db.minimap) ~= "table" then ns.db.minimap = {} end -- the minimap button: angle, hide
end

-- Slash commands ------------------------------------------------------------

SLASH_GETREADY1 = "/gr"
SLASH_GETREADY2 = "/getready"
-- "/gr" opens or closes the window. "/gr size 80" makes it fill 80% of the screen.
-- "/gr minimap" hides the minimap button or brings it back.
SlashCmdList.GETREADY = function(msg)
	if tostring(msg or ""):lower():match("^%s*minimap%s*$") then
		ns.db.minimap.hide = not ns.db.minimap.hide or nil
		ns.MinimapButton.Apply()
		ns.Print(ns.db.minimap.hide and "Minimap button hidden. /gr minimap brings it back." or "Minimap button shown.")
		return
	end
	local size = tostring(msg or ""):lower():match("^%s*size%s+(%d+)")
	if size then
		ns.db.size = math.max(40, math.min(100, tonumber(size)))
		ns.Window.Resize()
		ns.Print("Window size: " .. ns.db.size .. "% of the screen.")
		return
	end
	ns.Window.Toggle()
end

-- Events --------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({
	"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "UPDATE_FACTION",
}) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == ADDON then
			LoadSettings()
			ns.MinimapButton.Apply()
		end
		return
	end
	if ns.Window then ns.Window.Queue() end
end)
