--[[
Copyright (c) 2010, Hendrik "nevcairiel" Leppkes <h.leppkes@gmail.com>

All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, 
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, 
      this list of conditions and the following disclaimer in the documentation 
      and/or other materials provided with the distribution.
    * Neither the name of the developer nor the names of its contributors 
      may be used to endorse or promote products derived from this software without 
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

]]
local MAJOR_VERSION = "LibActionButton-1.0"
local MINOR_VERSION = 1

if not LibStub then error(MAJOR_VERSION .. " requires LibStub.") end
local lib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end

local CBH = LibStub("CallbackHandler-1.0")

local Generic = CreateFrame("CheckButton")
local Generic_MT = {__index = Generic}

local Action = setmetatable({}, {__index = Generic})
local Action_MT = {__index = Action}

local PetAction = setmetatable({}, {__index = Generic})
local PetAction_MT = {__index = PetAction}

local Spell = setmetatable({}, {__index = Generic})
local Spell_MT = {__index = Spell}

local Item = setmetatable({}, {__index = Generic})
local Item_MT = {__index = Item}

local Macro = setmetatable({}, {__index = Generic})
local Macro_MT = {__index = Macro}

local state_meta_map = {
	empty  = Generic_MT,
	action = Action_MT,
	pet    = PetAction_MT,
	spell  = Spell_MT,
	item   = Item_MT,
	macro  = Macro_MT
}

local Update, UpdateButtonState, UpdateUsable, UpdateCount, UpdateCooldown, UpdateTooltip
local StartFlash, StopFlash, UpdateFlash, UpdateHotkeys

--- Create a new action button.
-- @param id Internal id of the button (not used by LibActionButton-1.0, only for tracking inside the calling addon)
-- @param name Name of the button frame to be created (not used by LibActionButton-1.0 aside from naming the frame)
-- @param header Header that drives these action buttons (if any)
function lib:CreateButton(id, name, header)
	if type(name) ~= "string" then
		error("Usage: CreateButton(id, name. header): Buttons must have a valid name!", 2)
	end
	if not header then
		error("Usage: CreateButton(id, name, header): Buttons without a secure header are not yet supported!", 2)
	end

	local button = setmetatable(CreateFrame("CheckButton", name, UIParent, "SecureActionButtonTemplate, ActionButtonTemplate"), Generic_MT)

	button.id = id
	button.header = header
	-- Mapping of state -> action
	button.state_types = {}
	button.state_actions = {}

	-- just in case we're not run by a header, default to state 1
	button:SetAttribute("state", 1)

	-- securefunction UpdateState(self, state)
	-- update the type and action of the button based on the state
	button:SetAttribute("UpdateState", [[
		-- note that GetAttribute("state") is not guaranteed to return the current state in this method!
		local state = ...
		local type, action = self:GetAttribute(format("type-%d", state)), self:GetAttribute(format("action-%d", state))
		print(state, type, action)

		local action_field = type
		if type == "pet" then
			action_field = "action"
		end

		self:SetAttribute("type", type)
		self:SetAttribute(action_field, action)
	]])

	-- this function is invoked by the header when the state changes
	button:SetAttribute("_childupdate-state", [[
		control:RunFor(self, self:GetAttribute("UpdateState"), message)
		-- set it after refreshing the other attributes, so the OnAttributeChanged callback can catch it with updated informations
		self:SetAttribute("state", message)
	]])

	-- register for attribute changes
	button:SetScript("OnAttributeChanged", Generic.OnAttributeChanged)

	button.icon               = _G[name .. "Icon"]
	button.flash              = _G[name .. "Flash"]
	button.flyoutBorder       = _G[name .. "FlyoutBorder"]
	button.flyoutBorderShadow = _G[name .. "FlyoutBorderShadow"]
	button.flyoutArrow        = _G[name .. "FlyoutArrow"]
	button.hotkey             = _G[name .. "HotKey"]
	button.count              = _G[name .. "Count"]
	button.actionName         = _G[name .. "Name"]
	button.border             = _G[name .. "Border"]
	button.cooldown           = _G[name .. "Cooldown"]
	button.normalTexture      = _G[name .. "NormalTexture"]

	return button
end

-----------------------------------------------------------
--- state management

function Generic:OnAttributeChanged(attr, value)
	if attr == "state" then
		self:UpdateAction()
	end
end

function Generic:ClearStates()
	for state in pairs(self.state_types) do
		self:SetAttribute(format("type-%d", state), nil)
		self:SetAttribute(format("action-%d", state), nil)
	end
	wipe(self.state_types)
	wipe(self.state_actions)
end

function Generic:SetState(state, type, action)
	state = tonumber(state)
	if state ~= 1 and not self.header then
		error("SetStateAction: state ~= 1 requires a secure header!", 2)
	end
	self.state_types[state] = type
	self.state_actions[state] = action
	self:UpdateState(state)
end

function Generic:UpdateState(state)
	state = tonumber(state)
	self:SetAttribute(format("type-%d", state), self.state_types[state])
	self:SetAttribute(format("action-%d", state), self.state_actions[state])
	if state ~= self:GetAttribute("state") then return end
	if self.header then
		self.header:SetFrameRef("updateButton", self)
		self.header:Execute([[
			local frame = self:GetFrameRef("updateButton")
			control:RunFor(frame, frame:GetAttribute("UpdateState"), frame:GetAttribute("state"))
		]])
	else
	-- TODO
	end
	self:UpdateAction()
end

function Generic:GetAction(state)
	if not state then state = self:GetAttribute("state") end
	state = tonumber(state)
	return self.state_types[state], self.state_actions[state]
end

function Generic:UpdateAllStates()
	for state in pairs(self.state_types) do
		self:UpdateState(state)
	end
end

-----------------------------------------------------------
--- button management

function Generic:UpdateAction(force)
	local type, action = self:GetAction()
	if force or type ~= self._state_type or action ~= self._state_action then
		-- type changed, update the metatable
		if self._state_type ~= type then
			local meta = state_meta_map[type] or state_meta_map["empty"]
			setmetatable(self, meta)
			self._state_type = type
		end
		self._state_action = action
		Update(self)
	end
end

function Update(self)
	if not self:IsEmpty() then
	-- TODO: Show button
		UpdateButtonState(self)
		UpdateUsable(self)
		UpdateCooldown(self)
		UpdateFlash(self)
	else
	-- TODO: Hide button
		self.cooldown:Hide()
	end

	-- Add a green border if button is an equipped item
	if self:IsEquipped() then
		self.border:SetVertexColor(0, 1.0, 0, 0.35)
		self.border:Show()
	else
		self.border:Hide()
	end

	-- Update Action Text
	if not self:IsConsumableOrStackable() then
		self.actionName:SetText(self:GetActionText())
	else
		self.actionName:SetText("")
	end

	-- Update icon and hotkey
	local texture = self:GetTexture()
	if texture then
		self.icon:SetTexture(texture)
		self.icon:Show()
		self.rangeTimer = - 1
		self:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
	else
		self.icon:Hide()
		self.cooldown:Hide()
		self.rangeTimer = nil
		self:SetNormalTexture("Interface\\Buttons\\UI-Quickslot")
		if self.hotkey:GetText() == RANGE_INDICATOR then
			self.hotkey:Hide()
		else
			self.hotkey:SetVertexColor(0.6, 0.6, 0.6)
		end
	end

	self:UpdateLocal()

	UpdateCount(self)

	-- TODO: Update flyout
	-- TODO: Update Overlay Glow

	if GameTooltip:GetOwner() == self then
		UpdateTooltip()
	end
end

function Generic:UpdateLocal()
-- dummy function the other button types can override for special updating
end

function UpdateButtonState(self)
	if self:IsCurrentlyActive() or self:IsAutoRepeat() then
		self:SetChecked(1)
	else
		self:SetChecked(0)
	end
end

function UpdateUsable(self)
	local isUsable, notEnoughMana = self:IsUsable()
	-- TODO: make the colors configurable
	-- TODO: allow disabling of the whole recoloring
	if isUsable then
		self.icon:SetVertexColor(1.0, 1.0, 1.0)
		self.normalTexture:SetVertexColor(1.0, 1.0, 1.0)
	elseif notEnoughMana then
		self.icon:SetVertexColor(0.5, 0.5, 1.0)
		self.normalTexture:SetVertexColor(0.5, 0.5, 1.0)
	else
		self.icon:SetVertexColor(0.4, 0.4, 0.4)
		self.normalTexture:SetVertexColor(1.0, 1.0, 1.0)
	end
end

function UpdateCount(self)
	if self:IsConsumableOrStackable() then
		local count = self:GetCount()
		if count > (self.maxDisplayCount or 9999) then
			self.count:SetText("*")
		else
			self.count:SetText(count)
		end
	else
		self.count:SetText("")
	end
end

function UpdateCooldown(self)
	local start, duration, enable = self:GetCooldown()
	CooldownFrame_SetTimer(self.cooldown, start, duration, enable)
end

function StartFlash(self)
	self.flashing = 1
	self.flashtime = 0
	UpdateButtonState(self)
end

function StopFlash(self)
	self.flashing = 0
	self.flash:Hide()
	UpdateButtonState(self)
end

function UpdateFlash(self)
	if (self:IsAttack() and self:IsCurrentlyActive()) or self:IsAutoRepeat() then
		StartFlash(self)
	else
		StopFlash(self)
	end
end

function UpdateTooltip(self)
	if (GetCVar("UberTooltips") == "1") then
		GameTooltip_SetDefaultAnchor(GameTooltip, self);
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	end
	if self:SetTooltip() then
		self.UpdateTooltip = UpdateTooltip
	else
		self.UpdateTooltip = nil
	end
end

function UpdateHotkeys(self)
	local key = GetBindingKey("CLICK " .. self:GetName() .. ":LeftButton")
	local text = GetBindingText(key, "KEY_", 1)
	if text == "" then
		self.hotkey:SetText(RANGE_INDICATOR)
		self.hotkey:SetPoint("TOPLEFT", self, "TOPLEFT", 1, - 2)
		self.hotkey:Hide()
	else
		self.hotkey:SetText(text)
		self.hotkey:SetPoint("TOPLEFT", self, "TOPLEFT", - 2, - 2)
		self.hotkey:Show()
	end
end

-----------------------------------------------------------
--- WoW API mapping
--- Generic Button
Generic.IsEmpty                 = function(self) return true end
Generic.GetActionText           = function(self) return "" end
Generic.GetTexture              = function(self) return nil end
Generic.GetCount                = function(self) return 0 end
Generic.GetCooldown             = function(self) return nil end
Generic.IsAttack                = function(self) return nil end
Generic.IsEquipped              = function(self) return nil end
Generic.IsCurrentlyActive       = function(self) return nil end
Generic.IsAutoRepeat            = function(self) return nil end
Generic.IsUsable                = function(self) return nil end
Generic.IsConsumableOrStackable = function(self) return nil end
Generic.IsInRange               = function(self) return nil end
Generic.SetTooltip              = function(self) return nil end

-----------------------------------------------------------
--- Action Button
Action.IsEmpty                 = function(self) return not HasAction(self._state_action) end
Action.GetActionText           = function(self) return GetActionText(self._state_action) end
Action.GetTexture              = function(self) return GetActionTexture(self._state_action) end
Action.GetCount                = function(self) return GetActionCount(self._state_action) end
Action.GetCooldown             = function(self) return GetActionCooldown(self._state_action) end
Action.IsAttack                = function(self) return IsAttackAction(self._state_action) end
Action.IsEquipped              = function(self) return IsEquippedAction(self._state_action) end
Action.IsCurrentlyActive       = function(self) return IsCurrentAction(self._state_action) end
Action.IsAutoRepeat            = function(self) return IsAutoRepeatAction(self._state_action) end
Action.IsUsable                = function(self) return IsUsableAction(self._state_action) end
Action.IsConsumableOrStackable = function(self) return IsConsumableAction(self._state_action) or IsStackableAction(self._state_action) end
Action.IsInRange               = function(self) return IsActionInRange(self._state_action) end
Action.SetTooltip              = function(self) return GameTooltip:SetAction(self._state_action) end
