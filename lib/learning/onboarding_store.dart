import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/browser_storage.dart';

abstract interface class OnboardingProgress {
  Future<bool> isComplete();
  Future<void> markComplete();
  Future<int> currentStep();
  Future<void> saveStep(int step);
}

/// Persists the one-time introduction locally so it remains available offline.
class OnboardingStore implements OnboardingProgress {
  static const int _currentLessonVersion = 5;
  final File? _file;
  File get file => _file!;

  OnboardingStore(File file) : _file = file;
  OnboardingStore.web() : _file = null;

  static Future<OnboardingStore> forApplication() async {
    if (kIsWeb) return OnboardingStore.web();
    final directory = await getApplicationDocumentsDirectory();
    return OnboardingStore(
      File('${directory.path}${Platform.pathSeparator}onboarding.json'),
    );
  }

  @override
  Future<bool> isComplete() async {
    final contents = _file == null
        ? await readBrowserLocal('resonant.onboarding')
        : await _readFile();
    if (contents == null) return false;
    final data = jsonDecode(contents);
    // Re-run the revised operating lesson after an app upgrade without
    // deleting any saved letter practice or assessment results.
    return data is Map &&
        data['completed'] == true &&
        data['lesson_version'] == _currentLessonVersion;
  }

  @override
  Future<int> currentStep() async {
    final contents = _file == null
        ? await readBrowserLocal('resonant.onboarding')
        : await _readFile();
    if (contents == null) return 0;
    final data = jsonDecode(contents);
    final step = data is Map ? data['step'] : null;
    return step is int && step >= 0 && step < 10 ? step : 0;
  }

  @override
  Future<void> saveStep(int step) async {
    final contents = jsonEncode({
      'completed': false,
      'step': step.clamp(0, 9),
      'lesson_version': _currentLessonVersion,
    });
    await _write(contents);
  }

  @override
  Future<void> markComplete() async {
    final contents = jsonEncode({
      'completed': true,
      'step': 0,
      'lesson_version': _currentLessonVersion,
    });
    await _write(contents);
  }

  Future<String?> _readFile() async {
    final source = _file!;
    if (!await source.exists()) return null;
    return source.readAsString();
  }

  Future<void> _write(String contents) async {
    if (_file == null) {
      await writeBrowserLocal('resonant.onboarding', contents);
      return;
    }
    final target = _file;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
}
