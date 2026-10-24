# Sheafnote design

Warm paper and ink, bright and playful. Native iOS controls throughout; this file only sets what makes them look like Sheafnote. Follows GoodNotes 6 for layout and workflow, never for visuals.

## Color

| Token | Light | Dark | Use |
|---|---|---|---|
| paper | #FBF6EC | #1E1A16 | library and editor backgrounds (warm cream; "paper at night" in dark) |
| paperRaised | #FFFDF8 | #2A251F | cards, sheets, tiles |
| ink | #2B2420 | #F3ECE0 | primary text, default pen color |
| inkMuted | #7A6E64 | #A89C90 | secondary text, dates |
| rule | #E8DFD0 | #3A332B | dividers, tile outlines |
| accent (tangerine) | #F2542D | #FF7A55 | tint, selected tool, primary buttons |

Playful set (covers, default pen/highlighter presets, folder colors, stickers): sunflower #FFC93C, mint #3CC9A0, sky #3D9BFF, lilac #A77BFF, bubblegum #FF6FA8, tangerine #F2542D. Highlighter presets use the same hues at 35% opacity.

## Type

- Titles and section headers: SF Pro Rounded (`.fontDesign(.rounded)`), semibold.
- Notebook titles on covers and in the editor bar: New York (`.fontDesign(.serif)`), so notebooks feel like books.
- Body, menus, settings: system default. Dynamic Type everywhere.

## Shape and surface

- Continuous corners: tiles and cards 14pt, buttons and chips 10pt, covers 6pt with a rounded spine edge.
- Covers: flat color or simple pattern from the playful set, a darker spine stripe on the left, a cream label plate holding the serif title. Subtle paper grain overlay (very low opacity noise).
- Folders: paper folder with a tab, tinted from the playful set.
- Shadows: soft and warm (ink color at 8-12% opacity), only on covers and floating panels.
- Toolbars: the system Liquid Glass bars, tinted toward paper.

## Playful touches (small, never in the way of writing)

- Selected tool: tinted with the current ink color, a small ink dot under it, and an SF Symbol `.bounce` on selection.
- Covers tilt and lift slightly on press; new notebooks drop into the grid with a short spring.
- Empty states: a short hand-drawn ink doodle (rendered strokes) with one friendly line of copy.
- Haptics on tool switch, page add, and lasso pick-up.
- No animation on the writing surface itself, and none that delays input.

## App icon

A cream folded sheet on a tangerine background with a single ink swoosh across it.
