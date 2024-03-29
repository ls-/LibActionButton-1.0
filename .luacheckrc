std = "lua51"
max_line_length = false
exclude_files = {
	".luacheckrc"
}

ignore = {
	"211/_.*", -- Unused local variable starting with _
	"212", -- unused argument
	"542", -- empty if branch
}

globals = {

}

read_globals = {
	"format",
	"hooksecurefunc",
	"tinsert", "tremove",
	"wipe",

	-- Third Party AddOns/Libraries
	"LibStub",

	-- API categories
	"C_LevelLink",
	"C_ActionBar",
	"C_UnitAuras",

	-- API functions
	"ClearCursor",
	"CreateFrame",
	"FindSpellBookSlotBySpellID",
	"FlyoutHasSpell",
	"GetActionCharges",
	"GetActionCooldown",
	"GetActionCount",
	"GetActionInfo",
	"GetActionLossOfControlCooldown",
	"GetActionText",
	"GetActionTexture",
	"GetBindingKey",
	"GetBindingText",
	"GetBuildInfo",
	"GetCallPetSpellInfo",
	"GetCursorInfo",
	"GetCVar",
	"GetCVarBool",
	"GetFlyoutInfo",
	"GetFlyoutSlotInfo",
	"GetItemIcon",
	"GetItemCooldown",
	"GetItemCount",
	"GetLastZoneAbilitySpellTexture",
	"GetMacroInfo",
	"GetMacroSpell",
	"GetMouseFocus",
	"GetSpellCharges",
	"GetSpellCooldown",
	"GetSpellCount",
	"GetSpellInfo",
	"GetSpellLossOfControlCooldown",
	"GetSpellTexture",
	"GetTime",
	"HasAction",
	"HasZoneAbility",
	"InCombatLockdown",
	"IsActionInRange",
	"IsAttackAction",
	"IsAttackSpell",
	"IsAutoRepeatAction",
	"IsAutoRepeatSpell",
	"IsConsumableAction",
	"IsConsumableItem",
	"IsConsumableSpell",
	"IsCurrentAction",
	"IsCurrentItem",
	"IsCurrentSpell",
	"IsEquippedAction",
	"IsEquippedItem",
	"IsItemAction",
	"IsItemInRange",
	"IsLoggedIn",
	"IsMouseButtonDown",
	"IsSpellInRange",
	"IsSpellOverlayed",
	"IsStackableAction",
	"IsUsableAction",
	"IsUsableItem",
	"IsUsableSpell",
	"PickupAction",
	"PickupCompanion",
	"PickupEquipmentSet",
	"PickupItem",
	"PickupMacro",
	"PickupPetAction",
	"PickupSpell",
	"SetBinding",
	"SetBindingClick",
	"SetCVar",

	-- FrameXML API
	"ActionBarController_UpdateAllSpellHighlights",
	"ActionButton_HideOverlayGlow",
	"ActionButton_UpdateFlyout",
	"CooldownFrame_Set",
	"GameTooltip_SetDefaultAnchor",
	"SetClampedTextureRotation",

	-- FrameXML Frames
	"GameTooltip",
	"SpellFlyout",
	"UIParent",

	-- Fonts
	"GameFontHighlightSmallOutline",
	"NumberFontNormal",
	"NumberFontNormalSmallGray",

	-- FrameXML Constants
	"ACTION_HIGHLIGHT_MARKS",
	"ATTACK_BUTTON_FLASH_TIME",
	"COOLDOWN_TYPE_LOSS_OF_CONTROL",
	"COOLDOWN_TYPE_NORMAL",
	"RANGE_INDICATOR",
	"TOOLTIP_UPDATE_TIME",
	"WOW_PROJECT_ID",
	"WOW_PROJECT_MAINLINE",
	"WOW_PROJECT_CLASSIC",
	"WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
	"WOW_PROJECT_WRATH_CLASSIC",
}
