ABS = {}

local L = ActionBarSaverLocals

local spellCache = {}
local macroCache = {}
local restoreErrors = {}
local equipSlots = {"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot","TabardSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot","Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot"}
local charID
local iconCache

local MAX_MACROS = 36

function ABS:UncompressMacro(text)
	text = string.gsub(text, "|;|", ":")
	
	local name, _, icon, _, macro = string.split("||", text)
	if( not name or not icon or not macro ) then
		return nil
	end
	
	macro = string.gsub(macro, "/n", "\n")
	
	return name, icon, macro
end

function ABS:CompressMacro(id)
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
						list[i] = id .. ":" .. type .. ":" .. (string.gsub(spell, ":", "|;|")) .. ":" .. rank
					else
						list[i] = id .. ":" .. type .. ":" .. (string.gsub(spell, ":", "|;|"))
					end
				end
			elseif( type == "item" ) then
				local name = GetItemInfo(id)
				local text = name or id
				
				list[i] = id .. ":" .. type .. ":" .. (string.gsub(text, ":", "|;|"))
			elseif( type == "macro" ) then
				list[i] = id .. ":" .. type .. ":" .. self:CompressMacro(id)
			else
				list[i] = id .. ":" .. type
			end
		else
			list[i] = nil
		end
	end
	
	self.db.profiles[profile] = list
	self.db.profileData[profile] = charID
end

function ABS:GetActionID(id, type, idArg1, idArg2)
	-- Check the spellID via our cache
	if( type == "spell" and idArg1 and idArg1 ~= "" ) then
		idArg1 = string.gsub(idArg1, "|;|", ":")
		if( idArg2 ) then
			return spellCache[idArg1 .. idArg2]
		else
			return spellCache[idArg1]
		end
	
	-- Check the macro location, if it's not at the original known position then do trickery and find out where
	elseif( type == "macro" and idArg1 and idArg1 ~= "" ) then
		id = tonumber(id)
		
		-- We check it as a name||body format instead of icon because Blizzards a pain in the ass
		local name, _, icon, _, body = string.split("||", idArg1)
		name = string.gsub(name, "|;|", ":")

		local macroID = string.format("%s||%s", name or "", body or "")

		if( macroCache[id] ) then
			local name, _, icon, _, body = string.split("||", macroCache[id])
			local cacheID = string.format("%s||%s", name or "", body or "")
			
			if( cacheID == macroID ) then
				return id
			end
		end

		-- Try and find a macro that matches our ID
		for i, mID in pairs(macroCache) do
			local name, _, icon, _, body = string.split("||", mID)
			local cacheID = string.format("%s||%s", name or "", body or "")
			
			if( cacheID == macroID ) then
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
		macroCache[i] = self:CompressMacro(i)
	end
	
	-- Restore macros
	if( ABS.db.macro ) then
		local perCharacter = true
		for id, data in pairs(currentProfile) do
			local crtID, crtType, macroID = string.split(":", data)
			if( crtType == "macro" and macroID and macroID ~= "" ) then
				local globalNum, charNum = GetNumMacros()
				
				-- Make sure we aren't at the limit
				if( globalNum == 18 and charNum == 18 ) then
					table.insert(restoreErrors, L["Unable to restore macros, you already have 18 global and 18 per character ones created."])
					break
				
				-- We ran out of space for per character, so use global
				elseif( charNum == 18 ) then
					perCharacter = false
				end

				-- Find out if we have a macro of this type
				local id = self:GetActionID(crtID, crtType, macroID)
				if( id == -1 ) then
					local name, icon, macro = self:UncompressMacro(macroID)

					-- Create the cache
					if( not iconCache ) then
						iconCache = {}
						for i=1, GetNumMacroIcons() do
							iconCache[(GetMacroIconInfo(i))] = i
						end
					end

					-- Create the actual macro
					CreateMacro(name, iconCache[icon] or 1, macro, nil, perCharacter)
				end
			end
		end
		
		-- Recache everything we didn't have already
		for i=1, MAX_MACROS do
			macroCache[i] = self:CompressMacro(i)
		end
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
					PickupAction(i)
				end
				
				ClearCursor()

			-- Restore macros
			elseif( crtType == "macro" and id ) then
				PickupMacro(id)
				if( GetCursorInfo() == "macro" ) then
					PlaceAction(i)
				else
					table.insert(restoreErrors, string.format(L["Unable to restore macro id #%d to slot #%d, it appears to have been deleted."], crtID, i))
					PickupAction(i)
				end
				
				ClearCursor()
			
			-- Restore items
			elseif( crtType == "item" and id ) then
				PickupItem(id)
				if( GetCursorInfo() == "item" ) then
					PlaceAction(i)
				else
					table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], crtName or id, i))
					PickupAction(i)
				end
			
				ClearCursor()
			
			-- Unknown, clear this spot
			elseif( id or type ) then
				PickupAction(i)
				ClearCursor()
			end
			
		-- We have nothing here, simply clear this spot
		elseif( id or type ) then
			PickupAction(i)
			ClearCursor()
		end
	end

	-- Now set this as active profile
	self.db.currentProfiles[charID] = profile
	self.db.profileData[profile] = charID
	return true
end

function ABS:OnInitialize()
	if( not ActionBSDB ) then
		ActionBSDB = {
			profiles = {},
			currentProfiles = {},
			profileData = {},
			logout = false,
			macro = false,
		}
	end
		
	charID = string.format("%s-%s", UnitName("player"), GetRealmName())
	
	self.db = setmetatable(ActionBSDB, {})
	
	if( not self.db.currentProfiles ) then
		self.db.currentProfile = nil
		self.db.currentProfiles = {}
	end
	
	if( not self.db.profileData ) then
		self.db.profileData = {}
	end
	
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
			local profileList = {}
			
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

				local text = string.format(L["%s (%d of 120, %d spells, %d macros, %d items)"], profile, spells + macros + items, spells, macros, items)
				
				local id = self.db.profileData[profile] or L["Miscellaneous"]
				if( not profileList[id] ) then
					profileList[id] = {}
				end

				table.insert(profileList[id], text)
			end
			
			-- Now list categorized ones out
			for profileName, profiles in pairs(profileList) do
				DEFAULT_CHAT_FRAME:AddMessage(string.format("[|cff33ff99%s|r]", profileName))
				
				for _, text in pairs(profiles) do
					DEFAULT_CHAT_FRAME:AddMessage(text)
				end
			end
		
		elseif( cmd == "delete" ) then
			data = tostring(data)
			if( self.db.profiles[data] ) then
				self.db.profiles[data] = nil
				
				-- No longer the current profile
				if( self.db.currentProfiles[charID] == data ) then
					self.db.currentProfiles[charID] = nil
				end
				
				self:Print(string.format(L["Deleted saved profile %s."], data))
			else
				self:Print(string.format(L["No profile with the name \"%s\" exists."], data))
			end
		
		elseif( cmd == "macro" ) then
			self.db.macro = not self.db.macro
			
			if( self.db.macro ) then
				self:Print(L["Auto macro restoration is now enabled!"])
			else
				self:Print(L["Auto macro restoration is now disabled!"])
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
			DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
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
	elseif( event == "PLAYER_LEAVING_WORLD" and ABS.db.logout and ABS.db.currentProfiles[charID] ) then
		ABS:SaveActions(ABS.db.currentProfiles[charID])
	end
end)

ABS.frame = frame


local inspectSent
local inspectQueue = {}
local timeElapsed = 0
local frame = CreateFrame("Frame")
frame:Hide()

-- Reset our flag early if we get the info
frame:RegisterEvent("INSPECT_TALENT_READY")
frame:SetScript("OnEvent", function(self)
	inspectSent = nil
	timeElapsed = 0
	self:Hide()
end)

-- Time out after 3 seconds
frame:SetScript("OnUpdate", function(self, elapsed)
	timeElapsed = timeElapsed + elapsed
	
	if( timeElapsed >= 3 ) then
		-- Reset counter/stop counting
		timeElapsed = 0
		inspectSent = nil
		self:Hide()
		
		-- Inspection timed out, send next
		if( #(inspectQueue) > 0 ) then
			NotifyInspect(table.remove(inspectQueue, 1))
		end
	end
end)

-- Hook so we don't cause issues with other inspect addons
hooksecurefunc("NotifyInspect", function(unit)
	timeElapsed = 0
	inspectSent = true
	frame:Show()
end)

function queueInspect(unit)
	if( inspectSent ) then
		table.insert(inspectQueue, unit)
		return
	end
	
	NotifyInspect(unit)
end