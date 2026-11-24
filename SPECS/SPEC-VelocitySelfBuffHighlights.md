# Velocity Self Buff Highlights - spec

**Repo:** `VelocitySelfBuffHighlights\` (to be: origin WoWAddons-Kuro/VelocitySelfBuffHighlights). **Slash:** `/vsbh`.
**SV:** `VelocitySelfBuffHighlightsDB`. **Clients:** Classic Era (11509) and WoW Forever (16001).
**Research:** `AddonManagement\_EXTERNAL_APIS\wow_forever_aura_secrets_and_buff_reminders.md`.

## Purpose

Puts state **on the action buttons themselves**, so no extra icons or bars are needed:

1. **Buff reminder** - while a self-buff you know is *not* on you (at your highest known rank), every button
   holding that spell plays Blizzard's gold proc glow. Thorns, Mark of the Wild, Inner Fire, ...
2. **Exclusive-group reminder** - same, for a family where exactly one should be up: paladin seals, hunter
   aspects, mage/warlock armours, shaman shields, warrior shouts. Glow while *none* of the family is up.
3. **Auto-attack state mirror** - the player's melee auto-attack and ranged auto-shot state (Blizzard's
   steady yellow checked glow + 0.4 s red flash) drawn on **buttons the player chooses**, typically macros
   such as a hunter's stop-all-attacks or Arcane Shot macro, so the stock Attack / Auto Shot buttons can leave
   the bar.

Everything works **in combat on Forever** - the one hard requirement, proven by the spike (2026-11-23).

## Hard constraints (why the design looks like this)

| Constraint | Consequence |
|---|---|
| Forever: aura data is **secret** in combat; `UnitBuff`/`UnitAura` removed | Lua never decides "buff missing". The engine does, via `CustomAuraContainerTemplate` geometry (below). |
| Container reconfiguration (`AddAuraGroup`, `SetAuraGroupCandidateFilters`) only while auras readable | Rigs are built / repointed out of combat only; in combat we only Show/Hide our plain host frames. |
| Frames anchored to a group-owning container need `DisableUntrustedLayoutScriptsTemplate` | Host, clip and container are created with it; nothing is re-parented into them later. |
| Action buttons are secure | We parent overlays to them for position only; never Show/Hide/SetPoint the button. |
| `IsCurrentSpell` / `PLAYER_ENTER_COMBAT` etc. are the player's own action state | Auto-attack mirror is plain Lua and combat-safe; `issecretvalue` guard as insurance. |
| Classic ranks are separate spell IDs | Every table lists ranks ascending; "the buff" = highest rank known (`IsPlayerSpell`). |

## The engine trick (kind 1 and 2)

Per (button, reminder): `host` over the button -> `AuraContainer` (`SetUnit("player")`, one `HELPFUL` group,
`includeSpellIDs` = **map** of the reminder's tested IDs, `maxFrameCount = 1`, `elementWidth = W+1+2m`) ->
`clip` (`SetClipsChildren`) anchored `TOPLEFT -> container TOPRIGHT (-1-m, m)`, `BOTTOMRIGHT -> host (m, -m)`
-> proc-loop FlipBook texture inside the clip, anchored to the host. Container width is secretly 1 (none of the
IDs on the player) or W+1+2m (one is) -> clip full or zero width. Reference: `Core.lua` `BuildRig` (spike),
EverAuras `ForeverEngineAura.lua` `BuildGroup`.

**Era** has no AuraContainer: `UnitBuff` scan on `UNIT_AURA`, `ActionButtonSpellAlertTemplate` overlay.
Both behind one interface so the rest of the addon does not care (see Architecture).

## Data model

```lua
-- Reminders.lua: static catalogue. Ids are stable SV keys; never rename once released.
VSBH.Reminders = {
  { id = "DRUID.thorns",   class = "DRUID", kind = "buff",
    spells = { { name = "Thorns", ranks = { 467, 782, 1075, 8914, 9756, 9910 } } } },
  { id = "PALADIN.seal",   class = "PALADIN", kind = "group", label = "Seals",
    spells = { { name = "Seal of Righteousness", ranks = {...} }, { name = "Seal of the Crusader", ranks = {...} }, ... } },
}
-- Derived at SPELLS_CHANGED: reminder.auraSet = { [highest known rank of each spell] = true }  (the tested set)
--                            reminder.buttonSet = { [every rank of every spell] = true }       (which buttons glow)
-- kind "buff" is just a "group" with one spell; one code path.

-- Mirrors.lua: the two auto states.
VSBH.Mirrors = {
  melee  = { spellID = 6603, label = "Melee auto-attack" },
  ranged = { spellIDs = { 75, 5019 }, label = "Ranged auto-shot / Shoot" },  -- whichever the class has
}
```

```lua
-- SavedVariables (account-wide; the catalogue is class-scoped so one table serves every character)
VelocitySelfBuffHighlightsDB = {
  reminders = { ["DRUID.thorns"] = true, ["PALADIN.seal"] = false, ... },  -- absent = default on
  mirrors   = { melee  = { ["<class>"] = { "<macro name>", ... } },            -- buttons by macro NAME
                ranged = { ["<class>"] = { "<macro name>", ... } } },
}
```

Macro **name** is the key (not slot): the assignment follows the macro across bars, pages, forms and
VelocityMacroSync. A button is a mirror target when `GetActionInfo(slot)` is `macro` and `GetMacroInfo(id)`
name is in the list. Native Attack / Auto Shot / Shoot buttons already draw the state themselves - not touched.

## Visuals

| Meaning | Look | Source |
|---|---|---|
| "cast this" (kinds 1, 2) | gold proc loop, 1.4x button | atlas `UI-HUD-ActionBar-Proc-Loop-Flipbook`, FlipBook 6x5/30 frames, 1 s |
| "this auto is ON" (kind 3) | steady yellow checked glow **+** full-rect red flash, 0.4 s on/off | Blizzard Attack button: `CheckedTexture` (`UI-Quickslot-Depress`-style highlight, `ADD`) + `Interface\\Buttons\\UI-QuickslotRed` Flash, `ATTACK_BUTTON_FLASH_TIME = 0.4` |

The two never share a meaning; a button may carry one reminder and one mirror at once.

## Architecture

```
Client\Client.lua             INTERFACE = { "BuildMissingOverlay", "ReleaseMissingOverlay", "RefreshMissing", "PlayerKey", "PlayerDisplayName", "PlayerFirstName" }
Client\Client_Forever.lua     engine rigs (container + clip + flipbook); RefreshMissing is a no-op (engine decides)
Client\Client_ClassicEra.lua  UnitBuff scan + ActionButtonSpellAlertTemplate overlay; RefreshMissing on UNIT_AURA
Client\Client_Select.lua      WOW_PROJECT_ID -> flavour, interface check (as QuestAutomator)
Core.lua                      SV init, enabled/disabled, event wiring, /vsbh
Reminders.lua                 the catalogue (all classes)
Mirrors.lua                   melee/ranged state via IsCurrentSpell; checked+flash overlay; macro-name matching
Bars.lua                      Blizzard bar walk (ActionButton1-12, MultiBar*), slot -> spellID / macro name
Options.lua                   settings page (below)
```

Refresh triggers: `PLAYER_LOGIN`, `ACTIONBAR_SLOT_CHANGED`, `ACTIONBAR_PAGE_CHANGED`, `UPDATE_SHAPESHIFT_FORM`,
`UPDATE_BONUS_ACTIONBAR`, `SPELLS_CHANGED`, `PLAYER_REGEN_ENABLED` (apply deferred rig work), `UPDATE_MACROS`.
Mirror triggers: `PLAYER_ENTER_COMBAT`, `PLAYER_LEAVE_COMBAT`, `START_AUTOREPEAT_SPELL`, `STOP_AUTOREPEAT_SPELL`,
`ACTIONBAR_UPDATE_STATE`. Era only: `UNIT_AURA` (player).

## Settings page (`/vsbh`, Options > AddOns > Velocity Self Buff Highlights)

- Header: class name; **only the current class's reminders are listed** (others are irrelevant on this character).
- One checkbox per reminder (default on). Group reminders list their spells in the description.
- Mirrors: **a list of every macro the character has** (account tab then character tab, by name), each row with two
  checkboxes: **Melee** and **Ranged**. Ticked = that macro's buttons mirror that auto state. Rebuilt on `UPDATE_MACROS`.
- `/vsbh status` prints engine availability, each reminder's highest known rank, mirror assignments.

## Milestones

- [x] **M1 Repo & structure** (2026-11-23) - `git init`, LICENSE (MIT), `.pkgmeta`, `_Vanilla.toc`, README, Assets icon, Client\ split
      with the spike's Forever path and the Era path moved into the flavour files. Behaviour identical to the spike.
- [ ] **M2 Catalogue & groups** - `Reminders.lua` for all classes (table below); `auraSet`/`buttonSet` derivation;
      group semantics (glow while none up). Verify Paladin seals in game.
- [x] **M3 Settings** (2026-11-23) - SV, per-reminder checkbox page, macro list with Melee/Ranged checkboxes, `/vsbh status|macros`.
- [x] **M4 Mirrors** (2026-11-23, in-game OK) - `Mirrors.lua`, stock checked atlas + flash atlas overlay. Findings on Forever:
      `IsCurrentSpell(6603/75)` answers **false while auto-attacking** -> state is purely event-driven
      (`PLAYER_ENTER/LEAVE_COMBAT`, `START/STOP_AUTOREPEAT_SPELL`, `PLAYER_DEAD`); `GetActionInfo` returns a **global
      macro ID** for macros (not a 1-based index) so the name comes from `GetActionText(slot)`; `MAX_ACCOUNT_MACROS`
      is nil (fallback 120). Layering: flash in ARTWORK, checked glow in OVERLAY so the frame stays yellow.
- [ ] **M5 Release** - README, publish, first tag.
- [ ] **Icon** - Assets\VelocitySelfBuffHighlights.tga is a placeholder copied from VelocityTweakPile.

## Catalogue (M2) - self-buffs only, cast on self, Classic 1.12 spell data

| Class | Buff reminders | Exclusive groups |
|---|---|---|
| Druid | Thorns, Mark of the Wild, Omen of Clarity | - |
| Paladin | Blessing on self (Might/Wisdom/Kings/Sanctuary/Light/Salvation as one group "a blessing") | Seals; Auras |
| Priest | Power Word: Fortitude, Inner Fire, Shadow Protection, Divine Spirit | - |
| Mage | Arcane Intellect, Dampen/Amplify Magic (opt, default off) | Armours (Frost/Ice/Mage) |
| Warlock | Detect (Greater/Lesser) Invisibility (default off) | Armours (Demon Skin/Demon Armor) |
| Shaman | - | Shields (Lightning Shield; Water Shield on later clients) |
| Hunter | - | Aspects |
| Warrior | - | Battle Shout / Commanding Shout (Era: Battle Shout only) |
| Rogue | - | - |

## Open questions (defaults in bold)

1. Enabled flags account-wide (**yes**; catalogue is class-scoped) vs per character.
2. "Wrong seal up" (Righteousness up, you wanted Crusader): **ignore** - that is rotation logic, not a reminder.
3. Mirror also for **pet** attack state on the same button: **not in v1** (no single API; would need pet-bar
   `GetPetActionInfo` isActive). Revisit.
4. A reminder whose spell the character does not know: **never glows** (empty auraSet would glow forever).
5. Third-party bar addons (Bartender/Dominos): **Blizzard bars only** in v1.
6. Buff cast by someone else at a *higher* rank than you know (MotW from a higher druid): with highest-known-rank
   testing this glows. Option: test "highest known **or higher**" by including all ranks >= yours. **Do that** -
   trivial, strictly better.