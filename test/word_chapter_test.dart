import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/english_grade1_engine.dart';
import 'package:resonant_braille/main.dart';

void main() {
  testWidgets('first word lesson requires the six-dot Braille answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final attempts = <Map<String, Object?>>[];
    final spoken = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordChapterScreen(
            initialLesson: 0,
            completedWords: const {},
            onSpeak: (text) async => spoken.add(text),
            onFeedback: () {},
            audioEnabled: false,
            hapticsEnabled: false,
            onAttempt:
                ({
                  required lessonIndex,
                  required word,
                  required correct,
                  required attemptNumber,
                  required hintUsed,
                  groupId,
                  finalAttempt = true,
                  responseTimeMs = 0,
                  required skillObservations,
                }) async {
                  attempts.add({
                    'lesson': lessonIndex,
                    'word': word,
                    'correct': correct,
                    'final': finalAttempt,
                    'skill_observations': skillObservations,
                  });
                },
            onLessonChanged: (_) {},
            onMasteryPassed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('keyboard-check-pattern')),
      findsOneWidget,
    );
    expect(find.text('I explored this word'), findsNothing);

    await tester.tap(find.byTooltip('Switch to accessible dot controls'));
    await tester.pumpAndSettle();
    for (final cell in EnglishGrade1Engine.encode('CAT')) {
      for (final dot in EnglishGrade1Engine.dotsForCell(cell)) {
        await tester.tap(find.bySemanticsLabel('Braille dot $dot'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('keyboard-check-pattern')));
      await tester.pumpAndSettle();
    }
    expect(attempts, hasLength(1));
    expect(attempts.single['word'], 'CAT');
    expect(attempts.single['correct'], true);
    expect(attempts.single['final'], true);
    expect(attempts.single['skill_observations'], hasLength(3));
    expect(spoken.any((text) => text.contains('Next word: BAT')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'word-writing lesson validates every cell and persists attempts',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <Map<String, Object?>>[];
      final spoken = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordChapterScreen(
              initialLesson: 2,
              completedWords: const {},
              onSpeak: (text) async => spoken.add(text),
              onFeedback: () {},
              audioEnabled: false,
              hapticsEnabled: false,
              onAttempt:
                  ({
                    required lessonIndex,
                    required word,
                    required correct,
                    required attemptNumber,
                    required hintUsed,
                    groupId,
                    finalAttempt = true,
                    responseTimeMs = 0,
                    required skillObservations,
                  }) async {
                    events.add({
                      'lesson': lessonIndex,
                      'word': word,
                      'correct': correct,
                      'attempt': attemptNumber,
                      'hint': hintUsed,
                      'group': groupId,
                      'final': finalAttempt,
                      'duration': responseTimeMs,
                      'skill_observations': skillObservations,
                    });
                  },
              onLessonChanged: (_) {},
              onMasteryPassed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Let us write CAT'), findsNothing);
      expect(spoken.any((text) => text.contains('Current word: CAT')), isTrue);
      await tester.tap(find.byTooltip('Switch to accessible dot controls'));
      await tester.pumpAndSettle();

      Future<void> enterCell(int cell) async {
        for (final dot in EnglishGrade1Engine.dotsForCell(cell)) {
          await tester.tap(find.bySemanticsLabel('Braille dot $dot'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('keyboard-check-pattern')));
        await tester.pumpAndSettle();
      }

      // A wrong first cell is corrected without advancing the learner.
      await enterCell(1);
      expect(
        find.textContaining('That cell was not quite right'),
        findsNothing,
      );
      expect(
        spoken.any((text) => text.contains('That cell was not quite right')),
        isTrue,
      );
      expect(events.single['correct'], false);

      // Finish the two capital indicators, then record an incorrect C cell.
      await enterCell(32);
      await enterCell(32);
      await enterCell(1);
      expect(events.last['skill_observations'], [
        {
          'character': 'c',
          'skill_id': 'english-letter-c',
          'correct': false,
          'cell_start': 0,
          'cell_count': 1,
        },
      ]);
      await enterCell(EnglishGrade1Engine.encode('c').single);
      await tester.tap(find.byTooltip('Backspace previous Braille cell'));
      await tester.pumpAndSettle();
      expect(
        spoken.any((text) => text.contains('Previous cell removed')),
        isTrue,
      );

      for (final cell in EnglishGrade1Engine.encode('c')) {
        await enterCell(cell);
      }
      for (final cell in EnglishGrade1Engine.encode('at')) {
        await enterCell(cell);
      }

      expect(find.textContaining('Let us write BAT'), findsNothing);
      expect(spoken.any((text) => text.contains('Next word: BAT')), isTrue);
      expect(events.last['word'], 'CAT');
      expect(events.last['correct'], true);
      expect(events.last['final'], true);
      expect(events.last['attempt'], 8);
      expect(
        (events.last['skill_observations'] as List).map(
          (item) => (item as Map)['correct'],
        ),
        [true, true, true],
      );
      expect(
        spoken.any((text) => text.contains('Capital-word sign cell 1')),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
