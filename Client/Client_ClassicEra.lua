-- Velocity Self Buff Highlights: Classic Era client (11509). No secret values, no AuraContainer:
-- UnitBuff is readable at all times, so Lua decides "missing" on UNIT_AURA and shows/hides a
-- plain overlay (the proc-loop glow) parented to the button for position only.
local ADDON, VSBH = ...

local function PlayerHas(auraSet)
	for i = 1, 40 do
		local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
		if not name then break end
		if auraSet[spellId] then return true end
	end
	return false
end

local function Apply(overlay)
	local show = overlay.active and not PlayerHas(overlay.auraSet)
	if show and not overlay.host:IsShown() then overlay.host:Show(); overlay.anim:Play()
	elseif not show and overlay.host:IsShown() then overlay.anim:Stop(); overlay.host:Hide() end
end

local function BuildMissingOverlay(button, auraSet)
	local w, h = button:GetSize()
	local m = math.floor(w * 0.2 + 0.5)
	local host = CreateFrame("Frame", nil, button)
	host:SetAllPoints(button)
	host:SetFrameLevel(button:GetFrameLevel() + 5)
	host:Hide()
	local glow, anim = VSBH.CreateProcGlow(host, host, m)
	return { host = host, glow = glow, anim = anim, auraSet = auraSet, active = false }
end

VSBH.ClientFlavours.classic_era = {
	PlayerKey = function() return UnitGUID("player") end,
	PlayerDisplayName = function() return (UnitName("player")) end,
	CanConfigureOverlays = function() return true end,
	BuildMissingOverlay = BuildMissingOverlay,
	SetMissingOverlayAuras = function(overlay, auraSet) overlay.auraSet = auraSet; Apply(overlay); return true end,
	SetMissingOverlayActive = function(overlay, active) overlay.active = active and true or false; Apply(overlay) end,
	RefreshMissingOverlays = function(overlays) for _, o in ipairs(overlays) do Apply(o) end end,
	WantsAuraEvents = function() return true end,
}