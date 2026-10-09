local _, CP = ...

-- Full auction house scan using C_AuctionHouse.ReplicateItems, which returns a
-- snapshot of every auction. Blizzard allows one every 15 minutes.
local Scanner = { state = "idle", atAH = false }
CP.Scanner = Scanner

local COOLDOWN = 15 * 60
local PER_FRAME = 1500
local TIMEOUT = 90

local function IsSecret(v)
	return issecretvalue and issecretvalue(v)
end

function Scanner:CooldownLeft()
	local last = CP.db and CP.db.lastReplicate or 0
	return math.max(0, last + COOLDOWN - time())
end

function Scanner:Status()
	if self.state == "waiting" then
		return "Waiting for the auction house..."
	elseif self.state == "processing" then
		return ("Reading auctions %d / %d"):format(self.index or 0, self.total or 0)
	end
	local snap = CP.Prices:Snapshot()
	if not snap then return "No scan yet - open the auction house and click Scan." end
	local mins = math.floor((time() - snap.scanTime) / 60)
	local age = mins < 60 and (mins .. "m") or (("%.1fh"):format(mins / 60))
	return ("Last scan %s ago, %d auctions, %d items"):format(age, snap.auctions or 0, snap.itemCount or 0)
end

function Scanner:Start()
	if not self.atAH then
		CP:Print("Open the auction house first.")
		return
	end
	if self.state ~= "idle" then
		CP:Print("A scan is already running.")
		return
	end
	local left = self:CooldownLeft()
	if left > 0 then
		CP:Print(("Blizzard only allows a full scan every 15 minutes - try again in %dm %ds."):format(left / 60, left % 60))
		return
	end
	self.state = "waiting"
	self.startedAt = GetTime()
	CP.db.lastReplicate = time()
	C_AuctionHouse.ReplicateItems()
	CP:Print("Scanning the auction house...")
	CP.UI:UpdateStatus()
	C_Timer.After(TIMEOUT, function()
		if self.state == "waiting" and GetTime() - self.startedAt >= TIMEOUT - 1 then
			self.state = "idle"
			CP:Print("The auction house did not answer the scan. Try again later.")
			CP.UI:UpdateStatus()
		end
	end)
end

function Scanner:Abort(reason)
	self.state = "idle"
	self.worker:SetScript("OnUpdate", nil)
	CP:Print("Scan stopped: " .. reason)
	CP.UI:UpdateStatus()
end

-- Collapse the raw listings into min price, market price (average unit price
-- of the cheapest marketDepth share of quantity) and total quantity.
local function Summarise(listings, depth)
	local items, count = {}, 0
	for itemID, list in pairs(listings) do
		table.sort(list, function(a, b) return a[1] < b[1] end)
		local total = 0
		for _, l in ipairs(list) do total = total + l[2] end
		local want = math.max(1, math.ceil(total * depth))
		local took, spent = 0, 0
		for _, l in ipairs(list) do
			local n = math.min(l[2], want - took)
			took, spent = took + n, spent + n * l[1]
			if took >= want then break end
		end
		items[itemID] = { math.floor(list[1][1]), math.floor(spent / took), total }
		count = count + 1
	end
	return items, count
end

Scanner.worker = CreateFrame("Frame")

function Scanner:Process()
	self.state = "processing"
	self.total = C_AuctionHouse.GetNumReplicateItems()
	self.index = 0
	self.listings = {}
	self.auctions = 0
	CP.UI:UpdateStatus()

	self.worker:SetScript("OnUpdate", function()
		if not self.atAH then
			return self:Abort("the auction house was closed.")
		end
		local last = math.min(self.index + PER_FRAME, self.total)
		for i = self.index, last - 1 do
			-- index is 0-based
			local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
			if itemID and buyout and count and count > 0 and buyout > 0 and not IsSecret(buyout) then
				local list = self.listings[itemID]
				if not list then
					list = {}
					self.listings[itemID] = list
				end
				list[#list + 1] = { buyout / count, count }
				self.auctions = self.auctions + 1
			end
		end
		self.index = last
		CP.UI:UpdateStatus()
		if self.index >= self.total then
			self.worker:SetScript("OnUpdate", nil)
			self:Finish()
		end
	end)
end

function Scanner:Finish()
	local items, count = Summarise(self.listings, CP.db.settings.marketDepth)
	CP.db.prices[CP:RealmKey()] = {
		scanTime = time(),
		auctions = self.auctions,
		itemCount = count,
		items = items,
	}
	self.listings = nil
	self.state = "idle"
	CP:Print(("Scan complete: %d auctions, %d different items."):format(self.auctions, count))
	CP.UI:Show()
	CP.UI:Refresh()
end

CP:On("REPLICATE_ITEM_LIST_UPDATE", function()
	if Scanner.state == "waiting" then
		Scanner:Process()
	end
end)

CP:On("AUCTION_HOUSE_SHOW", function()
	Scanner.atAH = true
	CP.UI:AttachToAuctionHouse()
	CP.UI:UpdateStatus()
end)

CP:On("AUCTION_HOUSE_CLOSED", function()
	Scanner.atAH = false
	if Scanner.state == "waiting" then Scanner.state = "idle" end
	CP.UI:UpdateStatus()
end)
