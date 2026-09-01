# Ordo — LinkedIn brand assets

Built from the Ordo mark (`priv/static/favicon.svg`): the "O" ring in ink
`#16233B` with the gold accent dot `#FFC53D`, on paper `#F4F6F8`.

| File | Size | Use on LinkedIn |
|------|------|-----------------|
| `logo-light.png` | 400×400 | **Company logo** (default) — dark mark on light. Best on LinkedIn's white UI. |
| `logo-dark.png`  | 400×400 | Company logo, inverted — light mark on ink. Use if you want a dark tile. |
| `banner.png`     | 1128×191 | **Company page cover / banner.** |

LinkedIn requires PNG/JPG (not SVG); the `.svg` files are the editable sources.
Company logo min is 300×300 — 400×400 is safe. Personal-profile picture uses the
same square logo.

## Regenerate (needs ImageMagick + macOS SF Mono)

```sh
magick -background none logo-light.svg -resize 400x400 logo-light.png
magick -background none logo-dark.svg  -resize 400x400 logo-dark.png

magick -background none icon-mark.svg icon-mark.png
magick -size 1128x191 xc:'#16233B' \
  icon-mark.png -gravity West -geometry +64+0 -composite \
  -font /System/Library/Fonts/SFNSMono.ttf -fill '#F4F6F8' -kerning 8 -pointsize 66 \
    -gravity West -annotate +236-14 'ORDO' \
  -font /System/Library/Fonts/SFNSMono.ttf -fill '#8EA0BD' -kerning 5 -pointsize 19 \
    -gravity West -annotate +240+30 'AI SUPPORT FOR E-COMMERCE' \
  banner.png && rm icon-mark.png
```
