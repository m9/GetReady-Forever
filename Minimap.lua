local _, ns = ...

-- A round button on the edge of the minimap. A click opens or closes the window, a drag
-- moves the button around the edge. "/gr minimap" hides it or brings it back.

local Button = {}
ns.MinimapButton = Button

local DEFAULT_ANGLE = 215 -- degrees, counted from the right edge; lower left by default
local button

local function Place()
	local angle = math.rad(ns.db.minimap.angle or DEFAULT_ANGLE)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragged, the button stays on the edge, on the side the mouse is.
local function Follow()
	local centerX, centerY = Minimap:GetCenter()
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.minimap.angle = math.floor(math.deg(math.atan2(y / scale - centerY, x / scale - centerX)) % 360 + 0.5)
	Place()
end

local function Build()
	button = CreateFrame("Button", "GetReadyMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	back:SetSize(20, 20)
	back:SetPoint("TOPLEFT", 7, -5)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(ns.ICON)
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.icon:SetSize(20, 20)
	button.icon:SetPoint("TOPLEFT", 7, -5)
	local ring = button:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function() ns.Window.Toggle() end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Follow) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		ns.api.TextTooltip(self, "Get Ready", { "Click to open or close.", "Drag to move this button." })
	end)
	button:SetScript("OnLeave", ns.api.HideTooltip)
end

-- Shows or hides the button as the settings say. Called once the settings have loaded.
function Button.Apply()
	if not Minimap then return end
	if ns.db.minimap.hide then
		if button then button:Hide() end
		return
	end
	if not button then Build() end
	Place()
	button:Show()
end
