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
	db.wellFedIDs = db.wellFedIDs or {} -- [class] = { [spellID] = true } learned Well Fed auras (Reminders.lua)
	if db.suppressResting == nil then db.suppressResting = true end
	VSBH.db = db
end

function VSBH.IsReminderEnabled(r)
	if not VSBH.db then return false end
	local v = VSBH.db.reminders[r.id]
	if v == nil then return not r.defaultOff end
	return v == true
end

function VSBH.SetReminderEnabled(r, enabled)
	if not VSBH.db then return end
	VSBH.db.reminders[r.id] = enabled and true or false
	VSBH.Refresh()
end

--------------------------------------------------------------------------------
-- Suppression: "suppress buff highlights while resting and out of combat" (default on).
-- Never touches the auto-attack mirrors. Once the player has been in combat during a rest
-- period (duelling in town), suppression stays off until they LEAVE resting.
--------------------------------------------------------------------------------
local foughtWhileResting = false

function VSBH.SuppressionActive()
	if not VSBH.db or not VSBH.db.suppressResting then return false end
	if InCombatLockdown() or UnitAffectingCombat("player") then return false end
	if not IsResting() then return false end
	return not foughtWhileResting
end

function VSBH.SetSuppressResting(enabled)
	if not VSBH.db then return end
	VSBH.db.suppressResting = enabled and true or false
	VSBH.Refresh()
end

local function OnRestOrCombatChange(event)
	if event == "PLAYER_REGEN_DISABLED" then
		if IsResting() then foughtWhileResting = true end
	elseif event == "PLAYER_UPDATE_RESTING" then
		if not IsResting() then foughtWhileResting = false end
	end
end

VSBH.playerClass = select(2, UnitClass("player"))
for _, r in ipairs(VSBH.Reminders) do if VSBH.IsFoodReminder(r) then VSBH.FoodReminder = r end end
function VSBH.OverlayEntry(button) return overlays[button] end

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
	-- each stage guarded: a fault in one (new API shape on a new build) must not take the rest down
	local function stage(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then VSBH.WarnOnce("stage:" .. name, name .. ": " .. tostring(err)) end
		return ok
	end
	stage("wellfed", VSBH.LearnWellFed)
	stage("resolve", VSBH.ResolveReminders)
	local canConfigure = Client.CanConfigureOverlays()
	local suppressed = VSBH.SuppressionActive()
	local inCombat = InCombatLockdown()
	deferred = false
	VSBH.ForEachActionButton(function(button, spellID, _, itemID)
		local r
		if button:IsVisible() then
			r = VSBH.ReminderForSpell(spellID)
			if not r and itemID and VSBH.FoodItemMatches(itemID) then r = VSBH.FoodReminder end
		end
		if r and (not r.known or (r.class and r.class ~= VSBH.playerClass) or not VSBH.IsReminderEnabled(r)) then r = nil end
		if r and suppressed then r = nil end
		if r and r.outOfCombatOnly and inCombat then r = nil end
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
	stage("overlays", Client.RefreshMissingOverlays, activeList)
	if VSBH.RefreshMirrors then stage("mirrors", VSBH.RefreshMirrors) end
	if VSBH.RefreshLowRank then stage("lowrank", VSBH.RefreshLowRank) end
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
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_UPDATE_RESTING")
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
	OnRestOrCombatChange(event)
	local ok, err = pcall(VSBH.Refresh)
	if not ok then VSBH.WarnOnce("refresh", tostring(err)) end
end)
-- Food: Well Fed is learned from the aura list out of combat; the engine path registers no
-- UNIT_AURA, so poll cheaply after eating ends (the buff lands ~10 s into a meal).
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

--------------------------------------------------------------------------------
-- /vsbh
--------------------------------------------------------------------------------
function VSBH.PrintStatus()
	local n = 0
	for _, entry in pairs(overlays) do if entry.active then n = n + 1 end end
	Log("v%s, %s client, %s, can configure %s, %d button(s) carrying a reminder%s",
		VSBH.VERSION, Client.flavour, Client.PlayerDisplayName(), tostring(Client.CanConfigureOverlays()), n, deferred and ", work deferred to after combat" or "")
	if VSBH.MirrorStatus then Log("  mirrors: %s", VSBH.MirrorStatus()) end
	Log("  suppression: %s (setting %s, resting %s, fought while resting %s)", tostring(VSBH.SuppressionActive()), tostring(VSBH.db and VSBH.db.suppressResting), tostring(IsResting()), tostring(foughtWhileResting))
	local ids = {}
	for id in pairs(VSBH.WellFedIDs()) do ids[#ids + 1] = id end
	Log("  Well Fed name '%s', learned IDs: %s", VSBH.WellFedName(), #ids > 0 and table.concat(ids, ",") or "none")
	for button, entry in pairs(overlays) do
		Log("  overlay %s: %s, active %s, auraKey %s", button:GetName(), entry.reminder.label, tostring(entry.active), tostring(entry.auraKey))
	end
	VSBH.ForEachActionButton(function(button, spellID, macroName, itemID)
		if itemID then
			local sn, sid = nil, nil
			if C_Item and C_Item.GetItemSpell then sn, sid = C_Item.GetItemSpell(itemID) end
			Log("  item %s: id %d, use spell %s (%s), food %s", button:GetName(), itemID, tostring(sn), tostring(sid), tostring(VSBH.FoodItemMatches(itemID)))
		end
	end)
	for _, r in ipairs(VSBH.Reminders) do
		if r.class == nil or r.class == VSBH.playerClass then
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
	elseif msg == "buffs" and VSBH.DebugBuffs then
		VSBH.DebugBuffs()
	else
		VSBH.OpenOptions()
	end
end