-- Velocity Self Buff Highlights: countdown for the last seconds of a watched buff.
--
-- Setting (default off): while OUT of combat, when a reminder's buff has less than
-- COUNTDOWN_SECONDS left, the remaining whole seconds are written over every button carrying that
-- reminder. In combat the remaining time is secret on Forever (and the player is busy), so the
-- countdown is hidden on PLAYER_REGEN_DISABLED and the ticker stops. The text is ours, over the
-- button; the button itself is never touched.
--
-- Reads: the player's buff list (C_UnitAuras.GetAuraDataByIndex / UnitBuff), expirationTime per
-- aura; every value is checked with issecretvalue before any arithmetic.
local ADDON, VSBH = ...

local COUNTDOWN_SECONDS = 10
local TICK = 0.25

local texts = {}     -- button -> FontString
local ticker         -- C_Timer ticker while active

--------------------------------------------------------------------------------
-- Remaining seconds of the soonest-expiring aura in auraSet on the player, or nil.
--------------------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) end

local function RemainingFor(auraSet)
	local best
	local now = GetTime()
	local function consider(spellId, expirationTime)
		if Secret(spellId) or Secret(expirationTime) then return end
		if not auraSet[spellId] then return end
		if type(expirationTime) ~= "number" or expirationTime <= 0 then return end -- permanent
		local left = expirationTime - now
		if not best or left < best then best = left end
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 80 do
			local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not a then break end
			consider(a.spellId, a.expirationTime)
		end
	elseif UnitBuff then
		for i = 1, 40 do
			local name, _, _, _, _, expirationTime, _, _, _, spellId = UnitBuff("player", i)
			if not name then break end
			consider(spellId, expirationTime)
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- The text.
--------------------------------------------------------------------------------
local function TextFor(button)
	local fs = texts[button]
	if fs then return fs end
	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints(button)
	holder:SetFrameLevel(button:GetFrameLevel() + 7)
	fs = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
	fs:SetPoint("CENTER", button, "CENTER", 0, 0)
	fs:SetShadowOffset(1, -1)
	fs:Hide()
	texts[button] = fs
	return fs
end

local function HideAll()
	for _, fs in pairs(texts) do fs:Hide() end
end

local function StopTicker()
	if ticker then ticker:Cancel(); ticker = nil end
	HideAll()
end

function VSBH.IsCountdownEnabled()
	return VSBH.db and VSBH.db.countdown == true
end

function VSBH.SetCountdownEnabled(enabled)
	if not VSBH.db then return end
	VSBH.db.countdown = enabled and true or false
	VSBH.RefreshCountdown()
end

-- One pass: for every active reminder overlay, show the remaining seconds if under the threshold.
-- Returns true when anything is within range (so the ticker should keep running).
local function Tick()
	if InCombatLockdown() or UnitAffectingCombat("player") then StopTicker(); return false end
	local any = false
	local perReminder = {} -- reminder -> remaining | false (computed once per reminder per tick)
	VSBH.ForEachActionButton(function(button)
		local entry = VSBH.OverlayEntry(button)
		local fs = texts[button]
		if not entry or not entry.active or VSBH.IsFoodReminder(entry.reminder) then
			if fs then fs:Hide() end
			return
		end
		local r = entry.reminder
		local left = perReminder[r]
		if left == nil then left = RemainingFor(r.auraSet) or false; perReminder[r] = left end
		if left and left > 0 and left <= COUNTDOWN_SECONDS then
			any = true
			fs = fs or TextFor(button)
			local s = math.ceil(left)
			fs:SetText(s)
			if left <= 3 then fs:SetTextColor(1, 0.2, 0.2) else fs:SetTextColor(1, 0.85, 0.2) end
			fs:Show()
		elseif fs then
			fs:Hide()
		end
	end)
	if not any then StopTicker() end
	return any
end

-- Called by Core.Refresh and on UNIT_AURA: decides whether the ticker should be running.
function VSBH.RefreshCountdown()
	if not VSBH.IsCountdownEnabled() then StopTicker(); return end
	if InCombatLockdown() or UnitAffectingCombat("player") then StopTicker(); return end
	if Tick() and not ticker then
		ticker = C_Timer.NewTicker(TICK, function() local ok, err = pcall(Tick); if not ok then StopTicker(); VSBH.WarnOnce("countdown", tostring(err)) end end)
	end
end

-- A buff with more than 10 s left needs no ticker until it gets close: re-check when it would
-- enter the window. Cheap: one timer per refresh, keyed by the soonest reminder expiry.
local armed
local function ArmForSoonest()
	if armed then armed:Cancel(); armed = nil end
	if not VSBH.IsCountdownEnabled() or InCombatLockdown() then return end
	local soonest
	for _, r in ipairs(VSBH.Reminders) do
		if not VSBH.IsFoodReminder(r) and r.known and VSBH.IsReminderEnabled(r) then
			local left = RemainingFor(r.auraSet)
			if left and left > COUNTDOWN_SECONDS and (not soonest or left < soonest) then soonest = left end
		end
	end
	if soonest then
		armed = C_Timer.NewTimer(soonest - COUNTDOWN_SECONDS + 0.05, function() armed = nil; VSBH.RefreshCountdown() end)
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then StopTicker(); if armed then armed:Cancel(); armed = nil end; return end
	local ok, err = pcall(function() VSBH.RefreshCountdown(); ArmForSoonest() end)
	if not ok then VSBH.WarnOnce("countdown", tostring(err)) end
end)

-- Called from Core.Refresh as a stage, so bar/reminder/setting changes re-evaluate.
function VSBH.RefreshCountdownStage()
	VSBH.RefreshCountdown(); ArmForSoonest()
end