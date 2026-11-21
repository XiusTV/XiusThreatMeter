# Xius Threat Meter

A threat meter for **modern World of Warcraft** and **World of Warcraft Forever**. It sits beside the built-in damage meter: gold title bar, class-colored bars, and a dark background. It shows who is on the enemy's threat table, how much threat each player and pet has, and how close anyone is to pulling aggro.

Settings open inside [Xius Core](https://github.com/XiusTV/XiusCore). Xius Core is required.

The window is meant to blend with the default UI.

## Features

### Live threat tracking

- **Group and raid:** Tracks you, your party, your raid (up to 40 players), and pets on the enemy's threat table.
- **Target or focus:** Watch your target, or switch to your focus with the `T` / `F` button.
- **Ranked bars:** Each row shows rank, name, threat, TPS, and percent, for example `1. Xius  1,234 (120) (87%)`.
- **Relative fill:** When the client shows threat numbers, bars fill against the top of the list. When those numbers are hidden, bars fill by aggro percent, so a full bar means that player is about to pull.
- **Growth and sort:** Bars can grow top-to-bottom or bottom-to-top, and sort by highest threat, lowest threat, or tank first.
- **Tooltips:** Hover a bar for threat, threat percent, raw threat percent, and whether that player is tanking.

### Ability Threat Estimator

- **Out-of-combat estimates:** Calculates threat for known abilities from your attack power, spell power, weapon damage, form/stance, and talents.
- **Breakdown window:** Sortable table of hit and crit threat. Open it from Xius Core or with `/xtm abilities`.
- **Spell tooltips:** While out of combat, spell tooltips show estimated threat (and crit threat) with your current threat multiplier. Nothing is evaluated in combat or against secret values.

### Aggro warning

- **Pull alert:** Turns the window title amber, then red, and can play a warning sound as your threat gets close to the tank's. Visual and audio alerts are separate toggles.
- **Threshold:** Choose when the warning fires (50% – 100%, default 90%).
- **Role:** Auto uses your group role when the client has one. Tank warns when someone else contests or takes aggro. DPS and healers are warned as they approach the tank. Your own pet does not trip the warning while you are tanking.

### Native default UI look

- **Title bar:** The same gold header, header buttons, and dark body as the damage meter.
- **Class colors and icons:** Bars use class colors (optional). Pets use green bars and their own portraits.
- **Opacity, scale, and texture:** Background opacity, window scale, font size, and bar texture (Blizzard, Flat, or Raid).

## Display States

- **Expanded:** Title bar plus as many rows as fit the window. Resize to show more or fewer rows (up to 40).
- **Minimized:** Collapses upward to the title bar. The minimize button turns into a gold `+`. Click it again to expand.

## Controls & Slash Commands

| Command / Input | Action |
| --- | --- |
| `/xtm` or `/xthreat` | Open this page in Xius Core |
| `/xtm show` | Show the threat window |
| `/xtm hide` | Hide the threat window |
| `/xtm toggle` | Show or hide the threat window |
| `/xtm help` | List the commands |
| `/xtm config` | Open this page in Xius Core |
| `/xtm abilities` | Open the Ability Threat Breakdown window |
| `/xtm test` | Toggle test bars |
| `/xtm lock` or `/xtm unlock` | Lock or unlock moving and resizing |
| `/xtm target` or `/xtm focus` | Choose which enemy to track |
| `/xtm reset` | Reset window position and size |
| `/xtm check` | Show each option and why the window may be hidden |
| `/xius threat` | Open this page from Xius Core |
| Left-drag the title bar | Move the window when it is unlocked |
| Right-click the title bar | Open the quick menu |
| Bottom-right corner | Resize the window |
| `▼` button | Quick menu: Target / Focus, Test Mode, Lock, Settings, Hide |
| `T` / `F` button | Switch between target and focus |
| Gear button | Open this page in Xius Core |
| Red button | Minimize or expand |

## Configuration

Open settings with the gear button, `/xtm`, or `/xius threat`.

- **General:** Enable the meter, track target or focus, solo / party / raid visibility, lock, scale, size, opacity, test mode, and the Ability Threat Estimator.
- **Appearance & Bars:** Bar texture, font size, height, spacing, class colors, icons, threat numbers, TPS, growth direction, and sort order.
- **Alerts & Roles:** Role mode, warning threshold, visual and audio alerts, pet bars, and pet warning.

Settings are saved for the account and shared with Xius Core profiles.

## Installation

1. Install [Xius Core](https://www.curseforge.com/wow/addons/xius-core) first. This addon will not load without it.
2. Download the latest release `.zip` (or use **Code → Download ZIP** on this page).
3. Extract the `XiusThreatMeter` folder into the addon directory for the client you play:
   - Modern: `World of Warcraft\_retail_\Interface\AddOns`
   - WoW Forever: `World of Warcraft Forever\Interface\AddOns`
   If the extracted folder is named `XiusThreatMeter-main`, rename it to `XiusThreatMeter`.
4. Launch the game, confirm Xius Core and Xius Threat Meter are both enabled, and run `/reload`.
5. Type `/xtm test` to preview the bars and drag the window into place.

**Compatibility:** Modern World of Warcraft and World of Warcraft Forever. On boss fights the client hides exact threat numbers. The bars still draw, and the aggro warning follows the game's own aggro state.

## More From Xius

### Xius Core - [GitHub](https://github.com/XiusTV/XiusCore) · [CurseForge](https://www.curseforge.com/wow/addons/xius-core)

The settings window for every Xius addon. Quality of Life, profiles, account gold, and the minimap button live here. Quest log collapse is part of Xius Core. The old standalone quest collapser is retired.

### Xius XP & Reputation Tracker - [GitHub](https://github.com/XiusTV/XiusXPTracker) · [CurseForge](https://www.curseforge.com/wow/addons/xius-xp-and-reputation-tracker)

A HUD card for level, XP, rested XP, watched faction, session rates, gold, and time-to-level.

### Xius Marks Bar - [GitHub](https://github.com/XiusTV/XiusMarksBar) · [CurseForge](https://www.curseforge.com/wow/addons/xius-marks-bar)

A raid marking bar. Click the flag for world markers or the star for target markers. Includes 5 / 10 / 20 pull timers, ready check, and role check.

### Xius Max Graphics - [GitHub](https://github.com/XiusTV/XiusMaxGFX) · [CurseForge](https://www.curseforge.com/wow/addons/xius-max-graphics)

Graphics presets for Forever and retail. Ultimate, Balance, and Defaults raise view distance, grass, shadows, water, and image clarity, with optional loot and gathering sparkles.

### Xius Kill Streak - [GitHub](https://github.com/XiusTV/XiusKillStreak) · [CurseForge](https://www.curseforge.com/wow/addons/xius-kill-streak)

A ten-tier kill streak announcer for mobs and enemy players. Each tier shows a banner, plays a call, and keeps a counter for the streak and the time left.

Their settings open from Xius Core.

## License

Released under the [GNU General Public License v3.0](LICENSE).

## Development & AI Disclosure

This addon was built and refactored with the assistance of AI development tools (Cursor / LLMs) for code generation, UI layout structure, and visual styling, with manual architecture, in-game verification, and maintenance by Xius.
