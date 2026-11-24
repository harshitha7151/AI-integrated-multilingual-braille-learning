import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/browser_storage.dart';

/// The two selectable roles in Resonant.
enum AppRole { learner, teacher }

abstract interface class RoleStorage {
  /// Returns the previously chosen role, or null if none has been saved.
  Future<AppRole?> savedRole();

  /// Persists [role] so the role-selection screen is skipped on next launch.
  Future<void> saveRole(AppRole role);

  /// Clears the persisted role so the selection screen is shown again.
  Future<void> clearRole();
}

/// Persists the chosen role locally using an atomic write, following the same
/// pattern as [OnboardingStore].
class RoleStore implements RoleStorage {
  final File? _file;
  File get file => _file!;

  RoleStore(File file) : _file = file;
  RoleStore.web() : _file = null;

  static Future<RoleStore> forApplication() async {
    if (kIsWeb) return RoleStore.web();
    final directory = await getApplicationDocumentsDirectory();
    return RoleStore(
      File('${directory.path}${Platform.pathSeparator}role.json'),
    );
  }

  @override
  Future<AppRole?> savedRole() async {
    final contents = _file == null
        ? await readBrowserLocal('resonant.role')
        : await _readFile();
    if (contents == null) return null;
    try {
      final data = jsonDecode(contents);
      if (data is! Map) return null;
      return switch (data['role']) {
        'learner' => AppRole.learner,
        'teacher' => AppRole.teacher,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveRole(AppRole role) async {
    final contents = jsonEncode({'role': role.name});
    if (_file == null) {
      await writeBrowserLocal('resonant.role', contents);
      return;
    }
    final target = _file;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  @override
  Future<void> clearRole() async {
    if (_file == null) {
      await removeBrowserLocal('resonant.role');
    } else if (await _file.exists()) {
      await _file.delete();
    }
  }

  Future<String?> _readFile() async {
    final source = _file!;
    if (!await source.exists()) return null;
    return source.readAsString();
  }
}
