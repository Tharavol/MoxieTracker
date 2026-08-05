# Handoff Notes

## Project summary

MoxieTracker is a World of Warcraft addon for Retail / Midnight that displays current-character Artisan Moxie, Shard of Dundun, and Unalloyed Abundance currency values, plus the Fused Vitality item count, in a movable panel. The panel is shown while the crafting window is open and hidden otherwise; it defaults to the top-right of that window and can be dragged anywhere. Any row can be switched off from the options panel.

## Current state

- Addon files: MoxieTracker.toc, MoxieTracker.lua
- Tests: tests/stub.lua (fake WoW API), tests/run.lua (the tests, run with `lua5.1 tests/run.lua`). CI runs them; see the "Testing" note below.
- Release history is in CHANGELOG.md, following Keep a Changelog. Add an entry there as part of any change worth releasing; the packager includes CHANGELOG.md in the addon folder for both the CI and release workflows (per .pkgmeta's manual-changelog setting), and CI's package job fails if it is missing from the built archive. Do not touch ## Version in the TOC: since 1.1.1 it is the literal @project-version@, substituted by the packager from the release tag.
- Repository root: this folder
- License: GPL-3.0. LICENSE holds the full 674-line text fetched from gnu.org; it previously held only a 23-line stub that named the license and then cut to "See the GNU GPL for more details", so the terms were not actually stated. MoxieTracker.lua carries the standard GPL notice header, per the "How to Apply These Terms" section of the license.
- Credits: created by Tharavol, scaffold assisted by GitHub Copilot, Midnight API fixes and crafting window integration by Claude Opus 5 via Claude Code.

## Development notes

- The panel is created with the BackdropTemplate template; plain frames have had no SetBackdrop method since patch 9.0.
- Each currency row is a Frame wrapping a FontString, because FontStrings do not support script handlers such as OnEnter.
- Currency values are refreshed on relevant currency events such as CURRENCY_DISPLAY_UPDATE and PLAYER_LOGIN, and whenever the panel is shown.
- Visibility follows the crafting window via TRADE_SKILL_SHOW / TRADE_SKILL_CLOSE plus OnShow / OnHide hooks on ProfessionsFrame. Blizzard_Professions is load-on-demand, so the hook is deferred through EventUtil.ContinueOnAddOnLoaded.
- The panel anchors its TOPLEFT to ProfessionsFrame's TOPRIGHT, so it sits off the right edge of the crafting window and tracks that window when it moves. The default offset (4, -440) drops it down the right side; it was read back from a placement verified in-game, not guessed.
- A dragged position can be read off disk without being in-game: it is written to WTF/Account/<ACCOUNT>/SavedVariables/MoxieTracker.lua. The file is flushed on /reload or logout, so it is stale until one of those happens.
- Dragging stores an offset from that same TOPRIGHT corner in MoxieTrackerDB, normalized through both frames' effective scales so a dragged position round trips exactly even when the two frames differ in scale. /moxie reset clears it. If the anchor corner in ApplyAnchor is ever changed, SaveOffsetFromAnchor must be changed to match or dragging will jump.
- /moxie debug reports the current anchor offset, whether it is the default or user placed, whether the crafting frame was found, the tracked items, and every hidden row. /moxie showall clears the hidden table.
- Currencies are collected in three passes, deduped by both ID and lowercased name. ALWAYS_SHOWN_IDS (Shard of Dundun 3376, Unalloyed Abundance 3377) render even at zero. MOXIE_IDS (3256-3266, one per profession) render only above zero, since every character could otherwise show eleven empty rows. A keyword pass over the currency list then catches anything neither table knows about.
- Matching is by ID first because currency names are localized: a name scan finds nothing on a non-English client. The keyword list is a fallback for a moxie currency added in a future patch, not the primary path.
- Fused Vitality (245345) is an item, not a currency, so it comes from C_Item: GetItemCount for the count and GetItemInfo for the name. Its pass in CollectTracked always adds a row, the same way ALWAYS_SHOWN_IDS does, so a zero count reads as "none" rather than as a missing row. Item names are not cached at login, which is why TRACKED_ITEMS carries a fallback name, RequestLoadItemDataByID runs at load, and GET_ITEM_INFO_RECEIVED forces a redraw. Bag counts do not move on currency events, hence BAG_UPDATE_DELAYED.
- The item count includes bank and reagent bank (GetItemCount(id, true, false, true, true)), so it reads as "how many the character owns" rather than "how many are carried". Change those flags if the count should be bags only.
- GET_ITEM_INFO_RECEIVED fires for every item entering the client's cache during play, not just tracked ones, so the handler filters on the event's itemID against TRACKED_ITEM_ID_SET before redrawing. Without the filter, a crafting window streaming reagent data into the cache triggered hundreds of full-panel rebuilds.
- Hidden rows live in MoxieTrackerDB.hidden, keyed by EntryKey: "currency:<id>", "item:<id>", or "name:<lowercased>" for a keyword-fallback row whose link would not resolve. Only hidden rows are stored; visible is the absence of a key, so the table stays empty for a default install. If ApplyAnchor-style ID tables ever change, the keys stay valid because they are IDs rather than names.
- CollectTracked marks an entry as seen before the hidden check, so a hidden currency cannot re-enter through a later pass that identifies it a different way. CollectTracked(true) returns hidden entries too, which is what the options panel lists.
- The options panel is a canvas layout category (Settings.RegisterCanvasLayoutCategory plus RegisterAddOnCategory) and rebuilds its checkbox rows in OnShow rather than at load, because the trackable set is not known until runtime: moxie rows exist only for professions the character has, and the keyword fallback can turn up an unknown currency. Rows use an explicit FontString label rather than the UICheckButtonTemplate text region, whose name has moved between expansions. This was confirmed working in-game on a 120007 client in v1.2.0 -- the category registers under Options > AddOns, the rows render, and toggling one updates the panel -- so neither the Settings API calls nor the checkbox template need re-checking against that client version.
- Matching deliberately ignores info.description. Descriptions cross-reference each other -- Shard of Dundun's mentions Unalloyed Abundance -- so matching them pulls in unrelated currencies.
- Currency IDs are not returned by GetCurrencyListInfo; they are parsed out of GetCurrencyListLink. That call can fail, which is why dedupe also keys on name.
- GetCurrencyListInfo only enumerates visible rows, so currencies under a collapsed header are invisible to it. The ID passes are immune to this; the keyword fallback is not.
- The panel matches the crafting frame's strata and sits ten levels above it. At UIParent's default MEDIUM strata it drew beneath the crafting window and the addon panes docked to it, such as CraftSim's.
- Panel width is measured from the widest rendered row via GetStringWidth, floored at 240. Color escapes do not count toward that measurement.
- MoxieTrackerDB is account-wide (## SavedVariables). It was per-character until v1.1.0, which meant repositioning on every character. Switching scope orphans the old per-character files under WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/; the client ignores them and they can be deleted.
- The client interface version is 120007. Changes to the TOC require a full client restart, not a UI reload.
- MoxieTrackerDB is initialized in the ADDON_LOADED handler, gated on the addon's own name (captured as ADDON_NAME from the file's vararg), rather than at file scope. SavedVariables are only guaranteed populated once ADDON_LOADED fires for this addon; initializing earlier would create a throwaway table that the client's own load then discards. GetOffset() is the one accessor that can run before that point (the initial file-scope ApplyAnchor() call), so it tolerates MoxieTrackerDB being nil and falls back to the default offset.
- The version shown at login and in the options panel title comes from GetVersion(), which reads C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") and falls back to "dev" when the TOC still has the literal @project-version@ placeholder (an unpackaged copy). The login message respects MoxieTrackerDB.suppressLoginMessage, toggled from a checkbox in the options panel; this is read once at PLAYER_LOGIN, which is why it depends on MoxieTrackerDB already being initialized by ADDON_LOADED. Neither the login print nor the options title adds its own "v" prefix, since the version string from the release tag already carries one.
- /moxie and /moxietracker are both registered (SLASH_MOXIETRACKER1/2); SlashCmdList registration is last-writer-wins, so the longer alias is a fallback in case another addon takes the short one.
- The TOC declares IconTexture (Interface\Icons\INV_Misc_Coin_02) and Category (Professions) so the addon shows a real icon and groups correctly in the in-game AddOns list; both are cosmetic only.
- `local ADDON_NAME, ns = ...` captures the addon-private table WoW passes to every TOC-listed file. The ID/colour tables (ALWAYS_SHOWN_IDS, MOXIE_IDS, TRACKED_ITEMS, KEYWORDS, QUANTITY_COLOR, ITEM_QUANTITY_COLOR) and the functions that turn them into rows (EntryKey, GetQuantityColor, CollectTracked) hang off `ns` rather than being file-locals, so a second file or a test harness can reach them. `ns` is not a global, so this adds nothing to `.luacheckrc`. Everything UI-facing (the frame, the options panel, the slash command handler) stays file-local; there was no reason to expose it, and it still runs at file scope, so a test harness that loads this file whole still needs to stub the WoW frame API, not just C_CurrencyInfo/C_Item.
- Testing: tests/stub.lua installs a fake C_CurrencyInfo, C_Item, and C_AddOns (configurable per test via the fixtures table it returns), plus a generic catch-all stub object for CreateFrame/GameTooltip/UIParent -- one that answers any method call by returning another instance of itself, since MoxieTracker.lua's UI-construction code runs unconditionally at file scope and the tests never inspect what those calls return. tests/run.lua loads MoxieTracker.lua once against that stub to get `ns`, then drives scenarios by mutating the fixtures and MoxieTrackerDB.hidden between checks rather than reloading the file. Coverage priority, matching what is least protected: the dedupe/hidden-row precedence invariant in CollectTracked's `Add()` closure, EntryKey's persisted-key format, then the color thresholds. Run with `lua5.1 tests/run.lua` from the repo root; it exits non-zero on any failure.

## Next steps

- The options panel covers row visibility only. Position, size, and color thresholds are still code-level; the panel is the obvious place to add them.
- The options panel has no scroll frame. Eleven moxie rows plus the currencies and Fused Vitality fit the settings canvas, but a longer list would run off the bottom.
- The panel sits well down the right edge (-440). On a short crafting window or a small resolution it could run past the bottom of the screen; SetClampedToScreen keeps it visible but would break the chosen alignment. Worth checking at the smallest resolution in use.
- Continue development from another machine by cloning from GitHub.

## Local setup checklist

1. Install Git if needed.
2. Clone the repo from GitHub on the target machine.
3. Copy the addon folder into the WoW AddOns directory.
4. Reload the UI to test.
