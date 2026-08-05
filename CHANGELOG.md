# Changelog

All notable changes to MoxieTracker are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[1.4.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/Tharavol/MoxieTracker/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Tharavol/MoxieTracker/releases/tag/v1.0.0
