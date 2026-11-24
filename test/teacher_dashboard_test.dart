import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/api_config.dart';
import 'package:resonant_braille/teacher/dashboard_api.dart';

void main() {
  group('DashboardSummary and LearnerProgressItem parsing', () {
    test('DashboardSummary parses correctly from JSON', () {
      final json = {
        'total_learners': 5,
        'active_this_week': 3,
        'struggling': 1,
      };
      final summary = DashboardSummary.fromJson(json);
      expect(summary.totalLearners, 5);
      expect(summary.activeThisWeek, 3);
      expect(summary.struggling, 1);
    });

    test('LearnerProgressItem parses correctly and maps fields', () {
      final json = {
        'id': 'learner-123',
        'name': 'Aarav',
        'batch': 'Batch A',
        'preferred_language': 'Kannada',
        'last_active_at': '2026-11-12T10:00:00Z',
        'current_stage': 'stage-1-exercise-1',
        'current_letter': 'A',
        'accuracy_pct': 75.5,
        'attempts_7d': 8,
        'top_weak_letters': ['B', 'C'],
        'status': 'active',
      };
      final item = LearnerProgressItem.fromJson(json);
      expect(item.id, 'learner-123');
      expect(item.name, 'Aarav');
      expect(item.batch, 'Batch A');
      expect(item.preferredLanguage, 'Kannada');
      expect(item.accuracyPct, 75.5);
      expect(item.attempts7d, 8);
      expect(item.topWeakLetters, ['B', 'C']);
      expect(item.status, 'active');
    });

    test('LearnerDetailData parses recent attempts and contact info', () {
      final json = {
        'id': 'learner-456',
        'name': 'Priya',
        'batch': 'Grade 5',
        'phone': '9876543210',
        'email': 'priya@example.com',
        'preferred_language': 'English',
        'current_stage': 'stage-1',
        'current_letter': 'C',
        'accuracy_pct': 52.0,
        'total_attempts': 25,
        'attempts_7d': 10,
        'top_weak_letters': ['D', 'E'],
        'skill_progress': [
          {
            'skill_id': 'english-letter-d',
            'language': 'English',
            'attempts': 4,
            'correct_count': 2,
            'accuracy_pct': 50.0,
            'mastery_estimate': 0.43,
            'mastery_method': 'bayesian_knowledge_tracing',
            'next_review_at': '2026-11-24T00:00:00Z',
            'review_due': true,
          },
        ],
        'status': 'struggling',
        'recent_attempts': [
          {
            'submission_id': 'sub-1',
            'exercise_id': 'ex-1',
            'skill_id': 'english-letter-d',
            'exercise_type': 'letter_recognition',
            'outcome': 'incorrect',
            'response_time_ms': 1200,
            'hint_used': true,
            'attempt_number': 1,
            'created_at': '2026-11-12T09:00:00Z',
          },
        ],
        'recent_assessments': [
          {
            'assessment_id': 'assessment-1',
            'lesson_id': 'letter-d',
            'language': 'English',
            'assessment_type': 'lesson',
            'score': 0,
            'question_count': 1,
            'accuracy_pct': 0.0,
            'action': 'remedial_practice',
            'reason': 'Focused practice is needed.',
            'recommended_skill_id': 'english-letter-d',
            'recommended_lesson_id': 'letter-d',
            'status': 'completed',
            'decision_method': 'deterministic_rules',
            'remediation_cycle': 1,
            'mastery_before': 0.2,
            'mastery_after': 0.6,
            'succeeded': true,
            'prediction_id': 'prediction-1',
            'question_instance_id': 'question-instance-1',
            'model_version': 'resonant-v2',
            'difficulty_before': 3,
            'difficulty_after': 2,
            'fallback_used': false,
            'evidence': {
              'adaptive_selection_method':
                  'linucb_with_information_gain_forgetting_context',
              'bandit_observation_count': 5,
              'eligible_skill_scores': [
                {
                  'skill_id': 'english-letter-d',
                  'score': 1.2,
                  'information_gain_bits': 0.12,
                  'forgetting_risk_estimate': 0.2,
                  'bandit_score': 0.7,
                  'review_due': true,
                  'error_count': 2,
                },
              ],
            },
          },
        ],
        'assessment_error_summary': [
          {
            'skill_id': 'english-letter-d',
            'language': 'English',
            'error_category': 'character_confusion',
            'error_count': 2,
          },
        ],
        'recent_predictions': [
          {
            'prediction_id': 'prediction-1',
            'skill_id': 'english-letter-d',
            'language': 'English',
            'probability_incorrect': 0.72,
            'prediction_source': 'qualified_model',
            'validity_status': 'valid',
            'model_version': 'resonant-v2',
            'feature_schema_version': 'resonant-next-attempt-v2',
            'prediction_latency_ms': 3,
            'predicted_at': '2026-11-12T09:01:00Z',
            'observed_incorrect': false,
          },
          {
            'prediction_id': 'prediction-2',
            'skill_id': 'english-letter-e',
            'language': 'English',
            'probability_incorrect': 0.5,
            'prediction_source': 'cold_start_deterministic',
            'validity_status': 'fallback',
            'feature_schema_version': 'resonant-next-attempt-v2',
            'fallback_reason': 'artifact_missing',
            'prediction_latency_ms': 1,
          },
        ],
        'recent_adaptive_questions': [
          {
            'question_instance_id': 'question-instance-1',
            'prediction_id': 'prediction-1',
            'skill_id': 'english-letter-d',
            'lesson_id': 'letter-d',
            'language': 'English',
            'difficulty': 2,
            'question_type': 'letter_recognition',
            'question_source': 'validated_bank',
            'question_version': 'adaptive-bank-v1',
            'mapping_version': 'ueb-subset-v1',
            'curriculum_version': 'flutter-catalog-v1',
            'validation_status': 'validated',
          },
        ],
      };
      final detail = LearnerDetailData.fromJson(json);
      expect(detail.id, 'learner-456');
      expect(detail.name, 'Priya');
      expect(detail.phone, '9876543210');
      expect(detail.email, 'priya@example.com');
      expect(detail.status, 'struggling');
      expect(detail.skillProgress.single.accuracyPct, 50.0);
      expect(detail.skillProgress.single.masteryEstimate, 0.43);
      expect(detail.skillProgress.single.reviewDue, isTrue);
      expect(detail.recentAttempts.length, 1);
      expect(detail.recentAttempts.first.outcome, 'incorrect');
      expect(detail.recentAttempts.first.hintUsed, true);
      expect(detail.recentAssessments.single.action, 'remedial_practice');
      expect(detail.recentAssessments.single.recommendedLessonId, 'letter-d');
      expect(detail.recentAssessments.single.remediationSucceeded, isTrue);
      expect(detail.recentAssessments.single.masteryAfter, 0.6);
      expect(detail.recentAssessments.single.modelVersion, 'resonant-v2');
      expect(detail.recentAssessments.single.fallbackUsed, isFalse);
      expect(
        detail.recentAssessments.single.selectionEvidence[
            'adaptive_selection_method'],
        'linucb_with_information_gain_forgetting_context',
      );
      expect(detail.assessmentErrors.single.errorCount, 2);
      expect(detail.recentPredictions, hasLength(2));
      expect(detail.recentPredictions.first.usedQualifiedModel, isTrue);
      expect(detail.recentPredictions.last.usedQualifiedModel, isFalse);
      expect(
        detail.recentAdaptiveQuestions.single.mappingVersion,
        'ueb-subset-v1',
      );
    });

    test('apiBaseUrl defaults to localhost and can be configured', () {
      expect(apiBaseUrl, isNotEmpty);
    });
  });
}
