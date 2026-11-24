import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_config.dart';
import '../core/storage/browser_storage.dart';
import 'adaptive_decision_controller.dart';
import 'learner_account_store.dart';

typedef JsonMap = Map<String, dynamic>;

/// Durable offline event log and resume store, with optional backend sync.
class LessonProgressStore {
  final File? file;
  final http.Client? httpClient;
  final Uri? baseUri;
  Future<void> _writes = Future<void>.value();
  Future<void> _decisionWrites = Future<void>.value();
  final List<AdaptiveDecision> _transientAdaptiveDecisions = [];
  bool _syncing = false;

  LessonProgressStore(this.file, {this.httpClient, this.baseUri});
  LessonProgressStore.web({this.httpClient, this.baseUri}) : file = null;

  File get _resumeFile =>
      File('${file!.parent.path}${Platform.pathSeparator}resume-state.json');

  File get _adaptiveDecisionFile => File(
    '${file!.parent.path}${Platform.pathSeparator}adaptive-decisions.json',
  );

  static Future<LessonProgressStore> forApplication() async {
    if (kIsWeb) return LessonProgressStore.web();
    final directory = await getApplicationDocumentsDirectory();
    return LessonProgressStore(
      File('${directory.path}${Platform.pathSeparator}lesson-progress.json'),
    );
  }

  Future<JsonMap> readResumeState() async {
    if (_isTransientTestStore) return {};
    try {
      final contents = file == null
          ? await readBrowserLocal('resonant.resume-state')
          : await _readFileWithTemporary(_resumeFile);
      if (contents == null) return {};
      final decoded = jsonDecode(contents);
      return decoded is Map ? JsonMap.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<JsonMap> readResumeStateFor(String languageCode) async {
    final latest = await readResumeState();
    final byLanguage = latest['languages'];
    if (byLanguage is Map && byLanguage[languageCode] is Map) {
      return JsonMap.from(byLanguage[languageCode] as Map);
    }
    if (latest['language'] == languageCode) return latest;
    return {};
  }

  Future<void> saveResumeState({
    required String languageCode,
    required int chapter,
    required int lessonItem,
    required int wordLessonIndex,
  }) async {
    if (_isTransientTestStore) return;
    final existing = await readResumeState();
    final languages = <String, dynamic>{};
    final savedLanguages = existing['languages'];
    if (savedLanguages is Map) {
      languages.addAll(Map<String, dynamic>.from(savedLanguages));
    } else if (existing['language'] is String) {
      languages[existing['language'] as String] = {
        for (final entry in existing.entries)
          if (entry.key != 'languages') entry.key: entry.value,
      };
    }
    final priorLanguageState = languages[languageCode];
    final pausedAssessment = priorLanguageState is Map
        ? priorLanguageState['paused_word_assessment']
        : existing['language'] == languageCode
        ? existing['paused_word_assessment']
        : null;
    final current = {
      'language': languageCode,
      'chapter': chapter,
      'lesson_item': lessonItem,
      'word_lesson_index': wordLessonIndex,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (pausedAssessment is Map) 'paused_word_assessment': pausedAssessment,
    };
    languages[languageCode] = current;
    final contents = jsonEncode({...current, 'languages': languages});
    if (file == null) {
      await writeBrowserLocal('resonant.resume-state', contents);
    } else {
      await _writeFileAtomically(_resumeFile, contents);
    }
  }

  Future<void> savePausedWordAssessment({
    required String languageCode,
    required Map<String, dynamic>? pausedAssessment,
  }) async {
    if (_isTransientTestStore) return;
    final existing = await readResumeState();
    final savedLanguages = existing['languages'];
    final languages = savedLanguages is Map
        ? Map<String, dynamic>.from(savedLanguages)
        : <String, dynamic>{};
    final savedLanguage = languages[languageCode];
    final current = savedLanguage is Map
        ? Map<String, dynamic>.from(savedLanguage)
        : existing['language'] == languageCode
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{'language': languageCode};
    if (pausedAssessment == null) {
      current.remove('paused_word_assessment');
    } else {
      current['paused_word_assessment'] = pausedAssessment;
    }
    languages[languageCode] = current;
    final updated = <String, dynamic>{
      ...existing,
      if (existing['language'] == languageCode) ...current,
      'languages': languages,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final contents = jsonEncode(updated);
    if (file == null) {
      await writeBrowserLocal('resonant.resume-state', contents);
    } else {
      await _writeFileAtomically(_resumeFile, contents);
    }
  }

  Future<List<JsonMap>> readEvents() async {
    final contents = file == null
        ? await readBrowserLocal('resonant.lesson-progress')
        : await _readFileWithTemporary(file!);
    if (contents == null) return [];
    final decoded = jsonDecode(contents);
    if (decoded is! List) {
      throw const FormatException('Invalid lesson progress file.');
    }
    return decoded.whereType().map((event) => JsonMap.from(event)).toList();
  }

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
    JsonMap? expectedResponse,
    JsonMap? submittedResponse,
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
  }) {
    final submissionId = _newId();
    final task = _writes.catchError((_) {}).then((_) async {
      final events = await readEvents();
      events.add({
        'submission_id': submissionId,
        if (learnerId != null) 'learner_id': learnerId,
        'exercise_id': exerciseId,
        'skill_id': skillId,
        'language': exerciseId.startsWith('hi-')
            ? 'Hindi'
            : exerciseId.startsWith('kn-')
            ? 'Kannada'
            : language,
        'exercise_type': _mapExerciseType(exerciseType),
        'outcome': correct ? 'correct' : 'incorrect',
        'response_time_ms': responseTimeMs,
        'hint_used': hintUsed,
        'attempt_number': attemptNumber,
        if (questionId != null) 'question_id': questionId,
        if (questionInstanceId != null)
          'question_instance_id': questionInstanceId,
        'difficulty': difficulty.clamp(1, 5),
        if (expectedResponse != null) 'expected_response': expectedResponse,
        if (submittedResponse != null) 'submitted_response': submittedResponse,
        'input_status': inputStatus,
        if (technicalFailureCode != null)
          'technical_failure_code': technicalFailureCode,
        'mapping_version': mappingVersion,
        'curriculum_version': curriculumVersion,
        if (interventionType != null) 'intervention_type': interventionType,
        if (feedbackType != null) 'feedback_type': feedbackType,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'synced_at': null,
        if (groupId != null) 'group_id': groupId,
        if (assessmentKey != null) ...{
          'sync_kind': 'assessment',
          'assessment_key': assessmentKey,
          'lesson_id': lessonId ?? exerciseId,
          'question_text': questionText ?? exerciseId,
          'options': options ?? const <String>[],
          'learning_objective': learningObjective ?? skillId,
          'question_source': questionSource,
          'question_version': questionVersion,
          if (generationModel != null) 'generation_model': generationModel,
          'expected_response': expectedResponse ?? const <String, dynamic>{},
          'submitted_response': submittedResponse ?? const <String, dynamic>{},
        },
      });
      await _writeEvents(events);
    });
    _writes = task;
    return task.then((_) => submissionId);
  }

  Future<List<AdaptiveDecision>> readAdaptiveDecisions() async {
    if (_isTransientTestStore) {
      return List<AdaptiveDecision>.from(_transientAdaptiveDecisions);
    }
    try {
      final contents = file == null
          ? await readBrowserLocal('resonant.adaptive-decisions')
          : await _readFileWithTemporary(_adaptiveDecisionFile);
      if (contents == null) return [];
      final decoded = jsonDecode(contents);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => AdaptiveDecision.fromJson(JsonMap.from(item)))
          .where((decision) => decision.decisionId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<AdaptiveDecision> saveAdaptiveDecision(AdaptiveDecision decision) {
    late AdaptiveDecision saved;
    final task = _decisionWrites.catchError((_) {}).then((_) async {
      final decisions = await readAdaptiveDecisions();
      var incoming = decision;
      final alreadyStored = decisions.any(
        (item) => item.decisionId == decision.decisionId,
      );
      if (decision.source != AdaptiveDecisionSource.deterministicOffline &&
          !alreadyStored) {
        final offlineIndex = decisions.indexWhere(
          (item) =>
              item.source == AdaptiveDecisionSource.deterministicOffline &&
              item.status != AdaptiveDecisionStatus.superseded &&
              item.assessmentSubmissionId == decision.assessmentSubmissionId,
        );
        if (offlineIndex >= 0) {
          final offline = decisions[offlineIndex];
          incoming = decision.copyWith(
            status: offline.status,
            appliedAt: offline.appliedAt,
            completedAt: offline.completedAt,
            succeeded: offline.succeeded,
            remediationCycle:
                offline.remediationCycle > decision.remediationCycle
                ? offline.remediationCycle
                : decision.remediationCycle,
            clearLifecycleSyncedAt: true,
          );
          decisions[offlineIndex] = offline.markSuperseded();
        }
      }

      final existingIndex = decisions.indexWhere(
        (item) => item.decisionId == incoming.decisionId,
      );
      if (existingIndex >= 0) {
        final existing = decisions[existingIndex];
        if (_statusRank(existing.status) > _statusRank(incoming.status)) {
          incoming = incoming.copyWith(
            status: existing.status,
            appliedAt: existing.appliedAt,
            completedAt: existing.completedAt,
            succeeded: existing.succeeded,
            lifecycleSyncedAt: existing.lifecycleSyncedAt,
          );
        }
        decisions[existingIndex] = incoming;
      } else {
        final duplicateActive = decisions.any(
          (item) =>
              item.isActive &&
              item.assessmentSubmissionId != incoming.assessmentSubmissionId &&
              item.fingerprint == incoming.fingerprint,
        );
        saved = duplicateActive ? incoming.markSuperseded() : incoming;
        decisions.add(saved);
        await _writeAdaptiveDecisions(decisions);
        return;
      }
      saved = incoming;
      await _writeAdaptiveDecisions(decisions);
    });
    _decisionWrites = task;
    return task.then((_) => saved);
  }

  Future<AdaptiveDecision?> pendingAdaptiveDecision({
    String? languageCode,
  }) async {
    final normalizedLanguage = languageCode == null
        ? null
        : adaptiveLanguageCode(languageCode);
    final decisions =
        (await readAdaptiveDecisions())
            .where(
              (decision) =>
                  decision.isActive &&
                  (normalizedLanguage == null ||
                      decision.languageCode == normalizedLanguage),
            )
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return decisions.firstOrNull;
  }

  Future<AdaptiveDecision?> latestAdaptiveDecision({
    String? languageCode,
  }) async {
    final normalizedLanguage = languageCode == null
        ? null
        : adaptiveLanguageCode(languageCode);
    final decisions =
        (await readAdaptiveDecisions())
            .where(
              (decision) =>
                  normalizedLanguage == null ||
                  decision.languageCode == normalizedLanguage,
            )
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return decisions.firstOrNull;
  }

  Future<AdaptiveDecision?> markAdaptiveDecisionApplied(String decisionId) =>
      _updateAdaptiveDecision(decisionId, (decision) => decision.markApplied());

  Future<AdaptiveDecision?> markAdaptiveDecisionCompleted(
    String decisionId, {
    required bool succeeded,
  }) => _updateAdaptiveDecision(
    decisionId,
    (decision) => decision.markCompleted(succeeded: succeeded),
  );

  Future<int> completedRemediationCycles(String skillId) async {
    final decisions = await readAdaptiveDecisions();
    var highest = 0;
    for (final decision in decisions) {
      if (decision.skillId == skillId &&
          decision.status == AdaptiveDecisionStatus.completed &&
          decision.action == AdaptiveDecisionAction.remediate &&
          decision.remediationCycle > highest) {
        highest = decision.remediationCycle;
      }
    }
    return highest;
  }

  Future<bool> hasFailedCappedReassessment(
    String skillId, {
    int cycleLimit = 2,
  }) async {
    final decisions = await readAdaptiveDecisions();
    return decisions.any(
      (decision) =>
          decision.skillId == skillId &&
          decision.action == AdaptiveDecisionAction.reassess &&
          decision.status == AdaptiveDecisionStatus.completed &&
          decision.succeeded == false &&
          decision.remediationCycle >= cycleLimit,
    );
  }

  Future<AdaptiveDecision?> _updateAdaptiveDecision(
    String decisionId,
    AdaptiveDecision Function(AdaptiveDecision decision) update,
  ) {
    AdaptiveDecision? updated;
    final task = _decisionWrites.catchError((_) {}).then((_) async {
      final decisions = await readAdaptiveDecisions();
      final index = decisions.indexWhere(
        (decision) => decision.decisionId == decisionId,
      );
      if (index < 0) return;
      updated = update(decisions[index]);
      decisions[index] = updated!;
      await _writeAdaptiveDecisions(decisions);
    });
    _decisionWrites = task;
    return task.then((_) => updated);
  }

  Future<void> _writeAdaptiveDecisions(List<AdaptiveDecision> decisions) async {
    if (_isTransientTestStore) {
      _transientAdaptiveDecisions
        ..clear()
        ..addAll(decisions);
      return;
    }
    final contents = jsonEncode(
      decisions.map((decision) => decision.toJson()).toList(),
    );
    if (file == null) {
      await writeBrowserLocal('resonant.adaptive-decisions', contents);
    } else {
      await _writeFileAtomically(_adaptiveDecisionFile, contents);
    }
  }

  /// Attempts to upload pending events (synced_at == null) when a learner
  /// account exists and the backend is reachable.
  Future<AdaptiveDecision?> syncAssessmentDecision({
    required String submissionId,
    LearnerAccountStorage? accountStore,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_syncing) return null;
    _syncing = true;
    try {
      final store = accountStore ?? await LearnerAccountStore.forApplication();
      final account = await store.load();
      if (account == null) return null;
      await _writes.catchError((_) {});
      final events = await readEvents();
      final index = events.indexWhere(
        (event) =>
            event['submission_id'] == submissionId &&
            event['sync_kind'] == 'assessment',
      );
      if (index < 0) return null;
      final existing = (await readAdaptiveDecisions()).where(
        (decision) => decision.assessmentSubmissionId == submissionId,
      );
      if (events[index]['synced_at'] != null && existing.isNotEmpty) {
        return existing.last;
      }
      final client = httpClient ?? http.Client();
      final api = baseUri ?? ApiConfiguration.baseUri;
      final response = await client
          .post(
            api.resolve('/learners/${account.learnerId}/assessments'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(_assessmentUploadBody(events[index], account)),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['decision'] is! Map) return null;
      final decision = await saveAdaptiveDecision(
        AdaptiveDecision.fromBackend(
          response: JsonMap.from(decoded),
          assessmentEvent: events[index],
        ),
      );
      events[index]['synced_at'] = DateTime.now().toUtc().toIso8601String();
      events[index]['learner_id'] = account.learnerId;
      await _writeEvents(events);
      return decision;
    } catch (_) {
      return null;
    } finally {
      _syncing = false;
    }
  }

  Future<int> syncPending({LearnerAccountStorage? accountStore}) async {
    if (_syncing) return 0;
    _syncing = true;
    try {
      final store = accountStore ?? await LearnerAccountStore.forApplication();
      final account = await store.load();
      if (account == null) return 0;

      await _writes.catchError((_) {});
      final events = await readEvents();
      final pendingIndices = <int>[];
      for (var i = 0; i < events.length; i++) {
        if (events[i]['synced_at'] == null) {
          pendingIndices.add(i);
        }
      }
      final client = httpClient ?? http.Client();
      final api = baseUri ?? ApiConfiguration.baseUri;
      var syncedCount = 0;

      for (final idx in pendingIndices) {
        final ev = events[idx];
        final isAssessment = ev['sync_kind'] == 'assessment';
        final responseTimeMs = ev['response_time_ms'] as int? ?? 0;
        final uri = isAssessment
            ? api.resolve('/learners/${account.learnerId}/assessments')
            : api.resolve('/practice/attempts');
        final body = jsonEncode(
          isAssessment
              ? _assessmentUploadBody(ev, account)
              : {
                  'submission_id': ev['submission_id'],
                  'learner_id': ev['learner_id'] ?? account.learnerId,
                  'learner_code': account.learnerCode,
                  'exercise_id': ev['exercise_id'],
                  'skill_id': ev['skill_id'],
                  'language': ev['language'] ?? 'English',
                  'exercise_type': ev['exercise_type'] ?? 'letter_recognition',
                  'outcome': ev['outcome'] ?? 'incorrect',
                  'response_time_ms': responseTimeMs,
                  'hint_used': ev['hint_used'] ?? false,
                  'attempt_number': ev['attempt_number'] ?? 1,
                  'question_id': ev['question_id'],
                  'character_target': ev['character_target'],
                  'difficulty': ev['difficulty'] ?? 1,
                  'expected_response': ev['expected_response'],
                  'submitted_response': ev['submitted_response'],
                  'input_status': ev['input_status'] ?? 'valid',
                  'technical_failure_code': ev['technical_failure_code'],
                  'mapping_version': ev['mapping_version'] ?? 'unspecified',
                  'curriculum_version':
                      ev['curriculum_version'] ?? 'flutter-catalog-v1',
                  'intervention_type': ev['intervention_type'],
                  'feedback_type': ev['feedback_type'],
                },
        );

        try {
          final res = await client
              .post(
                uri,
                headers: {'content-type': 'application/json'},
                body: body,
              )
              .timeout(const Duration(seconds: 5));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            if (isAssessment) {
              try {
                final decoded = jsonDecode(res.body);
                if (decoded is Map && decoded['decision'] is Map) {
                  await saveAdaptiveDecision(
                    AdaptiveDecision.fromBackend(
                      response: JsonMap.from(decoded),
                      assessmentEvent: ev,
                    ),
                  );
                }
              } catch (_) {
                // The locally derived deterministic decision remains usable if
                // an older or malformed server response has no decision body.
              }
            }
            events[idx]['synced_at'] = DateTime.now().toUtc().toIso8601String();
            events[idx]['learner_id'] = account.learnerId;
            syncedCount++;
          }
        } catch (_) {
          // If network failed, stop syncing this batch and retry next time
          break;
        }
      }

      if (syncedCount > 0) {
        await _writeEvents(events);
      }
      await _syncAdaptiveDecisionLifecycle(
        client: client,
        api: api,
        learnerId: account.learnerId,
        learnerCode: account.learnerCode,
      );
      return syncedCount;
    } catch (_) {
      // Sync remains best-effort when storage plugins or the backend are
      // unavailable (for example, during offline use or widget tests).
      return 0;
    } finally {
      _syncing = false;
    }
  }

  JsonMap _assessmentUploadBody(JsonMap ev, LearnerAccount account) {
    final responseTimeMs = ev['response_time_ms'] as int? ?? 0;
    final completedAt =
        DateTime.tryParse(ev['created_at'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc();
    return {
      'submission_id': ev['submission_id'],
      'learner_code': account.learnerCode,
      'assessment_key': ev['assessment_key'],
      'lesson_id': ev['lesson_id'] ?? ev['exercise_id'],
      'language': ev['language'] ?? 'English',
      'assessment_type': 'lesson',
      'difficulty': ev['difficulty'] ?? 1,
      'generated_content_version':
          ev['question_version'] ?? 'flutter-catalog-v1',
      'duration_ms': responseTimeMs,
      'started_at': completedAt
          .subtract(Duration(milliseconds: responseTimeMs))
          .toIso8601String(),
      'completed_at': completedAt.toIso8601String(),
      'questions': [
        {
          'question_id': ev['question_id'] ?? ev['exercise_id'],
          'skill_id': ev['skill_id'],
          'exercise_type': ev['exercise_type'] ?? 'letter_recognition',
          'learning_objective': ev['learning_objective'] ?? ev['skill_id'],
          'difficulty': ev['difficulty'] ?? 1,
          'question_text': ev['question_text'] ?? ev['exercise_id'],
          'options': ev['options'] ?? const <String>[],
          'expected_response':
              ev['expected_response'] ?? const <String, dynamic>{},
          'submitted_response':
              ev['submitted_response'] ?? const <String, dynamic>{},
          'correct': ev['outcome'] == 'correct',
          'attempts': ev['attempt_number'] ?? 1,
          'response_time_ms': responseTimeMs,
          'hint_used': ev['hint_used'] ?? false,
          'input_status': ev['input_status'] ?? 'valid',
          'technical_failure_code': ev['technical_failure_code'],
          'question_instance_id': ev['question_instance_id'],
          'question_source': ev['question_source'] ?? 'validated_catalog',
          'question_version': ev['question_version'] ?? 'flutter-catalog-v1',
          'generation_model': ev['generation_model'],
          'mapping_version': ev['mapping_version'] ?? 'unspecified',
          'curriculum_version':
              ev['curriculum_version'] ?? 'flutter-catalog-v1',
          'intervention_type': ev['intervention_type'],
          'feedback_type': ev['feedback_type'],
        },
      ],
    };
  }

  Future<void> _writeEvents(List<JsonMap> events) async {
    final contents = jsonEncode(events);
    if (file == null) {
      await writeBrowserLocal('resonant.lesson-progress', contents);
    } else {
      await _writeFileAtomically(file!, contents);
    }
  }

  bool get _isTransientTestStore => file?.path.startsWith('unused-') ?? false;

  Future<String?> _readFileWithTemporary(File target) async {
    if (await target.exists()) return target.readAsString();
    final temporary = File('${target.path}.tmp');
    if (await temporary.exists()) return temporary.readAsString();
    return null;
  }

  Future<void> _writeFileAtomically(File target, String contents) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<void> _syncAdaptiveDecisionLifecycle({
    required http.Client client,
    required Uri api,
    required String learnerId,
    required String learnerCode,
  }) async {
    await _decisionWrites.catchError((_) {});
    final decisions = await readAdaptiveDecisions();
    for (final decision in decisions) {
      if (!decision.hasUnsyncedLifecycle) continue;
      final uri = api.resolve(
        '/learners/$learnerId/adaptive-decisions/${decision.decisionId}/status',
      );
      try {
        final response = await client
            .post(
              uri,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'learner_code': learnerCode,
                'status': decision.status.name,
                'succeeded': decision.succeeded,
                'applied_at': decision.appliedAt?.toIso8601String(),
                'completed_at': decision.completedAt?.toIso8601String(),
                'client_mastery':
                    (decision.evidence['local_history_accuracy'] as num?)
                        ?.toDouble(),
              }),
            )
            .timeout(const Duration(seconds: 5));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await _updateAdaptiveDecision(
            decision.decisionId,
            (current) =>
                current.status == decision.status &&
                    current.succeeded == decision.succeeded
                ? current.copyWith(lifecycleSyncedAt: DateTime.now().toUtc())
                : current,
          );
        }
      } catch (_) {
        break;
      }
    }
  }

  static int _statusRank(AdaptiveDecisionStatus status) => switch (status) {
    AdaptiveDecisionStatus.pending => 0,
    AdaptiveDecisionStatus.applied => 1,
    AdaptiveDecisionStatus.completed => 2,
    AdaptiveDecisionStatus.superseded => 3,
  };

  static String _mapExerciseType(String type) {
    const valid = {
      'dot_recognition',
      'letter_recognition',
      'listening',
      'braille_writing',
      'transcription',
      'quiz',
    };
    if (valid.contains(type)) return type;
    if ({
      'word_transcription',
      'phrase_transcription',
      'sentence_transcription',
    }.contains(type)) {
      return 'transcription';
    }
    return 'letter_recognition';
  }

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
