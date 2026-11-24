-- Velocity Self Buff Highlights: Blizzard action bar walk. What each visible button holds
-- (spell ID, or the macro's name and resolved spell). Plain data, readable in combat.
local ADDON, VSBH = ...

local BAR_PREFIXES = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
	"MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

-- Calls fn(button, spellID | nil, macroName | nil, itemID | nil) for every existing Blizzard action button.
function VSBH.ForEachActionButton(fn)
	for _, prefix in ipairs(BAR_PREFIXES) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then
				local spellID, macroName, itemID
				local slot = button.action
				if slot then
					local kind, id, _, sid = GetActionInfo(slot)
					if kind == "spell" then
						spellID = id
					elseif kind == "item" then
						itemID = id
					elseif kind == "macro" then
						spellID = sid or GetMacroSpell(id)
						-- Forever hands back a global macro ID here, not a 1-based slot, so
						-- GetMacroInfo(id) is nil. GetActionText(slot) is the macro's name on any client.
						macroName = GetActionText(slot) or GetMacroInfo(id)
						if macroName == "" then macroName = nil end
					end
				end
				fn(button, spellID, macroName)
			end
		end
	end
end