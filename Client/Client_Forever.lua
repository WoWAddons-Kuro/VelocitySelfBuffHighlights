-- Velocity Self Buff Highlights: WoW Forever client (16001, Mainline engine, secret auras).
--
-- Aura data is secret in combat, so Lua never decides "missing". The engine does, by geometry
-- (EverAuras' recipe, ForeverEngineAura.lua BuildGroup; proven here 2026-11-23):
--   host (ours, over the button)
--     container = CustomAuraContainerTemplate, unit player, ONE aura group filtered to auraSet,
--                 maxFrameCount 1, elementWidth W+1+2m. The engine sets its width SECRETLY:
--                 1 px while none of auraSet is on the player, W+1+2m px while one is.
--     clip      = SetClipsChildren, TOPLEFT on the container's right edge, BOTTOMRIGHT on the host:
--                 full width while absent, zero width while present.
--       glow    = proc-loop texture inside the clip, anchored to the host.
-- Container reconfiguration is only allowed while auras are readable (CanConfigureOverlays).
-- Frames anchored to a group-owning container must inherit DisableUntrustedLayoutScriptsTemplate.
-- Nothing of ours is ever re-parented or re-anchored after creation.
local ADDON, VSBH = ...
local GROUP_KEY = "vsbh"
local engineAvailable -- nil = not probed

local function EngineAvailable()
	if engineAvailable ~= nil then return engineAvailable end
	if C_AddOns and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	engineAvailable = (ok and c and type(c.AddAuraGroup) == "function" and type(c.SetUnit) == "function") or false
	if ok and c then c:Hide() end
	if not engineAvailable then VSBH.WarnOnce("engine", "CustomAuraContainerTemplate not available; buff reminders are off") end
	return engineAvailable
end

local function CanConfigureOverlays()
	if InCombatLockdown() then return false end
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return false end
	return true
end

local function BuildMissingOverlay(button, auraSet)
	if not EngineAvailable() then return nil end
	local w, h = button:GetSize()
	w, h = math.floor(w + 0.5), math.floor(h + 0.5)
	local m = math.floor(w * 0.2 + 0.5) -- the glow reaches m px past the button on every side
	local host = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
	host:SetAllPoints(button)
	host:SetFrameLevel(button:GetFrameLevel() + 5)
	host:Hide()
	local c = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
	c:SetPoint("TOPLEFT", host, "TOPLEFT") -- TOPLEFT only: the engine sets the size (secretly)
	c:SetFrameLevel(host:GetFrameLevel())
	c:SetUnit("player")
	local ok, err = pcall(c.AddAuraGroup, c, GROUP_KEY, "HELPFUL", {
		candidateFilters = { includeSpellIDs = auraSet }, -- a MAP id -> true
		maxFrameCount = 1,
		layout = { elementWidth = w + 1 + 2 * m, elementHeight = h },
		initializeFrame = function(b)
			b:SetSize(w + 1 + 2 * m, h)
			pcall(b.SetMouseClickEnabled, b, false)
			pcall(b.EnableMouseMotion, b, false)
			b:SetAlpha(0) -- draws nothing; only its width matters
		end,
	})
	if not ok then
		VSBH.WarnOnce("group", "AddAuraGroup failed: " .. tostring(err))
		host:Hide()
		return nil
	end
	local clip = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(host:GetFrameLevel() + 1)
	clip:SetPoint("TOPLEFT", c, "TOPRIGHT", -1 - m, m)
	clip:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", m, -m)
	local glow, anim = VSBH.CreateProcGlow(clip, host, m)
	return { host = host, container = c, clip = clip, glow = glow, anim = anim }
end

local function SetMissingOverlayAuras(overlay, auraSet)
	return (pcall(overlay.container.SetAuraGroupCandidateFilters, overlay.container, GROUP_KEY, { includeSpellIDs = auraSet }))
end

local function SetMissingOverlayActive(overlay, active)
	if active then
		if not overlay.host:IsShown() then overlay.host:Show(); overlay.anim:Play() end
	elseif overlay.host:IsShown() then
		overlay.anim:Stop(); overlay.host:Hide()
	end
end

VSBH.ClientFlavours.forever = {
	PlayerKey = function() return UnitGUID("player") end,
	PlayerDisplayName = function()
		local name, surname = UnitNameUnmodified("player")
		if surname and surname ~= "" then return name .. " " .. surname end
		return name
	end,
	CanConfigureOverlays = CanConfigureOverlays,
	BuildMissingOverlay = BuildMissingOverlay,
	SetMissingOverlayAuras = SetMissingOverlayAuras,
	SetMissingOverlayActive = SetMissingOverlayActive,
	RefreshMissingOverlays = function() end, -- the engine decides; nothing to read
	WantsAuraEvents = function() return false end,
}