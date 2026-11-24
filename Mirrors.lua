-- Velocity Self Buff Highlights: auto-attack state mirrors.
--
-- The player's melee auto-attack (Attack, 6603) and ranged auto-shot (Auto Shot 75 / Shoot 5019)
-- state, drawn on every action button whose MACRO the player ticked in the options, the way
-- Blizzard draws it on the stock Attack button: the checked yellow glow steady, plus a full-rect
-- red flash toggling every ATTACK_BUTTON_FLASH_TIME (0.4 s). The native Attack / Auto Shot
-- buttons already do this themselves and are left alone.
--
-- Decided by IsCurrentSpell(spellID): the player's OWN action state, which the Midnight/Forever
-- restrictions leave readable in combat... except that on Forever it answers false for Attack
-- and Auto Shot even while swinging (found 2026-11-23). So the state is EVENT-driven, which
-- carries no payload to secretise: PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT are the melee
-- auto-attack toggling on / off (Blizzard's misnamed pair), START_/STOP_AUTOREPEAT_SPELL the
-- ranged one. IsCurrentSpell is consulted only to SEED the state on login / reload, where it may
-- know better than "off" (it is correct on Era).
local ADDON, VSBH = ...

local MELEE_SPELL = 6603
local RANGED_SPELLS = { 75, 5019 }
local FLASH_TIME = ATTACK_BUTTON_FLASH_TIME or 0.4
-- Blizzard's Mainline ActionButtonTemplate.xml: CheckedTexture atlas UI-HUD-ActionBar-IconFrame-Mouseover
-- (46x45, TOPLEFT), Flash atlas UI-HUD-ActionBar-IconFrame-Flash (atlas size, TOPLEFT), shown/hidden
-- every ATTACK_BUTTON_FLASH_TIME. Classic Era's template uses the old file textures.
local CHECKED_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local FLASH_ATLAS = "UI-HUD-ActionBar-IconFrame-Flash"
local CHECKED_FILE = "Interface\\Buttons\\CheckButtonHilight"
local FLASH_FILE = "Interface\\Buttons\\UI-QuickslotRed"

local mirrors = {} -- button -> { frame, glow, flash, melee = bool, ranged = bool }
local state = { melee = false, ranged = false }

local function IsCurrent(spellID)
	local ok, v = pcall(IsCurrentSpell, spellID)
	if not ok then VSBH.WarnOnce("iscurrent", "IsCurrentSpell error: " .. tostring(v)); return false end
	if issecretvalue and issecretvalue(v) then VSBH.WarnOnce("iscurrent-secret", "IsCurrentSpell is secret; mirrors will use events only"); return false end
	return v and true or false
end

local function SeedState()
	state.melee = IsCurrent(MELEE_SPELL)
	local ranged = false
	for _, id in ipairs(RANGED_SPELLS) do if IsCurrent(id) then ranged = true end end
	state.ranged = ranged
end

--------------------------------------------------------------------------------
-- The overlay: Blizzard's checked look + red flash, as our own regions over the button.
--------------------------------------------------------------------------------
local function BuildMirror(button)
	local frame = CreateFrame("Frame", nil, button)
	frame:SetAllPoints(button)
	frame:SetFrameLevel(button:GetFrameLevel() + 4)
	frame:Hide()
	local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(CHECKED_ATLAS) ~= nil
	local w, h = button:GetSize()
	local scale = (w and w > 0) and (w / 45) or 1 -- the atlases are drawn for the 45 px stock button
	-- the steady yellow: the stock button's CheckedTexture. Drawn ABOVE the flash, as on the stock
	-- button (Flash is an ARTWORK layer texture; CheckedTexture sits over every layer), so the
	-- yellow frame stays yellow while the red flashes beneath it.
	local glow = frame:CreateTexture(nil, "OVERLAY", nil, 3)
	if hasAtlas then
		glow:SetAtlas(CHECKED_ATLAS)
		glow:SetSize(46 * scale, 45 * scale)
		glow:SetPoint("TOPLEFT", frame, "TOPLEFT")
	else
		glow:SetTexture(CHECKED_FILE)
		glow:SetBlendMode("ADD")
		glow:SetAllPoints(frame)
	end
	-- the flash: Blizzard toggles the texture's visibility, no fade
	local flash = frame:CreateTexture(nil, "ARTWORK")
	if hasAtlas then
		flash:SetAtlas(FLASH_ATLAS, true)
		if scale ~= 1 then flash:SetSize(flash:GetWidth() * scale, flash:GetHeight() * scale) end
		flash:SetPoint("TOPLEFT", frame, "TOPLEFT")
	else
		flash:SetTexture(FLASH_FILE)
		flash:SetAllPoints(frame)
	end
	flash:Hide()
	local ag = flash:CreateAnimationGroup()
	ag:SetLooping("REPEAT")
	local a1 = ag:CreateAnimation("Alpha")
	a1:SetFromAlpha(1); a1:SetToAlpha(1); a1:SetDuration(FLASH_TIME); a1:SetOrder(1)
	local a2 = ag:CreateAnimation("Alpha")
	a2:SetFromAlpha(0); a2:SetToAlpha(0); a2:SetDuration(FLASH_TIME); a2:SetOrder(2)
	return { frame = frame, glow = glow, flash = flash, anim = ag }
end

local function Apply(m)
	local on = (m.melee and state.melee) or (m.ranged and state.ranged)
	if on and not m.frame:IsShown() then
		m.frame:Show(); m.flash:Show(); m.anim:Play()
	elseif not on and m.frame:IsShown() then
		m.anim:Stop(); m.flash:Hide(); m.frame:Hide()
	end
end

--------------------------------------------------------------------------------
-- Which buttons mirror what: re-walked when bars or settings change.
--------------------------------------------------------------------------------
function VSBH.RefreshMirrors()
	if not VSBH.db then return end
	local seen = {}
	VSBH.ForEachActionButton(function(button, _, macroName)
		local s = macroName and button:IsVisible() and VSBH.MirrorSettings(macroName) or nil
		local m = mirrors[button]
		if s and (s.melee or s.ranged) then
			if not m then m = BuildMirror(button); mirrors[button] = m end
			m.melee, m.ranged = s.melee or false, s.ranged or false
			seen[button] = true
		elseif m then
			m.melee, m.ranged = false, false
		end
		if m then Apply(m) end
	end)
end

-- Auto state changed: re-read and re-apply, no bar walk.
local function ApplyAll()
	for _, m in pairs(mirrors) do Apply(m) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTER_COMBAT")  -- melee auto-attack ON (misnamed Blizzard event)
f:RegisterEvent("PLAYER_LEAVE_COMBAT")  -- melee auto-attack OFF
f:RegisterEvent("START_AUTOREPEAT_SPELL")
f:RegisterEvent("STOP_AUTOREPEAT_SPELL")
f:RegisterEvent("PLAYER_DEAD")           -- everything stops
f:SetScript("OnEvent", function(_, event)
	VSBH.lastMirrorEvent = event
	if event == "PLAYER_LOGIN" then SeedState()
	elseif event == "PLAYER_ENTER_COMBAT" then state.melee = true
	elseif event == "PLAYER_LEAVE_COMBAT" then state.melee = false
	elseif event == "START_AUTOREPEAT_SPELL" then state.ranged = true
	elseif event == "STOP_AUTOREPEAT_SPELL" then state.ranged = false
	elseif event == "PLAYER_DEAD" then state.melee, state.ranged = false, false
	end
	local ok, err = pcall(ApplyAll)
	if not ok then VSBH.WarnOnce("mirror", tostring(err)) end
end)

function VSBH.MirrorStatus()
	local n = 0
	for _, m in pairs(mirrors) do if m.melee or m.ranged then n = n + 1 end end
	local raw = {}
	for _, id in ipairs({ MELEE_SPELL, RANGED_SPELLS[1], RANGED_SPELLS[2] }) do
		local ok, v = pcall(IsCurrentSpell, id); raw[#raw + 1] = id .. "=" .. tostring(ok and v)
	end
	return string.format("melee auto %s, ranged auto %s, %d mirrored button(s); raw %s; last event %s", state.melee and "ON" or "off", state.ranged and "ON" or "off", n, table.concat(raw, " "), tostring(VSBH.lastMirrorEvent))
end