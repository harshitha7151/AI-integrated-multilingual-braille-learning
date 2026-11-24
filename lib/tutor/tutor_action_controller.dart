import '../learning/chapter_navigation_controller.dart';
import 'voice_command_parser.dart';

enum TutorActionStatus { ready, blocked, needsClarification }

class TutorActionContext {
  final LearningNavigationContext navigation;
  final bool learningPaused;
  final bool assessmentActive;
  final bool wordTestAvailable;
  final bool moduleTestAvailable;
  final bool hasRevisionHistory;
  final bool hasTargetedPractice;
  final bool hasAdaptiveDecision;
  final bool adaptiveRemediationRequired;
  final bool composedResponseTestAvailable;
  final bool sentenceResponseTestAvailable;

  const TutorActionContext({
    required this.navigation,
    required this.learningPaused,
    required this.assessmentActive,
    required this.wordTestAvailable,
    required this.moduleTestAvailable,
    required this.hasRevisionHistory,
    required this.hasTargetedPractice,
    this.hasAdaptiveDecision = false,
    this.adaptiveRemediationRequired = false,
    this.composedResponseTestAvailable = false,
    this.sentenceResponseTestAvailable = false,
  });

  TutorActionContext withNavigation(LearningNavigationContext value) =>
      TutorActionContext(
        navigation: value,
        learningPaused: learningPaused,
        assessmentActive: assessmentActive,
        wordTestAvailable: wordTestAvailable,
        moduleTestAvailable: moduleTestAvailable,
        hasRevisionHistory: hasRevisionHistory,
        hasTargetedPractice: hasTargetedPractice,
        hasAdaptiveDecision: hasAdaptiveDecision,
        adaptiveRemediationRequired: adaptiveRemediationRequired,
        composedResponseTestAvailable: composedResponseTestAvailable,
        sentenceResponseTestAvailable: sentenceResponseTestAvailable,
      );
}

class TutorActionResolution {
  final TutorActionStatus status;
  final VoiceCommand command;
  final String message;
  final NavigationResolution? navigation;
  final String? target;
  final String? languageCode;
  final String? difficulty;

  const TutorActionResolution({
    required this.status,
    required this.command,
    required this.message,
    this.navigation,
    this.target,
    this.languageCode,
    this.difficulty,
  });

  bool get isReady => status == TutorActionStatus.ready;
}

/// Validates parsed tutor commands against current application and curriculum
/// state. It returns a decision only; the caller performs the real action.
class TutorActionController {
  final ChapterNavigationController navigationController;

  const TutorActionController({
    this.navigationController = const ChapterNavigationController(),
  });

  TutorActionResolution resolve(
    ParsedVoiceCommand parsed,
    TutorActionContext context,
  ) {
    if (context.learningPaused &&
        parsed.command != VoiceCommand.resumeLearning &&
        parsed.command != VoiceCommand.help &&
        parsed.command != VoiceCommand.stopSpeaking &&
        !const {
          VoiceCommand.goToChapter,
          VoiceCommand.goToLesson,
          VoiceCommand.moduleBeginning,
          VoiceCommand.switchLanguage,
          VoiceCommand.exitAssessment,
          VoiceCommand.home,
          VoiceCommand.goBack,
          VoiceCommand.openSettings,
          VoiceCommand.openLessonMenu,
          VoiceCommand.showProgress,
        }.contains(parsed.command)) {
      return _result(
        parsed,
        TutorActionStatus.blocked,
        'Learning is paused. Say resume learning when you are ready.',
      );
    }

    switch (parsed.command) {
      case VoiceCommand.nextChapter:
        return _navigation(
          parsed,
          navigationController.nextChapter(context.navigation),
        );
      case VoiceCommand.previousChapter:
        return _navigation(
          parsed,
          navigationController.previousChapter(context.navigation),
        );
      case VoiceCommand.goToChapter:
        return _navigation(
          parsed,
          navigationController.goToChapter(context.navigation, parsed.target),
          target: parsed.target,
        );
      case VoiceCommand.goToLesson:
        return _navigation(
          parsed,
          navigationController.goToLesson(context.navigation, parsed.target),
          target: parsed.target,
        );
      case VoiceCommand.moduleBeginning:
        return _navigation(
          parsed,
          navigationController.beginningOfModule(context.navigation),
        );
      case VoiceCommand.startWordTest:
        return _availability(
          parsed,
          context.wordTestAvailable,
          ready: 'A validated word assessment is available.',
          blocked:
              'The word assessment unlocks after the required learning lessons are complete. You can still open Word lessons to practise without losing this assessment.',
        );
      case VoiceCommand.startModuleTest:
        return _availability(
          parsed,
          context.moduleTestAvailable,
          ready: 'A validated module assessment is available.',
          blocked:
              'A module assessment is not eligible yet. Complete the required lessons first.',
        );
      case VoiceCommand.startSkillTest:
        final target = parsed.target?.toLowerCase().trim();
        if (target == null || target.isEmpty) {
          return _result(
            parsed,
            TutorActionStatus.needsClarification,
            'Which skill should I test: letters or words?',
          );
        }
        if (target.contains('word')) {
          return _availability(
            parsed,
            context.wordTestAvailable,
            ready: 'A validated word assessment is available.',
            blocked:
                'The word assessment unlocks after the required learning lessons are complete. You can still open Word lessons to practise without losing this assessment.',
          );
        }
        if (target.contains('letter') ||
            target.contains('character') ||
            target.contains('dot')) {
          return _result(
            parsed,
            TutorActionStatus.ready,
            'Starting a validated assessment for the current skill.',
            target: target,
          );
        }
        if (target.contains('sentence') || target.contains('phrase')) {
          final available = target.contains('sentence')
              ? context.sentenceResponseTestAvailable
              : context.composedResponseTestAvailable;
          return _availability(
            parsed,
            available,
            ready:
                'A validated six-dot phrase or sentence assessment is available.',
            blocked:
                'Complete word mastery and the required phrase work before this assessment.',
          );
        }
        return _result(
          parsed,
          TutorActionStatus.blocked,
          'There is no validated $target assessment in the current curriculum yet.',
          target: target,
        );
      case VoiceCommand.startRevision:
        return _availability(
          parsed,
          context.hasRevisionHistory,
          ready: 'Revision history is available.',
          blocked: parsed.target == 'yesterday'
              ? 'No completed lesson from yesterday is available on this device.'
              : 'Complete at least one lesson before starting revision.',
        );
      case VoiceCommand.startTargetedPractice:
      case VoiceCommand.reviewDifficult:
        return _availability(
          parsed,
          context.hasTargetedPractice || context.adaptiveRemediationRequired,
          ready: 'A repeated-error skill is available for targeted practice.',
          blocked: 'No repeated-error skill is available yet.',
        );
      case VoiceCommand.startRemediation:
        return _availability(
          parsed,
          context.adaptiveRemediationRequired,
          ready: 'The assigned remediation is available.',
          blocked: 'There is no required remediation waiting right now.',
        );
      case VoiceCommand.explainAdaptiveSelection:
        return _availability(
          parsed,
          context.hasAdaptiveDecision,
          ready: 'The latest adaptive decision is available to explain.',
          blocked: 'There is no recorded adaptive decision to explain yet.',
        );
      case VoiceCommand.changeDifficulty:
        return _result(
          parsed,
          TutorActionStatus.blocked,
          'The current validated assessment does not have another difficulty tier yet.',
          difficulty: parsed.difficulty,
        );
      case VoiceCommand.switchLanguage:
        if (!const {
          'english',
          'hindi',
          'kannada',
        }.contains(parsed.languageCode)) {
          return _result(
            parsed,
            TutorActionStatus.needsClarification,
            'Which language should I use: English, Hindi, or Kannada?',
          );
        }
        return _result(
          parsed,
          TutorActionStatus.ready,
          'Language change validated.',
          languageCode: parsed.languageCode,
        );
      case VoiceCommand.openLessonMenu:
        return _result(
          parsed,
          TutorActionStatus.ready,
          'The lesson list is available.',
        );
      default:
        return _result(
          parsed,
          TutorActionStatus.ready,
          'Action validated.',
          target: parsed.target,
          languageCode: parsed.languageCode,
          difficulty: parsed.difficulty,
        );
    }
  }

  TutorActionResolution _navigation(
    ParsedVoiceCommand command,
    NavigationResolution destination, {
    String? target,
  }) => TutorActionResolution(
    status: destination.isResolved
        ? TutorActionStatus.ready
        : destination.status == NavigationResolutionStatus.needsClarification
        ? TutorActionStatus.needsClarification
        : TutorActionStatus.blocked,
    command: command.command,
    message: destination.message,
    navigation: destination,
    target: target,
  );

  TutorActionResolution _availability(
    ParsedVoiceCommand command,
    bool available, {
    required String ready,
    required String blocked,
  }) => _result(
    command,
    available ? TutorActionStatus.ready : TutorActionStatus.blocked,
    available ? ready : blocked,
    target: command.target,
  );

  TutorActionResolution _result(
    ParsedVoiceCommand command,
    TutorActionStatus status,
    String message, {
    NavigationResolution? navigation,
    String? target,
    String? languageCode,
    String? difficulty,
  }) => TutorActionResolution(
    status: status,
    command: command.command,
    message: message,
    navigation: navigation,
    target: target,
    languageCode: languageCode,
    difficulty: difficulty,
  );
}
