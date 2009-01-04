--[[ 
	Action Bar Saver, Mayen (Horde) from Icecrown (US) PvE
]]

ABS = LibStub("AceAddon-3.0"):NewAddon("ABS")

local L = ActionBarSaverLocals

local companions = {"critter", "mount"}
local restoreErrors, spellCache, macroCache, highestRanks = {}, {}, {}, {}
local iconCache, playerClass

local MAX_MACROS = 54
local MAX_CHAR_MACROS = 18
local MAX_GLOBAL_MACROS = 36

function ABS:OnInitialize()
	self.defaults = {
		profile = {
			macro = false,
			checkCount = false,
			restoreRank = true,
			
			spellSubs = {},
			sets = {UNKNOWN = {}},
		},
	}

	self.db = LibStub:GetLibrary("AceDB-3.0"):New("ActionBarSaverDB", self.defaults)
	self.db:SetProfile("Global")
	
	for name in pairs(RAID_CLASS_COLORS) do
		self.db.profile.sets[name] = self.db.profile.sets[name] or {}
	end

	-- Upgrade
	if( ActionBSDB ) then
		for name, data in pairs(ActionBSDB.profiles) do
			local actionData = {}
			for id, line in pairs(data) do
				local arg1, type, arg3 = string.split(":", line)
				if( type == "spell" ) then
					actionData[id] = string.format("%s|%d||%s", type, arg1, string.gsub(arg3 or "", "|;|", ":"))	
				elseif( type == "item" ) then
					actionData[id] = string.format("%s|%d||%s", type, arg1, string.gsub(arg3 or "", "|;|", ":"))
				elseif( type == "macro" ) then
					local macro = select(5, string.split("||", string.gsub(arg3 or "", "|;|", ":")))
					if( macro ) then
						-- Strip the last /n to prevent any ID issues
						macro = string.gsub(macro, "/n$", "")
						actionData[id] = string.format("%s|%d||%s", type, arg1, macro)
					end
				end
				
			end
			
			self.db.profile.sets.UNKNOWN[name] = actionData
		end
		
		self:Print(L["Your DB has been upgraded to the new storage format."])
		ActionBSDB = nil
	end
	
	playerClass = select(2, UnitClass("player"))
	
	-- Wait until now so we're sure the sets are filled in
	self:LoadBazaar()
end

-- Text "compression" so it can be stored in our format fine
function ABS:CompressText(text)
	text = string.gsub(text, "\n", "/n")
	text = string.gsub(text, "/n$", "")
	text = string.gsub(text, "||", "/124")
	
	return string.trim(text)
end

function ABS:UncompressText(text)
	text = string.gsub(text, "/n", "\n")
	text = string.gsub(text, "/124", "|")
	
	return string.trim(text)
end

function ABS:GetCompanionInfo(id)
	if( not self.tooltip ) then
		self.tooltip = CreateFrame("GameTooltip", "ABSTooltip", UIParent, "GameTooltipTemplate")
		self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	
	self.tooltip:SetAction(id)
	
	local text = ABSTooltipTextLeft1:GetText()
	if( not text ) then
		return
	end
	
	for _, type in pairs(companions) do
		for i=1, GetNumCompanions(type) do
			local id, name, spellID, icon, isActive = GetCompanionInfo(type, i)
			self.tooltip:SetHyperlink(string.format("spell:%d", spellID))
			
			if( text == ABSTooltipTextLeft1:GetText() ) then
				return type, i, text
			end
		end
	end
end

-- Restore a saved profile
function ABS:SaveProfile(name)
	self.db.profile.sets[playerClass][name] = self.db.profile.sets[playerClass][name] or {}
	local set = self.db.profile.sets[playerClass][name]
	
	for id=1, 120 do
		set[id] = nil
		
		local type, actionID = GetActionInfo(id)
		if( type and actionID ) then
			local binding = ""
			
			-- If actionID is 0, it's likely a companion, if we can find the companion then we process it
			-- otherwise will pass it to our standard handler
			if( type == "spell" and actionID == 0 ) then
				local newType, newID, newName = self:GetCompanionInfo(id)
				if( newType ) then
					set[id] = string.format("%s|%d|%s|%s", newType, newID, binding, newName)
					type = ""
				end
			end
			
			if( type == "spell" ) then
				local spell, rank = GetSpellName(actionID, BOOKTYPE_SPELL)
				if( spell ) then
					set[id] = string.format("%s|%d|%s|%s|%s", type, actionID, binding, spell or "", rank or "")
				end
			elseif( type == "item" ) then
				set[id] = string.format("%s|%d|%s|%s", type, actionID, binding, (GetItemInfo(actionID)) or "")
			elseif( type == "macro" ) then
				local name, icon, macro = GetMacroInfo(actionID)
				if( name and icon and macro ) then
					set[id] = string.format("%s|%d|%s|%s|%s|%s", type, actionID, binding, self:CompressText(name), icon, self:CompressText(macro))
				end
			end
		end
	end
	
	self:Print(string.format(L["Saved profile %s!"], name))
end

-- Finds the macroID in case it's changed
function ABS:FindMacro(id, data)
	if( macroCache[id] == data ) then
		return id
	end
	
	-- No such luck, check text
	for id, currentMacro in pairs(macroCache) do
		if( currentMacro == data ) then
			return id
		end
	end
	
	return nil
end

-- Restore any macros that don't exist
function ABS:RestoreMacros(set)
	local perCharacter = true
	for id, data in pairs(set) do
		local type, id, binding, macroName, macroIcon, macroData = string.split("|", data)
		if( type == "macro" ) then
			-- Do we already have a macro?
			local macroID = self:FindMacro(id, macroData)
			if( not macroID ) then
				local globalNum, charNum = GetNumMacros()
				-- Make sure we aren't at the limit
				if( globalNum == MAX_GLOBAL_MACROS and charNum == MAX_CHAR_MACROS ) then
					table.insert(restoreErrors, L["Unable to restore macros, you already have 18 global and 18 per character ones created."])
					break

				-- We ran out of space for per character, so use global
				elseif( charNum == MAX_CHAR_MACROS ) then
					perCharacter = false
				end

				-- When creating a macro, we have to pass the icon id not the icon path
				if( not iconCache ) then
					iconCache = {}
					for i=1, GetNumMacroIcons() do
						iconCache[(GetMacroIconInfo(i))] = i
					end
				end
				
				macroName = self:UncompressText(macroName)
				CreateMacro(macroName == "" and " " or macroName, iconCache[macroIcon] or 1, self:UncompressText(macroData), nil, perCharacter)
			end
		end
	end
	
	-- Recache macros due to any additions
	for i=1, MAX_MACROS do
		local macro = select(3, GetMacroInfo(i))
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
end

-- Restore a saved profile
function ABS:RestoreProfile(name, overrideClass)
	local set = self.db.profile.sets[overrideClass or playerClass][name]
	if( not set ) then
		self:Print(string.format(L["No profile with the name \"%s\" exists."], set))
		return
	elseif( InCombatLockdown() ) then
		self:Print(String.format(L["Unable to restore profile \"%s\", you are in combat."], set))
		return
	end
	
	-- Cache spells
	for k in pairs(spellCache) do spellCache[k] = nil end
	
	for book=1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(book)

		for i=1, numSpells do
			local index = offset + i
			local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)
			
			-- This way we restore the max rank of spells
			spellCache[spell] = index
			spellCache[string.lower(spell)] = index
			
			if( rank and rank ~= "" ) then
				spellCache[spell .. rank] = index
			end
		end
	end
		
	
	-- Cache macros
	for i=1, MAX_MACROS do
		local macro = select(3, GetMacroInfo(i))
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
	
	-- Check if we need to restore any missing macros
	if( self.db.profile.macro ) then
		self:RestoreMacros(set)
	end
	
	-- Start fresh with nothing on the cursor
	ClearCursor()
	
	for i=1, 120 do
		local type, id = GetActionInfo(i)
		
		-- Clear the current spot
		if( id or type ) then
			PickupAction(i)
			ClearCursor()
		end
		
		if( set[i] ) then
			self:RestoreAction(i, string.split("|", set[i]))
		end
	end
	
	
	-- Done!
	if( #(restoreErrors) == 0 ) then
		self:Print(string.format(L["Restored profile %s!"], name))
	else
		self:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /abs errors for more information."], name, #(restoreErrors)))
	end
end

function ABS:RestoreAction(i, type, actionID, binding, arg1, arg2, arg3)
	if( type == "spell" ) then
		-- Restore the highest rank first if we can, or the specific rank otherwise
		if( self.db.profile.restoreRank ) then
			if( spellCache[arg1] ) then
				PickupSpell(spellCache[arg1], BOOKTYPE_SPELL)
			elseif( arg2 ~= "" and spellCache[arg1 .. arg2] ) then
				PickupSpell(spellCache[arg1 .. arg2], BOOKTYPE_SPELL)
			end
		-- Restore the rank we saved
		else
			if( arg2 ~= "" and spellCache[arg1 .. arg2] ) then
				PickupSpell(spellCache[arg1 .. arg2], BOOKTYPE_SPELL)
			elseif( spellCache[arg1] ) then
				PickupSpell(spellCache[arg1], BOOKTYPE_SPELL)
			end
		end
		
		if( GetCursorInfo() ~= type ) then
			-- Bad restore, check if we should link at all
			local lowerSpell = string.lower(arg1)
			for spell, linked in pairs(self.db.profile.spellSubs) do
				if( lowerSpell == spell and spellCache[linked] ) then
					self:RestoreAction(i, type, actionID, binding, linked, nil, arg3)
					return
				elseif( lowerSpell == linked and spellCache[spell] ) then
					self:RestoreAction(i, type, actionID, binding, spell, nil, arg3)
					return
				end
			end
			
			table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], arg1, i))
			ClearCursor()
			return
		end

		PlaceAction(i)
	
	elseif( type == "critter" or type == "mount" ) then
		PickupCompanion(type, actionID)
		if( GetCursorInfo() ~= "spell" ) then
			table.insert(restoreErrors, string.format(L["Unable to restore companion \"%s\" to slot #%d, it does not appear to exist yet."], arg1, i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
	elseif( type == "item" ) then
		PickupItem(actionID)

		if( GetCursorInfo() ~= type ) then
			table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], arg1 and arg1 ~= "" and arg1 or actionID, i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
		
	elseif( type == "macro" ) then
		PickupMacro(self:FindMacro(actionID, arg3) or -1)
		
		if( GetCursorInfo() ~= type ) then
			table.insert(restoreErrors, string.format(L["Unable to restore macro id #%d to slot #%d, it appears to have been deleted."], actionID, i))
			ClearCursor()
			return
		end
		
		PlaceAction(i)
	end
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS|r: " .. msg)
end

SLASH_ABS1 = "/abs"
SLASH_ABS2 = "/actionbarsaver"
SlashCmdList["ABS"] = function(msg)
	msg = msg or ""
	
	local cmd, arg1 = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")
	arg1 = string.lower(arg1 or "")
	
	local self = ABS
	
	-- Profile saving
	if( cmd == "save" and arg1 ~= "" ) then
		self:SaveProfile(arg1)
	
	-- Spell sub
	elseif( cmd == "link" and arg1 ~= "" ) then
		local first, second = string.match(arg1, "\"(.+)\" \"(.+)\"")
		first = string.trim(first or "")
		second = string.trim(second or "")
		
		if( first == "" or second == "" ) then
			self:Print(L["Invalid spells passed, remember you must put quotes around both of them."])
			return
		end
		
		self.db.profile.spellSubs[first] = second
		
		self:Print(string.format(L["Spells \"%s\" and \"%s\" are now linked."], first, second))
		
	-- Profile restoring
	elseif( cmd == "restore" and arg1 ~= "" ) then
		for i=#(restoreErrors), 1, -1 do table.remove(restoreErrors, i) end
		
		-- Backwards compat with the old versions format
		local profileCat = playerClass
		if( not self.db.profile.sets[playerClass][arg1] and self.db.profile.sets.UNKNOWN[arg1] ) then
			profileCat = "UNKNOWN"
		end
		
		if( not self.db.profile.sets[profileCat][arg1] ) then
			self:Print(string.format(L["Cannot restore profile \"%s\", you can only restore profiles saved to your class."], arg1))
			return
		end
		
		self:RestoreProfile(arg1, profileCat)
		
		-- No errors, copy it to the new format
		if( #(restoreErrors) == 0 ) then
			if( overrideClass == "UNKNOWN" ) then
				if( not self.db.profile.sets[playerClass][name] ) then
					self.db.profile.sets[playerClass][name] = CopyTable(set)
					self.db.profile.sets[profileCat][name] = nil
				end

				self:Print(string.format(L["The profile %s has been moved from the unknown category to %s."], name, (UnitClass("player"))))
			end
		end

	-- Profile renaming
	elseif( cmd == "rename" and arg1 ~= "" ) then
		local old, new = string.split(" ", arg1, 2)
		new = string.trim(new or "")
		old = string.trim(old or "")
		
		if( new == old ) then
			self:Print(string.format(L["You cannot rename \"%s\" to \"%s\" they are the same profile names."], old, new))
			return
		elseif( new == "" ) then
			self:Print(string.format(L["No name specified to rename \"%s\" to."], old))
			return
		elseif( self.db.profile.sets[playerClass][new] ) then
			self:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], old, new, (UnitClass("player"))))
			return
		elseif( not self.db.profile.sets.UNKNOWN[old] and not self.db.profile.sets[playerClass][old] ) then
			self:Print(string.format(L["No profile with the name \"%s\" exists."], old))
			return
		end
		
		-- Backwards compat
		local profileCat = playerClass
		local isListed = ""
		if( self.db.profile.sets.UNKNOWN[old] and not self.db.profile.sets[playerClass][old] ) then
			profileCat = "UNKNOWN"
			isListed = string.format(L["Also moved from the unknown category to %s."], (UnitClass("player")))
		end
		
		self.db.profile.sets[playerClass][new] = CopyTable(self.db.profile.sets[profileCat][old])
		self.db.profile.sets[profileCat][old] = nil
		
		self:Print(string.format(L["Renamed \"%s\" to \"%s\". %s"], old, new, isListed))
		
	-- Restore errors
	elseif( cmd == "errors" ) then
		if( #(restoreErrors) == 0 ) then
			self:Print(L["No errors found!"])
			return
		end

		self:Print(string.format(L["Errors found: %d"], #(restoreErrors)))
		for _, text in pairs(restoreErrors) do
			DEFAULT_CHAT_FRAME:AddMessage(text)
		end

	-- Delete profile
	elseif( cmd == "delete" ) then
		self.db.profile.sets.UNKNOWN[arg1] = nil
		self.db.profile.sets[playerClass][arg1] = nil
		self:Print(string.format(L["Deleted saved profile %s."], arg1))
	
	-- List profiles
	elseif( cmd == "list" ) then
		local classes = {}
		local setList = {}
		
		for class, sets in pairs(self.db.profile.sets) do
			table.insert(classes, class)
		end
		
		table.sort(classes, function(a, b)
			return a < b
		end)
		
		for _, class in pairs(classes) do
			for i=#(setList), 1, -1 do table.remove(setList, i) end
			for setName in pairs(self.db.profile.sets[class]) do
				table.insert(setList, setName)
			end
			
			if( #(setList) > 0 ) then
				DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99%s|r: %s", L[class] or "???", table.concat(setList, ", ")))
			end
		end
		
	-- Macro restoring
	elseif( cmd == "macro" ) then
		self.db.profile.macro = not self.db.profile.macro

		if( self.db.profile.macro ) then
			self:Print(L["Auto macro restoration is now enabled!"])
		else
			self:Print(L["Auto macro restoration is now disabled!"])
		end
	
	-- Item counts
	elseif( cmd == "count" ) then
		self.db.profile.checkCount = not self.db.profile.checkCount

		if( self.db.profile.checkCount ) then
			self:Print(L["Checking item count is now enabled!"])
		else
			self:Print(L["Checking item count is now disabled!"])		
		end
	
	-- Rank restore
	elseif( cmd == "rank" ) then
		self.db.profile.restoreRank = not self.db.profile.restoreRank
		
		if( self.db.profile.restoreRank ) then
			self:Print(L["Auto restoring highest spell rank is now enabled!"])
		else
			self:Print(L["Auto restoring highest spell rank is now disabled!"])
		end
		
	-- Halp
	else
		self:Print(L["Slash commands"])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rename <oldProfile> <newProfile> - Renames a saved profile from oldProfile to newProfile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs link \"<spell 1>\" \"<spell 2>\" - Links a spell with another, INCLUDE QUOTES for example you can use \"Shadowmeld\" \"War Stomp\" so if War Stomp can't be found, it'll use Shadowmeld and vica versa."])
		--DEFAULT_CHAT_FRAME:AddMessage(L["/abs test <profile> - Tests restoring a profile, results will be outputted to chat."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rank - Toggles if ABS should restore the highest rank of the spell, or the one saved originally."])
		--DEFAULT_CHAT_FRAME:AddMessage(L["/abs errors - Lists the errors that happened on the last restore (if any)."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
	end
end

-- Bazaar support
function ABS:LoadBazaar()
	if( not Bazaar ) then
		return
	end
	
	local Config = {}
	function Config:Receive(data, categories)
		local self = ABS
		
		for key in pairs(categories) do
			if( key == "general" ) then
				self.db.profile.macro = data.general.macro
				self.db.profile.checkCount = data.general.checkCount
				
				-- Load our spells into this
				for first, second in pairs(data.general.spellSubs) do
					self.db.profile.spellSubs[first] = second
				end
			else
				-- Merge the profiles
				for name, data in pairs(data[key]) do
					-- We already have a profile with this name, so append (sync) to it
					if( self.db.profile.sets[key][name] ) then
						name = string.format("(sync) %s", name)
					end
					
					self.db.profile.sets[key][name] = data
				end
			end
		end
	end

	function Config:Send(categories)
		local config = {}
		local self = ABS
		
		for key in pairs(categories) do
			if( key == "general" ) then
				config.general = {}
				config.general.macro = self.db.profile.macro
				config.general.checkCount = self.db.profile.checkCount
				config.general.spellSubs = CopyTable(self.db.profile.spellSubs)
			elseif( self.db.profile.sets[key] ) then
				config[key] = CopyTable(self.db.profile.sets[key])
			end
		end

		return config
	end

	local obj = Bazaar:RegisterAddOn("ActionBarSaver")
	obj:RegisterCategory("general", "General")
	
	for name in pairs(self.db.profile.sets) do
		obj:RegisterCategory(name, string.format(L["%s Profiles"], L[name] or name))
	end
	
	obj:RegisterReceiveHandler(Config, "Receive")
	obj:RegisterSendHandler(Config, "Send")
end