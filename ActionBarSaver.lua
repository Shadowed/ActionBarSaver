--[[ 
	Action Bar Saver, Mayen (Horde) from Icecrown (US) PvE
]]

ABS = LibStub("AceAddon-3.0"):NewAddon("ABS", "AceEvent-3.0")

local L = ActionBarSaverLocals

local restoreErrors, spellCache, macroCache, highestRanks = {}, {}, {}, {}
local iconCache, playerClass, isTournament

local seasonItems = { [1] = L["^Gladiator"], [2] = L["^Merciless Gladiator"], [3] = L["^Vengeful Gladiator"], [4] = L["^Brutal Gladiator"] }

local MAX_MACROS = 36

function ABS:OnInitialize()
	self.defaults = {
		profile = {
			macro = false,
			checkCount = false,
			
			spellSubs = {},
			sets = {UNKNOWN = {}},
		},
	}

	self.db = LibStub:GetLibrary("AceDB-3.0"):New("ActionBarSaverDB", self.defaults)
	self.db:SetProfile("Global")
	
	-- Upgrade
	if( ActionBSDB ) then
		for name in pairs(RAID_CLASS_COLORS) do
			self.db.profile.sets[name] = self.db.profile.sets[name] or {}
		end
		
		for name, data in pairs(ActionBSDB.profiles) do
			local actionData = {}
			for id, line in pairs(data) do
				local arg1, type, arg3 = string.split(":", line)
				if( type == "spell" ) then
					actionData[id] = string.format("%s|%d||%s", type, arg1, string.gsub(arg3, "|;|", ":"))	
				elseif( type == "item" ) then
					actionData[id] = string.format("%s|%d||%s", type, arg1, string.gsub(arg3, "|;|", ":"))
				elseif( type == "macro" ) then
					local macro = select(5, string.split("||", string.gsub(arg3, "|;|", ":")))
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

-- Restore a saved profile
function ABS:SaveProfile(name)
	self.db.profile.sets[playerClass][name] = self.db.profile.sets[playerClass][name] or {}
	local set = self.db.profile.sets[playerClass][name]
	
	for id=1, 120 do
		local type, actionID = GetActionInfo(id)
		set[id] = nil
		
		if( type and actionID ) then
			local binding = ""
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
			local globalNum, charNum = GetNumMacros()

			-- Make sure we aren't at the limit
			if( globalNum == 18 and charNum == 18 ) then
				table.insert(restoreErrors, L["Unable to restore macros, you already have 18 global and 18 per character ones created."])
				break

			-- We ran out of space for per character, so use global
			elseif( charNum == 18 ) then
				perCharacter = false
			end
			
			-- Do we already have a macro?
			local macroID = self:FindMacro(id, macroData)
			if( not macroID ) then
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
	
	isTournement = string.match(GetRealmName(), "^Arena Tournament")
	
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
		if( arg2 and arg2 ~= "" and spellCache[arg1 .. arg2] ) then
			PickupSpell(spellCache[arg1 .. arg2], BOOKTYPE_SPELL)
		elseif( spellCache[arg1] ) then
			PickupSpell(spellCache[arg1], BOOKTYPE_SPELL)
		end
		
		if( GetCursorInfo() ~= type ) then
			table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], arg1, i))
			ClearCursor()
			return
		end

		PlaceAction(i)
	elseif( type == "item" ) then
		-- Check to prevent disconnects
		if( isTournament and string.match(arg1, seasonItems[GetCurrentArenaSeason()]) ) then
			table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, you on the Arena Tournament Realms and attempting to restore that item would cause a disconnect."], arg1, i))
			ClearCursor()
			return
		end
		
		
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
		self.db.macro = not self.db.macro

		if( self.db.macro ) then
			self:Print(L["Auto macro restoration is now enabled!"])
		else
			self:Print(L["Auto macro restoration is now disabled!"])
		end
	
	-- Item counts
	elseif( cmd == "count" ) then
		self.db.profile.checkCount = not self.db.profile.checkCount

		if( self.db.logout ) then
			self:Print(L["Checking item count is now enabled!"])
		else
			self:Print(L["Checking item count is now disabled!"])		
		end
		
	-- Halp
	else
		self:Print(L["Slash commands"])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rename <oldProfile> <newProfile> - Renames a saved profile from oldProfile to newProfile."])
		--DEFAULT_CHAT_FRAME:AddMessage(L["/abs test <profile> - Tests restoring a profile, results will be outputted to chat."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs errors - Lists the errors that happened on the last restore (if any)."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
	end
end