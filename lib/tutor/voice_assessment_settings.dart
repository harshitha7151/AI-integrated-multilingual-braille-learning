import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/browser_storage.dart';

class VoiceAssessmentSettings {
  const VoiceAssessmentSettings({
    this.enabled = false,
    this.activateTutorOnAssessment = false,
    this.readQuestions = true,
    this.readOptions = true,
    this.listenAfterReading = false,
    this.confirmSelection = true,
    this.stopListeningForSpeech = true,
    this.autoRelisten = false,
    this.timeoutSeconds = 30,
    this.recognitionLocale = 'system',
  });

  final bool enabled;
  final bool activateTutorOnAssessment;
  final bool readQuestions;
  final bool readOptions;
  final bool listenAfterReading;
  final bool confirmSelection;
  final bool stopListeningForSpeech;
  final bool autoRelisten;
  final int timeoutSeconds;

  /// Recognition may follow the selected lesson language or use an explicit
  /// override. It is passed separately from tutor TTS configuration.
  final String recognitionLocale;

  String recognitionLocaleFor(String selectedLanguageLocale) =>
      recognitionLocale == 'system' || recognitionLocale.isEmpty
      ? selectedLanguageLocale
      : recognitionLocale;

  VoiceAssessmentSettings copyWith({
    bool? enabled,
    bool? activateTutorOnAssessment,
    bool? readQuestions,
    bool? readOptions,
    bool? listenAfterReading,
    bool? confirmSelection,
    bool? stopListeningForSpeech,
    bool? autoRelisten,
    int? timeoutSeconds,
    String? recognitionLocale,
  }) => VoiceAssessmentSettings(
    enabled: enabled ?? this.enabled,
    activateTutorOnAssessment:
        activateTutorOnAssessment ?? this.activateTutorOnAssessment,
    readQuestions: readQuestions ?? this.readQuestions,
    readOptions: readOptions ?? this.readOptions,
    listenAfterReading: listenAfterReading ?? this.listenAfterReading,
    confirmSelection: confirmSelection ?? this.confirmSelection,
    stopListeningForSpeech:
        stopListeningForSpeech ?? this.stopListeningForSpeech,
    autoRelisten: autoRelisten ?? this.autoRelisten,
    timeoutSeconds: (timeoutSeconds ?? this.timeoutSeconds).clamp(10, 120),
    recognitionLocale: recognitionLocale ?? this.recognitionLocale,
  );

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'activate_tutor_on_assessment': activateTutorOnAssessment,
    'read_questions': readQuestions,
    'read_options': readOptions,
    'listen_after_reading': listenAfterReading,
    'confirm_selection': confirmSelection,
    'stop_listening_for_speech': stopListeningForSpeech,
    'auto_relisten': autoRelisten,
    'timeout_seconds': timeoutSeconds,
    'recognition_locale': recognitionLocale,
  };

  factory VoiceAssessmentSettings.fromJson(Map<String, dynamic> json) =>
      VoiceAssessmentSettings(
        enabled: json['enabled'] == true,
        activateTutorOnAssessment: json['activate_tutor_on_assessment'] == true,
        readQuestions: json['read_questions'] != false,
        readOptions: json['read_options'] != false,
        listenAfterReading: json['listen_after_reading'] == true,
        confirmSelection: json['confirm_selection'] != false,
        stopListeningForSpeech: json['stop_listening_for_speech'] != false,
        autoRelisten: json['auto_relisten'] == true,
        timeoutSeconds: json['timeout_seconds'] is int
            ? (json['timeout_seconds'] as int).clamp(10, 120)
            : 30,
        recognitionLocale: switch (json['recognition_locale']) {
          // Migrate the previous English choice to the requested India locale.
          'en-US' => 'en-IN',
          'system' ||
          'en-IN' ||
          'hi-IN' ||
          'kn-IN' => json['recognition_locale'] as String,
          _ => 'system',
        },
      );
}

class VoiceAssessmentSettingsStore {
  VoiceAssessmentSettingsStore(this.file);
  final File? file;
  VoiceAssessmentSettingsStore.web() : file = null;

  static Future<VoiceAssessmentSettingsStore> forApplication() async {
    if (kIsWeb) return VoiceAssessmentSettingsStore.web();
    final directory = await getApplicationDocumentsDirectory();
    return VoiceAssessmentSettingsStore(
      File(
        '${directory.path}${Platform.pathSeparator}voice-assessment-settings.json',
      ),
    );
  }

  Future<VoiceAssessmentSettings> load() async {
    final contents = file == null
        ? await readBrowserLocal('resonant.voice-assessment-settings')
        : await _readFile();
    if (contents == null) return const VoiceAssessmentSettings();
    try {
      final value = jsonDecode(contents);
      return value is Map
          ? VoiceAssessmentSettings.fromJson(Map<String, dynamic>.from(value))
          : const VoiceAssessmentSettings();
    } catch (_) {
      return const VoiceAssessmentSettings();
    }
  }

  Future<void> save(VoiceAssessmentSettings settings) async {
    final contents = jsonEncode(settings.toJson());
    if (file == null) {
      await writeBrowserLocal('resonant.voice-assessment-settings', contents);
      return;
    }
    final target = file!;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<String?> _readFile() async {
    final source = file!;
    if (!await source.exists()) return null;
    return source.readAsString();
  }
}
