local _, CP = ...

local Profit = {}
CP.Profit = Profit

local MAX_DEPTH = 3

-- itemID -> recipe that makes it (first found), for pricing crafted mats.
local function BuildProducerIndex(all)
	local index = {}
	for _, e in ipairs(all) do
		if not index[e.recipe.out] then index[e.recipe.out] = e end
	end
	return index
end

-- Cheapest way to get one of itemID: buy at a vendor, buy on the AH, or craft it.
-- Returns unitCost, source ("vendor" | "ah" | "craft") or nil when unpriced.
function Profit:BuyCost(itemID, ctx, depth)
	depth = depth or 0
	local best, source
	local v = CP.Prices:Vendor(itemID)
	if v then best, source = v, "vendor" end
	local ah = CP.Prices:AH(itemID)
	if ah and (not best or ah[2] < best) then best, source = ah[2], "ah" end

	if CP.db.settings.useCraftedMats and depth < MAX_DEPTH and not ctx.visiting[itemID] then
		local producer = ctx.producers[itemID]
		if producer then
			ctx.visiting[itemID] = true
			local cost = self:RecipeCost(producer.recipe, ctx, depth + 1)
			ctx.visiting[itemID] = nil
			if cost then
				local unit = cost / producer.recipe.outQty
				if not best or unit < best then best, source = unit, "craft" end
			end
		end
	end
	return best, source
end

-- Total cost of one craft, plus per-reagent breakdown and missing mats.
function Profit:RecipeCost(recipe, ctx, depth)
	local total, missing, lines = 0, nil, {}
	for _, slot in ipairs(recipe.reagents) do
		local bestUnit, bestSrc, bestID
		for _, id in ipairs(slot.ids) do
			local unit, src = self:BuyCost(id, ctx, depth)
			if unit and (not bestUnit or unit < bestUnit) then
				bestUnit, bestSrc, bestID = unit, src, id
			end
		end
		if bestUnit then
			total = total + bestUnit * slot.qty
		else
			missing = missing or {}
			missing[#missing + 1] = slot.ids[1]
		end
		lines[#lines + 1] = { id = bestID or slot.ids[1], qty = slot.qty, unit = bestUnit, source = bestSrc }
	end
	if missing then return nil, lines, missing end
	return total, lines
end

-- Evaluate every saved recipe. Each row:
-- { entry, cost, lines, missing, sellUnit, sellSource, revenue, profit, margin, listed }
function Profit:Evaluate()
	local all = CP.Recipes:All()
	local ctx = { producers = BuildProducerIndex(all), visiting = {} }
	local cut = CP.db.settings.ahCut
	local rows = {}

	for _, e in ipairs(all) do
		local r = e.recipe
		local cost, lines, missing = self:RecipeCost(r, ctx, 0)
		local ah = CP.Prices:AH(r.out)
		local _, _, _, _, vendorSell = CP:ItemInfo(r.out)

		local sellUnit, sellSource
		if ah then
			sellUnit, sellSource = ah[1] * (1 - cut), "ah"
		end
		if vendorSell and vendorSell > 0 and (not sellUnit or vendorSell > sellUnit) then
			sellUnit, sellSource = vendorSell, "vendor"
		end

		local row = {
			entry = e,
			cost = cost,
			lines = lines,
			missing = missing,
			ahMin = ah and ah[1],
			ahMkt = ah and ah[2],
			listed = ah and ah[3] or 0,
			sellUnit = sellUnit,
			sellSource = sellSource,
		}
		if sellUnit then
			row.revenue = sellUnit * r.outQty
			if cost then
				row.profit = row.revenue - cost
				row.margin = cost > 0 and row.profit / cost or nil
			end
		end
		rows[#rows + 1] = row
	end
	return rows
end
