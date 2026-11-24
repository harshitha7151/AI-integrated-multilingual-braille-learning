enum VoiceCommand {
  startLearning,
  resumeLearning,
  pauseLearning,
  teachLetter,
  repeat,
  repeatLesson,
  explainDots,
  startPractice,
  startTargetedPractice,
  startRemediation,
  explainAdaptiveSelection,
  selectAnswer,
  checkAnswer,
  nextLesson,
  previousExercise,
  repeatQuestion,
  readScreen,
  readQuestion,
  readOptions,
  readInstructions,
  readFeedback,
  whatExercise,
  explainCurrentContent,
  explainOption,
  nextChapter,
  previousChapter,
  goToChapter,
  goToLesson,
  moduleBeginning,
  goBack,
  exitAssessment,
  home,
  openTutor,
  openLessonMenu,
  stopSpeaking,
  repeatWord,
  clearPattern,
  giveHint,
  showProgress,
  getSkillMastery,
  getRecommendation,
  reviewDifficult,
  openSettings,
  startTest,
  startAssessment,
  startWordTest,
  startSkillTest,
  startModuleTest,
  startRevision,
  changeDifficulty,
  switchLanguage,
  help,
}

class ParsedVoiceCommand {
  final VoiceCommand command;
  final String? letter;
  final String? target;
  final String? languageCode;
  final String? difficulty;

  const ParsedVoiceCommand(
    this.command, {
    this.letter,
    this.target,
    this.languageCode,
    this.difficulty,
  });
}

/// Deterministic intent detection for executable learning actions.
///
/// This parser never executes an action. Callers must validate the structured
/// result against the curriculum and current learner state before changing UI
/// state. Questions that do not match remain with the conversational tutor.
class VoiceCommandParser {
  static ParsedVoiceCommand? parse(String input) {
    final normalized = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final text = _canonicalizePhrase(normalized);

    final language = RegExp(
      r'^(?:(?:switch|change|set)(?: my| the)? language to|(?:switch|change) to|start|i want(?: to learn in| to use)?) (english|hindi|kannada)(?: (?:module|lessons?|now))?$|^(?:open|take me to) (english|hindi|kannada) lessons?$',
    ).firstMatch(text);
    if (language != null) {
      final languageName = language.group(1) ?? language.group(2);
      return ParsedVoiceCommand(
        VoiceCommand.switchLanguage,
        languageCode: languageName,
      );
    }

    if ({
      'read my screen',
      'read the screen',
      'read screen',
      'what is displayed here',
      'what is on this screen',
      'what is displayed on my screen',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.readScreen);
    }
    if ({
      'read this question',
      'read the question',
      'read question',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.readQuestion);
    }
    if ({
      'read the options',
      'read all the options',
      'read choices',
      'read the choices',
      'what are the options',
      'what are the choices',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.readOptions);
    }
    if ({
      'read the instructions',
      'read instructions',
      'explain what i am supposed to do',
      "explain what i'm supposed to do",
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.readInstructions);
    }
    if ({
      'read the feedback',
      'read feedback',
      'what was my feedback',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.readFeedback);
    }
    if ({
      'what exercise am i on',
      'which exercise am i on',
      'what lesson am i on',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.whatExercise);
    }
    if ({
      'explain this',
      'explain that',
      'explain the current question',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.explainCurrentContent);
    }
    final explainOption = RegExp(
      r'^(?:what does|explain) (?:option|choice) ([a-e])(?: mean)?$',
    ).firstMatch(text);
    if (explainOption != null) {
      return ParsedVoiceCommand(
        VoiceCommand.explainOption,
        target: explainOption.group(1),
      );
    }

    // A short struggle utterance is an action request, not a general chatbot
    // question. Route it to the existing context-sensitive hint handler.
    if ({
      "i don't know",
      'i do not know',
      "i can't answer",
      'i cannot answer',
      "i don't understand",
      'i do not understand',
      'teach me this',
      'take me to the lesson',
      'help me learn this',
      'i forgot',
      'can you explain this',
      'i am stuck',
      "i'm stuck",
      'help me with this',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.giveHint);
    }

    if ({
      'repeat question',
      'repeat the question',
      'repeat current question',
      'say the question again',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.repeatQuestion);
    }
    if ({
      'show me a hint',
      'show me hint',
      'give me a hint',
      'give a hint',
      'hint',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.giveHint);
    }
    if ({
      'next exercise',
      'go to the next exercise',
      'next question',
      'go to the next question',
      'move to the next question',
      'next item',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.nextLesson);
    }
    if ({
      'previous exercise',
      'go to the previous exercise',
      'previous question',
      'go to the previous question',
      'move to the previous question',
      'previous item',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.previousExercise);
    }
    if ({'हिंदी भाषा', 'हिंदी में बदलो'}.contains(text)) {
      return const ParsedVoiceCommand(
        VoiceCommand.switchLanguage,
        languageCode: 'hindi',
      );
    }
    if ({'ಕನ್ನಡ ಭಾಷೆ', 'ಕನ್ನಡಕ್ಕೆ ಬದಲಿಸಿ'}.contains(text)) {
      return const ParsedVoiceCommand(
        VoiceCommand.switchLanguage,
        languageCode: 'kannada',
      );
    }

    if ({
      'next chapter',
      'go to the next chapter',
      'move forward',
      'teach me the next chapter',
      'अगला अध्याय',
      'ಮುಂದಿನ ಅಧ್ಯಾಯ',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.nextChapter);
    }
    if ({
      'previous chapter',
      'go to the previous chapter',
      'move back a chapter',
      'पिछला अध्याय',
      'ಹಿಂದಿನ ಅಧ್ಯಾಯ',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.previousChapter);
    }
    final chapter = RegExp(
      r'^(?:go|skip|move) to (?:the )?(?:named )?chapter (.+)$',
    ).firstMatch(text);
    if (chapter != null) {
      return ParsedVoiceCommand(
        VoiceCommand.goToChapter,
        target: chapter.group(1)!.trim(),
      );
    }
    final lesson = RegExp(
      r'^(?:go|skip|move) to (?:the )?(?:named )?lesson (.+)$',
    ).firstMatch(text);
    if (lesson != null) {
      return ParsedVoiceCommand(
        VoiceCommand.goToLesson,
        target: lesson.group(1)!.trim(),
      );
    }
    if ({
      'go to the beginning of this module',
      'beginning of this module',
      'start this module again',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.moduleBeginning);
    }
    if ({
      'repeat this chapter',
      'repeat this lesson',
      'start this chapter again',
      'start this lesson again',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.repeatLesson);
    }

    if (RegExp(r'\b(?:harder|more difficult) test\b').hasMatch(text)) {
      return const ParsedVoiceCommand(
        VoiceCommand.changeDifficulty,
        difficulty: 'harder',
      );
    }
    if (RegExp(r'\b(?:easier|simpler) test\b').hasMatch(text)) {
      return const ParsedVoiceCommand(
        VoiceCommand.changeDifficulty,
        difficulty: 'easier',
      );
    }
    if (RegExp(
          r'\b(?:test|assess)(?: me| myself)? (?:with|on) words\b|\bwords?\s+(?:assessment|test)\b|\b(?:assessment|test)\s+(?:with\s+)?words?\b',
        ).hasMatch(text) ||
        {'word test', 'start word test', 'test me with words'}.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.startWordTest);
    }
    if (RegExp(
      r'\b(?:practice|learn|study)\b.*\bwords?\b|\bwords?\b.*\b(?:practice|learn|study)\b',
    ).hasMatch(text)) {
      return const ParsedVoiceCommand(
        VoiceCommand.goToChapter,
        target: 'words',
      );
    }
    final skillTest = RegExp(
      r'^(?:i want to )?(?:test|assess) (?:me|myself) (?:with|on) (.+)$',
    ).firstMatch(text);
    if (skillTest != null) {
      return ParsedVoiceCommand(
        VoiceCommand.startSkillTest,
        target: skillTest.group(1)!.trim(),
      );
    }
    if ({
      'start module test',
      'test this module',
      'module test',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.startModuleTest);
    }
    if ({
      'start assessment',
      'begin assessment',
      'assess me',
      'test me',
      'परीक्षा शुरू करो',
      'ಪರೀಕ್ಷೆ ಪ್ರಾರಂಭಿಸಿ',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.startAssessment);
    }
    if (RegExp(
      r'\b(?:revise|review) what i learned yesterday\b',
    ).hasMatch(text)) {
      return const ParsedVoiceCommand(
        VoiceCommand.startRevision,
        target: 'yesterday',
      );
    }
    if ({
      'revise',
      'start revision',
      'revision',
      'review recent lessons',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.startRevision);
    }
    if ({
      'start remediation',
      'start my remediation',
      'start remedial lesson',
      'practice the assigned lesson',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.startRemediation);
    }
    if ({
      'why this lesson',
      'why did you choose this lesson',
      'why was i redirected',
      'explain this recommendation',
      'explain the adaptive decision',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.explainAdaptiveSelection);
    }
    if (RegExp(r'\b(?:struggling|having trouble|need help)\b').hasMatch(text) ||
        {'targeted practice', 'practice my mistakes'}.contains(text)) {
      final target = RegExp(
        r'\b(letters|words|dots|matras|characters)\b',
      ).firstMatch(text)?.group(1);
      return ParsedVoiceCommand(
        VoiceCommand.startTargetedPractice,
        target: target,
      );
    }

    if ({'pause learning', 'pause lesson', 'pause'}.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.pauseLearning);
    }
    if ({
      'resume learning',
      'resume lesson',
      'continue learning',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.resumeLearning);
    }
    if ({'start learning', 'start lesson'}.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.startLearning);
    }
    final letter = RegExp(
      r'^(?:(?:i want to )?learn|teach me|teach|take me to|go to|open|start lesson on) (?:the )?(?:(english|hindi|kannada) )?(?:letter )?([a-z])(?: lesson)?$',
    ).firstMatch(text);
    if (letter != null) {
      return ParsedVoiceCommand(
        VoiceCommand.teachLetter,
        letter: letter.group(2)!.toUpperCase(),
        languageCode: letter.group(1),
      );
    }
    if ({
      'repeat that',
      'repeat',
      'say that again',
      'repeat the explanation',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.repeat);
    }
    if ({
      'explain the six dots',
      'explain six dots',
      'what are the six dots',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.explainDots);
    }
    if ({
      'start practice',
      'begin practice',
      'practice now',
      'अभ्यास',
      'ಅಭ್ಯಾಸ',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.startPractice);
    }
    final spokenOption = RegExp(
      r'^(?:the )?(?:option|choice) ([a-e]|[1-5])$',
    ).firstMatch(text);
    if (spokenOption != null) {
      return ParsedVoiceCommand(
        VoiceCommand.selectAnswer,
        target: spokenOption.group(1),
      );
    }
    final ordinalOption = RegExp(
      r'^(?:select |choose )?(?:the )?(first|second|third|fourth|fifth) (?:option|choice|one)$',
    ).firstMatch(text);
    if (ordinalOption != null) {
      return ParsedVoiceCommand(
        VoiceCommand.selectAnswer,
        target: ordinalOption.group(1),
      );
    }
    final selectedAnswer = RegExp(
      r'^(?:(?:answer|choose|select)(?: answer)?|(?:my|the) answer is|i choose)\s+(.+)$',
    ).firstMatch(text);
    if (selectedAnswer != null) {
      return ParsedVoiceCommand(
        VoiceCommand.selectAnswer,
        target: selectedAnswer.group(1)!.trim(),
      );
    }
    if ({
      'check my answer',
      'check answer',
      'submit answer',
      'submit',
      'submit my answer',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.checkAnswer);
    }
    if ({
      'repeat the word',
      'repeat word',
      'say the word again',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.repeatWord);
    }
    if ({
      'clear my pattern',
      'clear the dots',
      'clear pattern',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.clearPattern);
    }
    if ({
      'what is my progress',
      'tell me my progress',
      'my progress',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.showProgress);
    }
    final mastery = RegExp(
      r'^(?:what is|show|tell me) (?:my )?(?:mastery|skill mastery)(?: for (.+))?$',
    ).firstMatch(text);
    if (mastery != null) {
      return ParsedVoiceCommand(
        VoiceCommand.getSkillMastery,
        target: mastery.group(1)?.trim(),
      );
    }
    if ({
      'what should i learn next',
      'get recommendation',
      'recommend my next lesson',
      'what do you recommend',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.getRecommendation);
    }
    if ({
      'review difficult letters',
      'review my mistakes',
      'review mistakes',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.reviewDifficult);
    }
    if ({
      'settings',
      'open settings',
      'accessibility settings',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.openSettings);
    }
    if ({'start the test', 'start test', 'begin the test'}.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.startTest);
    }
    if ({
      'go to the next lesson',
      'next lesson',
      'next letter',
      'next',
      'next exercise',
      'next question',
      'start another lesson',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.nextLesson);
    }
    if ({
      'open progress',
      'show progress',
      'go to my progress',
      'open my progress',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.showProgress);
    }
    if ({
      'go to dashboard',
      'open dashboard',
      'back to dashboard',
      'return to dashboard',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.home);
    }
    if ({'go back', 'back', 'previous screen'}.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.goBack);
    }
    if ({
      'exit assessment',
      'leave assessment',
      'leave this test',
      'i want to exit the test',
      'cancel assessment',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.exitAssessment);
    }
    if ({'go home', 'home', 'open home'}.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.home);
    }
    if ({
      'open the tutor',
      'open tutor',
      'open talk to resonant',
    }.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.openTutor);
    }
    if ({'stop speaking', 'stop talking'}.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.stopSpeaking);
    }
    if ({'help', 'help me', 'what can i say'}.contains(text)) {
      return const ParsedVoiceCommand(VoiceCommand.help);
    }
    return null;
  }

  /// Normalizes a finite set of tested spoken phrases to canonical commands.
  /// This is deterministic phrase handling, not a multilingual ML model.
  static String _canonicalizePhrase(String text) {
    const aliases = <String, String>{
      // English paraphrases used for language and learning navigation.
      'let us do kannada now': 'switch to kannada',
      "let's do kannada now": 'switch to kannada',
      'i want kannada': 'switch to kannada',
      'i want hindi': 'switch to hindi',
      'i want english': 'switch to english',
      'change my language to kannada': 'switch to kannada',
      'change my language to hindi': 'switch to hindi',
      'change my language to english': 'switch to english',
      'take me to the next exercise': 'go to the next exercise',
      'skip to the next exercise': 'go to the next exercise',
      'move to the next exercise': 'go to the next exercise',
      'move to the previous exercise': 'go to the previous exercise',
      'mark my answer': 'check my answer',
      'is my answer correct': 'check my answer',
      'check it': 'check my answer',
      'hint please': 'give me a hint',
      'give me a clue': 'give me a hint',
      'repeat options': 'read the options',
      'read the options again': 'read the options',
      'read all options': 'read all the options',
      'go to the dashboard': 'open dashboard',
      'back to dashboard': 'open dashboard',
      'return to dashboard': 'open dashboard',
      'open the lesson menu': 'open lesson menu',
      // Romanized Hindi and Kannada phrases tested for common command intents.
      'kannada mein le chalo': 'switch to kannada',
      'hindi mein le chalo': 'switch to hindi',
      'english mein le chalo': 'switch to english',
      'kannada mein padhana hai': 'switch to kannada',
      'agla exercise': 'go to the next exercise',
      'agla sawaal': 'go to the next question',
      'mera answer check karo': 'check my answer',
      'hint do': 'give me a hint',
      'sawal dobara sunao': 'repeat the question',
      'kannada ge change maadi': 'switch to kannada',
      'english ge hogu': 'switch to english',
      'hindi ge change maadi': 'switch to hindi',
      'mundina exercise': 'go to the next exercise',
      'mundina prashne': 'go to the next question',
      'nanna answer check maadi': 'check my answer',
      'hint kodi': 'give me a hint',
      // Native-script examples requested for Hindi and Kannada.
      'मुझे कन्नड़ में ले चलो': 'switch to kannada',
      'भाषा बदलकर कन्नड़ करो': 'switch to kannada',
      'मुझे अंग्रेज़ी में ले चलो': 'switch to english',
      'मुझे हिंदी में पढ़ना है': 'switch to hindi',
      'अगला अभ्यास खोलो': 'go to the next exercise',
      'अगला सवाल': 'go to the next question',
      'मेरा उत्तर जाँचो': 'check my answer',
      'मुझे संकेत दो': 'give me a hint',
      'सवाल दोबारा सुनाओ': 'repeat the question',
      'ನನ್ನನ್ನು ಕನ್ನಡಕ್ಕೆ ಬದಲಾಯಿಸು': 'switch to kannada',
      'ಇಂಗ್ಲಿಷ್‌ಗೆ ಬದಲಾಯಿಸು': 'switch to english',
      'ಹಿಂದಿಗೆ ಬದಲಾಯಿಸು': 'switch to hindi',
      'ಮುಂದಿನ ಅಭ್ಯಾಸಕ್ಕೆ ಹೋಗು': 'go to the next exercise',
      'ಮುಂದಿನ ಪ್ರಶ್ನೆ': 'go to the next question',
      'ನನ್ನ ಉತ್ತರ ಪರಿಶೀಲಿಸು': 'check my answer',
      'ಸುಳಿವು ಕೊಡು': 'give me a hint',
      'ಪ್ರಶ್ನೆಯನ್ನು ಮತ್ತೆ ಹೇಳು': 'repeat the question',
    };
    return aliases[text] ?? text;
  }
}
