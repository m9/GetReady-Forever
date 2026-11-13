local ADDON, ns = ...

-- Options: window size, and whether to list what other classes can do.
-- The same controls show in two places: a small panel that the cog in the window opens,
-- and a page in the game's own options. Both read and write the saved settings.

local Options = {}
ns.Options = Options

local STEP = 5 -- percent per click on the size buttons

local GOLD = { 1.00, 0.82, 0.30 }
local TEXT = { 0.94, 0.92, 0.86 }
local MUTED = { 0.64, 0.61, 0.55 }
local PANEL = { 0.075, 0.07, 0.062 }
local LINE = { 0.27, 0.235, 0.16 }

-- Settings ------------------------------------------------------------------------

function Options.Size()
	return tonumber(ns.db.size) or ns.DEFAULT_SIZE
end

function Options.SetSize(percent)
	ns.db.size = math.max(ns.MIN_SIZE, math.min(ns.MAX_SIZE, math.floor(percent + 0.5)))
	ns.Window.Resize()
	Options.Sync()
end

function Options.AllClasses()
	return ns.db.allClasses == true
end

function Options.SetAllClasses(on)
	ns.db.allClasses = on and true or nil
	ns.Window.Refresh()
	Options.Sync()
end

-- Controls ------------------------------------------------------------------------

local function Label(parent, font, c, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(c[1], c[2], c[3])
	fs:SetText(text or "")
	return fs
end

-- A small square button with one sign on it.
local function SignButton(parent, sign)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	b.back = b:CreateTexture(nil, "BACKGROUND")
	b.back:SetAllPoints()
	b.back:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
	b.hover = b:CreateTexture(nil, "HIGHLIGHT")
	b.hover:SetAllPoints()
	b.hover:SetColorTexture(1, 1, 1, 0.12)
	b.label = Label(b, "GameFontNormalLarge", GOLD, sign)
	b.label:SetPoint("CENTER", 0, 0)
	return b
end

local filled = {} -- every set of controls made, so a change shows in all of them

-- Puts the controls on a frame, top left at x, y. Returns the height they take.
function Options.Fill(parent, x, y)
	local set = {}

	set.sizeLabel = Label(parent, "GameFontNormal", GOLD, "Window size")
	set.sizeLabel:SetPoint("TOPLEFT", x, y)
	set.less = SignButton(parent, "-")
	set.less:SetPoint("TOPLEFT", x, y - 22)
	set.less.option = "less"
	set.less:SetScript("OnClick", function() Options.SetSize(Options.Size() - STEP) end)
	set.value = Label(parent, "GameFontHighlightLarge", TEXT)
	set.value:SetPoint("LEFT", set.less, "RIGHT", 10, 0)
	set.value:SetWidth(52)
	set.value:SetJustifyH("CENTER")
	set.more = SignButton(parent, "+")
	set.more:SetPoint("LEFT", set.value, "RIGHT", 10, 0)
	set.more.option = "more"
	set.more:SetScript("OnClick", function() Options.SetSize(Options.Size() + STEP) end)
	set.sizeHint = Label(parent, "GameFontHighlightSmall", MUTED, "Share of the screen the window fills.")
	set.sizeHint:SetPoint("TOPLEFT", x, y - 52)

	set.all = CreateFrame("Button", nil, parent)
	set.all:SetSize(240, 24)
	set.all:SetPoint("TOPLEFT", x, y - 82)
	set.all.option = "allClasses"
	set.all.box = set.all:CreateTexture(nil, "BACKGROUND")
	set.all.box:SetSize(20, 20)
	set.all.box:SetPoint("LEFT", 0, 0)
	set.all.box:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
	set.all.check = set.all:CreateTexture(nil, "ARTWORK")
	set.all.check:SetSize(22, 22)
	set.all.check:SetPoint("CENTER", set.all.box, "CENTER", 0, 0)
	set.all.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	set.all.label = Label(set.all, "GameFontNormal", GOLD, "Show other classes")
	set.all.label:SetPoint("LEFT", set.all.box, "RIGHT", 8, 0)
	set.all:SetScript("OnClick", function() Options.SetAllClasses(not Options.AllClasses()) end)
	set.allHint = Label(parent, "GameFontHighlightSmall", MUTED, "Also list chains and steps your class cannot do.")
	set.allHint:SetPoint("TOPLEFT", x, y - 110)

	filled[#filled + 1] = set
	Options.Sync()
	return 126
end

-- Shows the saved values on every set of controls.
function Options.Sync()
	local size, all = Options.Size(), Options.AllClasses()
	for _, set in ipairs(filled) do
		set.value:SetText(size .. "%")
		set.less:SetAlpha(size > ns.MIN_SIZE and 1 or 0.35)
		set.more:SetAlpha(size < ns.MAX_SIZE and 1 or 0.35)
		set.all.check:SetShown(all)
	end
end

-- The panel in the window ------------------------------------------------------------

local popup

-- Opens or closes the small panel under the cog.
function Options.Toggle(window, cog)
	if not popup then
		popup = CreateFrame("Frame", "GetReadyOptions", window, "BackdropTemplate")
		popup:SetFrameStrata("DIALOG")
		popup:EnableMouse(true)
		popup:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		popup:SetBackdropColor(PANEL[1], PANEL[2], PANEL[3], 0.98)
		popup:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
		popup:SetPoint("TOPRIGHT", cog, "BOTTOMRIGHT", 6, -6)
		popup.title = Label(popup, "GameFontNormalLarge", GOLD, "Options")
		popup.title:SetPoint("TOPLEFT", 16, -14)
		local height = Options.Fill(popup, 16, -44)
		popup:SetSize(290, height + 58)
		popup:Hide()
	end
	popup:SetShown(not popup:IsShown())
	if popup:IsShown() then Options.Sync() end
end

function Options.IsShown()
	return popup ~= nil and popup:IsShown()
end

-- "/gr options": the window with the panel open.
function Options.Open()
	if not ns.Window.IsShown() then ns.Window.Toggle() end
	if not Options.IsShown() then ns.Window.Options() end
end

-- The page in the game's options -------------------------------------------------------

local page

function Options.Register()
	if page then return end
	page = CreateFrame("Frame", "GetReadyOptionsPage")
	page.name = "Get Ready"
	page.title = Label(page, "GameFontNormalLarge", GOLD, "Get Ready")
	page.title:SetPoint("TOPLEFT", 16, -16)
	Options.Fill(page, 16, -52)
	page:SetScript("OnShow", Options.Sync)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(page, page.name)
		Settings.RegisterAddOnCategory(category)
		Options.category = category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(page)
	end
end
