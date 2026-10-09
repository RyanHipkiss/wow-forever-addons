local _, CP = ...

-- Captures the recipes the current character knows whenever a profession
-- window is opened, and keeps them per character so alts' recipes show too.
local Recipes = {}
CP.Recipes = Recipes

local function BasicReagentType()
	return Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
end

local function ReadRecipe(recipeID)
	local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
	if not info or not info.learned or info.isDummyRecipe or info.isGatheringRecipe
		or info.isSalvageRecipe or info.isRecraft then
		return nil
	end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not schematic or not schematic.outputItemID or schematic.outputItemID == 0 then
		return nil -- enchants and other recipes that don't make an item
	end

	local basic = BasicReagentType()
	local reagents = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		local isBasic = (basic and slot.reagentType == basic) or (not basic and slot.required)
		if isBasic and slot.quantityRequired and slot.quantityRequired > 0 then
			local ids = {}
			for _, r in ipairs(slot.reagents or {}) do
				if r.itemID then ids[#ids + 1] = r.itemID end
			end
			if #ids > 0 then
				reagents[#reagents + 1] = { ids = ids, qty = slot.quantityRequired }
			end
		end
	end
	if #reagents == 0 then return nil end

	local qMin = schematic.quantityMin or 1
	local qMax = schematic.quantityMax or qMin
	return {
		name = schematic.name or info.name,
		out = schematic.outputItemID,
		outQty = math.max((qMin + qMax) / 2, 1),
		reagents = reagents,
	}
end

function Recipes:Capture()
	if not C_TradeSkillUI then return end
	if (C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked())
		or (C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild())
		or (C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting()) then
		return -- someone else's recipes
	end

	local prof = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	local profName = prof and prof.professionName
	if not profName or profName == "" then
		local child = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
		profName = child and (child.parentProfessionName or child.professionName)
	end
	if not profName or profName == "" then return end

	local getIDs = C_TradeSkillUI.GetAllRecipeIDs or C_TradeSkillUI.GetFilteredRecipeIDs
	local ids = getIDs and getIDs() or {}
	local recipes, n = {}, 0
	for _, recipeID in ipairs(ids) do
		local r = ReadRecipe(recipeID)
		if r then
			recipes[recipeID] = r
			n = n + 1
		end
	end
	if n == 0 then return end -- list not ready yet; a later update will fire

	local char = CP.db.chars[CP:CharKey()] or { professions = {} }
	CP.db.chars[CP:CharKey()] = char
	local old = char.professions[profName]
	local oldCount = 0
	if old then for _ in pairs(old.recipes) do oldCount = oldCount + 1 end end
	char.professions[profName] = { updated = time(), recipes = recipes }
	if n ~= oldCount then
		CP:Print(("Saved %d %s recipes."):format(n, profName))
	end
	CP.UI:Refresh()
end

-- All saved recipes across characters: list of { id, recipe, char, prof }.
function Recipes:All()
	local list = {}
	for charKey, char in pairs(CP.db.chars) do
		for profName, prof in pairs(char.professions or {}) do
			for id, r in pairs(prof.recipes) do
				list[#list + 1] = { id = id, recipe = r, char = charKey:match("^[^-]+"), prof = profName }
			end
		end
	end
	return list
end

local pending = false
local function QueueCapture()
	if pending then return end
	pending = true
	C_Timer.After(1, function()
		pending = false
		Recipes:Capture()
	end)
end

CP:On("TRADE_SKILL_SHOW", QueueCapture)
CP:On("TRADE_SKILL_LIST_UPDATE", QueueCapture)
CP:On("TRADE_SKILL_DATA_SOURCE_CHANGED", QueueCapture)
CP:On("NEW_RECIPE_LEARNED", QueueCapture)
