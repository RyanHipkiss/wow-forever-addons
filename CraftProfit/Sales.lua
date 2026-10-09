local _, CP = ...

-- Records your own auction sales from "Auction successful" mails. WoW doesn't
-- tell addons what other players' items sold for, so only your sales are known.
-- Open your mailbox before taking the gold so the mails can be read.
local Sales = {}
CP.Sales = Sales

local MAIL_DAYS = 30      -- auction house mail expires after 30 days
local KEEP_DAYS = 400
local SAME_SALE_WINDOW = 3600

function Sales:Realm()
	local key = CP:RealmKey()
	CP.db.sales[key] = CP.db.sales[key] or {}
	return CP.db.sales[key]
end

-- Find an item ID from a name, using items CraftProfit has already seen.
local function ItemIDByName(name)
	local h = CP.db.history[CP:RealmKey()]
	if h then
		for id, item in pairs(h.items) do
			if item.name == name then return tonumber(id) end
		end
	end
	return C_Item.GetItemInfoInstant(name)
end

local function IsDuplicate(list, sale)
	for i = #list, math.max(1, #list - 1000), -1 do
		local s = list[i]
		if s.name == sale.name and s.price == sale.price and s.count == sale.count
			and math.abs(s.t - sale.t) < SAME_SALE_WINDOW then
			return true
		end
	end
	return false
end

function Sales:ScanInbox()
	local list = self:Realm()
	local added = 0
	for i = 1, GetInboxNumItems() do
		local invoiceType, itemName, _, bid, _, _, _, _, _, _, count = GetInboxInvoiceInfo(i)
		if invoiceType == "seller" and itemName and bid and bid > 0 then
			local daysLeft = select(7, GetInboxHeaderInfo(i)) or MAIL_DAYS
			local sale = {
				name = itemName,
				item = ItemIDByName(itemName),
				count = count or 1,
				price = bid, -- what the buyer paid, before the AH cut
				t = time() - math.floor((MAIL_DAYS - daysLeft) * 86400),
			}
			if not IsDuplicate(list, sale) then
				list[#list + 1] = sale
				added = added + 1
			end
		end
	end

	local cutoff = time() - KEEP_DAYS * 86400
	for i = #list, 1, -1 do
		if list[i].t < cutoff then table.remove(list, i) end
	end
	if added > 0 then
		CP:Print(("Recorded %d auction sale%s."):format(added, added == 1 and "" or "s"))
	end
end

local pending = false
CP:On("MAIL_INBOX_UPDATE", function()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		Sales:ScanInbox()
	end)
end)
