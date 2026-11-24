import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/english_grade1_engine.dart';
import 'package:resonant_braille/learning/learner_account_store.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';
import 'package:resonant_braille/learning/lesson_progress_store.dart';
import 'package:resonant_braille/learning/onboarding_store.dart';
import 'package:resonant_braille/main.dart';

class _CompletedOnboarding implements OnboardingProgress {
  @override
  Future<int> currentStep() async => 10;

  @override
  Future<bool> isComplete() async => true;

  @override
  Future<void> markComplete() async {}

  @override
  Future<void> saveStep(int step) async {}
}

class _EmptyAccountStorage implements LearnerAccountStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<LearnerAccount?> load() async => null;

  @override
  Future<void> save(LearnerAccount account) async {}
}

class _MemoryProgressStore extends LessonProgressStore {
  final List<Map<String, dynamic>> _events;
  final Map<String, dynamic> resumeState;
  final List<Map<String, dynamic>> recordedEvents = [];

  _MemoryProgressStore(
    List<Map<String, dynamic>> events, {
    this.resumeState = const {},
  }) : _events = events.map(Map<String, dynamic>.from).toList(),
       super(File('unused-sentence-writing-progress.json'));

  @override
  Future<List<Map<String, dynamic>>> readEvents() async =>
      _events.map(Map<String, dynamic>.from).toList();

  @override
  Future<Map<String, dynamic>> readResumeState() async => resumeState;

  @override
  Future<Map<String, dynamic>> readResumeStateFor(String languageCode) async =>
      resumeState['language'] == languageCode ? resumeState : const {};

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
    final submissionId = 'sentence-${recordedEvents.length + 1}';
    final event = <String, dynamic>{
      'submission_id': submissionId,
      'exercise_id': exerciseId,
      'skill_id': skillId,
      'exercise_type': exerciseType,
      'outcome': correct ? 'correct' : 'incorrect',
      'attempt_number': attemptNumber,
      'hint_used': hintUsed,
      'response_time_ms': responseTimeMs,
      'language': language,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'synced_at': null,
      if (assessmentKey != null) ...{
        'sync_kind': 'assessment',
        'assessment_key': assessmentKey,
        'lesson_id': lessonId,
        'question_text': questionText,
        'options': options ?? const <String>[],
        'learning_objective': learningObjective,
        'difficulty': difficulty,
        'expected_response': expectedResponse,
        'submitted_response': submittedResponse,
        'question_source': questionSource,
        'question_version': questionVersion,
        'mapping_version': mappingVersion,
        'curriculum_version': curriculumVersion,
      },
    };
    _events.add(event);
    recordedEvents.add(event);
    return submissionId;
  }
}

Map<String, dynamic> _completedEvent(String exerciseId, {String? groupId}) => {
  'exercise_id': exerciseId,
  'skill_id': 'seed-$exerciseId',
  'exercise_type': 'transcription',
  'outcome': 'correct',
  'attempt_number': 1,
  'hint_used': false,
  if (groupId != null) 'group_id': groupId,
};

List<Map<String, dynamic>> _sentencePrerequisites() {
  final events = <Map<String, dynamic>>[
    for (final exercise in LessonCatalog.english[1].exercises)
      _completedEvent(exercise.id),
  ];
  for (final stage in LessonCatalog.curriculum) {
    for (var index = 0; index < stage.words.length; index++) {
      events.add(_completedEvent('word-stage-${stage.id}-word-$index'));
    }
  }
  for (var index = 0; index < LessonCatalog.cumulativeWords.length; index++) {
    events.add(_completedEvent('word-stage-cumulative-word-$index'));
  }
  for (var lesson = 0; lesson < 4; lesson++) {
    for (final word in LessonCatalog.wordLessons[lesson].words) {
      events.add(
        _completedEvent(
          'word-chapter-lesson-${lesson + 1}-${word.toLowerCase()}',
        ),
      );
    }
  }
  for (final word in LessonCatalog.wordLessons[4].words) {
    events.add(
      _completedEvent(
        'word-chapter-lesson-5-${word.toLowerCase()}',
        groupId: 'seed-mastery-round',
      ),
    );
  }
  for (final exercise in LessonCatalog.english[3].exercises) {
    events.add(_completedEvent(exercise.id));
  }
  return events;
}

String _patternForCell(int cell) =>
    List.generate(6, (index) => (cell & (1 << index)) == 0 ? '0' : '1').join();

void main() {
  testWidgets(
    'writes a personalized complete sentence through six-dot input and advances',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = _MemoryProgressStore(_sentencePrerequisites());
      const account = LearnerAccount(
        learnerId: 'sentence-learner',
        learnerCode: '123456',
        name: 'Namit',
        preferredLanguage: 'English',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ResonantHome(
            learnerAccount: account,
            accountStorage: _EmptyAccountStorage(),
            onboardingProgress: _CompletedOnboarding(),
            lessonProgressStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My name is Namit.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'My name is Namit\.')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('start-composed-braille-writing')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BrailleKeyboard), findsOneWidget);

      final cells = EnglishGrade1Engine.encode('My name is Namit.');
      for (final cell in cells) {
        final keyboard = tester.widget<BrailleKeyboard>(
          find.byType(BrailleKeyboard),
        );
        keyboard.onSubmitPattern!(_patternForCell(cell));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final assessment = store.recordedEvents.firstWhere(
        (event) =>
            event['exercise_id'] ==
            'lesson-assessment-en-sentence-personal-name',
      );
      expect(assessment['exercise_type'], 'sentence_transcription');
      expect(assessment['expected_response']['text'], 'My name is Namit.');
      expect(assessment['expected_response']['cells'], cells);
      expect(assessment['submitted_response']['cells'], cells);
      expect(find.text('I read Braille.'), findsOneWidget);
    },
  );

  testWidgets('stale resume state cannot skip the first sentence', (
    tester,
  ) async {
    const account = LearnerAccount(
      learnerId: 'resume-sentence-learner',
      learnerCode: '654321',
      name: 'Sam',
      preferredLanguage: 'English',
    );
    final store = _MemoryProgressStore(
      _sentencePrerequisites(),
      resumeState: const {
        'language': 'en',
        'chapter': 4,
        'lesson_item': 1,
        'word_lesson_index': 4,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ResonantHome(
          learnerAccount: account,
          accountStorage: _EmptyAccountStorage(),
          onboardingProgress: _CompletedOnboarding(),
          lessonProgressStore: store,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('My name is Sam.'), findsOneWidget);
    expect(find.text('I read Braille.'), findsNothing);
  });
}
