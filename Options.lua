--[[ 
	Action Bar Saver Options, Goranaws
]]
local ActionBarSaver = select(2, ...)
ActionBarSaver.Options = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)
ActionBarSaver.Options.name = "Action Button Saver"
InterfaceOptions_AddCategory(ActionBarSaver.Options)

local Options = ActionBarSaver.Options

Options:Hide()
Options.profileButtons = {used = {},unUsed = {}}

local overrideClass, overrideName
local forceOverride

local L = ActionBarSaver.L
local playerClass

function Options:GetDB()
	return ActionBarSaverDB
end

local stored = {}
function Options:GetAllProfiles()
	local profiles = self:GetDB().sets
	table.wipe(stored) 
	for class, profs in pairs(profiles) do
		for profileName, settings in pairs(profs) do
			local storing = {name = profileName, class = class, settings = settings}
			tinsert(stored, storing)
		end		
	end
	return stored
end

	--update options display
function Options:Reload()
	ActionBarSaver:OnInitialize()
	self.pName:SetText(overrideName or string.lower(UnitName("Player")))
	self.cName:SetText(overrideClass or playerClass)
	self:SetProfileButtons()
end

local function newButton(parent, text)
	local b = CreateFrame("Button",nil, parent, "UIMenuButtonStretchTemplate")
	b.Text:SetText(text)
	b:SetWidth(b.Text:GetWidth()+20)
	b:SetScript("OnClick", function()
		if b.click then
			b.click()
		end
	end)
	return b
end

local index = 1
local prevCheck
local function newCheck(parent, text)
	local b = CreateFrame("CheckButton","ActionBarSaverCheckButton"..index, parent, "OptionsCheckButtonTemplate")
	index = index + 1
	_G[b:GetName().."Text"]:SetText(text)
	b.offset = _G[b:GetName().."Text"]:GetWidth()
	b:SetScript("OnClick", function()
		if b.click then
			b:SetChecked(b.click())
		end
	end)
	b:SetScript("OnShow", function()
		if b.onShow then
			b:SetChecked(b.onShow())
		end
	end)
	b:SetScript("OnEnter", function()
		if b.onEnter then
			GameTooltip:SetOwner(b, "ANCHOR_BOTTOMRIGHT")
			GameTooltip:SetText(string.trim(b.onEnter), 1, 1, 1, nil, true);
			GameTooltip:Show();
		end
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end)
	b:Hide()
	
	if prevCheck then
		b:SetPoint("TopLeft", prevCheck, "BottomLeft", 0, -3)
	else
		b:SetPoint("TopLeft", parent, 10, -70)
	end
	
	prevCheck = b
	
	return b
end

Options:SetScript("OnShow", function(self)
	--Create the options menu
	playerClass = select(2, UnitClass("player"))
	
	local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetText(self.name)
	title:SetPoint("TopLeft", 10,-10)
	
	
	local pName = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
	pName:SetSize(150, 25)
	pName:SetAutoFocus(false)
	pName:SetPoint("TopLeft", 10, -40)
	local t = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	t:SetText("Profile")
	t:SetPoint("BottomLeft", pName, "TopLeft")
	self.pName = pName
	
	local cName = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
	cName:SetSize(150, 25)
	cName:SetAutoFocus(false)
	cName:SetPoint("Left", pName, "Right", 5, 0)
	local t = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	t:SetText("Class")
	t:SetPoint("BottomLeft", cName, "TopLeft")
	self.cName = cName
	
	local Save = newButton(self, "Save")
	Save:SetPoint("Left", cName, "Right", 5, 0)
	Save.click = function()
		overrideName = string.lower(string.gsub(pName:GetText(), " ", ""))
		overrideClass = playerClass
		SlashCmdList.ABS("save "..overrideName)
		Options:Reload()	
	end
	
	local Delete = newButton(self, "Delete")
	Delete:SetPoint("Left", Save, "Right", 5, 0)
	Delete.click = function()
		local arg = pName:GetText()
		self:GetDB().sets[overrideClass or playerClass][arg] = nil
		ActionBarSaver:Print(string.format(L["Deleted saved profile %s."], arg))
		Options:Reload()	
	end

	local Rename = newButton(self, "Rename")
	Rename:SetPoint("Left", Delete, "Right", 5, 0)
	Rename.click = function()
		local self = ActionBarSaver
		local arg = pName:GetText()
		local old, new = string.split(" ", arg, 2)
		new = string.trim(new or "")
		old = string.trim(old or "")
		
		if( new == old ) then
			self:Print(string.format(L["You cannot rename \"%s\" to \"%s\" they are the same profile names."], old, new))
			return
		elseif( new == "" ) then
			self:Print(string.format(L["No name specified to rename \"%s\" to."], old))
			return
		elseif( self.db.sets[overrideClass or playerClass][new] ) then
			self:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], old, new, (overrideClass or playerClass)))
			return
		elseif( not self.db.sets[overrideClass or playerClass][old] ) then
			self:Print(string.format(L["No profile with the name \"%s\" exists."], old))
			return
		end
		
		self.db.sets[overrideClass or playerClass][new] = CopyTable(self.db.sets[overrideClass or playerClass][old])
		self.db.sets[overrideClass or playerClass][old] = nil
		
		self:Print(string.format(L["Renamed \"%s\" to \"%s\""], old, new))
		overrideName = new
		Options:Reload()	
	end
	
	local Restore = newButton(self, "Restore")
	Restore:SetPoint("Left", Rename, "Right", 5, 0)
	Restore.click = function()
		if forceOverride == true then
			--override class restrictions!
			local old, new = string.split(" ", pName:GetText(), 2)
			ActionBarSaver:RestoreProfile(old, overrideClass or playerClass)
		else
			SlashCmdList.ABS("restore "..pName:GetText())
			--workaround since some of the error reporting is stored as locals in ActionButtonSaver.lua
		end
		forceOverride = nil
	end
	Restore.tooltipText = ""

	
	local Clear = newButton(self, "Clear")
	Clear:SetPoint("Left", Restore, "Right", 5, 0)
	Clear.click = function()
		ActionBarSaver:ClearActionBars()	
	end

	pName:SetScript("OnTextChanged", function()
		local t = pName:GetText()
		if string.gsub(t, " ", "") == "" then
			Save:Disable()
			Delete:Disable()
			Rename:Disable()
			Restore:Disable()
		else
			if string.find(t," ") then
				Save:Disable()
				Rename:Enable()
			else
				Save:Enable()
				Rename:Disable()
			end
			Delete:Enable()
			if (overrideClass and overrideClass ~= playerClass) and (forceOverride == nil) then
				Restore:Disable()
			else
				Restore:Enable()
			end
		end
	end)
	
	local macros = newCheck(self, "Restore Macros")
	function macros.click()
		self:GetDB().macro = not self:GetDB().macro
		return self:GetDB().macro
	end
	function macros.onShow()
		return self:GetDB().macro
	end
	local _, text = string.split("-", L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
	macros.onEnter = text

	macros:Show()
	
	local rank = newCheck(self, "Restore Highest Rank")
	function rank.click()
		self:GetDB().restoreRank = not self:GetDB().restoreRank
		return self:GetDB().restoreRank
	end
	function rank.onShow()
		return self:GetDB().restoreRank
	end
	local _, text = string.split("-", L["/abs rank - Toggles if ABS should restore the highest rank of the spell, or the one saved originally."])
	rank.onEnter = text
	rank:Show()
	
	local count = newCheck(self, "Item Count")
	function count.click()
		self:GetDB().checkCount = not self:GetDB().checkCount
		return self:GetDB().checkCount
	end
	function count.onShow()
		return self:GetDB().checkCount
	end
	local _, text = string.split("-", L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
	count.onEnter = text
	count:Show()
	
	local class = newCheck(self, "Leave Class")

	function class.onShow()
		return self:GetDB().leaveClass
	end
	local text = "Do not remove class specific spells or macros."
	class.onEnter = text
	class:Show()
	
	local noClear = newCheck(self, "Leave Current")
	
	function class.click()
		self:GetDB().leaveClass = not self:GetDB().leaveClass
		if self:GetDB().leaveClass == true then
			self:GetDB().leaveAll = nil
		end
		noClear:SetChecked(self:GetDB().leaveAll)
		return self:GetDB().leaveClass
	end
	
	function noClear.click()
		self:GetDB().leaveAll = not self:GetDB().leaveAll
		if self:GetDB().leaveAll == true then
			self:GetDB().leaveClass = nil
		end
		class:SetChecked(self:GetDB().leaveClass)
		return self:GetDB().leaveAll
	end
	function noClear.onShow()
		return self:GetDB().leaveAll
	end
	local text = "Do not remove anything from your action bars, just add new ones from the selected profile."
	noClear.onEnter = text
	noClear:Show()
	
	

	local ignorePlacement = newCheck(self, "Ignore Class")
	function ignorePlacement.click()
		self:GetDB().ignoreClass = not self:GetDB().ignoreClass
		return self:GetDB().ignoreClass
	end
	function ignorePlacement.onShow()
		return self:GetDB().ignoreClass
	end
	local text = "Ignore any spells or macros not specific to your current class."
	ignorePlacement.onEnter = text
	ignorePlacement:Show()
	
	
	
	local buttonContainer = CreateFrame("Frame",nil, self)

	buttonContainer:SetPoint("TopLeft", prevCheck, "BottomLeft", 0, -25)
	buttonContainer:SetPoint("BottomRight", 25, 10)

	self.bc = buttonContainer
	

	local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetText("Saved Profiles")
	title:SetPoint("BottomLeft", self.bc, "TopLeft", 10,5)
	
	self:SetScript("OnEvent", self.Reload)
	self:RegisterEvent("ADDON_LOADED")
	self:SetScript("OnShow", self.Reload)
	self:SetScript("OnSizeChanged", self.SetProfileButtons)
	Options:Reload()	
end)

local used = {}
local unused = {}

function Options:getButton(index)
	if used[index] then
		return used[index]
	else
		if #unused ~= 0 then
			local b = unused[1]
			tremove(unused, 1)
			tinsert(used, b)
			return b
		else
			local b = newButton(self.bc, "")
			b:SetWidth(125)
			tinsert(used, b)
			return b
		end
	end
end

local W, H = 125, 26
local maxCols, maxRows = 4, 12


function Options:SetProfileButtons()
	local profiles = self:GetAllProfiles()
	while #used > #profiles do
		used[1]:Hide()
		tinsert(unused, used[1])
		
		tremove(used, 1)
	end
	
	local height = H + ((self.bc:GetHeight() - (maxRows * H)) / maxRows)
	local width  = W + ((self.bc:GetWidth()  - (maxCols * W)) / maxCols)
	
	for index, profile in pairs(profiles) do
		local b = self:getButton(index)
		b.Text:SetText(profile.name)
		--this extra line below makes the tooltip display the profile name on one line, and class on the second.
		b.tooltipText = profile.name..[[

]]..profile.class

		b.click = function()
			overrideClass = profile.class
			overrideName = profile.name
			if IsShiftKeyDown() then
				forceOverride = true
			else
				forceOverride = nil
			end
			self:Reload()	
		end
		
		local row = (index - 1) % maxRows
		local col = floor((index - 1) / maxRows)
		
		local x = width * col
		local y = height * row
		
		if x and y then
			b:ClearAllPoints()
			b:SetPoint("TopLeft", x, -y)
		end
		
		b:Show()
	end
end