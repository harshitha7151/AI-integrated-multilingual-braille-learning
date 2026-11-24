import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/learning/adaptive_decision_controller.dart';
import 'package:resonant_braille/learning/onboarding_store.dart';
import 'package:resonant_braille/learning/lesson_progress_store.dart';
import 'package:resonant_braille/core/braille/english_grade1_engine.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';
import 'package:resonant_braille/learning/welcome_onboarding.dart';
import 'package:resonant_braille/main.dart';

class _MemoryOnboarding implements OnboardingProgress {
  bool completed = false;
  int step = 0;
  @override
  Future<bool> isComplete() async => completed;
  @override
  Future<void> markComplete() async => completed = true;
  @override
  Future<int> currentStep() async => step;
  @override
  Future<void> saveStep(int value) async => step = value;
}

class _MemoryLessonProgressStore extends LessonProgressStore {
  _MemoryLessonProgressStore([this.events = const []])
    : super(File('unused-progress.json'));
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> recordedEvents = [];
  @override
  Future<List<Map<String, dynamic>>> readEvents() async => events;
  @override
  Future<String> record({
    required String exerciseId,
    required String skillId,
    required String exerciseType,
    required bool correct,
    required int attemptNumber,
    required bool hintUsed,
    required int responseTimeMs,
    String? groupId,
    String? learnerId,
    String language = 'English',
    String? assessmentKey,
    String? lessonId,
    String? questionText,
    List<String>? options,
    String? learningObjective,
    int difficulty = 1,
    Map<String, dynamic>? expectedResponse,
    Map<String, dynamic>? submittedResponse,
    String inputStatus = 'valid',
    String? technicalFailureCode,
    String? questionId,
    String? questionInstanceId,
    String questionSource = 'validated_catalog',
    String questionVersion = 'flutter-catalog-v1',
    String? generationModel,
    String mappingVersion = 'unspecified',
    String curriculumVersion = 'flutter-catalog-v1',
    String? interventionType,
    String? feedbackType,
  }) async {
    final submissionId = 'memory-${recordedEvents.length + 1}';
    recordedEvents.add({
      'submission_id': submissionId,
      'exercise_id': exerciseId,
      'skill_id': skillId,
      'exercise_type': exerciseType,
      'correct': correct,
      'attempt_number': attemptNumber,
      'hint_used': hintUsed,
      'response_time_ms': responseTimeMs,
      'language': language,
      if (assessmentKey != null) ...{
        'assessment_key': assessmentKey,
        'lesson_id': lessonId,
        if (questionId != null) 'question_id': questionId,
        if (questionInstanceId != null)
          'question_instance_id': questionInstanceId,
        'question_source': questionSource,
        'question_version': questionVersion,
        'mapping_version': mappingVersion,
        'curriculum_version': curriculumVersion,
        if (generationModel != null) 'generation_model': generationModel,
        if (interventionType != null) 'intervention_type': interventionType,
        if (feedbackType != null) 'feedback_type': feedbackType,
        'expected_response': expectedResponse,
        'submitted_response': submittedResponse,
      },
    });
    return submissionId;
  }
}

Future<void> swipeLessonUp(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('lesson-swipe-navigation')),
    const Offset(0, -80),
  );
  await tester.pumpAndSettle();
}

Future<void> swipeCourseUp(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('course-swipe-navigation')),
    const Offset(0, -80),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('onboarding completion persists after reopening', () async {
    final directory = await Directory.systemTemp.createTemp(
      'resonant-onboarding-',
    );
    try {
      final store = OnboardingStore(
        File('${directory.path}${Platform.pathSeparator}onboarding.json'),
      );
      expect(await store.isComplete(), isFalse);
      await store.saveStep(4);
      expect(await OnboardingStore(store.file).currentStep(), 4);
      await store.markComplete();
      expect(await OnboardingStore(store.file).isComplete(), isTrue);
      expect(await OnboardingStore(store.file).currentStep(), 0);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'legacy completed onboarding requires revised Lesson 1 without erasing progress',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'resonant-onboarding-upgrade-',
      );
      try {
        final file = File(
          '${directory.path}${Platform.pathSeparator}onboarding.json',
        );
        await file.writeAsString(
          '{"completed":true,"step":0,"lesson_version":4}',
        );
        final store = OnboardingStore(file);
        expect(await store.isComplete(), isFalse);
        expect(await store.currentStep(), 0);
        await store.markComplete();
        expect(await OnboardingStore(file).isComplete(), isTrue);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets('first launch opens onboarding before any keyboard or lesson', (
    tester,
  ) async {
    final progress = _MemoryOnboarding();
    await tester.pumpWidget(
      MaterialApp(home: ResonantHome(onboardingProgress: progress)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-title')), findsOneWidget);
    expect(find.text('Welcome to Resonant'), findsWidgets);
    expect(find.byType(BrailleKeyboard), findsNothing);
    expect(find.text('Learn letter A'), findsNothing);
  });

  testWidgets('swiping anywhere in the welcome lesson advances its steps', (
    tester,
  ) async {
    final progress = _MemoryOnboarding();
    await tester.pumpWidget(
      MaterialApp(home: ResonantHome(onboardingProgress: progress)),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('onboarding-swipe-surface')),
      const Offset(0, -90),
    );
    await tester.pumpAndSettle();
    expect(find.text('How lessons work'), findsOneWidget);
    expect(find.textContaining('Step 2 of 10'), findsOneWidget);
  });

  testWidgets(
    'returning learner can replay Welcome without clearing practice',
    (tester) async {
      final progress = _MemoryOnboarding()..completed = true;
      final saved = _MemoryLessonProgressStore([
        {'exercise_id': 'letter-a', 'outcome': 'correct', 'hint_used': false},
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: ResonantHome(
            onboardingProgress: progress,
            lessonProgressStore: saved,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final tutorArea = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label?.startsWith('Tutor area.') ?? false),
        ),
      );
      tutorArea.properties.customSemanticsActions!.entries
          .singleWhere((entry) => entry.key.label == 'Replay welcome lesson')
          .value();
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Resonant'), findsOneWidget);
      expect(saved.events.single['exercise_id'], 'letter-a');
    },
  );

  testWidgets('returning learner resumes directly at letter A', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final progress = _MemoryOnboarding()..completed = true;
    await tester.pumpWidget(
      MaterialApp(
        home: ResonantHome(
          onboardingProgress: progress,
          lessonProgressStore: _MemoryLessonProgressStore(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('onboarding-title')), findsNothing);
    expect(find.text('Learn letter A'), findsOneWidget);
    expect(find.byType(BrailleKeyboard), findsNothing);
  });

  testWidgets('swiping lesson content begins practice anywhere on the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ResonantHome(
          onboardingProgress: _MemoryOnboarding()..completed = true,
          lessonProgressStore: _MemoryLessonProgressStore(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.drag(
      find.textContaining('In Braille, the letter A'),
      const Offset(0, -90),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BrailleKeyboard), findsOneWidget);
  });

  testWidgets(
    'resumes an unfinished A–E word test after the five letters are mastered',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final progress = _MemoryOnboarding()..completed = true;
      final events = [
        for (final letter in 'abcde'.split(''))
          {
            'exercise_id': 'letter-$letter',
            'outcome': 'correct',
            'hint_used': false,
          },
        {
          'exercise_id': 'word-stage-a-e-word-0',
          'outcome': 'correct',
          'hint_used': false,
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ResonantHome(
            onboardingProgress: progress,
            lessonProgressStore: _MemoryLessonProgressStore(events),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Write a word: CAB'), findsOneWidget);
    },
  );

  testWidgets(
    'lesson screen stays usable at phone width and enlarged text without dashboard navigation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: ResonantHome(
              onboardingProgress: _MemoryOnboarding()..completed = true,
              lessonProgressStore: _MemoryLessonProgressStore(),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final tutorArea = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label?.startsWith('Tutor area.') ?? false),
        ),
      );
      expect(tutorArea.properties.label, contains('Swipe up'));
      expect(
        tutorArea.properties.customSemanticsActions?.keys.map(
          (action) => action.label,
        ),
        contains('Talk to Resonant'),
      );
      expect(find.byKey(const ValueKey('open-voice-tutor')), findsNothing);
      expect(find.text('Learn letter A'), findsOneWidget);
      expect(find.text('Continue Learning'), findsNothing);
      expect(find.text('My Progress'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('teaches A through E before a whole-word BAD assessment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final progress = _MemoryOnboarding();
    final lessonStore = _MemoryLessonProgressStore();
    await tester.pumpWidget(
      MaterialApp(
        home: ResonantHome(
          onboardingProgress: progress,
          lessonProgressStore: lessonStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await swipeLessonUp(tester);
    }
    for (var i = 0; i < 5; i++) {
      await swipeLessonUp(tester);
    }
    await swipeLessonUp(tester);

    Future<void> practiseLetter(String letter, List<int> dots) async {
      expect(find.text('Learn letter $letter'), findsOneWidget);
      expect(find.byType(BrailleKeyboard), findsNothing);
      await swipeCourseUp(tester);
      if (find.byType(BrailleKeyboard).evaluate().isEmpty) {
        await swipeCourseUp(tester);
      }
      expect(find.byType(BrailleKeyboard), findsOneWidget);
      expect(find.textContaining('Guided practice:'), findsNothing);
      expect(find.textContaining('Enter the pattern for'), findsNothing);
      expect(find.text('RESONANT'), findsNothing);
      await tester.tap(find.byTooltip('Switch to accessible dot controls'));
      await tester.pump();
      for (final dot in dots) {
        await tester.tap(find.bySemanticsLabel('Braille dot $dot'));
        await tester.pump();
      }
      if (letter == 'A') {
        await tester.drag(
          find.byKey(const ValueKey('braille-check-swipe-area')),
          const Offset(-80, 0),
        );
      } else {
        await tester.tap(find.byKey(const ValueKey('keyboard-check-pattern')));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('LESSON ASSESSMENT'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('lesson-answer-${letter.toLowerCase()}')),
      );
      await tester.pump();
      await tester.tap(find.text('Check answer'));
      await tester.pumpAndSettle();
    }

    await practiseLetter('A', [1]);
    await practiseLetter('B', [1, 2]);
    await practiseLetter('C', [1, 4]);
    await practiseLetter('D', [1, 4, 5]);
    await practiseLetter('E', [1, 5]);
    expect(
      lessonStore.recordedEvents,
      contains(containsPair('exercise_id', 'guided-practice-letter-a')),
    );
    expect(
      lessonStore.recordedEvents,
      contains(
        allOf(
          containsPair('exercise_id', 'lesson-assessment-letter-a'),
          containsPair('exercise_type', 'quiz'),
        ),
      ),
    );
    final letterAssessment = lessonStore.recordedEvents.firstWhere(
      (event) => event['exercise_id'] == 'lesson-assessment-letter-a',
    );
    expect(letterAssessment['assessment_key'], 'en-letter-a-v1');
    expect(letterAssessment['lesson_id'], 'letter-a');
    expect(letterAssessment['expected_response']['cells'], [1]);
    expect(letterAssessment['submitted_response']['choice'], 'a');
    expect(find.text('Write a word: BAD'), findsOneWidget);
    await swipeCourseUp(tester);
    expect(find.text('Check answer'), findsNothing);
    expect(find.byKey(const ValueKey('check-lesson-answer')), findsNothing);
    expect(
      find.byKey(const ValueKey('keyboard-check-pattern')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Switch to accessible dot controls'));
    await tester.pump();

    Future<void> enterWord(String word) async {
      for (var index = 0; index < word.length; index++) {
        await tester.tap(find.byTooltip('Clear pattern'));
        await tester.pump();
        final dots = EnglishGrade1Engine.dotsForCell(
          EnglishGrade1Engine.encode(word[index].toLowerCase()).single,
        );
        for (final dot in dots) {
          await tester.tap(find.bySemanticsLabel('Braille dot $dot'));
          await tester.pump();
        }
        await tester.tap(find.byKey(const ValueKey('keyboard-check-pattern')));
        await tester.pumpAndSettle();
        if (index < word.length - 1) {
          await tester.tap(find.byTooltip('Clear pattern'));
          await tester.pump();
        }
      }
    }

    for (
      var wordIndex = 0;
      wordIndex < LessonCatalog.curriculum.first.words.length;
      wordIndex++
    ) {
      if (wordIndex > 0) {
        await swipeCourseUp(tester);
        await tester.tap(find.byTooltip('Switch to accessible dot controls'));
        await tester.pump();
      }
      await enterWord(LessonCatalog.curriculum.first.words[wordIndex]);
    }
    expect(find.text('Learn letter F'), findsOneWidget);
  });

  testWidgets(
    'failed lesson assessment starts focused remediation before reassessment',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final progress = _MemoryOnboarding()..completed = true;
      final lessonStore = _MemoryLessonProgressStore();
      await tester.pumpWidget(
        MaterialApp(
          home: ResonantHome(
            onboardingProgress: progress,
            lessonProgressStore: lessonStore,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Learn letter A'), findsOneWidget);

      await swipeCourseUp(tester);
      if (find.byType(BrailleKeyboard).evaluate().isEmpty) {
        await swipeCourseUp(tester);
      }
      await tester.tap(find.byTooltip('Switch to accessible dot controls'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Braille dot 1'));
      await tester.tap(find.byKey(const ValueKey('keyboard-check-pattern')));
      await tester.pumpAndSettle();
      expect(find.textContaining('LESSON ASSESSMENT'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lesson-answer-b')));
      await tester.pump();
      await tester.tap(find.text('Check answer'));
      await tester.pumpAndSettle();

      expect(find.byType(BrailleKeyboard), findsOneWidget);
      expect(find.textContaining('LESSON ASSESSMENT'), findsNothing);
      expect(
        lessonStore.recordedEvents,
        contains(
          allOf(
            containsPair('exercise_id', 'lesson-assessment-letter-a'),
            containsPair('correct', false),
          ),
        ),
      );
      final pending = await lessonStore.pendingAdaptiveDecision(
        languageCode: 'en',
      );
      expect(pending?.action, AdaptiveDecisionAction.remediate);
      expect(pending?.status, AdaptiveDecisionStatus.applied);
    },
  );

  testWidgets(
    'introduction starts without the Braille keyboard and teaches six dots',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final progress = _MemoryOnboarding();
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeOnboarding(
            onComplete: progress.markComplete,
            onSpeak: (_) async {},
            onStop: () async {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('onboarding-title')), findsOneWidget);
      expect(find.textContaining('Swipe up to continue'), findsOneWidget);
      expect(find.byKey(const ValueKey('braille-touch-surface')), findsNothing);
      for (var i = 0; i < 3; i++) {
        await swipeLessonUp(tester);
      }
      expect(
        find.textContaining('screen-left shows dots 1, 2, 3'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Six-dot Braille cell.*screen-right dots 4, 5, 6'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('braille-touch-surface')), findsNothing);
    },
  );

  testWidgets('welcome lesson speaks automatically without recording audio', (
    tester,
  ) async {
    final spoken = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeOnboarding(
          onComplete: () async {},
          onSpeak: (text) async {
            spoken.add(text);
          },
          onStop: () async {},
        ),
      ),
    );
    expect(spoken, hasLength(1));
    expect(spoken.single, contains('Welcome to Resonant'));
  });

  testWidgets('last onboarding action marks the welcome complete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final progress = _MemoryOnboarding();
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeOnboarding(
          onComplete: progress.markComplete,
          onSpeak: (_) async {},
          onStop: () async {},
        ),
      ),
    );
    for (var i = 0; i < 9; i++) {
      await swipeLessonUp(tester);
    }
    await swipeLessonUp(tester);
    expect(progress.completed, isTrue);
  });
}
