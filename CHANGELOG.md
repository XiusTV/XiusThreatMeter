# Changelog

All notable changes to Xius Threat Meter are documented here.

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
