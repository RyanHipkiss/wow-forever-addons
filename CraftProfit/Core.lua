local ADDON, CP = ...
_G.CraftProfit = CP

CP.version = "0.1.0"

local DEFAULTS = {
	settings = {
		ahCut = 0.05,          -- auction house cut taken from the sale
		marketDepth = 0.15,    -- share of listed quantity averaged for the "market" price
		useCraftedMats = true, -- price a mat at its own craft cost if that is cheaper
		profitableOnly = false,
		hideNoListings = false,
	},
	prices = {},   -- [realmKey] = { scanTime, auctions, items = { [itemID] = { min, mkt, qty } } }
	vendor = {},   -- [itemID] = unit price paid to a merchant
	chars = {},    -- [charKey] = { professions = { [name] = { updated, recipes = { [recipeID] = recipe } } } }
}

local function ApplyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			ApplyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

function CP:Print(...)
	print("|cff33ff99CraftProfit|r:", ...)
end

function CP:RealmKey()
	return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
end

function CP:CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Money -----------------------------------------------------------------------

function CP:Money(copper)
	if not copper then return "|cff808080--|r" end
	copper = math.floor(copper + 0.5)
	if copper < 0 then
		return "|cffff4040-|r" .. GetMoneyString(-copper, true)
	end
	return GetMoneyString(copper, true)
end

-- Item info (loads asynchronously; the UI refreshes when data arrives) -------

local pendingLoads = {}

function CP:ItemInfo(itemID)
	local name, link, quality, _, _, _, _, _, _, icon, sellPrice = C_Item.GetItemInfo(itemID)
	if not name and not pendingLoads[itemID] then
		pendingLoads[itemID] = true
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return name, link, quality, icon or C_Item.GetItemIconByID(itemID), sellPrice
end

-- Events ---------------------------------------------------------------------

local frame = CreateFrame("Frame")
CP.eventFrame = frame
local handlers = {}

function CP:On(event, fn)
	handlers[event] = handlers[event] or {}
	table.insert(handlers[event], fn)
	frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(CP, ...)
	end
end)

CP:On("ADDON_LOADED", function(self, name)
	if name ~= ADDON then return end
	CraftProfitDB = CraftProfitDB or {}
	ApplyDefaults(CraftProfitDB, DEFAULTS)
	self.db = CraftProfitDB
	if self.OnInit then self:OnInit() end
end)

local refreshQueued = false
CP:On("ITEM_DATA_LOAD_RESULT", function(self, itemID)
	if not pendingLoads[itemID] then return end
	pendingLoads[itemID] = nil
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0.5, function()
		refreshQueued = false
		if self.UI and self.UI.Refresh then self.UI:Refresh() end
	end)
end)

-- Slash commands -------------------------------------------------------------

SLASH_CRAFTPROFIT1 = "/cp"
SLASH_CRAFTPROFIT2 = "/craftprofit"
SlashCmdList.CRAFTPROFIT = function(msg)
	local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then
		CP.UI:Toggle()
	elseif cmd == "scan" then
		CP.Scanner:Start()
	elseif cmd == "cut" then
		local pct = tonumber(rest)
		if pct and pct >= 0 and pct < 100 then
			CP.db.settings.ahCut = pct / 100
			CP:Print(("Auction house cut set to %g%%."):format(pct))
			CP.UI:Refresh()
		else
			CP:Print(("Auction house cut is %g%%. Use /cp cut <percent>."):format(CP.db.settings.ahCut * 100))
		end
	elseif cmd == "vendor" then
		-- /cp vendor <item link or id> <copper>
		local id = tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)"))
		local price = tonumber(rest:match("(%d+)%s*$"))
		if id and price and rest:match("%s%d+%s*$") then
			CP.db.vendor[id] = price
			CP:Print(("Vendor price for item %d set to %s."):format(id, CP:Money(price)))
			CP.UI:Refresh()
		else
			CP:Print("Usage: /cp vendor <item link or ID> <price in copper>")
		end
	elseif cmd == "forget" then
		CP.db.chars[CP:CharKey()] = nil
		CP:Print("Forgot this character's recipes. Open your profession windows to capture them again.")
		CP.UI:Refresh()
	else
		CP:Print("/cp - toggle window, /cp scan - scan the AH (must be at the AH), /cp cut <pct>, /cp vendor <item> <copper>, /cp forget")
	end
end
