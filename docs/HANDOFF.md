# Handoff Notes

## Project summary

MoxieTracker is a World of Warcraft addon for Retail / Midnight that displays current-character Artisan Moxie and Dun'Dun shard currency values in a movable panel anchored to the bottom-left of the screen.

## Current state

- Addon files: MoxieTracker.toc, MoxieTracker.lua
- Repository root: this folder
- License: GPL-3.0

## Development notes

- The panel is created with a standard WoW frame and uses the currency tooltip API for hover behavior.
- Currency values are refreshed on relevant currency events such as CURRENCY_DISPLAY_UPDATE and PLAYER_LOGIN.
- The current implementation filters for entries whose names or descriptions indicate Artisan Moxie or Dun'Dun-related currencies and displays only values above zero.

## Next steps

- Test in-game on Retail / Midnight and adjust the layout if needed.
- Add optional configuration for position, size, or color if desired.
- Push the repository to GitHub and continue development from another machine.

## Local setup checklist

1. Install Git if needed.
2. Clone the repo from GitHub on the target machine.
3. Copy the addon folder into the WoW AddOns directory.
4. Reload the UI to test.
