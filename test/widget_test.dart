import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/main.dart';

void main() {
  Future<void> showKeyboard(
    WidgetTester tester, {
    Future<void> Function(String)? onSpeak,
    VoidCallback? onTutor,
    ValueChanged<String>? onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrailleKeyboard(
            onFeedback: () {},
            onSpeak: onSpeak ?? (_) async {},
            onAudioChanged: (_) {},
            audioEnabled: false,
            hapticsEnabled: false,
            onTutor: onTutor,
            onSubmitPattern: onSubmit,
          ),
        ),
      ),
    );
  }

  testWidgets('screen columns match the landscape keyboard reference', (
    tester,
  ) async {
    await showKeyboard(tester);
    final surface = tester.getRect(
      find.byKey(const ValueKey('braille-touch-surface')),
    );

    await tester.tapAt(Offset(surface.left + 20, surface.top + 20));
    await tester.pump();
    expect(find.textContaining('Dots: 1'), findsOneWidget);

    await tester.tapAt(Offset(surface.center.dx + 20, surface.top + 20));
    await tester.pump();
    expect(find.textContaining('Dots: 4'), findsOneWidget);
  });

  testWidgets('keyboard tutor prompt is accessible and does not overlap dots', (
    tester,
  ) async {
    var opened = false;
    await showKeyboard(tester, onTutor: () => opened = true);
    expect(find.text('Swipe up here to talk'), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
    final prompt = find.byKey(const ValueKey('keyboard-tutor-prompt'));
    expect(prompt, findsOneWidget);
    await tester.tap(prompt);
    expect(opened, isTrue);
    final surface = tester.getRect(
      find.byKey(const ValueKey('braille-touch-surface')),
    );
    final promptRect = tester.getRect(prompt);
    expect(surface.bottom, lessThanOrEqualTo(promptRect.top));
  });

  testWidgets(
    'swipes in all four directions on the status strip submit the selected cell',
    (tester) async {
      final submitted = <String>[];
      await showKeyboard(tester, onSubmit: submitted.add);
      await tester.tap(find.byTooltip('Switch to accessible dot controls'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Braille dot 1'));
      await tester.pump();
      final status = tester.getRect(
        find.byKey(const ValueKey('braille-check-swipe-area')),
      );
      for (final delta in const [
        Offset(-80, 0),
        Offset(80, 0),
        Offset(0, -80),
        Offset(0, 80),
      ]) {
        final gesture = await tester.startGesture(status.center);
        await gesture.moveBy(delta);
        await gesture.up();
        await tester.pump();
      }
      expect(submitted, ['100000', '100000', '100000', '100000']);
    },
  );

  testWidgets('dragging across zones cancels instead of adding dots', (
    tester,
  ) async {
    await showKeyboard(tester);
    final surface = tester.getRect(
      find.byKey(const ValueKey('braille-touch-surface')),
    );
    final gesture = await tester.startGesture(
      Offset(surface.left + 20, surface.top + 20),
    );
    await gesture.moveTo(Offset(surface.center.dx + 20, surface.top + 20));
    await tester.pump();

    expect(find.textContaining('Chord cancelled'), findsOneWidget);
    expect(find.textContaining('Dots: None'), findsOneWidget);
    await gesture.up();
  });

  testWidgets('simultaneous fingers complete one two-dot chord', (
    tester,
  ) async {
    await showKeyboard(tester);
    final surface = tester.getRect(
      find.byKey(const ValueKey('braille-touch-surface')),
    );
    final rightHand = await tester.startGesture(
      Offset(surface.left + 20, surface.top + 20),
      pointer: 1,
    );
    final leftHand = await tester.startGesture(
      Offset(surface.center.dx + 20, surface.top + 20),
      pointer: 2,
    );

    await rightHand.up();
    await tester.pump();
    expect(find.textContaining('Dots: 1, 4'), findsNothing);

    await leftHand.up();
    await tester.pump();
    expect(find.textContaining('Dots: 1, 4'), findsOneWidget);
    expect(find.textContaining('100100'), findsOneWidget);
  });

  testWidgets('pointer cancellation discards the in-progress chord', (
    tester,
  ) async {
    await showKeyboard(tester);
    final surface = tester.getRect(
      find.byKey(const ValueKey('braille-touch-surface')),
    );
    final gesture = await tester.startGesture(
      Offset(surface.left + 20, surface.top + 20),
    );
    await gesture.cancel();
    await tester.pump();

    expect(find.textContaining('Touch interrupted'), findsOneWidget);
    expect(find.textContaining('Dots: None'), findsOneWidget);
  });

  testWidgets(
    'provides buttonless semantic dot controls as an input alternative',
    (tester) async {
      await showKeyboard(tester);
      expect(find.byType(Scrollable), findsNothing);
      await tester.tap(find.byTooltip('Switch to accessible dot controls'));
      await tester.pump();
      expect(find.byType(Scrollable), findsNothing);

      final dotOne = find.bySemanticsLabel('Braille dot 1');
      expect(dotOne, findsOneWidget);
      await tester.tap(dotOne);
      await tester.pump();

      final semantics = tester.getSemantics(dotOne).getSemanticsData();
      expect(semantics.value, 'selected');
      expect(semantics.hasFlag(SemanticsFlag.isButton), isFalse);
    },
  );

  testWidgets(
    'dot selections announce the full pattern and can speak its decoded character',
    (tester) async {
      final spoken = <String>[];
      await showKeyboard(
        tester,
        onSpeak: (text) async {
          spoken.add(text);
        },
      );
      await tester.tap(find.byTooltip('Switch to accessible dot controls'));
      await tester.pump();
      final dotOne = find.bySemanticsLabel('Braille dot 1');
      await tester.tap(dotOne);
      await tester.pump();
      expect(spoken.last, contains('Current selection: dot 1'));
      expect(tester.getSemantics(dotOne).getSemanticsData().value, 'selected');
      await tester.tap(find.byTooltip('Hear Braille character'));
      await tester.pump();
      expect(spoken.last, contains('represents the character a'));
      await tester.tap(dotOne);
      await tester.pump();
      expect(
        tester.getSemantics(dotOne).getSemanticsData().value,
        'not selected',
      );
    },
  );

  testWidgets('keyboard actions wrap on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: MaterialApp(
          home: Scaffold(
            body: BrailleKeyboard(
              onFeedback: () {},
              onSpeak: (_) async {},
              onAudioChanged: (_) {},
              audioEnabled: false,
              hapticsEnabled: false,
              onSubmitPattern: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Clear pattern'), findsOneWidget);
    expect(find.byTooltip('Check pattern'), findsOneWidget);
  });
}
