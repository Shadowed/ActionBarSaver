--[[ 
	Action Bar Saver, Shadowed
]]
ActionBarSaver = select(2, ...)

local ABS = ActionBarSaver
local L = ABS.L

local restoreErrors, spellCache, macroCache, macroNameCache, highestRanks = {}, {}, {}, {}, {}
local playerClass

local MAX_MACROS = 54
local MAX_CHAR_MACROS = 18
local MAX_GLOBAL_MACROS = 36
local MAX_ACTION_BUTTONS = 144
local POSSESSION_START = 121
local POSSESSION_END = 132

local MAX_CHAR_MACROS = MAX_CHARACTER_MACROS
local MAX_GLOBAL_MACROS = MAX_ACCOUNT_MACROS
local MAX_MACROS = MAX_CHAR_MACROS + MAX_GLOBAL_MACROS

function ABS:OnInitialize()
	local defaults = {
		macro = false,
		checkCount = false,
		restoreRank = false,
		spellSubs = {},
		sets = {}
	}
	
	ActionBarSaverDB = ActionBarSaverDB or {}
		
	-- Load defaults in
	for key, value in pairs(defaults) do
		if( ActionBarSaverDB[key] == nil ) then
			ActionBarSaverDB[key] = value
		end
	end
	
	for classToken in pairs(RAID_CLASS_COLORS) do
		ActionBarSaverDB.sets[classToken] = ActionBarSaverDB.sets[classToken] or {}
	end
	
	self.db = ActionBarSaverDB
	
	playerClass = select(2, UnitClass("player"))
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


function macroContainsClassSpell(macroBody)
	for spellName, id in pairs(spellCache) do
		if string.find(macroBody, spellName) then
			return true
		end
	end
end


-- Restore a saved profile
function ABS:SaveProfile(name)
	self:CreateSpellCache()
	self.db.sets[playerClass][name] = self.db.sets[playerClass][name] or {}
	local set = self.db.sets[playerClass][name]
	for actionID = 1, MAX_ACTION_BUTTONS do
		set[actionID] = nil
		local type, id, subType, extraID = GetActionInfo(actionID)
		if( type and id and ( actionID < POSSESSION_START or actionID > POSSESSION_END ) ) then
			-- DB Format: <type>|<id>|<binding>|<name>|<extra ...>
			--save a mount
	--		print(type, subType)
			if( type == "summonmount" ) or (subType == "MOUNT") then
				--Blizzard uses two different methods for mounts, so catch it either way. 
				set[actionID] = string.join("|", "MOUNT", id) --mount must be all caps! GetCursorInfo returns it as all caps when restoring
			--save a battle pet(non-combat pets)
			elseif( type == "summonpet" ) then
				set[actionID] = string.join("|", "battlepet", id)
			-- Save a companion
			elseif( type == "companion" ) then
				set[actionID] = string.join("|", type, id, "", "", subType)
			-- Save an equipment set
			elseif( type == "equipmentset" ) then
				set[actionID] = string.join("|", type, id, "")
			-- Save an item
			elseif( type == "item" ) then
				set[actionID] = string.join("|", type, id, "", (GetItemInfo(id)) or "")
			-- Save a pet spell
			elseif( subType == "pet" and id > 0 ) then
			 local spellName, spellStance = GetSpellInfo(id)
				if( spellName) then
					set[actionID] = string.join("|", "petaction", id, "", spellName, spellStance or "", extraID or "")
				end
			-- Save a spell
			elseif( type == "spell" and id > 0 ) then
			 local spellName, spellStance = GetSpellInfo(id)
				if( spellName) then
					local class
					if spellCache[spellName] then
						--spell is class specific
						class =  select(2, UnitClass("player"))
					end
					set[actionID] = string.join("|", type, id, "", spellName, spellStance or "", extraID or "", class or "")
				end
			-- Save a macro
			elseif( type == "macro" ) then
				local name, icon, macro = GetMacroInfo(id)
				if( name and icon and macro ) then
					local spellName = GetMacroSpell(GetMacroIndexByName(name))
					local class
					if macroContainsClassSpell(macro) then
						--macro casts a spell, and that spell is class specific
						class =  select(2, UnitClass("player"))
					end
					set[actionID] = string.join("|", type, actionID, "", self:CompressText(name), icon, self:CompressText(macro), class or "")
				end
			-- Flyout menu
		 elseif( type == "flyout" ) then
			set[actionID] = string.join("|", type, id, "", (GetFlyoutInfo(id)))
			end
		end
	end
	
	self:Print(string.format(L["Saved profile %s!"], name))
end

-- Finds the macroID in case it's changed
function ABS:FindMacro(id, name, data)
	if( macroCache[id] == data ) then
		return id
	end
		
	-- No such luck, check text
	for id, currentMacro in pairs(macroCache) do
		if( currentMacro == data ) then
			return id
		end
	end
	
	-- Still no luck, let us try name
	if( macroNameCache[name] ) then
		return macroNameCache[name]
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
			local macroID = self:FindMacro(id, macroName, macroData)
			if( not macroID ) then
				local globalNum, charNum = GetNumMacros()
				-- Make sure we aren't at the limit
				if( globalNum == MAX_GLOBAL_MACROS and charNum == MAX_CHAR_MACROS ) then
					table.insert(restoreErrors, L["Unable to restore macros, you already have 36 global and 18 per character ones created."])
					break

				-- We ran out of space for per character, so use global
				elseif( charNum == MAX_CHAR_MACROS ) then
					perCharacter = false
				end
				
				macroName = self:UncompressText(macroName)

				-- GetMacroInfo still returns the full path while CreateMacro needs the relative
				-- can also return INTERFACE\ICONS\ as well, apparently.
				macroIcon = macroIcon and string.gsub(macroIcon, "[iI][nN][tT][eE][rR][fF][aA][cC][eE]\\[iI][cC][oO][nN][sS]\\", "")
				
				-- No macro name means a space has to be used or else it won't be created and saved
				CreateMacro(macroName == "" and " " or macroName, macroIcon or "INV_Misc_QuestionMark", self:UncompressText(macroData), perCharacter)
			end
		end
	end
	
	-- Recache macros due to any additions
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			-- If there are macros with the same name, then blacklist and don't look by name
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
end

function isSpellCurrentClass(type, id)
	local isCurrent
	
	if type == "macro" then
		local name, icon, body, isLocal = GetMacroInfo(id)
		id = GetMacroSpell(name)
	end

	local spellName = spellCache[GetSpellInfo(id)]
	if spellName then		
		local spec, class = IsSpellClassOrSpec(spellName, "spell")
		
		if id and ((type == "spell") or (type == "macro")) and (spec or class) then
			isCurrent = true
		end
	end
	return isCurrent
end

function ABS:CreateSpellCache()
	table.wipe(spellCache)
	-- Cache spells
	for book=1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells, _, offSpecID = GetSpellTabInfo(book)

		for i=1, numSpells do
			if offSpecID == 0 then -- don't process grayed-out "offspec" tabs
				for i=1, numSpells do
					local index = offset + i
					local spell, stance = GetSpellBookItemName(index, BOOKTYPE_SPELL)
				
					-- This way we restore the max rank of spells
					spellCache[spell] = index
					spellCache[string.lower(spell)] = index
				
					if( stance and stance ~= "" ) then
						spellCache[spell .. stance] = index
					end
	 			end
			end
		end
	end
end

function ABS:ClearActionBars()
	for i=1, MAX_ACTION_BUTTONS do
		if( i < POSSESSION_START or i > POSSESSION_END ) then
			PickupAction(i)
			ClearCursor()
		end
	end
end

-- Restore a saved profile
function ABS:RestoreProfile(name, overrideClass)
	local set = self.db.sets[overrideClass or playerClass][name]
	if( not set ) then
		self:Print(string.format(L["No profile with the name \"%s\" exists."], set))
		return
	elseif( InCombatLockdown() ) then
		self:Print(String.format(L["Unable to restore profile \"%s\", you are in combat."], set))
		return
	end
	
	table.wipe(macroCache)
	table.wipe(macroNameCache)

	self:CreateSpellCache()
	
	-- Cache macros
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			-- If there are macros with the same name, then blacklist and don't look by name
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
	
	-- Check if we need to restore any missing macros
	if( self.db.macro ) then
		self:RestoreMacros(set)
	end

	-- Start fresh with nothing on the cursor
	ClearCursor()
	
	-- Save current sound setting
	local soundToggle = GetCVar("Sound_EnableAllSound")
	-- Turn sound off
	SetCVar("Sound_EnableAllSound", 0)

	for i=1, MAX_ACTION_BUTTONS do
		if( i < POSSESSION_START or i > POSSESSION_END ) then
			local type, id, subType = GetActionInfo(i)
		
			local proceed = true
			-- Clear the current spot
			if( id or type ) and (self.db.leave ~= true) then
				
				if (self.db.leaveClass == true) then
					proceed = isSpellCurrentClass(type, id) == nil
				end
				
				if proceed == true then
					PickupAction(i)
					ClearCursor()
				end
			end
		
			-- Restore this spot
			if( set[i] ) and (proceed == true) then
				self:RestoreAction(i, string.split("|", set[i]))
			end
		end
	end
	
	-- Restore old sound setting
	SetCVar("Sound_EnableAllSound", soundToggle)
	
	-- Done!
	if( #(restoreErrors) == 0 ) then
		self:Print(string.format(L["Restored profile %s!"], name))
	else
		self:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /abs errors for more information."], name, #(restoreErrors)))
	end
end
local types
types = {
	item = {
		pickup = function(i, type, actionID, binding, ...)
			return PickupItem(actionID)
		end,
		errorMessage = function(i, type, actionID, binding, ...)
			if( GetCursorInfo() ~= type ) then
				local itemName = select(i, ...)
				table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], itemName and itemName ~= "" and itemName or actionID, i))
				return true
			end
		end,
	},
	macro = {
		pickup = function(i, type, actionID, binding, ...)
			local name, _, content, class = ...
			
			if class and (class ~= "") and ABS.db.ignoreClass and (class ~= select(2, UnitClass("player"))) then
				
			else
				return PickupMacro(ABS:FindMacro(actionID, name, content or -1))
			end
		end,
		errorMessage = function(i, type, actionID, binding, ...)
			if( GetCursorInfo() ~= type ) then
				table.insert(restoreErrors, string.format(L["Unable to restore macro id #%d to slot #%d, it appears to have been deleted."], actionID, i))
				return true
			end
		end,
	},
	petaction = {
		pickup = function(i, type, actionID, binding, ...)
			PickupPetSpell(actionID)
		end,
		errorMessage = function(...) return types.spell.errorMessage(...) end,
	},
	spell = {
		pickup = function(i, type, actionID, binding, ...)
			local spellName, _, _, class = ...
			if class and (class ~= "") and ABS.db.ignoreClass and (class ~= select(2, UnitClass("player"))) then

			
			else
				if( spellCache[spellName] and ABS.db.restoreRank ) then
					return PickupSpellBookItem(spellCache[spellName], BOOKTYPE_SPELL);
				else
					return PickupSpell(actionID)
				end
						
				if( GetCursorInfo() ~= type ) then
					--last ditch effort if spellCache goes wrong(it does fail for a few warlock spells)
					return PickupSpell(actionID)
				end
			end
		end,
		errorMessage = function(i, type, actionID, binding, ...)
			local spellName = ...
			if( GetCursorInfo() ~= type ) then
				-- Bad restore, check if we should link at all
				local lowerSpell = string.lower(spellName)
				for spell, linked in pairs(ABS.db.spellSubs) do
					if( lowerSpell == spell and spellCache[linked] ) then
						ABS:RestoreAction(i, type, actionID, binding, linked, nil, arg3)
						return
					elseif( lowerSpell == linked and spellCache[spell] ) then
						ABS:RestoreAction(i, type, actionID, binding, spell, nil, arg3)
						return
					end
				end
				table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], spellName, i))
				return true
			end
		end,
	},
	mount = {
		pickup = function(i, type, actionID, binding, ...)
			local _, spellID = types.mount.info(actionID)
			PickupSpell(spellID or actionID)
		end,
		info = function(actionID)
			return C_MountJournal.GetMountInfoByID(actionID)
		end,
		errorMessage = function(i, type, actionID, binding, ...)
			print(type)
			local cType, cID, cSubType = GetCursorInfo()
			local creatureName = types.mount.info(actionID)
			if( cSubType ~= type ) and creatureName then
				table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], creatureName, i))
				return true
			end
		end,
	},
	equipmentset = {
		pickup = function(i, type, actionID, binding, ...)
			local slotID = -1
			for i=1, GetNumEquipmentSets() do
				if( GetEquipmentSetInfo(i) == actionID ) then
					slotID = i
					break
				end
			end
			
			return PickupEquipmentSet(slotID)
		end,
		errorMessage = function(i, type, actionID, binding, ...)
			if( GetCursorInfo() ~= "equipmentset" ) then
				table.insert(restoreErrors, string.format(L["Unable to restore equipment set \"%s\" to slot #%d, it does not appear to exist anymore."], actionID, i))
				return true
			end
		end,
	},
	flyout = {
		pickup = function(i, type, actionID, binding, ...)
			local name = ...
			PickupSpellBookItem(spellCache[string.lower(name)] or actionId, "spell")
		end,
		errorMessage = function(i, type, actionID, binding, ...)
			if( GetCursorInfo() ~= "flyout" ) then
				table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], name, actionID))
				return true
			end
		end,
	},
	battlepet ={
		pickup = function(i, type, actionID, binding, ...)
					local _, customName, _, _, _, _, _, name = types.battlepet.info(actionID)
			C_PetJournal.PickupPet(actionID)	
		end,
		info = function(actionID)
			return C_PetJournal.GetPetInfoByPetID(actionID)
		end,
		errorMessage = function(i, type, actionID, binding, ...)
			if( type ~= GetCursorInfo() ) then
				table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], customName or name, i))
				return true
			end
		end,
	},
	
}

function ABS:RestoreAction(i, type, actionID, binding, ...)
	local info = types[string.lower(type)]
	if info then
		info.pickup(i, type, actionID, binding, ...)
		if info.errorMessage(i, type, actionID, binding, ...) then
			ClearCursor()
		end
	end
	PlaceAction(i)
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS|r: " .. msg)
end

SLASH_ACTIONBARSAVER1 = nil
SlashCmdList["ACTIONBARSAVER"] = nil

SLASH_ABS1 = "/abs"
SLASH_ABS2 = "/actionbarsaver"
SlashCmdList["ABS"] = function(msg)
	msg = msg or ""
	
	local cmd, arg = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")
	arg = string.lower(arg or "")
	
	local self = ABS
	
	-- Profile saving
	if( cmd == "save" and arg ~= "" ) then
		self:SaveProfile(arg)
	
	-- Spell sub
	elseif( cmd == "link" and arg ~= "" ) then
		local first, second = string.match(arg, "\"(.+)\" \"(.+)\"")
		first = string.trim(first or "")
		second = string.trim(second or "")
		
		if( first == "" or second == "" ) then
			self:Print(L["Invalid spells passed, remember you must put quotes around both of them."])
			return
		end
		
		self.db.spellSubs[first] = second
		
		self:Print(string.format(L["Spells \"%s\" and \"%s\" are now linked."], first, second))
		
	-- Profile restoring
	elseif( cmd == "restore" and arg ~= "" ) then
		for i=#(restoreErrors), 1, -1 do table.remove(restoreErrors, i) end
				
		if( not self.db.sets[playerClass][arg] ) then
			self:Print(string.format(L["Cannot restore profile \"%s\", you can only restore profiles saved to your class."], arg))
			return
		end
		
		self:RestoreProfile(arg, playerClass)
		
	-- Profile renaming
	elseif( cmd == "rename" and arg ~= "" ) then
		local old, new = string.split(" ", arg, 2)
		new = string.trim(new or "")
		old = string.trim(old or "")
		
		if( new == old ) then
			self:Print(string.format(L["You cannot rename \"%s\" to \"%s\" they are the same profile names."], old, new))
			return
		elseif( new == "" ) then
			self:Print(string.format(L["No name specified to rename \"%s\" to."], old))
			return
		elseif( self.db.sets[playerClass][new] ) then
			self:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], old, new, (UnitClass("player"))))
			return
		elseif( not self.db.sets[playerClass][old] ) then
			self:Print(string.format(L["No profile with the name \"%s\" exists."], old))
			return
		end
		
		self.db.sets[playerClass][new] = CopyTable(self.db.sets[playerClass][old])
		self.db.sets[playerClass][old] = nil
		
		self:Print(string.format(L["Renamed \"%s\" to \"%s\""], old, new))
		
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
		self.db.sets[playerClass][arg] = nil
		self:Print(string.format(L["Deleted saved profile %s."], arg))
	
	-- List profiles
	elseif( cmd == "list" ) then
		local classes = {}
		local setList = {}
		
		for class, sets in pairs(self.db.sets) do
			table.insert(classes, class)
		end
		
		table.sort(classes, function(a, b)
			return a < b
		end)
		
		for _, class in pairs(classes) do
			for i=#(setList), 1, -1 do table.remove(setList, i) end
			for setName in pairs(self.db.sets[class]) do
				table.insert(setList, setName)
			end
			
			if( #(setList) > 0 ) then
				DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99%s|r: %s", L[class] or "???", table.concat(setList, ", ")))
			end
		end
		
	-- Macro restoring
	elseif( cmd == "macro" ) then
		self.db.macro = not self.db.macro

		if( self.db.macro ) then
			self:Print(L["Auto macro restoration is now enabled!"])
		else
			self:Print(L["Auto macro restoration is now disabled!"])
		end
	
	-- Item counts
	elseif( cmd == "count" ) then
		self.db.checkCount = not self.db.checkCount

		if( self.db.checkCount ) then
			self:Print(L["Checking item count is now enabled!"])
		else
			self:Print(L["Checking item count is now disabled!"])		
		end
	
	-- Rank restore
	elseif( cmd == "rank" ) then
		self.db.restoreRank = not self.db.restoreRank
		
		if( self.db.restoreRank ) then
			self:Print(L["Auto restoring highest spell rank is now enabled!"])
		else
			self:Print(L["Auto restoring highest spell rank is now disabled!"])
		end
		
	-- open new profiles menu	
	elseif( string.find("options", cmd, 1)) then
		InterfaceOptionsFrame:Show()
		InterfaceOptionsFrame_OpenToCategory(ActionBarSaver.Options.name)
	-- Halp
	else
		self:Print(L["Slash commands"])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rename <oldProfile> <newProfile> - Renames a saved profile from oldProfile to newProfile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs link \"<spell 1>\" \"<spell 2>\" - Links a spell with another, INCLUDE QUOTES for example you can use \"Shadowmeld\" \"War Stomp\" so if War Stomp can't be found, it'll use Shadowmeld and vica versa."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rank - Toggles if ABS should restore the highest rank of the spell, or the one saved originally."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
	end
end

-- Check if we need to load
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
	if( addon == "ActionBarSaver" ) then
		ABS:OnInitialize()
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
