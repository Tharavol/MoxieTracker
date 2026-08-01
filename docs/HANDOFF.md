# Handoff Notes

## Project summary

MoxieTracker is a World of Warcraft addon for Retail / Midnight that displays current-character Artisan Moxie, Shard of Dundun, and Unalloyed Abundance currency values in a movable panel. The panel is shown while the crafting window is open and hidden otherwise; it defaults to the top-right of that window and can be dragged anywhere.

## Current state

- Addon files: MoxieTracker.toc, MoxieTracker.lua
- Repository root: this folder
- License: GPL-3.0. LICENSE holds the full 674-line text fetched from gnu.org; it previously held only a 23-line stub that named the license and then cut to "See the GNU GPL for more details", so the terms were not actually stated. MoxieTracker.lua carries the standard GPL notice header, per the "How to Apply These Terms" section of the license.
- Credits: created by Tharavol, scaffold assisted by GitHub Copilot, Midnight API fixes and crafting window integration by Claude Opus 5 via Claude Code.

## Development notes

- The panel is created with the BackdropTemplate template; plain frames have had no SetBackdrop method since patch 9.0.
- Each currency row is a Frame wrapping a FontString, because FontStrings do not support script handlers such as OnEnter.
- Currency values are refreshed on relevant currency events such as CURRENCY_DISPLAY_UPDATE and PLAYER_LOGIN, and whenever the panel is shown.
- Visibility follows the crafting window via TRADE_SKILL_SHOW / TRADE_SKILL_CLOSE plus OnShow / OnHide hooks on ProfessionsFrame. Blizzard_Professions is load-on-demand, so the hook is deferred through EventUtil.ContinueOnAddOnLoaded.
- The panel anchors its TOPLEFT to ProfessionsFrame's TOPRIGHT, so it sits off the right edge of the crafting window and tracks that window when it moves. The default offset (4, -440) drops it down the right side; it was read back from a placement verified in-game, not guessed.
- A dragged position can be read off disk without being in-game: it is written to WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/MoxieTracker.lua. The file is flushed on /reload or logout, so it is stale until one of those happens. The variable is SavedVariablesPerCharacter, so each character has its own file.
- Dragging stores an offset from that same TOPRIGHT corner in MoxieTrackerDB, normalized through both frames' effective scales so a dragged position round trips exactly even when the two frames differ in scale. /moxie reset clears it. If the anchor corner in ApplyAnchor is ever changed, SaveOffsetFromAnchor must be changed to match or dragging will jump.
- /moxie debug reports the current anchor offset, whether it is the default or user placed, and whether the crafting frame was found.
- Observed in-game: Artisan Moxie is per-profession, e.g. "Artisan Alchemist's Moxie" (id 3256). The "moxie" keyword catches every profession variant, which is why matching is by name rather than by ID.
- Shard of Dundun (id 3376, no apostrophe, per its Wowhead page) and Unalloyed Abundance (id 3377) are tracked by explicit ID, not by keyword. Undiscovered currencies are absent from the currency list entirely, so a name scan cannot find one the character has never held. Explicit IDs are shown even at zero quantity; keyword matches still require a quantity above zero.
- Currency IDs are not returned by GetCurrencyListInfo; they are parsed out of GetCurrencyListLink.
- Keyword matching ("moxie", "dundun") covers the per-profession moxie currencies and requires a quantity above zero. Explicitly tracked IDs bypass both the keyword list and the zero check.
- GetCurrencyListInfo only enumerates visible rows, so currencies under a collapsed header are invisible to it. Matching on explicit currency IDs would avoid this.
- The client interface version is 120007. Changes to the TOC require a full client restart, not a UI reload.

## Next steps

- Add optional configuration for position, size, or color if desired.
- The panel sits well down the right edge (-440). On a short crafting window or a small resolution it could run past the bottom of the screen; SetClampedToScreen keeps it visible but would break the chosen alignment. Worth checking at the smallest resolution in use.
- Continue development from another machine by cloning from GitHub.

## Local setup checklist

1. Install Git if needed.
2. Clone the repo from GitHub on the target machine.
3. Copy the addon folder into the WoW AddOns directory.
4. Reload the UI to test.
