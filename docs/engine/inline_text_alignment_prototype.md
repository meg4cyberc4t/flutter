# Inline text alignment prototype

This branch adds vertical alignment to wrapping inline text. It requires the
matching custom engine; an ordinary prebuilt Flutter engine does not implement
the new Dart API. The change is experimental and includes known performance
tradeoffs.

## Paired source revisions

- Flutter base: `19946f91c8d9de18a4674460d015229cc0b2534f`.
- Skia base: `430885776aa87d5e9cdfa369ceb4e52e1256fdde`.
- Skia prototype: [`231b9709d39085da76c0a566f609d3362e67ddd2`](https://github.com/meg4cyberc4t/skia/commit/231b9709d39085da76c0a566f609d3362e67ddd2).

`DEPS` fetches this exact commit from the Skia fork. Other Skia-hosted
dependencies retain their original repositories and revisions. The Skia commit
also includes the previously tested bidi placeholder correction, so the pair
reproduces the validated implementation without rolling unrelated Skia sources.

## API

`RichText.alignment`, `RenderParagraph.alignment`, `TextPainter.alignment` and
`dart:ui.ParagraphStyle.alignment` default to `PlaceholderAlignment.baseline`.
`TextSpan.alignment` is nullable: omission inherits the parent span or paragraph
alignment; an explicit `baseline` resets it. `WidgetSpan.alignment` remains
independent.

```dart
RichText(
  textDirection: TextDirection.ltr,
  alignment: PlaceholderAlignment.middle,
  text: TextSpan(
    style: const TextStyle(fontSize: 32, color: Color(0xFF000000)),
    children: <InlineSpan>[
      const TextSpan(text: 'Large '),
      const TextSpan(text: 'small ', style: TextStyle(fontSize: 14)),
      const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox(
          width: 16,
          height: 16,
          child: ColoredBox(color: Color(0xFF0066CC)),
        ),
      ),
      const TextSpan(
        text: ' top',
        alignment: PlaceholderAlignment.top,
        style: TextStyle(fontSize: 14),
      ),
    ],
  ),
)
```

Alignment uses text metrics, including height and leading, rather than painted
ink bounds. It is applied independently on each wrapped line:

| Value | Text placement |
| --- | --- |
| `baseline` | Existing typographic placement |
| `top` | Top of the text metrics at the line top |
| `middle` | Center of the text metrics at the line center |
| `bottom` | Bottom of the text metrics at the line bottom |
| `aboveBaseline` | Bottom of the text metrics at the alphabetic baseline |
| `belowBaseline` | Top of the text metrics at the alphabetic baseline |

Line height and the public paragraph baseline retain the ordinary layout result.
Above/below-baseline text may extend outside its line. On lines using the new
alignment, top/middle/bottom placeholders use the final line bounds, including
large neighboring text and strut; their own alignment value is preserved.

Shaping, bidi reordering, glyph positions in X and line breaking remain in
SkParagraph. Vertical fragments do not split a grapheme or glyph cluster. If a
span boundary falls inside one, the atom uses the first logical character's
alignment. Paint effects, selection geometry and glyph queries receive the
corresponding vertical shift.

## Build and verification

Use the existing [engine setup](contributing/Setting-up-the-Engine-development-environment.md)
and [compilation instructions](contributing/Compiling-the-engine.md) with this
branch and its pinned DEPS, then select your locally built engine with Flutter's
`--local-engine-src-path`, `--local-engine` and `--local-engine-host` flags.
Sync dependencies after selecting the branch; do not rebase onto a different
upstream revision as part of reproducing this prototype.

Native builds require the patched SkParagraph and Dart UI API together. Web also
requires the patched Web SDK and locally built CanvasKit/skwasm artifacts;
stock CDN artifacts do not contain the new bindings. A source checkout alone
does not replace the prebuilt engine downloaded by the Flutter tool.

Feature tests live in:

- `packages/flutter/test/widgets/rich_text_inline_alignment_test.dart`.
- `engine/src/flutter/lib/web_ui/test/ui/paragraph_inline_alignment_test.dart`.
- Skia `modules/skparagraph/tests/SkParagraphTest.cpp`,
  `SkParagraph_InlineAlignment*` (19 named tests).

The implementation was validated on macOS arm64 and Chrome CanvasKit,
skwasm with threads, and skwasm without threads (106 Web tests per configuration).
Additional native/framework text regressions and 312 instrumented SkParagraph
ASan/UBSan inputs passed before packaging; Skia/ICU/HarfBuzz dependencies were
not sanitizer-instrumented. Android/iOS devices and Windows/Linux were not run.

The expanded CPU benchmark compared against the unmodified pinned master over
159 input datasets and 17 operations, with seven process samples per variant.
Results vary: some large mixed-font layouts improved, but baseline spacing-heavy
inputs regressed and alignment-only fragments increased paint/raster costs.
This prototype does not claim zero overhead, GPU speedups or measured mobile/Web
performance. Benchmark artifacts remain in the separate investigation workspace.
