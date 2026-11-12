import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

typedef JsonMap = Map<String, dynamic>;

/// Small durable offline event log and resume state store.
class LessonProgressStore {
  final File file;
  Future<void> _writes = Future<void>.value();

  LessonProgressStore(this.file);

  File get _resumeFile =>
      File('${file.parent.path}${Platform.pathSeparator}resume-state.json');

  static Future<LessonProgressStore> forApplication() async {
    final directory = await getApplicationDocumentsDirectory();
    return LessonProgressStore(
      File('${directory.path}${Platform.pathSeparator}lesson-progress.json'),
    );
  }

  Future<JsonMap> readResumeState() async {
    if (file.path.startsWith('unused-') || !await _resumeFile.exists()) return {};
    try {
      final decoded = jsonDecode(await _resumeFile.readAsString());
      return decoded is Map ? JsonMap.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> saveResumeState({
    required String languageCode,
    required int chapter,
    required int lessonItem,
    required int wordLessonIndex,
  }) async {
    if (file.path.startsWith('unused-')) return;     await file.parent.create(recursive: true);     final temporary = File('${_resumeFile.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'language': languageCode,
        'chapter': chapter,
        'lesson_item': lessonItem,
        'word_lesson_index': wordLessonIndex,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    if (await _resumeFile.exists()) await _resumeFile.delete();
    await temporary.rename(_resumeFile.path);
  }

  Future<List<JsonMap>> readEvents() async {
    final temporary = File('${file.path}.tmp');
    final source = await file.exists() ? file : temporary;
    if (!await source.exists()) return [];
    final decoded = jsonDecode(await source.readAsString());
    if (decoded is! List) {
      throw const FormatException('Invalid lesson progress file.');
    }
    return decoded
        .whereType()
        .map((event) => JsonMap.from(event))
        .toList();
  }

  Future<void> record({
    required String exerciseId,
    required String skillId,
    required String exerciseType,
    required bool correct,
    required int attemptNumber,
    required bool hintUsed,
    required int responseTimeMs,
    String? groupId,
  }) {
    final task = _writes.catchError((_) {}).then((_) async {
      final events = await readEvents();
      events.add({
        'submission_id': _newId(),
        'exercise_id': exerciseId,
        'skill_id': skillId,
        'language': exerciseId.startsWith('hi-')
            ? 'Hindi'
            : exerciseId.startsWith('kn-')
            ? 'Kannada'
            : 'English',
        'exercise_type': exerciseType,
        'outcome': correct ? 'correct' : 'incorrect',
        'response_time_ms': responseTimeMs,
        'hint_used': hintUsed,
        'attempt_number': attemptNumber,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'synced_at': null,
        if (groupId != null) 'group_id': groupId,
      });
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(events), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
    _writes = task;
    return task;
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


