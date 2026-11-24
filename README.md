# Velocity Self Buff Highlights

State **on the action buttons themselves**, so no extra icons or bars are needed.

- **Buff reminders** - while a self-buff you know is not on you (at your highest rank), every action
  button holding that spell plays Blizzard's gold proc glow. Cast it, the glow goes. Thorns, Mark of the
  Wild, and exclusive families like paladin seals (glow while *no* seal is up).
- **Auto-attack mirrors** - the melee auto-attack and ranged auto-shot state (Blizzard's yellow
  "active" glow with the red flash), drawn on the **macro buttons you pick** - a hunter's stop-all
  macro, an Arcane Shot macro - so the stock Attack and Auto Shot buttons can leave your bar.

**Works in combat on WoW Forever.** Forever hides aura data from addons in combat; this addon never reads
it. Blizzard's own aura engine decides whether the glow is drawn, by geometry the addon cannot see.
Classic Era too, where the plain path is used.

## Options

`/vsbh` opens the page (Options > AddOns > Velocity Self Buff Highlights): a checkbox per reminder for
your class, and the list of your macros with **Melee** / **Ranged** checkboxes. `/vsbh status` prints
the state. Settings are account-wide; macro mirrors are per class, by macro name.

## Licence

MIT.