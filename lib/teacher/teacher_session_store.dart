import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/browser_storage.dart';

/// A teacher's locally persisted auth session.
class TeacherSession {
  final String teacherId;
  final String name;
  final String email;
  final String? organization;
  final String token;

  const TeacherSession({
    required this.teacherId,
    required this.name,
    required this.email,
    this.organization,
    required this.token,
  });

  Map<String, dynamic> toJson() => {
        'teacher_id': teacherId,
        'name': name,
        'email': email,
        'organization': organization,
        'token': token,
      };

  factory TeacherSession.fromJson(Map<String, dynamic> json) => TeacherSession(
        teacherId: json['teacher_id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        organization: json['organization'] as String?,
        token: json['token'] as String,
      );
}

abstract interface class TeacherSessionStorage {
  Future<TeacherSession?> load();
  Future<void> save(TeacherSession session);
  Future<void> clear();
}

/// Atomic-write JSON persistence following the [OnboardingStore] pattern.
class TeacherSessionStore implements TeacherSessionStorage {
  final File? file;

  TeacherSessionStore(this.file);
  TeacherSessionStore.web() : file = null;

  static Future<TeacherSessionStore> forApplication() async {
    if (kIsWeb) return TeacherSessionStore.web();
    final directory = await getApplicationDocumentsDirectory();
    return TeacherSessionStore(
      File('${directory.path}${Platform.pathSeparator}teacher_session.json'),
    );
  }

  @override
  Future<TeacherSession?> load() async {
    final contents = file == null
        ? await readBrowserSession('resonant.teacher-session')
        : await _readFile();
    if (contents == null) return null;
    try {
      final data = jsonDecode(contents);
      if (data is! Map<String, dynamic>) return null;
      return TeacherSession.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(TeacherSession session) async {
    final contents = jsonEncode(session.toJson());
    if (file == null) {
      await writeBrowserSession('resonant.teacher-session', contents);
      return;
    }
    final target = file!;
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    if (await target.exists()) await target.delete();
    await tmp.rename(target.path);
  }

  @override
  Future<void> clear() async {
    if (file == null) {
      await removeBrowserSession('resonant.teacher-session');
    } else if (await file!.exists()) {
      await file!.delete();
    }
  }

  Future<String?> _readFile() async {
    final source = file!;
    if (!await source.exists()) return null;
    return source.readAsString();
  }
}

