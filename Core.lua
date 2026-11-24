-- Velocity Self Buff Highlights: core. SV, events, and the refresh that pairs action buttons
-- with reminders. Flavour-agnostic: how an overlay decides "missing" lives in Client\.
-- Spec: SPECS\SPEC-VelocitySelfBuffHighlights.md
local ADDON, VSBH = ...
local Client = VSBH.Client

VSBH.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"
VSBH.db = nil

local overlays = {} -- button -> { overlay = <client overlay>, reminder = r, auraKey = r.auraKey, active = bool }
local activeList = {}

local function Log(fmt, ...) print("|cff60c0ffVSBH:|r " .. string.format(fmt, ...)) end
VSBH.Log = Log

--------------------------------------------------------------------------------
-- Settings.
--------------------------------------------------------------------------------
local function InitDB()
	VelocitySelfBuffHighlightsDB = VelocitySelfBuffHighlightsDB or {}
	local db = VelocitySelfBuffHighlightsDB
	db.reminders = db.reminders or {} -- [reminder id] = false to disable (absent = on)
	db.mirrors = db.mirrors or {}     -- [class] = { [macro name] = { melee = bool, ranged = bool } }
	VSBH.db = db
end

function VSBH.IsReminderEnabled(r)
	return VSBH.db and VSBH.db.reminders[r.id] ~= false
end

function VSBH.SetReminderEnabled(r, enabled)
	if not VSBH.db then return end
	VSBH.db.reminders[r.id] = enabled and nil or false
	VSBH.Refresh()
end

VSBH.playerClass = select(2, UnitClass("player"))

--------------------------------------------------------------------------------
-- Refresh: Lua decides only WHICH buttons carry WHICH reminder. The client decides
-- (or lets the engine decide) whether the buff is actually missing.
--------------------------------------------------------------------------------
local function SetActive(entry, active)
	if entry.active == active then return end
	entry.active = active
	Client.SetMissingOverlayActive(entry.overlay, active)
end

local deferred = false

function VSBH.Refresh()
	if not VSBH.db then return end
	VSBH.ResolveReminders()
	local canConfigure = Client.CanConfigureOverlays()
	deferred = false
	VSBH.ForEachActionButton(function(button, spellID)
		local r = button:IsVisible() and VSBH.ReminderForSpell(spellID) or nil
		if r and (not r.known or r.class ~= VSBH.playerClass or not VSBH.IsReminderEnabled(r)) then r = nil end
		local entry = overlays[button]
		if r then
			if not entry then
				if not canConfigure then deferred = true; return end
				local overlay = Client.BuildMissingOverlay(button, r.auraSet)
				if not overlay then return end
				entry = { overlay = overlay, reminder = r, auraKey = r.auraKey, active = false }
				overlays[button] = entry
			elseif entry.reminder ~= r or entry.auraKey ~= r.auraKey then
				if not canConfigure then deferred = true; return end
				if not Client.SetMissingOverlayAuras(entry.overlay, r.auraSet) then return end
				entry.reminder, entry.auraKey = r, r.auraKey
			end
			SetActive(entry, true)
		elseif entry then
			SetActive(entry, false)
		end
	end)
	wipe(activeList)
	for _, entry in pairs(overlays) do if entry.active then activeList[#activeList + 1] = entry.overlay end end
	Client.RefreshMissingOverlays(activeList)
	if VSBH.RefreshMirrors then VSBH.RefreshMirrors() end
end

--------------------------------------------------------------------------------
-- Events.
--------------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
f:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
f:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
f:RegisterEvent("SPELLS_CHANGED")
if Client.WantsAuraEvents() then f:RegisterUnitEvent("UNIT_AURA", "player") end
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then InitDB() end
		return
	end
	if event == "UNIT_AURA" then
		Client.RefreshMissingOverlays(activeList)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" and not deferred then return end
	local ok, err = pcall(VSBH.Refresh)
	if not ok then VSBH.WarnOnce("refresh", tostring(err)) end
end)

--------------------------------------------------------------------------------
-- /vsbh
--------------------------------------------------------------------------------
function VSBH.PrintStatus()
	local n = 0
	for _, entry in pairs(overlays) do if entry.active then n = n + 1 end end
	Log("v%s, %s client, %s, can configure %s, %d button(s) carrying a reminder%s",
		VSBH.VERSION, Client.flavour, Client.PlayerDisplayName(), tostring(Client.CanConfigureOverlays()), n, deferred and ", work deferred to after combat" or "")
	if VSBH.MirrorStatus then Log("  mirrors: %s", VSBH.MirrorStatus()) end
	for _, r in ipairs(VSBH.Reminders) do
		if r.class == VSBH.playerClass then
			Log("  %s: %s, %s", r.label, VSBH.IsReminderEnabled(r) and "on" or "off", r.known and ("tests " .. (r.auraKey or "")) or "spell not known")
		end
	end
end

SLASH_VELOCITYSELFBUFFHIGHLIGHTS1 = "/vsbh"
SlashCmdList.VELOCITYSELFBUFFHIGHLIGHTS = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "status" or not VSBH.OpenOptions then
		VSBH.PrintStatus()
	elseif msg == "macros" and VSBH.DebugMacros then
		VSBH.DebugMacros()
	else
		VSBH.OpenOptions()
	end
end