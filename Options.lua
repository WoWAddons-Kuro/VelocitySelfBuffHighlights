-- Velocity Self Buff Highlights: settings page.
--
-- Section 1: one checkbox per reminder of the player's class (default on).
-- Section 2: every macro the character has (account tab, then character tab), each with two
--            checkboxes - Melee and Ranged - meaning "buttons holding this macro mirror that
--            auto-attack state". Rebuilt on UPDATE_MACROS. Stored per class by macro NAME.
local ADDON, VSBH = ...

local optionsCategory, optionsFrame
local WIDTH = 580
local ROW_H = 24

--------------------------------------------------------------------------------
-- Mirror settings (per class, by macro name).
--------------------------------------------------------------------------------
function VSBH.MirrorSettings(macroName)
	if not VSBH.db then return nil end
	local byClass = VSBH.db.mirrors[VSBH.playerClass]
	return byClass and byClass[macroName] or nil
end

function VSBH.SetMirror(macroName, which, enabled)
	if not VSBH.db then return end
	local byClass = VSBH.db.mirrors[VSBH.playerClass]
	if not byClass then byClass = {}; VSBH.db.mirrors[VSBH.playerClass] = byClass end
	local m = byClass[macroName] or {}
	m[which] = enabled and true or nil
	if not m.melee and not m.ranged then m = nil end
	byClass[macroName] = m
	if VSBH.RefreshMirrors then VSBH.RefreshMirrors() end
end

-- { { name, icon, account = bool }, ... } account macros first, then character macros.
-- GetNumMacros() can report 0 until the macro frame has been opened once on this session, so
-- macros currently on the action bars are merged in as well (they are what matters anyway).
local function ListMacros()
	local out = {}
	local seen = {}
	local nAccount, nChar = GetNumMacros()
	for i = 1, (nAccount or 0) do
		local name, icon = GetMacroInfo(i)
		if name and not seen[name] then seen[name] = true; out[#out + 1] = { name = name, icon = icon, account = true } end
	end
	for i = 1, (nChar or 0) do
		-- character macros follow the account block; the block size constant is absent on Forever
		local base = MAX_ACCOUNT_MACROS or 120
		local name, icon = GetMacroInfo(base + i)
		if name and not seen[name] then seen[name] = true; out[#out + 1] = { name = name, icon = icon, account = false } end
	end
	VSBH.ForEachActionButton(function(button, _, macroName)
		if macroName and not seen[macroName] then
			seen[macroName] = true
			local icon = button.icon and button.icon.GetTexture and button.icon:GetTexture() or nil
			if issecretvalue and issecretvalue(icon) then icon = nil end
			out[#out + 1] = { name = macroName, icon = icon, account = nil, onBar = true }
		end
	end)
	if #out == 0 then
		VSBH.Log("no macros found: GetNumMacros=%s/%s. Open the macro window once (Esc > Macros) and reopen this page.",
			tostring(nAccount), tostring(nChar))
	end
	return out
end
VSBH.ListMacros = ListMacros

function VSBH.DebugMacros()
	local nAccount, nChar = GetNumMacros()
	VSBH.Log("GetNumMacros = %s / %s, MAX_ACCOUNT_MACROS = %s", tostring(nAccount), tostring(nChar), tostring(MAX_ACCOUNT_MACROS))
	VSBH.ForEachActionButton(function(button, spellID, macroName)
		local kind, id = GetActionInfo(button.action or 0)
		if kind == "macro" then VSBH.Log("  %s: macro id %s name %s", button:GetName(), tostring(id), tostring(macroName)) end
	end)
	for i, m in ipairs(ListMacros()) do VSBH.Log("  list %d: %s", i, m.name) end
end

--------------------------------------------------------------------------------
-- Page.
--------------------------------------------------------------------------------
local function NewCheck(parent, label)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	local text = cb.Text or _G[cb:GetName() and (cb:GetName() .. "Text")]
	if text then text:SetText(label); text:SetFontObject("GameFontHighlight") end
	return cb
end

local function CreateOptions()
	if optionsFrame then return end
	optionsFrame = CreateFrame("Frame", "VelocitySelfBuffHighlightsOptions")
	optionsFrame.name = "Velocity Self Buff Highlights"

	local title = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16); title:SetText("Velocity Self Buff Highlights")
	local sub = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); sub:SetWidth(WIDTH); sub:SetJustifyH("LEFT")
	sub:SetText("Buff reminders glow the spell's action button while the buff is not on you. Auto-attack mirrors draw the melee / ranged auto state on the macro buttons you tick below.")

	-- Section 1: reminders
	local h1 = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	h1:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
	local className = UnitClass("player")
	h1:SetText("Buff reminders (" .. className .. ")")
	local reminderChecks = {}
	local last = h1
	local any = false
	for _, r in ipairs(VSBH.Reminders) do
		if r.class == VSBH.playerClass then
			any = true
			local cb = NewCheck(optionsFrame, r.label)
			cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == h1 and -2 or 0, last == h1 and -6 or -2)
			cb:SetScript("OnClick", function(self) VSBH.SetReminderEnabled(r, self:GetChecked() and true or false) end)
			cb.Update = function(self) self:SetChecked(VSBH.IsReminderEnabled(r)) end
			reminderChecks[#reminderChecks + 1] = cb
			last = cb
		end
	end
	if not any then
		local none = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		none:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -6); none:SetText("No reminders defined for this class yet.")
		last = none
	end

	-- Section 2: macro mirrors
	local h2 = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	h2:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == h1 and 0 or -2, -20)
	h2:SetText("Auto-attack mirrors: tick a macro to show that auto state on its buttons")
	local colMelee = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	colMelee:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -8); colMelee:SetText("Melee")
	local colRanged = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	colRanged:SetPoint("LEFT", colMelee, "LEFT", 60, 0); colRanged:SetText("Ranged")

	local scroll = CreateFrame("ScrollFrame", nil, optionsFrame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", colMelee, "BOTTOMLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -30, 16)
	local list = CreateFrame("Frame", nil, scroll)
	list:SetSize(WIDTH, 10)
	scroll:SetScrollChild(list)
	local rows = {}

	local function Row(i)
		local row = rows[i]
		if row then return row end
		row = CreateFrame("Frame", nil, list)
		row:SetSize(WIDTH, ROW_H)
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
		row.melee = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
		row.melee:SetPoint("LEFT", row, "LEFT", 4, 0)
		if row.melee.Text then row.melee.Text:SetText("") end
		row.ranged = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
		row.ranged:SetPoint("LEFT", row, "LEFT", 64, 0)
		if row.ranged.Text then row.ranged.Text:SetText("") end
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", row, "LEFT", 124, 0)
		row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0); row.label:SetJustifyH("LEFT")
		row.melee:SetScript("OnClick", function(self) VSBH.SetMirror(row.macroName, "melee", self:GetChecked()) end)
		row.ranged:SetScript("OnClick", function(self) VSBH.SetMirror(row.macroName, "ranged", self:GetChecked()) end)
		rows[i] = row
		return row
	end

	local function UpdateMacros()
		local macros = ListMacros()
		for i, m in ipairs(macros) do
			local row = Row(i)
			row.macroName = m.name
			row.icon:SetTexture(m.icon)
			row.label:SetText(m.name .. (m.account and "" or "  |cff808080(character)|r"))
			local s = VSBH.MirrorSettings(m.name)
			row.melee:SetChecked(s and s.melee or false)
			row.ranged:SetChecked(s and s.ranged or false)
			row:Show()
		end
		for i = #macros + 1, #rows do rows[i]:Hide() end
		list:SetHeight(math.max(10, #macros * ROW_H))
	end

	function optionsFrame:Update()
		if not VSBH.db then return end
		for _, cb in ipairs(reminderChecks) do cb:Update() end
		UpdateMacros()
	end
	optionsFrame:SetScript("OnShow", optionsFrame.Update)
	optionsFrame:RegisterEvent("UPDATE_MACROS")
	optionsFrame:SetScript("OnEvent", function(self) if self:IsVisible() then self:Update() end end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsFrame, "Velocity Self Buff Highlights")
		Settings.RegisterAddOnCategory(optionsCategory)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(optionsFrame)
	end
end

function VSBH.OpenOptions()
	CreateOptions()
	if Settings and Settings.OpenToCategory and optionsCategory then
		Settings.OpenToCategory(optionsCategory:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(optionsFrame); InterfaceOptionsFrame_OpenToCategory(optionsFrame)
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self) self:UnregisterEvent("PLAYER_LOGIN"); CreateOptions() end)