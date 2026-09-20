// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:test/bootstrap/browser.dart';
import 'package:test/test.dart';
import 'package:ui/ui.dart' as ui;

import '../common/test_initialization.dart';

void main() {
  internalBootstrapBrowserTest(() => testMain);
}

Future<void> testMain() async {
  setUpUnitTests(setUpTestViewDimensions: false);
  registerInlineAlignmentMatrixTests();
  registerInlineHitPositionTests();

  ui.Paragraph build(bool center, ui.TextDirection direction) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontFamily: 'FlutterTest',
        fontSize: 16,
        textDirection: direction,
        alignment: center ? ui.PlaceholderAlignment.middle : ui.PlaceholderAlignment.baseline,
      ),
    );
    builder.addText('small ');
    builder.pushStyle(ui.TextStyle(fontSize: 40));
    builder.addText('BIG ');
    builder.pop();
    builder.addPlaceholder(32, 64, ui.PlaceholderAlignment.middle);
    builder.addText(' tail that wraps over several lines');
    return builder.build();
  }

  Future<(int, int)> paintedBounds(ui.Paragraph paragraph, [int offset = 0]) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawParagraph(paragraph, ui.Offset.zero);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(1200, 200);
    final ByteData pixels = (await image.toByteData())!;
    final ui.Rect box = paragraph.getBoxesForRange(offset, offset + 1).single.toRect();
    var top = 200;
    var bottom = -1;
    for (var y = 0; y < 200; y++) {
      for (int x = box.left.ceil(); x < box.right.floor(); x++) {
        if (pixels.getUint8((y * 1200 + x) * 4 + 3) != 0) {
          if (y < top) {
            top = y;
          }
          if (y > bottom) {
            bottom = y;
          }
        }
      }
    }
    expect(bottom, greaterThanOrEqualTo(top));
    image.dispose();
    picture.dispose();
    return (top, bottom);
  }

  test('centering participates in paragraph style equality', () {
    final normal = ui.ParagraphStyle();
    // Verify that explicit baseline alignment is equivalent to omitting it.
    // ignore: avoid_redundant_argument_values
    final explicitDefault = ui.ParagraphStyle(alignment: ui.PlaceholderAlignment.baseline);
    final centered = ui.ParagraphStyle(alignment: ui.PlaceholderAlignment.middle);
    expect(normal, explicitDefault);
    expect(normal.hashCode, explicitDefault.hashCode);
    expect(normal, isNot(centered));
  });

  test('painted glyphs move together with text geometry', () async {
    final ui.Paragraph normal = build(false, ui.TextDirection.ltr)
      ..layout(const ui.ParagraphConstraints(width: 1200));
    final ui.Paragraph centered = build(true, ui.TextDirection.ltr)
      ..layout(const ui.ParagraphConstraints(width: 1200));
    // The larger span moves; the middle placeholder already centers the small
    // default font in the standard layout.
    final (int, int) before = await paintedBounds(normal, 6);
    final (int, int) after = await paintedBounds(centered, 6);
    final double dy =
        centered.getBoxesForRange(6, 7).single.top - normal.getBoxesForRange(6, 7).single.top;
    expect(dy.abs(), greaterThan(1));
    expect(after.$1 - before.$1, closeTo(dy, 1));
    expect(after.$2 - before.$2, closeTo(dy, 1));
    normal.dispose();
    centered.dispose();
  });

  for (final ui.TextDirection direction in ui.TextDirection.values) {
    test('centers text and placeholder; preserves wrapping for $direction', () {
      final ui.Paragraph normal = build(false, direction);
      final ui.Paragraph centered = build(true, direction);
      for (final width in <double>[800, 260, 180, 800]) {
        normal.layout(ui.ParagraphConstraints(width: width));
        centered.layout(ui.ParagraphConstraints(width: width));
        expect(centered.height, normal.height);
        final List<ui.LineMetrics> lines = centered.computeLineMetrics();
        expect(lines.length, normal.computeLineMetrics().length);
        for (
          var offset = 0;
          offset < 'small BIG \uFFFC tail that wraps over several lines'.length;
          offset++
        ) {
          expect(
            centered.getLineBoundary(ui.TextPosition(offset: offset)),
            normal.getLineBoundary(ui.TextPosition(offset: offset)),
          );
        }
        for (final range in <(int, int)>[(0, 5), (6, 9)]) {
          final List<ui.TextBox> a = normal.getBoxesForRange(range.$1, range.$2);
          final List<ui.TextBox> b = centered.getBoxesForRange(range.$1, range.$2);
          expect(a.length, b.length);
          for (var i = 0; i < a.length; i++) {
            expect(b[i].left, a[i].left);
            expect(b[i].right, a[i].right);
          }
        }
        if (width == 800) {
          final double target = centered.getBoxesForPlaceholders().single.toRect().center.dy;
          expect(centered.getBoxesForRange(0, 5).single.toRect().center.dy, closeTo(target, 0.01));
          expect(centered.getBoxesForRange(6, 9).single.toRect().center.dy, closeTo(target, 0.01));
        }
      }
      normal.dispose();
      centered.dispose();
    });
  }
  test('span alignment inherits and resets within one shaped run', () async {
    ui.Paragraph mixed(bool aligned) {
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontFamily: 'FlutterTest',
          fontSize: 20,
          alignment: aligned ? ui.PlaceholderAlignment.middle : ui.PlaceholderAlignment.baseline,
        ),
      );
      builder.pushStyle(
        ui.TextStyle(
          alignment: aligned ? ui.PlaceholderAlignment.top : ui.PlaceholderAlignment.baseline,
        ),
      );
      builder.addText('A');
      builder.pushStyle(ui.TextStyle(color: const ui.Color(0xffff0000)));
      builder.addText('B');
      builder.pop();
      builder.pushStyle(
        ui.TextStyle(
          alignment: aligned ? ui.PlaceholderAlignment.bottom : ui.PlaceholderAlignment.baseline,
        ),
      );
      builder.addText('C');
      builder.pop();
      builder.pop();
      builder.addText('D');
      builder.pushStyle(ui.TextStyle(alignment: ui.PlaceholderAlignment.baseline));
      builder.addText('E');
      builder.pop();
      builder.addPlaceholder(20, 100, ui.PlaceholderAlignment.bottom);
      return builder.build()..layout(const ui.ParagraphConstraints(width: 1200));
    }

    final ui.Paragraph normal = mixed(false);
    final ui.Paragraph aligned = mixed(true);
    ui.Rect box(int offset) => aligned.getBoxesForRange(offset, offset + 1).single.toRect();
    expect(box(0).top, closeTo(0, 0.01));
    expect(box(1).top, closeTo(0, 0.01));
    expect(box(2).bottom, closeTo(aligned.height, 0.01));
    expect(box(3).center.dy, closeTo(aligned.height / 2, 0.01));
    expect(box(4), normal.getBoxesForRange(4, 5).single.toRect());
    expect(aligned.getBoxesForPlaceholders(), normal.getBoxesForPlaceholders());
    for (var offset = 0; offset < 5; offset++) {
      final (int, int) before = await paintedBounds(normal, offset);
      final (int, int) after = await paintedBounds(aligned, offset);
      final double dy = box(offset).top - normal.getBoxesForRange(offset, offset + 1).single.top;
      expect(after.$1 - before.$1, closeTo(dy, 1));
      expect(after.$2 - before.$2, closeTo(dy, 1));
    }
    normal.dispose();
    aligned.dispose();
  });

  test('TextStyle alignment affects equality and explicit baseline differs from inherit', () {
    final inherited = ui.TextStyle();
    final baseline = ui.TextStyle(alignment: ui.PlaceholderAlignment.baseline);
    final top = ui.TextStyle(alignment: ui.PlaceholderAlignment.top);
    expect(inherited, isNot(baseline));
    expect(top, isNot(baseline));
    expect(top, ui.TextStyle(alignment: ui.PlaceholderAlignment.top));
  });

  test('small placeholders use their own alignment against the final line box', () {
    for (final ui.TextDirection direction in ui.TextDirection.values) {
      for (final ui.PlaceholderAlignment alignment in ui.PlaceholderAlignment.values) {
        for (final height in <double>[12, 24, 100]) {
          ui.Paragraph build(bool aligned) {
            final builder = ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: 'FlutterTest',
                fontSize: 16,
                textDirection: direction,
                alignment: aligned
                    ? ui.PlaceholderAlignment.middle
                    : ui.PlaceholderAlignment.baseline,
              ),
            );
            builder.addText('small ');
            builder.pushStyle(ui.TextStyle(fontSize: 64));
            builder.addText('BIG ');
            builder.pop();
            builder.addPlaceholder(
              24,
              height,
              alignment,
              baseline: ui.TextBaseline.alphabetic,
              baselineOffset: 9,
            );
            return builder.build()..layout(const ui.ParagraphConstraints(width: 600));
          }

          final ui.Paragraph normal = build(false);
          final ui.Paragraph aligned = build(true);
          final ui.Rect before = normal.getBoxesForPlaceholders().single.toRect();
          final ui.Rect after = aligned.getBoxesForPlaceholders().single.toRect();
          expect(after.left, before.left);
          expect(after.width, before.width);
          expect(after.height, closeTo(height, 0.01));
          expect(aligned.height, normal.height);
          switch (alignment) {
            case ui.PlaceholderAlignment.top:
              expect(after.top, closeTo(0, 0.01));
            case ui.PlaceholderAlignment.middle:
              expect(after.center.dy, closeTo(aligned.height / 2, 0.01));
              expect(
                after.center.dy,
                closeTo(aligned.getBoxesForRange(6, 9).single.toRect().center.dy, 0.01),
              );
            case ui.PlaceholderAlignment.bottom:
              expect(after.bottom, closeTo(aligned.height, 0.01));
            case ui.PlaceholderAlignment.baseline:
            case ui.PlaceholderAlignment.aboveBaseline:
            case ui.PlaceholderAlignment.belowBaseline:
              expect(after, before);
          }
          normal.dispose();
          aligned.dispose();
        }
      }
    }
  });
}

void registerInlineHitPositionTests() {
  for (final ui.TextDirection direction in ui.TextDirection.values) {
    test('hit position across inline fragments $direction', () {
      ui.Paragraph build(bool aligned) {
        final b = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontFamily: 'FlutterTest',
            fontSize: 20,
            textDirection: direction,
            strutStyle: ui.StrutStyle(
              fontFamily: 'FlutterTest',
              fontSize: 100,
              forceStrutHeight: true,
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          b.pushStyle(
            ui.TextStyle(
              alignment: !aligned
                  ? ui.PlaceholderAlignment.baseline
                  : i.isEven
                  ? ui.PlaceholderAlignment.top
                  : ui.PlaceholderAlignment.bottom,
            ),
          );
          b.addText('abcd'[i]);
          b.pop();
        }
        return b.build()..layout(const ui.ParagraphConstraints(width: 1000));
      }

      final ui.Paragraph reference = build(false);
      final ui.Paragraph aligned = build(true);
      for (var i = 0; i < 4; i++) {
        final ui.TextBox expectedBox = reference.getBoxesForRange(i, i + 1).single;
        final ui.TextBox box = aligned.getBoxesForRange(i, i + 1).single;
        for (final fraction in <double>[.25, .75]) {
          final double x = box.left + (box.right - box.left) * fraction;
          expect(
            aligned.getPositionForOffset(ui.Offset(x, (box.top + box.bottom) / 2)),
            reference.getPositionForOffset(
              ui.Offset(x, (expectedBox.top + expectedBox.bottom) / 2),
            ),
            reason: 'character $i, fraction $fraction',
          );
        }
      }
      aligned.dispose();
      reference.dispose();
    });
  }
}

void _checkInlineEdge(ui.Rect rect, ui.PlaceholderAlignment mode, ui.Paragraph p) {
  switch (mode) {
    case ui.PlaceholderAlignment.top:
      expect(rect.top, closeTo(0, .02));
    case ui.PlaceholderAlignment.middle:
      expect(rect.center.dy, closeTo(p.height / 2, .02));
    case ui.PlaceholderAlignment.bottom:
      expect(rect.bottom, closeTo(p.height, .02));
    case ui.PlaceholderAlignment.aboveBaseline:
      expect(rect.bottom, closeTo(p.alphabeticBaseline, .02));
    case ui.PlaceholderAlignment.belowBaseline:
      expect(rect.top, closeTo(p.alphabeticBaseline, .02));
    case ui.PlaceholderAlignment.baseline:
      break;
  }
}

void registerInlineAlignmentMatrixTests() {
  for (final ui.TextDirection direction in ui.TextDirection.values) {
    for (final ui.PlaceholderAlignment mode in ui.PlaceholderAlignment.values) {
      for (final ui.PlaceholderAlignment widgetMode in ui.PlaceholderAlignment.values) {
        test('matrix text=$mode widget=$widgetMode direction=$direction', () {
          for (final ui.TextBaseline kind in ui.TextBaseline.values) {
            for (final widgetHeight in <double>[0, 12, 100]) {
              ui.Paragraph build(ui.PlaceholderAlignment alignment) {
                final b = ui.ParagraphBuilder(
                  ui.ParagraphStyle(
                    fontFamily: 'FlutterTest',
                    fontSize: 16,
                    alignment: alignment,
                    textDirection: direction,
                  ),
                );
                b.addText('a');
                b.pushStyle(ui.TextStyle(fontSize: 64));
                b.addText('B');
                b.pop();
                b.addPlaceholder(20, widgetHeight, widgetMode, baseline: kind, baselineOffset: 7);
                b.addText('c');
                return b.build()..layout(const ui.ParagraphConstraints(width: 1000));
              }

              final ui.Paragraph baseline = build(ui.PlaceholderAlignment.baseline),
                  p = build(mode);
              expect(p.height, baseline.height);
              for (final offset in <int>[0, 1, 3]) {
                final ui.Rect a = baseline.getBoxesForRange(offset, offset + 1).single.toRect();
                final ui.Rect b = p.getBoxesForRange(offset, offset + 1).single.toRect();
                expect(b.left, a.left);
                expect(b.right, a.right);
                _checkInlineEdge(b, mode, p);
                if (mode == ui.PlaceholderAlignment.baseline) {
                  expect(b, a);
                }
              }
              final ui.Rect before = baseline.getBoxesForPlaceholders().single.toRect();
              final ui.Rect after = p.getBoxesForPlaceholders().single.toRect();
              expect(after.left, before.left);
              expect(after.size, before.size);
              if (mode == ui.PlaceholderAlignment.baseline ||
                  <ui.PlaceholderAlignment>[
                    ui.PlaceholderAlignment.baseline,
                    ui.PlaceholderAlignment.aboveBaseline,
                    ui.PlaceholderAlignment.belowBaseline,
                  ].contains(widgetMode)) {
                expect(after, before);
              } else {
                _checkInlineEdge(after, widgetMode, p);
              }
              p.dispose();
              baseline.dispose();
            }
          }
        });
      }
      test('selection glyph info and relayout mode=$mode direction=$direction', () {
        for (final scenario in <String>['ordinary', 'ellipsis', 'height', 'newlines']) {
          ui.Paragraph build() {
            final b = ui.ParagraphBuilder(
              ui.ParagraphStyle(
                fontFamily: 'FlutterTest',
                fontSize: 20,
                textDirection: direction,
                alignment: mode,
                maxLines: scenario == 'ellipsis' ? 2 : null,
                ellipsis: scenario == 'ellipsis' ? '...' : null,
                strutStyle: scenario == 'height'
                    ? ui.StrutStyle(
                        fontFamily: 'FlutterTest',
                        fontSize: 32,
                        height: 1.4,
                        forceStrutHeight: true,
                      )
                    : null,
                textHeightBehavior: const ui.TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
              ),
            );
            for (var i = 0; i < 12; i++) {
              b.pushStyle(
                ui.TextStyle(
                  fontSize: 12 + (i % 4) * 8,
                  alignment: i % 3 == 0 ? ui.PlaceholderAlignment.baseline : null,
                ),
              );
              b.addText(scenario == 'newlines' ? 'a  b\n' : 'abc ');
              b.pop();
              if (i % 4 == 2) {
                b.addPlaceholder(12, 48, ui.PlaceholderAlignment.middle);
              }
            }
            return b.build();
          }

          final ui.Paragraph p = build();
          for (final width in <double>[800, 110, 260, 800]) {
            p.layout(ui.ParagraphConstraints(width: width));
            // First full query populates the geometry cache before partial queries.
            p.getBoxesForRange(0, 1000);
            final ui.Paragraph fresh = build()..layout(ui.ParagraphConstraints(width: width));
            expect(p.height, fresh.height);
            expect(p.didExceedMaxLines, fresh.didExceedMaxLines);
            for (final ui.BoxHeightStyle height in ui.BoxHeightStyle.values) {
              for (final ui.BoxWidthStyle boxWidth in ui.BoxWidthStyle.values) {
                for (final range in <(int, int)>[
                  (0, 1000),
                  (0, 1),
                  (1, 1),
                  (3, 12),
                  (19, 30),
                  (41, 51),
                  (1000, 1001),
                ]) {
                  expect(
                    p.getBoxesForRange(
                      range.$1,
                      range.$2,
                      boxHeightStyle: height,
                      boxWidthStyle: boxWidth,
                    ),
                    fresh.getBoxesForRange(
                      range.$1,
                      range.$2,
                      boxHeightStyle: height,
                      boxWidthStyle: boxWidth,
                    ),
                  );
                }
              }
            }
            for (var offset = 0; offset < 40; offset++) {
              final ui.GlyphInfo? a = p.getGlyphInfoAt(offset), b = fresh.getGlyphInfoAt(offset);
              expect(a?.graphemeClusterLayoutBounds, b?.graphemeClusterLayoutBounds);
              expect(a?.graphemeClusterCodeUnitRange, b?.graphemeClusterCodeUnitRange);
              expect(
                p.getLineBoundary(ui.TextPosition(offset: offset)),
                fresh.getLineBoundary(ui.TextPosition(offset: offset)),
              );
              expect(
                p.getWordBoundary(ui.TextPosition(offset: offset)),
                fresh.getWordBoundary(ui.TextPosition(offset: offset)),
              );
            }
            expect(p.getBoxesForPlaceholders(), fresh.getBoxesForPlaceholders());
            fresh.dispose();
          }
          p.dispose();
        }
      });
      test('deep style inheritance and reset root=$mode direction=$direction', () {
        for (final ui.PlaceholderAlignment childMode in ui.PlaceholderAlignment.values) {
          final b = ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: 'FlutterTest',
              fontSize: 20,
              alignment: mode,
              textDirection: direction,
            ),
          );
          b.addText('A');
          b.pushStyle(ui.TextStyle(alignment: childMode));
          b.addText('B');
          b.pushStyle(ui.TextStyle(color: const ui.Color(0xffff0000)));
          b.addText('C');
          b.pop();
          b.pushStyle(ui.TextStyle(alignment: ui.PlaceholderAlignment.baseline));
          b.addText('D');
          b.pop();
          b.addText('E');
          b.pop();
          b.addText('F');
          b.addPlaceholder(
            1,
            100,
            ui.PlaceholderAlignment.baseline,
            baseline: ui.TextBaseline.alphabetic,
            baselineOffset: 50,
          );
          final ui.Paragraph p = b.build()..layout(const ui.ParagraphConstraints(width: 1000));
          for (var i = 0; i < 6; i++) {
            final ui.PlaceholderAlignment expected = i == 0 || i == 5
                ? mode
                : i == 3
                ? ui.PlaceholderAlignment.baseline
                : childMode;
            final ui.Rect rect = p.getBoxesForRange(i, i + 1).single.toRect();
            _checkInlineEdge(rect, expected, p);
            if (expected == ui.PlaceholderAlignment.baseline) {
              final referenceBuilder = ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontFamily: 'FlutterTest',
                  fontSize: 20,
                  textDirection: direction,
                ),
              );
              referenceBuilder.addText('D');
              referenceBuilder.addPlaceholder(
                1,
                100,
                ui.PlaceholderAlignment.baseline,
                baseline: ui.TextBaseline.alphabetic,
                baselineOffset: 50,
              );
              final ui.Paragraph reference = referenceBuilder.build()
                ..layout(const ui.ParagraphConstraints(width: 1000));
              expect(rect.top, reference.getBoxesForRange(0, 1).single.top);
              reference.dispose();
            }
          }
          p.dispose();
        }
      });
    }
  }
  test('all alignment values participate in style equality', () {
    for (final a in <ui.PlaceholderAlignment?>[null, ...ui.PlaceholderAlignment.values]) {
      for (final b in <ui.PlaceholderAlignment?>[null, ...ui.PlaceholderAlignment.values]) {
        expect(ui.TextStyle(alignment: a) == ui.TextStyle(alignment: b), a == b);
        if (a != null && b != null) {
          expect(ui.ParagraphStyle(alignment: a) == ui.ParagraphStyle(alignment: b), a == b);
        }
      }
    }
  });
}
