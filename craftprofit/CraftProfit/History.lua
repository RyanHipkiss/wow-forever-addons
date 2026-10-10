local _, CP = ...

-- Keeps a daily record of every recipe's profit and the prices of the items
-- involved, so the browser dashboard can chart them. WoW writes this to
-- WTF\Account\<account>\SavedVariables\CraftProfit.lua on /reload or logout.
local History = {}
CP.History = History

local KEEP_DAYS = 400

local function Today()
	return date("%Y-%m-%d")
end

local function Round(v)
	return v and math.floor(v + 0.5) or nil
end

function History:Realm()
	local key = CP:RealmKey()
	CP.db.history[key] = CP.db.history[key] or { recipes = {}, days = {}, prices = {}, items = {}, scans = {} }
	return CP.db.history[key]
end

local function RememberItem(h, itemID)
	local name, _, quality = CP:ItemInfo(itemID)
	local item = h.items[itemID] or {}
	item.name = name or item.name
	item.quality = quality or item.quality
	h.items[itemID] = item
end

local function RecordPrice(h, itemID, day)
	local ah = CP.Prices:AH(itemID)
	if not ah then return end
	h.prices[itemID] = h.prices[itemID] or {}
	h.prices[itemID][day] = { min = ah[1], mkt = ah[2], qty = ah[3] }
end

local function Prune(byDay, cutoff)
	for day in pairs(byDay) do
		if day < cutoff then byDay[day] = nil end
	end
end

-- Called after every completed scan. The last scan of a day wins.
function History:Record()
	local h = self:Realm()
	local day = Today()
	local snap = CP.Prices:Snapshot()

	for _, row in ipairs(CP.Profit:Evaluate()) do
		local e, r = row.entry, row.entry.recipe
		local mats = {}
		for _, l in ipairs(row.lines or {}) do
			mats[#mats + 1] = { id = l.id, qty = l.qty, unit = Round(l.unit), source = l.source }
			RememberItem(h, l.id)
			RecordPrice(h, l.id, day)
		end
		RememberItem(h, r.out)
		RecordPrice(h, r.out, day)

		h.recipes[e.id] = {
			name = r.name,
			item = r.out,
			outQty = r.outQty,
			char = e.char,
			prof = e.prof,
			mats = mats,
			sellSource = row.sellSource,
		}
		h.days[e.id] = h.days[e.id] or {}
		h.days[e.id][day] = {
			profit = Round(row.profit),
			cost = Round(row.cost),
			revenue = Round(row.revenue),
			listed = row.listed,
			ahMin = row.ahMin,
			t = time(),
		}
	end

	table.insert(h.scans, { t = time(), auctions = snap and snap.auctions, items = snap and snap.itemCount })
	while #h.scans > 200 do table.remove(h.scans, 1) end

	local cutoff = date("%Y-%m-%d", time() - KEEP_DAYS * 86400)
	for _, byDay in pairs(h.days) do Prune(byDay, cutoff) end
	for _, byDay in pairs(h.prices) do Prune(byDay, cutoff) end
end
