import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import 'voice_command_parser.dart';

class TutorIntentInterpretation {
  const TutorIntentInterpretation({
    this.command,
    this.confidence = 0,
    this.clarification,
    this.reasoningSummary = '',
    this.isTutorQuestion = false,
  });

  final ParsedVoiceCommand? command;
  final double confidence;
  final String? clarification;
  final String reasoningSummary;
  final bool isTutorQuestion;
}

/// Calls the backend's schema-validated Ollama interpreter. It returns a
/// candidate command only; the app's action controller and active screen still
/// validate destinations, answer options, prerequisites, and execution.
class HttpTutorIntentInterpreter {
  HttpTutorIntentInterpreter({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _baseUriOverride = baseUri;

  final http.Client _client;
  final Uri? _baseUriOverride;
  Uri get _baseUri => _baseUriOverride ?? ApiConfiguration.baseUri;

  Future<TutorIntentInterpretation> interpret({
    required String utterance,
    required String language,
    required Map<String, Object?> screenContext,
    required List<Map<String, String>> recentTurns,
    required List<String> availableActions,
  }) async {
    final response = await _client
        .post(
          _baseUri.resolve('/interpret'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'utterance': utterance,
            'language': language,
            'screen_context': screenContext,
            'history': recentTurns,
            'available_actions': availableActions,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TutorIntentException(
        'Intent service returned ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Intent response must be a JSON object.');
    }
    final confidenceValue = decoded['confidence'];
    if (confidenceValue is! num || confidenceValue < 0 || confidenceValue > 1) {
      throw const FormatException('Intent confidence is invalid.');
    }
    final confidence = confidenceValue.toDouble();
    final intent = decoded['intent'];
    final clarification = decoded['clarification'];
    final reasoning = decoded['reasoning_summary'];
    if (intent == 'clarify' || confidence < 0.62) {
      return TutorIntentInterpretation(
        confidence: confidence,
        clarification: clarification is String && clarification.isNotEmpty
            ? clarification
            : 'Please tell me which lesson or activity you want.',
        reasoningSummary: reasoning is String ? reasoning : '',
      );
    }
    if (intent == 'ask_tutor') {
      return TutorIntentInterpretation(
        confidence: confidence,
        reasoningSummary: reasoning is String ? reasoning : '',
        isTutorQuestion: true,
      );
    }
    if (intent is! String || !availableActions.contains(intent)) {
      return TutorIntentInterpretation(
        confidence: confidence,
        clarification: switch (language) {
          'Hindi' =>
            'यह कार्य अभी उपलब्ध नहीं है। आप कौन-सा दूसरा काम करना चाहेंगे?',
          'Kannada' =>
            'ಈ ಕ್ರಿಯೆ ಈಗ ಲಭ್ಯವಿಲ್ಲ. ನೀವು ಯಾವ ಬೇರೆ ಕೆಲಸ ಮಾಡಲು ಬಯಸುತ್ತೀರಿ?',
          _ =>
            'That action is not available here. What would you like to do instead?',
        },
        reasoningSummary: reasoning is String ? reasoning : '',
      );
    }

    final target = decoded['target'];
    final languageTarget = decoded['language_target'];
    final letter = decoded['letter'];
    final optionIndex = decoded['option_index'];
    String? textTarget = target is String ? target.trim() : null;
    if (optionIndex != null) {
      if (optionIndex is! int || optionIndex < 1 || optionIndex > 5) {
        throw const FormatException('Intent option index is invalid.');
      }
      textTarget = 'option $optionIndex';
    }
    final String? languageCode = switch (languageTarget) {
      'English' => 'english',
      'Hindi' => 'hindi',
      'Kannada' => 'kannada',
      null => null,
      _ => throw const FormatException('Intent language is unsupported.'),
    };
    final parsed = switch (intent) {
      'switch_language' when languageCode != null => ParsedVoiceCommand(
        VoiceCommand.switchLanguage,
        languageCode: languageCode,
      ),
      'teach_letter' when letter is String && letter.trim().isNotEmpty =>
        ParsedVoiceCommand(
          VoiceCommand.teachLetter,
          letter: letter.trim().toUpperCase(),
          languageCode: languageCode,
        ),
      'go_to_lesson' => ParsedVoiceCommand(
        VoiceCommand.goToLesson,
        target: textTarget,
        languageCode: languageCode,
      ),
      'go_to_chapter' => ParsedVoiceCommand(
        VoiceCommand.goToChapter,
        target: textTarget,
        languageCode: languageCode,
      ),
      'open_word_lessons' => const ParsedVoiceCommand(
        VoiceCommand.goToChapter,
        target: 'words',
      ),
      'next_exercise' => const ParsedVoiceCommand(VoiceCommand.nextLesson),
      'previous_exercise' => const ParsedVoiceCommand(
        VoiceCommand.previousExercise,
      ),
      'start_practice' => const ParsedVoiceCommand(VoiceCommand.startPractice),
      'start_assessment' => const ParsedVoiceCommand(
        VoiceCommand.startAssessment,
      ),
      'start_word_test' => const ParsedVoiceCommand(VoiceCommand.startWordTest),
      'start_skill_test' => ParsedVoiceCommand(
        VoiceCommand.startSkillTest,
        target: textTarget,
      ),
      'select_answer' => ParsedVoiceCommand(
        VoiceCommand.selectAnswer,
        target: textTarget,
      ),
      'check_answer' => const ParsedVoiceCommand(VoiceCommand.checkAnswer),
      'repeat_question' => const ParsedVoiceCommand(
        VoiceCommand.repeatQuestion,
      ),
      'read_options' => const ParsedVoiceCommand(VoiceCommand.readOptions),
      'give_hint' => const ParsedVoiceCommand(VoiceCommand.giveHint),
      'exit_assessment' => const ParsedVoiceCommand(
        VoiceCommand.exitAssessment,
      ),
      'show_progress' => const ParsedVoiceCommand(VoiceCommand.showProgress),
      'open_settings' => const ParsedVoiceCommand(VoiceCommand.openSettings),
      'go_home' => const ParsedVoiceCommand(VoiceCommand.home),
      'go_back' => const ParsedVoiceCommand(VoiceCommand.goBack),
      'open_lesson_menu' => const ParsedVoiceCommand(
        VoiceCommand.openLessonMenu,
      ),
      'read_screen' => const ParsedVoiceCommand(VoiceCommand.readScreen),
      'read_question' => const ParsedVoiceCommand(VoiceCommand.readQuestion),
      'read_instructions' => const ParsedVoiceCommand(
        VoiceCommand.readInstructions,
      ),
      'read_feedback' => const ParsedVoiceCommand(VoiceCommand.readFeedback),
      'what_exercise' => const ParsedVoiceCommand(VoiceCommand.whatExercise),
      'explain_current_content' => const ParsedVoiceCommand(
        VoiceCommand.explainCurrentContent,
      ),
      'explain_option' => ParsedVoiceCommand(
        VoiceCommand.explainOption,
        target: textTarget,
      ),
      'repeat' => const ParsedVoiceCommand(VoiceCommand.repeat),
      'repeat_lesson' => const ParsedVoiceCommand(VoiceCommand.repeatLesson),
      'start_learning' => const ParsedVoiceCommand(VoiceCommand.startLearning),
      'resume_learning' => const ParsedVoiceCommand(
        VoiceCommand.resumeLearning,
      ),
      'pause_learning' => const ParsedVoiceCommand(VoiceCommand.pauseLearning),
      'start_revision' => ParsedVoiceCommand(
        VoiceCommand.startRevision,
        target: textTarget,
      ),
      'get_recommendation' => const ParsedVoiceCommand(
        VoiceCommand.getRecommendation,
      ),
      'get_skill_mastery' => ParsedVoiceCommand(
        VoiceCommand.getSkillMastery,
        target: textTarget,
      ),
      'review_difficult' => const ParsedVoiceCommand(
        VoiceCommand.reviewDifficult,
      ),
      'start_targeted_practice' => const ParsedVoiceCommand(
        VoiceCommand.startTargetedPractice,
      ),
      'change_difficulty' => ParsedVoiceCommand(
        VoiceCommand.changeDifficulty,
        difficulty: textTarget,
      ),
      'help' => const ParsedVoiceCommand(VoiceCommand.help),
      _ => null,
    };
    if (parsed == null) {
      throw const FormatException(
        'Intent does not contain a valid action target.',
      );
    }
    return TutorIntentInterpretation(
      command: parsed,
      confidence: confidence,
      reasoningSummary: reasoning is String ? reasoning : '',
    );
  }
}

class TutorIntentException implements Exception {
  const TutorIntentException(this.message);
  final String message;
  @override
  String toString() => message;
}
