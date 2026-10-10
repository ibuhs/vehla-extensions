# Cover Art Search

Cover Art Search is a compact Vehla command palette extension for finding
official poster art for movies, TV shows, anime, and games.

Type **cover art** in Vehla's Command Palette, enter a title, and choose a
result to:

- Copy the poster image to the clipboard.
- Copy the direct image URL.
- Open the title's IMDb page.

Results use IMDb's suggestion endpoint and poster URLs. No API key or account
is required. Individual TV episodes are omitted because they are not title
cover art.

## Build and install

```sh
swift test
./build.sh
```

Install the generated `dist/CoverArtSearch` folder from Vehla's **Install Local
Package** workflow.
