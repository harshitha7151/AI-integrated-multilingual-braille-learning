import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

abstract interface class OnboardingProgress {
  Future<bool> isComplete();
  Future<void> markComplete();
  Future<int> currentStep();
  Future<void> saveStep(int step);
}

/// Persists the one-time introduction locally so it remains available offline.
class OnboardingStore implements OnboardingProgress {
  static const int _currentLessonVersion = 5;
  final File file;

  OnboardingStore(this.file);

  static Future<OnboardingStore> forApplication() async {
    // Browsers have no filesystem: keep state in memory for the session.
    if (kIsWeb) return OnboardingStore(MemoryFileSystem().file('/onboarding.json'));
    final directory = await getApplicationDocumentsDirectory();
    return OnboardingStore(
      File('${directory.path}${Platform.pathSeparator}onboarding.json'),
    );
  }

  @override
  Future<bool> isComplete() async {
    if (!await file.exists()) return false;
    final data = jsonDecode(await file.readAsString());
    // Re-run the revised operating lesson after an app upgrade without
    // deleting any saved letter practice or assessment results.
    return data is Map &&
        data['completed'] == true &&
        data['lesson_version'] == _currentLessonVersion;
  }

  @override
  Future<int> currentStep() async {
    if (!await file.exists()) return 0;
    final data = jsonDecode(await file.readAsString());
    final step = data is Map ? data['step'] : null;
    return step is int && step >= 0 && step < 10 ? step : 0;
  }

  @override
  Future<void> saveStep(int step) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'completed': false,
        'step': step.clamp(0, 9),
        'lesson_version': _currentLessonVersion,
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<void> markComplete() async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'completed': true,
        'step': 0,
        'lesson_version': _currentLessonVersion,
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
