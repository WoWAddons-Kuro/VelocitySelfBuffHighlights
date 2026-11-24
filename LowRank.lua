-- Velocity Self Buff Highlights: low-rank badge.
--
-- A red down arrow in the corner of every action button whose spell is a LOWER rank than one
-- the player knows (rank 1 Mark of the Wild on the bar, rank 2 learned at the trainer). No
-- catalogue: the spellbook is read by name, so it works for every class and every spell. Plain
-- data (spellbook + GetActionInfo), readable in combat; nothing secret involved.
-- Setting: db.lowRankBadge (default on).
local ADDON, VSBH = ...

local badges = {} -- button -> texture

--------------------------------------------------------------------------------
-- Spellbook: name -> { highest = rankNumber, ids = { [spellID] = rankNumber } }
-- Rank number comes from the sub-text ("Rank 2"); spells without a rank are ignored.
--------------------------------------------------------------------------------
local book = {}
local bookStamp = 0

local function RankFromSubtext(sub)
	if type(sub) ~= "string" then return nil end
	return tonumber(sub:match("(%d+)"))
end

local function AddEntry(name, spellID, rank)
	if not name or not spellID or not rank then return end
	local e = book[name]
	if not e then e = { highest = 0, ids = {} }; book[name] = e end
	e.ids[spellID] = rank
	if rank > e.highest then e.highest = rank end
end

local function ReadSpellbook()
	wipe(book)
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
		local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if info and info.itemIndexOffset and info.numSpellBookItems then
				for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
					if item and item.name and not item.isPassive then
						local sub = item.subName
						if (not sub or sub == "") and C_Spell and C_Spell.GetSpellSubtext and item.spellID then sub = C_Spell.GetSpellSubtext(item.spellID) end
						AddEntry(item.name, item.spellID or item.actionID, RankFromSubtext(sub))
					end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName and GetSpellBookItemInfo then
		for tab = 1, GetNumSpellTabs() or 0 do
			local _, _, offset, n = GetSpellTabInfo(tab)
			for i = (offset or 0) + 1, (offset or 0) + (n or 0) do
				local name, sub = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
				local _, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
				AddEntry(name, id, RankFromSubtext(sub))
			end
		end
	end
	bookStamp = GetTime()
end

-- Subtext ("Rank 2") of a spell that is NOT in the book any more. Forever/Mainline REPLACE a
-- rank in the spellbook when the next one is trained, so a stale rank-1 button is only known
-- from its own spell data. On Mainline the subtext loads asynchronously: nil on first ask,
-- SPELL_TEXT_UPDATE when it lands, so a load is requested and the refresh re-runs on that event.
local subtextRequested = {}
local function SubtextOf(spellID)
	local sub
	if C_Spell and C_Spell.GetSpellSubtext then sub = C_Spell.GetSpellSubtext(spellID)
	elseif GetSpellSubtext then sub = GetSpellSubtext(spellID) end
	if (sub == nil or sub == "") and not subtextRequested[spellID] then
		subtextRequested[spellID] = true
		if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
	end
	return sub
end

-- For a spell id on a button: its rank and the highest known rank of that spell, or nil.
function VSBH.RankInfo(spellID)
	if not spellID then return nil end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or (GetSpellInfo and GetSpellInfo(spellID))
	if not name or (issecretvalue and issecretvalue(name)) then return nil end
	local e = book[name]
	if not e then return nil end
	local rank = e.ids[spellID]
	if not rank then
		rank = RankFromSubtext(SubtextOf(spellID))
	end
	if not rank then return nil end
	return rank, e.highest, name
end

--------------------------------------------------------------------------------
-- The badge.
--------------------------------------------------------------------------------
local function Badge(button)
	local t = badges[button]
	if t then return t end
	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints(button)
	holder:SetFrameLevel(button:GetFrameLevel() + 6)
	t = holder:CreateTexture(nil, "OVERLAY", nil, 7)
	local w = button:GetWidth() or 36
	local s = math.max(10, math.floor(w * 0.34 + 0.5))
	t:SetSize(s, s)
	t:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
	-- Blizzard's scroll-down arrow art, tinted red
	t:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
	t:SetTexCoord(0.25, 0.75, 0.25, 0.75)
	t:SetVertexColor(1, 0.15, 0.15, 1)
	t.holder = holder
	t:Hide()
	badges[button] = t
	return t
end

function VSBH.IsLowRankBadgeEnabled()
	return VSBH.db and VSBH.db.lowRankBadge ~= false
end

function VSBH.SetLowRankBadgeEnabled(enabled)
	if not VSBH.db then return end
	VSBH.db.lowRankBadge = enabled and true or false
	VSBH.RefreshLowRank()
end

function VSBH.RefreshLowRank()
	if not VSBH.db then return end
	ReadSpellbook()
	local on = VSBH.IsLowRankBadgeEnabled()
	VSBH.ForEachActionButton(function(button, spellID)
		local show = false
		if on and spellID and button:IsVisible() then
			local rank, highest = VSBH.RankInfo(spellID)
			show = rank ~= nil and highest > rank
		end
		local t = badges[button]
		if show then
			t = t or Badge(button)
			if not t:IsShown() then t:Show() end
		elseif t and t:IsShown() then
			t:Hide()
		end
	end)
end

-- Tooltip line for a low-rank button (used by Tooltip.lua).
function VSBH.LowRankNoteFor(button)
	if not VSBH.IsLowRankBadgeEnabled() then return nil end
	local kind, id, _, sid = GetActionInfo(button.action or 0)
	local spellID = (kind == "spell" and id) or (kind == "macro" and (sid or GetMacroSpell(id))) or nil
	local rank, highest, name = VSBH.RankInfo(spellID)
	if not rank or highest <= rank then return nil end
	return string.format("Rank %d on this button - you know rank %d of %s.", rank, highest, name)
end

-- Spell subtext arriving late (Mainline loads it on demand): re-badge once it is here.
local f = CreateFrame("Frame")
f:RegisterEvent("SPELL_TEXT_UPDATE")
f:SetScript("OnEvent", function(_, _, spellID)
	if subtextRequested[spellID] then
		local ok, err = pcall(VSBH.RefreshLowRank); if not ok then VSBH.WarnOnce("lowrank", tostring(err)) end
	end
end)