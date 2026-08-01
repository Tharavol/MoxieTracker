# MoxieTracker

MoxieTracker is a World of Warcraft addon for Retail / Midnight that displays the current character's Artisan Moxie and Shards of Dun'Dun currency values in a small movable window anchored to the bottom-left of the screen.

## Features

- Shows any tracked Artisan Moxie and Dun'Dun-related currency values that are above zero
- Places a compact, draggable panel outside the crafting frame
- Displays the same tooltip information as the default currency UI when hovering over a line

## Installation

1. Copy the MoxieTracker folder into your World of Warcraft AddOns directory.
2. Launch World of Warcraft.
3. Reload the UI or restart the game.

## Development and CI

- GitHub Actions runs a lightweight validation workflow on pushes and pull requests.
- A release artifact is packaged automatically on pushes to main or master.
- Tagging a release with a version like v1.0.0 creates a GitHub Release with the packaged addon zip.

## Credits

- Created by Tharavol
- Assisted by GitHub Copilot

## License

This project is licensed under the GNU General Public License v3.0.
