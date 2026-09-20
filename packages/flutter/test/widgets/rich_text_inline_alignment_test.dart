// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  registerInlineFrameworkMatrixTests();
  testWidgets('RichText centers mixed text styles and a live inline widget', (
    WidgetTester tester,
  ) async {
    const childKey = ValueKey<String>('inline');
    const small = TextSelection(baseOffset: 0, extentOffset: 5);
    const big = TextSelection(baseOffset: 6, extentOffset: 9);
    Widget build(bool center, double width, double widgetHeight) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: RichText(
            alignment: center ? PlaceholderAlignment.middle : PlaceholderAlignment.baseline,
            text: TextSpan(
              style: const TextStyle(fontSize: 16),
              children: <InlineSpan>[
                const TextSpan(text: 'small '),
                const TextSpan(text: 'BIG ', style: TextStyle(fontSize: 40)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: SizedBox(key: childKey, width: 32, height: widgetHeight),
                ),
                const TextSpan(text: ' text continuing over multiple lines'),
              ],
            ),
          ),
        ),
      ),
    );

    for (final (double width, double widgetHeight) in <(double, double)>[
      for (final double width in <double>[700, 320])
        for (final double height in <double>[24, 64, 100]) (width, height),
    ]) {
      await tester.pumpWidget(build(false, width, widgetHeight));
      final RenderParagraph paragraph = tester.renderObject(find.byType(RichText));
      final Size originalSize = paragraph.size;
      final Rect originalSmall = paragraph.getBoxesForSelection(small).single.toRect();
      final Rect originalBig = paragraph.getBoxesForSelection(big).single.toRect();
      final Offset origin = tester.getTopLeft(find.byType(RichText));

      await tester.pumpWidget(build(true, width, widgetHeight));
      expect(paragraph.alignment, PlaceholderAlignment.middle);
      final Rect smallBox = paragraph.getBoxesForSelection(small).single.toRect();
      final Rect bigBox = paragraph.getBoxesForSelection(big).single.toRect();
      final Rect childBox = tester.getRect(find.byKey(childKey)).shift(-origin);
      expect(smallBox.center.dy, closeTo(bigBox.center.dy, 0.01));
      expect(smallBox.center.dy, closeTo(childBox.center.dy, 0.01));
      expect(smallBox.left, originalSmall.left);
      expect(bigBox.left, originalBig.left);
      expect(paragraph.size, originalSize);

      await tester.pumpWidget(build(false, width, widgetHeight));
      expect(paragraph.getBoxesForSelection(small).single.toRect(), originalSmall);
      expect(paragraph.getBoxesForSelection(big).single.toRect(), originalBig);
    }
  });
  testWidgets('TextSpan alignment inherits, overrides, resets and leaves widgets alone', (
    WidgetTester tester,
  ) async {
    const childKey = ValueKey<String>('independent-placeholder');
    Widget build(PlaceholderAlignment alignment) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RichText(
          alignment: alignment,
          text: const TextSpan(
            style: TextStyle(fontSize: 20),
            children: <InlineSpan>[
              TextSpan(
                alignment: PlaceholderAlignment.top,
                text: 'A',
                children: <InlineSpan>[
                  TextSpan(text: 'B'),
                  TextSpan(alignment: PlaceholderAlignment.bottom, text: 'C'),
                ],
              ),
              TextSpan(text: 'D'),
              TextSpan(alignment: PlaceholderAlignment.baseline, text: 'E'),
              WidgetSpan(
                // Exercise the widget's own alignment independently of the root.
                // ignore: avoid_redundant_argument_values
                alignment: PlaceholderAlignment.bottom,
                child: SizedBox(key: childKey, width: 20, height: 100),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(PlaceholderAlignment.baseline));
    final RenderParagraph paragraph = tester.renderObject(find.byType(RichText));
    Rect box(int offset) => paragraph
        .getBoxesForSelection(TextSelection(baseOffset: offset, extentOffset: offset + 1))
        .single
        .toRect();
    final Rect originalWidget = tester.getRect(find.byKey(childKey));
    final Rect baseline = box(4);
    await tester.pumpWidget(build(PlaceholderAlignment.middle));
    expect(box(0).top, closeTo(0, 0.01));
    expect(box(1).top, closeTo(0, 0.01));
    expect(box(2).bottom, closeTo(paragraph.size.height, 0.01));
    expect(box(3).center.dy, closeTo(paragraph.size.height / 2, 0.01));
    expect(box(4), baseline);
    expect(tester.getRect(find.byKey(childKey)), originalWidget);
    expect(
      paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 5)).length,
      greaterThanOrEqualTo(4),
    );
  });

  test('TextSpan alignment participates in equality and layout invalidation', () {
    const top = TextSpan(text: 'same font', alignment: PlaceholderAlignment.top);
    const bottom = TextSpan(text: 'same font', alignment: PlaceholderAlignment.bottom);
    expect(top, isNot(bottom));
    expect(top.compareTo(bottom), RenderComparison.layout);
    expect(top, const TextSpan(text: 'same font', alignment: PlaceholderAlignment.top));
  });
}

void registerInlineFrameworkMatrixTests() {
  for (final TextDirection direction in TextDirection.values) {
    for (final PlaceholderAlignment root in PlaceholderAlignment.values) {
      testWidgets('nested alignment update root=$root direction=$direction', (
        WidgetTester tester,
      ) async {
        Widget build(PlaceholderAlignment child) => Directionality(
          textDirection: direction,
          child: Align(
            alignment: Alignment.topLeft,
            child: RichText(
              alignment: root,
              text: TextSpan(
                style: const TextStyle(fontSize: 20),
                children: <InlineSpan>[
                  const TextSpan(text: 'A'),
                  TextSpan(
                    alignment: child,
                    text: 'B',
                    children: const <InlineSpan>[
                      TextSpan(
                        text: 'C',
                        style: TextStyle(color: Color(0xffff0000)),
                      ),
                      TextSpan(text: 'D', alignment: PlaceholderAlignment.baseline),
                    ],
                  ),
                  const TextSpan(text: 'E'),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: SizedBox(
                      width: 1,
                      height: 100,
                      child: Baseline(
                        baseline: 50,
                        baselineType: TextBaseline.alphabetic,
                        child: SizedBox(width: 1, height: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        Rect? baselineReference;
        for (final PlaceholderAlignment child in PlaceholderAlignment.values) {
          await tester.pumpWidget(build(child));
          final RenderParagraph p = tester.renderObject(find.byType(RichText));
          Rect box(int i) => p
              .getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1))
              .single
              .toRect();
          baselineReference ??= box(3);
          expect(box(1).top, box(2).top);
          expect(box(0).top, box(4).top);
          expect(p.text.toPlainText(), 'ABCDE\uFFFC');
          final double baseline = p.getDryBaseline(p.constraints, TextBaseline.alphabetic)!;
          for (final (int offset, PlaceholderAlignment alignment) in <(int, PlaceholderAlignment)>[
            (0, root),
            (1, child),
            (2, child),
            (3, PlaceholderAlignment.baseline),
            (4, root),
          ]) {
            final Rect r = box(offset);
            switch (alignment) {
              case PlaceholderAlignment.top:
                expect(r.top, closeTo(0, .02));
              case PlaceholderAlignment.middle:
                expect(r.center.dy, closeTo(p.size.height / 2, .02));
              case PlaceholderAlignment.bottom:
                expect(r.bottom, closeTo(p.size.height, .02));
              case PlaceholderAlignment.aboveBaseline:
                expect(r.bottom, closeTo(baseline, .02));
              case PlaceholderAlignment.belowBaseline:
                expect(r.top, closeTo(baseline, .02));
              case PlaceholderAlignment.baseline:
                expect(r.top, baselineReference.top);
            }
          }
        }
      });
      testWidgets('aligned text and WidgetSpan retain tap targets $root $direction', (
        WidgetTester tester,
      ) async {
        var textTaps = 0, widgetTaps = 0;
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            textTaps++;
          };
        addTearDown(recognizer.dispose);
        const widgetKey = ValueKey<String>('tap-widget');
        await tester.pumpWidget(
          Directionality(
            textDirection: direction,
            child: Align(
              alignment: Alignment.topLeft,
              child: RichText(
                alignment: root,
                text: TextSpan(
                  style: const TextStyle(fontSize: 20),
                  children: <InlineSpan>[
                    TextSpan(text: 'AB', recognizer: recognizer),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: SizedBox(
                        width: 30,
                        height: 100,
                        child: Baseline(
                          baseline: 50,
                          baselineType: TextBaseline.alphabetic,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              widgetTaps++;
                            },
                            child: const SizedBox(
                              key: widgetKey,
                              width: 30,
                              height: 20,
                              child: Text('X', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final RenderParagraph p = tester.renderObject(find.byType(RichText).first);
        final Rect rect = p
            .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
            .single
            .toRect();
        await tester.tapAt(tester.getTopLeft(find.byType(RichText).first) + rect.center);
        expect(textTaps, 1);
        expect(widgetTaps, 0);
        await tester.tapAt(tester.getCenter(find.byKey(widgetKey)));
        expect(textTaps, 1);
        expect(widgetTaps, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
  test('nullable TextSpan alignment equality and layout comparison matrix', () {
    for (final a in <PlaceholderAlignment?>[null, ...PlaceholderAlignment.values]) {
      for (final b in <PlaceholderAlignment?>[null, ...PlaceholderAlignment.values]) {
        final x = TextSpan(text: 'same', alignment: a), y = TextSpan(text: 'same', alignment: b);
        expect(x == y, a == b);
        expect(x.compareTo(y), a == b ? RenderComparison.identical : RenderComparison.layout);
        if (a == b) {
          expect(x.hashCode, y.hashCode);
        }
      }
    }
  });
}
