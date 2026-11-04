# Changelog

All notable changes to Xius Threat Meter are documented here.

## [1.6.1] - 2026-11-04

### Added
- Registered **Xius Threat Meter** in the default game `Options -> AddOns` window with all settings (Window, Bars, Aggro Warning, and action buttons) synced in real time with the standalone settings panel.
- Added a **Hide Window / Show Window** button to both the standalone settings window and the default game `Options -> AddOns` panel.

### Changed
- `/xtm` (with no arguments) now opens the settings window. Showing and hiding the threat meter window is done from the settings window or via `/xtm show`, `/xtm hide`, and `/xtm toggle`.

### Fixed
- Fixed a crash in Test Mode (`/xtm test`) where the 9th sample raid member indexed past the 8-entry base/swing tables.
- In a raid, you and your pet are always read from the player and pet tokens. A hidden unit comparison can no longer skip your row, so the aggro warning still watches you and your pet.
- Never triggers a false aggro warning from your pet's threat while you are already tanking the enemy.
- Guaranteed strict weak ordering in row sorting so mixed secret/readable values or tied secret names can never cause `table.sort` errors or row flickering.
- Dragging the window scale slider now keeps the window anchored in place instead of drifting across the screen.
- With "Only show when there is threat" enabled, targeting your tank out of combat now polls their target so the window pops up immediately when the pull starts.
- Right-clicking the title bar while the quick menu is open now closes the menu instead of reopening it.
- Swapping pets refreshes the pet portrait icon even when unit GUIDs are hidden, and pets out of 3D portrait range show the fallback pet icon until they enter visual range instead of a blank portrait.
- Tanks holding aggro with 0 numerical threat (e.g., on initial body-pull) now render a full threat bar instead of an empty bar.
- Added fallback resize bounds (`SetMinResize` / `SetMaxResize`), classic group API/color fallbacks, and drag-stop cleanup on hide.

### Improved
- Cached unit identity (`isPlayer` / `isOwnPet`) across threat scans, eliminating redundant `UnitExists`, `UnitIsUnit`, `UnitGUID`, and duplicate-removal passes in 40-player raids and skipping party scans when solo.
- Short-circuited bursty `UNIT_THREAT_LIST_UPDATE` and `UNIT_THREAT_SITUATION_UPDATE` events while a throttled update is already queued, and skipped unit scanning altogether when the window is hidden by visibility rules and aggro warnings are inactive.
- Quantized threat value display checks (`K`/`M` rounding) so `Render()` skips string formatting and widget updates when minor threat ticks do not change the displayed text.
- Cached client gradient API detection after the first texture so startup no longer repeats failed `pcall`s or extra color allocations.
- Formatted secret threat values and percentages as rounded numbers (`%.0f`) instead of raw decimals.

## [1.6.0] - 2026-10-30

### Added
- Loads on Modern (Midnight 12.1.5, interface `120105`) and World of Warcraft Forever (1.60.1, interface `16001`).

### Fixed
- Boss threat is drawn again. Exact numbers are secret in combat, so they are passed straight to the bars and text instead of being dropped.
- Switching targets, or your target switching targets, resets the aggro warning even when the mob id is hidden.
- Hiding pet rows no longer reuses that pet's row for someone else.
- Death knight, monk, demon hunter, and evoker icons resolve on Modern.
- A hidden name, guid, or attack check no longer stops the whole list from updating.

### Changed
- When exact threat numbers are hidden, bars show aggro percent and the warning uses the game's aggro state. The percent slider still applies whenever the numbers are readable.

## [1.5.4] - 2026-10-22

### Fixed
- Healers targeting the tank now see threat on that tank's target. Focus mode does the same with focus target.
- Raid slots are all checked, so a player in a sparse raid id is no longer skipped.
- Threat from your own pet can trigger the aggro warning.
- Clients that only report a threat percent, or that mark the tank with status 3, still draw bars.
- One bad unit no longer stops the rest of the list from updating.
- Turning warning, pets, or visibility options on or off applies immediately.
- Sliders save clean steps (no drifting decimals). Test mode threat no longer climbs forever.
- `/xtm check` reports each option and why the window is hidden.

### Changed
- Combat updates follow threat events (about 5 times a second at most) with a slower safety poll, so idle and busy fights use less CPU.

## [1.5.3] - 2026-10-19

### Fixed
- Removed the washed-out “erased” band across the right side of the title bar (caused by side-faded glow strips).
- Title bar glow is now a single full-width vertical fade that matches the Damage Done meter more cleanly.

### Changed
- Header height tightened again (24px) with smaller header buttons.
- Dropdown chevron fills the button more like the default UI.
- Gear glyph refined with finer teeth and a clearer center hole.
- Minimize button uses a thinner centered gold dash and a darker red fill.

## [1.5.2] - 2026-10-19

### Improved
- Threat updates are event-driven with short coalescing (~0.12s) so bars react faster in combat.
- Combat safety poll reduced to 0.25s.
- Out-of-combat scanning stops when there is no hostile target/focus (lower CPU use).
- Aggro warning resets when switching to a different mob.
- Unrelated nameplate threat events are ignored.
- Skips threat API calls on missing units and skips sorting for 0–1 entries.

### Changed
- Title bar height reduced toward the built-in Damage Done meter proportions.

## [1.5.1] - 2026-10-19

### Improved
- Performance and rendering polish for the threat window and shared UI helpers.

## [1.5.0] - 2026-10-11

### Added
- Initial release for World of Warcraft Forever (TOC `16001`).
- Group/raid threat bars with pets, target/focus modes, aggro warning, settings window, and test mode.
