# fonts

Fraunces (titles, headings) and Inter (everything else), both SIL Open Font License 1.1 (`OFL.txt`, no reserved font names).

Sources, google/fonts `main` as of 2026-11-19:

- https://github.com/google/fonts/tree/main/ofl/fraunces — `Fraunces[SOFT,WONK,opsz,wght].ttf`, `OFL.txt`
- https://github.com/google/fonts/tree/main/ofl/inter — `Inter[opsz,wght].ttf`, `OFL.txt`

google/fonts only ships variable files. KOReader's freetype renders a variable font at its default instance, and Fraunces' default is wght 900 (black), so these are static instances made with fonttools `varLib.instancer`:

- Fraunces Regular/Medium/SemiBold: wght 400/500/600, opsz 28, SOFT 0, WONK 0 (`scripts/fraunces-statics.py <variable ttf>`, writes `out/`)
- Inter Regular/Medium/SemiBold: `fonttools varLib.instancer --update-name-table Inter[opsz,wght].ttf wght=400|500|600 opsz=14`

Copy the `.ttf` files into `koreader/fonts/bookbindery/` (any folder under `koreader/fonts/` works). Without them the plugin falls back to KOReader's Noto fonts.
