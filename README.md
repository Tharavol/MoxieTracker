# MoxieTracker

MoxieTracker is a World of Warcraft addon for Retail / Midnight that displays the current character's Artisan Moxie, Shard of Dundun, and Unalloyed Abundance currency values, plus the Fused Vitality item count, in a small movable window. The panel appears automatically when the crafting window opens and hides again when it closes.

## Features

- Tracks Artisan Moxie for all eleven professions, Shard of Dundun, and Unalloyed Abundance, matched by currency ID so it works on any client locale
- Tracks Fused Vitality (item 245345), counted across bags, bank, and reagent bank
- Shard of Dundun, Unalloyed Abundance, and Fused Vitality always show, even at zero; moxie rows appear only for professions the character actually has
- Any row can be hidden from the options panel, under Options > AddOns > MoxieTracker or `/moxie options`
- Remembers one panel position across the whole account
- Colors each count against its own thresholds: Shard of Dundun is green at 6 and red at 7-8, Unalloyed Abundance is green at 800 or more, Moxie is green at 600 or more, Fused Vitality is green at 20 or more, yellow otherwise
- Docks a compact, draggable panel to the top-right of the crafting window, shown only while that window is open
- Displays the same tooltip information as the default currency UI when hovering over a line
- Prints the addon version to chat at login (toggle from the options panel) and shows it in the options panel title

## Slash commands

`/moxie` and `/moxietracker` are both recognized.

- `/moxie options` - open the options panel and choose which rows are shown
- `/moxie showall` - unhide every row
- `/moxie pin` - keep the panel visible even with no profession open
- `/moxie debug` - print the anchor state, every tracked currency and item ID with its quantity, the hidden rows, then every currency with a nonzero quantity
- `/moxie reset` - move the panel back to the crafting window's top-right corner

## Installation

1. Copy the MoxieTracker folder into your World of Warcraft AddOns directory.
2. Launch World of Warcraft.
3. Reload the UI or restart the game.

## Changelog

Release history is in [CHANGELOG.md](CHANGELOG.md).

## Development and CI

- GitHub Actions validates the addon on pushes and pull requests: `luac5.1 -p` for syntax, luacheck for undefined globals, and a check that the TOC declares an interface version.
- A release artifact is packaged automatically on pushes to main or master.
- Tagging a release with a version like v1.0.0 creates a GitHub Release with the packaged addon zip.

## Credits

- Created by Tharavol
- Initial scaffold assisted by GitHub Copilot
- Midnight API fixes, crafting window integration, and currency thresholds by Claude Opus 5 (Anthropic), working through Claude Code

## License

MoxieTracker is licensed under the GNU General Public License v3.0. The full
license text is in [LICENSE](LICENSE), and each source file carries the
standard GPL notice.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.
