import 'lesson_catalog.dart';
import '../core/braille/braille_dispatcher.dart';

enum AdaptiveDecisionAction { remediate, reinforce, advance, reassess, revise }

enum AdaptiveDecisionStatus { pending, applied, completed, superseded }

enum AdaptiveDecisionSource {
  deterministicOffline,
  deterministicBackend,
  mlAssistedBackend,
}

AdaptiveDecisionAction adaptiveDecisionActionFromWire(String? value) {
  return switch (value?.toLowerCase().trim()) {
    'remediate' ||
    'remedial_practice' ||
    'revisit_prerequisite' => AdaptiveDecisionAction.remediate,
    'reinforce' => AdaptiveDecisionAction.reinforce,
    'reassess' => AdaptiveDecisionAction.reassess,
    'revise' || 'schedule_revision' => AdaptiveDecisionAction.revise,
    'advance' || 'increase_difficulty' => AdaptiveDecisionAction.advance,
    _ => AdaptiveDecisionAction.reassess,
  };
}

String adaptiveDecisionActionToWire(AdaptiveDecisionAction action) =>
    action.name;

AdaptiveDecisionStatus adaptiveDecisionStatusFromWire(String? value) {
  return AdaptiveDecisionStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => AdaptiveDecisionStatus.pending,
  );
}

AdaptiveDecisionSource adaptiveDecisionSourceFromWire(String? value) {
  return switch (value) {
    'mlAssistedBackend' => AdaptiveDecisionSource.mlAssistedBackend,
    'deterministicBackend' => AdaptiveDecisionSource.deterministicBackend,
    _ => AdaptiveDecisionSource.deterministicOffline,
  };
}

String adaptiveLanguageCode(String? value) {
  return switch (value?.toLowerCase().trim()) {
    'hindi' || 'hi' => 'hi',
    'kannada' || 'kn' => 'kn',
    _ => 'en',
  };
}

class AdaptivePracticeQuestion {
  final String questionInstanceId;
  final String questionId;
  final String skillId;
  final String lessonId;
  final String language;
  final int difficulty;
  final String questionType;
  final String questionText;
  final List<String> options;
  final String answer;
  final List<int> expectedCells;
  final String source;
  final String questionVersion;
  final String mappingVersion;
  final String curriculumVersion;
  final String? generationModel;
  final String validationStatus;

  const AdaptivePracticeQuestion({
    required this.questionInstanceId,
    required this.questionId,
    required this.skillId,
    required this.lessonId,
    required this.language,
    required this.difficulty,
    required this.questionType,
    required this.questionText,
    required this.options,
    required this.answer,
    required this.expectedCells,
    required this.source,
    required this.questionVersion,
    required this.mappingVersion,
    required this.curriculumVersion,
    this.generationModel,
    required this.validationStatus,
  });

  factory AdaptivePracticeQuestion.fromJson(Map<String, dynamic> json) {
    final expected = json['expected_response'];
    final expectedMap = expected is Map
        ? Map<String, dynamic>.from(expected)
        : const <String, dynamic>{};
    return AdaptivePracticeQuestion(
      questionInstanceId: '${json['question_instance_id'] ?? ''}',
      questionId: '${json['question_id'] ?? ''}',
      skillId: '${json['skill_id'] ?? ''}',
      lessonId: '${json['lesson_id'] ?? ''}',
      language: '${json['language'] ?? ''}',
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
      questionType: '${json['question_type'] ?? 'letter_recognition'}',
      questionText: '${json['question_text'] ?? ''}',
      options:
          (json['options'] as List?)?.map((item) => '$item').toList() ??
          const [],
      answer: '${json['answer'] ?? expectedMap['choice'] ?? ''}',
      expectedCells:
          (expectedMap['cells'] as List?)
              ?.whereType<num>()
              .map((cell) => cell.toInt())
              .toList() ??
          const [],
      source: '${json['question_source'] ?? 'validated_bank'}',
      questionVersion: '${json['question_version'] ?? ''}',
      mappingVersion: '${json['mapping_version'] ?? 'unspecified'}',
      curriculumVersion:
          '${json['curriculum_version'] ?? 'flutter-catalog-v1'}',
      generationModel: json['generation_model'] as String?,
      validationStatus: '${json['validation_status'] ?? 'validated'}',
    );
  }

  Map<String, dynamic> toJson() => {
    'question_instance_id': questionInstanceId,
    'question_id': questionId,
    'skill_id': skillId,
    'lesson_id': lessonId,
    'language': language,
    'difficulty': difficulty,
    'question_type': questionType,
    'question_text': questionText,
    'options': options,
    'answer': answer,
    'expected_response': {'choice': answer, 'cells': expectedCells},
    'question_source': source,
    'question_version': questionVersion,
    'mapping_version': mappingVersion,
    'curriculum_version': curriculumVersion,
    'generation_model': generationModel,
    'validation_status': validationStatus,
  };

  bool get isValid =>
      questionInstanceId.isNotEmpty &&
      questionId.isNotEmpty &&
      skillId.isNotEmpty &&
      lessonId.isNotEmpty &&
      questionText.isNotEmpty &&
      options.contains(answer) &&
      expectedCells.isNotEmpty &&
      source.isNotEmpty &&
      questionVersion.isNotEmpty &&
      mappingVersion.isNotEmpty &&
      curriculumVersion.isNotEmpty &&
      const {
        'validated',
        'fallback_after_rejection',
      }.contains(validationStatus);
}

class AdaptiveDecision {
  final String decisionId;
  final String assessmentSubmissionId;
  final String assessmentKey;
  final String languageCode;
  final String lessonId;
  final String skillId;
  final AdaptiveDecisionAction action;
  final String recommendedLessonId;
  final String reason;
  final Map<String, dynamic> evidence;
  final double confidence;
  final String expectedLearningObjective;
  final AdaptiveDecisionSource source;
  final AdaptiveDecisionStatus status;
  final int remediationCycle;
  final DateTime createdAt;
  final DateTime? appliedAt;
  final DateTime? completedAt;
  final bool? succeeded;
  final DateTime? lifecycleSyncedAt;
  final AdaptivePracticeQuestion? nextQuestion;

  const AdaptiveDecision({
    required this.decisionId,
    required this.assessmentSubmissionId,
    required this.assessmentKey,
    required this.languageCode,
    required this.lessonId,
    required this.skillId,
    required this.action,
    required this.recommendedLessonId,
    required this.reason,
    required this.evidence,
    required this.confidence,
    required this.expectedLearningObjective,
    required this.source,
    required this.status,
    required this.remediationCycle,
    required this.createdAt,
    this.appliedAt,
    this.completedAt,
    this.succeeded,
    this.lifecycleSyncedAt,
    this.nextQuestion,
  });

  bool get isActive =>
      status == AdaptiveDecisionStatus.pending ||
      status == AdaptiveDecisionStatus.applied;

  bool get requiresLearningAction =>
      isActive &&
      {
        AdaptiveDecisionAction.remediate,
        AdaptiveDecisionAction.reinforce,
        AdaptiveDecisionAction.reassess,
      }.contains(action);

  bool get hasUnsyncedLifecycle =>
      source != AdaptiveDecisionSource.deterministicOffline &&
      status != AdaptiveDecisionStatus.pending &&
      lifecycleSyncedAt == null;

  bool get usedQualifiedModel =>
      source == AdaptiveDecisionSource.mlAssistedBackend &&
      evidence['model_status'] == 'qualified_prediction_used';

  String get learnerModelStatusMessage {
    if (usedQualifiedModel) {
      return 'A qualified Resonant learner-history model advised this activity. Verified Braille, curriculum, mastery, and prerequisite rules remain authoritative.';
    }
    if (evidence['model_status'] == 'cold_start_fallback') {
      return 'Personalization is using deterministic cold-start rules because no qualified Resonant learner model was available.';
    }
    if (source == AdaptiveDecisionSource.deterministicOffline) {
      return 'Personalization is using on-device deterministic rules while offline or before backend synchronization.';
    }
    return 'Personalization is using transparent deterministic learning rules.';
  }

  String get learnerActivityMessage {
    final activity = switch (action) {
      AdaptiveDecisionAction.remediate => 'focused remediation',
      AdaptiveDecisionAction.reinforce => 'reinforcement practice',
      AdaptiveDecisionAction.advance => 'the next eligible lesson',
      AdaptiveDecisionAction.reassess => 'a supported reassessment',
      AdaptiveDecisionAction.revise => 'spaced revision',
    };
    return 'Recommended activity: $activity for skill $skillId. $reason';
  }

  String get fingerprint =>
      '$languageCode|$skillId|$recommendedLessonId|${action.name}|$remediationCycle';

  AdaptiveDecision copyWith({
    String? decisionId,
    String? skillId,
    String? recommendedLessonId,
    AdaptiveDecisionAction? action,
    AdaptiveDecisionSource? source,
    AdaptiveDecisionStatus? status,
    int? remediationCycle,
    DateTime? appliedAt,
    DateTime? completedAt,
    bool? succeeded,
    DateTime? lifecycleSyncedAt,
    bool clearLifecycleSyncedAt = false,
    Map<String, dynamic>? evidence,
    AdaptivePracticeQuestion? nextQuestion,
    bool clearNextQuestion = false,
  }) {
    return AdaptiveDecision(
      decisionId: decisionId ?? this.decisionId,
      assessmentSubmissionId: assessmentSubmissionId,
      assessmentKey: assessmentKey,
      languageCode: languageCode,
      lessonId: lessonId,
      skillId: skillId ?? this.skillId,
      action: action ?? this.action,
      recommendedLessonId: recommendedLessonId ?? this.recommendedLessonId,
      reason: reason,
      evidence: evidence ?? this.evidence,
      confidence: confidence,
      expectedLearningObjective: expectedLearningObjective,
      source: source ?? this.source,
      status: status ?? this.status,
      remediationCycle: remediationCycle ?? this.remediationCycle,
      createdAt: createdAt,
      appliedAt: appliedAt ?? this.appliedAt,
      completedAt: completedAt ?? this.completedAt,
      succeeded: succeeded ?? this.succeeded,
      lifecycleSyncedAt: clearLifecycleSyncedAt
          ? null
          : lifecycleSyncedAt ?? this.lifecycleSyncedAt,
      nextQuestion: clearNextQuestion
          ? null
          : nextQuestion ?? this.nextQuestion,
    );
  }

  AdaptiveDecision markApplied({DateTime? at}) => copyWith(
    status: AdaptiveDecisionStatus.applied,
    appliedAt: at ?? DateTime.now().toUtc(),
    clearLifecycleSyncedAt: true,
  );

  AdaptiveDecision markCompleted({required bool succeeded, DateTime? at}) =>
      copyWith(
        status: AdaptiveDecisionStatus.completed,
        completedAt: at ?? DateTime.now().toUtc(),
        succeeded: succeeded,
        clearLifecycleSyncedAt: true,
      );

  AdaptiveDecision markSuperseded() => copyWith(
    status: AdaptiveDecisionStatus.superseded,
    completedAt: DateTime.now().toUtc(),
    clearLifecycleSyncedAt: true,
  );

  Map<String, dynamic> toJson() => {
    'decision_id': decisionId,
    'assessment_submission_id': assessmentSubmissionId,
    'assessment_key': assessmentKey,
    'language_code': languageCode,
    'lesson_id': lessonId,
    'skill_id': skillId,
    'action': adaptiveDecisionActionToWire(action),
    'recommended_lesson_id': recommendedLessonId,
    'reason': reason,
    'evidence': evidence,
    'confidence': confidence,
    'expected_learning_objective': expectedLearningObjective,
    'source': source.name,
    'status': status.name,
    'remediation_cycle': remediationCycle,
    'created_at': createdAt.toUtc().toIso8601String(),
    'applied_at': appliedAt?.toUtc().toIso8601String(),
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'succeeded': succeeded,
    'lifecycle_synced_at': lifecycleSyncedAt?.toUtc().toIso8601String(),
    if (nextQuestion != null) 'next_question': nextQuestion!.toJson(),
  };

  factory AdaptiveDecision.fromJson(Map<String, dynamic> json) {
    final evidence = json['evidence'];
    final evidenceMap = evidence is Map
        ? Map<String, dynamic>.from(evidence)
        : <String, dynamic>{};
    final rawQuestion = json['next_question'] ?? evidenceMap['next_question'];
    return AdaptiveDecision(
      decisionId: '${json['decision_id'] ?? ''}',
      assessmentSubmissionId:
          '${json['assessment_submission_id'] ?? json['submission_id'] ?? ''}',
      assessmentKey: '${json['assessment_key'] ?? ''}',
      languageCode: adaptiveLanguageCode(
        '${json['language_code'] ?? json['language'] ?? 'en'}',
      ),
      lessonId: '${json['lesson_id'] ?? ''}',
      skillId: '${json['skill_id'] ?? json['recommended_skill_id'] ?? ''}',
      action: adaptiveDecisionActionFromWire('${json['action'] ?? ''}'),
      recommendedLessonId:
          '${json['recommended_lesson_id'] ?? json['lesson_id'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
      evidence: evidenceMap,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      expectedLearningObjective: '${json['expected_learning_objective'] ?? ''}',
      source: adaptiveDecisionSourceFromWire('${json['source'] ?? ''}'),
      status: adaptiveDecisionStatusFromWire('${json['status'] ?? ''}'),
      remediationCycle: (json['remediation_cycle'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse('${json['created_at'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc(),
      appliedAt: DateTime.tryParse('${json['applied_at'] ?? ''}')?.toUtc(),
      completedAt: DateTime.tryParse('${json['completed_at'] ?? ''}')?.toUtc(),
      succeeded: json['succeeded'] as bool?,
      lifecycleSyncedAt: DateTime.tryParse(
        '${json['lifecycle_synced_at'] ?? ''}',
      )?.toUtc(),
      nextQuestion: rawQuestion is Map
          ? AdaptivePracticeQuestion.fromJson(
              Map<String, dynamic>.from(rawQuestion),
            )
          : null,
    );
  }

  factory AdaptiveDecision.fromBackend({
    required Map<String, dynamic> response,
    required Map<String, dynamic> assessmentEvent,
  }) {
    final rawDecision = response['decision'];
    if (rawDecision is! Map) {
      throw const FormatException('Assessment response has no decision.');
    }
    final decision = Map<String, dynamic>.from(rawDecision);
    final method = '${decision['decision_method'] ?? ''}';
    return AdaptiveDecision.fromJson({
      ...decision,
      'assessment_submission_id':
          response['submission_id'] ?? assessmentEvent['submission_id'],
      'assessment_key':
          response['assessment_key'] ?? assessmentEvent['assessment_key'],
      'language': response['language'] ?? assessmentEvent['language'],
      'lesson_id': response['lesson_id'] ?? assessmentEvent['lesson_id'],
      'skill_id':
          decision['recommended_skill_id'] ?? assessmentEvent['skill_id'],
      'source': method == 'hybrid_ml_rules'
          ? AdaptiveDecisionSource.mlAssistedBackend.name
          : AdaptiveDecisionSource.deterministicBackend.name,
      'status': decision['status'] ?? AdaptiveDecisionStatus.pending.name,
      'remediation_cycle':
          decision['remediation_cycle'] ??
          decision['evidence']?['remediation_cycle'] ??
          0,
      'created_at':
          decision['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
    });
  }
}

class AdaptiveAssessmentSnapshot {
  final String submissionId;
  final String assessmentKey;
  final String languageCode;
  final String lessonId;
  final String skillId;
  final bool correct;
  final int attemptNumber;
  final bool hintUsed;
  final List<int> expectedCells;
  final List<int> submittedCells;
  final bool prerequisiteSatisfied;
  final String? prerequisiteLessonId;
  final String learningObjective;
  final int remediationCycles;
  final bool isReassessment;
  final List<Map<String, dynamic>> history;

  const AdaptiveAssessmentSnapshot({
    required this.submissionId,
    required this.assessmentKey,
    required this.languageCode,
    required this.lessonId,
    required this.skillId,
    required this.correct,
    required this.attemptNumber,
    required this.hintUsed,
    required this.expectedCells,
    required this.submittedCells,
    required this.prerequisiteSatisfied,
    this.prerequisiteLessonId,
    required this.learningObjective,
    required this.remediationCycles,
    required this.isReassessment,
    required this.history,
  });
}

enum AdaptiveResolutionStatus { ready, blocked, duplicate }

class AdaptiveDecisionResolution {
  final AdaptiveResolutionStatus status;
  final AdaptiveDecision decision;
  final String message;
  final int? chapterIndex;
  final int? lessonIndex;

  const AdaptiveDecisionResolution({
    required this.status,
    required this.decision,
    required this.message,
    this.chapterIndex,
    this.lessonIndex,
  });

  bool get isReady => status == AdaptiveResolutionStatus.ready;
}

/// Transparent, deterministic learner-side adaptation.
///
/// This controller does not train or run a statistical model. It converts
/// recorded assessment evidence into prerequisite-safe actions and validates
/// backend decisions before the Flutter coordinator may execute them.
class AdaptiveDecisionController {
  final int maxAutomaticRemediationCycles;

  const AdaptiveDecisionController({this.maxAutomaticRemediationCycles = 2});

  AdaptiveDecision deriveOffline(AdaptiveAssessmentSnapshot snapshot) {
    final prior = snapshot.history.where(
      (event) =>
          event['sync_kind'] == 'assessment' &&
          event['skill_id'] == snapshot.skillId &&
          event['submission_id'] != snapshot.submissionId,
    );
    final priorCount = prior.length;
    final priorCorrect = prior
        .where((event) => event['outcome'] == 'correct')
        .length;
    final priorWrong = priorCount - priorCorrect;
    final totalResults = priorCount + 1;
    final correctResults = priorCorrect + (snapshot.correct ? 1 : 0);
    final localAccuracy = correctResults / totalResults;
    final errorSignature = _errorSignature(
      snapshot.expectedCells,
      snapshot.submittedCells,
    );
    final repeatedDotConfusion = snapshot.correct
        ? 0
        : 1 +
              prior.where((event) {
                final expected = _responseCells(event['expected_response']);
                final submitted = _responseCells(event['submitted_response']);
                return _errorSignature(expected, submitted) == errorSignature;
              }).length;

    late AdaptiveDecisionAction action;
    late String reason;
    var cycle = snapshot.remediationCycles;
    if (!snapshot.prerequisiteSatisfied) {
      action = AdaptiveDecisionAction.remediate;
      cycle++;
      reason =
          'A required earlier lesson is not mastered, so this skill must be retaught before advancement.';
    } else if (!snapshot.correct &&
        snapshot.remediationCycles >= maxAutomaticRemediationCycles) {
      action = AdaptiveDecisionAction.reassess;
      reason =
          'The same focused remediation has already been assigned $maxAutomaticRemediationCycles times. It will not be assigned again automatically; the learner remains on a supported reassessment.';
    } else if (!snapshot.correct) {
      action = AdaptiveDecisionAction.remediate;
      cycle++;
      reason = repeatedDotConfusion >= 2
          ? 'The same Braille-dot confusion occurred $repeatedDotConfusion times, so focused teaching and guided practice are required before reassessment.'
          : 'The assessment answer was incorrect, so the tested skill needs a focused explanation, guided practice, and reassessment.';
    } else if (snapshot.isReassessment) {
      action = AdaptiveDecisionAction.advance;
      reason =
          'The learner answered the reassessment correctly after remediation, so the next prerequisite-safe lesson can unlock.';
    } else if (snapshot.attemptNumber > 1 ||
        snapshot.hintUsed ||
        repeatedDotConfusion >= 2 ||
        (priorCount >= 2 && localAccuracy < 0.8)) {
      action = AdaptiveDecisionAction.reinforce;
      cycle++;
      reason =
          'The answer was correct, but attempts, hints, or recent history show that short reinforcement is appropriate before advancement.';
    } else {
      action = AdaptiveDecisionAction.advance;
      reason =
          'The verified assessment was correct without a hint or repeated attempt, and the recorded prerequisite is complete.';
    }

    final evidence = <String, dynamic>{
      'decision_method': 'deterministic_rules',
      'rule_version': 'learner-offline-v1',
      'accuracy': snapshot.correct ? 1.0 : 0.0,
      'wrong_answers': snapshot.correct ? 0 : 1,
      'attempt_number': snapshot.attemptNumber,
      'hint_used': snapshot.hintUsed,
      'previous_assessment_count': priorCount,
      'previous_wrong_answers': priorWrong,
      'local_history_accuracy': double.parse(localAccuracy.toStringAsFixed(4)),
      'repeated_dot_confusion': repeatedDotConfusion,
      if (errorSignature != null) 'dot_confusion_signature': errorSignature,
      'prerequisite_mastered': snapshot.prerequisiteSatisfied,
      'remediation_cycle': cycle,
    };
    final confidence = totalResults >= 3 ? 0.72 : 0.62;
    return AdaptiveDecision(
      decisionId: 'offline-${snapshot.submissionId}',
      assessmentSubmissionId: snapshot.submissionId,
      assessmentKey: snapshot.assessmentKey,
      languageCode: adaptiveLanguageCode(snapshot.languageCode),
      lessonId: snapshot.lessonId,
      skillId: snapshot.skillId,
      action: action,
      recommendedLessonId:
          !snapshot.prerequisiteSatisfied &&
              snapshot.prerequisiteLessonId != null
          ? snapshot.prerequisiteLessonId!
          : snapshot.lessonId,
      reason: reason,
      evidence: evidence,
      confidence: confidence,
      expectedLearningObjective: snapshot.learningObjective,
      source: AdaptiveDecisionSource.deterministicOffline,
      status: AdaptiveDecisionStatus.pending,
      remediationCycle: cycle,
      createdAt: DateTime.now().toUtc(),
    );
  }

  AdaptiveDecisionResolution resolve({
    required AdaptiveDecision decision,
    required String languageCode,
    required List<LessonChapter> chapters,
    required int currentChapterIndex,
    required int currentLessonIndex,
    required Set<String> completedExerciseIds,
    Set<String> activeFingerprints = const {},
  }) {
    if (!decision.isActive) {
      return AdaptiveDecisionResolution(
        status: AdaptiveResolutionStatus.duplicate,
        decision: decision,
        message: 'This adaptive decision has already been handled.',
      );
    }
    if (adaptiveLanguageCode(languageCode) != decision.languageCode) {
      return AdaptiveDecisionResolution(
        status: AdaptiveResolutionStatus.blocked,
        decision: decision,
        message: 'This adaptive decision belongs to another learning language.',
      );
    }
    if (activeFingerprints.contains(decision.fingerprint)) {
      return AdaptiveDecisionResolution(
        status: AdaptiveResolutionStatus.duplicate,
        decision: decision,
        message: 'This adaptive action is already active.',
      );
    }

    var resolved = decision;
    var target = _findLesson(chapters, decision.recommendedLessonId);
    if (target == null) {
      return AdaptiveDecisionResolution(
        status: AdaptiveResolutionStatus.blocked,
        decision: decision,
        message: 'The recommended lesson is not in the validated curriculum.',
      );
    }
    final prerequisiteSatisfied = _prerequisitesComplete(
      chapters[target.chapter].exercises,
      target.lesson,
      completedExerciseIds,
    );
    if (!prerequisiteSatisfied &&
        decision.action == AdaptiveDecisionAction.advance) {
      return AdaptiveDecisionResolution(
        status: AdaptiveResolutionStatus.blocked,
        decision: decision,
        message:
            'The next lesson remains locked until its prerequisite is complete.',
      );
    }
    if (!prerequisiteSatisfied) {
      final missingIndex = chapters[target.chapter].exercises
          .take(target.lesson)
          .toList()
          .indexWhere(
            (exercise) => !completedExerciseIds.contains(exercise.id),
          );
      if (missingIndex >= 0) {
        final prerequisite = chapters[target.chapter].exercises[missingIndex];
        resolved = decision.copyWith(
          action: AdaptiveDecisionAction.remediate,
          skillId: prerequisite.skillId,
          recommendedLessonId: prerequisite.id,
          evidence: {
            ...decision.evidence,
            'prerequisite_redirected_from': decision.recommendedLessonId,
            'prerequisite_lesson_id': prerequisite.id,
          },
        );
        target = (chapter: target.chapter, lesson: missingIndex);
      }
    }
    if (decision.action == AdaptiveDecisionAction.remediate &&
        decision.remediationCycle > maxAutomaticRemediationCycles) {
      resolved = decision.copyWith(action: AdaptiveDecisionAction.reassess);
    }
    if (resolved.action == AdaptiveDecisionAction.advance &&
        !completedExerciseIds.contains(decision.lessonId)) {
      return AdaptiveDecisionResolution(
        status: AdaptiveResolutionStatus.blocked,
        decision: resolved,
        message: 'Advancement requires a completed verified assessment.',
      );
    }

    final questionRejection = _questionRejectionReason(
      resolved.nextQuestion,
      decision: resolved,
      target: chapters[target.chapter].exercises[target.lesson],
    );
    if (questionRejection != null) {
      resolved = resolved.copyWith(
        clearNextQuestion: true,
        evidence: {
          ...resolved.evidence,
          'question_validation_status': 'rejected_by_flutter',
          'question_fallback_reason': questionRejection,
        },
      );
    } else if (resolved.nextQuestion != null) {
      resolved = resolved.copyWith(
        evidence: {
          ...resolved.evidence,
          'question_validation_status': 'validated_by_flutter',
        },
      );
    }

    return AdaptiveDecisionResolution(
      status: AdaptiveResolutionStatus.ready,
      decision: resolved,
      message: resolved.reason,
      chapterIndex: resolved.action == AdaptiveDecisionAction.advance
          ? currentChapterIndex
          : target.chapter,
      lessonIndex: resolved.action == AdaptiveDecisionAction.advance
          ? currentLessonIndex
          : target.lesson,
    );
  }

  ({int chapter, int lesson})? _findLesson(
    List<LessonChapter> chapters,
    String lessonId,
  ) {
    for (var chapter = 0; chapter < chapters.length; chapter++) {
      for (
        var lesson = 0;
        lesson < chapters[chapter].exercises.length;
        lesson++
      ) {
        if (chapters[chapter].exercises[lesson].id == lessonId) {
          return (chapter: chapter, lesson: lesson);
        }
      }
    }
    return null;
  }

  bool _prerequisitesComplete(
    List<LessonExercise> exercises,
    int target,
    Set<String> completed,
  ) {
    if (target <= 0) return true;
    return exercises
        .take(target)
        .every((exercise) => completed.contains(exercise.id));
  }

  String? _questionRejectionReason(
    AdaptivePracticeQuestion? question, {
    required AdaptiveDecision decision,
    required LessonExercise target,
  }) {
    if (question == null) return null;
    if (!question.isValid) return 'question_contract_invalid';
    if (adaptiveLanguageCode(question.language) != decision.languageCode) {
      return 'question_language_mismatch';
    }
    if (question.skillId != decision.skillId ||
        question.lessonId != decision.recommendedLessonId) {
      return 'question_target_mismatch';
    }
    if (target.id != question.lessonId || target.skillId != question.skillId) {
      return 'question_not_in_validated_curriculum';
    }
    if (target.answer != question.answer) {
      return 'question_answer_mismatch';
    }
    final language = AppLanguage.fromCode(decision.languageCode);
    final verifiedCells = BrailleDispatcher.encodeToBitmasks(
      language == AppLanguage.english
          ? target.answer.toLowerCase()
          : target.answer,
      language,
    );
    if (!_sameCells(verifiedCells, question.expectedCells)) {
      return 'question_braille_mapping_mismatch';
    }
    return null;
  }

  static List<int> _responseCells(Object? response) {
    if (response is! Map || response['cells'] is! List) return const [];
    return (response['cells'] as List)
        .whereType<num>()
        .map((value) => value.toInt())
        .toList();
  }

  static String? _errorSignature(List<int> expected, List<int> submitted) {
    if (expected.isEmpty ||
        submitted.isEmpty ||
        _sameCells(expected, submitted)) {
      return null;
    }
    final expectedSorted = [...expected]..sort();
    final submittedSorted = [...submitted]..sort();
    return '${expectedSorted.join(',')}>${submittedSorted.join(',')}';
  }

  static bool _sameCells(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
