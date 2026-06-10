# Font System — Spleen

Three-size Spleen font family (BSD-2-Clause) replacing Cozette.

## Registered fonts

| Atom | File | Source BDF | Size | advance_y | Chars/line | Best for |
|------|------|-----------|------|-----------|-----------|----------|
| `:small` | `spleen_6x12.uff` | `spleen-6x12.bdf` | 6×12 | 12 | 21 | Dense body text, system stats |
| `:medium` | `spleen_8x16.uff` | `spleen-8x16.bdf` | 8×16 | 16 | 16 | Labels, screen titles, status lines |
| `:large` | `spleen_12x24.uff` | `spleen-12x24.bdf` | 12×24 | 24 | 10 | Hero values (temperature, numbers) |

All variants include ASCII (U+0020–007E) + degree sign (U+00B0, for temperature display).

## Where each size is used

| Screen | `:small` | `:medium` | `:large` |
|--------|----------|-----------|---------|
| Splash | WiFi/weather status | App title | — |
| System Stats | all rows | — | — |
| Weather | location counter | condition label, location name | temperature, humidity |

## Regenerating

Download BDFs from https://github.com/fcambus/spleen, then:

```bash
python3 tools/gen_font.py spleen-6x12.bdf  0 assets/fonts/spleen_6x12.uff
python3 tools/gen_font.py spleen-8x16.bdf  0 assets/fonts/spleen_8x16.uff
python3 tools/gen_font.py spleen-12x24.bdf 0 assets/fonts/spleen_12x24.uff numeric
```

The `size_px` argument (second positional) is ignored for BDF inputs — the embedded bitmap strike is used directly.

The optional `numeric` mode (fourth argument) restricts the charset to `CHARS_NUMERIC`: space, `%`, `-`, `0–9`, `C`, `F`, `°`. This is used for `:large` because it only renders temperature and humidity values. It shrinks the 12×24 font from ~15.6 KB to ~2.7 KB, recovering ~13 KB of ESP32 heap.

## Adding a new size

1. Download the desired `spleen-NxM.bdf` from the Spleen repo
2. Run `gen_font.py` as above, naming the output `assets/fonts/spleen_<name>.uff`
3. Add an entry to the `@aliases` map in `lib/oled_display/fonts.ex`
4. Use the new atom in any screen's display list

## Font metrics (from gen_font.py output)

```
spleen_6x12.uff:  ascender=9  descender=3  advance_y=12
spleen_8x16.uff:  ascender=12 descender=4  advance_y=16
spleen_12x24.uff: ascender=19 descender=5  advance_y=24
```

## Character sets

**`CHARS_FULL`** (used by `:small` and `:medium`):
- ASCII printable: U+0020–007E (95 glyphs)
- Degree sign: U+00B0 (1 glyph)
- Total: 96 glyphs, 2 intervals

**`CHARS_NUMERIC`** (used by `:large` — `numeric` mode):
- space (U+0020), `%` (U+0025), `-` (U+002D), `0–9` (U+0030–0039), `C` (U+0043), `F` (U+0046), `°` (U+00B0)
- Total: 16 glyphs, 7 intervals

To expand coverage (e.g. full Latin-1), add codepoints to `CHARS_FULL` in `gen_font.py` and regenerate.
