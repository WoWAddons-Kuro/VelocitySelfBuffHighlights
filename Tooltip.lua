-- Velocity Self Buff Highlights: tooltip note on a glowing button that explains WHY it glows
-- when the reason is not obvious - the spell on the button is a lower rank than one you know,
-- so the buff you have (rank 1) does not count as "up" (rank 2 known). Without this line the
-- player casts rank 1, sees the glow stay, and thinks the addon is broken. Teal, under the body.
-- The rank facts come from LowRank.lua (spellbook by name, any class, any spell).
local ADDON, VSBH = ...

local NOTE_COLOR = { 0.25, 0.85, 0.85 }

-- The note for an action button, or nil.
function VSBH.TooltipNoteFor(button)
	local note = VSBH.LowRankNoteFor and VSBH.LowRankNoteFor(button)
	if not note then return nil end
	local entry = VSBH.OverlayEntry and VSBH.OverlayEntry(button)
	if entry and entry.active then note = note .. " The glow stays until the higher rank is on you." end
	return note
end

local function AddNote(tooltip, button)
	if not button or tooltip ~= GameTooltip then return end
	local note = VSBH.TooltipNoteFor(button)
	if not note then return end
	tooltip:AddLine(" ")
	tooltip:AddLine(note, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true)
	tooltip:Show()
end

-- The action-bar tooltip is set with GameTooltip:SetAction(slot) from the button's OnEnter;
-- GameTooltip:GetOwner() is the button at that point. Works on Era and Forever.
if GameTooltip and hooksecurefunc then
	hooksecurefunc(GameTooltip, "SetAction", function(tooltip)
		local ok, err = pcall(function()
			local owner = tooltip:GetOwner()
			if owner and owner.action then AddNote(tooltip, owner) end
		end)
		if not ok then VSBH.WarnOnce("tooltip", tostring(err)) end
	end)
end