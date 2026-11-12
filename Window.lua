local _, ns = ...

-- Main window: chains on the left, the picked chain in the middle, and what may drop on the
-- way on the right. The steps of a chain show as a list, or as a graph when they lead to
-- one another.
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
local DEFAULT_SIZE = 96 -- percent of the screen; "/gr size N" changes it
local TOP = 64 -- room for the window's title
local PAD = 18
local LIST_WIDTH = 290
local LIST_ROW, LIST_HEAD = 34, 36
local LOOT_WIDTH = 270 -- right column, without its scroll bar
local DETAIL_WIDTH = WIDTH - LIST_WIDTH - LOOT_WIDTH - PAD * 4 - 22 * 2 -- middle, edge to edge
local DETAIL_HEIGHT = HEIGHT - TOP - PAD -- middle, top to bottom
local BANNER_HEIGHT = 140 -- picture of the place with the chain's name on it
local TILES, TILE_GAP, TILE_HEIGHT = 4, 8, 58 -- the numbers under the banner
local TILE_WIDTH = (DETAIL_WIDTH - TILE_GAP * (TILES - 1)) / TILES
local FACT_LABEL, FACT_ROW = 104, 20 -- "Dungeons", "Needs", "Reputation" lines
local ICON = 36 -- a chain reward or loot icon, with its gap
local REWARDS_LEFT = FACT_LABEL -- reward icons start right of the "Rewards" label
local REWARDS_PER_ROW = math.floor((DETAIL_WIDTH - REWARDS_LEFT) / ICON)
local REWARD_ROWS = 3 -- more than this many rows of chain rewards is cut short
local LOOT_PER_ROW = math.floor(LOOT_WIDTH / ICON)
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

-- A step's state: the color of its mark and stripe, and of its name.
local STATE_COLOR = { done = GREEN, skipped = GREEN_DIM, active = GOLD, ready = BLUE, locked = FAINT }
local STATE_TEXT = { done = GREEN, skipped = GREEN_DIM, active = GOLD, ready = TEXT, locked = MUTED }
-- The game's own small pictures, so a state reads without its color too. "ready" has none
-- and gets a blue square.
local STATE_ICON = {
	done = "Interface\\RaidFrame\\ReadyCheck-Ready",
	skipped = "Interface\\RaidFrame\\ReadyCheck-Ready",
	active = "Interface\\RaidFrame\\ReadyCheck-Waiting",
	locked = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK",
}
-- Picture laid over an item icon when the character cannot use the item as things stand.
-- Both are the game's own, with nothing behind them, so the item still shows through.
local OVERLAY = {
	no = "Interface\\RaidFrame\\ReadyCheck-NotReady", -- red cross: the class never can
	learn = "Interface\\RaidFrame\\ReadyCheck-Waiting", -- yellow question mark: the class can learn to
}
local LEGEND = { { "done", "Done" }, { "active", "In your log" }, { "ready", "Can start" }, { "locked", "Locked" } }

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
	if line:find("^Needs ") then return RED_CODE .. line .. "|r" end
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
local loot, lootChild, lootHeads, lootIcons -- right column: frame, scroll child, pools
-- Where the graph is scrolled to, how far it can go, and whose graph it is.
local graph = { x = 0, y = 0, maxX = 0, maxY = 0 }
local selected
local queued = false

local function Select(id)
	selected = id
	ns.db.selected = id
	Window.Refresh()
end

local function Pin(target)
	if not target then return end
	if ns.api.SetWaypoint(target.map, target.x, target.y) then
		ns.Print("Map pin: " .. target.name)
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
	row:SetScript("OnClick", function(self) Pin(self.target) end)
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
	b.name:SetWordWrap(false)
	b.xp = Text(b, "GameFontHighlightSmall", VIOLET)
	b.xp:SetPoint("BOTTOMLEFT", 10, 8)
	b.icons = {}
	b:SetScript("OnClick", function(self) Pin(self.step.target) end)
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

local function Build()
	frame = CreateFrame("Frame", "GetReadyFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
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

	-- Left: chains
	local list = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	list:SetPoint("TOPLEFT", PAD, -TOP)
	list:SetPoint("BOTTOMLEFT", PAD, PAD)
	list:SetWidth(LIST_WIDTH + 22)
	Panel(list, PANEL, 0.7)

	local listScroll = CreateFrame("ScrollFrame", "GetReadyListScroll", list, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", 4, -4)
	listScroll:SetPoint("BOTTOMRIGHT", -26, 4)
	listChild = CreateFrame("Frame", nil, listScroll)
	listChild:SetSize(LIST_WIDTH, 10)
	listScroll:SetScrollChild(listChild)

	-- Middle: the picked chain
	detail = CreateFrame("Frame", nil, frame)
	detail:SetPoint("TOPLEFT", list, "TOPRIGHT", PAD, 0)
	detail:SetPoint("BOTTOMRIGHT", -(PAD * 2 + LOOT_WIDTH + 22), PAD)

	-- Right: what may drop on the way. Not quest rewards, so it has its own column.
	loot = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	loot:SetPoint("TOPLEFT", detail, "TOPRIGHT", PAD, 0)
	loot:SetPoint("BOTTOMLEFT", detail, "BOTTOMRIGHT", PAD, 0)
	loot:SetWidth(LOOT_WIDTH + 22)
	Panel(loot, PANEL, 0.7)
	loot.title = Heading(loot, 19, GOLD)
	loot.title:SetPoint("TOPLEFT", 10, -10)
	loot.title:SetText("Possible loot")
	loot.sub = Text(loot, "GameFontHighlightSmall", MUTED)
	loot.sub:SetPoint("TOPLEFT", 10, -36)
	loot.sub:SetWidth(LOOT_WIDTH)
	loot.rule = Fill(loot, "ARTWORK", LINE, 1)
	loot.rule:SetPoint("TOPLEFT", 8, -74)
	loot.rule:SetPoint("TOPRIGHT", -8, -74)
	loot.rule:SetHeight(1)
	local lootScroll = CreateFrame("ScrollFrame", "GetReadyLootScroll", loot, "UIPanelScrollFrameTemplate")
	lootScroll:SetPoint("TOPLEFT", 8, -82)
	lootScroll:SetPoint("BOTTOMRIGHT", -26, 6)
	lootChild = CreateFrame("Frame", nil, lootScroll)
	lootChild:SetSize(LOOT_WIDTH, 10)
	lootScroll:SetScrollChild(lootChild)
	lootHeads, lootIcons = {}, {}

	-- Banner: a strip of the place's loading screen. On it, bottom up: the chain's note,
	-- its name, and what kind of chain it is. A chain without a picture gets the same
	-- banner on plain black.
	local banner = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	detail.banner = banner
	banner:SetPoint("TOPLEFT", 0, 0)
	banner:SetSize(DETAIL_WIDTH, BANNER_HEIGHT)
	Panel(banner, BLACK, 1, GOLD_DIM)
	banner.art = banner:CreateTexture(nil, "BORDER")
	banner.art:SetPoint("TOPLEFT", 1, -1)
	banner.art:SetPoint("BOTTOMRIGHT", -1, 1)
	-- The screens are 4:3 pictures; show the full width and a band from a little above the middle.
	local band = (BANNER_HEIGHT / DETAIL_WIDTH) / 0.75
	banner.art:SetTexCoord(0, 1, 0.45 - band / 2, 0.45 + band / 2)
	-- Dark from the bottom up, so the words read on any picture.
	banner.shade = Fill(banner, "ARTWORK", BLACK, 0.6)
	banner.shade:SetPoint("BOTTOMLEFT", 1, 1)
	banner.shade:SetPoint("BOTTOMRIGHT", -1, 1)
	banner.shade:SetHeight(BANNER_HEIGHT - 2)
	if CreateColor and banner.shade.SetGradient then
		banner.shade:SetColorTexture(1, 1, 1, 1)
		local ok = pcall(banner.shade.SetGradient, banner.shade, "VERTICAL",
			CreateColor(BLACK[1], BLACK[2], BLACK[3], 0.95), CreateColor(BLACK[1], BLACK[2], BLACK[3], 0.1))
		if not ok then banner.shade:SetColorTexture(BLACK[1], BLACK[2], BLACK[3], 0.6) end
	end

	detail.tag = Text(banner, "GameFontNormalSmall", GOLD_SOFT)
	detail.tag:SetPoint("BOTTOMLEFT", 16, 80)
	detail.title = Heading(banner, 36, GOLD)
	detail.title:SetPoint("BOTTOMLEFT", 14, 38)
	detail.title:SetWidth(DETAIL_WIDTH - 28)
	detail.title:SetWordWrap(false)
	detail.note = Text(banner, "GameFontHighlight", TEXT)
	detail.note:SetPoint("BOTTOMLEFT", 16, 14)
	detail.note:SetWidth(DETAIL_WIDTH - 32)
	detail.note:SetWordWrap(false)
	-- for what the game cannot see, or a chain the player does not want to do
	detail.markButton = GoldButton(banner, "", 150)
	detail.markButton:SetPoint("TOPRIGHT", -10, -10)
	detail.markButton:SetScript("OnClick", function(self)
		ns.Mark(self.chain, self.to)
		Window.Refresh()
	end)

	-- The numbers at a glance: one tile each. The first has the progress bar.
	detail.tiles = {}
	for i = 1, TILES do
		local tile = CreateFrame("Frame", nil, detail, "BackdropTemplate")
		tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
		Panel(tile, PANEL, 0.9)
		tile.label = Text(tile, "GameFontHighlightSmall", MUTED)
		tile.label:SetPoint("TOPLEFT", 12, -8)
		tile.value = Text(tile, "GameFontNormalLarge", TEXT)
		tile.value:SetPoint("BOTTOMLEFT", 12, 10)
		detail.tiles[i] = tile
	end
	detail.bar = Bar(detail.tiles[1], TILE_WIDTH - 2, 3)
	detail.bar:SetPoint("BOTTOMLEFT", 1, 1)

	-- Facts that need words: a grey label, then the text in the color of its kind.
	detail.facts = {}
	for i = 1, 3 do
		local fact = CreateFrame("Frame", nil, detail)
		fact:SetSize(DETAIL_WIDTH, FACT_ROW)
		fact.label = Text(fact, "GameFontHighlightSmall", MUTED)
		fact.label:SetPoint("TOPLEFT", 0, -1)
		fact.text = Text(fact, "GameFontHighlightSmall", TEXT)
		fact.text:SetPoint("TOPLEFT", FACT_LABEL, -1)
		fact.text:SetWidth(DETAIL_WIDTH - FACT_LABEL)
		fact.text:SetWordWrap(false)
		detail.facts[i] = fact
	end

	-- Everything the chain's quests give, the chain's own item first
	detail.rewards = CreateFrame("Frame", nil, detail)
	detail.rewards:SetSize(DETAIL_WIDTH, ICON)
	detail.rewards.label = Text(detail.rewards, "GameFontHighlightSmall", MUTED)
	detail.rewards.label:SetPoint("TOPLEFT", 0, -10)
	detail.rewards.label:SetText("Rewards")
	detail.rewards.icons = {}
	detail.rewards.more = Text(detail.rewards, "GameFontHighlightSmall", MUTED)
	detail.rewards.more:SetPoint("TOPLEFT", 0, -ICON - 6)

	-- "Next" box: the one thing to do now. Its stripe has the color of the step's state.
	detail.next = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	detail.next:SetWidth(DETAIL_WIDTH)
	Panel(detail.next, PANEL_HI, 0.95, GOLD_DIM)
	detail.next.stripe = detail.next:CreateTexture(nil, "ARTWORK")
	detail.next.stripe:SetPoint("TOPLEFT", 1, -1)
	detail.next.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	detail.next.stripe:SetWidth(4)
	detail.next.label = Text(detail.next, "GameFontHighlightSmall", MUTED)
	detail.next.label:SetPoint("TOPLEFT", 18, -10)
	detail.next.name = Text(detail.next, "GameFontNormalLarge", GOLD)
	detail.next.name:SetPoint("TOPLEFT", 18, -28)
	detail.next.name:SetWidth(DETAIL_WIDTH - 170)
	detail.next.name:SetWordWrap(false)
	detail.next.hint = Text(detail.next, "GameFontHighlight", TEXT)
	detail.next.hint:SetPoint("TOPLEFT", 18, -56)
	detail.next.hint:SetWidth(DETAIL_WIDTH - 36)
	detail.next.hint:SetSpacing(4)
	detail.next.pin = GoldButton(detail.next, "Show on map", 126)
	detail.next.pin:SetPoint("TOPRIGHT", -10, -10)
	detail.next.pin:SetScript("OnClick", function(self) Pin(self.target) end)

	-- "Steps", what the marks mean, and the graph or list button, on one line
	detail.stepsLabel = Heading(detail, 19, GOLD)
	detail.stepsLabel:SetText("Steps")
	detail.legend = CreateFrame("Frame", nil, detail)
	detail.legend:SetSize(10, 20)
	local x = 0
	for _, entry in ipairs(LEGEND) do
		local mark = Mark(detail.legend, 16)
		mark:SetPoint("LEFT", x, 0)
		mark:Set(entry[1])
		local word = Text(detail.legend, "GameFontHighlightSmall", MUTED)
		word:SetPoint("LEFT", x + 20, 0)
		word:SetText(entry[2])
		x = x + 20 + #entry[2] * 7 + 22
	end

	detail.mode = GoldButton(detail, "", 112)
	detail.mode:SetScript("OnClick", function(self)
		ns.db.modes[self.chain] = self.to
		Window.Refresh()
	end)
	detail.modeHint = Text(detail, "GameFontHighlightSmall", FAINT)
	detail.modeHint:SetPoint("RIGHT", detail.mode, "LEFT", -10, 0)
	detail.modeHint:SetText("Wheel or drag to move")

	detail.graph = CreateFrame("Frame", nil, detail, "BackdropTemplate")
	Panel(detail.graph, BLACK, 0.6)
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

	local stepScroll = CreateFrame("ScrollFrame", "GetReadyStepScroll", detail, "UIPanelScrollFrameTemplate")
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
				row.name:SetText(chain.name)
				Color(row.name, chain.done and GREEN_DIM or (picked and GOLD or TEXT))
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
	listChild:SetHeight(math.max(y, 10))
end

local function DrawNext(next)
	local box = detail.next
	local c = STATE_COLOR[next.state] or GOLD
	box.stripe:SetColorTexture(c[1], c[2], c[3], 1)
	box.label:SetText(next.label)
	box.name:SetText(next.name or "")
	Color(box.name, next.state == "locked" and MUTED or (next.state == "done" and GREEN or GOLD))
	box.hint:SetText(PrettyLines(next.lines))
	box.pin.target = next.target
	box.pin:SetShown(next.target ~= nil)
	box.height = 66 + (#next.lines > 0 and TextHeight(box.hint, #next.lines, 20) or 0)
	box:SetHeight(box.height)
end

local function DrawSteps(steps)
	local y = 0
	for i, step in ipairs(steps) do
		local row = StepRow(i)
		local finished = step.state == "done" or step.state == "skipped"
		row.mark:Set(step.state)
		-- the level after the name: red when the player is below it
		local level = step.needLevel and (RED_CODE .. "level " .. step.needLevel .. "|r")
			or (step.level and (MUTED_CODE .. "level " .. step.level .. "|r"))
		row.name:SetText(step.name .. (level and ("  " .. level) or ""))
		Color(row.name, STATE_TEXT[step.state])
		row.xp:SetText(step.xp or "")
		row.xp:SetAlpha(finished and 0.5 or 1)
		-- under the name: what to do, then the reputation the quest gives
		local lines = {}
		for n, line in ipairs(step.hints) do lines[n] = Pretty(line) end
		if step.rep then lines[#lines + 1] = TEAL_CODE .. step.rep .. "|r" end
		row.hint:SetText(table.concat(lines, "\n"))
		row.hint:SetShown(#lines > 0)
		row.hint:SetAlpha(finished and 0.5 or 1)
		row.target = step.target
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
	end
	for i = #steps + 1, #stepRows do stepRows[i]:Hide() end
	stepChild:SetHeight(math.max(y, 10))
end

-- Right column: loot by the creature that drops it.
local function DrawLoot(groups)
	local count = 0
	for _, group in ipairs(groups) do count = count + #group.items end
	loot.sub:SetText(count > 0 and "May drop from enemies on the way.\nNot quest rewards." or "Nothing known for this chain.")

	local y, used = 0, 0
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
	for i, step in ipairs(d.steps) do
		local b = Node(i)
		local c = STATE_COLOR[step.state]
		local x, y = Cell(step)
		local finished = step.state == "done" or step.state == "skipped"
		b.step = step
		b.tip = { step.status }
		for _, line in ipairs(step.hints) do b.tip[#b.tip + 1] = line end
		b.tip[#b.tip + 1] = step.rewardLine
		b.tip[#b.tip + 1] = step.gain
		if step.target then b.tip[#b.tip + 1] = "Click for a map pin" end
		b.mark:Set(step.state)
		b.name:SetText(step.name)
		Color(b.name, STATE_TEXT[step.state])
		-- second line: the level in red when the player is below it, then the XP
		b.xp:SetText((step.needLevel and (RED_CODE .. "Lvl " .. step.needLevel .. "|r  ") or "") .. (step.xp or ""))
		b.xp:SetAlpha(finished and 0.5 or 1)
		ShowIcons(b.icons, b, step.rewards, NODE_ICONS, NODE_ICON - 2, function(icon, n)
			icon:SetPoint("BOTTOMRIGHT", -6 - (n - 1) * NODE_ICON, 5)
		end)
		for n = 1, #b.icons do b.icons[n]:SetAlpha(finished and 0.45 or 1) end
		b.stripe:SetColorTexture(c[1], c[2], c[3], 1)
		-- a goal has a gold edge, twice as thick; a step in your log is a shade lighter
		local edge = step.goal and GOLD_DIM or LINE
		local fill = step.state == "active" and PANEL_HI or PANEL
		local inset = step.goal and 2 or 1
		b.edge:SetColorTexture(edge[1], edge[2], edge[3], 1)
		b.body:SetColorTexture(fill[1], fill[2], fill[3], 1)
		b.body:ClearAllPoints()
		b.body:SetPoint("TOPLEFT", inset, -inset)
		b.body:SetPoint("BOTTOMRIGHT", -inset, inset)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", x, -y)
		b:Show()
	end
	for i = #d.steps + 1, #nodes do nodes[i]:Hide() end

	-- A line leaves the earlier step to the right, turns just before the later one, and goes in.
	local n = 0
	for _, edge in ipairs(g.edges) do
		local ax, ay = Cell(d.steps[edge.from])
		local bx, by = Cell(d.steps[edge.to])
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
	graph.maxX = math.max(0, width - GRAPH_WIDTH)
	graph.maxY = math.max(0, height - viewHeight)
	if graph.shown == d.id then
		ScrollGraph(graph.x, graph.y) -- same graph as before: stay where the player was
	else
		graph.shown = d.id
		local x, y = 0, 0
		if g.focus then
			x, y = Cell(d.steps[g.focus]) -- another one: start at the next step
			x, y = x - NODE_W / 2, y - NODE_ROW * 2
		end
		ScrollGraph(x, y)
	end
end

local function DrawDetail(d)
	detail.tag:SetText(d.tag or "")
	detail.title:SetText(d.name)
	detail.note:SetText(d.note or "")
	detail.markButton:SetShown(d.canMark)
	detail.markButton.chain, detail.markButton.to = d.id, not d.marked
	detail.markButton.label:SetText(d.marked and "Not done after all" or "Mark as done")
	detail.banner.art:SetTexture(d.art)
	detail.banner.art:SetShown(d.art ~= nil)
	detail.bar:Set(d.fraction)
	DrawNext(d.next)
	DrawLoot(d.loot)
	local asGraph = d.graph ~= nil and d.mode == "graph"
	DrawSteps(asGraph and {} or d.steps)

	-- Stack the blocks top down; some are empty and take no room.
	local y = BANNER_HEIGHT + TILE_GAP
	local function place(region, height, gap)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", 0, -y)
		y = y + height + (gap or 8)
	end

	for i, tile in ipairs(detail.tiles) do
		local stat = d.stats[i]
		tile:SetShown(stat ~= nil)
		if stat then
			tile.label:SetText(stat.label)
			tile.value:SetText(stat.value)
			Color(tile.value, TONE[stat.tone] or TEXT)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", (i - 1) * (TILE_WIDTH + TILE_GAP), -y)
		end
	end
	y = y + TILE_HEIGHT + 10

	for i, fact in ipairs(detail.facts) do
		local entry = d.facts[i]
		fact:SetShown(entry ~= nil)
		if entry then
			fact.label:SetText(entry.label)
			fact.text:SetText(entry.text)
			Color(fact.text, TONE[entry.tone] or TEXT)
			place(fact, FACT_ROW, 1)
		end
	end
	if #d.facts > 0 then y = y + 5 end

	detail.rewards:SetShown(#d.rewards > 0)
	if #d.rewards > 0 then
		-- All of them, in rows; what is already in hand is dimmed.
		local icons = detail.rewards.icons
		local left = ShowIcons(icons, detail.rewards, d.rewards, REWARDS_PER_ROW * REWARD_ROWS, ICON - 2, function(b, n)
			b:SetPoint("TOPLEFT", REWARDS_LEFT + ((n - 1) % REWARDS_PER_ROW) * ICON, -math.floor((n - 1) / REWARDS_PER_ROW) * ICON)
		end)
		local shown = #d.rewards - left
		for n = 1, shown do icons[n]:SetAlpha(d.got[d.rewards[n]] and 0.4 or 1) end
		detail.rewards.more:SetText(left > 0 and ("+" .. left .. " more") or "")
		local height = math.ceil(shown / REWARDS_PER_ROW) * ICON
		detail.rewards:SetHeight(height)
		place(detail.rewards, height)
	end

	place(detail.next, detail.next.height or 70, 14)

	-- "Steps", the legend, and the graph or list button on the same line
	detail.stepsLabel:SetShown(#d.steps > 0)
	detail.legend:SetShown(#d.steps > 0)
	detail.legend:ClearAllPoints()
	detail.legend:SetPoint("TOPLEFT", 86, -(y + 1))
	detail.mode:SetShown(d.graph ~= nil)
	if d.graph then
		detail.mode.chain = d.id
		detail.mode.to = asGraph and "list" or "graph"
		detail.mode.label:SetText(asGraph and "Show list" or "Show graph")
		detail.mode:ClearAllPoints()
		detail.mode:SetPoint("TOPRIGHT", detail, "TOPLEFT", DETAIL_WIDTH, -(y - 4))
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
	local model = ns.View.Build(selected, ns.db.closed, ns.db.modes)
	selected = model.selected
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

function Window.Toggle()
	if not frame then Build() end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		Window.Refresh()
	end
end
