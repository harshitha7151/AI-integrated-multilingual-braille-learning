import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/accessibility/two_finger_navigation_detector.dart';

void main() {
  testWidgets('opt-in two-finger left and right swipes report next and previous', (tester) async {
    final directions = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TwoFingerNavigationDetector(
          enabled: true,
          onSwipe: directions.add,
          child: const SizedBox.expand(key: ValueKey('gesture-surface')),
        ),
      ),
    ));
    final rect = tester.getRect(find.byKey(const ValueKey('gesture-surface')));

    final leftA = await tester.startGesture(Offset(rect.left + 220, rect.top + 120), pointer: 1);
    final leftB = await tester.startGesture(Offset(rect.left + 400, rect.top + 120), pointer: 2);
    await leftA.moveTo(Offset(rect.left + 80, rect.top + 120));
    await leftB.moveTo(Offset(rect.left + 260, rect.top + 120));
    await tester.pump();
    await leftA.up();
    await leftB.up();
    expect(directions, [1]);

    final rightA = await tester.startGesture(Offset(rect.left + 80, rect.top + 220), pointer: 3);
    final rightB = await tester.startGesture(Offset(rect.left + 260, rect.top + 220), pointer: 4);
    await rightA.moveTo(Offset(rect.left + 220, rect.top + 220));
    await rightB.moveTo(Offset(rect.left + 400, rect.top + 220));
    await tester.pump();
    await rightA.up();
    await rightB.up();
    expect(directions, [1, -1]);
  });

  testWidgets('one-finger and disabled gestures never navigate', (tester) async {
    final directions = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TwoFingerNavigationDetector(
          enabled: false,
          onSwipe: directions.add,
          child: const SizedBox.expand(key: ValueKey('gesture-surface')),
        ),
      ),
    ));
    final rect = tester.getRect(find.byKey(const ValueKey('gesture-surface')));
    final oneFinger = await tester.startGesture(Offset(rect.left + 220, rect.top + 120));
    await oneFinger.moveTo(Offset(rect.left + 50, rect.top + 120));
    await tester.pump();
    await oneFinger.up();
    expect(directions, isEmpty);
  });

  testWidgets('three-finger horizontal swipe invokes dedicated language action', (tester) async {
    var languageChanges = 0;
    final directions = <int>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TwoFingerNavigationDetector(
      enabled: true,
      onSwipe: directions.add,
      onLanguageSwipe: () => languageChanges++,
      child: const SizedBox.expand(key: ValueKey('gesture-surface')),
    ))));
    final rect = tester.getRect(find.byKey(const ValueKey('gesture-surface')));
    final a = await tester.startGesture(Offset(rect.left + 300, rect.top + 100), pointer: 11);
    final b = await tester.startGesture(Offset(rect.left + 300, rect.top + 160), pointer: 12);
    final c = await tester.startGesture(Offset(rect.left + 300, rect.top + 220), pointer: 13);
    await a.moveTo(Offset(rect.left + 140, rect.top + 100));
    await b.moveTo(Offset(rect.left + 140, rect.top + 160));
    await c.moveTo(Offset(rect.left + 140, rect.top + 220));
    await tester.pump();
    await a.up(); await b.up(); await c.up();
    expect(languageChanges, 1);
    expect(directions, isEmpty);
  });

  testWidgets('two-finger up and down swipes invoke section navigation', (tester) async {
    final sections = <int>[];
    final lessons = <int>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TwoFingerNavigationDetector(
      enabled: true,
      onSwipe: lessons.add,
      onVerticalSwipe: sections.add,
      child: const SizedBox.expand(key: ValueKey('gesture-surface')),
    ))));
    final rect = tester.getRect(find.byKey(const ValueKey('gesture-surface')));
    final upA = await tester.startGesture(Offset(rect.left + 120, rect.top + 300), pointer: 21);
    final upB = await tester.startGesture(Offset(rect.left + 180, rect.top + 300), pointer: 22);
    await upA.moveTo(Offset(rect.left + 120, rect.top + 150));
    await upB.moveTo(Offset(rect.left + 180, rect.top + 150));
    await tester.pump();
    await upA.up(); await upB.up();
    final downA = await tester.startGesture(Offset(rect.left + 120, rect.top + 150), pointer: 23);
    final downB = await tester.startGesture(Offset(rect.left + 180, rect.top + 150), pointer: 24);
    await downA.moveTo(Offset(rect.left + 120, rect.top + 300));
    await downB.moveTo(Offset(rect.left + 180, rect.top + 300));
    await tester.pump();
    await downA.up(); await downB.up();
    expect(sections, [1, -1]);
    expect(lessons, isEmpty);
  });
}
