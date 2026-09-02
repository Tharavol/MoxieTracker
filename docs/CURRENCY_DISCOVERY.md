# Concentration tracker window + independent window positions (#40)

Implements issue #40: a third tracker window showing every character's
current Crafter's Concentration with a projected time to reach the cap, plus
independently positionable/movable windows now that there are three of them
instead of two, plus per-character/per-profession muting for both rosters.

## What the issue asks for

Two related pieces: (1) a Concentration roster window mirroring the
Knowledge Points window's "own window, one row per character, indented
per-profession breakdown, accumulates as alts log in" shape, with a
projected time-to-cap per profession; (2) since that makes three tracker
windows, each one (main Moxie panel, Knowledge Points, Concentration) needs
its own independently stored, independently draggable position instead of
Knowledge Points riding along beneath the main window the way it did before
this. During planning the user also asked for per-character *and*
per-profession muting for Concentration, in its own settings area, and for
the existing Knowledge Points mute list to become the same nested
character->profession shape.

## What's confirmed about the data source

Unlike Moxie and Knowledge Points, Concentration has **no static currency ID
to hardcode**. It is resolved live, per profession, via
`C_TradeSkillUI.GetConcentrationCurrencyID(skillLineID)`, where `skillLineID`
comes from `C_TradeSkillUI.GetProfessionChildSkillLineID()` while that
profession's crafting window is open. This was confirmed by reading
derfloh205/CraftSim's `Modules/ConcentrationTracker/ConcentrationTracker.lua`
and `Classes/ConcentrationData.lua` (MIT licensed) -- CraftSim already ships
a working Concentration tracker, and its own constants file
(`Util/Const.lua`) has a hardcoded ID table for Moxie but nothing equivalent
for Concentration, confirming the dynamic-lookup requirement rather than
just a gap in this addon's own research.

Also confirmed there:

- Only the 8 crafting professions have Concentration. Gathering professions
  (Herbalism, Mining, Skinning, Fishing) do not -- CraftSim explicitly
  excludes them (`CraftSim.CONST.GATHERING_PROFESSIONS`).
- `C_CurrencyInfo.GetCurrencyInfo(currencyID)` -- the exact same call
  MOXIE_IDS/KNOWLEDGE_PROFESSIONS already use -- returns `.maxQuantity` and
  `.rechargingCycleDurationMS` directly. Confirmed against Blizzard's own
  `TradeSkillUITypesDocumentation.lua` (`Gethe/wow-ui-source`) too, which is
  also where `ProfessionInfo.professionName` (localized) vs. `.profession`
  (the locale-independent `Enum.Profession` value) was confirmed --
  `ns.CONCENTRATION_PROFESSIONS` in the Config file keys off `.profession`
  for exactly this reason, matching this addon's existing "matched by ID,
  not name, so it works on any locale" principle.
- The projection formula (linear regen from a snapshot, capped at max) is
  CraftSim's `ConcentrationData:GetCurrentAmount()`/`:GetTimeUntil()`. No
  CraftSim code was copied -- MoxieTracker's `ns.ProjectConcentration` etc.
  (`MoxieTracker_Collect.lua`) are independent implementations arrived at
  because CraftSim's source revealed which API calls/fields exist, not by
  translating its implementation. See the credited comments at
  `ns.DiscoverConcentrationCurrencyID`/`ns.ProjectConcentration` in that
  file.

## Design decisions

- **Currency ID discovery**: cached account-wide the first time each
  profession's crafting window opens (`TRADE_SKILL_SHOW`), not rediscovered
  every login. A freshly installed copy shows no Concentration row for a
  profession until that profession's window has been opened once -- the
  same "rows only appear for what the character has actually shown you"
  rule Moxie already follows.
- **Window positions** (`MoxieTracker_Config.lua`'s `ns.GetOffset`/
  `ns.SetOffset`/`ns.ClearOffset`, `MoxieTracker_UI.lua`'s
  `ApplyWindowAnchor`): per-window now, stored under
  `MoxieTrackerDB.windows.<main|knowledge|concentration>`. Main keeps a
  numeric default (unchanged placement); Knowledge and Concentration have no
  numeric default -- until dragged, they stay anchored beneath the window
  above them via a live SetPoint, so nothing visually jumps for existing
  users on upgrade. A one-time migration
  (`ns.MigrateWindowOffset`) moves the old single `offsetX`/`offsetY` into
  `windows.main`.
- **Muting** (`ns.IsRosterEntryMuted`/`ns.SetRosterEntryMuted`): two
  independent rosters, `mutedKnowledge` and `mutedConcentration`, each
  supporting a whole-character mute (the `"*"` sentinel) or a per-profession
  mute. A one-time migration (`ns.MigrateMutedCharacters`) moves the old
  whole-character-only `mutedCharacters` (Knowledge-only) into
  `mutedKnowledge`'s `"*"` entries.
- **Coloring**: Concentration gets its own threshold *per profession*
  (unlike Moxie's single shared threshold across all eleven), stored as flat
  `"concentration:<Profession>"` keys in the existing
  `MoxieTrackerDB.thresholds` table so the existing "Reset thresholds"
  button covers them for free. Every profession defaults to 300. On top of
  the threshold, quantity at or above the real cap (`maxQuantity` read live,
  never hardcoded to 1000) always renders red, mirroring Shard of Dundun's
  fixed-cap rule.

## Sources

- [derfloh205/CraftSim](https://github.com/derfloh205/CraftSim) (MIT
  licensed) -- specifically `Modules/ConcentrationTracker/ConcentrationTracker.lua`
  and `Classes/ConcentrationData.lua`, for the Concentration currency
  discovery mechanism and the regen-projection formula. Pointed at by the
  user during planning.
- [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) --
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua`,
  for the `ProfessionInfo` struct's `.profession`/`.professionName` fields.
