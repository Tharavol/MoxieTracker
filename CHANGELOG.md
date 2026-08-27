# Changelog

All notable changes to MoxieTracker are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.9.2] - 2026-08-26

### Fixed
- A character's Moxie row list could show a profession they never trained, e.g. both Alchemist's and Engineer's Moxie for a character who only has one of the two (#42). `C_CurrencyInfo.GetCurrencyInfo` returns a valid nonzero quantity for any profession's Moxie currency once any character on the account has earned it, not just the currently logged-in one -- the same account-wide-currency leak #40 already fixed for Concentration, now also applied to Moxie's row collection.
- Concentration almost never accumulated across characters (#42, #40 follow-up). `GetProfessions()` -- the API `ns.IsProfessionLearned` uses to gate a character's Concentration snapshot -- goes dark by the time `PLAYER_LOGOUT` fires, reporting no profession at all even for a character confirmed live moments earlier in the same session, so a logout only ever recorded real data for a character who happened to freshly discover their own profession's currency ID while its crafting window was open. Every other character silently logged out with an empty Concentration entry. A per-character cache now remembers the last confirmed-live result and falls back to it when the API drops out at logout.

## [1.9.1] - 2026-08-26

### Changed
- The options panel is now six pages instead of one long scroll (#41): a "General" top-level page (login message, window visibility, window positions, tracked currencies), a "Thresholds" page (all eleven color thresholds), and four mute pages -- "Characters", "Character Professions", "Concentration", and "Concentration Professions" -- one per list instead of all four sharing a single "Muting" page. Purely a reorganization -- no settings, thresholds, or mute behavior changed.

## [1.9.0] - 2026-08-26

### Added
- Tracks Crafter's Concentration for every character that has logged in, in its own window below the Knowledge Points window, with a projected time until each profession reaches its cap (#40). Concentration keeps regenerating in real time even while a character is offline, so an alt's row is projected forward from its last login rather than shown stale; the current character's own row stays live. Currency IDs are discovered automatically the first time each profession's crafting window is opened -- there is no fixed list to hardcode, since Concentration is resolved per profession rather than by a static ID.
- Every window (the main tracker, Knowledge Points, and the new Concentration window) is now independently movable and remembers its own position, rather than Knowledge Points always trailing beneath the main window. Undragged windows keep stacking beneath the one above them exactly as before, so nothing moves for existing users until a window is actually dragged.
- Concentration coloring gets its own threshold per crafting profession (default 300, editable in the options panel), separate from Moxie's single shared threshold; a currency at its real cap always renders red regardless of the threshold.
- Concentration gets its own "Concentration" and "Concentration Professions" mute sections in the options panel, mirroring Knowledge's Characters/Character Professions pair exactly -- muting a character's (or one profession's) Concentration never touches their Knowledge mute state, and vice versa.

### Changed
- The options panel's Position section now has one compact row per window (label, X, Y, Reset) instead of a single block for the main window only, with X/Y column labels and Tab/Shift-Tab moving between a row's two fields.
- All eleven color thresholds (Unalloyed Abundance, Moxie, Fused Vitality, and the eight Concentration professions) now live under one "Color thresholds" section with a single reset button, instead of Concentration having its own separate section.

## [1.8.0] - 2026-08-11

### Fixed
- Knowledge is now snapshotted on logout instead of on entering the world. The latter fires on every zone/instance load, not just true login, and could read currency data before it finished syncing from the server, occasionally persisting 0 and clobbering a character's real total until its next login (#38).
- The options panel's row lists (tracked currencies, muted characters, and the new muted professions below) now share a single scroll region instead of two small ones sitting below an un-scrolled Position/Threshold section. A large-enough roster used to overflow past the bottom of the window and draw over the Close button rather than scrolling.

### Added
- A "Character Professions" section in the options panel mutes a single profession's Knowledge for a single character, without muting the whole character (#38 follow-up).

## [1.7.0] - 2026-08-11

### Added
- Tracks unspent profession Knowledge for every character that has logged in, shown in its own window anchored below the main tracker rather than as a section of it, so a long roster doesn't push the currency rows around (#38). The roster grows automatically as you log into each character -- no rescan is needed or possible, since the addon can only see whichever character is currently logged in. The current character's total is always live rather than the last-login snapshot.
- Characters with unspent points in more than one profession show a per-profession breakdown, indented under the character's name, e.g.:
  ```
  Tharavol
      Engineering: 4
      Tailoring: 2
  ```
  A character with points in exactly one profession still gets the same breakdown format, so a count is never ambiguous between "N total" and "N in this profession".
- A "Characters" section in the options panel lets any character be muted out of the Knowledge Points roster permanently, independent of hiding individual currency/item rows.
- A "Show Knowledge Points window" checkbox in the options panel hides the whole window regardless of content.
- A real `IconTexture` (`inv_10_gearcraft_artisansmettle_color2`), replacing the placeholder coin icon.

### Changed
- A character with 0 unspent Knowledge no longer appears in the roster at all, matching how tracked currencies already hide what isn't there.
- Character names render in white with point counts in green (previously the whole line was green).
- `/moxie reset settings` and `/moxie status` now also cover muted characters and the Knowledge Points window's visibility.

## [1.6.0] - 2026-08-11

Adopts the cross-addon slash command standard (#37).

### Changed

- Bare `/moxie` now opens the options panel instead of printing the command list; that list moved to a new `help` command
- `debug` is now a real `on`/`off` logging toggle (bare toggles and reports the new state); the old one-shot diagnostic dump moved to `debug dump` so it isn't lost
- `reset` on its own used to move the panel back to the crafting window's top-right; that's now `reset position`, freeing `reset settings` to restore hidden rows, pin state, thresholds and debug logging to defaults
- Extracted every `print()` call site (about fifteen of them, each hand-writing its own colour prefix) into a single `ns.Print` helper
- An unrecognised command, or a recognised one given a bad argument, now says so instead of silently falling back to the command list

### Added

- `status`, `version`, `help`, and `gui` as an additional alias for the options panel (alongside the existing `options`/`config`)

## [1.5.2] - 2026-08-11

### Changed

- Bump TOC Interface to 120100 for WoW 12.1.0
- Exclude CHANGELOG.md from the packaged zip
- Add X-ReleaseNotes with the addon summary and repository link

## [1.5.1] - 2026-08-07

### Fixed

- Dragging the panel could persist a floating-point offset such as
  `3.9999999999994` (the scale-conversion math in `SaveOffsetFromAnchor` is
  only exact when the panel and the crafting window share the same effective
  scale), which then showed up verbatim in the options panel's offset fields
  and `/moxie debug`. Offsets are now rounded to the nearest whole pixel when
  a drag ends.

### Changed

- MoxieTracker_UI.lua's panel-height numbers (the placeholder height before
  first draw, the first row's top offset, and the empty/all-hidden state's
  height) are now named constants instead of inline literals, matching the
  convention MoxieTracker_Options.lua already uses for its own layout. No
  behavior change.

## [1.5.0] - 2026-08-06

### Added

- A "Position" section in the options panel with horizontal/vertical offset
  fields and a reset button, so the panel's position no longer requires
  dragging or `/moxie reset`. The two fields commit as a pair and revert to
  the last valid value on bad input.
- A "Color thresholds" section in the options panel exposing the Unalloyed
  Abundance, Moxie, and Fused Vitality green-at cutoffs as editable fields,
  stored in `MoxieTrackerDB.thresholds` with a reset button. Shard of Dundun
  is deliberately not included: its rule is a fixed three-band cutoff tied to
  the currency's actual in-game cap of 8, not a single threshold.
- The row-visibility checkbox list now scrolls, using a native
  `UIPanelScrollFrameTemplate`. The Position and Color thresholds sections
  above it already push the fixed header content close to a screen's worth,
  and the keyword fallback can add rows a fixed layout couldn't guarantee fit.

### Changed

- MoxieTracker.lua split into five files along the config / collect / ui /
  options / commands seam (MoxieTracker_Config.lua, _Collect.lua, _UI.lua,
  _Options.lua, _Commands.lua), sharing state through the addon-private `ns`
  table from #12. No behavior change; done now because the Position and Color
  thresholds sections above already roughly doubled the options panel code.
  `tests/run.lua` now loads whichever files MoxieTracker.toc lists, in order,
  instead of a single hardcoded filename.

### Fixed

- The release archive no longer includes `tests/`. It has shipped there since
  v1.4.0 added the test suite; dev-only tooling has no reason to reach an
  installed copy of the addon. CI now fails if it reappears.
- The options panel's row-visibility list rendered nothing at all -- not even
  the "Nothing to configure yet" message. Two compounding causes, both found
  by dumping frame state in-game rather than guessing from screenshots:
  the options panel is a canvas settings category, and one is not guaranteed
  to be resized to fill the available area (`MoxieTrackerOptionsPanel:GetWidth()`
  read back as 0, so the scroll frame's size -- previously anchored to the
  panel's edges -- resolved to zero on one axis at a time as each was fixed);
  and the scroll child was being manually anchored with `SetPoint` before
  `SetScrollChild`, which fights a ScrollFrame's internal child positioning
  and loses, leaving the child (and every row anchored to it) with no
  resolved screen position at all despite reporting a normal size and a true
  Show/IsVisible state. Fixed by giving the scroll frame an explicit size on
  both axes instead of anchoring it to the panel, giving the scroll child a
  size with no `SetPoint` calls of its own, and calling
  `scrollFrame:UpdateScrollChildRect()` after resizing the child each
  refresh, since a ScrollFrame does not reliably recompute its scroll range
  on its own when that happens.

### Removed

- `release.yml` no longer wires `CF_API_KEY`, `WOWI_API_TOKEN`, or
  `WAGO_API_TOKEN` into the packager. None were set, the TOC never declared
  `## X-Curse-Project-ID` the CurseForge path needs, and GitHub Releases is
  the only channel actually in use. Simpler to drop the dead wiring than
  carry secrets and a TOC field for a release path that doesn't exist yet.

## [1.4.0] - 2026-08-05

### Added

- An addon-private `ns` table (`local ADDON_NAME, ns = ...`) now carries the
  ID/color tables and the `EntryKey`, `GetQuantityColor`, and `CollectTracked`
  functions, instead of them being file-locals. No behavior change; this
  makes the pure collection logic reachable from outside MoxieTracker.lua.
- A headless test suite under `tests/`, run with `lua5.1 tests/run.lua` and
  wired into CI. `tests/stub.lua` fakes the WoW API surface the addon touches
  at load; the tests cover the dedupe/hidden-row precedence invariant in
  `CollectTracked`, `EntryKey`'s persisted-key format, and the color
  thresholds.

## [1.3.0] - 2026-08-05

### Added

- The addon version now prints to chat at login and shows in the options panel
  title. A checkbox in the options panel turns the login message off.
- `/moxietracker` is now recognized alongside `/moxie`. `SlashCmdList`
  registration is last-writer-wins, so a shorter alias can be silently taken
  over by another addon; the full-length command is a fallback that survives
  that collision.
- The TOC declares `IconTexture` and `Category` (`Professions`), so the addon
  shows a real icon and groups correctly in the in-game AddOns list.

### Fixed

- `MoxieTrackerDB` is now initialized in an `ADDON_LOADED` handler gated on the
  addon's own name, instead of at file scope before SavedVariables are
  guaranteed to be loaded. Previously a placeholder table created too early
  could be silently discarded when the client installed the real saved data.
- `GET_ITEM_INFO_RECEIVED` now only triggers a redraw when the event's item ID
  is one this addon tracks. It previously rebuilt the whole panel for every
  item entering the client's item cache, which fires continuously while a
  crafting window is open.
- CI now actually runs the `luac5.1 -p` syntax check, a TOC interface-version
  check, and a check that CHANGELOG.md is present in the packaged archive,
  matching what the README and HANDOFF describe.
- HANDOFF.md no longer claims `MoxieTrackerDB` is per-character; it has been
  account-wide since v1.1.0.

## [1.2.0] - 2026-08-02

### Added

- Fused Vitality (item 245345) is now tracked alongside the currencies. It is a
  bag item rather than a currency, so it is read through `C_Item` and refreshed
  on `BAG_UPDATE_DELAYED`; the count covers bags, bank, and reagent bank. Like
  Shard of Dundun it shows even at zero. Its color is green at 20 or more and
  yellow below that.
- An options panel under Options > AddOns > MoxieTracker, also reachable with
  `/moxie options`, with a checkbox per tracked row. Unchecking a row hides it
  from the panel. The choice is stored account-wide in `MoxieTrackerDB.hidden`
  and keyed by currency or item ID, so it survives a locale change.
- `/moxie showall` clears every hidden row at once.

### Changed

- `/moxie debug` also reports tracked items and the currently hidden rows.
- With every row hidden the panel says so rather than showing "No tracked
  currencies", which was indistinguishable from the addon having broken.

## [1.1.1] - 2026-08-01

Packaging and tooling only — no functional changes.

### Changed

- Releases are now built by [BigWigsMods/packager](https://github.com/BigWigsMods/packager) instead of a hand-rolled zip step. The previous workflow copied a hardcoded list of files, so any file added to the addon would have been silently left out of the release until someone remembered to update the list in two places.
- The version in the TOC now comes from the release tag rather than being maintained by hand, so it can no longer disagree with the release it was published under. Versions now carry a leading `v`.
- CI now builds the real release zip on every push and checks its layout, so packaging breakage surfaces before a tag rather than after.

## [1.1.0] - 2026-08-01

### Added

- Artisan Moxie is now matched by currency ID for all eleven professions
  (3256-3266) rather than by name, so it resolves on any client locale.
- `/moxie debug` lists every tracked currency ID with its quantity before
  walking the currency list, so zero-quantity and undiscovered currencies
  appear.
- luacheck linting in CI, with a deliberately narrow `read_globals` list so a
  typo'd API name fails the build.

### Changed

- The panel position is stored account-wide (`## SavedVariables`) instead of
  per character. One placement now applies everywhere.
- The panel adopts the crafting frame's strata and sits ten levels above it.
  At `UIParent`'s default `MEDIUM` strata it drew beneath the crafting window
  and the addon panes docked to it.
- Panel width is measured from the widest rendered row, floored at 240, so long
  names such as "Artisan Leatherworker's Moxie" are no longer clipped.
- Moxie rows appear only for professions the character actually has. Shard of
  Dundun and Unalloyed Abundance still show at zero.

### Removed

- Currency descriptions are no longer matched. Descriptions cross-reference
  each other, so matching them pulled in unrelated currencies.

### Migration

- Requires a full client restart, not a UI reload, because the TOC changed.
- Changing the saved-variable scope orphans the previous per-character files
  under `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/`. The client
  ignores them and they can be deleted. Every character starts from the default
  position until the panel is moved again.

## [1.0.0] - 2026-08-01

First release that loads. The initial scaffold was tagged v1.0.0 but aborted
during load; that tag was removed and reused for this release.

### Fixed

- `SetBackdrop` was called on a plain frame, which has had no such method since
  patch 9.0. The resulting error aborted the rest of the file before any events
  were registered, so the addon never appeared. The panel now uses
  `BackdropTemplate`.
- Currency rows were `FontString`s with `OnEnter`/`OnLeave` handlers, which
  regions do not support. Each row is now a `Frame` wrapping a `FontString`.
- Hover tooltips passed a nil currency ID. `GetCurrencyListInfo` does not return
  one; it is now resolved through `GetCurrencyListLink`.
- `## Interface` was 110000 against a 120007 client, flagging the addon as out
  of date.
- The `WHITE8X8` texture path lost its backslashes to unescaped sequences.
- Optional events are registered defensively, since registering an event the
  client does not know raises an error and would abort the file a second time.
- Release archives contained loose files at the archive root. WoW requires the
  addon to sit in a folder matching the TOC name, so the published archive
  could not be installed.
- The CI "Check Lua syntax" step only grepped for `CreateFrame`, which is why a
  file that aborted on load passed. It now runs `luac5.1 -p`.

### Added

- The panel shows with the crafting window and hides when it closes, driven by
  both `TRADE_SKILL_SHOW`/`CLOSE` and `OnShow`/`OnHide` hooks on
  `ProfessionsFrame`.
- The panel anchors off the crafting window's top-right corner and tracks it.
  Dragging persists an offset normalized through both frames' effective scales.
- Shard of Dundun (3376) and Unalloyed Abundance (3377) are tracked by explicit
  ID so they display even at zero.
- Per-currency quantity colors: Shard of Dundun green at 6 and red at 7-8,
  Unalloyed Abundance green at 800 or more, Moxie green at 600 or more, yellow
  otherwise.
- `/moxie`, `/moxie pin`, `/moxie debug`, and `/moxie reset`.
- The full GPL-3.0 text, replacing a truncated stub that named the license but
  omitted its terms.

[1.9.2]: https://github.com/Tharavol/MoxieTracker/compare/v1.9.1...v1.9.2
[1.9.1]: https://github.com/Tharavol/MoxieTracker/compare/v1.9.0...v1.9.1
[1.9.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.5.2...v1.6.0
[1.5.1]: https://github.com/Tharavol/MoxieTracker/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/Tharavol/MoxieTracker/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Tharavol/MoxieTracker/releases/tag/v1.0.0
