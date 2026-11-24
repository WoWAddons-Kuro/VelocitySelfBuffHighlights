-- Velocity Self Buff Highlights: the reminder catalogue.
--
-- A reminder = "glow the buttons of these spells while NONE of them is on the player". One spell
-- (Thorns) or an exclusive family (seals) - same shape. `id` is the SV key: never rename once
-- released. Ranks ascending, Classic spell data; the self-buff aura carries the cast's ID.
--
-- Derived per reminder at SPELLS_CHANGED (VSBH.ResolveReminders):
--   auraSet   = { [id] = true } for every rank >= the highest rank the player knows, per spell
--               (a higher rank from another caster counts as "up"); empty if no spell is known
--   buttonSet = { [id] = true } for every rank of every spell (which buttons glow)
local ADDON, VSBH = ...

VSBH.Reminders = {
	{ id = "DRUID.thorns", class = "DRUID", label = "Thorns",
		spells = { { name = "Thorns", ranks = { 467, 782, 1075, 8914, 9756, 9910 } } } },
	{ id = "DRUID.motw", class = "DRUID", label = "Mark of the Wild",
		spells = { { name = "Mark of the Wild", ranks = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 } } } },
}

local reminderByRank = {} -- any rank id -> reminder
for _, r in ipairs(VSBH.Reminders) do
	r.auraSet, r.buttonSet = {}, {}
	for _, spell in ipairs(r.spells) do
		for _, id in ipairs(spell.ranks) do
			r.buttonSet[id] = true
			reminderByRank[id] = r
		end
	end
end

function VSBH.ReminderForSpell(spellID)
	return spellID and reminderByRank[spellID] or nil
end

local function Known(id)
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	return IsSpellKnown and IsSpellKnown(id) or false
end

-- Recomputes auraSet for every reminder. Returns true when any changed.
function VSBH.ResolveReminders()
	local changed = false
	for _, r in ipairs(VSBH.Reminders) do
		local set, known, sig = {}, false, {}
		for _, spell in ipairs(r.spells) do
			local best
			for i, id in ipairs(spell.ranks) do if Known(id) then best = i end end
			if best then
				known = true
				for i = best, #spell.ranks do set[spell.ranks[i]] = true; sig[#sig + 1] = spell.ranks[i] end
			end
		end
		table.sort(sig)
		local key = table.concat(sig, ",")
		if key ~= r.auraKey then
			r.auraKey, r.auraSet, r.known = key, set, known
			changed = true
		end
	end
	return changed
end