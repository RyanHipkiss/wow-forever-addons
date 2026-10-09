local _, CP = ...

local Prices = {}
CP.Prices = Prices

function Prices:Snapshot()
	return CP.db.prices[CP:RealmKey()]
end

-- Returns { min, mkt, qty } for an item from the latest AH scan, or nil.
function Prices:AH(itemID)
	local snap = self:Snapshot()
	return snap and snap.items[itemID]
end

function Prices:Vendor(itemID)
	return CP.db.vendor[itemID]
end

-- Record what merchants charge, so vendor mats (thread, vials, flux...) get priced.
local function RecordMerchant()
	local getInfo = C_MerchantFrame and C_MerchantFrame.GetItemInfo
	for i = 1, GetMerchantNumItems() do
		local price, stack, available, extended
		if getInfo then
			local info = getInfo(i)
			if info then
				price, stack, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
			end
		else
			local _
			_, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
		end
		local link = GetMerchantItemLink(i)
		local itemID = link and C_Item.GetItemInfoInstant(link)
		-- Only unlimited-stock items bought with gold give a dependable price.
		if itemID and price and price > 0 and not extended and available == -1 then
			CP.db.vendor[itemID] = price / math.max(stack or 1, 1)
		end
	end
end

CP:On("MERCHANT_SHOW", function() C_Timer.After(0.3, RecordMerchant) end)
CP:On("MERCHANT_UPDATE", function() RecordMerchant() end)
