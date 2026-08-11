# Knowledge points tracking (#38)

Plan for "Track unused knowledge points for all characters and make that
visible in the tracker window beneath the existing currencies. The names
should be visible in green and you can just accumulate that as users log in."

## What the issue asks for

Three distinct pieces: (1) read a character's *unspent* profession
knowledge, (2) persist it **per character**, and (3) render a roster
section -- not just the current character's numbers, which is what
everything else in the addon does today.

## What's confirmed about the data source

Per a Blizzard forum thread on this exact question, profession Knowledge
Points are exposed the same way Moxie already is: as ordinary currencies via
`C_CurrencyInfo.GetCurrencyInfo(currencyID)` -- no separate `C_ProfSpecs`
unspent-points getter exists. That's good news: it's the exact same API
shape `MOXIE_IDS` already uses, not a new integration pattern.

What could **not** be pinned down from outside the client: the actual
currency ID(s). Knowledge currencies appear to be per-profession (e.g.
"Weekly Mining Knowledge" is currency 3065), and there may be multiple
knowledge currencies per profession (base + weekly + catch-up, per how the
established addon "Myu's Knowledge Points Tracker" categorizes them) rather
than one. **This has to be confirmed in-game** -- first real task, not a
guess to bake into the implementation.

## The real design question: multi-character storage

Everything else in MoxieTracker reads live, current-character state on
demand (`CollectTracked()`). Knowledge points need a **roster that outlives
the current login** -- character A's numbers have to still be visible while
you're playing character B. Two things make this easier than it sounds:

- `MoxieTrackerDB` is already account-wide (`## SavedVariables:
  MoxieTrackerDB`, no `PerCharacter` variant), so no SavedVariables
  restructuring is needed to share data across characters.
- `PLAYER_ENTERING_WORLD` and `ADDON_LOADED` are already registered and
  handled in `MoxieTracker_UI.lua`, so there's an existing hook to snapshot
  into.

## Proposed plan

1. **Confirm the currency ID(s) in-game.** Log a character into their
   profession window, `/dump C_CurrencyInfo.GetCurrencyInfo(<id>)` against
   candidate IDs (or read them off the currency tab), and determine: one ID
   per profession, or a shared "unspent" total? This determines everything
   below, so it's a blocking first step, not parallelizable with the rest.

2. **Data model** -- add `MoxieTrackerDB.knowledge`, keyed by
   `"CharacterName-RealmName"` (matching the pattern `UnitName("player")`
   plus realm gives you), storing `{ points = <n>, lastSeen = <timestamp or
   version> }` per character. Keep it a flat table, not nested
   per-profession, unless step 1 shows the points genuinely don't sum
   meaningfully across professions.

3. **Collection** -- on `PLAYER_ENTERING_WORLD` (already handled), read the
   current character's unspent knowledge and write it into the roster
   table. This is the "accumulate as users log in" the issue describes: no
   rescan needed for other characters, the roster just grows/updates one
   entry at a time as each alt logs in.

4. **Rendering** -- extend `MoxieTracker_UI.lua`'s `UpdateDisplay()` to
   append a second section below the existing currency rows: a header
   ("Knowledge Points" or similar), then one line per roster entry,
   character name in green (`ns.GREEN`, already defined), count in the
   existing white/threshold-colored style. Current character's own row
   should probably reflect live data, not the last-snapshot value, to avoid
   it looking stale while you're looking right at it.

5. **Options panel** -- decide whether this needs a toggle at all (the issue
   doesn't ask for one) versus always showing when the roster is non-empty,
   mirroring how `ALWAYS_SHOWN_IDS` rows behave today. Probably start with
   no toggle, matching the issue's minimal scope, and let a follow-up issue
   add hide/show if wanted.

6. **Edge cases worth deciding before writing code:**
   - Does a deleted/renamed/faction-changed character's stale entry ever get
     pruned, or does the roster grow forever? (MoxieTracker already has a
     precedent for user-driven cleanup -- the hidden-rows list -- so
     "manual remove via right-click or a reset-adjacent command" is
     consistent with the addon's existing philosophy.)
   - Multiple characters on the account but different servers -- realm-
     qualify the key (per above) so two characters named the same on
     different realms don't collide.
   - Should the roster section respect the panel's existing
     width-driven-by-widest-row layout, or does a long character-realm name
     blow that out? Worth a quick look at `UpdateDisplay`'s width math
     (`EnsureLine`/`widest` in `MoxieTracker_UI.lua`) since it's currently
     sized only for currency-row text.

7. **Tests** -- `tests/run.lua`'s stub already fakes `C_CurrencyInfo`,
   extending it to also fake whichever knowledge currency ID(s) step 1
   identifies gets you coverage for the collection logic the same way
   `CollectTracked` is tested today. The roster-storage logic (character
   keying, no pruning vs. manual removal) is pure-data and easy to unit
   test in isolation, same style as the existing dedupe/threshold tests.

## Suggested order

Step 1 (confirm the API) blocks everything else and should happen before
any code is written -- treat it as its own quick spike, in-game, before
anything else here is scheduled. Once that's back, steps 2-4 are a single
focused PR (data model + collection + rendering), and 5-7 (options
integration, edge-case handling, tests) are natural follow-up polish,
similar in spirit to how MoxieTracker's own milestones have sequenced "make
it work" before "make it configurable."

## Sources

- [API for profession knowledge points - UI and Macro - World of Warcraft Forums](https://us.forums.blizzard.com/en/wow/t/api-for-profession-knowledge-points/2011267)
- [Myu's Knowledge Points Tracker - World of Warcraft Addons - CurseForge](https://www.curseforge.com/wow/addons/myus-knowledge-points-tracker)
- [11.0 Professions - Tracker - Weekly Mining Knowledge - Currency - World of Warcraft](https://www.wowhead.com/currency=3065/11-0-professions-tracker-weekly-mining-knowledge)
