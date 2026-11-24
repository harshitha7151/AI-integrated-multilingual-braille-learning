import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/browser_storage.dart';

/// A registered learner account saved locally after teacher-assisted
/// registration (or account restore).
class LearnerAccount {
  final String learnerId;
  final String learnerCode; // 6-digit code, kept locally for display/restore
  final String name;
  final String? phone;
  final String? email;
  final String? batch;
  final String preferredLanguage;

  const LearnerAccount({
    required this.learnerId,
    required this.learnerCode,
    required this.name,
    this.phone,
    this.email,
    this.batch,
    this.preferredLanguage = 'English',
  });

  Map<String, dynamic> toJson() => {
        'learner_id': learnerId,
        'learner_code': learnerCode,
        'name': name,
        'phone': phone,
        'email': email,
        'batch': batch,
        'preferred_language': preferredLanguage,
      };

  factory LearnerAccount.fromJson(Map<String, dynamic> json) => LearnerAccount(
        learnerId: json['learner_id'] as String,
        learnerCode: json['learner_code'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        batch: json['batch'] as String?,
        preferredLanguage:
            json['preferred_language'] as String? ?? 'English',
      );

  LearnerAccount withPreferredLanguage(String language) => LearnerAccount(
        learnerId: learnerId,
        learnerCode: learnerCode,
        name: name,
        phone: phone,
        email: email,
        batch: batch,
        preferredLanguage: language,
      );
}

abstract interface class LearnerAccountStorage {
  /// Returns the locally saved learner account, or null if none exists.
  Future<LearnerAccount?> load();

  /// Persists the account atomically (write-then-rename).
  Future<void> save(LearnerAccount account);

  /// Removes the saved account (e.g., on sign-out).
  Future<void> clear();
}

/// Atomic-write JSON persistence following the [OnboardingStore] pattern.
class LearnerAccountStore implements LearnerAccountStorage {
  final File? file;

  LearnerAccountStore(this.file);
  LearnerAccountStore.web() : file = null;

  static Future<LearnerAccountStore> forApplication() async {
    if (kIsWeb) return LearnerAccountStore.web();
    final directory = await getApplicationDocumentsDirectory();
    return LearnerAccountStore(
      File('${directory.path}${Platform.pathSeparator}learner_account.json'),
    );
  }

  @override
  Future<LearnerAccount?> load() async {
    final contents = file == null
        ? await readBrowserSession('resonant.learner-account')
        : await _readFile();
    if (contents == null) return null;
    try {
      final data = jsonDecode(contents);
      if (data is! Map<String, dynamic>) return null;
      return LearnerAccount.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(LearnerAccount account) async {
    final contents = jsonEncode(account.toJson());
    if (file == null) {
      await writeBrowserSession('resonant.learner-account', contents);
      return;
    }
    final target = file!;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  @override
  Future<void> clear() async {
    if (file == null) {
      await removeBrowserSession('resonant.learner-account');
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

