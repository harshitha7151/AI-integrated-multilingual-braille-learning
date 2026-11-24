import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/learning/chapter_navigation_controller.dart';
import 'package:resonant_braille/tutor/tutor_action_controller.dart';
import 'package:resonant_braille/tutor/voice_command_parser.dart';

void main() {
  const controller = TutorActionController();

  TutorActionContext context({
    bool paused = false,
    bool assessmentActive = false,
    bool wordTest = false,
    bool moduleTest = false,
    bool revision = false,
    bool targeted = false,
    bool adaptive = false,
    bool remediation = false,
    bool composedResponseTest = false,
    bool sentenceResponseTest = false,
    int chapter = 1,
  }) => TutorActionContext(
    navigation: LearningNavigationContext(
      language: AppLanguage.english,
      chapterIndex: chapter,
      lessonIndex: 0,
      wordChapterIndex: 0,
      englishLetterCourseComplete: false,
    ),
    learningPaused: paused,
    assessmentActive: assessmentActive,
    wordTestAvailable: wordTest,
    moduleTestAvailable: moduleTest,
    hasRevisionHistory: revision,
    hasTargetedPractice: targeted,
    hasAdaptiveDecision: adaptive,
    adaptiveRemediationRequired: remediation,
    composedResponseTestAvailable: composedResponseTest,
    sentenceResponseTestAvailable: sentenceResponseTest,
  );

  test('validates a word-test action only when prerequisites expose one', () {
    final parsed = VoiceCommandParser.parse(
      'I want to test myself with words',
    )!;
    expect(
      controller.resolve(parsed, context()).status,
      TutorActionStatus.blocked,
    );
    expect(
      controller.resolve(parsed, context(wordTest: true)).status,
      TutorActionStatus.ready,
    );
    expect(
      controller
          .resolve(
            parsed,
            context(wordTest: true, assessmentActive: true, remediation: true),
          )
          .status,
      TutorActionStatus.ready,
    );
  });

  test('gates validated sentence tests behind curriculum prerequisites', () {
    final parsed = VoiceCommandParser.parse(
      'I want to test myself with sentences',
    )!;
    final blocked = controller.resolve(parsed, context());
    expect(blocked.status, TutorActionStatus.blocked);
    expect(blocked.message, contains('word mastery'));

    final ready = controller.resolve(
      parsed,
      context(sentenceResponseTest: true),
    );
    expect(ready.status, TutorActionStatus.ready);
    expect(ready.message, contains('six-dot'));
  });

  test('keeps phrase and sentence availability separate', () {
    final phrase = VoiceCommandParser.parse(
      'I want to test myself with phrases',
    )!;
    final sentence = VoiceCommandParser.parse(
      'I want to test myself with sentences',
    )!;
    final afterWordMastery = context(composedResponseTest: true);

    expect(
      controller.resolve(phrase, afterWordMastery).status,
      TutorActionStatus.ready,
    );
    expect(
      controller.resolve(sentence, afterWordMastery).status,
      TutorActionStatus.blocked,
    );
  });

  test('keeps executable actions paused until an explicit resume', () {
    final next = VoiceCommandParser.parse('Next chapter')!;
    final blocked = controller.resolve(next, context(paused: true));
    expect(blocked.status, TutorActionStatus.blocked);
    expect(blocked.message, contains('Learning is paused'));

    final resume = VoiceCommandParser.parse('Resume learning')!;
    expect(
      controller.resolve(resume, context(paused: true)).status,
      TutorActionStatus.ready,
    );
  });

  test('returns a structured validated navigation destination', () {
    final parsed = VoiceCommandParser.parse('Go to chapter 1')!;
    final result = controller.resolve(parsed, context());
    expect(result.status, TutorActionStatus.ready);
    expect(result.navigation?.chapterIndex, 0);
    expect(result.navigation?.lessonIndex, 0);
  });

  test('lesson menu capability remains available from a paused assessment', () {
    final menu = controller.resolve(
      const ParsedVoiceCommand(VoiceCommand.openLessonMenu),
      context(paused: true, assessmentActive: true),
    );
    expect(menu.status, TutorActionStatus.ready);
  });

  test('explicit navigation remains available during an active assessment', () {
    final next = VoiceCommandParser.parse('Next chapter')!;
    final result = controller.resolve(next, context(assessmentActive: true));
    expect(result.status, TutorActionStatus.ready);

    for (final phrase in ['Next exercise', 'Previous exercise']) {
      final exerciseCommand = VoiceCommandParser.parse(phrase)!;
      expect(
        controller
            .resolve(exerciseCommand, context(assessmentActive: true))
            .status,
        TutorActionStatus.ready,
      );
    }
  });

  test('remediation remains available without locking explicit navigation', () {
    final remediation = VoiceCommandParser.parse('Start remediation')!;
    expect(
      controller.resolve(remediation, context()).status,
      TutorActionStatus.blocked,
    );
    expect(
      controller.resolve(remediation, context(remediation: true)).status,
      TutorActionStatus.ready,
    );

    final next = VoiceCommandParser.parse('Next lesson')!;
    expect(
      controller.resolve(next, context(remediation: true)).status,
      TutorActionStatus.ready,
    );
  });

  test('explains a recorded adaptive selection only when evidence exists', () {
    final why = VoiceCommandParser.parse('Why this lesson')!;
    expect(
      controller.resolve(why, context()).status,
      TutorActionStatus.blocked,
    );
    expect(
      controller.resolve(why, context(adaptive: true)).status,
      TutorActionStatus.ready,
    );
  });
}
