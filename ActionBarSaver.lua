ABS = {}

local spellCache = {}
local macroCache = {}
local restoreErrors = {}
local equipSlots = {"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot","TabardSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot","Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot"}


local MAX_MACROS = 36

local L = {
	["Slash commands"] = "Slash commands",
	["Saved profile %s!"] = "Saved profile %s!",
	["Restored profile %s!"] = "Restored profile %s!",
	["No profile with the name \"%s\" exists."] = "No profile with the name \"%s\" exists.",
	["Deleted saved profile %s."] = "Deleted saved profile %s.",
	["Profile List"] = "Profile List",
	["%s (%d of 120, %d spells, %d macros, %d items)"] = "%s (%d of 120, %d spells, %d macros, %d items)",
	["Auto profile save on logout is enabled!"] = "Auto profile save on logout is enabled!",
	["Auto profile save on logout is disabled!"] = "Auto profile save on logout is disabled!",
	
	["/abs save <profile> - Saves your current action bar setup under the given profile."] = "/abs save <profile> - Saves your current action bar setup under the given profile.",
	["/abs restore <profile> - Changes your action bars to the passed profile."] = "/abs restore <profile> - Changes your action bars to the passed profile.",
	["/abs delete <profile> - Deletes the saved profile."] = "/abs delete <profile> - Deletes the saved profile.",
	["/abs logout - Toggles auto saving of the current profile whenever you leave the world."] = "/abs logout - Toggles auto saving of the current profile whenever you leave the world.",
	["/abs list - Lists all saved profiles."] = "/abs list - Lists all saved profiles.",
	["/abs errors - Lists the errors that happened on the last restore (if any)."] = "/abs errors - Lists the errors that happened on the last restore (if any).",
	
	["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."] = "Unable to restore item \"%s\" to slot #%d, cannot be found in inventory.",
	["Unable to restore macro id #%d to slot #%d, it appears to have been deleted."] = "Unable to restore macro id #%d to slot #%d, it appears to have been deleted.",
	["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."] = "Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet.",
	
	["No errors found"] = "No errors found",
	["Errors found: %d"] = "Errors found: %d",
	["Restored profile %s, failed to restore %d buttons type /abs errors for more information."] = "Restored profile %s, failed to restore %d buttons type /abs errors for more information.",
}

function ABS:CompileMacroID(id)
	local name, icon, text = GetMacroInfo(id)
	if( not text ) then
		return ""
	end
	
	text = string.gsub(text, "\n", "/n")
	text = string.gsub(text, ":", "|;|")
	
	return string.format("%s||%s||%s", name or "", icon or "", text or "")
end

function ABS:SaveActions(profile)
	local list = self.db.profiles[profile] or {}
	for i=1, 120 do
		local type, id = GetActionInfo(i)
		if( type and id ) then
			if( type == "spell" ) then
				local spell, rank = GetSpellName(id, BOOKTYPE_SPELL)
				if( spell ) then
					if( rank and rank ~= "" ) then
						list[i] = id .. ":" .. type .. ":" .. spell .. ":" .. rank
					else
						list[i] = id .. ":" .. type .. ":" .. spell
					end
				end
			elseif( type == "item" ) then
				local name = GetItemInfo(id)
				list[i] = id .. ":" .. type .. ":" .. (name or id)
			elseif( type == "macro" ) then
				list[i] = id .. ":" .. type .. ":" .. self:CompileMacroID(id)
			else
				list[i] = id .. ":" .. type
			end
		else
			list[i] = nil
		end
	end
	
	self.db.profiles[profile] = list
end

function ABS:GetActionID(id, type, idArg1, idArg2)
	-- Check the spellID via our cache
	if( type == "spell" and idArg1 and idArg1 ~= "" ) then
		if( idArg2 ) then
			return spellCache[idArg1 .. idArg2]
		else
			return spellCache[idArg1]
		end
	
	-- Check the macro location, if it's not at the original known position then do trickery and find out where
	elseif( type == "macro" and idArg1 and idArg1 ~= "" ) then
		id = tonumber(id)
		
		if( macroCache[id] == idArg1 ) then
			return id
		end
		
		-- Try and find a macro that matches our ID
		for i, macroID in pairs(macroCache) do
			if( macroID == idArg1 ) then
				return i
			end
		end
		
		return -1
	end
	
	return tonumber(id)
end

function ABS:LoadActions(profile)
	local currentProfile = self.db.profiles[profile]
	if( not currentProfile ) then
		return nil
	end
	
	-- Create the spell cache
	for k in pairs(spellCache) do
		spellCache[k] = nil
	end
	
	for book=1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(book)

		for i=1, numSpells do
			local index = offset + i
			local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)
			if( rank and rank ~= "" ) then
				-- If we've got a numeric "Rank #" then store it as "spell#" and "spellRank #" for compatability issues
				-- Remove this in a version or two
				local numRank = string.match(rank, "(%d+)")	
				if( numRank ) then
					spellCache[spell .. numRank] = index
				end
				
				spellCache[spell .. rank] = index
			else
				spellCache[spell] = index
			end
		end
	end
	
	-- Create macro cache
	for i=1, MAX_MACROS do
		macroCache[i] = self:CompileMacroID(i)
	end
	
	-- Restore positions
	for i=1, 120 do
		local type, id = GetActionInfo(i)
		if( currentProfile[i] ) then
			local crtID, crtType, crtName, crtRank, crtBookType = string.split(":", currentProfile[i])
			local id = self:GetActionID(crtID, crtType, crtName, crtRank)
			
			-- Restore spells
			if( crtType == "spell" and id ) then
				PickupSpell(id, BOOKTYPE_SPELL)
				if( GetCursorInfo() == "spell" ) then
					PlaceAction(i)
				else
					local name = crtName
					if( crtRank and crtRank ~= "" ) then
						name = string.format("%s (%s)", name, crtRank)
					end
					
					table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], name, i))
				end
				
				ClearCursor()

			-- Restore macros
			elseif( crtType == "macro" and id ) then
				PickupMacro(id)
				if( GetCursorInfo() == "macro" ) then
					PlaceAction(i)
				else
					table.insert(restoreErrors, string.format(L["Unable to restore macro id #%d to slot #%d, it appears to have been deleted."], crtID, i))
				end
				
				ClearCursor()
			
			-- Restore items
			elseif( crtType == "item" and id ) then
				PickupItem(id)
				if( GetCursorInfo() == "item" ) then
					PlaceAction(i)
				else
					table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], crtName or id, i))
				end
			
				ClearCursor()
			end

		-- We have nothing here, simply clear this spot
		elseif( type and id ) then
			PickupAction(i)
			ClearCursor()
		end
	end

	-- Now set this as active profile
	self.db.currentProfile = profile
	return true
end

function ABS:OnInitialize()
	if( not ActionBSDB ) then
		ActionBSDB = {
			profiles = {},
			logout = true,
			currentProfile = nil,
		}
	end
	
	self.db = setmetatable(ActionBSDB, {})
	
	SLASH_ACTIONBS1 = "/abs"
	SLASH_ACTIONBS2 = "/actionbarsaver"
	SlashCmdList["ACTIONBS"] = function(msg)
		msg = msg or ""
		
		local self = ABS
		local cmd, data = string.match(msg, "^([a-zA-Z0-9]+) (.+)")
		if( not cmd and not data ) then
			cmd = string.lower(msg)
		elseif( cmd ) then
			cmd = string.lower(cmd)
		end
		
		if( cmd == "save" and data ) then
			data = tostring(data)
			
			self:SaveActions(data)
			self:Print(string.format(L["Saved profile %s!"], data))
			
		elseif( cmd == "restore" and data ) then
			data = tostring(data)
			
			for i=#(restoreErrors), 1, -1 do
				table.remove(restoreErrors, i)
			end
			
			local results = self:LoadActions(data)
			if( results ) then
				if( #(restoreErrors) == 0 ) then
					self:Print(string.format(L["Restored profile %s!"], data))
				else
					self:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /abs errors for more information."], data, #(restoreErrors)))
				end
			else
				self:Print(string.format(L["No profile with the name \"%s\" exists."], data))
			end
		
		elseif( msg == "errors" ) then
			if( #(restoreErrors) == 0 ) then
				self:Print(L["No errors found!"])
				return
			end
			
			self:Print(string.format(L["Errors found: %d"], #(restoreErrors)))
			for _, text in pairs(restoreErrors) do
				DEFAULT_CHAT_FRAME:AddMessage(text)
			end
		
		elseif( msg == "list" ) then
			self:Print(L["Profile List"])
			for profile, info in pairs(self.db.profiles) do
				local spells = 0
				local macros = 0
				local items = 0
				
				for _, row in pairs(info) do
					if( string.match(row, "spell") ) then
						spells = spells + 1
					elseif( string.match(row, "macro") ) then
						macros = macros + 1
					elseif( string.match(row, "item") ) then
						items = items + 1
					end
				end
				
				DEFAULT_CHAT_FRAME:AddMessage(string.format(L["%s (%d of 120, %d spells, %d macros, %d items)"], profile, spells + macros + items, spells, macros, items))
			end
		
		elseif( cmd == "delete" ) then
			data = tostring(data)
			if( self.db.profiles[data] ) then
				self.db.profiles[data] = nil
				
				-- No longer the current profile
				if( self.db.currentProfile == data ) then
					self.db.currentProfile = nil
				end
				
				self:Print(string.format(L["Deleted saved profile %s."], data))
			else
				self:Print(string.format(L["No profile with the name \"%s\" exists."], data))
			end
			
		elseif( cmd == "logout" ) then
			self.db.logout = not self.db.logout
			
			if( self.db.logout ) then
				self:Print(L["Auto profile save on logout is enabled!"])
			else
				self:Print(L["Auto profile save on logout is disabled!"])		
			end
		else
			self:Print(L["Slash commands"])
			DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
			DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
			DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
			DEFAULT_CHAT_FRAME:AddMessage(L["/abs logout - Toggles auto saving of the current profile whenever you leave the world."])
			DEFAULT_CHAT_FRAME:AddMessage(L["/abs errors - Lists the errors that happened on the last restore (if any)."])
			DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
		end
	end
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS|r: " .. msg)
end


local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, addon)
	if( event == "ADDON_LOADED" and addon == "ActionBarSaver" ) then
		ABS.OnInitialize(ABS)
	elseif( event == "PLAYER_LEAVING_WORLD" and ABS.db.logout and ABS.db.currentProfile ) then
		ABS:SaveActions(ABS.db.currentProfile)
	end
end)

ABS.frame = frame