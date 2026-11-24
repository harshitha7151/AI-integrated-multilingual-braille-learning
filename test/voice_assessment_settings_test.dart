import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/tutor/voice_assessment_settings.dart';

void main() {
  test('settings persist and listening timeout is bounded', () async {
    final directory = await Directory.systemTemp.createTemp(
      'resonant-voice-settings',
    );
    try {
      final store = VoiceAssessmentSettingsStore(
        File('${directory.path}/settings.json'),
      );
      const settings = VoiceAssessmentSettings(
        enabled: true,
        activateTutorOnAssessment: true,
        readQuestions: true,
        readOptions: false,
        listenAfterReading: true,
        confirmSelection: true,
        autoRelisten: false,
        timeoutSeconds: 80,
        recognitionLocale: 'hi-IN',
      );
      await store.save(settings);
      final restored = await store.load();
      expect(restored.enabled, isTrue);
      expect(restored.activateTutorOnAssessment, isTrue);
      expect(restored.readOptions, isFalse);
      expect(restored.listenAfterReading, isTrue);
      expect(restored.timeoutSeconds, 80);
      expect(restored.recognitionLocale, 'hi-IN');
      expect(settings.copyWith(timeoutSeconds: 500).timeoutSeconds, 120);
      expect(settings.copyWith(timeoutSeconds: 2).timeoutSeconds, 10);
      expect(
        VoiceAssessmentSettings.fromJson({
          'recognition_locale': 'unsupported',
        }).recognitionLocale,
        'system',
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
