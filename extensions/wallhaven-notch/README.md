# Wallhaven Notch

Browse Wallhaven from a tab in the Notch and set a wallpaper in one click.

- **Browse and search:** a vertically scrolling grid with sorting (toplist, latest, hot, random, ...), paging, and a
  minimum-resolution filter.
- **Content level (needs your Wallhaven API key):** a menu appears only when an API key is set in Vehla's Store
  settings. It is a single choice of tier: **Regular**, **Sketchy** (Regular plus sketchy) or **NSFW** (everything).
  Regular is the default and is remembered. Without a key it is always Regular, enforced where the request is built.
- **Large preview:** open an image and press **Space** (or the expand button) for a large preview outside the Notch,
  Quick Look style. It shows the thumbnail at once, then swaps in the full-size image. Space or Esc closes it; the
  left and right arrow keys move to the neighbouring wallpaper.
- **Remembers where you left off:** closing the Notch and reopening it brings you back to the same search, sorting,
  page, and the image you had open; going back to the grid scrolls to it.
- **Favorites:** heart any wallpaper; view them with the heart in the bar.
- **Set as Wallpaper:** downloads the full image and applies it to every screen, with a live activity in the closed
  Notch.

Your API key is sent only to `wallhaven.cc` as the `X-API-Key` header. Favorites, preferences and where you left off
are stored in the extension's data folder.
