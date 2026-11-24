import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/tutor/voice_command_parser.dart';

void main() {
  test(
    'commands cover lesson navigation, word tests, hints and accessibility',
    () {
      expect(
        VoiceCommandParser.parse('Start the test')?.command,
        VoiceCommand.startTest,
      );
      expect(
        VoiceCommandParser.parse('Repeat the word')?.command,
        VoiceCommand.repeatWord,
      );
      expect(
        VoiceCommandParser.parse('Clear my pattern')?.command,
        VoiceCommand.clearPattern,
      );
      expect(
        VoiceCommandParser.parse('Give me a hint')?.command,
        VoiceCommand.giveHint,
      );
      final answer = VoiceCommandParser.parse('Choose answer B');
      expect(answer?.command, VoiceCommand.selectAnswer);
      expect(answer?.target, 'b');
      expect(
        VoiceCommandParser.parse('What is my progress')?.command,
        VoiceCommand.showProgress,
      );
      expect(
        VoiceCommandParser.parse('Review my mistakes')?.command,
        VoiceCommand.reviewDifficult,
      );
      expect(
        VoiceCommandParser.parse('Accessibility settings')?.command,
        VoiceCommand.openSettings,
      );
    },
  );

  test('detects structured chapter and assessment intents without an LLM', () {
    expect(
      VoiceCommandParser.parse('Teach me the next chapter')?.command,
      VoiceCommand.nextChapter,
    );
    expect(
      VoiceCommandParser.parse('Previous chapter')?.command,
      VoiceCommand.previousChapter,
    );
    final chapter = VoiceCommandParser.parse('Go to chapter 3');
    expect(chapter?.command, VoiceCommand.goToChapter);
    expect(chapter?.target, '3');

    final wordTest = VoiceCommandParser.parse(
      'I want to test myself with words',
    );
    expect(wordTest?.command, VoiceCommand.startWordTest);
    expect(
      VoiceCommandParser.parse("Let's do a word test")?.command,
      VoiceCommand.startWordTest,
    );
    expect(
      VoiceCommandParser.parse('Take me to the words assessment')?.command,
      VoiceCommand.startWordTest,
    );
    expect(VoiceCommandParser.parse("Let's practice words")?.target, 'words');

    final sentenceTest = VoiceCommandParser.parse(
      'I want to test myself with sentences',
    );
    expect(sentenceTest?.command, VoiceCommand.startSkillTest);
    expect(sentenceTest?.target, 'sentences');

    final revision = VoiceCommandParser.parse(
      'Revise what I learned yesterday',
    );
    expect(revision?.command, VoiceCommand.startRevision);
    expect(revision?.target, 'yesterday');

    final targeted = VoiceCommandParser.parse(
      'I am struggling with these letters',
    );
    expect(targeted?.command, VoiceCommand.startTargetedPractice);
    expect(targeted?.target, 'letters');
  });

  test('detects difficulty, pause and explicit language actions', () {
    final harder = VoiceCommandParser.parse("Let's do a harder test");
    expect(harder?.command, VoiceCommand.changeDifficulty);
    expect(harder?.difficulty, 'harder');

    expect(
      VoiceCommandParser.parse('Pause learning')?.command,
      VoiceCommand.pauseLearning,
    );
    expect(
      VoiceCommandParser.parse('Resume learning')?.command,
      VoiceCommand.resumeLearning,
    );

    final language = VoiceCommandParser.parse('Switch language to Kannada');
    expect(language?.command, VoiceCommand.switchLanguage);
    expect(language?.languageCode, 'kannada');
  });

  test('detects remediation and decision-explanation actions locally', () {
    expect(
      VoiceCommandParser.parse('Start my remediation')?.command,
      VoiceCommand.startRemediation,
    );
    expect(
      VoiceCommandParser.parse('Why was I redirected')?.command,
      VoiceCommand.explainAdaptiveSelection,
    );
  });

  test('routes learner struggle phrases to the contextual hint action', () {
    for (final phrase in [
      "I don't know",
      "I can't answer",
      "I don't understand",
      'Teach me this',
      'Take me to the lesson',
      'Help me learn this',
      'I forgot',
      'Can you explain this?',
      "I'm stuck",
      'Help me with this',
    ]) {
      expect(
        VoiceCommandParser.parse(phrase)?.command,
        VoiceCommand.giveHint,
        reason: phrase,
      );
    }
  });

  test('recognizes action phrases and spoken option references', () {
    expect(
      VoiceCommandParser.parse('Go to the next exercise')?.command,
      VoiceCommand.nextLesson,
    );
    expect(
      VoiceCommandParser.parse('Next question')?.command,
      VoiceCommand.nextLesson,
    );
    expect(
      VoiceCommandParser.parse('Previous exercise')?.command,
      VoiceCommand.previousExercise,
    );
    expect(
      VoiceCommandParser.parse('Switch to Kannada')?.languageCode,
      'kannada',
    );
    expect(
      VoiceCommandParser.parse('Change to Hindi module')?.languageCode,
      'hindi',
    );
    expect(VoiceCommandParser.parse('Start English')?.languageCode, 'english');
    expect(
      VoiceCommandParser.parse('Repeat the question')?.command,
      VoiceCommand.repeatQuestion,
    );
    expect(
      VoiceCommandParser.parse('Show me a hint')?.command,
      VoiceCommand.giveHint,
    );
    expect(VoiceCommandParser.parse('Option B')?.target, 'b');
    expect(VoiceCommandParser.parse('The second option')?.target, 'second');
    expect(
      VoiceCommandParser.parse('The answer is option 1')?.target,
      'option 1',
    );
    expect(
      VoiceCommandParser.parse('I want to exit the test')?.command,
      VoiceCommand.exitAssessment,
    );
  });

  test('normalizes tested English, Hindi, Kannada and Romanized commands', () {
    for (final phrase in [
      'Let us do Kannada now',
      'I want to learn in Kannada',
      'मुझे कन्नड़ में ले चलो',
      'मुझे हिंदी में पढ़ना है',
      'ನನ್ನನ್ನು ಕನ್ನಡಕ್ಕೆ ಬದಲಾಯಿಸು',
      'kannada mein le chalo',
      'kannada ge change maadi',
    ]) {
      expect(
        VoiceCommandParser.parse(phrase)?.languageCode,
        phrase.contains('हिंदी') ? 'hindi' : 'kannada',
        reason: phrase,
      );
    }
    for (final phrase in [
      'Agla exercise',
      'ಮುಂದಿನ ಅಭ್ಯಾಸಕ್ಕೆ ಹೋಗು',
      'अगला अभ्यास खोलो',
      'Skip to the next exercise',
    ]) {
      expect(
        VoiceCommandParser.parse(phrase)?.command,
        VoiceCommand.nextLesson,
        reason: phrase,
      );
    }
    expect(
      VoiceCommandParser.parse('Mera answer check karo')?.command,
      VoiceCommand.checkAnswer,
    );
    expect(
      VoiceCommandParser.parse('Nanna answer check maadi')?.command,
      VoiceCommand.checkAnswer,
    );
    expect(
      VoiceCommandParser.parse('ಇಂಗ್ಲಿಷ್‌ಗೆ ಬದಲಾಯಿಸು')?.languageCode,
      'english',
    );
    expect(
      VoiceCommandParser.parse('English ge hogu')?.languageCode,
      'english',
    );
    expect(
      VoiceCommandParser.parse('Hint kodi')?.command,
      VoiceCommand.giveHint,
    );
    expect(
      VoiceCommandParser.parse('Question ge hogu')?.command,
      isNull,
      reason: 'Unsupported ambiguous phrasing must not trigger an action.',
    );
  });

  test('extracts letter targets from natural navigation forms', () {
    for (final phrase in [
      'I want to learn letter K',
      'Take me to letter E',
      'Open the K lesson',
      'Go to English letter B',
    ]) {
      expect(
        VoiceCommandParser.parse(phrase)?.command,
        VoiceCommand.teachLetter,
        reason: phrase,
      );
    }
    expect(
      VoiceCommandParser.parse('Go to English letter B')?.languageCode,
      'english',
    );
    expect(VoiceCommandParser.parse('I want to learn letter K')?.letter, 'K');
  });

  test('recognizes screen-aware reading and contextual action intents', () {
    expect(
      VoiceCommandParser.parse('Read my screen')?.command,
      VoiceCommand.readScreen,
    );
    expect(
      VoiceCommandParser.parse('Read this question')?.command,
      VoiceCommand.readQuestion,
    );
    expect(
      VoiceCommandParser.parse('What are the options?')?.command,
      VoiceCommand.readOptions,
    );
    expect(
      VoiceCommandParser.parse('Explain what I am supposed to do')?.command,
      VoiceCommand.readInstructions,
    );
    expect(
      VoiceCommandParser.parse('What exercise am I on?')?.command,
      VoiceCommand.whatExercise,
    );
    expect(
      VoiceCommandParser.parse('Explain this')?.command,
      VoiceCommand.explainCurrentContent,
    );
    expect(VoiceCommandParser.parse('What does option C mean?')?.target, 'c');
    expect(VoiceCommandParser.parse('Choose the second one')?.target, 'second');
    expect(
      VoiceCommandParser.parse('Submit')?.command,
      VoiceCommand.checkAnswer,
    );
    expect(VoiceCommandParser.parse('Next')?.command, VoiceCommand.nextLesson);
  });
}
