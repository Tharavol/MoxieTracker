# MoxieTracker

MoxieTracker is a World of Warcraft addon for Retail / Midnight that displays the current character's Artisan Moxie, Shard of Dundun, and Unalloyed Abundance currency values, plus the Fused Vitality item count, in a small movable window, with a Knowledge Points roster and a Concentration roster in their own windows beneath it. The main panel appears automatically when the crafting window opens and hides again when it closes.

## Features

- Tracks Artisan Moxie for all eleven professions, Shard of Dundun, and Unalloyed Abundance, matched by currency ID so it works on any client locale
- Tracks Fused Vitality (item 245345), counted across bags, bank, and reagent bank
- Shard of Dundun, Unalloyed Abundance, and Fused Vitality always show, even at zero; moxie rows appear only for professions the character actually has
- A "Show Moxie" checkbox on the options panel's General page hides Moxie from the tracker entirely, a global setting independent of any character; individual professions can be hidden from their own "Moxie Professions" page
- Any row can be hidden from the options panel, under Options > AddOns > MoxieTracker or `/moxie options`
- Colors each count against its own thresholds: Shard of Dundun is green at 6 and red at 7-8, Unalloyed Abundance is green at 800 or more, Moxie is green at 600 or more, Fused Vitality is green at 20 or more, yellow otherwise
- Docks a compact, draggable panel to the top-right of the crafting window, shown only while that window is open
- Displays the same tooltip information as the default currency UI when hovering over a line
- Prints the addon version to chat at login (toggle from the options panel) and shows it in the options panel title
- Tracks unspent profession Knowledge (summed across all eleven professions) for every character that has logged in, in its own window, with each character's name in green. Builds up automatically as you log into each character; the current character's total is always live
- Tracks Crafter's Concentration for every character that has logged in, one row per crafting profession with a projected time until it reaches its cap; regenerates in real time, so an offline character's row is projected forward from its last login rather than shown stale. Colored per profession (default green at 300, editable) with red at the real cap. An option on the Thresholds page can hide a profession's line entirely while it is under threshold, instead of always showing it
- All three windows (main panel, Knowledge Points, Concentration) are independently movable and remember their own position across the whole account
- Either roster can mute a whole character or just one of their professions, from its own section in the options panel

## Slash commands

`/moxie` and `/moxietracker` are both recognized. `/moxie` on its own (also `options`, `config`, `gui`) opens the options panel and chooses which rows are shown.

- `/moxie showall` - unhide every row
- `/moxie pin` - keep the panel visible even with no profession open
- `/moxie debug [on|off]` - toggle or set debug logging
- `/moxie debug dump` - print the anchor state, every tracked currency and item ID with its quantity, the hidden rows, then every currency with a nonzero quantity
- `/moxie reset position` - move all three windows back to their default positions
- `/moxie reset settings` - restore hidden rows, muted characters/professions, the Moxie, Knowledge Points and Concentration window toggles, pin state, thresholds, the Concentration under-threshold display toggle, and debug logging to defaults
- `/moxie status` - show current settings
- `/moxie version` - show the addon version
- `/moxie help` - list all commands

## Installation

1. Copy the MoxieTracker folder into your World of Warcraft AddOns directory.
2. Launch World of Warcraft.
3. Reload the UI or restart the game.

## Changelog

Release history is in [CHANGELOG.md](CHANGELOG.md).

## Development and CI

- GitHub Actions validates the addon on pushes and pull requests: `luac5.1 -p` for syntax, a headless test suite (`tests/run.lua`) for the pure collection logic, luacheck for undefined globals, and a check that the TOC declares an interface version.
- A release artifact is packaged automatically on pushes to main.
- Tagging a release with a version like v1.0.0 creates a GitHub Release with the packaged addon zip.

## Credits

- Created by Tharavol
- Initial scaffold assisted by GitHub Copilot
- Midnight API fixes, crafting window integration, and currency thresholds by Claude Opus 5 (Anthropic), working through Claude Code
- Concentration currency discovery and its regen-projection math were confirmed against [derfloh205/CraftSim](https://github.com/derfloh205/CraftSim) (MIT licensed), which already tracks Concentration; no CraftSim code is included in MoxieTracker (see docs/CURRENCY_DISCOVERY.md's Sources section for what was learned there)

## License

MoxieTracker is licensed under the GNU General Public License v3.0. The full
license text is in [LICENSE](LICENSE), and each source file carries the
standard GPL notice.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.
