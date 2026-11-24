import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/learning/adaptive_decision_controller.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';
import 'package:resonant_braille/learning/lesson_progress_store.dart';

void main() {
  const controller = AdaptiveDecisionController();

  AdaptiveAssessmentSnapshot snapshot({
    String submissionId = 'submission-1',
    bool correct = false,
    int attemptNumber = 1,
    bool hintUsed = false,
    bool prerequisiteSatisfied = true,
    int remediationCycles = 0,
    bool isReassessment = false,
    List<Map<String, dynamic>> history = const [],
  }) => AdaptiveAssessmentSnapshot(
    submissionId: submissionId,
    assessmentKey: 'en-letter-a-v1',
    languageCode: 'en',
    lessonId: 'letter-a',
    skillId: 'english-letter-a',
    correct: correct,
    attemptNumber: attemptNumber,
    hintUsed: hintUsed,
    expectedCells: const [1],
    submittedCells: correct ? const [1] : const [3],
    prerequisiteSatisfied: prerequisiteSatisfied,
    learningObjective: 'Recognize letter a.',
    remediationCycles: remediationCycles,
    isReassessment: isReassessment,
    history: history,
  );

  test('weak learner receives explainable focused remediation', () {
    final decision = controller.deriveOffline(snapshot());
    expect(decision.action, AdaptiveDecisionAction.remediate);
    expect(decision.recommendedLessonId, 'letter-a');
    expect(decision.evidence['decision_method'], 'deterministic_rules');
    expect(decision.evidence['wrong_answers'], 1);
    expect(decision.remediationCycle, 1);
  });

  test(
    'strong first-attempt learner advances without bypassing validation',
    () {
      final decision = controller.deriveOffline(snapshot(correct: true));
      expect(decision.action, AdaptiveDecisionAction.advance);
      expect(decision.reason, contains('prerequisite'));
    },
  );

  test(
    'repeated identical dot error is called out in remediation evidence',
    () {
      final decision = controller.deriveOffline(
        snapshot(
          submissionId: 'submission-2',
          history: const [
            {
              'submission_id': 'submission-1',
              'sync_kind': 'assessment',
              'skill_id': 'english-letter-a',
              'outcome': 'incorrect',
              'expected_response': {
                'cells': [1],
              },
              'submitted_response': {
                'cells': [3],
              },
            },
          ],
        ),
      );
      expect(decision.action, AdaptiveDecisionAction.remediate);
      expect(decision.evidence['repeated_dot_confusion'], 2);
      expect(decision.reason, contains('2 times'));
    },
  );

  test('automatic remediation is capped and becomes reassessment', () {
    final decision = controller.deriveOffline(snapshot(remediationCycles: 2));
    expect(decision.action, AdaptiveDecisionAction.reassess);
    expect(decision.reason, contains('will not be assigned again'));
  });

  test(
    'validated backend question must match authoritative Braille mapping',
    () {
      const question = AdaptivePracticeQuestion(
        questionInstanceId: '11111111-1111-4111-8111-111111111111',
        questionId: 'question-a-v1',
        skillId: 'english-letter-a',
        lessonId: 'letter-a',
        language: 'English',
        difficulty: 2,
        questionType: 'letter_recognition',
        questionText: 'Which English letter uses dot 1?',
        options: ['a', 'b', 'c'],
        answer: 'a',
        expectedCells: [1],
        source: 'validated_bank',
        questionVersion: 'adaptive-bank-v1',
        mappingVersion: 'ueb-subset-v1',
        curriculumVersion: 'flutter-catalog-v1',
        validationStatus: 'validated',
      );
      final decision = controller
          .deriveOffline(snapshot())
          .copyWith(
            source: AdaptiveDecisionSource.mlAssistedBackend,
            evidence: const {
              'model_status': 'qualified_prediction_used',
              'probability_incorrect': 0.81,
            },
            nextQuestion: question,
          );

      final accepted = controller.resolve(
        decision: decision,
        languageCode: 'en',
        chapters: LessonCatalog.english,
        currentChapterIndex: 1,
        currentLessonIndex: 0,
        completedExerciseIds: const {},
      );
      expect(accepted.isReady, isTrue);
      expect(accepted.decision.nextQuestion, same(question));
      expect(
        accepted.decision.evidence['question_validation_status'],
        'validated_by_flutter',
      );
      expect(
        accepted.decision.learnerModelStatusMessage,
        isNot(contains('0.81')),
      );

      final rejected = controller.resolve(
        decision: decision.copyWith(
          nextQuestion: const AdaptivePracticeQuestion(
            questionInstanceId: '22222222-2222-4222-8222-222222222222',
            questionId: 'question-a-invalid',
            skillId: 'english-letter-a',
            lessonId: 'letter-a',
            language: 'English',
            difficulty: 2,
            questionType: 'letter_recognition',
            questionText: 'Which English letter uses dot 3?',
            options: ['a', 'b'],
            answer: 'a',
            expectedCells: [3],
            source: 'validated_bank',
            questionVersion: 'adaptive-bank-v1',
            mappingVersion: 'ueb-subset-v1',
            curriculumVersion: 'flutter-catalog-v1',
            validationStatus: 'validated',
          ),
        ),
        languageCode: 'en',
        chapters: LessonCatalog.english,
        currentChapterIndex: 1,
        currentLessonIndex: 0,
        completedExerciseIds: const {},
      );
      expect(rejected.isReady, isTrue);
      expect(rejected.decision.nextQuestion, isNull);
      expect(
        rejected.decision.evidence['question_fallback_reason'],
        'question_braille_mapping_mismatch',
      );
    },
  );

  test('deterministic AI rejection fallback remains a valid question', () {
    const question = AdaptivePracticeQuestion(
      questionInstanceId: '33333333-3333-4333-8333-333333333333',
      questionId: 'question-a-fallback',
      skillId: 'english-letter-a',
      lessonId: 'letter-a',
      language: 'English',
      difficulty: 1,
      questionType: 'letter_recognition',
      questionText: 'Choose the English letter represented by dot 1.',
      options: ['a', 'b'],
      answer: 'a',
      expectedCells: [1],
      source: 'deterministic_fallback',
      questionVersion: 'adaptive-bank-v1',
      mappingVersion: 'ueb-subset-v1',
      curriculumVersion: 'flutter-catalog-v1',
      validationStatus: 'fallback_after_rejection',
    );
    expect(question.isValid, isTrue);
  });

  test('successful post-remediation reassessment advances', () {
    final decision = controller.deriveOffline(
      snapshot(correct: true, isReassessment: true, remediationCycles: 1),
    );
    expect(decision.action, AdaptiveDecisionAction.advance);
    expect(decision.reason, contains('after remediation'));
  });

  test('advancement remains blocked until the assessed lesson is complete', () {
    final decision = controller.deriveOffline(snapshot(correct: true));
    final blocked = controller.resolve(
      decision: decision,
      languageCode: 'en',
      chapters: LessonCatalog.english,
      currentChapterIndex: 1,
      currentLessonIndex: 0,
      completedExerciseIds: const {},
    );
    expect(blocked.status, AdaptiveResolutionStatus.blocked);

    final ready = controller.resolve(
      decision: decision,
      languageCode: 'en',
      chapters: LessonCatalog.english,
      currentChapterIndex: 1,
      currentLessonIndex: 0,
      completedExerciseIds: const {'letter-a'},
    );
    expect(ready.isReady, isTrue);
  });

  test('decision inbox suppresses duplicate active remediation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'resonant-adaptive-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LessonProgressStore(
      File('${directory.path}${Platform.pathSeparator}progress.json'),
    );
    final first = controller.deriveOffline(snapshot());
    final duplicate = controller.deriveOffline(
      snapshot(submissionId: 'submission-2'),
    );
    await store.saveAdaptiveDecision(first);
    final savedDuplicate = await store.saveAdaptiveDecision(duplicate);

    expect(savedDuplicate.status, AdaptiveDecisionStatus.superseded);
    final active = (await store.readAdaptiveDecisions())
        .where((decision) => decision.isActive)
        .toList();
    expect(active, hasLength(1));
    expect(active.single.decisionId, first.decisionId);
  });

  test(
    'failed capped reassessment is remembered to prevent auto loops',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'resonant-adaptive-cap-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LessonProgressStore(
        File('${directory.path}${Platform.pathSeparator}progress.json'),
      );
      final reassess = controller
          .deriveOffline(snapshot(remediationCycles: 2))
          .markCompleted(succeeded: false);
      await store.saveAdaptiveDecision(reassess);

      expect(
        await store.hasFailedCappedReassessment('english-letter-a'),
        isTrue,
      );
    },
  );
}
