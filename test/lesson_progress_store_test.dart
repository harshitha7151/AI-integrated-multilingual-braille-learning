import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonant_braille/learning/adaptive_decision_controller.dart';
import 'package:resonant_braille/learning/learner_account_store.dart';
import 'package:resonant_braille/learning/lesson_progress_store.dart';

void main() {
  late Directory directory;
  late File file;
  late LessonProgressStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('resonant-progress-');
    file = File('${directory.path}${Platform.pathSeparator}progress.json');
    store = LessonProgressStore(file);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('lesson attempts survive reopening the local store', () async {
    await store.record(
      exerciseId: 'letter-a',
      skillId: 'english-letter-a',
      exerciseType: 'letter_recognition',
      correct: false,
      attemptNumber: 1,
      hintUsed: true,
      responseTimeMs: 1200,
    );
    await store.record(
      exerciseId: 'letter-a',
      skillId: 'english-letter-a',
      exerciseType: 'letter_recognition',
      correct: true,
      attemptNumber: 2,
      hintUsed: true,
      responseTimeMs: 1800,
    );

    final reopened = LessonProgressStore(file);
    final events = await reopened.readEvents();
    expect(events, hasLength(2));
    expect(events[0]['outcome'], 'incorrect');
    expect(events[1]['outcome'], 'correct');
    expect(events[0]['submission_id'], isNot(events[1]['submission_id']));
    expect(events.every((event) => event['synced_at'] == null), isTrue);
    expect(events[1]['attempt_number'], 2);
  });

  test(
    'paused word assessment survives resume writes and can be cleared',
    () async {
      const paused = {
        'assessment_submission_id': 'attempt-1',
        'stage_id': 'a-e',
        'language': 'en',
        'word_index': 1,
        'word': 'CAT',
        'letter': 'T',
      };
      await store.saveResumeState(
        languageCode: 'en',
        chapter: 1,
        lessonItem: 4,
        wordLessonIndex: 0,
      );
      await store.savePausedWordAssessment(
        languageCode: 'en',
        pausedAssessment: paused,
      );
      await store.saveResumeState(
        languageCode: 'en',
        chapter: 1,
        lessonItem: 19,
        wordLessonIndex: 0,
      );
      expect(
        (await store.readResumeStateFor('en'))['paused_word_assessment'],
        paused,
      );

      await store.savePausedWordAssessment(
        languageCode: 'en',
        pausedAssessment: null,
      );
      expect(
        (await store.readResumeStateFor(
          'en',
        )).containsKey('paused_word_assessment'),
        isFalse,
      );
    },
  );

  test(
    'incorrect and correct word submissions stay separate through retries',
    () async {
      final wrongId = await store.record(
        exerciseId: 'word-cat',
        skillId: 'english-word-writing-test',
        exerciseType: 'transcription',
        correct: false,
        attemptNumber: 1,
        hintUsed: false,
        responseTimeMs: 1000,
        language: 'English',
        expectedResponse: const {
          'text': 'CAT',
          'cells': [5, 1, 20],
        },
        submittedResponse: const {
          'cells': [5, 1, 16],
          'skill_observations': [
            {'character': 'c', 'skill_id': 'english-letter-c', 'correct': true},
            {'character': 'a', 'skill_id': 'english-letter-a', 'correct': true},
            {
              'character': 't',
              'skill_id': 'english-letter-t',
              'correct': false,
            },
          ],
        },
      );
      final correctId = await store.record(
        exerciseId: 'word-cat',
        skillId: 'english-word-writing-test',
        exerciseType: 'transcription',
        correct: true,
        attemptNumber: 2,
        hintUsed: false,
        responseTimeMs: 1600,
        language: 'English',
        expectedResponse: const {
          'text': 'CAT',
          'cells': [5, 1, 20],
        },
        submittedResponse: const {
          'cells': [5, 1, 20],
          'skill_observations': [
            {'character': 'c', 'skill_id': 'english-letter-c', 'correct': true},
            {'character': 'a', 'skill_id': 'english-letter-a', 'correct': true},
            {'character': 't', 'skill_id': 'english-letter-t', 'correct': true},
          ],
        },
      );
      expect(wrongId, isNot(correctId));

      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        final event = jsonDecode(request.body) as Map<String, dynamic>;
        expect(event['learner_code'], '012345');
        expect(event['submission_id'], isNotEmpty);
        expect(event['submitted_response']['skill_observations'], hasLength(3));
        return requests == 1
            ? http.Response('{}', 503)
            : http.Response('{}', 201);
      });
      store = LessonProgressStore(
        file,
        httpClient: client,
        baseUri: Uri.parse('http://resonant.test'),
      );
      final accountStore = LearnerAccountStore(
        File('${directory.path}${Platform.pathSeparator}account.json'),
      );
      await accountStore.save(
        const LearnerAccount(
          learnerId: '11111111-1111-1111-1111-111111111111',
          learnerCode: '012345',
          name: 'Learner',
        ),
      );

      expect(await store.syncPending(accountStore: accountStore), 1);
      final afterFailure = await store.readEvents();
      expect(afterFailure, hasLength(2));
      expect(afterFailure[0]['submission_id'], wrongId);
      expect(afterFailure[0]['synced_at'], isNull);
      expect(afterFailure[1]['submission_id'], correctId);
      expect(afterFailure[1]['outcome'], 'correct');
      expect(await store.syncPending(accountStore: accountStore), 1);
      final afterRetry = await store.readEvents();
      expect(afterRetry, hasLength(2));
      expect(afterRetry.every((event) => event['synced_at'] != null), isTrue);
      expect(requests, 3);
    },
  );

  test('word mastery attempt groups persist for retry-safe scoring', () async {
    await store.record(
      exerciseId: 'word-chapter-lesson-5-cat',
      skillId: 'english-word-word-mastery',
      exerciseType: 'braille_writing',
      correct: true,
      attemptNumber: 5,
      hintUsed: false,
      responseTimeMs: 3000,
      groupId: 'word-mastery-round-1',
    );

    final events = await LessonProgressStore(file).readEvents();
    expect(events.single['group_id'], 'word-mastery-round-1');
    expect(events.single['exercise_id'], 'word-chapter-lesson-5-cat');
  });

  test(
    'resume location is preserved independently for each language',
    () async {
      await store.saveResumeState(
        languageCode: 'en',
        chapter: 1,
        lessonItem: 5,
        wordLessonIndex: 2,
      );
      await store.saveResumeState(
        languageCode: 'hi',
        chapter: 1,
        lessonItem: 12,
        wordLessonIndex: 0,
      );
      await store.saveResumeState(
        languageCode: 'kn',
        chapter: 2,
        lessonItem: 3,
        wordLessonIndex: 0,
      );

      final reopened = LessonProgressStore(file);
      expect((await reopened.readResumeStateFor('en'))['lesson_item'], 5);
      expect((await reopened.readResumeStateFor('hi'))['lesson_item'], 12);
      expect((await reopened.readResumeStateFor('kn'))['chapter'], 2);
    },
  );

  test(
    'pending attempts remain local until a learner account exists',
    () async {
      await store.record(
        exerciseId: 'letter-a',
        skillId: 'english-letter-a',
        exerciseType: 'letter_recognition',
        correct: true,
        attemptNumber: 1,
        hintUsed: false,
        responseTimeMs: 900,
      );

      final accountStore = LearnerAccountStore(
        File('${directory.path}${Platform.pathSeparator}account.json'),
      );
      expect(await store.syncPending(accountStore: accountStore), 0);
      expect((await store.readEvents()).single['synced_at'], isNull);
    },
  );

  test('legacy practice sync includes learner ownership proof', () async {
    late Map<String, dynamic> uploaded;
    final client = MockClient((request) async {
      uploaded = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/practice/attempts');
      return http.Response('{}', 201);
    });
    store = LessonProgressStore(
      file,
      httpClient: client,
      baseUri: Uri.parse('http://resonant.test'),
    );
    await store.record(
      exerciseId: 'letter-a',
      skillId: 'english-letter-a',
      exerciseType: 'letter_recognition',
      correct: true,
      attemptNumber: 1,
      hintUsed: false,
      responseTimeMs: 900,
      learnerId: '11111111-1111-1111-1111-111111111111',
    );
    final accountStore = LearnerAccountStore(
      File('${directory.path}${Platform.pathSeparator}account.json'),
    );
    await accountStore.save(
      const LearnerAccount(
        learnerId: '11111111-1111-1111-1111-111111111111',
        learnerCode: '012345',
        name: 'Learner',
      ),
    );

    expect(await store.syncPending(accountStore: accountStore), 1);
    expect(uploaded['learner_id'], '11111111-1111-1111-1111-111111111111');
    expect(uploaded['learner_code'], '012345');
  });

  test(
    'lesson assessments sync with learner proof and structured responses',
    () async {
      late Uri requestedUri;
      late Map<String, dynamic> uploaded;
      final client = MockClient((request) async {
        requestedUri = request.url;
        uploaded = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 201);
      });
      store = LessonProgressStore(
        file,
        httpClient: client,
        baseUri: Uri.parse('http://resonant.test'),
      );
      await store.record(
        exerciseId: 'lesson-assessment-letter-a',
        skillId: 'english-letter-a',
        exerciseType: 'quiz',
        correct: true,
        attemptNumber: 1,
        hintUsed: false,
        responseTimeMs: 900,
        learnerId: '11111111-1111-1111-1111-111111111111',
        assessmentKey: 'en-letter-a-v1',
        lessonId: 'letter-a',
        questionText: 'Which letter uses dot 1?',
        options: const ['a', 'b', 'c', 'd'],
        learningObjective: 'Recognize the uncontracted English letter a.',
        expectedResponse: const {
          'choice': 'a',
          'cells': [1],
        },
        submittedResponse: const {
          'choice': 'a',
          'cells': [1],
        },
      );
      final accountStore = LearnerAccountStore(
        File('${directory.path}${Platform.pathSeparator}account.json'),
      );
      await accountStore.save(
        const LearnerAccount(
          learnerId: '11111111-1111-1111-1111-111111111111',
          learnerCode: '012345',
          name: 'Learner',
        ),
      );

      expect(await store.syncPending(accountStore: accountStore), 1);
      expect(
        requestedUri.path,
        '/learners/11111111-1111-1111-1111-111111111111/assessments',
      );
      expect(uploaded['learner_code'], '012345');
      expect(uploaded['lesson_id'], 'letter-a');
      final questions = uploaded['questions'] as List<dynamic>;
      expect(questions.single['expected_response']['cells'], [1]);
      expect((await store.readEvents()).single['synced_at'], isNotNull);
    },
  );

  test(
    'assessment decisions persist and lifecycle status synchronizes',
    () async {
      var lifecycleRequests = 0;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/assessments')) {
          return http.Response(
            jsonEncode({
              'submission_id': body['submission_id'],
              'assessment_key': body['assessment_key'],
              'lesson_id': body['lesson_id'],
              'language': body['language'],
              'decision': {
                'decision_id': '22222222-2222-4222-8222-222222222222',
                'action': 'remedial_practice',
                'recommended_skill_id': 'english-letter-a',
                'recommended_lesson_id': 'letter-a',
                'reason': 'Focused practice is required.',
                'evidence': {
                  'decision_method': 'deterministic_rules',
                  'remediation_cycle': 1,
                },
                'confidence': 0.7,
                'expected_learning_objective': 'Recognize letter a.',
                'status': 'pending',
                'remediation_cycle': 1,
              },
            }),
            201,
          );
        }
        if (request.url.path.contains('/adaptive-decisions/')) {
          lifecycleRequests++;
          expect(body['learner_code'], '012345');
          expect(body['status'], 'completed');
          expect(body['succeeded'], isTrue);
          return http.Response('{}', 200);
        }
        return http.Response('{}', 404);
      });
      store = LessonProgressStore(
        file,
        httpClient: client,
        baseUri: Uri.parse('http://resonant.test'),
      );
      await store.record(
        exerciseId: 'lesson-assessment-letter-a',
        skillId: 'english-letter-a',
        exerciseType: 'quiz',
        correct: false,
        attemptNumber: 1,
        hintUsed: false,
        responseTimeMs: 900,
        assessmentKey: 'en-letter-a-v1',
        lessonId: 'letter-a',
        questionText: 'Which letter uses dot 1?',
        options: const ['a', 'b', 'c', 'd'],
        learningObjective: 'Recognize letter a.',
        expectedResponse: const {
          'choice': 'a',
          'cells': [1],
        },
        submittedResponse: const {
          'choice': 'b',
          'cells': [3],
        },
      );
      final accountStore = LearnerAccountStore(
        File('${directory.path}${Platform.pathSeparator}account.json'),
      );
      await accountStore.save(
        const LearnerAccount(
          learnerId: '11111111-1111-1111-1111-111111111111',
          learnerCode: '012345',
          name: 'Learner',
        ),
      );

      expect(await store.syncPending(accountStore: accountStore), 1);
      final decision = (await store.readAdaptiveDecisions()).single;
      expect(decision.source, AdaptiveDecisionSource.deterministicBackend);
      expect(decision.action, AdaptiveDecisionAction.remediate);
      await store.markAdaptiveDecisionCompleted(
        decision.decisionId,
        succeeded: true,
      );

      expect(await store.syncPending(accountStore: accountStore), 0);
      expect(lifecycleRequests, 1);
      expect(
        (await store.readAdaptiveDecisions()).single.lifecycleSyncedAt,
        isNotNull,
      );
    },
  );

  test(
    'direct assessment synchronization returns the hybrid decision and question',
    () async {
      late Map<String, dynamic> uploaded;
      final client = MockClient((request) async {
        uploaded = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'submission_id': uploaded['submission_id'],
            'assessment_key': uploaded['assessment_key'],
            'lesson_id': uploaded['lesson_id'],
            'language': uploaded['language'],
            'decision': {
              'decision_id': '44444444-4444-4444-8444-444444444444',
              'action': 'reinforce',
              'recommended_skill_id': 'english-letter-a',
              'recommended_lesson_id': 'letter-a',
              'reason':
                  'A different validated exercise will reinforce the skill.',
              'evidence': {
                'decision_method': 'hybrid_ml_rules',
                'model_status': 'qualified_prediction_used',
                'next_question': {
                  'question_instance_id':
                      '55555555-5555-4555-8555-555555555555',
                  'question_id': 'adaptive-a-v2',
                  'skill_id': 'english-letter-a',
                  'lesson_id': 'letter-a',
                  'language': 'English',
                  'difficulty': 2,
                  'question_type': 'letter_recognition',
                  'question_text': 'Choose the letter represented by dot 1.',
                  'options': ['b', 'a', 'c'],
                  'answer': 'a',
                  'expected_response': {
                    'choice': 'a',
                    'cells': [1],
                  },
                  'question_source': 'deterministic_fallback',
                  'question_version': 'adaptive-bank-v1',
                  'mapping_version': 'ueb-subset-v1',
                  'curriculum_version': 'flutter-catalog-v1',
                  'validation_status': 'fallback_after_rejection',
                },
              },
              'confidence': 0.7,
              'expected_learning_objective': 'Recognize letter a.',
              'decision_method': 'hybrid_ml_rules',
              'status': 'pending',
              'remediation_cycle': 1,
            },
          }),
          201,
        );
      });
      store = LessonProgressStore(
        file,
        httpClient: client,
        baseUri: Uri.parse('http://resonant.test'),
      );
      final submissionId = await store.record(
        exerciseId: 'lesson-assessment-letter-a',
        skillId: 'english-letter-a',
        exerciseType: 'quiz',
        correct: true,
        attemptNumber: 1,
        hintUsed: false,
        responseTimeMs: 700,
        assessmentKey: 'en-letter-a-v1',
        lessonId: 'letter-a',
        questionId: 'adaptive-a-v1',
        questionInstanceId: '66666666-6666-4666-8666-666666666666',
        questionSource: 'validated_bank',
        questionVersion: 'adaptive-bank-v1',
        mappingVersion: 'ueb-subset-v1',
        curriculumVersion: 'flutter-catalog-v1',
        interventionType: 'reinforce',
        feedbackType: 'verified_correct',
        questionText: 'Which letter uses dot 1?',
        options: const ['a', 'b'],
        learningObjective: 'Recognize letter a.',
        expectedResponse: const {
          'choice': 'a',
          'cells': [1],
        },
        submittedResponse: const {
          'choice': 'a',
          'cells': [1],
        },
      );
      final accountStore = LearnerAccountStore(
        File('${directory.path}${Platform.pathSeparator}direct-account.json'),
      );
      await accountStore.save(
        const LearnerAccount(
          learnerId: '11111111-1111-1111-1111-111111111111',
          learnerCode: '012345',
          name: 'Learner',
        ),
      );

      final decision = await store.syncAssessmentDecision(
        submissionId: submissionId,
        accountStore: accountStore,
      );

      expect(decision, isNotNull);
      expect(decision!.source, AdaptiveDecisionSource.mlAssistedBackend);
      expect(decision.nextQuestion?.isValid, isTrue);
      expect(
        decision.nextQuestion?.validationStatus,
        'fallback_after_rejection',
      );
      expect(uploaded['questions'].single['question_id'], 'adaptive-a-v1');
      expect(
        uploaded['questions'].single['question_instance_id'],
        '66666666-6666-4666-8666-666666666666',
      );
      expect(uploaded['questions'].single['intervention_type'], 'reinforce');
      expect((await store.readEvents()).single['synced_at'], isNotNull);
    },
  );
}
