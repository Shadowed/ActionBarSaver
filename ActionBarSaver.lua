ABS = {}
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
}

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
			
			local results = self:LoadActions(data)
			if( results ) then
				self:Print(string.format(L["Restored profile %s!"], data))
			else
				self:Print(string.format(L["No profile with the name \"%s\" exists."], data))
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
			DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
		end
	end
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS|r: " .. msg)
end

function ABS:SaveActions(profile)
	local list = self.db.profiles[profile] or {}
	for i=1, 120 do
		local type, id = GetActionInfo(i)
		if( type and id ) then
			list[i] = id .. ":" .. type
		else
			list[i] = nil
		end
	end
	
	self.db.profiles[profile] = list
end

function ABS:LoadActions(profile)
	local currentProfile = self.db.profiles[profile]
	if( not currentProfile ) then
		return nil
	end
	
	for i=1, 120 do
		local type, id = GetActionInfo(i)
		if( currentProfile[i] ) then
			local crtID, crtType = string.split(":", currentProfile[i])
			crtID = tonumber(crtID)
			
			-- Make sure it's not the same thing
			if( crtType == "spell" and crtID ) then
				PickupSpell(crtID, BOOKTYPE_SPELL)
				PlaceAction(i)
				ClearCursor()

			elseif( crtType == "macro" and crtID ) then
				PickupMacro(crtID)
				PlaceAction(i)
				ClearCursor()

			elseif( crtType == "item" and crtID ) then
				local found
				for bag=0, NUM_BAG_SLOTS do
					for slot=1, GetContainerNumSlots(bag) do
						local link = GetContainerItemLink(bag, slot)
						if( link and not found ) then
							local itemid = string.match(link, "item:([0-9]+):")
							itemid = tonumber(itemid)
							
							if( itemid and itemid == crtID ) then
								PickupContainerItem(bag, slot)
								PlaceAction(i)
								ClearCursor()

								found = true
							end
						end
					end
				end
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