# bookbindery

A KOReader plugin that gives your e-reader a home screen and a library built from your calibre library, plus a theme for KOReader's own menus and dialogs.

- **home:** a clock, the book you're reading now with the other books you're reading in a row below it, and how many days you read this month. With a `fanfic/` folder, a tile counts its fandoms.
- **shelves:** status tiles (to read, reading, read, did not finish) and a shelf tree. Statuses come from a calibre `#workflow` column when your library has one, otherwise from KOReader's own reading status. The tree comes from a calibre `#type` column (dotted paths such as `fiction.classics`) when present, otherwise from each book's first tag. Hold a shelf to pin it. Below the tree: fanfic, manga, articles and all files.
- **book info and fic info:** hold any book for what calibre and KOReader know: cover, rating, year, pages, shelf, progress, time read and pace, highlights, file details. Fics show their fandom, ships and AO3 rating.
- **mark as:** to read, reading, read or did not finish, saved as KOReader's own reading status.
- **fanfic by folder:** works under `fanfic/<fandom>/`, grouped by fandom.
- **manga:** a screen over rakuyomi's library (library, downloaded, new chapters) that opens chapters in rakuyomi.
- **articles:** the wallabag plugin's downloads.
- **updates:** new manga chapters and unread articles, with check and sync buttons.
- **search:** offline over your library (title, author, series) and fanfic (title, author, fandom, ship), plus handoffs to rakuyomi and KOReader's dictionary.
- **its own menu:** the top-right button or a swipe down opens five tabs (library, sources, reading, device, system) over KOReader's file manager menu. Nothing is lost: entries it doesn't place are under system → more.
- **theme:** a user patch that restyles KOReader's menus, button dialogs, input dialogs and keyboard to match.

## requirements

- KOReader v2026.07.x (bookbindery is built and tested on it).
- A calibre library sent to the device with KOReader's calibre plugin, or any folder with a `.metadata.calibre` file at its root, which is the file calibre writes when it sends books to a device.
- Optional calibre columns: `#workflow` (statuses), `#type` (the shelf tree) and `#pages` (a number, for page counts).
- Optional: the statistics plugin (on by default) for days read, time read and pace.

## install

1. Copy `bookbindery.koplugin` to `koreader/plugins/`.
2. Copy `patches/2-bookbindery-theme.lua` to `koreader/patches/` (optional, for the theme).
3. Copy `fonts/*.ttf` to `koreader/fonts/bookbindery/`. Without them bookbindery falls back to KOReader's own fonts.
4. Restart KOReader. Open it from the tools menu: "bookbindery home".

## start with

To open bookbindery when KOReader starts: file browser menu → first tab → Start with → bookbindery home. With it set, closing a book brings you back home.

## settings it reads and writes

- `bookbindery_books_root`: the folder with your books and `.metadata.calibre`. Without it, bookbindery uses KOReader's home folder (file browser → set as home folder), else KOReader's default folder. Set it in `settings.reader.lua` to point somewhere else.
- `bookbindery_pinned_shelves`: shelves pinned to the top, written when you hold a shelf. Settings → clear pinned shelves empties it.
- `bookbindery_manga_covers`: off by default; the switch is in system → bookbindery settings. When on, "check all now" on updates fetches missing manga covers from the URLs rakuyomi's sources give, so the requests go to those sources. Covers are cached in `settings/bookbindery/manga-covers/`.
- `bookbindery_menu_tab`: the menu tab you used last.
- `settings/bookbindery/toread.lua`: books you marked "to read" (KOReader has no such status, so bookbindery keeps the list).
- Mark as writes the book's reading status into its KOReader sidecar, creating the sidecar if the book has none.
- `settings/bookbindery/` also holds a cache of the parsed library. It never edits book files.

## optional integrations

- **rakuyomi:** the manga screen reads rakuyomi's database read-only and never starts or changes rakuyomi.
- **wallabag:** articles and updates read the wallabag plugin's download folder; sync calls the plugin's own sync.

Each one is left out quietly when its plugin isn't installed.

## turning the theme off

Use KOReader's patch management (system → patches in bookbindery's menu, or KOReader's own menu), or delete `koreader/patches/2-bookbindery-theme.lua`. Disabling the plugin doesn't turn the theme off. Each part of the theme switches itself off and logs `bookbindery-theme: <part> off: <error>` if it fails.

## tests

`scripts/test.sh` runs luacheck, a LuaJIT compile of every file and the busted specs in a throwaway docker container. The specs use made-up fixtures in `spec/fixtures/`.

## licence

MIT, see `LICENSE`. The fonts (Fraunces and Inter) are under the SIL Open Font License 1.1, see `fonts/OFL.txt` and `fonts/README.md`.
