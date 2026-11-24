import 'tutor_option_resolver.dart';
import 'voice_command_parser.dart';

/// Resolves unambiguous assessment controls locally before optional LLM
/// interpretation. The assessment controller remains responsible for checking
/// that the action is valid and for evaluating/persisting an answer.
class AssessmentVoiceCommandResolver {
  const AssessmentVoiceCommandResolver._();

  static ParsedVoiceCommand? resolve({
    required String utterance,
    required bool assessmentActive,
    required List<String> options,
  }) {
    if (!assessmentActive || utterance.trim().isEmpty) return null;

    final parsed = VoiceCommandParser.parse(utterance);
    if (parsed != null && _assessmentControls.contains(parsed.command)) {
      return parsed;
    }

    // Some recognizers return a bare spoken choice (for example, "A" or
    // "one"). Resolve it only against the currently visible options.
    final optionIndex = TutorOptionResolver.resolveIndex(options, utterance);
    if (optionIndex == null) return null;
    return ParsedVoiceCommand(
      VoiceCommand.selectAnswer,
      target: options[optionIndex],
    );
  }

  static const Set<VoiceCommand> _assessmentControls = {
    VoiceCommand.selectAnswer,
    VoiceCommand.checkAnswer,
    VoiceCommand.nextLesson,
    VoiceCommand.previousExercise,
    VoiceCommand.exitAssessment,
    VoiceCommand.repeatQuestion,
    VoiceCommand.repeat,
    VoiceCommand.readQuestion,
    VoiceCommand.readOptions,
    VoiceCommand.giveHint,
  };
}
