-- Velocity Self Buff Highlights: client interface declaration.
--
-- The one thing that differs per flavour is HOW a "buff missing" overlay on an action button
-- decides to be visible. Forever: aura data is secret in combat, so the engine decides via a
-- CustomAuraContainer whose secret width drives a clip (Client_Forever.lua). Era: UnitBuff is
-- readable, so Lua decides on UNIT_AURA (Client_ClassicEra.lua). Nothing outside Client\
-- reads aura data. Client_Select.lua binds the flavour onto VSBH.Client.
local ADDON, VSBH = ...

VSBH.Client = {}
VSBH.ClientFlavours = {}

VSBH.Client.INTERFACE = {
	-- PlayerKey() -> UnitGUID("player"); the only per-character SV key.
	"PlayerKey",
	-- PlayerDisplayName() -> Era "Kuro"; Forever "Kuro Oakheart".
	"PlayerDisplayName",
	-- CanConfigureOverlays() -> true when overlays may be built / repointed now (Forever: out of
	-- combat and auras not secret; Era: always).
	"CanConfigureOverlays",
	-- BuildMissingOverlay(button, auraSet) -> overlay | nil. Creates the "glow while none of
	-- auraSet is on the player" overlay for this action button. auraSet is a MAP spellID -> true.
	-- Only called when CanConfigureOverlays() is true. The overlay is parented to the button for
	-- position only; the button is never touched.
	"BuildMissingOverlay",
	-- SetMissingOverlayAuras(overlay, auraSet) -> ok. Repoints an existing overlay at a new set
	-- (rank learned, different reminder on this button). Configure-time only.
	"SetMissingOverlayAuras",
	-- SetMissingOverlayActive(overlay, active). active == false hides it whatever the aura state
	-- (button no longer holds the spell). Safe at any time, combat included.
	"SetMissingOverlayActive",
	-- RefreshMissingOverlays(overlays) -> called on UNIT_AURA (player). Era re-evaluates
	-- UnitBuff; Forever is a no-op (the engine decides). overlays: list of active overlays.
	"RefreshMissingOverlays",
	-- WantsAuraEvents() -> true if RefreshMissingOverlays needs UNIT_AURA registered.
	"WantsAuraEvents",
}

-- Shared helper: the proc-loop glow texture every flavour draws, anchored m px past `anchor`.
-- parent must be created by the caller (Forever needs it inside the clip). Returns texture, animGroup.
function VSBH.CreateProcGlow(parent, anchor, m)
	local glow = parent:CreateTexture(nil, "OVERLAY")
	glow:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
	glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -m, m)
	glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", m, -m)
	local ag = glow:CreateAnimationGroup()
	ag:SetLooping("REPEAT")
	local flip = ag:CreateAnimation("FlipBook")
	flip:SetFlipBookRows(6)
	flip:SetFlipBookColumns(5)
	flip:SetFlipBookFrames(30)
	flip:SetFlipBookFrameWidth(0)
	flip:SetFlipBookFrameHeight(0)
	flip:SetDuration(1)
	return glow, ag
end