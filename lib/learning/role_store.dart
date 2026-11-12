import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

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
  final File file;

  RoleStore(this.file);

  static Future<RoleStore> forApplication() async {
    // Browsers have no filesystem: keep state in memory for the session.
    if (kIsWeb) return RoleStore(MemoryFileSystem().file('/role.json'));
    final directory = await getApplicationDocumentsDirectory();
    return RoleStore(
      File('${directory.path}${Platform.pathSeparator}role.json'),
    );
  }

  @override
  Future<AppRole?> savedRole() async {
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
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
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'role': role.name}),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<void> clearRole() async {
    if (await file.exists()) await file.delete();
  }
}

