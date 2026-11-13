local _, ns = ...

-- Main window: chains on the left, the picked chain's steps in the middle, and a side panel
-- on the right with two tabs: details (of the chain, or of the step you clicked) and loot.
-- The steps show as a list, or as a graph when they lead to one another; they are what the
-- window is for, so they get most of the room.
--
-- Look: black and gold. Gold is for names, headings and what is picked. Plain text is
-- off-white, secondary text grey, so the gold stays readable. A few other colors each mean
-- one thing everywhere: green done, blue can start, red missing, violet XP, teal reputation.

local Window = {}
ns.Window = Window

-- Sizes ---------------------------------------------------------------------------

-- The window is laid out at this fixed size and then scaled as a whole to fill a share of
-- the screen (Fit), so text and icons grow with the window. The sizes below are in the
-- window's own units, not screen pixels.
local WIDTH, HEIGHT = 1480, 830
local DEFAULT_SIZE = ns.DEFAULT_SIZE -- percent of the screen; the options and "/gr size N" change it
local TOP = 64 -- room for the window's title
local PAD = 18
local LIST_WIDTH = 290
local SEARCH_HEIGHT = 22
local LIST_ROW, LIST_HEAD = 34, 36
local LOOT_WIDTH = 320 -- the side panel on the right, without its scroll bar
local SIDE_WIDTH = LOOT_WIDTH + 40 -- the side panel with its edges and scroll bar
local DETAIL_WIDTH = WIDTH - LIST_WIDTH - 22 - SIDE_WIDTH - PAD * 4 -- middle, edge to edge
local DETAIL_HEIGHT = HEIGHT - TOP - PAD -- middle, top to bottom
local WIDE_WIDTH = WIDTH - LIST_WIDTH - 22 - PAD * 3 -- the middle while the side panel is closed
local HEAD_ICON = 26 -- a reward icon in the banner, with its gap
local BANNER_HEIGHT = 190 -- picture of the place with the chain's name and numbers on it
local TAB_HEIGHT = 28 -- the side panel's title line
local LOOT_HEIGHT = 560 -- the "Rewards and loot" pop-up
local FACT_LINES = 3 -- lines in the banner for facts that need words: dungeons, needs, reputation
local FACT_LABEL, FACT_ROW = 92, 20 -- "Level", "Dungeons", "Reputation" lines in the side panel
local ICON = 36 -- a reward or loot icon, with its gap
local LOOT_PER_ROW = math.floor(LOOT_WIDTH / ICON)
local REWARD_ROWS = 4 -- more than this many rows of a step's rewards in the side panel is cut short
local INFO_ROWS = 8 -- label and text lines in the side panel
local STEP_WIDTH = DETAIL_WIDTH - 26 -- minus the scroll bar
local STEP_ROW = 28
local STEP_ICON = 24 -- a reward icon on a step, with its gap
local STEP_ICONS = 4 -- reward icons shown on a step
local STEP_RIGHT = 28 + STEP_ICONS * STEP_ICON -- room the icons and "+2" take on the right of a step

-- Steps as a graph: one box per step, in columns, with lines between them.
local NODE_W, NODE_H = 196, 50 -- two lines: the name, then XP and reward icons
local NODE_GAP = 26 -- room between columns, for the lines
local NODE_ROW = 60 -- from one row to the next
local NODE_ICON = 22 -- a reward icon on a box, with its gap
local NODE_ICONS = 3 -- reward icons shown on a box
local GRAPH_PAD = 6
local GRAPH_WIDTH = DETAIL_WIDTH - GRAPH_PAD * 2 -- the part of the graph you see

-- Colors --------------------------------------------------------------------------

local FANTASY_FONT = "Fonts\\MORPHEUS.TTF"
-- Text sizes, by the game font each kind of text is made from.
local FONT_SIZE = { GameFontHighlightSmall = 12, GameFontNormalSmall = 12, GameFontHighlight = 14, GameFontNormalLarge = 19 }

local BLACK = { 0.03, 0.025, 0.02 } -- the window
local PANEL = { 0.075, 0.07, 0.062 } -- a block on the window
local PANEL_HI = { 0.12, 0.108, 0.09 } -- a block that wants attention
local LINE = { 0.27, 0.235, 0.16 } -- edges and rules that should not shout

local GOLD = { 1.00, 0.82, 0.00 }
local GOLD_SOFT = { 0.85, 0.68, 0.30 }
local GOLD_DIM = { 0.55, 0.44, 0.20 }

local TEXT = { 0.94, 0.92, 0.86 } -- what you read
local MUTED = { 0.64, 0.61, 0.55 } -- labels and second lines
local FAINT = { 0.44, 0.42, 0.38 } -- what does not matter right now

local GREEN = { 0.45, 0.80, 0.40 } -- done
local GREEN_DIM = { 0.38, 0.56, 0.35 } -- no longer needed
local BLUE = { 0.47, 0.74, 1.00 } -- can start now
local RED = { 0.96, 0.45, 0.36 } -- something is missing
local VIOLET = { 0.76, 0.64, 0.98 } -- XP
local TEAL = { 0.42, 0.82, 0.76 } -- reputation

-- A chain's first level in the list, by how it stands to the player's level: the colors
-- the game uses for quests.
local LEVEL_COLOR = {
	over = { 1.00, 0.25, 0.20 }, -- above the player
	even = { 1.00, 0.82, 0.00 }, -- within two levels below
	under = { 0.25, 0.75, 0.25 }, -- up to nine below
	far = { 0.55, 0.55, 0.55 }, -- further below
}

-- "[30] " before a step's name, in the color of how that level stands to the player's.
-- Grey once the step is behind the player. Empty for a step that asks for no level.
local function LevelTag(step)
	if not step.min then return "" end
	local finished = step.state == "done" or step.state == "skipped"
	local c = finished and LEVEL_COLOR.far or (LEVEL_COLOR[step.minTone] or MUTED)
	return ("|cff%02x%02x%02x[%d]|r "):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), step.min)
end

-- A step's state: the color of its mark and stripe, and of its name.
-- A quest in the log is silver until it is complete; ready to turn in is gold.
local SILVER = { 0.78, 0.78, 0.80 }
local STATE_COLOR = { done = GREEN, skipped = GREEN_DIM, active = SILVER, turnin = GOLD, ready = BLUE, locked = FAINT }
local STATE_TEXT = { done = GREEN, skipped = GREEN_DIM, active = SILVER, turnin = GOLD, ready = TEXT, locked = MUTED }
-- The marks are the game's own quest pictures, the ones over quest givers' heads: a yellow
-- "!" for a quest you can take, a grey "?" for one in your log, a yellow "?" for one ready
-- to turn in. "turnin" is not a step state of its own: it is an active step whose quest is
-- complete (View.lua's "mark").
local STATE_ICON = {
	done = "Interface\\RaidFrame\\ReadyCheck-Ready",
	skipped = "Interface\\RaidFrame\\ReadyCheck-Ready",
	ready = "Interface\\GossipFrame\\AvailableQuestIcon",
	active = "Interface\\GossipFrame\\IncompleteQuestIcon",
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
	locked = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK",
}
-- A step that has you kill something carries the game's small skull.
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local function HasKill(step)
	for _, part in ipairs(step.parts or {}) do
		if part.kind == "kill" then return true end
	end
	return false
end

-- Picture laid over an item icon when the character cannot use the item as things stand.
-- Both are the game's own, with nothing behind them, so the item still shows through.
local OVERLAY = {
	no = "Interface\\RaidFrame\\ReadyCheck-NotReady", -- red cross: the class never can
	learn = "Interface\\RaidFrame\\ReadyCheck-Waiting", -- yellow question mark: the class can learn to
}
-- What a number or a fact is about (View.lua's "tone").
local TONE = { plain = TEXT, good = GREEN, warn = RED, xp = VIOLET, rep = TEAL }

-- Small builders ------------------------------------------------------------------

local function Color(region, c, a)
	region:SetTextColor(c[1], c[2], c[3], a or 1)
end

local function Text(parent, font, c)
	font = font or "GameFontHighlightSmall"
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	-- our own size, in the game's font for the player's language
	if STANDARD_TEXT_FONT and FONT_SIZE[font] then fs:SetFont(STANDARD_TEXT_FONT, FONT_SIZE[font], "") end
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	Color(fs, c or TEXT)
	return fs
end

-- Heading in the fantasy font. Falls back to the normal font if the file is missing.
local function Heading(parent, size, c)
	local fs = Text(parent, "GameFontNormalLarge", c or GOLD)
	fs:SetFont(FANTASY_FONT, size, "")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
end

local function Fill(parent, layer, c, a)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(c[1], c[2], c[3], a or 1)
	return t
end

-- A block: flat fill with a thin edge.
local function Panel(f, fill, alpha, edge)
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	fill, edge = fill or PANEL, edge or LINE
	f:SetBackdropColor(fill[1], fill[2], fill[3], alpha or 0.9)
	f:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
end

-- Color code for a piece of a line of text.
local function Code(c)
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
local MUTED_CODE, VIOLET_CODE, TEAL_CODE, RED_CODE = Code(MUTED), Code(VIOLET), Code(TEAL), Code(RED)

-- Colors the parts of a help line: "Start:" grey so the name after it stands out,
-- XP violet, reputation teal, and a whole "Needs ..." line red.
local function Pretty(line)
	if line:find("^Needs ") or line:find("^Required level") then return RED_CODE .. line .. "|r" end
	if line:find("^Gives:") then
		line = line:gsub("([%d,]+ XP)", VIOLET_CODE .. "%1|r"):gsub("(%+[%d,]+ [^,|]+)", TEAL_CODE .. "%1|r")
	end
	return (line:gsub("^([%a ]+:)", MUTED_CODE .. "%1|r", 1))
end

local function PrettyLines(lines)
	local out = {}
	for i, line in ipairs(lines) do out[i] = Pretty(line) end
	return table.concat(out, "\n")
end

-- Gold line that fades out to both sides.
local function Divider(parent, width)
	local line = CreateFrame("Frame", nil, parent)
	line:SetSize(width, 1)
	local half = width / 2
	local left = Fill(line, "ARTWORK", GOLD_SOFT, 0.9)
	left:SetPoint("TOPLEFT")
	left:SetSize(half, 1)
	local right = Fill(line, "ARTWORK", GOLD_SOFT, 0.9)
	right:SetPoint("TOPRIGHT")
	right:SetSize(half, 1)
	-- The fade is a nicety; a plain line is fine if this client lacks it.
	if CreateColor and left.SetGradient then
		local clear = CreateColor(GOLD_SOFT[1], GOLD_SOFT[2], GOLD_SOFT[3], 0)
		local solid = CreateColor(GOLD_SOFT[1], GOLD_SOFT[2], GOLD_SOFT[3], 0.9)
		pcall(left.SetGradient, left, "HORIZONTAL", clear, solid)
		pcall(right.SetGradient, right, "HORIZONTAL", solid, clear)
	end
	return line
end

-- Progress bar: dark track, gold fill that turns green when full.
local function Bar(parent, width, height)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetSize(width, height)
	bar.track = Fill(bar, "BACKGROUND", LINE, 0.8)
	bar.track:SetAllPoints()
	bar.fill = Fill(bar, "ARTWORK", GOLD, 1)
	bar.fill:SetPoint("TOPLEFT")
	bar.fill:SetHeight(height)
	bar.width = width
	function bar:Set(fraction)
		fraction = math.max(0, math.min(1, fraction or 0))
		local c = fraction >= 1 and GREEN or GOLD
		self.fill:SetColorTexture(c[1], c[2], c[3], 1)
		self.fill:SetShown(fraction > 0)
		self.fill:SetWidth(math.max(1, self.width * fraction))
	end
	return bar
end

-- Dark button with a gold edge.
local function GoldButton(parent, label, width)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, 26)
	Panel(b, PANEL_HI, 1, GOLD_DIM)
	b.label = Text(b, "GameFontNormalSmall", GOLD)
	b.label:SetPoint("CENTER")
	b.label:SetText(label)
	b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1) end)
	return b
end

-- The small picture that says what state a step is in.
local function Mark(parent, size)
	local m = CreateFrame("Frame", nil, parent)
	m:SetSize(size, size)
	m.icon = m:CreateTexture(nil, "ARTWORK")
	m.icon:SetAllPoints()
	m.dot = m:CreateTexture(nil, "ARTWORK")
	m.dot:SetSize(size - 6, size - 6)
	m.dot:SetPoint("CENTER")
	function m:Set(state)
		local path = STATE_ICON[state]
		self.icon:SetShown(path ~= nil)
		self.dot:SetShown(path == nil)
		if path then
			self.icon:SetTexture(path)
			self.icon:SetDesaturated(state == "skipped" or state == "locked")
			self.icon:SetAlpha((state == "skipped" or state == "locked") and 0.7 or 1)
		else
			local c = STATE_COLOR[state] or FAINT
			self.dot:SetColorTexture(c[1], c[2], c[3], 1)
		end
	end
	return m
end

-- White outline for the picture laid over an item icon: eight white copies of its shape,
-- each a little off to one side, under the picture itself. A copy is a white square cut to
-- the picture's shape by a mask. Made the first time a button needs it; most never do.
local RIM = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }
local function ShowRim(b, path)
	if not b.rim then
		b.rim = {}
		local step = b.overSize >= 16 and 1 or 0.5 -- how far each copy sits out: the outline's thickness
		for i, dir in ipairs(RIM) do
			-- a client without masks gets the picture without the outline
			local mask = b.CreateMaskTexture and b:CreateMaskTexture()
			if not mask then break end
			mask:SetSize(b.overSize, b.overSize)
			mask:SetPoint("CENTER", dir[1] * step, dir[2] * step)
			local white = b:CreateTexture(nil, "OVERLAY")
			white:SetDrawLayer("OVERLAY", 1)
			white:SetColorTexture(1, 1, 1, 1)
			white:SetSize(b.overSize, b.overSize)
			white:SetPoint("CENTER", dir[1] * step, dir[2] * step)
			white:AddMaskTexture(mask)
			b.rim[i] = { white = white, mask = mask }
		end
	end
	for _, copy in ipairs(b.rim) do
		copy.mask:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		copy.white:Show()
	end
end

local function HideRim(b)
	for _, copy in ipairs(b.rim or {}) do copy.white:Hide() end
end

-- Item icon with the game's own tooltip.
local function IconButton(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.note = false -- one more tooltip line; the loot column sets it
	b.edge = Fill(b, "BACKGROUND", LINE, 1)
	b.edge:SetAllPoints()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- laid over the middle of the picture, see OVERLAY
	b.overSize = math.floor(size * 0.55)
	b.rim = false -- its white outline, see ShowRim
	b.over = b:CreateTexture(nil, "OVERLAY")
	b.over:SetDrawLayer("OVERLAY", 2)
	b.over:SetPoint("CENTER")
	b.over:SetSize(b.overSize, b.overSize)
	b:SetScript("OnEnter", function(self) if self.item then ns.api.ItemTooltip(self, self.item, self.note) end end)
	b:SetScript("OnLeave", function() ns.api.HideTooltip() end)
	function b:SetItem(id)
		self.item = id
		self.icon:SetTexture(ns.api.ItemIcon(id))
		local usable = ns.api.Usable(id)
		self.usable = usable or false
		-- the edge takes the item's quality color once the game knows it
		local r, g, bl = ns.api.ItemQualityColor(id)
		if r then
			self.edge:SetColorTexture(r, g, bl, 1)
		else
			self.edge:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
		end
		-- a red cross over the picture when the class can never use the item, a question
		-- mark when it can learn to; both with a white outline
		local mark = OVERLAY[usable]
		self.over:SetShown(mark ~= nil)
		if mark then
			self.over:SetTexture(mark)
			ShowRim(self, mark)
		else
			HideRim(self)
		end
	end
	return b
end

-- Shows up to max icons from a list in a row of pooled buttons; returns how many did not fit.
local function ShowIcons(pool, parent, items, max, size, place)
	local shown = math.min(#items, max)
	for i = 1, shown do
		local b = pool[i]
		if not b then
			b = IconButton(parent, size)
			pool[i] = b
			place(b, i)
		end
		b:SetItem(items[i])
		b:Show()
	end
	for i = shown + 1, #pool do pool[i]:Hide() end
	return #items - shown
end

-- State ---------------------------------------------------------------------------

local frame, listChild, detail, stepChild, graphScroll, graphChild
local headRows, chainRows, stepRows, nodes, segs = {}, {}, {}, {}, {}
local side, info -- right panel and its "Details" tab
local loot, lootChild, lootHeads, lootIcons -- its "Loot" tab: frame, scroll child, pools
local pickedStep -- quest ID of the step whose details the side panel shows, or nil
local sideOpen = false -- the side panel is closed until a step is clicked
local lootOpen = false -- the "Rewards and loot" pop-up
local INFO_LINKS = 10 -- "After" and "Leads to" lines in the side panel
local INFO_PARTS = 8 -- kill, use and get lines in the side panel
local PART_ROW = 22 -- a kill, use or get line under a step in the list
local MODEL_HEIGHT = 190 -- the creature's 3D model in the side panel
local pickedPart -- which part of the picked step the side panel shows a model of, or nil
local partRows = {}
local mid = WIDE_WIDTH -- how wide the middle is right now: WIDE_WIDTH, or DETAIL_WIDTH beside the side panel
-- Where the graph is scrolled to, how far it can go, and whose graph it is.
local graph = { x = 0, y = 0, maxX = 0, maxY = 0 }
local selected
local searchBox, search = nil, "" -- the box over the list and the text in it
local noneText -- "Nothing found." under the box
local queued = false

local function Select(id)
	selected = id
	ns.db.selected = id
	pickedStep = nil
	Window.Refresh()
end

local function CloseSide()
	pickedStep = nil
	Window.Refresh()
end

-- Shows a step in the side panel.
local function GoStep(quest)
	if quest == pickedStep then return end
	pickedStep, pickedPart = quest, nil
	Window.Refresh()
end

-- A click on a kill, use or get line: shows its step, and that creature's model.
local function PickPart(quest, at)
	if type(quest) ~= "number" then return end
	pickedStep, pickedPart = quest, at
	Window.Refresh()
end

-- A kill, use or get line under a step in the list.
local function PartRow(i)
	local row = partRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, stepChild)
	row:SetHeight(PART_ROW)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.mark = Mark(row, 14)
	row.mark:SetPoint("LEFT", 34, 0)
	row.skull = row:CreateTexture(nil, "ARTWORK")
	row.skull:SetSize(14, 14)
	row.skull:SetPoint("LEFT", 54, 0)
	row.skull:SetTexture(SKULL)
	row.name = Text(row, "GameFontHighlightSmall", TEXT)
	row.name:SetPoint("LEFT", 54, 0)
	row.name:SetWordWrap(false)
	row.partRow = true
	row:SetScript("OnClick", function(self) PickPart(self.quest, self.at) end)
	partRows[i] = row
	return row
end

-- One line for a part: "Kill  Name (place)", the word grey, the place grey.
local function PartText(part)
	return MUTED_CODE .. part.label .. "|r  " .. part.name .. MUTED_CODE .. part.place .. "|r"
end

-- A click on a step in the list or graph: shows it; a second click on it closes the panel.
local function PickStep(quest)
	if type(quest) ~= "number" then return end -- "Reach level N" has no quest and nothing more to show
	if quest == pickedStep and not pickedPart then return CloseSide() end
	if quest == pickedStep then
		pickedPart = nil
		return Window.Refresh()
	end
	GoStep(quest)
end

-- "Rewards and loot" in the header: opens its pop-up, or closes it.
local function ToggleLoot()
	lootOpen = not lootOpen
	Window.Refresh()
end

-- "Show on map": puts a pin on the place and opens the game's map there, in front of this
-- window. The window stays open behind it.
local function Pin(target)
	if not target then return end
	if ns.api.SetWaypoint(target.map, target.x, target.y) then
		ns.Print("Map pin: " .. target.name)
		ns.api.OpenMap(target.map)
	else
		ns.Print("No map pin here.")
	end
end

-- Left list -----------------------------------------------------------------------

local function HeadRow(i)
	local row = headRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, listChild)
	row:SetSize(LIST_WIDTH - 8, LIST_HEAD)
	row.label = Heading(row, 19, GOLD)
	row.label:SetPoint("BOTTOMLEFT", 6, 7)
	row.count = Text(row, "GameFontHighlightSmall", MUTED)
	row.count:SetPoint("BOTTOMRIGHT", -8, 7)
	row.line = Fill(row, "ARTWORK", GOLD_DIM, 0.7)
	row.line:SetPoint("BOTTOMLEFT", 2, 1)
	row.line:SetPoint("BOTTOMRIGHT", -2, 1)
	row.line:SetHeight(1)
	row:SetScript("OnClick", function(self)
		ns.db.closed[self.group] = not ns.db.closed[self.group] or nil
		Window.Refresh()
	end)
	headRows[i] = row
	return row
end

local function ChainRow(i)
	local row = chainRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, listChild)
	row:SetSize(LIST_WIDTH - 8, LIST_ROW)
	row.pick = Fill(row, "BACKGROUND", GOLD, 0.13)
	row.pick:SetAllPoints()
	row.edge = Fill(row, "ARTWORK", GOLD, 1)
	row.edge:SetPoint("TOPLEFT")
	row.edge:SetPoint("BOTTOMLEFT")
	row.edge:SetWidth(3)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.name = Text(row, "GameFontHighlight", TEXT)
	row.name:SetPoint("TOPLEFT", 12, -7)
	row.name:SetWidth(LIST_WIDTH - 88)
	row.name:SetWordWrap(false)
	-- New in Forever: a blue infinity sign after the name. Drawn in Arial Narrow, which has the sign.
	row.new = Text(row, "GameFontHighlight", BLUE)
	row.new:SetFont("Fonts\\ARIALN.TTF", 18, "")
	row.new:SetPoint("LEFT", row.name, "RIGHT", 5, 1)
	row.new:SetText("\226\136\158")
	row.count = Text(row, "GameFontHighlightSmall", MUTED)
	row.count:SetPoint("TOPRIGHT", -8, -9)
	row.count:SetJustifyH("RIGHT")
	row.check = Mark(row, 16) -- finished chains get the green check
	row.check:SetPoint("TOPRIGHT", -8, -8)
	row.check:Set("done")
	row.bar = Bar(row, LIST_WIDTH - 30, 4)
	row.bar:SetPoint("BOTTOMLEFT", 12, 3)
	row:SetScript("OnClick", function(self) Select(self.chain.id) end)
	chainRows[i] = row
	return row
end

-- Middle --------------------------------------------------------------------------

local function StepRow(i)
	local row = stepRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, stepChild)
	row:SetWidth(STEP_WIDTH)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.05)
	row.rule = Fill(row, "BACKGROUND", LINE, 0.45)
	row.rule:SetPoint("BOTTOMLEFT")
	row.rule:SetPoint("BOTTOMRIGHT")
	row.rule:SetHeight(1)
	row.mark = Mark(row, 18)
	row.mark:SetPoint("TOPLEFT", 4, -5)
	row.name = Text(row, "GameFontHighlight", TEXT)
	row.name:SetPoint("TOPLEFT", 30, -6)
	row.name:SetWidth(STEP_WIDTH - 34 - STEP_RIGHT - 104)
	row.name:SetWordWrap(false)
	-- right side: XP, then reward icons
	-- a skull left of the XP, for a step with something to kill
	row.skull = row:CreateTexture(nil, "ARTWORK")
	row.skull:SetSize(16, 16)
	row.skull:SetPoint("TOPRIGHT", -STEP_RIGHT - 8 - 96 - 4, -6)
	row.skull:SetTexture(SKULL)
	row.xp = Text(row, "GameFontHighlightSmall", VIOLET)
	row.xp:SetPoint("TOPRIGHT", -STEP_RIGHT - 8, -8)
	row.xp:SetWidth(96)
	row.xp:SetJustifyH("RIGHT")
	row.icons = {}
	row.more = Text(row, "GameFontHighlightSmall", MUTED)
	row.more:SetPoint("TOPRIGHT", -2, -8)
	row.more:SetWidth(26)
	row.more:SetJustifyH("RIGHT")
	row.hint = Text(row, "GameFontHighlightSmall", TEXT)
	row.hint:SetPoint("TOPLEFT", 30, -STEP_ROW)
	row.hint:SetWidth(STEP_WIDTH - 34)
	row.hint:SetSpacing(3)
	row.pick = Fill(row, "BACKGROUND", GOLD, 0.10) -- the step shown in the side panel
	row.pick:SetAllPoints()
	row.pickEdge = Fill(row, "ARTWORK", GOLD, 1)
	row.pickEdge:SetPoint("TOPLEFT")
	row.pickEdge:SetPoint("BOTTOMLEFT")
	row.pickEdge:SetWidth(2)
	row:SetScript("OnClick", function(self) PickStep(self.quest) end)
	stepRows[i] = row
	return row
end

-- Graph ---------------------------------------------------------------------------

local function ScrollGraph(x, y)
	graph.x = math.max(0, math.min(graph.maxX, x))
	graph.y = math.max(0, math.min(graph.maxY, y))
	graphScroll:SetHorizontalScroll(graph.x)
	graphScroll:SetVerticalScroll(graph.y)
end

-- The wheel moves a tall graph up and down, any other sideways. Shift always goes sideways.
local function WheelGraph(_, delta)
	if graph.maxY == 0 or (IsShiftKeyDown and IsShiftKeyDown()) then
		ScrollGraph(graph.x - delta * (NODE_W + NODE_GAP) / 2, graph.y)
	else
		ScrollGraph(graph.x, graph.y - delta * NODE_ROW * 2)
	end
end

-- Runs every frame while the mouse button is held on the graph's background.
local function DragGraph(self)
	local scale = self:GetEffectiveScale() or 1
	local x, y = GetCursorPosition()
	ScrollGraph(graph.fromX - (x - graph.cursorX) / scale, graph.fromY + (y - graph.cursorY) / scale)
end

-- A step's box: a stripe in the state's color on the left, the state's picture and the
-- name on the first line, XP and reward icons on the second.
local function Node(i)
	local b = nodes[i]
	if b then return b end
	b = CreateFrame("Button", nil, graphChild)
	b:SetSize(NODE_W, NODE_H)
	b.edge = b:CreateTexture(nil, "BORDER")
	b.edge:SetAllPoints()
	b.body = b:CreateTexture(nil, "ARTWORK")
	b.stripe = b:CreateTexture(nil, "OVERLAY")
	b.stripe:SetPoint("TOPLEFT")
	b.stripe:SetPoint("BOTTOMLEFT")
	b.stripe:SetWidth(4)
	b.hover = b:CreateTexture(nil, "HIGHLIGHT")
	b.hover:SetAllPoints()
	b.hover:SetColorTexture(1, 1, 1, 0.08)
	b.mark = Mark(b, 16)
	b.mark:SetPoint("TOPLEFT", 9, -6)
	b.name = Text(b, "GameFontHighlightSmall", TEXT)
	b.name:SetPoint("TOPLEFT", 30, -8)
	b.name:SetWidth(NODE_W - 36)
	-- a skull in the top right corner, for a step with something to kill
	b.skull = b:CreateTexture(nil, "OVERLAY")
	b.skull:SetSize(14, 14)
	b.skull:SetPoint("TOPRIGHT", -5, -5)
	b.skull:SetTexture(SKULL)
	b.name:SetWordWrap(false)
	b.xp = Text(b, "GameFontHighlightSmall", VIOLET)
	b.xp:SetPoint("BOTTOMLEFT", 10, 8)
	b.icons = {}
	b:SetScript("OnClick", function(self) PickStep(self.step.quest) end)
	b:SetScript("OnEnter", function(self) ns.api.TextTooltip(self, self.step.name, self.tip) end)
	b:SetScript("OnLeave", function() ns.api.HideTooltip() end)
	nodes[i] = b
	return b
end

-- One straight piece of a line, from the pool.
local function Seg(n, x, y, width, height, lit)
	local t = segs[n]
	if not t then
		t = graphChild:CreateTexture(nil, "BACKGROUND")
		segs[n] = t
	end
	local c = lit and GREEN or FAINT
	t:SetColorTexture(c[1], c[2], c[3], lit and 0.9 or 0.8)
	t:SetDrawLayer("BACKGROUND", lit and 1 or 0) -- lit lines on top where lines share a stretch
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", x, -y)
	t:SetSize(width, height)
	t:Show()
end

-- Scrolling ------------------------------------------------------------------------

local WHEEL_STEP = 70 -- how far one notch of the wheel moves a list

-- A scrolling area with a thin bar of its own in the window's colors: a dark track and a
-- gold thumb just right of the area. The bar hides when everything fits. The wheel
-- scrolls; the thumb can be dragged, and a click on the track jumps there.
local function SlimScroll(name, parent)
	local s = CreateFrame("ScrollFrame", name, parent)
	local bar = CreateFrame("Button", nil, parent)
	s.bar = bar
	bar:SetWidth(8)
	bar:SetPoint("TOPLEFT", s, "TOPRIGHT", 8, 0)
	bar:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", 8, 0)
	bar.track = Fill(bar, "BACKGROUND", LINE, 0.45)
	bar.track:SetPoint("TOP")
	bar.track:SetPoint("BOTTOM")
	bar.track:SetWidth(2)
	local thumb = CreateFrame("Button", nil, bar)
	s.thumb = thumb
	thumb:SetWidth(8)
	thumb.fill = Fill(thumb, "ARTWORK", GOLD_DIM, 1)
	thumb.fill:SetPoint("TOP")
	thumb.fill:SetPoint("BOTTOM")
	thumb.fill:SetWidth(4)
	thumb.scrollThumb = true

	local function range() return math.max(0, s:GetVerticalScrollRange() or 0) end
	local function view() return s:GetHeight() or 0 end

	-- Moves the thumb to match where the area is scrolled to.
	function s:Sync()
		local max, height = range(), view()
		local needed = max > 0.5 and height > 0
		bar:SetShown(needed)
		if not needed then return end
		local size = math.max(24, height * height / (height + max))
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", 0, -(height - size) * math.min(1, (self:GetVerticalScroll() or 0) / max))
	end

	function s:ScrollTo(offset)
		self:SetVerticalScroll(math.max(0, math.min(range(), offset)))
		self:Sync()
	end

	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo((self:GetVerticalScroll() or 0) - delta * WHEEL_STEP) end)
	-- the content grew or shrank: stay inside it
	s:SetScript("OnScrollRangeChanged", function(self) self:ScrollTo(self:GetVerticalScroll() or 0) end)
	s:SetScript("OnVerticalScroll", function(self) self:Sync() end)
	s:SetScript("OnShow", function(self) self:Sync() end)

	local function color(c) thumb.fill:SetColorTexture(c[1], c[2], c[3], 1) end
	thumb:SetScript("OnEnter", function() color(GOLD) end)
	thumb:SetScript("OnLeave", function(self) if not self.dragging then color(GOLD_DIM) end end)
	thumb:SetScript("OnMouseDown", function(self)
		if not GetCursorPosition then return end
		self.dragging = true
		local _, y = GetCursorPosition()
		self.fromY, self.fromScroll = y, s:GetVerticalScroll() or 0
		self:SetScript("OnUpdate", function(me)
			local _, now = GetCursorPosition()
			local height = view()
			local travel = height - (me:GetHeight() or 24)
			if travel <= 0 then return end
			s:ScrollTo(me.fromScroll + (me.fromY - now) / (me:GetEffectiveScale() or 1) * range() / travel)
		end)
	end)
	local function release(self)
		self.dragging = nil
		self:SetScript("OnUpdate", nil)
		color(GOLD_DIM)
	end
	thumb:SetScript("OnMouseUp", release)
	thumb:SetScript("OnHide", release)
	-- a click on the track: a page up or down, toward the click
	bar:SetScript("OnMouseDown", function(self)
		if not GetCursorPosition then return end
		local _, y = GetCursorPosition()
		local top = thumb:GetTop()
		if not top then return end
		local up = y / (self:GetEffectiveScale() or 1) > top
		s:ScrollTo((s:GetVerticalScroll() or 0) + (up and -1 or 1) * view() * 0.9)
	end)
	bar:Hide()
	return s
end

-- The creature model in the side panel ------------------------------------------------

local MODEL_ZOOM, MODEL_FACING = 1.7, 0.35 -- how a creature first shows: far enough for a tall one to fit
local MODEL_NEAR, MODEL_FAR = 0.3, 4 -- how close and how far the wheel can take it

-- Puts the camera back and shows the creature. A model frame only takes a creature while
-- it is on screen, so this is called once the box shows, and again a moment later: the
-- game may still be loading the creature the first time it is asked for.
local function ShowCreature(model, id)
	model.creature = id
	model.zoom, model.facing, model.panX, model.panY = MODEL_ZOOM, MODEL_FACING, 0, 0
	local function apply()
		if model.creature ~= id then return end
		-- a client that cannot show this creature leaves the box with the picture alone
		pcall(function()
			model:ClearModel()
			model:SetCreature(id)
			model:SetPortraitZoom(0)
			model:SetCamDistanceScale(model.zoom)
			model:SetFacing(model.facing)
			model:SetPosition(0, model.panX, model.panY)
		end)
	end
	apply()
	if C_Timer and C_Timer.After then C_Timer.After(0.1, apply) end
end

-- The wheel zooms. The left button turns the creature, the right button moves it.
local function WheelModel(self, delta)
	self.zoom = math.max(MODEL_NEAR, math.min(MODEL_FAR, (self.zoom or MODEL_ZOOM) - delta * 0.15))
	pcall(self.SetCamDistanceScale, self, self.zoom)
end

local function DragModel(self)
	local x, y = GetCursorPosition()
	local scale = self:GetEffectiveScale() or 1
	local dx, dy = (x - self.cursorX) / scale, (y - self.cursorY) / scale
	self.cursorX, self.cursorY = x, y
	if self.dragging == "RightButton" then
		self.panX, self.panY = (self.panX or 0) + dx * 0.01, (self.panY or 0) + dy * 0.01
		pcall(self.SetPosition, self, 0, self.panX, self.panY)
	else
		self.facing = (self.facing or MODEL_FACING) + dx * 0.02
		pcall(self.SetFacing, self, self.facing)
	end
end

local function MakeModelMovable(model)
	model:EnableMouse(true) -- so a drag on it does not drag the window
	model:EnableMouseWheel(true)
	model:SetScript("OnMouseWheel", WheelModel)
	model:SetScript("OnMouseDown", function(self, button)
		if not GetCursorPosition then return end
		self.dragging = button
		self.cursorX, self.cursorY = GetCursorPosition()
		self:SetScript("OnUpdate", DragModel)
	end)
	model:SetScript("OnMouseUp", function(self) self.dragging = nil self:SetScript("OnUpdate", nil) end)
	model:SetScript("OnHide", function(self) self.dragging = nil self:SetScript("OnUpdate", nil) end)
end

-- Creatures the picked chain has you kill are shown once, unseen, when the chain is first
-- opened: the game then has them ready when their step is clicked.
local preloader, preloaded, queue = nil, {}, {}
local function PreloadNext()
	local id = table.remove(queue, 1)
	if not id then return end
	pcall(function()
		preloader:ClearModel()
		preloader:SetCreature(id)
	end)
	if #queue > 0 and C_Timer and C_Timer.After then C_Timer.After(0.05, PreloadNext) end
end

local function Preload(d)
	if preloaded[d.id] or not frame then return end
	preloaded[d.id] = true
	local seen, waiting = {}, #queue > 0
	for _, step in ipairs(d.steps) do
		for _, part in ipairs(step.parts or {}) do
			if part.kind == "kill" and not seen[part.id] then
				seen[part.id] = true
				queue[#queue + 1] = part.id
			end
		end
	end
	if #queue == 0 then return end
	if not preloader then
		-- one pixel, see-through, in a corner of the window: shown, so it loads
		preloader = CreateFrame("PlayerModel", nil, frame)
		preloader:SetSize(1, 1)
		preloader:SetPoint("BOTTOMLEFT", 2, 2)
		preloader:SetAlpha(0)
		preloader.preloader = true
	end
	if not waiting then PreloadNext() end
end

-- A web address to copy: the game cannot open it. A click selects it all, Ctrl+C copies it,
-- and typing does not change it. Set box.url, then box:SetText(box.url).
local function LinkBox(parent, name, width)
	local box = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnTextChanged", function(self, byUser)
		if byUser and self.url then
			self:SetText(self.url)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEnter", function(self) ns.api.TextTooltip(self, "Wowhead", { "Click the address, then Ctrl+C to copy." }) end)
	box:SetScript("OnLeave", ns.api.HideTooltip)
	return box
end

-- Building ------------------------------------------------------------------------

-- Scales the whole window to its share of the screen, whatever the screen and UI scale.
local function Fit()
	local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
	if type(screenWidth) ~= "number" or screenWidth <= 0 or type(screenHeight) ~= "number" or screenHeight <= 0 then return end
	local share = (tonumber(ns.db.size) or DEFAULT_SIZE) / 100
	frame:SetScale(share * math.min(screenWidth / WIDTH, screenHeight / HEIGHT))
end

-- After "/gr size N".
function Window.Resize()
	if frame then Fit() end
end

-- The side panel on the right. Split from Build: a function can only reach 60 outer locals.
local function BuildSide()
	-- Right: the side panel, with two tabs.
	side = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	side:SetPoint("TOPLEFT", detail, "TOPRIGHT", PAD, 0)
	side:SetPoint("BOTTOMLEFT", detail, "BOTTOMRIGHT", PAD, 0)
	side:SetWidth(SIDE_WIDTH)
	Panel(side, PANEL, 0.7)
	side.title = Heading(side, 19, GOLD)
	side.title:SetPoint("TOPLEFT", 12, -13)
	side.title:SetText("Details")
	side.rule = Fill(side, "ARTWORK", LINE, 1)
	side.rule:SetPoint("TOPLEFT", 8, -(TAB_HEIGHT + 12))
	side.rule:SetPoint("TOPRIGHT", -8, -(TAB_HEIGHT + 12))
	side.rule:SetHeight(1)
	side.close = CreateFrame("Button", nil, side, "UIPanelCloseButton")
	side.close:SetSize(28, 28)
	side.close:SetPoint("TOPRIGHT", -3, -6)
	side.close.closeSide = true
	side.close:SetScript("OnClick", CloseSide)
	-- The step you clicked. Filled by DrawInfo.
	-- It scrolls: a step with a model, many parts and long words is taller than the panel.
	local infoScroll = SlimScroll("GetReadyInfoScroll", side)
	infoScroll:SetPoint("TOPLEFT", 12, -(TAB_HEIGHT + 24))
	infoScroll:SetPoint("BOTTOMRIGHT", -28, 8)
	info = CreateFrame("Frame", nil, infoScroll)
	info:SetSize(LOOT_WIDTH, 10)
	infoScroll:SetScrollChild(info)
	info.scroll = infoScroll
	info.kicker = Text(info, "GameFontHighlightSmall", MUTED)
	info.name = Heading(info, 19, GOLD) -- same look as the "Wowhead" heading below
	info.name:SetWidth(LOOT_WIDTH)
	info.body = Text(info, "GameFontHighlight", TEXT)
	info.body:SetWidth(LOOT_WIDTH)
	info.body:SetSpacing(4)
	info.rows = {}
	for i = 1, INFO_ROWS do
		local row = CreateFrame("Frame", nil, info)
		row:SetSize(LOOT_WIDTH, FACT_ROW)
		row.label = Text(row, "GameFontHighlightSmall", MUTED)
		row.label:SetPoint("TOPLEFT", 0, -1)
		row.text = Text(row, "GameFontHighlightSmall", TEXT)
		row.text:SetPoint("TOPLEFT", FACT_LABEL, -1)
		row.text:SetWidth(LOOT_WIDTH - FACT_LABEL)
		info.rows[i] = row
	end
	info.rewards = CreateFrame("Frame", nil, info)
	info.rewards:SetSize(LOOT_WIDTH, ICON)
	info.rewards.label = Text(info.rewards, "GameFontHighlightSmall", MUTED)
	info.rewards.label:SetPoint("TOPLEFT", 0, 0)
	info.rewards.label:SetText("Rewards")
	info.rewards.icons = {}
	info.rewards.more = Text(info.rewards, "GameFontHighlightSmall", MUTED)
	-- A creature the step has you kill: its 3D model, on plain black.
	info.modelBox = CreateFrame("Frame", nil, info, "BackdropTemplate")
	info.modelBox:SetSize(LOOT_WIDTH, MODEL_HEIGHT)
	Panel(info.modelBox, BLACK, 1, GOLD_DIM)
	info.model = CreateFrame("PlayerModel", nil, info.modelBox)
	info.model:SetPoint("TOPLEFT", 1, -1)
	info.model:SetPoint("BOTTOMRIGHT", -1, 20)
	MakeModelMovable(info.model)
	info.modelName = Text(info.modelBox, "GameFontNormalSmall", GOLD)
	info.modelName:SetPoint("BOTTOM", 0, 5)
	info.modelName:SetJustifyH("CENTER")
	-- what the quest asks for, a line each; a click on a creature shows its model
	info.parts = {}
	for i = 1, INFO_PARTS do
		local b = CreateFrame("Button", nil, info)
		b:SetSize(LOOT_WIDTH, 20)
		b.hover = b:CreateTexture(nil, "HIGHLIGHT")
		b.hover:SetAllPoints()
		b.hover:SetColorTexture(1, 1, 1, 0.07)
		b.mark = Mark(b, 14)
		b.mark:SetPoint("LEFT", 2, 0)
		b.name = Text(b, "GameFontHighlightSmall", TEXT)
		b.name:SetPoint("LEFT", 22, 0)
		b.name:SetWidth(LOOT_WIDTH - 26)
		b.name:SetWordWrap(false)
		b.partLink = true
		b:SetScript("OnClick", function(self) PickPart(self.quest, self.at) end)
		info.parts[i] = b
	end

	-- who starts the quest and who takes it: a click on a line with a known place shows it on the map
	info.ways = {}
	for i = 1, 2 do
		local b = CreateFrame("Button", nil, info)
		b:SetSize(LOOT_WIDTH, 20)
		b.hover = b:CreateTexture(nil, "HIGHLIGHT")
		b.hover:SetAllPoints()
		b.hover:SetColorTexture(1, 1, 1, 0.07)
		b.name = Text(b, "GameFontHighlight", TEXT)
		b.name:SetPoint("TOPLEFT", 0, -2)
		b.name:SetWidth(LOOT_WIDTH)
		b.wayLink = i
		b:SetScript("OnClick", function(self) Pin(self.target) end)
		b:SetScript("OnEnter", function(self)
			if self.target then ns.api.TextTooltip(self, "Show on map", {}, "ANCHOR_CURSOR") end
		end)
		b:SetScript("OnLeave", ns.api.HideTooltip)
		info.ways[i] = b
	end

	-- the steps right before and right after: a click shows that step
	info.beforeLabel = Text(info, "GameFontHighlightSmall", MUTED)
	info.beforeLabel:SetText("After")
	info.afterLabel = Text(info, "GameFontHighlightSmall", MUTED)
	info.afterLabel:SetText("Leads to")
	info.links = {}
	for i = 1, INFO_LINKS do
		local b = CreateFrame("Button", nil, info)
		b:SetSize(LOOT_WIDTH, 20)
		b.hover = b:CreateTexture(nil, "HIGHLIGHT")
		b.hover:SetAllPoints()
		b.hover:SetColorTexture(1, 1, 1, 0.07)
		b.mark = Mark(b, 16)
		b.mark:SetPoint("LEFT", 2, 0)
		b.name = Text(b, "GameFontHighlightSmall", TEXT)
		b.name:SetPoint("LEFT", 24, 0)
		b.name:SetWidth(LOOT_WIDTH - 28)
		b.name:SetWordWrap(false)
		b.stepLink = true
		b:SetScript("OnClick", function(self) GoStep(self.quest) end)
		info.links[i] = b
	end
	-- for what the game cannot see, or a step the player does not want to do
	info.markStep = GoldButton(info, "", 150)
	info.markStep.markStep = true
	info.markStep:SetScript("OnClick", function(self)
		ns.MarkStep(self.quest, self.to)
		Window.Refresh()
	end)
	info.pin = GoldButton(info, "Show on map", 126)
	info.pin.pin = true
	info.pin:SetScript("OnClick", function(self) Pin(self.target) end)
	-- The quest's page on the web: the game cannot open it, so the address is there to copy.
	info.linkLabel = Text(info, "GameFontHighlightSmall", MUTED)
	info.linkLabel:SetText("Wowhead")
	info.link = LinkBox(info, "GetReadyLink", LOOT_WIDTH - 8)
	info.linkHint = Text(info, "GameFontHighlightSmall", FAINT)
	info.linkHint:SetText("Click the address, then Ctrl+C to copy.")

	-- "Rewards and loot" pop-up, opened from the banner: what the chain's quests give, then
	-- what may drop on the way. It hangs under its button, over the steps.
	loot = CreateFrame("Frame", "GetReadyLoot", frame, "BackdropTemplate")
	loot:SetFrameStrata("DIALOG")
	loot:EnableMouse(true)
	loot:SetSize(LOOT_WIDTH + 48, LOOT_HEIGHT)
	Panel(loot, PANEL, 0.98, GOLD_DIM)
	loot.heading = Heading(loot, 19, GOLD)
	loot.heading:SetPoint("TOPLEFT", 14, -13)
	loot.heading:SetText("Rewards and loot")
	loot.close = CreateFrame("Button", nil, loot, "UIPanelCloseButton")
	loot.close:SetSize(28, 28)
	loot.close:SetPoint("TOPRIGHT", -3, -6)
	loot.close.closeLoot = true
	loot.close:SetScript("OnClick", ToggleLoot)
	loot.rule = Fill(loot, "ARTWORK", LINE, 1)
	loot.rule:SetPoint("TOPLEFT", 8, -(TAB_HEIGHT + 12))
	loot.rule:SetPoint("TOPRIGHT", -8, -(TAB_HEIGHT + 12))
	loot.rule:SetHeight(1)
	loot:Hide()
	local lootScroll = SlimScroll("GetReadyLootScroll", loot)
	lootScroll:SetPoint("TOPLEFT", 14, -(TAB_HEIGHT + 22))
	lootScroll:SetPoint("BOTTOMRIGHT", -28, 10)
	lootChild = CreateFrame("Frame", nil, lootScroll)
	lootChild:SetSize(LOOT_WIDTH, 10)
	lootScroll:SetScrollChild(lootChild)
	lootHeads, lootIcons = {}, {}
	-- first section: what the chain's quests give; second: what may drop on the way
	loot.rewardsTitle = Heading(lootChild, 19, GOLD)
	loot.rewardsTitle:SetText("Quest rewards")
	loot.rewardsSub = Text(lootChild, "GameFontHighlightSmall", MUTED)
	loot.rewardsSub:SetWidth(LOOT_WIDTH)
	loot.rewardIcons = {}
	loot.title = Heading(lootChild, 19, GOLD)
	loot.title:SetText("Possible loot drops")
	loot.sub = Text(lootChild, "GameFontHighlightSmall", MUTED)
	loot.sub:SetWidth(LOOT_WIDTH)
end

-- The banner at the top of the middle.
local function BuildBanner()
	-- Banner: a strip of the place's loading screen. On it, top down: what kind of chain it
	-- is, its name, and its numbers on one line; the progress bar runs along the bottom.
	-- A chain without a picture gets the same banner on plain black.
	local banner = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	detail.banner = banner
	banner:SetPoint("TOPLEFT", 0, 0)
	banner:SetSize(WIDE_WIDTH, BANNER_HEIGHT)
	Panel(banner, BLACK, 1, GOLD_DIM)
	banner.art = banner:CreateTexture(nil, "BORDER")
	banner.art:SetPoint("TOPLEFT", 1, -1)
	banner.art:SetPoint("BOTTOMRIGHT", -1, 1)
	-- The screens are 4:3 pictures; show the full width and a band from a little above the middle.
	local band = (BANNER_HEIGHT / WIDE_WIDTH) / 0.75
	banner.art:SetTexCoord(0, 1, 0.45 - band / 2, 0.45 + band / 2)
	-- Dark from the bottom up, so the words read on any picture.
	banner.shade = Fill(banner, "ARTWORK", BLACK, 0.6)
	banner.shade:SetPoint("BOTTOMLEFT", 1, 1)
	banner.shade:SetPoint("BOTTOMRIGHT", -1, 1)
	banner.shade:SetHeight(BANNER_HEIGHT - 2)
	if CreateColor and banner.shade.SetGradient then
		banner.shade:SetColorTexture(1, 1, 1, 1)
		local ok = pcall(banner.shade.SetGradient, banner.shade, "VERTICAL",
			CreateColor(BLACK[1], BLACK[2], BLACK[3], 0.95), CreateColor(BLACK[1], BLACK[2], BLACK[3], 0.25))
		if not ok then banner.shade:SetColorTexture(BLACK[1], BLACK[2], BLACK[3], 0.6) end
	end

	-- Left, top down: kind, name, note. Bottom up: the numbers, then the facts that need words.
	detail.tag = Text(banner, "GameFontNormalSmall", GOLD_SOFT)
	detail.tag:SetPoint("TOPLEFT", 16, -14)
	detail.title = Heading(banner, 36, GOLD)
	detail.title:SetPoint("TOPLEFT", 14, -32)
	detail.title:SetWordWrap(false)
	-- under the name: what the chain's quests give, as icons
	detail.headRewards = CreateFrame("Frame", nil, banner)
	detail.headRewards:SetPoint("TOPLEFT", 16, -76)
	detail.headRewards:SetSize(10, HEAD_ICON)
	detail.headRewards.icons = {}
	detail.headRewards.more = Text(detail.headRewards, "GameFontHighlightSmall", MUTED)
	-- the chain's note stands on the first line, after its kind and level (see DrawDetail)
	detail.note = Text(banner, "GameFontHighlight", TEXT)
	detail.note:Hide()
	detail.note:SetWordWrap(false)
	-- one line each, stacked over the numbers; DrawDetail puts the ones in use in place
	detail.factLines = {}
	for i = 1, FACT_LINES do
		local line = Text(banner, "GameFontHighlightSmall", TEXT)
		line:SetWordWrap(false)
		detail.factLines[i] = line
	end
	-- A line cut short ("+2 more") shows the whole list when pointed at.
	detail.factHits = {}
	for i = 1, FACT_LINES do
		local hit = CreateFrame("Button", nil, banner)
		hit:SetAllPoints(detail.factLines[i])
		hit.factHit = i
		hit:SetScript("OnEnter", function(self)
			-- at the mouse: the line is wider than its text, so its edge is far from the words
			if self.full then ns.api.TextTooltip(self, self.title, self.full, "ANCHOR_CURSOR") end
		end)
		hit:SetScript("OnLeave", ns.api.HideTooltip)
		detail.factHits[i] = hit
	end
	detail.summary = Text(banner, "GameFontHighlightSmall", TEXT)
	detail.summary:SetPoint("BOTTOMLEFT", 16, 14)
	detail.summary:SetWordWrap(false)
	detail.bar = Bar(banner, WIDE_WIDTH - 2, 3)
	detail.bar:SetPoint("BOTTOMLEFT", 1, 1)

	-- Right, top down: mark as done, rewards and loot, the chain's page on Wowhead.
	-- "Mark as done" is for what the game cannot see, or a chain the player does not want to do.
	detail.markButton = GoldButton(banner, "", 150)
	detail.markButton:SetPoint("TOPRIGHT", -10, -10)
	detail.markButton:SetScript("OnClick", function(self)
		ns.Mark(self.chain, self.to)
		Window.Refresh()
	end)
	detail.lootButton = GoldButton(banner, "Rewards and loot", 150)
	detail.lootButton:SetPoint("TOPRIGHT", -10, -42)
	detail.lootButton.lootToggle = true
	detail.lootButton:SetScript("OnClick", ToggleLoot)
	detail.link = LinkBox(banner, "GetReadyChainLink", 226)
	detail.link:SetPoint("BOTTOMRIGHT", -12, 12)
	detail.linkLabel = Heading(banner, 16, GOLD)
	detail.linkLabel:SetPoint("BOTTOMLEFT", detail.link, "TOPLEFT", -4, 3)
	detail.linkLabel:SetText("Wowhead")
end

local function Build()
	frame = CreateFrame("Frame", "GetReadyFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	-- Same layer as the game's own windows, so the map can come in front of this one.
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true) -- a click on the window brings it back in front
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relative, x, y = self:GetPoint(1)
		if point then ns.db.point = { point, relative, x, y } end
	end)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
		edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	frame:SetBackdropColor(BLACK[1], BLACK[2], BLACK[3], 0.97)
	local saved = ns.db.point
	if type(saved) == "table" and saved[1] then
		frame:SetPoint(saved[1], UIParent, saved[2] or saved[1], saved[3] or 0, saved[4] or 0)
	else
		frame:SetPoint("CENTER")
	end
	tinsert(UISpecialFrames, "GetReadyFrame") -- Esc closes
	Fit()

	local title = Heading(frame, 28, GOLD)
	title:SetPoint("TOP", 0, -15)
	title:SetJustifyH("CENTER")
	title:SetText("Get Ready")

	local rule = Divider(frame, WIDTH - 80)
	rule:SetPoint("TOP", 0, -52)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- Options: the cog left of the close button
	local cog = CreateFrame("Button", nil, frame)
	cog:SetSize(22, 22)
	cog:SetPoint("RIGHT", close, "LEFT", -4, 0)
	cog.icon = cog:CreateTexture(nil, "ARTWORK")
	cog.icon:SetAllPoints()
	-- The world map's gear in gold. The file holds four pictures; the first is the plain one.
	cog.icon:SetTexture("Interface\\WorldMap\\Gear_64")
	cog.icon:SetTexCoord(0, 0.5, 0, 0.5)
	cog.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	cog.hover = cog:CreateTexture(nil, "HIGHLIGHT")
	cog.hover:SetAllPoints()
	cog.hover:SetTexture("Interface\\WorldMap\\Gear_64")
	cog.hover:SetTexCoord(0, 0.5, 0, 0.5)
	cog.hover:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	cog.hover:SetBlendMode("ADD")
	cog.options = true
	cog:SetScript("OnClick", function(self) ns.Options.Toggle(frame, self) end)
	frame.cog = cog
	cog:SetScript("OnEnter", function(self) ns.api.TextTooltip(self, "Options", {}) end)
	cog:SetScript("OnLeave", ns.api.HideTooltip)

	-- Left: chains
	local list = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	list:SetPoint("TOPLEFT", PAD, -TOP)
	list:SetPoint("BOTTOMLEFT", PAD, PAD)
	list:SetWidth(LIST_WIDTH + 22)
	Panel(list, PANEL, 0.7)

	-- Search: type to keep only the chains whose name has the text
	searchBox = CreateFrame("EditBox", "GetReadySearch", list, "SearchBoxTemplate")
	searchBox:SetPoint("TOPLEFT", 14, -6)
	searchBox:SetPoint("TOPRIGHT", -8, -6)
	searchBox:SetHeight(SEARCH_HEIGHT)
	searchBox:SetAutoFocus(false)
	searchBox:SetMaxLetters(40)
	searchBox:HookScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		if text ~= search then
			search = text
			Window.Refresh()
		end
	end)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

	local listScroll = SlimScroll("GetReadyListScroll", list)
	listScroll:SetPoint("TOPLEFT", 4, -(SEARCH_HEIGHT + 12))
	listScroll:SetPoint("BOTTOMRIGHT", -26, 4)
	listChild = CreateFrame("Frame", nil, listScroll)
	listChild:SetSize(LIST_WIDTH, 10)
	listScroll:SetScrollChild(listChild)

	-- Middle: the picked chain
	detail = CreateFrame("Frame", nil, frame)
	detail:SetPoint("TOPLEFT", list, "TOPRIGHT", PAD, 0)
	detail:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	BuildSide()

	BuildBanner()

	-- "Next" box: the one thing to do now. Its stripe has the color of the step's state.
	detail.next = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	detail.next:SetWidth(DETAIL_WIDTH)
	Panel(detail.next, PANEL_HI, 0.95, GOLD_DIM)
	detail.next.stripe = detail.next:CreateTexture(nil, "ARTWORK")
	detail.next.stripe:SetPoint("TOPLEFT", 1, -1)
	detail.next.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	detail.next.stripe:SetWidth(4)
	detail.next.label = Heading(detail.next, 19, GOLD) -- "Next step", in the heading font
	detail.next.label:SetPoint("TOPLEFT", 18, -10)
	detail.next.name = Text(detail.next, "GameFontNormalLarge", GOLD)
	detail.next.name:SetPoint("TOPLEFT", 18, -36)
	detail.next.name:SetWidth(DETAIL_WIDTH - 170)
	detail.next.name:SetWordWrap(false)
	detail.next.hint = Text(detail.next, "GameFontHighlight", TEXT)
	detail.next.hint:SetPoint("TOPLEFT", 18, -64)
	detail.next.hint:SetWidth(DETAIL_WIDTH - 36)
	detail.next.hint:SetSpacing(4)
	detail.next.pin = GoldButton(detail.next, "Show on map", 126)
	detail.next.pin:SetPoint("TOPRIGHT", -10, -10)
	detail.next.pin:SetScript("OnClick", function(self) Pin(self.target) end)

	-- "Steps" and the graph or list button, on one line. The marks are the game's own
	-- quest pictures, so they need no legend.
	detail.stepsLabel = Heading(detail, 19, GOLD)
	detail.stepsLabel:SetText("Steps")
	detail.mode = GoldButton(detail, "", 112)
	detail.mode:SetScript("OnClick", function(self)
		ns.db.modes[self.chain] = self.to
		Window.Refresh()
	end)

	detail.graph = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	Panel(detail.graph, BLACK, 0.6)
	-- how to move a graph that does not fit: in its bottom right corner, over the boxes
	detail.modeHint = CreateFrame("Frame", nil, detail.graph)
	detail.modeHint:SetSize(160, 18)
	detail.modeHint:SetPoint("BOTTOMRIGHT", -8, 6)
	detail.modeHint:SetFrameLevel((detail.graph:GetFrameLevel() or 1) + 20)
	detail.modeHint.back = Fill(detail.modeHint, "BACKGROUND", BLACK, 0.8)
	detail.modeHint.back:SetAllPoints()
	detail.modeHint.label = Text(detail.modeHint, "GameFontHighlightSmall", MUTED)
	detail.modeHint.label:SetPoint("CENTER")
	detail.modeHint.label:SetText("Wheel or drag to move")
	graphScroll = CreateFrame("ScrollFrame", nil, detail.graph)
	graphScroll:SetPoint("TOPLEFT", GRAPH_PAD, -GRAPH_PAD)
	graphScroll:SetPoint("BOTTOMRIGHT", -GRAPH_PAD, GRAPH_PAD)
	graphChild = CreateFrame("Frame", nil, graphScroll)
	graphChild:SetSize(10, 10)
	graphScroll:SetScrollChild(graphChild)
	graphScroll:EnableMouseWheel(true)
	graphScroll:SetScript("OnMouseWheel", WheelGraph)
	graphScroll:EnableMouse(true)
	graphScroll:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" or not GetCursorPosition then return end
		graph.cursorX, graph.cursorY = GetCursorPosition()
		graph.fromX, graph.fromY = graph.x, graph.y
		self:SetScript("OnUpdate", DragGraph)
	end)
	graphScroll:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	graphScroll:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

	local stepScroll = SlimScroll("GetReadyStepScroll", detail)
	detail.stepScroll = stepScroll
	stepChild = CreateFrame("Frame", nil, stepScroll)
	stepChild:SetSize(STEP_WIDTH, 10)
	stepScroll:SetScrollChild(stepChild)

	selected = ns.db.selected
	frame:Hide()
end

-- Drawing -------------------------------------------------------------------------
-- All text comes from View.lua; this part only puts it on screen.

-- Height of a block of help lines. Long lines can wrap, so ask the game when it can tell.
local function TextHeight(fs, lines, lineHeight)
	local h = fs:GetStringHeight()
	if type(h) == "number" and h > 0 then return h end
	return lines * (lineHeight or 17)
end

local function DrawList(model)
	local y, heads, rows = 0, 0, 0
	for _, group in ipairs(model.groups) do
		heads = heads + 1
		local head = HeadRow(heads)
		head.group = group.kind
		head.label:SetText(group.label)
		head.count:SetText(group.done .. " / " .. group.total)
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT", 0, -y)
		head:Show()
		y = y + LIST_HEAD + 2

		if not group.closed then
			for _, chain in ipairs(group.chains) do
				rows = rows + 1
				local row = ChainRow(rows)
				local picked = chain.id == model.selected
				row.chain = chain
				-- "[30] Name", the level in the color of how it stands to the player's
				local level = chain.level and (Code(LEVEL_COLOR[chain.levelTone] or MUTED) .. "[" .. chain.level .. "]|r ") or ""
				row.name:SetText(level .. chain.name)
				Color(row.name, chain.done and GREEN_DIM or (picked and GOLD or TEXT))
				-- the infinity sign sits right after the name, so the name is only as wide as its text
				row.new:SetShown(chain.new == true)
				local room = LIST_WIDTH - 88 - (chain.new and 20 or 0)
				local wide = chain.new and row.name:GetStringWidth()
				row.name:SetWidth((type(wide) == "number" and wide > 0) and math.min(wide + 1, room) or room)
				-- done: the check says it; a chain marked by hand also says so
				row.check:SetShown(chain.done)
				row.count:SetText((chain.done and not chain.marked) and "" or chain.count)
				row.count:ClearAllPoints()
				row.count:SetPoint("TOPRIGHT", chain.done and -30 or -8, -9)
				Color(row.count, chain.done and GREEN_DIM or MUTED)
				row.bar:Set(chain.fraction)
				row.pick:SetShown(picked)
				row.edge:SetShown(picked)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -y)
				row:Show()
				y = y + LIST_ROW
			end
		end
		y = y + 8
	end
	for i = heads + 1, #headRows do headRows[i]:Hide() end
	for i = rows + 1, #chainRows do chainRows[i]:Hide() end
	-- a search that finds nothing says so
	if model.search and rows == 0 then
		if not noneText then
			noneText = Text(listChild, "GameFontHighlight", MUTED)
			noneText:SetPoint("TOPLEFT", 12, -10)
			noneText:SetText("Nothing found.")
		end
		noneText:Show()
	elseif noneText then
		noneText:Hide()
	end
	listChild:SetHeight(math.max(y, 10))
end

local function DrawNext(next)
	local box = detail.next
	local c = STATE_COLOR[next.mark or next.state] or GOLD
	box.stripe:SetColorTexture(c[1], c[2], c[3], 1)
	box.label:SetText(next.label)
	box.name:SetText(next.name or "")
	Color(box.name, next.state == "locked" and MUTED or (next.state == "done" and GREEN or (next.mark == "active" and SILVER or GOLD)))
	box.hint:SetText(PrettyLines(next.lines))
	box.pin.target = next.target
	box.pin:SetShown(next.target ~= nil)
	-- a box with only its label is short
	box.height = (next.name and 74 or 44) + (#next.lines > 0 and TextHeight(box.hint, #next.lines, 20) or 0)
	box:SetHeight(box.height)
end

--   first: "Reach level N", drawn before the quest steps, or nil
local function DrawSteps(steps, first)
	local y, used = 0, 0
	local list = steps
	if first and #steps > 0 then
		list = { first }
		for i, step in ipairs(steps) do list[i + 1] = step end
	end
	steps = list
	for i, step in ipairs(steps) do
		local row = StepRow(i)
		row:SetWidth(mid - 26)
		row.name:SetWidth(mid - 26 - 34 - STEP_RIGHT - 104 - 22)
		row.skull:SetShown(HasKill(step))
		row.skull:SetAlpha((step.state == "done" or step.state == "skipped") and 0.4 or 1)
		row.hint:SetWidth(mid - 26 - 34)
		local finished = step.state == "done" or step.state == "skipped"
		row.mark:Set(step.mark)
		-- the level after the name: red when the player is below it
		row.name:SetText(LevelTag(step) .. step.name)
		Color(row.name, STATE_TEXT[step.mark])
		row.xp:SetText(step.xp or "")
		row.xp:SetAlpha(finished and 0.5 or 1)
		-- under the name: what to do, then the reputation the quest gives
		local lines = {}
		for _, line in ipairs(step.hints) do
			-- what to kill, use and get has its own lines under the step
			local own = #(step.parts or {}) > 0 and (line:find("^Kill:") or line:find("^Use:") or line:find("^Get:"))
			if not own then lines[#lines + 1] = Pretty(line) end
		end
		if step.rep then lines[#lines + 1] = TEAL_CODE .. step.rep .. "|r" end
		row.hint:SetText(table.concat(lines, "\n"))
		row.hint:SetShown(#lines > 0)
		row.hint:SetAlpha(finished and 0.5 or 1)
		row.quest = step.quest
		row.pick:SetShown(step.picked == true)
		row.pickEdge:SetShown(step.picked == true)
		local left = ShowIcons(row.icons, row, step.rewards, STEP_ICONS, STEP_ICON - 2, function(b, n)
			b:SetPoint("TOPRIGHT", -28 - (STEP_ICONS - n) * STEP_ICON, -3)
		end)
		for n = 1, #row.icons do row.icons[n]:SetAlpha(finished and 0.45 or 1) end
		row.more:SetText(left > 0 and ("+" .. left) or "")
		local height = STEP_ROW + (#lines > 0 and (TextHeight(row.hint, #lines) + 8) or 2)
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:Show()
		y = y + height
		-- under the step: what it has you kill, use and get, a line each
		for at, part in ipairs(step.parts or {}) do
			used = used + 1
			local line = PartRow(used)
			line.quest, line.at = step.quest, at
			line.mark:Set(part.mark)
			line.name:SetText(PartText(part))
			-- a kill line has the skull between its mark and its words
			local kill = part.kind == "kill"
			line.skull:SetShown(kill)
			line.name:ClearAllPoints()
			line.name:SetPoint("LEFT", kill and 74 or 54, 0)
			line.name:SetWidth(mid - 26 - 60 - (kill and 20 or 0))
			Color(line.name, STATE_TEXT[part.mark] or TEXT)
			line:SetAlpha(finished and 0.55 or 1)
			line:SetWidth(mid - 26)
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", 0, -y)
			line:Show()
			y = y + PART_ROW
		end
		if #(step.parts or {}) > 0 then y = y + 4 end
	end
	for i = used + 1, #partRows do partRows[i]:Hide() end
	for i = #steps + 1, #stepRows do stepRows[i]:Hide() end
	stepChild:SetHeight(math.max(y, 10))
end

-- "Loot" tab: first every reward the chain's quests give, then what may drop on the way,
-- by the creature that drops it.
local function DrawLoot(d)
	local groups, rewards = d.loot, d.rewards
	local y = 0

	loot.rewardsTitle:ClearAllPoints()
	loot.rewardsTitle:SetPoint("TOPLEFT", 0, -y)
	y = y + 26
	-- a line only when there is nothing to show
	loot.rewardsSub:SetShown(#rewards == 0)
	if #rewards == 0 then
		loot.rewardsSub:SetText("This chain's quests give no items.")
		loot.rewardsSub:ClearAllPoints()
		loot.rewardsSub:SetPoint("TOPLEFT", 0, -y)
		y = y + 22
	end
	local top = y
	ShowIcons(loot.rewardIcons, lootChild, rewards, #rewards, ICON - 2, function() end)
	for n, id in ipairs(rewards) do
		local b = loot.rewardIcons[n]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", ((n - 1) % LOOT_PER_ROW) * ICON, -top - math.floor((n - 1) / LOOT_PER_ROW) * ICON)
		b:SetAlpha(d.got[id] and 0.4 or 1)
	end
	y = y + math.ceil(#rewards / LOOT_PER_ROW) * ICON + 18

	local count = 0
	for _, group in ipairs(groups) do count = count + #group.items end
	loot.title:ClearAllPoints()
	loot.title:SetPoint("TOPLEFT", 0, -y)
	y = y + 38 -- the heading, and room before the first name
	loot.sub:SetShown(count == 0)
	if count == 0 then
		loot.sub:SetText("No loot known for this chain.")
		loot.sub:ClearAllPoints()
		loot.sub:SetPoint("TOPLEFT", 0, -y)
		y = y + 22
	end

	local used = 0
	for i, group in ipairs(groups) do
		local head = lootHeads[i]
		if not head then
			head = Text(lootChild, "GameFontHighlightSmall", GOLD_SOFT)
			head:SetWidth(LOOT_WIDTH)
			head:SetWordWrap(false)
			lootHeads[i] = head
		end
		head:SetText(group.name)
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT", 0, -y)
		head:Show()
		y = y + 20
		for n, item in ipairs(group.items) do
			used = used + 1
			local b = lootIcons[used]
			if not b then
				b = IconButton(lootChild, ICON - 2)
				lootIcons[used] = b
			end
			b:SetItem(item)
			b.note = group.from
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", ((n - 1) % LOOT_PER_ROW) * ICON, -y - math.floor((n - 1) / LOOT_PER_ROW) * ICON)
			b:Show()
		end
		y = y + math.ceil(#group.items / LOOT_PER_ROW) * ICON + 12
	end
	for i = #groups + 1, #lootHeads do lootHeads[i]:Hide() end
	for i = used + 1, #lootIcons do lootIcons[i]:Hide() end
	lootChild:SetHeight(math.max(y, 10))
end

-- Top left corner of a step's box in the graph.
local function Cell(step)
	return (step.col - 1) * (NODE_W + NODE_GAP), (step.row - 1) * NODE_ROW
end

-- Columns and rows come from View.Graph; this only draws them.
--   viewHeight: how much of the graph fits on screen, top to bottom
local function DrawGraph(d, viewHeight)
	local g = d.graph
	-- "Reach level N" is drawn too: it goes after the quest steps, so their numbers stay
	-- as the lines know them, and gets a line to each step that waits for nothing else.
	local steps, edges = d.steps, g.edges
	if d.reach and g.reach then
		steps, edges = {}, {}
		for i, step in ipairs(d.steps) do steps[i] = step end
		steps[#steps + 1] = d.reach
		for i, edge in ipairs(g.edges) do edges[i] = edge end
		for _, to in ipairs(g.reach) do edges[#edges + 1] = { from = #steps, to = to, lit = g.reach.lit } end
	end
	for i, step in ipairs(steps) do
		local b = Node(i)
		local c = STATE_COLOR[step.mark]
		local x, y = Cell(step)
		local finished = step.state == "done" or step.state == "skipped"
		b.step = step
		b.tip = { step.status }
		for _, line in ipairs(step.hints) do b.tip[#b.tip + 1] = line end
		b.tip[#b.tip + 1] = step.rewardLine
		b.tip[#b.tip + 1] = step.gain
		b.tip[#b.tip + 1] = "Click for details"
		b.mark:Set(step.mark)
		local kills = HasKill(step)
		b.skull:SetShown(kills)
		b.skull:SetAlpha(finished and 0.4 or 1)
		b.name:SetWidth(NODE_W - 36 - (kills and 18 or 0))
		b.name:SetText(LevelTag(step) .. step.name)
		Color(b.name, STATE_TEXT[step.mark])
		-- second line: the level in red when the player is below it, then the XP
		b.xp:SetText(step.xp or "")
		b.xp:SetAlpha(finished and 0.5 or 1)
		ShowIcons(b.icons, b, step.rewards, NODE_ICONS, NODE_ICON - 2, function(icon, n)
			icon:SetPoint("BOTTOMRIGHT", -6 - (n - 1) * NODE_ICON, 5)
		end)
		for n = 1, #b.icons do b.icons[n]:SetAlpha(finished and 0.45 or 1) end
		b.stripe:SetColorTexture(c[1], c[2], c[3], 1)
		-- a goal has a gold edge, twice as thick; a step in your log is a shade lighter
		-- the step shown in the side panel has a bright edge
		local edge = step.picked and GOLD or (step.goal and GOLD_DIM or LINE)
		local fill = (step.picked or step.state == "active") and PANEL_HI or PANEL
		local inset = (step.picked or step.goal) and 2 or 1
		b.edge:SetColorTexture(edge[1], edge[2], edge[3], 1)
		b.body:SetColorTexture(fill[1], fill[2], fill[3], 1)
		b.body:ClearAllPoints()
		b.body:SetPoint("TOPLEFT", inset, -inset)
		b.body:SetPoint("BOTTOMRIGHT", -inset, inset)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", x, -y)
		b:Show()
	end
	for i = #steps + 1, #nodes do nodes[i]:Hide() end

	-- A line leaves the earlier step to the right, turns just before the later one, and goes in.
	local n = 0
	for _, edge in ipairs(edges) do
		local ax, ay = Cell(steps[edge.from])
		local bx, by = Cell(steps[edge.to])
		local y1, y2 = ay + NODE_H / 2, by + NODE_H / 2
		local turn = bx - NODE_GAP / 2
		n = n + 1
		Seg(n, ax + NODE_W, y1, turn - ax - NODE_W, 1, edge.lit)
		if y1 ~= y2 then
			n = n + 1
			Seg(n, turn, math.min(y1, y2), 1, math.abs(y2 - y1) + 1, edge.lit)
		end
		n = n + 1
		Seg(n, turn, y2, bx - turn, 1, edge.lit)
	end
	for i = n + 1, #segs do segs[i]:Hide() end

	local width = g.cols * NODE_W + (g.cols - 1) * NODE_GAP
	local height = (g.rows - 1) * NODE_ROW + NODE_H
	graphChild:SetSize(width, height)
	graph.maxX = math.max(0, width - (mid - GRAPH_PAD * 2))
	graph.maxY = math.max(0, height - viewHeight)
	if graph.shown == d.id then
		ScrollGraph(graph.x, graph.y) -- same graph as before: stay where the player was
	else
		graph.shown = d.id
		local x, y = 0, 0
		if g.focus then
			x, y = Cell(d.steps[g.focus]) -- another one: start at the next step
			-- keep the column before it in view too: for the first quests that is "Reach level N"
			x, y = x - (NODE_W + NODE_GAP) - NODE_W / 2, y - NODE_ROW * 2
		end
		ScrollGraph(x, y)
	end
end

-- "Details" tab of the side panel: the step the player clicked.
local function DrawInfo(d)
	local p = d.picked
	local y = 0
	local function place(region, height, gap)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", 0, -y)
		region:Show()
		y = y + height + (gap or 8)
	end

	if not p then
		-- nothing picked: say how to pick
		info.kicker:Hide()
		info.name:Hide()
		for _, row in ipairs(info.rows) do row:Hide() end
		info.rewards:Hide()
		info.pin:Hide()
		info.markStep:Hide()
		info.modelBox:Hide()
		for _, b in ipairs(info.parts) do b:Hide() end
		for _, b in ipairs(info.ways) do b:Hide() end
		info.beforeLabel:Hide()
		info.afterLabel:Hide()
		for _, b in ipairs(info.links) do b:Hide() end
		info.linkLabel:Hide()
		info.link:Hide()
		info.linkHint:Hide()
		info.link.url = nil
		info.body:SetText(MUTED_CODE .. "Click a step to see its details here.|r")
		place(info.body, 20)
		info:SetHeight(y)
		info.showing = nil
		return
	end

	-- its state
	info.kicker:SetText(p.status or "")
	Color(info.kicker, STATE_COLOR[p.mark] or MUTED)
	place(info.kicker, 16, 8)

	info.name:SetText(p.name)
	place(info.name, TextHeight(info.name, 1, 24), 12)

	-- right under the name: its page on Wowhead, small
	info.link.url = p.link
	info.linkLabel:ClearAllPoints()
	info.linkLabel:SetPoint("TOPLEFT", 0, -(y + 5))
	info.linkLabel:Show()
	info.link:ClearAllPoints()
	info.link:SetPoint("TOPLEFT", 66, -y)
	info.link:SetWidth(LOOT_WIDTH - 70)
	info.link:SetText(p.link)
	info.link:SetCursorPosition(0)
	info.link:Show()
	info.linkHint:Hide()
	y = y + 22 + 12

	-- the creature to kill, as the game draws it
	if p.model then
		info.modelName:SetText(p.model.name)
		place(info.modelBox, MODEL_HEIGHT, 10)
		-- after the box shows: a hidden model takes no creature
		if info.model.creature ~= p.model.id then ShowCreature(info.model, p.model.id) end
	else
		info.modelBox:Hide()
		info.model.creature = nil
	end

	-- what the quest asks for, a line each
	for i, b in ipairs(info.parts) do
		local part = p.parts[i]
		b:SetShown(part ~= nil)
		if part then
			b.quest, b.at = p.quest, i
			b.mark:Set(part.mark)
			b.name:SetText(PartText(part))
			Color(b.name, (p.model and p.model.at == i) and GOLD or (STATE_TEXT[part.mark] or TEXT))
			place(b, 20, 0)
		end
	end
	if #p.parts > 0 then y = y + 10 end

	-- words: what the quest asks, how far you are with it, then who and where
	local parts, count = {}, 0
	if p.text then
		parts[#parts + 1] = p.text
		count = count + 2
	end
	if #p.objectives > 0 then
		local list = {}
		for n, o in ipairs(p.objectives) do
			list[n] = (o.done and Code(GREEN) or Code(GOLD)) .. o.text .. "|r"
		end
		parts[#parts + 1] = table.concat(list, "\n")
		count = count + #list
	end
	if #p.lines > 0 then
		parts[#parts + 1] = PrettyLines(p.lines)
		count = count + #p.lines
	end
	local body = table.concat(parts, "\n\n")
	info.body:SetText(body)
	if body ~= "" then
		place(info.body, TextHeight(info.body, count + #parts - 1, 20), 12)
	else
		info.body:Hide()
	end

	-- who starts it and who takes it; blue and clickable when the place is known
	for i, b in ipairs(info.ways) do
		local way = p.ways[i]
		b:SetShown(way ~= nil)
		if way then
			b.target = way.target
			b.name:SetText(MUTED_CODE .. way.label .. ":|r " .. (way.target and Code(BLUE) or "") .. way.text .. (way.target and "|r" or ""))
			local height = math.max(20, TextHeight(b.name, 1, 18) + 4)
			b:SetHeight(height)
			place(b, height, 0)
		end
	end
	if #p.ways > 0 then y = y + 10 end

	-- label and text lines: the step's level, XP and reputation
	local rows = p.rows
	for i, row in ipairs(info.rows) do
		local entry = rows[i]
		row:SetShown(entry ~= nil)
		if entry then
			row.label:SetText(entry.label)
			row.text:SetText(entry.text)
			Color(row.text, TONE[entry.tone] or TEXT)
			local height = math.max(FACT_ROW, TextHeight(row.text, 1, FACT_ROW) + 4)
			row:SetHeight(height)
			place(row, height, 0)
		end
	end
	if #rows > 0 then y = y + 10 end

	-- what the step gives (the chain's rewards are on the Loot tab)
	local rewards = p.rewards
	info.rewards:SetShown(#rewards > 0)
	if #rewards > 0 then
		local icons = info.rewards.icons
		local left = ShowIcons(icons, info.rewards, rewards, LOOT_PER_ROW * REWARD_ROWS, ICON - 2, function(b, n)
			b:SetPoint("TOPLEFT", ((n - 1) % LOOT_PER_ROW) * ICON, -20 - math.floor((n - 1) / LOOT_PER_ROW) * ICON)
		end)
		local shown = #rewards - left
		for n = 1, shown do icons[n]:SetAlpha(1) end
		local height = 20 + math.ceil(shown / LOOT_PER_ROW) * ICON
		info.rewards.more:SetText(left > 0 and ("+" .. left .. " more") or "")
		info.rewards.more:ClearAllPoints()
		info.rewards.more:SetPoint("TOPLEFT", 0, -height)
		if left > 0 then height = height + 16 end
		info.rewards:SetHeight(height)
		place(info.rewards, height, 12)
	end

	-- where to go, and where to read more
	-- the steps before and after, each a line to click
	local used = 0
	for _, part in ipairs({ { info.beforeLabel, p.before }, { info.afterLabel, p.after } }) do
		local label, list = part[1], part[2]
		label:SetShown(#list > 0)
		if #list > 0 then
			place(label, 14, 2)
			for _, other in ipairs(list) do
				local b = info.links[used + 1]
				if not b then break end
				used = used + 1
				b.quest = other.quest
				b.mark:Set(other.mark)
				b.name:SetText(other.name)
				Color(b.name, STATE_TEXT[other.mark] or TEXT)
				place(b, 20, 0)
			end
			y = y + 10
		end
	end
	for i = used + 1, #info.links do info.links[i]:Hide() end

	-- buttons: where to go, and the mark by hand
	info.pin.target = p.target
	local buttons = y
	if p.target then place(info.pin, 26, 14) else info.pin:Hide() end
	info.markStep:SetShown(p.canMark)
	if p.canMark then
		info.markStep.quest, info.markStep.to = p.quest, not p.marked
		info.markStep.label:SetText(p.marked and "Not done after all" or "Mark as done")
		info.markStep:ClearAllPoints()
		-- beside "Show on map" when that is there, else in its place
		info.markStep:SetPoint("TOPLEFT", p.target and 136 or 0, -buttons)
		if not p.target then y = y + 26 + 14 end
	end
	info:SetHeight(math.max(y, 10))
	-- another step starts at its top
	if info.showing ~= p.quest then
		info.showing = p.quest
		info.scroll:SetVerticalScroll(0)
	end
end

-- The side panel with the clicked step, and the "Rewards and loot" pop-up.
local function DrawSide(d)
	side:SetShown(sideOpen)
	DrawInfo(d)
	loot:SetShown(lootOpen)
	loot:ClearAllPoints()
	loot:SetPoint("TOPRIGHT", detail.lootButton, "BOTTOMRIGHT", 0, -6)
	DrawLoot(d)
end

-- Gives the middle the room the side panel leaves it, and sizes what depends on that.
local function Layout()
	sideOpen = pickedStep ~= nil
	mid = sideOpen and DETAIL_WIDTH or WIDE_WIDTH
	detail:SetPoint("BOTTOMRIGHT", sideOpen and -(PAD * 2 + SIDE_WIDTH) or -PAD, PAD)
	local banner = detail.banner
	banner:SetWidth(mid)
	-- The screens are 4:3 pictures; show the full width and a band from a little above the middle.
	local band = (BANNER_HEIGHT / mid) / 0.75
	banner.art:SetTexCoord(0, 1, 0.45 - band / 2, 0.45 + band / 2)
	local text = mid - 32 - 250 -- left of the buttons and the address
	detail.title:SetWidth(text)
	detail.note:SetWidth(text)
	for _, line in ipairs(detail.factLines) do line:SetWidth(text) end
	detail.summary:SetWidth(text)
	detail.bar.width = mid - 2
	detail.bar:SetWidth(mid - 2)
	detail.next:SetWidth(mid)
	detail.next.name:SetWidth(mid - 170)
	detail.next.hint:SetWidth(mid - 36)
	stepChild:SetWidth(mid - 26)
end

local function DrawDetail(d)
	Layout()
	-- first line: what kind of chain, its level, and what it is for
	detail.tag:SetText((d.tag or "") .. (d.note and ("   " .. Code(TEXT) .. d.note .. "|r") or ""))
	detail.tag:SetWidth(mid - 32 - 190)
	detail.tag:SetWordWrap(false)
	detail.title:SetText(d.name)
	-- The rewards of the chain's quests, in one row under the name; what does not fit is
	-- counted ("+12"), and the pop-up has them all. What is already in the bags is dimmed.
	local row = detail.headRewards
	local fits = math.max(1, math.floor((mid - 32 - 250 - 40) / HEAD_ICON))
	local left = ShowIcons(row.icons, row, d.rewards, fits, HEAD_ICON - 2, function(b, n)
		b:SetPoint("TOPLEFT", (n - 1) * HEAD_ICON, 0)
	end)
	local shown = #d.rewards - left
	for n = 1, shown do row.icons[n]:SetAlpha(d.got[ d.rewards[n] ] and 0.4 or 1) end
	row.more:SetText(left > 0 and ("+" .. left) or "")
	row.more:ClearAllPoints()
	row.more:SetPoint("LEFT", row, "TOPLEFT", shown * HEAD_ICON + 4, -HEAD_ICON / 2)
	row:SetShown(#d.rewards > 0)
	detail.markButton:SetShown(d.canMark)
	detail.markButton.chain, detail.markButton.to = d.id, not d.marked
	detail.markButton.label:SetText(d.marked and "Not done after all" or "Mark as done")
	-- the loot button stands under "Mark as done", or in its place
	detail.lootButton:ClearAllPoints()
	detail.lootButton:SetPoint("TOPRIGHT", -10, d.canMark and -42 or -10)
	detail.banner.art:SetTexture(d.art)
	detail.banner.art:SetShown(d.art ~= nil)
	detail.bar:Set(d.fraction)
	-- the numbers on one line, and the facts on the line over it
	local parts = {}
	for _, stat in ipairs(d.stats) do
		if stat.value ~= "-" then
			parts[#parts + 1] = MUTED_CODE .. stat.label .. ":|r " .. Code(TONE[stat.tone] or TEXT) .. stat.value .. "|r"
		end
	end
	detail.summary:SetText(table.concat(parts, "      "))
	-- the facts that need words, one line each, the last one right over the numbers
	for i, line in ipairs(detail.factLines) do
		local fact = d.facts[i]
		local hit = detail.factHits[i]
		line:SetShown(fact ~= nil)
		hit:SetShown(fact ~= nil and fact.full ~= nil)
		hit.title, hit.full = fact and fact.label, fact and fact.full
		if fact then
			line:SetText(MUTED_CODE .. fact.label .. ":|r " .. Code(TONE[fact.tone] or TEXT) .. fact.text .. "|r")
			line:ClearAllPoints()
			line:SetPoint("BOTTOMLEFT", 16, 34 + (math.min(#d.facts, FACT_LINES) - i) * 20)
		end
	end
	-- the chain's page on Wowhead, when it has one
	detail.link.url = d.link
	detail.link:SetShown(d.link ~= nil)
	detail.linkLabel:SetShown(d.link ~= nil)
	if d.link then
		detail.link:SetText(d.link)
		detail.link:SetCursorPosition(0)
	end
	DrawNext(d.next)
	DrawSide(d)
	Preload(d)
	local asGraph = d.graph ~= nil and d.mode == "graph"
	DrawSteps(asGraph and {} or d.steps, d.reach)

	-- Stack the blocks top down. The steps get everything under the "Next" box.
	local y = BANNER_HEIGHT + 8
	local function place(region, height, gap)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", 0, -y)
		y = y + height + (gap or 8)
	end

	place(detail.next, detail.next.height or 70, 14)

	-- "Steps" and the graph or list button on the same line
	detail.stepsLabel:SetShown(#d.steps > 0)
	detail.mode:SetShown(d.graph ~= nil)
	if d.graph then
		detail.mode.chain = d.id
		detail.mode.to = asGraph and "list" or "graph"
		detail.mode.label:SetText(asGraph and "Show list" or "Show graph")
		detail.mode:ClearAllPoints()
		detail.mode:SetPoint("TOPRIGHT", detail, "TOPLEFT", mid, -(y - 4))
	end
	place(detail.stepsLabel, 22, 10)

	detail.stepScroll:SetShown(not asGraph)
	detail.stepScroll:ClearAllPoints()
	detail.stepScroll:SetPoint("TOPLEFT", 0, -y)
	detail.stepScroll:SetPoint("BOTTOMRIGHT", -22, 0)

	detail.graph:SetShown(asGraph)
	detail.graph:ClearAllPoints()
	detail.graph:SetPoint("TOPLEFT", 0, -y)
	detail.graph:SetPoint("BOTTOMRIGHT", 0, 0)
	if asGraph then
		DrawGraph(d, DETAIL_HEIGHT - y - GRAPH_PAD * 2)
	else
		graph.shown = nil
	end
	detail.modeHint:SetShown(asGraph and (graph.maxX > 0 or graph.maxY > 0))
end

function Window.Refresh()
	queued = false
	if not frame then return end
	local model = ns.View.Build(selected, ns.db.closed, ns.db.modes, search, pickedStep, pickedPart)
	selected = model.selected
	pickedStep = model.step
	if not pickedStep then pickedPart = nil end
	DrawList(model)
	detail:SetShown(model.detail ~= nil)
	if model.detail then DrawDetail(model.detail) end
end

-- Many events can arrive at once (bags, quests); draw once for all of them.
function Window.Queue()
	if queued or not Window.IsShown() then return end
	queued = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.2, Window.Refresh)
	else
		Window.Refresh()
	end
end

function Window.IsShown()
	return frame ~= nil and frame:IsShown()
end

-- Is the "Nothing found." line under the search box showing?
function Window.NothingFound()
	return noneText ~= nil and noneText:IsShown()
end

-- Opens or closes the options panel under the cog.
function Window.Options()
	if frame then ns.Options.Toggle(frame, frame.cog) end
end

function Window.Toggle()
	if not frame then Build() end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		frame:Raise()
		Window.Refresh()
	end
end
