# Demo app icon

A reusable, generic icon for short SwiftUI sample apps. Circular-first so one set of layers survives the iOS/iPadOS/macOS squircle and the watchOS/visionOS circle. No product name, no wordmark, no thin strokes.

Metaphor: **run this sample**. A glass disc, a separated orbit ring, and a rounded play glyph.

```
demo-app-icon/
├── 0_base-disc.svg                 Icon Composer layer (back)
├── 1_orbit-ring.svg                Icon Composer layer (middle)
├── 2_play-glyph.svg                Icon Composer layer (front)
├── demo-icon-marketing-1024.svg    Flattened 1024×1024 composite (App Store / README / social)
└── demo-icon-marketing-1024.png    Raster preview of the composite
```

## What you drop into Icon Composer

Use only the three numbered SVGs. Do **not** import the marketing file.

| File | Role | Shape | Fill |
|---|---|---|---|
| `0_base-disc.svg` | Back glass plate | Circle, r = 328 on a 1024 canvas | `#EEF0FF` |
| `1_orbit-ring.svg` | Mid glass rim | Annulus, outer r = 412, inner r = 356 | `#FFFFFF` |
| `2_play-glyph.svg` | Foreground mark | Rounded play chevron, optically centered | `#FFFFFF` |

Each file is:

- 1024 × 1024 viewBox, 1:1
- Transparent canvas (no plate, no squircle, no circle mask)
- Flat filled vectors only — no blur, shadow, specular, opacity tricks, or filters
- Positioned on the same coordinate system so they land already aligned

The 16 px air gap between the disc (r 328) and the ring hole (r 356) is deliberate. Liquid Glass refraction needs a little space between layers or the stack reads as one lump.

## Icon Composer setup

Apple’s current workflow (Xcode / Icon Composer): layers come from your design tool; **background color, Liquid Glass, dark/mono annotations, and platform previews stay in Icon Composer**.

1. New icon document, 1024 canvas (iPhone / iPad / Mac master). Watch uses 1088 with the same grid; this artwork is centered and circular, so it translates without a second drawing.
2. Drag the three SVGs in. Icon Composer sorts alphabetically — the `0_`, `1_`, `2_` prefixes keep back-to-front order.
3. Put each SVG in its **own group** (up to four groups). Glass properties apply per group, which is what you want if you are turning glass on for every layer.
4. Set the document **background** in Icon Composer, not in the SVGs. Suggested default:
   - Default / light: `#5B3DF5` (or a gradient from `#2B1C8F` → `#8B7CFF`)
   - Dark: `#1E1B4B` or a deeper indigo
   - Mono / clear / tinted: leave the white artwork and let the system tint; check contrast on a few wallpapers
5. Enable Liquid Glass on each group. Starting points that usually look right on this mark:
   - Specular: Automatic (or Outside on the ring, Inside on the disc)
   - Refraction: low on the disc, a touch higher on the ring so the gap picks up the background
   - Translucency: keep the play glyph more opaque than the disc
   - Shadow: Neutral for dark/mono; Chromatic can look good on the default purple
6. Preview Default, Dark, Mono, plus the circular watch/vision mask. The ring sits inside r ≈ 412, so the circle crop does not clip artwork. If anything feels tight on Watch’s 1088 canvas, scale the three layers up ~6 % as a group rather than redrawing.
7. Save the `.icon` bundle into the Xcode project. Use **File → Export** only when you need another flattened PNG; the marketing SVG in this folder already covers App Store / GitHub images.

Do not pre-mask the layers to a rounded rectangle or a circle. The system applies the platform mask so specular highlights follow the real edge.

## Marketing composite

`demo-icon-marketing-1024.svg` is the three layers plus a rounded-rect plate and a simple indigo–violet wash. Use it for:

- App Store promotional images
- GitHub social preview / README hero
- A stand-in until Icon Composer’s own flattened export exists

It is **not** an Icon Composer layer. It includes a clip-path plate (`rx = 228`) that only approximates the system squircle. Shipping icons should always be the `.icon` file, not this SVG.

## Why this drawing

Apple’s current HIG (Liquid Glass era) rewards:

- One idea, few shapes, filled — not outlined
- Artwork centered on the shared 1024 grid so squircle and circle masks both work
- Edges thick enough that specular highlights have something to catch
- No text (no localization, no accessibility, unreadable at Settings size)
- No baked shadows, blurs, or glass — those now belong to the system
- A background you define in Icon Composer so Dark / Clear / Tinted can change it without re-exporting artwork

A play glyph is the most honest generic “demo” signal: this sample runs. The surrounding ring keeps it from looking like a video-hosting brand, and the separated disc gives you a third glass surface. Recolor the Icon Composer background per repo if you want each sample to feel distinct without drawing a new mark.

## Geometry (1024 canvas, origin top-left)

| Element | Center | Radius / box |
|---|---|---|
| Canvas | — | 1024 × 1024 |
| Base disc | (512, 512) | r = 328 |
| Ring outer | (512, 512) | r = 412 |
| Ring inner | (512, 512) | r = 356 |
| Play | optical center ≈ (504, 512) | height 312, corner r = 30 |

Safe relative to the templates you pasted:

- iOS / iPadOS / macOS squircle — ring well inside the rounded corners
- watchOS / visionOS circle — ring diameter 824 on a 1024 inscribed circle
- tvOS 800 × 480 is a different canvas; if you ever need it, place the same three shapes on a landscape artboard and keep a generous focus safe zone. This pack is 1:1 as requested.

## Recoloring a single sample

Keep the three white-ish SVGs. Change only the Icon Composer background (and, if you want, the layer fills in the inspector). The marketing SVG hard-codes the purple wash; duplicate it and edit the `bg` gradient stops if a particular repo needs a matching hero image.

Suggested backgrounds that still contrast the pale artwork:

- Indigo `#5B3DF5` (default in the composite)
- Teal `#0F766E`
- Slate `#334155`
- Coral `#E11D48` (check Dark + Tinted)

Avoid near-white backgrounds — the glyph disappears — and avoid pure black on watchOS, which Apple calls out as blending into the display.

## License

Artwork is original and intended for your open-source SwiftUI demos. Use, copy, and modify freely.
