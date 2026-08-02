# Changelog

All notable changes to MoxieTracker are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.1.0]: https://github.com/Tharavol/MoxieTracker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Tharavol/MoxieTracker/releases/tag/v1.0.0
