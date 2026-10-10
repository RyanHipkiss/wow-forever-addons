local _, CP = ...

local UI = {}
CP.UI = UI

local ROW_HEIGHT = 36
local LINE_HEIGHT = 16
local COLUMNS = {
	{ key = "name",   label = "Item",      width = 230, justify = "LEFT" },
	{ key = "char",   label = "Crafter",   width = 120, justify = "LEFT" },
	{ key = "cost",   label = "Mat cost",  width = 95,  justify = "RIGHT" },
	{ key = "sell",   label = "Sells for", width = 95,  justify = "RIGHT" },
	{ key = "profit", label = "Profit",    width = 95,  justify = "RIGHT" },
	{ key = "margin", label = "Margin",    width = 55,  justify = "RIGHT" },
	{ key = "listed", label = "Listed",    width = 50,  justify = "RIGHT" },
}
local SOURCE_LABEL = { ah = "AH", vendor = "vendor", craft = "crafted" }

UI.sortKey, UI.sortDesc = "profit", true

-- r, g, b, "|cffrrggbb" for an item quality, or nil.
local function QualityColor(quality)
	if not quality or not C_Item.GetItemQualityColor then return nil end
	local r, g, b, hex = C_Item.GetItemQualityColor(quality)
	if not r then return nil end
	return r, g, b, hex and ("|c" .. hex) or nil
end

local function RowName(row)
	local name = CP:ItemInfo(row.entry.recipe.out)
	return name or row.entry.recipe.name or "?"
end

local SORT_VALUE = {
	name = RowName,
	char = function(row) return row.entry.char .. row.entry.prof end,
	cost = function(row) return row.cost end,
	sell = function(row) return row.revenue end,
	profit = function(row) return row.profit end,
	margin = function(row) return row.margin end,
	listed = function(row) return row.listed end,
}

-- Window ------------------------------------------------------------------------

function UI:Create()
	if self.frame then return end
	local f = CreateFrame("Frame", "CraftProfitFrame", UIParent, "BasicFrameTemplateWithInset")
	self.frame = f
	f:SetSize(790, 560)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:Hide()
	tinsert(UISpecialFrames, "CraftProfitFrame") -- Escape closes it

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.title:SetPoint("TOP", 0, -5)
	f.title:SetText("CraftProfit - what to craft for profit")

	local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	scan:SetSize(110, 22)
	scan:SetPoint("TOPLEFT", 12, -30)
	scan:SetScript("OnClick", function() CP.Scanner:Start() end)
	self.scanButton = scan

	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.status:SetPoint("LEFT", scan, "RIGHT", 10, 0)
	f.status:SetJustifyH("LEFT")

	local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	search:SetSize(150, 20)
	search:SetPoint("TOPRIGHT", -16, -31)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function() UI:Refresh() end)
	search:SetScript("OnEscapePressed", search.ClearFocus)
	self.search = search
	local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	searchLabel:SetPoint("RIGHT", search, "LEFT", -8, 0)
	searchLabel:SetText("Search")

	self.checks = {}
	local function Check(label, settingKey, anchor, x)
		local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, -4)
		cb.text = cb.text or cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cb.text:ClearAllPoints()
		cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cb.text:SetFontObject("GameFontHighlightSmall")
		cb.text:SetText(label)
		cb:SetScript("OnShow", function(self) self:SetChecked(CP.db.settings[settingKey]) end)
		UI.checks[settingKey] = cb
		cb:SetScript("OnClick", function(self)
			CP.db.settings[settingKey] = self:GetChecked() and true or false
			UI:Refresh()
		end)
		return cb
	end
	local c1 = Check("Profitable only", "profitableOnly", scan, -2)
	local c2 = Check("Hide items with no AH listings", "hideNoListings", scan, 130)
	Check("Price mats at craft cost when cheaper", "useCraftedMats", scan, 360)

	-- Column headers
	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT", c1, "BOTTOMLEFT", 4, -6)
	header:SetSize(760, 18)
	local x = 0
	self.headers = {}
	for _, col in ipairs(COLUMNS) do
		local b = CreateFrame("Button", nil, header)
		b:SetSize(col.width, 18)
		b:SetPoint("LEFT", x, 0)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetAllPoints()
		fs:SetJustifyH(col.justify)
		fs:SetText(col.label)
		b.label = fs
		b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
		b:SetScript("OnClick", function()
			if UI.sortKey == col.key then
				UI.sortDesc = not UI.sortDesc
			else
				UI.sortKey, UI.sortDesc = col.key, col.key ~= "name" and col.key ~= "char"
			end
			UI:Refresh()
		end)
		self.headers[col.key] = b
		x = x + col.width + 4
	end

	-- Scrolling list
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -32, 30)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(760, 1)
	scroll:SetScrollChild(content)
	self.scroll, self.content, self.rows = scroll, content, {}

	f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.footer:SetPoint("BOTTOMLEFT", 14, 10)
	f.footer:SetPoint("BOTTOMRIGHT", -14, 10)
	f.footer:SetJustifyH("LEFT")

	f:SetScript("OnShow", function()
		UI:Refresh()
		UI.ticker = C_Timer.NewTicker(1, function() UI:UpdateStatus() end)
	end)
	f:SetScript("OnHide", function()
		if UI.ticker then UI.ticker:Cancel() UI.ticker = nil end
	end)
end

-- Rows ----------------------------------------------------------------------------

local function ShowRowTooltip(btn)
	local row = btn.data
	if not row then return end
	local r = row.entry.recipe
	local name, _, quality = CP:ItemInfo(r.out)
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	local qr, qg, qb = QualityColor(quality)
	GameTooltip:AddLine(name or r.name, qr or 1, qg or 1, qb or 1)
	GameTooltip:AddLine(("%s - %s"):format(row.entry.char, row.entry.prof), 0.7, 0.7, 0.7)
	if r.outQty ~= 1 then GameTooltip:AddLine(("Makes %g on average"):format(r.outQty), 0.7, 0.7, 0.7) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Materials")
	for _, l in ipairs(row.lines or {}) do
		local mName = CP:ItemInfo(l.id) or ("item " .. l.id)
		if l.unit then
			GameTooltip:AddDoubleLine(("%dx %s |cff808080(%s)|r"):format(l.qty, mName, SOURCE_LABEL[l.source] or "?"),
				CP:Money(l.unit * l.qty), 1, 1, 1, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine(("%dx %s"):format(l.qty, mName), "no price", 1, 0.3, 0.3, 1, 0.3, 0.3)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Mat cost", CP:Money(row.cost), 1, 0.82, 0, 1, 1, 1)
	if row.ahMin then
		GameTooltip:AddDoubleLine("Lowest AH buyout (each)", CP:Money(row.ahMin), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddDoubleLine("Market price (each)", CP:Money(row.ahMkt), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddDoubleLine("Listed on AH", row.listed, 1, 0.82, 0, 1, 1, 1)
	end
	if row.revenue then
		local how = row.sellSource == "vendor" and "Sells to vendor for" or
			("After %g%% AH cut"):format(CP.db.settings.ahCut * 100)
		GameTooltip:AddDoubleLine(how, CP:Money(row.revenue), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Profit per craft", CP:Money(row.profit), 1, 0.82, 0, 1, 1, 1)
	if row.missing then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Some mats have no price. Scan the AH, visit the vendor that sells them, or use /cp vendor.", 1, 0.3, 0.3, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Shift-click to link the item in chat.", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function InsertLink(link)
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		ChatFrameUtil.InsertLink(link)
	elseif ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
	end
end

function UI:GetRow(i)
	local row = self.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, self.content)
	row:SetSize(760, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	if i % 2 == 0 then
		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.04)
	end
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
	row.icon:SetPoint("LEFT", 0, 0)
	local iconSpace = ROW_HEIGHT
	row.cells = {}
	local x = 0
	for _, col in ipairs(COLUMNS) do
		local fs = row:CreateFontString(nil, "OVERLAY", col.key == "name" and "GameFontHighlight" or "GameFontHighlightSmall")
		local offset = col.key == "name" and iconSpace or 0
		fs:SetPoint("TOPLEFT", x + offset, -2)
		fs:SetSize(col.width - offset, LINE_HEIGHT)
		fs:SetJustifyH(col.justify)
		fs:SetWordWrap(false)
		row.cells[col.key] = fs
		x = x + col.width + 4
	end
	-- Second line: the mats to buy for one craft
	row.mats = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.mats:SetPoint("BOTTOMLEFT", iconSpace, 3)
	row.mats:SetSize(760 - iconSpace, LINE_HEIGHT)
	row.mats:SetJustifyH("LEFT")
	row.mats:SetWordWrap(false)
	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", function(btn)
		if IsModifiedClick("CHATLINK") and btn.data then
			local _, link = CP:ItemInfo(btn.data.entry.recipe.out)
			if link then InsertLink(link) end
		end
	end)
	self.rows[i] = row
	return row
end

local function FillRow(row, data)
	row.data = data
	local r = data.entry.recipe
	local name, _, quality, icon = CP:ItemInfo(r.out)
	row.icon:SetTexture(icon or 134400)
	local _, _, _, hex = QualityColor(quality)
	local label = (hex or "") .. (name or r.name or "?") .. (hex and "|r" or "")
	if r.outQty ~= 1 then label = ("%s |cff808080x%g|r"):format(label, r.outQty) end
	row.cells.name:SetText(label)
	row.cells.char:SetText(("%s |cff808080%s|r"):format(data.entry.char, data.entry.prof))
	row.cells.cost:SetText(data.cost and CP:Money(data.cost) or "|cffff4040missing|r")
	local sell = CP:Money(data.revenue)
	if data.sellSource == "vendor" then sell = "|cff808080(v)|r " .. sell end
	row.cells.sell:SetText(sell)
	row.cells.profit:SetText(CP:Money(data.profit))
	if data.margin then
		local pct = data.margin * 100
		local c = pct >= 0 and "|cff40ff40" or "|cffff4040"
		row.cells.margin:SetText(("%s%.0f%%|r"):format(c, pct))
	else
		row.cells.margin:SetText("|cff808080--|r")
	end
	row.cells.listed:SetText(data.ahMin and data.listed or "|cff8080800|r")

	local parts = {}
	for _, l in ipairs(data.lines or {}) do
		local mName = CP:ItemInfo(l.id) or ("item " .. l.id)
		local where
		if not l.unit then
			where = "|cffff4040no price|r"
		elseif l.source == "craft" then
			where = "|cff80c0ffcraft it|r"
		else
			where = SOURCE_LABEL[l.source] .. " " .. CP:Money(l.unit)
		end
		parts[#parts + 1] = ("|cffd0d0d0%dx %s|r (%s)"):format(l.qty, mName, where)
	end
	row.mats:SetText("Mats: " .. table.concat(parts, ",  "))
	row:Show()
end

-- Refresh -------------------------------------------------------------------------

function UI:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	local s = CP.db.settings
	local query = strtrim(self.search:GetText() or ""):lower()
	for key, cb in pairs(self.checks) do cb:SetChecked(s[key]) end

	local rows = {}
	for _, row in ipairs(CP.Profit:Evaluate()) do
		local keep = true
		if s.profitableOnly and not (row.profit and row.profit > 0) then keep = false end
		if s.hideNoListings and not row.ahMin then keep = false end
		if keep and query ~= "" then
			local hay = (RowName(row) .. " " .. row.entry.char .. " " .. row.entry.prof):lower()
			if not hay:find(query, 1, true) then keep = false end
		end
		if keep then rows[#rows + 1] = row end
	end

	local valueOf, desc = SORT_VALUE[self.sortKey], self.sortDesc
	table.sort(rows, function(a, b)
		local va, vb = valueOf(a), valueOf(b)
		if va == nil and vb == nil then return RowName(a) < RowName(b) end
		if va == nil then return false end
		if vb == nil then return true end
		if va == vb then return RowName(a) < RowName(b) end
		if desc then return va > vb end
		return va < vb
	end)

	for key, b in pairs(self.headers) do
		local col
		for _, c in ipairs(COLUMNS) do if c.key == key then col = c end end
		local arrow = key == self.sortKey and (self.sortDesc and " v" or " ^") or ""
		b.label:SetText(col.label .. arrow)
	end

	for i, data in ipairs(rows) do
		FillRow(self:GetRow(i), data)
	end
	for i = #rows + 1, #self.rows do
		self.rows[i]:Hide()
		self.rows[i].data = nil
	end
	self.content:SetHeight(math.max(1, #rows * ROW_HEIGHT))

	local recipeCount = #CP.Recipes:All()
	if recipeCount == 0 then
		self.frame.footer:SetText("|cffff8040No recipes saved yet. Open each of your profession windows once so CraftProfit can read your recipes.|r")
	elseif not CP.Prices:Snapshot() then
		self.frame.footer:SetText("|cffff8040No auction house scan yet. Go to the auction house and click Scan AH.|r")
	elseif #rows == 0 and s.profitableOnly then
		self.frame.footer:SetText(("None of your %d recipes is profitable at current prices. Untick \"Profitable only\" to see them all."):format(recipeCount))
	else
		self.frame.footer:SetText(("Showing %d of %d recipes. AH cut %g%% (/cp cut). Sell price = lowest buyout; mat cost = cheapest of vendor, AH market price, or crafting it.")
			:format(#rows, recipeCount, s.ahCut * 100))
	end
	self:UpdateStatus()
end

function UI:UpdateStatus()
	if not self.frame then return end
	local sc = CP.Scanner
	self.frame.status:SetText(sc:Status())
	local left = sc:CooldownLeft()
	if sc.state ~= "idle" then
		self.scanButton:SetText("Scanning...")
		self.scanButton:Disable()
	elseif not sc.atAH then
		self.scanButton:SetText("Scan AH")
		self.scanButton:Disable()
	elseif left > 0 then
		self.scanButton:SetText(("Scan in %d:%02d"):format(left / 60, left % 60))
		self.scanButton:Disable()
	else
		self.scanButton:SetText("Scan AH")
		self.scanButton:Enable()
	end
	if self.ahButton then
		self.ahButton:SetText(sc.state ~= "idle" and "Scanning..." or "CraftProfit")
	end
end

function UI:Show()
	self:Create()
	self.frame:Show()
end

function UI:Toggle()
	self:Create()
	self.frame:SetShown(not self.frame:IsShown())
end

-- Button on the auction house window
function UI:AttachToAuctionHouse()
	if self.ahButton or not AuctionHouseFrame then return end
	local b = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
	b:SetSize(110, 22)
	b:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -1)
	b:SetText("CraftProfit")
	b:SetScript("OnClick", function() UI:Toggle() end)
	self.ahButton = b
end

function CP:OnInit()
	UI:Create()
end
