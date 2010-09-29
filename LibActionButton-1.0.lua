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

local type_meta_map = {
	empty  = Generic_MT,
	action = Action_MT,
	pet    = PetAction_MT,
	spell  = Spell_MT,
	item   = Item_MT,
	macro  = Macro_MT
}

local ButtonRegistry, ActiveButtons = {}, {}

local Update, UpdateButtonState, UpdateUsable, UpdateCount, UpdateCooldown, UpdateTooltip
local StartFlash, StopFlash, UpdateFlash, UpdateHotkeys, UpdateRangeTimer, UpdateOverlayGlow

local InitializeEventHandler, OnEvent, ForAllButtons

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
	button:RegisterForDrag("LeftButton", "RightButton")
	button:RegisterForClicks("AnyUp")

	-- Frame Scripts
	button:SetScript("OnEnter", Generic.OnEnter)
	button:SetScript("OnLeave", Generic.OnLeave)
	button:SetScript("PostClick", Generic.PostClick)

	button.id = id
	button.header = header
	-- Mapping of state -> action
	button.state_types = {}
	button.state_actions = {}

	-- Store the LAB Version that created this button for debugging
	button.__LAB_Version = MINOR_VERSION

	-- just in case we're not run by a header, default to state 1
	button:SetAttribute("state", 1)

	-- secure UpdateState(self, state)
	-- update the type and action of the button based on the state
	button:SetAttribute("UpdateState", [[
		-- note that GetAttribute("state") is not guaranteed to return the current state in this method!
		local state = ...
		self:SetAttribute("state", state)
		local type, action = (self:GetAttribute(format("labtype-%d", state)) or "empty"), self:GetAttribute(format("labaction-%d", state))

		self:SetAttribute("type", type)
		if type ~= "empty" then
			local action_field = (type == "pet") and "action" or type
			self:SetAttribute(action_field, action)
			self:SetAttribute("action_field", action_field)
		end
	]])

	-- this function is invoked by the header when the state changes
	button:SetAttribute("_childupdate-state", [[
		self:RunAttribute("UpdateState", message)
		self:CallMethod("UpdateAction")
	]])

	-- secure PickupButton(self, kind, value, ...)
	-- utility function to place a object on the cursor
	button:SetAttribute("PickupButton", [[
		local kind, value = ...
		print("pickup", kind, value)
		if kind == "empty" then
			return "clear"
		elseif kind == "action" or kind == "spell" or kind == "item" or kind == "macro" or kind == "pet" then
			local actionType = (kind == "pet") and "petaction" or kind
			return actionType, value
		else
			print("LibActionButton-1.0: Unknown type: " .. tostring(kind))
			return false
		end
	]])

	-- Wrapped OnDragStart(self, button, kind, value, ...)
	header:WrapScript(button, "OnDragStart", [[
		local subtype = ...
		local state = self:GetAttribute("state")
		local type = self:GetAttribute("type")
		-- if the button is empty, we can't drag anything off it
		if type == "empty" then
			return false
		end
		-- Get the value for the action attribute
		local action_field = self:GetAttribute("action_field")
		local action = self:GetAttribute(action_field)

		-- non-action fields need to change their type to empty
		if type ~= "action" and type ~= "pet" then
			self:SetAttribute(format("labtype-%d", state), "empty")
			self:SetAttribute(format("labaction-%d", state), nil)
			-- update internal state
			self:RunAttribute("UpdateState", state)
			-- send a notification to the insecure code
			self:CallMethod("ButtonContentsChanged", state, "empty", nil)
		end
		-- return the button contents for pickup
		return self:RunAttribute("PickupButton", type, action)
	]])

	-- Wrapped OnReceiveDrag(self, button, kind, value, ...)
	header:WrapScript(button, "OnReceiveDrag", [[
		local subtype = ...
		local state = self:GetAttribute("state")
		local buttonType, buttonAction = self:GetAttribute("type"), nil
		-- action buttons can do their magic themself
		-- for all other buttons, we'll need to update the content now
		if buttonType ~= "action" and buttonType ~= "pet" then
			-- We get spell book ids from CursorInfo
			-- Convert them to actual spell ids
			if kind == "spell" then
				-- TODO: This needs either an API update or a lookup table
				local stype, sid -- = GetSpellBookItemInfo(value, subtype)
				if stype == "SPELL" then
					value = sid
				else
					-- we don't accept anything else then spells from the spellbook
					return false
				end
			end

			-- Get the action that was on the button before
			if buttonType ~= "empty" then
				buttonAction = self:GetAttribute(self:GetAttribute("action_field"))
			end

			-- TODO: validate what kind of action is being fed in here
			-- We can only use a handful of the possible things on the cursor
			-- return false for all those we can't put on buttons

			self:SetAttribute(format("labtype-%d", state), kind)
			self:SetAttribute(format("labaction-%d", state), value)
			-- update internal state
			self:RunAttribute("UpdateState", state)
			-- send a notification to the insecure code
			self:CallMethod("ButtonContentsChanged", state, kind, value)
		else
			-- get the action for (pet-)action buttons
			buttonAction = self:GetAttribute("action")
		end
		return self:RunAttribute("PickupButton", buttonType, buttonAction)
	]])

	-- Store all sub frames on the button object for easier access
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

	-- Store the button in the registry, needed for event and OnUpdate handling
	if not next(ButtonRegistry) then
		InitializeEventHandler()
	end
	ButtonRegistry[button] = true

	-- run an initial update
	button:UpdateAction()
	UpdateHotkeys(button)

	return button
end

-----------------------------------------------------------
--- state management

function Generic:ClearStates()
	for state in pairs(self.state_types) do
		self:SetAttribute(format("labtype-%d", state), nil)
		self:SetAttribute(format("labaction-%d", state), nil)
	end
	wipe(self.state_types)
	wipe(self.state_actions)
end

function Generic:SetState(state, kind, action)
	state = tonumber(state)
	-- we allow a nil kind for setting a empty state
	if not kind then kind = "empty" end
	if not type_meta_map[kind] then
		error("SetStateAction: unknown action type: %s" .. tostring(kind), 2)
	end
	if kind ~= "empty" and action == nil then
		error("SetStateAction: an action is required for non-empty states", 2)
	end
	if action ~= nil and type(action) ~= "number" and type(action) ~= "string" then
		error("SetStateAction: invalid action data type, only strings and numbers allowed", 2)
	end
	self.state_types[state] = kind
	self.state_actions[state] = action
	self:UpdateState(state)
end

function Generic:UpdateState(state)
	state = tonumber(state)
	self:SetAttribute(format("labtype-%d", state), self.state_types[state])
	self:SetAttribute(format("labaction-%d", state), self.state_actions[state])
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
	return self.state_types[state] or "empty", self.state_actions[state]
end

function Generic:UpdateAllStates()
	for state in pairs(self.state_types) do
		self:UpdateState(state)
	end
end

function Generic:ButtonContentsChanged(state, kind, value)
	print("button contents changed", state, kind, value)
	self.state_types[state] = kind or "emtpy"
	self.state_actions[state] = value
	-- TODO: Notify addon about this
	self:UpdateAction(self)
end

-----------------------------------------------------------
--- frame scripts

function Generic:OnEnter()
	UpdateTooltip(self)
end

function Generic:OnLeave()
	GameTooltip:Hide()
end

function Generic:PostClick()
	UpdateButtonState(self)
end

-----------------------------------------------------------
--- event handler

function ForAllButtons(method, onlyWithAction, ...)
	assert(type(method) == "function")
	for button in next, (onlyWithAction and ActiveButtons or ButtonRegistry) do
		method(button, ...)
	end
end

function InitializeEventHandler()
	-- I'm abusing the "Generic" base frame as event handler
	Generic:SetScript("OnEvent", OnEvent)
	Generic:RegisterEvent("PLAYER_ENTERING_WORLD")
	Generic:RegisterEvent("ACTIONBAR_SHOWGRID")
	Generic:RegisterEvent("ACTIONBAR_HIDEGRID")
	Generic:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
	Generic:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	Generic:RegisterEvent("UPDATE_BINDINGS")
	Generic:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

	Generic:RegisterEvent("ACTIONBAR_UPDATE_STATE")
	Generic:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
	Generic:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	Generic:RegisterEvent("PLAYER_TARGET_CHANGED")
	Generic:RegisterEvent("TRADE_SKILL_SHOW")
	Generic:RegisterEvent("TRADE_SKILL_CLOSE")
	Generic:RegisterEvent("ARCHAEOLOGY_CLOSED")
	Generic:RegisterEvent("PLAYER_ENTER_COMBAT")
	Generic:RegisterEvent("PLAYER_LEAVE_COMBAT")
	Generic:RegisterEvent("START_AUTOREPEAT_SPELL")
	Generic:RegisterEvent("STOP_AUTOREPEAT_SPELL")
	Generic:RegisterEvent("UNIT_ENTERED_VEHICLE")
	Generic:RegisterEvent("UNIT_EXITED_VEHICLE")
	Generic:RegisterEvent("COMPANION_UPDATE")
	Generic:RegisterEvent("UNIT_INVENTORY_CHANGED")
	Generic:RegisterEvent("LEARNED_SPELL_IN_TAB")
	Generic:RegisterEvent("PET_STABLE_UPDATE")
	Generic:RegisterEvent("PET_STABLE_SHOW")
	Generic:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
	Generic:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

	-- With those two, do we still need the ACTIONBAR equivalents of them?
	Generic:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	Generic:RegisterEvent("SPELL_UPDATE_USABLE")
end

function OnEvent(frame, event, arg1, ...)
	if (event == "UNIT_INVENTORY_CHANGED" and arg1 == "player") or event == "LEARNED_SPELL_IN_TAB" then
		local tooltipOwner = GameTooltip:GetOwner()
		if ButtonRegistry[tooltipOwner] then
			tooltipOwner:SetTooltip()
		end
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		for button in next, ButtonRegistry do
			if button._state_type == "action" and (arg1 == 0 or arg1 == tonumber(button._state_action)) then
				Update(button)
			end
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_SHAPESHIFT_FORM" then
		ForAllButtons(Update)
	elseif event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
		-- TODO: Are these even needed?
	elseif event == "ACTIONBAR_SHOWGRID" then
		-- TODO
	elseif event == "ACTIONBAR_HIDEGRID" then
		-- TODO
	elseif event == "UPDATE_BINDINGS" then
		ForAllButtons(UpdateHotkeys)
	elseif event == "PLAYER_TARGET_CHANGED" then
		ForAllButtons(UpdateRangeTimer, true)
	elseif (event == "ACTIONBAR_UPDATE_STATE") or
		((event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and (arg1 == "player")) or
		((event == "COMPANION_UPDATE") and (arg1 == "MOUNT")) then
		ForAllButtons(UpdateButtonState, true)
	elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "SPELL_UPDATE_USABLE" then
		ForAllButtons(UpdateUsable, true)
	elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
		ForAllButtons(UpdateCooldown, true)
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE"  or event == "ARCHAEOLOGY_CLOSED" then
		ForAllButtons(UpdateButtonState, true)
	elseif event == "PLAYER_ENTER_COMBAT" then
		for button in next, ActiveButtons do
			if button:IsAttack() then
				StartFlash(button)
			end
		end
	elseif event == "PLAYER_LEAVE_COMBAT" then
		for button in next, ActiveButtons do
			if button:IsAttack() then
				StopFlash(button)
			end
		end
	elseif event == "START_AUTOREPEAT_SPELL" then
		for button in next, ActiveButtons do
			if button:IsAutoRepeat() then
				StartFlash(button)
			end
		end
	elseif event == "STOP_AUTOREPEAT_SPELL" then
		for button in next, ActiveButtons do
			if button.flashing == 1 and not button:IsAttack() then
				StopFlash(button)
			end
		end
	elseif event == "PET_STABLE_UPDATE" or event == "PET_STABLE_SHOW" then
		ForAllButtons(UpdateUsable, true)
	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
		for button in next, ActiveButtons do
			local spellId = button:GetSpellId()
			if spellId and spellId == arg1 then
				ActionButton_ShowOverlayGlow(button)
			end
		end
	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
		for button in next, ActiveButtons do
			local spellId = button:GetSpellId()
			if spellId and spellId == arg1 then
				ActionButton_HideOverlayGlow(button)
			end
		end
	end
end

-----------------------------------------------------------
--- button management

function Generic:UpdateAction(force)
	local type, action = self:GetAction()
	if force or type ~= self._state_type or action ~= self._state_action then
		-- type changed, update the metatable
		if self._state_type ~= type then
			local meta = type_meta_map[type] or type_meta_map.empty
			setmetatable(self, meta)
			self._state_type = type
		end
		self._state_action = action
		Update(self)
	end
end

function Update(self)
	if self:HasAction() then
		ActiveButtons[self] = true
		-- TODO: Show button
		UpdateButtonState(self)
		UpdateUsable(self)
		UpdateCooldown(self)
		UpdateFlash(self)
	else
		ActiveButtons[self] = nil
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
	UpdateOverlayGlow(self)

	if GameTooltip:GetOwner() == self then
		UpdateTooltip(self)
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

function UpdateOverlayGlow(self)
	local spellId = self:GetSpellId()
	if spellId and IsSpellOverlayed(spellId) then
		ActionButton_ShowOverlayGlow(self)
	else
		ActionButton_HideOverlayGlow(self)
	end
end

function UpdateRangeTimer(self)
	self.rangeTimer = -1
end

-----------------------------------------------------------
--- WoW API mapping
--- Generic Button
Generic.HasAction               = function(self) return nil end
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
Generic.GetSpellId              = function(self) return nil end

-----------------------------------------------------------
--- Action Button
Action.HasAction               = function(self) return HasAction(self._state_action) end
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
Action.GetSpellId              = function(self) local actionType, id, subType = GetActionInfo(self._state_action) return actionType == "spell" and id or nil end

-----------------------------------------------------------
--- Spell Button
Spell.HasAction               = function(self) return true end
Spell.GetActionText           = function(self) return "" end
Spell.GetTexture              = function(self) return GetSpellTexture(self._state_action) end
Spell.GetCount                = function(self) return GetSpellCount(self._state_action) end
Spell.GetCooldown             = function(self) return GetSpellCooldown(self._state_action) end
Spell.IsAttack                = function(self) return IsAttackSpell(FindSpellBookSlotBySpellID(self._state_action), "spell") end -- needs spell book id as of 4.0.1.13066
Spell.IsEquipped              = function(self) return false end
Spell.IsCurrentlyActive       = function(self) return IsCurrentSpell(self._state_action) end
Spell.IsAutoRepeat            = function(self) return IsAutoRepeatSpell(FindSpellBookSlotBySpellID(self._state_action), "spell") end -- needs spell book id as of 4.0.1.13066
Spell.IsUsable                = function(self) return IsUsableSpell(self._state_action) end
Spell.IsConsumableOrStackable = function(self) return IsConsumableSpell(self._state_action) end
Spell.IsInRange               = function(self) return IsSpellInRange(FindSpellBookSlotBySpellID(self._state_action), "spell", "target") end -- needs spell book id as of 4.0.1.13066
Spell.SetTooltip              = function(self) return GameTooltip:SetSpellByID(self._state_action) end
Spell.GetSpellId              = function(self) return self._state_action end
