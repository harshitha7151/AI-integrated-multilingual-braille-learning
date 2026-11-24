import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/tutor/speech_to_text_recognizer.dart';
import 'package:resonant_braille/tutor/voice_assessment_settings.dart';

void main() {
  test('system locale is independent and does not pin recognition', () {
    expect(speechRecognitionLocaleId('system'), isNull);
    expect(speechRecognitionLocaleId(''), isNull);
  });

  test('explicit recognition locale is passed to the platform service', () {
    expect(speechRecognitionLocaleId('en-US'), 'en-US');
    expect(speechRecognitionLocaleId('en-IN'), 'en-IN');
    expect(speechRecognitionLocaleId('hi-IN'), 'hi-IN');
    expect(speechRecognitionLocaleId('kn-IN'), 'kn-IN');
  });

  test('follow-learning-language selects the matching India locale', () {
    const settings = VoiceAssessmentSettings();
    expect(settings.recognitionLocaleFor('en-IN'), 'en-IN');
    expect(settings.recognitionLocaleFor('hi-IN'), 'hi-IN');
    expect(settings.recognitionLocaleFor('kn-IN'), 'kn-IN');
  });

  test('explicit recognition locale overrides the learning language', () {
    const settings = VoiceAssessmentSettings(recognitionLocale: 'kn-IN');
    expect(settings.recognitionLocaleFor('en-IN'), 'kn-IN');
  });

  test('device locale matching honors region and does not cross languages', () {
    expect(matchSpeechRecognitionLocale('kn-IN', ['en-IN', 'kn_IN']), 'kn_IN');
    expect(
      matchSpeechRecognitionLocale('hi-IN', ['en-IN']),
      isNull,
      reason: 'An unavailable Hindi locale must not fall back to English.',
    );
    expect(matchSpeechRecognitionLocale('hi-IN', []), 'hi-IN');
  });

  test('legacy English recognition preference migrates to English India', () {
    expect(
      VoiceAssessmentSettings.fromJson({
        'recognition_locale': 'en-US',
      }).recognitionLocale,
      'en-IN',
    );
  });
}
