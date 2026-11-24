import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/api_config.dart';

class DashboardSummary {
  final int totalLearners;
  final int activeThisWeek;
  final int struggling;

  const DashboardSummary({
    required this.totalLearners,
    required this.activeThisWeek,
    required this.struggling,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        totalLearners: json['total_learners'] as int? ?? 0,
        activeThisWeek: json['active_this_week'] as int? ?? 0,
        struggling: json['struggling'] as int? ?? 0,
      );
}

class LearnerProgressItem {
  final String id;
  final String name;
  final String? batch;
  final String preferredLanguage;
  final String? lastActiveAt;
  final String currentStage;
  final String currentLetter;
  final double accuracyPct;
  final int attempts7d;
  final List<String> topWeakLetters;
  final String status; // 'active', 'inactive', 'struggling'

  const LearnerProgressItem({
    required this.id,
    required this.name,
    this.batch,
    this.preferredLanguage = 'Unknown',
    this.lastActiveAt,
    required this.currentStage,
    required this.currentLetter,
    required this.accuracyPct,
    required this.attempts7d,
    required this.topWeakLetters,
    required this.status,
  });

  factory LearnerProgressItem.fromJson(Map<String, dynamic> json) =>
      LearnerProgressItem(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        batch: json['batch'] as String?,
        preferredLanguage:
            json['preferred_language'] as String? ?? 'Unknown',
        lastActiveAt: json['last_active_at'] as String?,
        currentStage: json['current_stage'] as String? ?? '',
        currentLetter: json['current_letter'] as String? ?? '',
        accuracyPct: (json['accuracy_pct'] as num?)?.toDouble() ?? 0.0,
        attempts7d: json['attempts_7d'] as int? ?? 0,
        topWeakLetters:
            (json['top_weak_letters'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        status: json['status'] as String? ?? 'inactive',
      );
}

class TeacherDashboardData {
  final DashboardSummary summary;
  final List<LearnerProgressItem> learners;

  const TeacherDashboardData({required this.summary, required this.learners});

  factory TeacherDashboardData.fromJson(Map<String, dynamic> json) =>
      TeacherDashboardData(
        summary: DashboardSummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? {},
        ),
        learners:
            (json['learners'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(LearnerProgressItem.fromJson)
                .toList() ??
            const [],
      );
}

class AttemptRecord {
  final String submissionId;
  final String exerciseId;
  final String skillId;
  final String exerciseType;
  final String outcome;
  final int responseTimeMs;
  final bool hintUsed;
  final int attemptNumber;
  final String? createdAt;

  const AttemptRecord({
    required this.submissionId,
    required this.exerciseId,
    required this.skillId,
    required this.exerciseType,
    required this.outcome,
    required this.responseTimeMs,
    required this.hintUsed,
    required this.attemptNumber,
    this.createdAt,
  });

  factory AttemptRecord.fromJson(Map<String, dynamic> json) => AttemptRecord(
    submissionId: json['submission_id'] as String? ?? '',
    exerciseId: json['exercise_id'] as String? ?? '',
    skillId: json['skill_id'] as String? ?? '',
    exerciseType: json['exercise_type'] as String? ?? '',
    outcome: json['outcome'] as String? ?? '',
    responseTimeMs: json['response_time_ms'] as int? ?? 0,
    hintUsed: json['hint_used'] as bool? ?? false,
    attemptNumber: json['attempt_number'] as int? ?? 1,
    createdAt: json['created_at'] as String?,
  );
}

class AssessmentRecord {
  final String assessmentId;
  final String lessonId;
  final String language;
  final String assessmentType;
  final int score;
  final int questionCount;
  final double accuracyPct;
  final String? completedAt;
  final String action;
  final String reason;
  final String recommendedSkillId;
  final String recommendedLessonId;
  final String decisionStatus;
  final String decisionMethod;
  final int remediationCycle;
  final double? masteryBefore;
  final double? masteryAfter;
  final bool? remediationSucceeded;
  final String? predictionId;
  final String? questionInstanceId;
  final String? modelVersion;
  final int? difficultyBefore;
  final int? difficultyAfter;
  final bool fallbackUsed;
  final Map<String, dynamic> selectionEvidence;

  const AssessmentRecord({
    required this.assessmentId,
    required this.lessonId,
    required this.language,
    required this.assessmentType,
    required this.score,
    required this.questionCount,
    required this.accuracyPct,
    this.completedAt,
    required this.action,
    required this.reason,
    required this.recommendedSkillId,
    required this.recommendedLessonId,
    required this.decisionStatus,
    required this.decisionMethod,
    required this.remediationCycle,
    this.masteryBefore,
    this.masteryAfter,
    this.remediationSucceeded,
    this.predictionId,
    this.questionInstanceId,
    this.modelVersion,
    this.difficultyBefore,
    this.difficultyAfter,
    required this.fallbackUsed,
    required this.selectionEvidence,
  });

  factory AssessmentRecord.fromJson(Map<String, dynamic> json) =>
      AssessmentRecord(
        assessmentId: json['assessment_id'] as String? ?? '',
        lessonId: json['lesson_id'] as String? ?? '',
        language: json['language'] as String? ?? '',
        assessmentType: json['assessment_type'] as String? ?? 'lesson',
        score: json['score'] as int? ?? 0,
        questionCount: json['question_count'] as int? ?? 0,
        accuracyPct: (json['accuracy_pct'] as num?)?.toDouble() ?? 0.0,
        completedAt: json['completed_at'] as String?,
        action: json['action'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        recommendedSkillId: json['recommended_skill_id'] as String? ?? '',
        recommendedLessonId: json['recommended_lesson_id'] as String? ?? '',
        decisionStatus: json['status'] as String? ?? 'pending',
        decisionMethod:
            json['decision_method'] as String? ?? 'deterministic_rules',
        remediationCycle: json['remediation_cycle'] as int? ?? 0,
        masteryBefore: (json['mastery_before'] as num?)?.toDouble(),
        masteryAfter: (json['mastery_after'] as num?)?.toDouble(),
        remediationSucceeded: json['succeeded'] as bool?,
        predictionId: json['prediction_id']?.toString(),
        questionInstanceId: json['question_instance_id']?.toString(),
        modelVersion: json['model_version'] as String?,
        difficultyBefore: (json['difficulty_before'] as num?)?.toInt(),
        difficultyAfter: (json['difficulty_after'] as num?)?.toInt(),
        fallbackUsed: json['fallback_used'] as bool? ?? true,
        selectionEvidence:
            json['evidence'] as Map<String, dynamic>? ?? const {},
      );
}

class AssessmentErrorRecord {
  final String skillId;
  final String language;
  final String errorCategory;
  final int errorCount;
  final String? lastSeenAt;

  const AssessmentErrorRecord({
    required this.skillId,
    required this.language,
    required this.errorCategory,
    required this.errorCount,
    this.lastSeenAt,
  });

  factory AssessmentErrorRecord.fromJson(Map<String, dynamic> json) =>
      AssessmentErrorRecord(
        skillId: json['skill_id'] as String? ?? '',
        language: json['language'] as String? ?? '',
        errorCategory: json['error_category'] as String? ?? 'unknown',
        errorCount: json['error_count'] as int? ?? 0,
        lastSeenAt: json['last_seen_at'] as String?,
      );
}

class SkillProgressRecord {
  final String skillId;
  final String language;
  final int attempts;
  final int correctCount;
  final double accuracyPct;
  final double masteryEstimate;
  final String masteryMethod;
  final String? nextReviewAt;
  final bool reviewDue;

  const SkillProgressRecord({
    required this.skillId,
    required this.language,
    required this.attempts,
    required this.correctCount,
    required this.accuracyPct,
    required this.masteryEstimate,
    required this.masteryMethod,
    required this.nextReviewAt,
    required this.reviewDue,
  });

  factory SkillProgressRecord.fromJson(Map<String, dynamic> json) =>
      SkillProgressRecord(
        skillId: json['skill_id'] as String? ?? '',
        language: json['language'] as String? ?? '',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        correctCount: (json['correct_count'] as num?)?.toInt() ?? 0,
        accuracyPct: (json['accuracy_pct'] as num?)?.toDouble() ?? 0,
        masteryEstimate:
            (json['mastery_estimate'] as num?)?.toDouble() ?? 0,
        masteryMethod: json['mastery_method'] as String? ?? 'unknown',
        nextReviewAt: json['next_review_at']?.toString(),
        reviewDue: json['review_due'] as bool? ?? false,
      );
}

class AdaptivePredictionRecord {
  final String predictionId;
  final String skillId;
  final String language;
  final double probabilityIncorrect;
  final String predictionSource;
  final String validityStatus;
  final String? modelVersion;
  final String featureSchemaVersion;
  final String? fallbackReason;
  final int predictionLatencyMs;
  final String? predictedAt;
  final String? linkedSubmissionId;
  final bool? observedIncorrect;
  final String? resolvedAt;

  const AdaptivePredictionRecord({
    required this.predictionId,
    required this.skillId,
    required this.language,
    required this.probabilityIncorrect,
    required this.predictionSource,
    required this.validityStatus,
    this.modelVersion,
    required this.featureSchemaVersion,
    this.fallbackReason,
    required this.predictionLatencyMs,
    this.predictedAt,
    this.linkedSubmissionId,
    this.observedIncorrect,
    this.resolvedAt,
  });

  bool get usedQualifiedModel =>
      predictionSource == 'qualified_model' && validityStatus == 'valid';

  factory AdaptivePredictionRecord.fromJson(Map<String, dynamic> json) =>
      AdaptivePredictionRecord(
        predictionId: json['prediction_id']?.toString() ?? '',
        skillId: json['skill_id'] as String? ?? '',
        language: json['language'] as String? ?? '',
        probabilityIncorrect:
            (json['probability_incorrect'] as num?)?.toDouble() ?? 0.0,
        predictionSource:
            json['prediction_source'] as String? ?? 'cold_start_deterministic',
        validityStatus: json['validity_status'] as String? ?? 'fallback',
        modelVersion: json['model_version'] as String?,
        featureSchemaVersion:
            json['feature_schema_version'] as String? ?? 'unknown',
        fallbackReason: json['fallback_reason'] as String?,
        predictionLatencyMs:
            (json['prediction_latency_ms'] as num?)?.toInt() ?? 0,
        predictedAt: json['predicted_at']?.toString(),
        linkedSubmissionId: json['linked_submission_id']?.toString(),
        observedIncorrect: json['observed_incorrect'] as bool?,
        resolvedAt: json['resolved_at']?.toString(),
      );
}

class AdaptiveQuestionRecord {
  final String questionInstanceId;
  final String? predictionId;
  final String skillId;
  final String lessonId;
  final String language;
  final int difficulty;
  final String questionType;
  final String questionSource;
  final String questionVersion;
  final String mappingVersion;
  final String curriculumVersion;
  final String? generationModel;
  final String? generationFailure;
  final String validationStatus;
  final String? createdAt;

  const AdaptiveQuestionRecord({
    required this.questionInstanceId,
    this.predictionId,
    required this.skillId,
    required this.lessonId,
    required this.language,
    required this.difficulty,
    required this.questionType,
    required this.questionSource,
    required this.questionVersion,
    required this.mappingVersion,
    required this.curriculumVersion,
    this.generationModel,
    this.generationFailure,
    required this.validationStatus,
    this.createdAt,
  });

  factory AdaptiveQuestionRecord.fromJson(Map<String, dynamic> json) =>
      AdaptiveQuestionRecord(
        questionInstanceId: json['question_instance_id']?.toString() ?? '',
        predictionId: json['prediction_id']?.toString(),
        skillId: json['skill_id'] as String? ?? '',
        lessonId: json['lesson_id'] as String? ?? '',
        language: json['language'] as String? ?? '',
        difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
        questionType: json['question_type'] as String? ?? '',
        questionSource: json['question_source'] as String? ?? '',
        questionVersion: json['question_version'] as String? ?? '',
        mappingVersion: json['mapping_version'] as String? ?? '',
        curriculumVersion: json['curriculum_version'] as String? ?? '',
        generationModel: json['generation_model'] as String?,
        generationFailure: json['generation_failure'] as String?,
        validationStatus: json['validation_status'] as String? ?? '',
        createdAt: json['created_at']?.toString(),
      );
}

class LearnerDetailData {
  final String id;
  final String name;
  final String? batch;
  final String? phone;
  final String? email;
  final String preferredLanguage;
  final String? createdAt;
  final String? lastActiveAt;
  final String currentStage;
  final String currentLetter;
  final double accuracyPct;
  final int totalAttempts;
  final int attempts7d;
  final List<String> topWeakLetters;
  final List<SkillProgressRecord> skillProgress;
  final String status;
  final List<AttemptRecord> recentAttempts;
  final List<AssessmentRecord> recentAssessments;
  final List<AssessmentErrorRecord> assessmentErrors;
  final List<AdaptivePredictionRecord> recentPredictions;
  final List<AdaptiveQuestionRecord> recentAdaptiveQuestions;

  const LearnerDetailData({
    required this.id,
    required this.name,
    this.batch,
    this.phone,
    this.email,
    required this.preferredLanguage,
    this.createdAt,
    this.lastActiveAt,
    required this.currentStage,
    required this.currentLetter,
    required this.accuracyPct,
    required this.totalAttempts,
    required this.attempts7d,
    required this.topWeakLetters,
    required this.skillProgress,
    required this.status,
    required this.recentAttempts,
    required this.recentAssessments,
    required this.assessmentErrors,
    required this.recentPredictions,
    required this.recentAdaptiveQuestions,
  });

  factory LearnerDetailData.fromJson(Map<String, dynamic> json) =>
      LearnerDetailData(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        batch: json['batch'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        preferredLanguage: json['preferred_language'] as String? ?? 'English',
        createdAt: json['created_at'] as String?,
        lastActiveAt: json['last_active_at'] as String?,
        currentStage: json['current_stage'] as String? ?? '',
        currentLetter: json['current_letter'] as String? ?? '',
        accuracyPct: (json['accuracy_pct'] as num?)?.toDouble() ?? 0.0,
        totalAttempts: json['total_attempts'] as int? ?? 0,
        attempts7d: json['attempts_7d'] as int? ?? 0,
        topWeakLetters:
            (json['top_weak_letters'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        skillProgress:
            (json['skill_progress'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(SkillProgressRecord.fromJson)
                .toList() ??
            const [],
        status: json['status'] as String? ?? 'inactive',
        recentAttempts:
            (json['recent_attempts'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(AttemptRecord.fromJson)
                .toList() ??
            const [],
        recentAssessments:
            (json['recent_assessments'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(AssessmentRecord.fromJson)
                .toList() ??
            const [],
        assessmentErrors:
            (json['assessment_error_summary'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(AssessmentErrorRecord.fromJson)
                .toList() ??
            const [],
        recentPredictions:
            (json['recent_predictions'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(AdaptivePredictionRecord.fromJson)
                .toList() ??
            const [],
        recentAdaptiveQuestions:
            (json['recent_adaptive_questions'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(AdaptiveQuestionRecord.fromJson)
                .toList() ??
            const [],
      );
}

class DashboardApi {
  final http.Client _client;
  final Uri? _baseUriOverride;
  Uri get _baseUri => _baseUriOverride ?? ApiConfiguration.baseUri;
  final String teacherToken;

  DashboardApi({required this.teacherToken, http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _baseUriOverride = baseUri;

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'authorization': 'Bearer $teacherToken',
  };

  Future<TeacherDashboardData> fetchDashboard() async {
    final uri = _baseUri.resolve('/teachers/me/dashboard');
    final res = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    _check(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return TeacherDashboardData.fromJson(json);
  }

  Future<LearnerDetailData> fetchLearnerDetail(String learnerId) async {
    final uri = _baseUri.resolve('/teachers/me/learners/$learnerId');
    final res = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    _check(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return LearnerDetailData.fromJson(json);
  }

  Future<void> deleteLearner(String learnerId) async {
    final uri = _baseUri.resolve('/learners/$learnerId');
    final res = await _client
        .delete(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    _check(res);
  }

  void _check(http.Response res) {
    if (res.statusCode == 401) {
      throw const DashboardApiException(
        'Session expired. Please log in again.',
      );
    }
    if (res.statusCode == 404) {
      throw const DashboardApiException('Learner not found.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = 'Server error (${res.statusCode})';
      try {
        final b = jsonDecode(res.body);
        if (b is Map && b['detail'] is String) detail = b['detail'] as String;
      } catch (_) {}
      throw DashboardApiException(detail);
    }
  }
}

class DashboardApiException implements Exception {
  final String message;
  const DashboardApiException(this.message);
  @override
  String toString() => message;
}
