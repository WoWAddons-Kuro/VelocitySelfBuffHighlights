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
	-- Well Fed: one aura name, one spell ID per food tier (dozens; Forever adds its own). No table:
	-- the IDs are LEARNED - whenever the buff is seen on the player out of combat, its spell ID is
	-- remembered in SV (db.wellFedIDs) and becomes the tested set. Buttons: any item whose use
	-- spell's description mentions the Well Fed buff (see FoodItemMatches). Default off.
	{ id = "ALL.wellfed", class = nil, label = "Highlight buff food when not Well Fed", kind = "food",
		defaultOff = true, spells = {}, outOfCombatOnly = true },
}
VSBH.WELL_FED_REFERENCE_SPELL = 19705 -- retail "Well Fed" spell; used only to fetch the localised name

local function IsFood(r) return r.kind == "food" end
VSBH.IsFoodReminder = IsFood

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

--------------------------------------------------------------------------------
-- Well Fed: learned aura IDs and food-item detection.
--------------------------------------------------------------------------------
local wellFedName
function VSBH.WellFedName()
	if wellFedName then return wellFedName end
	local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(VSBH.WELL_FED_REFERENCE_SPELL)
	if not n and GetSpellInfo then n = GetSpellInfo(VSBH.WELL_FED_REFERENCE_SPELL) end
	if n and n ~= "" and not (issecretvalue and issecretvalue(n)) then wellFedName = n end
	return wellFedName or "Well Fed"
end

-- Out of combat only (aura names readable). Adds any Well Fed spell ID on the player to SV.
-- Returns true when a new ID was learned.
local function EachPlayerBuff(fn)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 80 do
			local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not aura then break end
			fn(aura.name, aura.spellId)
		end
	elseif UnitBuff then
		for i = 1, 40 do
			local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
			if not name then break end
			fn(name, spellId)
		end
	end
end

-- Learned IDs are per CLASS: only food this class has actually eaten counts, which keeps other
-- classes' stat food off the glow list.
function VSBH.WellFedIDs()
	if not VSBH.db then return {} end
	local t = VSBH.db.wellFedIDs[VSBH.playerClass]
	if not t then t = {}; VSBH.db.wellFedIDs[VSBH.playerClass] = t end
	return t
end

function VSBH.LearnWellFed()
	if not VSBH.db or InCombatLockdown() then return false end
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return false end
	local want, learned, sawSecret = VSBH.WellFedName(), false, false
	local ids = VSBH.WellFedIDs()
	EachPlayerBuff(function(name, spellId)
		if issecretvalue and (issecretvalue(name) or issecretvalue(spellId)) then sawSecret = true; return end
		if name == want and type(spellId) == "number" and not ids[spellId] then
			ids[spellId] = true
			learned = true
			VSBH.Log("learned a Well Fed buff (spell %d) for this class; its food now glows when you are not Well Fed", spellId)
		end
	end)
	if sawSecret then VSBH.WarnOnce("wellfed-secret", "aura names are secret right now; Well Fed cannot be learned here") end
	return learned
end

function VSBH.DebugBuffs()
	VSBH.Log("player buffs as we see them (looking for '%s'):", VSBH.WellFedName())
	local n = 0
	EachPlayerBuff(function(name, spellId)
		n = n + 1
		local secret = issecretvalue and (issecretvalue(name) or issecretvalue(spellId))
		VSBH.Log("  %s (%s)%s", secret and "?" or tostring(name), secret and "?" or tostring(spellId), secret and " SECRET" or "")
	end)
	if n == 0 then VSBH.Log("  (nothing - enumeration returned no auras)") end
end

-- itemID -> does using it lead to Well Fed? Cached; the description is only readable once the
-- spell data is loaded, so nil (unknown yet) is distinct from false.
local foodCache = {}
function VSBH.FoodItemMatches(itemID)
	if not itemID then return false end
	local cached = foodCache[itemID]
	if cached ~= nil then return cached end
	local spellName, spellID = nil, nil
	if C_Item and C_Item.GetItemSpell then spellName, spellID = C_Item.GetItemSpell(itemID)
	elseif GetItemSpell then spellName, spellID = GetItemSpell(itemID) end
	if not spellID then return false end -- not usable, or item data not loaded (retried next refresh)
	local desc = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
	if not desc or desc == "" or (issecretvalue and issecretvalue(desc)) then return false end
	local hit = desc:lower():find(VSBH.WellFedName():lower(), 1, true) ~= nil
	foodCache[itemID] = hit
	return hit
end

local function Known(id)
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	return IsSpellKnown and IsSpellKnown(id) or false
end

-- The typed rank tables are Classic Era data; Forever can renumber. So the KNOWN ranks come from
-- the spellbook by NAME: every spellbook entry called `spell.name` is a rank the player knows,
-- whatever its ID. Returns { id, ... } (may be empty) - these are the IDs that match the aura the
-- player actually casts. Falls back to the typed table when the spellbook API is absent.
local function KnownIDsByName(spell)
	local ids = {}
	local spellName = spell.name
	-- shape as in VelocityMacroSync\Client\Client.lua: modern C_SpellBook (Forever), classic tabs (Era)
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemName then
		local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if info and info.itemIndexOffset and info.numSpellBookItems then
				for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local name = C_SpellBook.GetSpellBookItemName(i, bank)
					if name == spellName then
						local item = C_SpellBook.GetSpellBookItemInfo and C_SpellBook.GetSpellBookItemInfo(i, bank)
						-- only real spells: itemType Spell, numeric spellID (flyouts/pet actions carry other shapes)
						local isSpell = item and (not Enum.SpellBookItemType or item.itemType == Enum.SpellBookItemType.Spell)
						local id = isSpell and item.spellID or nil
						if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then ids[#ids + 1] = id end
					end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
		for tab = 1, GetNumSpellTabs() or 0 do
			local _, _, offset, n = GetSpellTabInfo(tab)
			for i = (offset or 0) + 1, (offset or 0) + (n or 0) do
				local name = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
				if name == spellName and GetSpellBookItemInfo then
					local _, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
					if type(id) == "number" then ids[#ids + 1] = id end
				end
			end
		end
	end
	return ids
end

-- Recomputes auraSet for every reminder. Returns true when any changed.
function VSBH.ResolveReminders()
	local changed = false
	for _, r in ipairs(VSBH.Reminders) do
		local set, known, sig = {}, false, {}
		if IsFood(r) then
			-- tested set = every Well Fed ID learned so far; "known" once at least one has been seen
			local ids = VSBH.WellFedIDs()
			for id in pairs(ids) do set[id] = true; sig[#sig + 1] = id; known = true end
			table.sort(sig)
			local key = table.concat(sig, ",")
			if key ~= r.auraKey then r.auraKey, r.auraSet, r.known = key, set, known; changed = true end
		else
		for _, spell in ipairs(r.spells) do
			-- the ranks the player knows, by NAME from the spellbook (Forever's real IDs), plus the
			-- typed table's ranks at or above the highest typed rank known (a higher-rank buff from
			-- another caster counts as up)
			local bookIDs = KnownIDsByName(spell)
			for _, id in ipairs(bookIDs) do if not set[id] then set[id] = true; sig[#sig + 1] = id; known = true end end
			local best
			for i, id in ipairs(spell.ranks) do if set[id] or Known(id) then best = i end end
			if best then
				known = true
				for i = best, #spell.ranks do
					local id = spell.ranks[i]
					if not set[id] then set[id] = true; sig[#sig + 1] = id end
				end
			end
		end
		table.sort(sig)
		local key = table.concat(sig, ",")
		if key ~= r.auraKey then
			r.auraKey, r.auraSet, r.known = key, set, known
			changed = true
		end
		end
	end
	return changed
end