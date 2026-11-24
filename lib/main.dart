import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';
import 'package:resonant_braille/learning/chapter_navigation_controller.dart';
import 'package:resonant_braille/learning/adaptive_decision_controller.dart';
import 'package:resonant_braille/learning/adaptive_recommendation_status.dart';
import 'package:resonant_braille/learning/adaptive_word_recommender.dart';
import 'package:resonant_braille/learning/word_assessment_validator.dart';
import 'package:resonant_braille/learning/paused_word_assessment.dart';
import 'package:resonant_braille/learning/lesson_progress_store.dart';
import 'package:resonant_braille/learning/onboarding_store.dart';
import 'package:resonant_braille/learning/welcome_onboarding.dart';
import 'package:resonant_braille/core/braille/english_grade1_engine.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/tutor/speech_to_text_recognizer.dart';
import 'package:resonant_braille/tutor/voice_tutor_panel.dart';
import 'package:resonant_braille/tutor/voice_tutor_controller.dart';
import 'package:resonant_braille/tutor/voice_command_parser.dart';
import 'package:resonant_braille/tutor/assessment_voice_command_resolver.dart';
import 'package:resonant_braille/tutor/tutor_action_controller.dart';
import 'package:resonant_braille/tutor/http_tutor_intent_interpreter.dart';
import 'package:resonant_braille/tutor/tutor_screen_context.dart';
import 'package:resonant_braille/tutor/tutor_option_resolver.dart';
import 'package:resonant_braille/tutor/live_demo_client.dart';
import 'package:resonant_braille/tutor/live_demo_connect_page.dart';
import 'package:resonant_braille/tutor/voice_assessment_settings.dart';
import 'package:resonant_braille/accessibility/accessible_action_surface.dart';
import 'package:resonant_braille/accessibility/two_finger_navigation_detector.dart';
import 'package:resonant_braille/learning/role_selection_page.dart';
import 'package:resonant_braille/learning/learner_registration_page.dart';
import 'package:resonant_braille/learning/learner_account_store.dart';
import 'package:resonant_braille/learning/learner_api.dart';
import 'package:resonant_braille/teacher/teacher_gate.dart';

typedef IntSet = Set<int>;
typedef StringSet = Set<String>;
typedef BoolMap = Map<String, bool>;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  runApp(const ResonantApp());
}

class ResonantApp extends StatelessWidget {
  const ResonantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resonant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2468D9),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF202124),
      ),
      home: const _RoleGateRoot(),
    );
  }
}

class _RoleGateRoot extends StatefulWidget {
  const _RoleGateRoot();

  @override
  State<_RoleGateRoot> createState() => _RoleGateRootState();
}

class _RoleGateRootState extends State<_RoleGateRoot> {
  final FlutterTts _tts = FlutterTts();
  final LiveDemoClient _liveDemoClient = LiveDemoClient();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _tts.setVolume(1.0);
  }

  @override
  void dispose() {
    _tts.stop();
    unawaited(_liveDemoClient.disconnect());
    super.dispose();
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      onSpeak: _speak,
      onStop: _stop,
      learnerHome: const _LearnerGate(),
      learnerHomeBuilder: (onSwitchRole) =>
          _LearnerGate(demoClient: _liveDemoClient, onSwitchRole: onSwitchRole),
      teacherHome: (onSwitchRole) => TeacherGate(onSwitchRole: onSwitchRole),
      onConnectToAimlLab: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LiveDemoConnectPage(client: _liveDemoClient),
          ),
        );
      },
    );
  }
}

/// Thin stateful bridge: shows [LearnerRegistrationGate] until an account is
/// confirmed, then shows [ResonantHome].  Keeps the learner path decoupled
/// from [RoleGate] so [RoleGate] needs no knowledge of registration.
class _LearnerGate extends StatefulWidget {
  final LiveDemoClient? demoClient;
  final VoidCallback? onSwitchRole;

  const _LearnerGate({this.demoClient, this.onSwitchRole});

  @override
  State<_LearnerGate> createState() => _LearnerGateState();
}

class _LearnerGateState extends State<_LearnerGate> {
  bool _ready = false;
  LearnerAccount? _account;

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return ResonantHome(
        learnerAccount: _account,
        enablePhysicalTutorKeys: !kIsWeb,
        demoClient: widget.demoClient,
        onSwitchRole: widget.onSwitchRole,
      );
    }
    return LearnerRegistrationGate(
      onAccountReady: (account) {
        if (mounted) {
          setState(() {
            _account = account;
            _ready = true;
          });
        }
      },
    );
  }
}

class ResonantHome extends StatefulWidget {
  final OnboardingProgress? onboardingProgress;
  final LessonProgressStore? lessonProgressStore;
  final LearnerAccount? learnerAccount;
  final LearnerAccountStorage? accountStorage;
  final LearnerApi? learnerApi;
  final bool enablePhysicalTutorKeys;
  final LiveDemoClient? demoClient;
  final VoidCallback? onSwitchRole;

  const ResonantHome({
    super.key,
    this.onboardingProgress,
    this.lessonProgressStore,
    this.learnerAccount,
    this.accountStorage,
    this.learnerApi,
    this.enablePhysicalTutorKeys = false,
    this.demoClient,
    this.onSwitchRole,
  });

  @override
  State<ResonantHome> createState() => _ResonantHomeState();
}

class _ResonantHomeState extends State<ResonantHome> {
  static const EventChannel _physicalTutorEvents = EventChannel(
    'resonant/physical_tutor',
  );
  static const MethodChannel _physicalTutorControl = MethodChannel(
    'resonant/physical_tutor_control',
  );
  StreamSubscription<dynamic>? _physicalTutorSubscription;
  VoiceTutorController? _activeTutorController;
  bool _physicalTutorMode = false;
  final FlutterTts tts = FlutterTts();
  late final LiveDemoClient liveDemoClient;
  final SpeechToTextRecognizer voiceSpeech = SpeechToTextRecognizer();
  final TutorActionController tutorActionController =
      const TutorActionController();
  final HttpTutorIntentInterpreter tutorIntentInterpreter =
      HttpTutorIntentInterpreter();
  final AdaptiveDecisionController adaptiveDecisionController =
      const AdaptiveDecisionController();
  final AdaptiveWordRecommender adaptiveWordRecommender =
      const AdaptiveWordRecommender();

  int page = 0;
  int chapter = 0;
  int lessonItem = 0;
  String? selectedLessonAnswer;
  String? _lastTutorSubmittedExerciseId;
  String? _lastTutorSubmittedAnswer;
  String? lessonFeedback;
  bool lessonAnswerCorrect = false;
  final Set<String> completedLessonQuestions = {};
  final Set<String> hintedLessonQuestions = {};
  final Map<String, int> lessonAttempts = {};
  final Map<String, int> lessonAssessmentAttempts = {};
  LessonProgressStore? progressStore;
  late final Future<void> progressReady;
  DateTime exerciseStartedAt = DateTime.now();
  OnboardingProgress? onboardingStore;
  bool onboardingLoading = true;
  bool onboardingComplete = false;
  int onboardingStep = 0;
  int _vernacularIntroStep = 0;
  bool replayingOnboarding = false;
  bool lessonTaught = false;
  bool guidedPractice = false;
  bool lessonAssessment = false;
  bool wordAssessment = false;
  bool cumulativeAssessment = false;
  VoiceAssessmentSettings voiceAssessmentSettings =
      const VoiceAssessmentSettings();
  VoiceAssessmentSettingsStore? _voiceAssessmentSettingsStore;
  bool _assessmentVoicePrepared = false;
  bool _assessmentVoicePreparationPending = false;
  String? _lastAssessmentVoiceKey;
  String? _lastDemoAssessmentKey;
  bool courseComplete = false;
  String assessmentWord = 'BAD';
  final Set<String> completedWordStages = {};
  final Map<String, IntSet> completedStageWords = {};
  int assessmentWordIndex = 0;
  final List<int> assessmentCells = [];
  int wordAssessmentAttempts = 0;
  final Map<String, Set<int>> _wordRemediationVisited = {};
  PausedWordAssessment? _pausedWordAssessment;
  int wordChapterLessonIndex = 0;
  bool wordChapterComplete = false;
  final Map<int, StringSet> wordChapterCompletedWords = {};
  List<JsonMap> _learningHistory = const [];
  String lastSpokenInstruction = '';
  String lastPatternFeedback = '';
  final GlobalKey<_BrailleKeyboardState> brailleKeyboardKey =
      GlobalKey<_BrailleKeyboardState>();
  final GlobalKey<_WordChapterScreenState> wordChapterScreenKey =
      GlobalKey<_WordChapterScreenState>();
  bool twoFingerNavigationEnabled = false;
  int? _courseSwipePointer;
  Offset? _courseSwipeStart;

  bool audioEnabled = true;
  bool hapticsEnabled = true;
  bool learningPaused = false;
  AppLanguage selectedLanguage = AppLanguage.english;
  LearnerAccount? activeAccount;
  AdaptiveDecision? _activeAdaptiveDecision;
  AdaptiveDecision? _latestAdaptiveDecision;
  bool _applyingAdaptiveDecision = false;
  String? _processingLessonAssessmentId;
  Future<void> _adaptiveDecisionApplications = Future<void>.value();

  final List<String> pages = [
    'Learning',
    'Braille Keyboard',
    'Lessons',
    'Settings',
    'My Progress',
    'Help',
  ];

  List<LessonChapter> get activeChapters =>
      LessonCatalog.chaptersFor(selectedLanguage);

  LessonChapter get currentChapter =>
      activeChapters[chapter.clamp(0, activeChapters.length - 1)];

  LessonExercise get currentExercise => currentChapter.exercises[lessonItem];

  String get currentExerciseAnswer => currentExercise.resolvedAnswer(
    selectedLanguage,
    learnerName: activeAccount?.name,
  );

  List<int> get currentExerciseCells => BrailleDispatcher.encodeToBitmasks(
    currentExerciseAnswer,
    selectedLanguage,
  );

  CurriculumStage get currentCurriculumStage =>
      LessonCatalog.stageForIndex(lessonItem);

  String get assessmentStageId => selectedLanguage == AppLanguage.english
      ? (cumulativeAssessment ? 'cumulative' : currentCurriculumStage.id)
      : '${selectedLanguage.code}-word-test';

  List<String> get currentAssessmentWords =>
      selectedLanguage == AppLanguage.english
      ? cumulativeAssessment
            ? LessonCatalog.cumulativeWords
            : currentCurriculumStage.words
      : activeChapters[2].exercises.map((exercise) => exercise.answer).toList();

  bool get _wordProgressionComplete => selectedLanguage == AppLanguage.english
      ? wordChapterComplete
      : completedWordStages.contains('${selectedLanguage.code}-word-test');

  bool get _phraseProgressionComplete =>
      activeChapters.length > 3 &&
      activeChapters[3].exercises.every(
        (exercise) => completedLessonQuestions.contains(exercise.id),
      );

  bool get _composedResponseTestAvailable => _wordProgressionComplete;

  LearningNavigationContext get navigationContext => LearningNavigationContext(
    language: selectedLanguage,
    chapterIndex: chapter,
    lessonIndex: lessonItem,
    wordChapterIndex: wordChapterLessonIndex,
    englishLetterCourseComplete: courseComplete,
    englishWordCourseComplete: wordChapterComplete,
    completedWordChapterWords: {
      for (final entry in wordChapterCompletedWords.entries)
        entry.key: Set<String>.from(entry.value),
    },
    completedWordAssessmentStageIds: Set<String>.from(completedWordStages),
    completedLessonExerciseIds: Set<String>.from(completedLessonQuestions),
  );

  bool get wordMasteryAssessmentAvailable {
    if (selectedLanguage != AppLanguage.english) return false;
    for (var index = 0; index < 4; index++) {
      final completed = wordChapterCompletedWords[index] ?? const <String>{};
      if (!LessonCatalog.wordLessons[index].words.every(completed.contains)) {
        return false;
      }
    }
    return true;
  }

  CurriculumStage? get latestEligibleEnglishStage {
    if (selectedLanguage != AppLanguage.english) return null;
    final letterExercises = LessonCatalog.english[1].exercises;
    for (final stage in LessonCatalog.curriculum.reversed) {
      final complete =
          List<int>.generate(
            stage.last - stage.first + 1,
            (offset) => stage.first + offset,
          ).every(
            (index) =>
                completedLessonQuestions.contains(letterExercises[index].id),
          );
      if (complete) return stage;
    }
    return null;
  }

  bool get vernacularWordAssessmentAvailable {
    if (selectedLanguage == AppLanguage.english) return false;
    return activeChapters[1].exercises.every(
      (exercise) => completedLessonQuestions.contains(exercise.id),
    );
  }

  bool get validatedWordTestAvailable {
    if (wordAssessment || wordMasteryAssessmentAvailable) return true;
    if (selectedLanguage == AppLanguage.english) {
      final stage = latestEligibleEnglishStage;
      return stage != null && !completedWordStages.contains(stage.id);
    }
    return vernacularWordAssessmentAvailable &&
        !completedWordStages.contains('${selectedLanguage.code}-word-test');
  }

  TutorActionContext get tutorActionContext => TutorActionContext(
    navigation: navigationContext,
    learningPaused: learningPaused,
    assessmentActive: lessonAssessment || wordAssessment,
    wordTestAvailable: validatedWordTestAvailable,
    moduleTestAvailable: validatedWordTestAvailable,
    hasRevisionHistory:
        completedLessonQuestions.isNotEmpty || completedWordStages.isNotEmpty,
    hasTargetedPractice: lessonAttempts.values.any((attempts) => attempts > 1),
    hasAdaptiveDecision: _latestAdaptiveDecision != null,
    adaptiveRemediationRequired: _adaptiveRequirementActive,
    composedResponseTestAvailable: _composedResponseTestAvailable,
    sentenceResponseTestAvailable: _phraseProgressionComplete,
  );

  TutorScreenContext get tutorScreenContext {
    final screenName = page >= 0 && page < pages.length
        ? (page == 0 ? 'Dashboard' : pages[page])
        : 'Learning';
    final wordChapter =
        page == 2 && selectedLanguage == AppLanguage.english && chapter == 2;
    final wordScreen = wordChapterScreenKey.currentState;
    final wordQuestionActive =
        wordChapter &&
        (wordScreen?.lessonIndex == 1 || wordScreen?.lessonIndex == 3);
    final isLessonScreen = page == 2 && !wordChapter;
    final options = isLessonScreen && lessonAssessment
        ? _lessonQuestionOptions
        : wordQuestionActive
        ? wordScreen!.words
        : const <String>[];
    final exerciseCount = isLessonScreen
        ? currentChapter.exercises.length
        : wordChapter
        ? wordScreen?.words.length
        : null;
    final exerciseNumber = isLessonScreen
        ? lessonItem + 1
        : wordChapter && wordScreen != null
        ? wordScreen.wordIndex + 1
        : null;
    final lesson = wordChapter
        ? wordScreen?.lesson.title
        : isLessonScreen
        ? currentExercise.answer.isEmpty
              ? currentChapter.title
              : 'Letter or character ${currentExercise.answer}'
        : null;
    final activeQuestion = isLessonScreen && lessonAssessment
        ? _lessonQuestionPrompt
        : wordQuestionActive
        ? wordScreen?._repeatPrompt()
        : null;
    final activeInstruction = page == 1
        ? (wordAssessment
              ? 'Write $assessmentWord using the Braille keyboard.'
              : currentExercise.prompt)
        : isLessonScreen && !lessonAssessment
        ? currentExercise.prompt
        : wordChapter && !wordQuestionActive
        ? wordScreen?._repeatPrompt()
        : null;
    final currentFeedback =
        lessonFeedback ?? (wordChapter ? wordScreen?.feedbackText : null);
    final keyboard = page == 1 ? brailleKeyboardKey.currentState : null;
    final activeAssessment =
        lessonAssessment || wordAssessment || cumulativeAssessment;
    final intentActions = <String>{
      'ask_tutor',
      'help',
      'switch_language',
      'go_home',
      'go_back',
      'show_progress',
      'open_settings',
      'read_screen',
      'open_lesson_menu',
      'go_to_chapter',
      'go_to_lesson',
      if (page == 0 && onboardingComplete) 'start_learning',
      if (learningPaused) 'resume_learning',
      if (!learningPaused && (page == 1 || page == 2)) 'pause_learning',
      if (activeChapters.length > 2) 'open_word_lessons',
      if (activeChapters.any((item) => item.exercises.isNotEmpty))
        'teach_letter',
      if (page == 2) 'next_exercise',
      if (page == 2 && lessonItem > 0) 'previous_exercise',
      if (page == 2) 'repeat',
      if (page == 2) 'repeat_lesson',
      if (page == 2) 'start_practice',
      if (page == 2 && chapter > 0) 'start_assessment',
      if (page == 2 && validatedWordTestAvailable) 'start_word_test',
      if (page == 2 && validatedWordTestAvailable) 'start_skill_test',
      if (options.isNotEmpty) 'select_answer',
      if (options.isNotEmpty || page == 1) 'check_answer',
      if (activeQuestion != null) 'read_question',
      if (activeQuestion != null) 'repeat_question',
      if (activeInstruction != null) 'read_instructions',
      if (currentFeedback != null) 'read_feedback',
      if (activeQuestion != null && options.isNotEmpty) 'read_options',
      if (page == 2) 'what_exercise',
      if (page == 1 || page == 2) 'give_hint',
      if (activeAssessment) 'exit_assessment',
      if (completedLessonQuestions.isNotEmpty || completedWordStages.isNotEmpty)
        'start_revision',
      if (completedLessonQuestions.isNotEmpty) 'get_skill_mastery',
      if (_latestAdaptiveDecision != null) 'get_recommendation',
      if (lessonAttempts.values.any((attempts) => attempts > 1))
        'start_targeted_practice',
    }.toList();
    return TutorScreenContext(
      screenName: screenName,
      language: selectedLanguage.storageName,
      module: page == 2 ? currentChapter.title : null,
      lesson: lesson,
      exerciseNumber: exerciseNumber,
      exerciseCount: exerciseCount,
      instruction: activeInstruction,
      question: activeQuestion,
      options: options,
      selectedAnswer: selectedLessonAnswer,
      answerSubmitted: lessonFeedback != null,
      feedback: currentFeedback,
      availableActions: [
        if (page == 2) 'repeat',
        if (page == 2 && !lessonAssessment && !wordAssessment) 'start practice',
        if (page == 2 && options.isNotEmpty) 'read options, select an option',
        if (page == 2 && selectedLessonAnswer != null) 'submit answer',
        if (page == 1) 'read instructions, check answer, clear pattern',
        if (page == 2 && lessonItem > 0) 'previous exercise',
        if (page == 2 && lessonItem + 1 < currentChapter.exercises.length)
          'next exercise',
        'switch language',
        'read progress',
      ],
      availableIntentActions: intentActions,
      contextMetadata: {
        'content_language': selectedLanguage.storageName,
        'speech_recognition_locale': voiceAssessmentSettings.recognitionLocale,
        'tutor_response_language': selectedLanguage.storageName,
        'ui_language': 'English',
        'assessment_active': activeAssessment,
        'learning_paused': learningPaused,
        'chapter_index': chapter,
        'lesson_index': lessonItem,
        'word_lesson_index': wordChapterLessonIndex,
        'word_assessment_available': validatedWordTestAvailable,
        'completed_lessons': completedLessonQuestions.length,
        'completed_word_stages': completedWordStages.length,
        'destinations': activeChapters.map((item) => item.title).toList(),
      },
      visibleBrailleDescription:
          keyboard != null && keyboard.selectedDots.isNotEmpty
          ? 'The selected cell has ${keyboard.dotLabel == 'None' ? 'no dots' : 'dots ${keyboard.dotLabel}'}. '
          : null,
      accessibilityInstruction: page == 1
          ? 'Choose dots one through six, then use the keyboard status strip to check the cell.'
          : null,
      completedItems:
          completedLessonQuestions.length + completedWordStages.length,
    );
  }

  bool get _adaptiveRequirementActive =>
      _activeAdaptiveDecision?.requiresLearningAction ?? false;

  AdaptivePracticeQuestion? get _currentAdaptivePracticeQuestion {
    if (!lessonAssessment) return null;
    final decision = _activeAdaptiveDecision;
    final question = decision?.nextQuestion;
    if (question == null ||
        question.lessonId != currentExercise.id ||
        question.skillId != currentExercise.skillId ||
        adaptiveLanguageCode(question.language) != selectedLanguage.code) {
      return null;
    }
    return question;
  }

  String get _lessonQuestionPrompt =>
      _currentAdaptivePracticeQuestion?.questionText ?? currentExercise.prompt;

  List<String> get _lessonQuestionOptions =>
      _currentAdaptivePracticeQuestion?.options ?? currentExercise.options;

  String get _adaptiveRequirementMessage {
    final decision = _activeAdaptiveDecision;
    if (decision == null) return '';
    return 'Adaptive learning assigned ${decision.recommendedLessonId}. ${decision.reason}';
  }

  AdaptiveWordRecommendation _wordRecommendation(
    List<String> candidates, {
    AppLanguage? language,
  }) => adaptiveWordRecommender.recommend(
    language: language ?? selectedLanguage,
    candidates: candidates,
    history: _learningHistory,
  );

  int _nextRecommendedWordIndex(String stageId, List<String> words) {
    final done = completedStageWords[stageId] ?? const <int>{};
    final incomplete = <int>[
      for (var index = 0; index < words.length; index++)
        if (!done.contains(index)) index,
    ];
    if (incomplete.isEmpty) return words.length;
    final candidates = incomplete.map((index) => words[index]).toList();
    final recommended = _wordRecommendation(candidates).rankedWords.first;
    return incomplete.firstWhere(
      (index) => words[index] == recommended,
      orElse: () => incomplete.first,
    );
  }

  Map<int, List<String>> get _englishAdaptiveWordOrders => {
    for (var index = 0; index < LessonCatalog.wordLessons.length; index++)
      index: index == LessonCatalog.wordLessons.length - 1
          ? List<String>.from(LessonCatalog.wordLessons[index].words)
          : _wordRecommendation(
              LessonCatalog.wordLessons[index].words,
              language: AppLanguage.english,
            ).rankedWords,
  };

  Map<int, String> get _englishAdaptiveWordReasons => {
    for (var index = 0; index < LessonCatalog.wordLessons.length; index++)
      index: index == LessonCatalog.wordLessons.length - 1
          ? 'The mastery test keeps its fixed validated word set.'
          : _wordRecommendation(
              LessonCatalog.wordLessons[index].words,
              language: AppLanguage.english,
            ).reason,
  };

  @override
  void initState() {
    super.initState();
    if (widget.enablePhysicalTutorKeys && !kIsWeb) {
      _physicalTutorSubscription = _physicalTutorEvents
          .receiveBroadcastStream()
          .listen(_handlePhysicalTutorEvent, onError: (_) {});
    }
    activeAccount = widget.learnerAccount;
    liveDemoClient = widget.demoClient ?? LiveDemoClient();
    selectedLanguage = AppLanguage.fromCode(
      widget.learnerAccount?.preferredLanguage,
    );
    progressReady = restoreLessonProgress();
    restoreOnboarding();
    configureAudio();
    unawaited(_restoreVoiceAssessmentSettings());
  }

  Future<void> _restoreVoiceAssessmentSettings() async {
    try {
      _voiceAssessmentSettingsStore =
          await VoiceAssessmentSettingsStore.forApplication();
      final saved = await _voiceAssessmentSettingsStore!.load();
      if (mounted) setState(() => voiceAssessmentSettings = saved);
    } catch (_) {
      // Safe defaults leave automatic microphone use disabled.
    }
  }

  Future<void> _saveVoiceAssessmentSettings(
    VoiceAssessmentSettings settings,
  ) async {
    setState(() => voiceAssessmentSettings = settings);
    try {
      _voiceAssessmentSettingsStore ??=
          await VoiceAssessmentSettingsStore.forApplication();
      await _voiceAssessmentSettingsStore!.save(settings);
    } catch (_) {
      if (mounted) {
        setState(
          () => voiceAssessmentSettings = const VoiceAssessmentSettings(),
        );
        speak(
          'Voice assessment settings could not be saved. Automatic listening remains off.',
        );
      }
    }
  }

  void _emitDemoEvent(
    String type, {
    Map<String, Object?> payload = const {},
    String? correlationId,
  }) {
    final screen = page >= 0 && page < pages.length ? pages[page] : 'Learning';
    liveDemoClient.emit(
      type,
      payload: {
        'screen': screen,
        'language': selectedLanguage.storageName,
        if (page == 2) 'module': currentChapter.title,
        if (page == 2)
          'lesson': currentExercise.answer.isEmpty
              ? currentChapter.title
              : currentExercise.answer,
        ...payload,
      },
      correlationId: correlationId,
    );
  }

  Future<void> _prepareAssessmentVoice() async {
    if (_assessmentVoicePreparationPending || _assessmentVoicePrepared) return;
    _assessmentVoicePreparationPending = true;
    try {
      final settings = voiceAssessmentSettings;
      if (!settings.enabled) return;
      _assessmentVoicePrepared = true;
      final contextSnapshot = tutorScreenContext;
      if (settings.stopListeningForSpeech) {
        await _activeTutorController?.pauseListeningForSpeech();
      }
      if (settings.readQuestions) {
        final question =
            contextSnapshot.question ?? contextSnapshot.readInstructions();
        if (question.isNotEmpty) await speak('Question. $question');
        if (!mounted ||
            !(lessonAssessment || wordAssessment || cumulativeAssessment)) {
          return;
        }
      }
      if (settings.readOptions && contextSnapshot.options.isNotEmpty) {
        await speak(contextSnapshot.readOptions());
        _emitDemoEvent(
          'assessment_options_read',
          payload: {'option_count': contextSnapshot.options.length},
        );
      }
      if (!settings.activateTutorOnAssessment || !mounted) return;
      await speak(
        settings.listenAfterReading
            ? 'Voice assessment is ready. Listening will begin after the tutor opens.'
            : 'Voice assessment is ready. Activate listening when you want to answer.',
      );
      await openVoiceTutor(startListening: settings.listenAfterReading);
    } finally {
      _assessmentVoicePreparationPending = false;
    }
  }

  void _scheduleAssessmentVoicePreparation() {
    final active = lessonAssessment || wordAssessment || cumulativeAssessment;
    if (!active) {
      _assessmentVoicePrepared = false;
      _assessmentVoicePreparationPending = false;
      _lastAssessmentVoiceKey = null;
      _lastDemoAssessmentKey = null;
      return;
    }
    final key =
        '${selectedLanguage.code}:$chapter:$lessonItem:$assessmentWord:${currentExercise.id}';
    if (_lastDemoAssessmentKey != key) {
      _lastDemoAssessmentKey = key;
      _emitDemoEvent(
        'assessment_opened',
        payload: {
          'activity': wordAssessment ? 'word_writing' : 'lesson_assessment',
          'question_number': lessonItem + 1,
        },
      );
    }
    if (_lastAssessmentVoiceKey != key) {
      _lastAssessmentVoiceKey = key;
      _assessmentVoicePrepared = false;
    }
    final settings = voiceAssessmentSettings;
    if (!settings.enabled ||
        _assessmentVoicePrepared ||
        _assessmentVoicePreparationPending) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepareAssessmentVoice());
    });
  }

  void _handlePhysicalTutorEvent(dynamic event) {
    if (!mounted) return;
    switch (event) {
      case 'activate':
        _physicalTutorMode = true;
        unawaited(openVoiceTutor(physicalActivation: true));
      case 'speak':
        if (_physicalTutorMode) {
          final controller = _activeTutorController;
          if (controller != null) {
            unawaited(controller.startListening());
          } else {
            unawaited(
              speak(
                'Resonant Tutor is opening. Press volume up again to speak.',
              ),
            );
          }
        }
      case 'cycleLanguage':
        _cycleLanguageFromGesture(fromPhysicalKey: true);
      case 'cancel':
        _physicalTutorMode = false;
        unawaited(_cancelPhysicalTutor());
    }
  }

  Future<void> _setPhysicalTutorActive(bool active) async {
    if (kIsWeb || !widget.enablePhysicalTutorKeys) return;
    try {
      await _physicalTutorControl.invokeMethod<void>(
        'setActive',
        <String, Object>{'active': active},
      );
    } catch (_) {}
  }

  Future<void> _cancelPhysicalTutor() async {
    await _activeTutorController?.clearConversation();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await speak('Tutor mode cancelled. The microphone is off.');
  }

  Future<void> _saveCurrentResume({
    bool clearPausedWordAssessment = false,
  }) async {
    await progressReady;
    final store = progressStore;
    await store?.saveResumeState(
      languageCode: selectedLanguage.code,
      chapter: chapter,
      lessonItem: lessonItem,
      wordLessonIndex: wordChapterLessonIndex,
    );
    if (_pausedWordAssessment != null || clearPausedWordAssessment) {
      await store?.savePausedWordAssessment(
        languageCode: selectedLanguage.code,
        pausedAssessment: _pausedWordAssessment?.toJson(),
      );
    }
  }

  List<String> _wordsForAssessmentStage(String stageId) {
    if (stageId == 'cumulative') return LessonCatalog.cumulativeWords;
    if (stageId == 'hi-word-test') {
      return LessonCatalog.chaptersFor(
        AppLanguage.hindi,
      )[2].exercises.map((exercise) => exercise.answer).toList();
    }
    if (stageId == 'kn-word-test') {
      return LessonCatalog.chaptersFor(
        AppLanguage.kannada,
      )[2].exercises.map((exercise) => exercise.answer).toList();
    }
    return LessonCatalog.curriculum
            .where((stage) => stage.id == stageId)
            .firstOrNull
            ?.words ??
        const <String>[];
  }

  int? _letterLessonIndex(String character, AppLanguage language) {
    final chapters = LessonCatalog.chaptersFor(language);
    if (chapters.length < 2) return null;
    final target = language == AppLanguage.english
        ? character.toLowerCase()
        : character;
    for (var index = 0; index < chapters[1].exercises.length; index++) {
      final answer = chapters[1].exercises[index].answer;
      final comparable = language == AppLanguage.english
          ? answer.toLowerCase()
          : answer;
      if (comparable == target) return index;
    }
    return null;
  }

  int _nextAssessmentWordAfter(String stageId, List<String> words, int failed) {
    final completed = completedStageWords[stageId] ?? const <int>{};
    return PausedWordAssessment.nextUncompletedWord(
      failedIndex: failed,
      wordCount: words.length,
      completedIndices: completed,
    );
  }

  Future<bool> _beginWordLetterRemediation({
    required String? submissionId,
    required String stageId,
    required int wordIndex,
    required String word,
    required AppLanguage language,
    required List<Map<String, dynamic>> observations,
  }) async {
    if (submissionId == null) return false;
    final error = observations
        .where((item) => item['correct'] != true)
        .firstOrNull;
    final character = error?['character'];
    if (character is! String || character.isEmpty) return false;
    final lessonIndex = _letterLessonIndex(character, language);
    if (lessonIndex == null) return false;
    final words = _wordsForAssessmentStage(stageId);
    if (wordIndex < 0 || wordIndex >= words.length) return false;
    _pausedWordAssessment = PausedWordAssessment(
      assessmentSubmissionId: submissionId,
      stageId: stageId,
      language: language.code,
      wordIndex: wordIndex,
      word: word,
      cumulative: cumulativeAssessment,
      lessonItem: lessonItem,
      letter: character,
      letterLessonIndex: lessonIndex,
      nextWordIndex: _nextAssessmentWordAfter(stageId, words, wordIndex),
    );
    setState(() {
      chapter = 1;
      lessonItem = lessonIndex;
      wordAssessment = false;
      lessonAssessment = false;
      guidedPractice = false;
      lessonTaught = false;
      selectedLessonAnswer = null;
      lessonAnswerCorrect = false;
      assessmentCells.clear();
      page = 2;
      lessonFeedback =
          'Mistake with ${language == AppLanguage.english ? 'letter ' : ''}$character. Let us learn it, then continue the word assessment.';
      exerciseStartedAt = DateTime.now();
    });
    await _saveCurrentResume();
    feedback();
    await speak(lessonFeedback!);
    await speak(_lessonExplanation());
    return true;
  }

  Future<void> _resumePausedWordAssessment() async {
    final paused = _pausedWordAssessment;
    if (paused == null) return;
    final words = _wordsForAssessmentStage(paused.stageId);
    if (words.isEmpty) {
      await speak('The saved word assessment could not be restored safely.');
      return;
    }
    final next =
        paused.nextWordIndex >= 0 && paused.nextWordIndex < words.length
        ? paused.nextWordIndex
        : paused.wordIndex;
    setState(() {
      chapter = 1;
      lessonItem = paused.lessonItem;
      cumulativeAssessment = paused.cumulative;
      wordAssessment = true;
      lessonAssessment = false;
      guidedPractice = false;
      lessonTaught = true;
      assessmentWordIndex = next;
      assessmentWord = words[next];
      assessmentCells.clear();
      lessonAnswerCorrect = false;
      lessonFeedback =
          'Letter remediation completed. The earlier word remains eligible for revision.';
      page = 2;
      _pausedWordAssessment = null;
      exerciseStartedAt = DateTime.now();
    });
    await _saveCurrentResume(clearPausedWordAssessment: true);
    feedback();
    await speak(
      'You practised ${paused.letter}. Continuing the word assessment. Write ${words[next]} using the six-dot Braille keyboard.',
    );
  }

  Future<void> switchLanguage(AppLanguage lang, {bool announce = true}) async {
    if (_pausedWordAssessment != null) {
      if (announce) {
        await speak(
          'Finish the letter practice for ${_pausedWordAssessment!.letter} before switching languages. Your word assessment is paused safely.',
        );
      }
      return;
    }
    if (lessonAssessment || wordAssessment || cumulativeAssessment) {
      _emitDemoEvent(
        'assessment_abandoned',
        payload: {'recorded_as_complete': false, 'reason': 'language_change'},
      );
    }
    await _saveCurrentResume();
    final targetResume =
        await progressStore?.readResumeStateFor(lang.code) ?? {};
    final languageChapters = LessonCatalog.chaptersFor(lang);
    brailleKeyboardKey.currentState?.clearPattern();
    setState(() {
      if (page == 1) page = 2;
      selectedLanguage = lang;
      chapter =
          targetResume['chapter'] is int &&
              (targetResume['chapter'] as int) >= 0 &&
              (targetResume['chapter'] as int) < languageChapters.length
          ? targetResume['chapter'] as int
          : lang == AppLanguage.english
          ? 1
          : 0;
      final chapterExercises = languageChapters[chapter].exercises;
      lessonItem =
          targetResume['lesson_item'] is int &&
              (targetResume['lesson_item'] as int) >= 0 &&
              (targetResume['lesson_item'] as int) < chapterExercises.length
          ? targetResume['lesson_item'] as int
          : 0;
      if (lang == AppLanguage.english &&
          chapter == 2 &&
          targetResume['word_lesson_index'] is int) {
        wordChapterLessonIndex = (targetResume['word_lesson_index'] as int)
            .clamp(0, LessonCatalog.wordLessons.length - 1);
      }
      _vernacularIntroStep = 0;
      lessonTaught = false;
      guidedPractice = false;
      lessonAssessment = false;
      wordAssessment = false;
      courseComplete = false;
      lessonFeedback = null;
      selectedLessonAnswer = null;
      assessmentCells.clear();
      if (lang != AppLanguage.english && targetResume.isEmpty) {
        _selectVernacularResumePoint();
      }
    });
    try {
      await tts.setLanguage(lang.ttsLocale);
      await tts.setSpeechRate(0.45);
    } catch (_) {}
    await _saveCurrentResume();
    _emitDemoEvent(
      'language_changed',
      payload: {
        'language': lang.storageName,
        'chapter': chapter + 1,
        'lesson_number': lessonItem + 1,
      },
    );
    final preferenceSaved = await _persistPreferredLanguage(lang);
    await _refreshAdaptiveDecisionState();
    if (announce) {
      final msg = switch (lang) {
        AppLanguage.english =>
          'Language switched to English. ${currentChapter.title}.',
        AppLanguage.hindi => 'भाषा हिंदी चुनी गई है। ${currentChapter.title}।',
        AppLanguage.kannada =>
          'ಕನ್ನಡ ಭಾಷೆಯನ್ನು ಆಯ್ಕೆ ಮಾಡಲಾಗಿದೆ. ${currentChapter.title}.',
      };
      await speak(
        preferenceSaved || activeAccount == null
            ? '$msg ${lang != AppLanguage.english && chapter == 0 ? _introStepAnnouncement(lang, _vernacularIntroStep) : ''}'
            : '$msg This choice is saved on this device. Connect to the Resonant server to update the account for other devices. ${lang != AppLanguage.english && chapter == 0 ? _introStepAnnouncement(lang, _vernacularIntroStep) : ''}',
      );
    }
  }

  void _cycleLanguageFromGesture({bool fromPhysicalKey = false}) {
    if (_pausedWordAssessment != null) {
      unawaited(
        speak(
          'Finish the letter practice for ${_pausedWordAssessment!.letter} before switching languages.',
        ),
      );
      return;
    }
    if (_adaptiveRequirementActive) {
      unawaited(
        speak(
          'Complete the assigned remediation and reassessment before changing learning language.',
        ),
      );
      return;
    }
    if (!fromPhysicalKey &&
        (page == 1 || guidedPractice || lessonAssessment || wordAssessment)) {
      return;
    }
    final next = AppLanguage
        .values[(selectedLanguage.index + 1) % AppLanguage.values.length];
    feedback();
    unawaited(switchLanguage(next));
  }

  List<String> _introStepsFor(AppLanguage language) => switch (language) {
    AppLanguage.english => const [],
    AppLanguage.hindi => const [
      'ब्रेल में आपका स्वागत है। ब्रेल स्पर्श से पढ़ी और लिखी जाने वाली प्रणाली है।',
      'ब्रेल उन लोगों को पढ़ने और लिखने में मदद करती है जो मुद्रित अक्षर नहीं देख पाते।',
      'एक मानक ब्रेल सेल में दो कॉलम और तीन पंक्तियाँ होती हैं, यानी छह स्थान।',
      'बाईं ओर ऊपर से नीचे बिंदु 1, 2, 3 और दाईं ओर 4, 5, 6 हैं।',
      'इन स्थानों के अलग-अलग संयोजन वर्ण बनाते हैं। सटीक हिंदी रूप सत्यापित भारती तालिका से सीखेंगे।',
    ],
    AppLanguage.kannada => const [
      'ಬ್ರೈಲ್ ಕಲಿಕೆಗೆ ಸುಸ್ವಾಗತ. ಬ್ರೈಲ್ ಸ್ಪರ್ಶದ ಮೂಲಕ ಓದಿ ಬರೆಯುವ ಪದ್ಧತಿ.',
      'ಮುದ್ರಿತ ಅಕ್ಷರಗಳನ್ನು ನೋಡಲು ಸಾಧ್ಯವಾಗದವರಿಗೆ ಬ್ರೈಲ್ ಓದಲು ಮತ್ತು ಬರೆಯಲು ಸಹಾಯ ಮಾಡುತ್ತದೆ.',
      'ಸಾಮಾನ್ಯ ಬ್ರೈಲ್ ಕೋಶದಲ್ಲಿ ಎರಡು ಕಾಲಮ್‌ಗಳು ಮತ್ತು ಮೂರು ಸಾಲುಗಳು, ಒಟ್ಟು ಆರು ಸ್ಥಾನಗಳಿವೆ.',
      'ಎಡಭಾಗದಲ್ಲಿ ಮೇಲಿನಿಂದ ಕೆಳಗೆ 1, 2, 3 ಮತ್ತು ಬಲಭಾಗದಲ್ಲಿ 4, 5, 6 ಚುಕ್ಕೆಗಳಿವೆ.',
      'ಈ ಸ್ಥಾನಗಳ ವಿಭಿನ್ನ ಸಂಯೋಜನೆಗಳು ಅಕ್ಷರಗಳನ್ನು ಸೂಚಿಸುತ್ತವೆ. ಕನ್ನಡದ ನಿಖರ ರೂಪಗಳನ್ನು ಪರಿಶೀಲಿತ ಭಾರತಿ ಪಟ್ಟಿಯಿಂದ ಕಲಿಯುತ್ತೇವೆ.',
    ],
  };

  String _introStepAnnouncement(AppLanguage language, int step) {
    final steps = _introStepsFor(language);
    final hint = language == AppLanguage.hindi
        ? 'परिचय भाग ${step + 1} में से ${steps.length}। अगले भाग के लिए दो उंगलियों से बाईं ओर स्वाइप करें; पिछले भाग के लिए दाईं ओर।'
        : 'ಪರಿಚಯದ ಭಾಗ ${step + 1}ರಲ್ಲಿ ${steps.length}. ಮುಂದಿನ ಭಾಗಕ್ಕೆ ಎರಡು ಬೆರಳುಗಳಿಂದ ಎಡಕ್ಕೆ; ಹಿಂದಿನ ಭಾಗಕ್ಕೆ ಬಲಕ್ಕೆ ಸ್ವೈಪ್ ಮಾಡಿ.';
    return '${steps[step]} $hint';
  }

  void _navigateIntroduction(int direction) {
    if (!mounted || direction == 0) return;
    final steps = _introStepsFor(selectedLanguage);
    final next = _vernacularIntroStep + direction;
    if (next < 0) {
      feedback();
      unawaited(
        speak(
          selectedLanguage == AppLanguage.hindi
              ? 'यह पहला परिचय भाग है। आगे के लिए दो उंगलियों से बाईं ओर स्वाइप करें।'
              : 'ಇದು ಮೊದಲ ಪರಿಚಯದ ಭಾಗ. ಮುಂದಕ್ಕೆ ಹೋಗಲು ಎರಡು ಬೆರಳುಗಳಿಂದ ಎಡಕ್ಕೆ ಸ್ವೈಪ್ ಮಾಡಿ.',
        ),
      );
      return;
    }
    if (next >= steps.length) {
      setState(() {
        chapter = 1;
        lessonItem = 0;
        lessonTaught = false;
        _vernacularIntroStep = 0;
        guidedPractice = false;
        wordAssessment = false;
        lessonFeedback = null;
        selectedLessonAnswer = null;
      });
      unawaited(_saveCurrentResume());
      feedback();
      unawaited(
        speak(
          selectedLanguage == AppLanguage.hindi
              ? 'परिचय पूरा हुआ। अब पहला अक्षर पाठ शुरू करते हैं। ${_lessonExplanation()}'
              : 'ಪರಿಚಯ ಮುಗಿದಿದೆ. ಈಗ ಮೊದಲ ಅಕ್ಷರದ ಪಾಠ ಆರಂಭಿಸೋಣ. ${_lessonExplanation()}',
        ),
      );
      return;
    }
    setState(() => _vernacularIntroStep = next);
    feedback();
    unawaited(speak(_introStepAnnouncement(selectedLanguage, next)));
  }

  void _navigateSection(int direction) {
    if (page != 2 ||
        chapter == 2 ||
        guidedPractice ||
        lessonAssessment ||
        wordAssessment) {
      return;
    }
    if (chapter == 0 &&
        selectedLanguage != AppLanguage.english &&
        !lessonTaught) {
      unawaited(
        speak(
          selectedLanguage == AppLanguage.hindi
              ? 'परिचय के भाग बदलने के लिए दो उंगलियों से बाईं या दाईं ओर स्वाइप करें।'
              : 'ಪರಿಚಯದ ಭಾಗಗಳನ್ನು ಬದಲಿಸಲು ಎರಡು ಬೆರಳುಗಳಿಂದ ಎಡಕ್ಕೆ ಅಥವಾ ಬಲಕ್ಕೆ ಸ್ವೈಪ್ ಮಾಡಿ.',
        ),
      );
      return;
    }
    final nextChapterIndex = chapter + direction;
    if (nextChapterIndex < 0 || nextChapterIndex >= activeChapters.length) {
      unawaited(
        speak(
          direction > 0
              ? 'You are at the last section.'
              : 'You are at the first section.',
        ),
      );
      return;
    }
    setState(() {
      chapter = nextChapterIndex;
      lessonItem = 0;
      if (chapter == 0 && selectedLanguage != AppLanguage.english) {
        _vernacularIntroStep = 0;
      }
      lessonTaught = false;
      guidedPractice = false;
      lessonFeedback = null;
      page = 2;
    });
    feedback();
    unawaited(_saveCurrentResume());
    unawaited(
      speak(
        chapter == 0 && selectedLanguage != AppLanguage.english
            ? _introStepAnnouncement(selectedLanguage, _vernacularIntroStep)
            : '${currentChapter.title}. Section ${chapter + 1} of ${activeChapters.length}. ${currentExercise.prompt}',
      ),
    );
  }

  Future<bool> _persistPreferredLanguage(AppLanguage language) async {
    final account = activeAccount;
    if (account == null) return true;
    final updated = account.withPreferredLanguage(language.storageName);
    activeAccount = updated;
    try {
      final storage =
          widget.accountStorage ?? await LearnerAccountStore.forApplication();
      await storage.save(updated);
    } catch (_) {
      // Keep the current selection usable if local storage is unavailable.
    }
    try {
      final api = widget.learnerApi ?? LearnerApi();
      await api.updatePreferredLanguage(
        learnerId: account.learnerId,
        learnerCode: account.learnerCode,
        preferredLanguage: language.storageName,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> restoreOnboarding() async {
    try {
      final store =
          widget.onboardingProgress ?? await OnboardingStore.forApplication();
      onboardingStore = store;
      onboardingComplete = await store.isComplete();
      if (!onboardingComplete) onboardingStep = await store.currentStep();
    } catch (_) {
      onboardingComplete = false;
    }
    if (onboardingComplete) {
      await progressReady;
      _selectResumePoint();
      _selectWordChapterResumePoint();
      chapter = selectedLanguage == AppLanguage.english
          ? (courseComplete ? 2 : 1)
          : 0;
      if (selectedLanguage == AppLanguage.english &&
          courseComplete &&
          wordChapterComplete) {
        _selectComposedResumePoint();
      } else if (selectedLanguage != AppLanguage.english) {
        _selectVernacularResumePoint();
      }
      page = 2;
      lessonTaught = !wordAssessment;

      final latestResume = await progressStore?.readResumeState() ?? {};
      if (widget.learnerAccount == null && latestResume.isNotEmpty) {
        selectedLanguage = AppLanguage.fromCode(
          latestResume['language'] as String?,
        );
      }
      final savedResume =
          await progressStore?.readResumeStateFor(selectedLanguage.code) ?? {};
      if (savedResume.isNotEmpty &&
          savedResume['language'] == selectedLanguage.code) {
        final savedChapter = savedResume['chapter'];
        final savedItem = savedResume['lesson_item'];
        final savedWordIdx = savedResume['word_lesson_index'];
        if (savedChapter is int &&
            savedChapter >= 0 &&
            savedChapter < activeChapters.length &&
            _chapterPrerequisitesComplete(savedChapter)) {
          chapter = savedChapter;
          if (savedItem is int &&
              savedItem >= 0 &&
              savedItem < currentChapter.exercises.length &&
              _resumeLessonPrerequisitesComplete(savedChapter, savedItem)) {
            lessonItem = savedItem;
          }
        }
        if (savedWordIdx is int &&
            savedWordIdx >= 0 &&
            savedWordIdx < LessonCatalog.wordLessons.length) {
          wordChapterLessonIndex = savedWordIdx;
        }
        final pausedAssessment = PausedWordAssessment.fromJson(
          savedResume['paused_word_assessment'],
        );
        if (pausedAssessment != null &&
            pausedAssessment.language == selectedLanguage.code &&
            pausedAssessment.letterLessonIndex >= 0 &&
            pausedAssessment.letterLessonIndex <
                LessonCatalog.chaptersFor(
                  selectedLanguage,
                )[1].exercises.length) {
          _pausedWordAssessment = pausedAssessment;
          chapter = 1;
          lessonItem = pausedAssessment.letterLessonIndex;
          wordAssessment = false;
          lessonAssessment = false;
          guidedPractice = false;
          lessonTaught = false;
          page = 2;
        }
        try {
          await tts.setLanguage(selectedLanguage.ttsLocale);
        } catch (_) {}
      } else if (selectedLanguage != AppLanguage.english) {
        _selectVernacularResumePoint();
      }
      lessonTaught =
          !wordAssessment &&
          !(selectedLanguage != AppLanguage.english &&
              chapter == 0 &&
              lessonItem == 0);
    }
    if (mounted) setState(() => onboardingLoading = false);
    final adaptive = _activeAdaptiveDecision;
    if (onboardingComplete &&
        mounted &&
        adaptive != null &&
        adaptive.requiresLearningAction) {
      await _applyAdaptiveDecision(adaptive, announce: true);
      return;
    }
    if (onboardingComplete && mounted) {
      unawaited(
        speak(
          _pausedWordAssessment != null
              ? 'Your word assessment is paused for a lesson on ${_pausedWordAssessment!.letter}. ${_lessonExplanation()}'
              : selectedLanguage != AppLanguage.english &&
                    chapter == 0 &&
                    lessonItem == 0
              ? (selectedLanguage == AppLanguage.hindi
                    ? 'ब्रेल में आपका स्वागत है। ब्रेल स्पर्श से पढ़ी जाने वाली लेखन प्रणाली है। एक मानक सेल में छह बिंदु होते हैं।'
                    : 'ಬ್ರೈಲ್‌ಗೆ ಸ್ವಾಗತ. ಬ್ರೈಲ್ ಸ್ಪರ್ಶದ ಮೂಲಕ ಓದುವ ಬರವಣಿಗೆ ವಿಧಾನ. ಸಾಮಾನ್ಯ ಕೋಶದಲ್ಲಿ ಆರು ಚುಕ್ಕೆಗಳಿರುತ್ತವೆ.')
              : selectedLanguage != AppLanguage.english
              ? '${currentChapter.title}. ${currentExercise.prompt}'
              : chapter == 2
              ? '${LessonCatalog.wordLessons[wordChapterLessonIndex].title}. ${LessonCatalog.wordLessons[wordChapterLessonIndex].description}'
              : wordAssessment
              ? 'Welcome back. Resume the word test. The word is $assessmentWord.'
              : 'Welcome back. ${_lessonExplanation()}',
        ),
      );
    }
  }

  Future<void> finishOnboarding({bool announce = true}) async {
    try {
      await onboardingStore?.markComplete();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      onboardingComplete = true;
      replayingOnboarding = false;
      page = 2;
      chapter = 1;
      lessonItem = 0;
      lessonTaught = true;
      guidedPractice = false;
      _selectResumePoint();
      _selectWordChapterResumePoint();
      chapter = selectedLanguage == AppLanguage.english
          ? (courseComplete ? 2 : 1)
          : 0;
      if (selectedLanguage == AppLanguage.english &&
          courseComplete &&
          wordChapterComplete) {
        _selectComposedResumePoint();
      } else if (selectedLanguage != AppLanguage.english) {
        _selectVernacularResumePoint();
      }
    });
    if (announce) {
      await speak(
        selectedLanguage != AppLanguage.english
            ? '${currentChapter.title}. ${currentExercise.prompt} ${currentExercise.explanation}'
            : chapter == 2
            ? '${LessonCatalog.wordLessons[wordChapterLessonIndex].title}. ${LessonCatalog.wordLessons[wordChapterLessonIndex].description}'
            : 'Let us begin with letter ${currentExercise.answer.toUpperCase()}. ${_lessonExplanation()}',
      );
    }
  }

  void continueLearning({bool announce = true}) {
    final adaptive = _activeAdaptiveDecision;
    if (adaptive != null && adaptive.requiresLearningAction) {
      unawaited(_applyAdaptiveDecision(adaptive, announce: announce));
      return;
    }
    if (selectedLanguage != AppLanguage.english) {
      _selectVernacularResumePoint();
      setState(() {
        page = 2;
        lessonTaught = false;
        guidedPractice = false;
      });
      if (announce) {
        speak('${currentChapter.title}. ${currentExercise.prompt}');
      }
      return;
    }
    _selectResumePoint();
    _selectWordChapterResumePoint();
    if (courseComplete && wordChapterComplete) {
      _selectComposedResumePoint();
    }
    setState(() {
      page = 2;
      if (!courseComplete) chapter = 1;
      if (courseComplete && !wordChapterComplete) chapter = 2;
      lessonTaught = !wordAssessment;
      guidedPractice = false;
    });
    if (announce && courseComplete) {
      speak(
        wordChapterComplete
            ? 'Continue with ${currentChapter.title}. ${currentExercise.prompt}'
            : 'Continue with ${LessonCatalog.wordLessons[wordChapterLessonIndex].title}.',
      );
    } else if (announce) {
      speak(
        wordAssessment
            ? 'Resume the ${currentCurriculumStage.title} word test. Write $assessmentWord.'
            : _lessonExplanation(),
      );
    }
  }

  void _selectVernacularResumePoint() {
    final chapters = LessonCatalog.chaptersFor(selectedLanguage);
    if (_wordProgressionComplete) {
      for (
        var chapterIndex = 3;
        chapterIndex < chapters.length;
        chapterIndex++
      ) {
        final exercises = chapters[chapterIndex].exercises;
        final next = exercises.indexWhere(
          (exercise) => !completedLessonQuestions.contains(exercise.id),
        );
        if (next >= 0) {
          chapter = chapterIndex;
          lessonItem = next;
          wordAssessment = false;
          return;
        }
      }
      chapter = chapters.length - 1;
      lessonItem = chapters.last.exercises.length - 1;
      wordAssessment = false;
      return;
    }
    for (var chapterIndex = 0; chapterIndex < chapters.length; chapterIndex++) {
      final exercises = chapters[chapterIndex].exercises;
      for (
        var exerciseIndex = 0;
        exerciseIndex < exercises.length;
        exerciseIndex++
      ) {
        if (!completedLessonQuestions.contains(exercises[exerciseIndex].id)) {
          chapter = chapterIndex;
          lessonItem = exerciseIndex;
          wordAssessment = false;
          courseComplete = false;
          return;
        }
      }
    }
    chapter = chapters.length - 1;
    lessonItem = chapters.last.exercises.length - 1;
    courseComplete = true;
  }

  void replayWelcome() {
    setState(() => replayingOnboarding = true);
  }

  void _selectWordChapterResumePoint() {
    wordChapterComplete =
        wordChapterCompletedWords[4]?.length ==
        LessonCatalog.wordLessons[4].words.length;
    wordChapterLessonIndex = 4;
    for (var index = 0; index < 4; index++) {
      final lesson = LessonCatalog.wordLessons[index];
      final done = wordChapterCompletedWords[index] ?? const <String>{};
      if (!lesson.words.every(done.contains)) {
        wordChapterLessonIndex = index;
        return;
      }
    }
  }

  bool _selectComposedResumePoint() {
    if (!_wordProgressionComplete || activeChapters.length <= 3) return false;
    for (
      var chapterIndex = 3;
      chapterIndex < activeChapters.length;
      chapterIndex++
    ) {
      final next = activeChapters[chapterIndex].exercises.indexWhere(
        (exercise) => !completedLessonQuestions.contains(exercise.id),
      );
      if (next >= 0) {
        chapter = chapterIndex;
        lessonItem = next;
        wordAssessment = false;
        return true;
      }
    }
    chapter = activeChapters.length - 1;
    lessonItem = activeChapters.last.exercises.length - 1;
    wordAssessment = false;
    return true;
  }

  bool _chapterPrerequisitesComplete(int targetChapter) {
    if (targetChapter < 3) return true;
    if (!_wordProgressionComplete) return false;
    if (targetChapter < 4) return true;
    return _phraseProgressionComplete;
  }

  bool _resumeLessonPrerequisitesComplete(int targetChapter, int targetLesson) {
    if (targetLesson <= 0) return true;
    if (selectedLanguage == AppLanguage.english && targetChapter == 2) {
      return true;
    }
    return activeChapters[targetChapter].exercises
        .take(targetLesson)
        .every((exercise) => completedLessonQuestions.contains(exercise.id));
  }

  void _selectResumePoint() {
    for (final stage in LessonCatalog.curriculum) {
      final nextLetter =
          List<int>.generate(
                stage.last - stage.first + 1,
                (i) => stage.first + i,
              )
              .where(
                (index) => !completedLessonQuestions.contains(
                  'letter-${LessonCatalog.alphabet[index].toLowerCase()}',
                ),
              )
              .firstOrNull;
      if (nextLetter != null) {
        courseComplete = false;
        lessonItem = nextLetter;
        wordAssessment = false;
        cumulativeAssessment = false;
        assessmentWord = stage.words.first;
        return;
      }
      if (!completedWordStages.contains(stage.id)) {
        courseComplete = false;
        lessonItem = stage.last;
        assessmentWordIndex = _nextRecommendedWordIndex(stage.id, stage.words);
        assessmentWord = stage.words[assessmentWordIndex];
        wordAssessment = true;
        cumulativeAssessment = false;
        return;
      }
    }
    lessonItem = LessonCatalog.alphabet.length - 1;
    cumulativeAssessment = true;
    wordAssessment = !completedWordStages.contains('cumulative');
    assessmentWord = 'AMAZE';
    assessmentWordIndex = _nextRecommendedWordIndex(
      'cumulative',
      LessonCatalog.cumulativeWords,
    );
    if (assessmentWordIndex < LessonCatalog.cumulativeWords.length) {
      assessmentWord = LessonCatalog.cumulativeWords[assessmentWordIndex];
    }
    courseComplete = !wordAssessment;
  }

  Future<void> restoreLessonProgress() async {
    try {
      final store =
          widget.lessonProgressStore ??
          await LessonProgressStore.forApplication();
      final events = await store.readEvents();
      progressStore = store;
      _learningHistory = List<JsonMap>.from(events);
      for (final event in events) {
        final storedId = event['exercise_id'] as String?;
        if (storedId == null) continue;
        final isGuidedPractice = storedId.startsWith('guided-practice-');
        final isLessonAssessment = storedId.startsWith('lesson-assessment-');
        final id = isGuidedPractice
            ? storedId.substring('guided-practice-'.length)
            : isLessonAssessment
            ? storedId.substring('lesson-assessment-'.length)
            : storedId;
        lessonAttempts.update(id, (value) => value + 1, ifAbsent: () => 1);
        if (isLessonAssessment) {
          lessonAssessmentAttempts.update(
            id,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
        if (event['outcome'] == 'correct' && !isGuidedPractice) {
          completedLessonQuestions.add(id);
        }
        if (storedId.startsWith('word-stage-') &&
            event['outcome'] == 'correct') {
          final wordSeparator = storedId.lastIndexOf('-word-');
          final wordIndex = wordSeparator < 0
              ? null
              : int.tryParse(storedId.substring(wordSeparator + 6));
          if (wordIndex != null) {
            final stageId = storedId.substring(
              'word-stage-'.length,
              wordSeparator,
            );
            final vernacularLanguage = stageId == 'hi-word-test'
                ? AppLanguage.hindi
                : stageId == 'kn-word-test'
                ? AppLanguage.kannada
                : null;
            final words = stageId == 'cumulative'
                ? LessonCatalog.cumulativeWords
                : vernacularLanguage != null
                ? LessonCatalog.chaptersFor(
                    vernacularLanguage,
                  )[2].exercises.map((exercise) => exercise.answer).toList()
                : LessonCatalog.curriculum
                      .where((stage) => stage.id == stageId)
                      .firstOrNull
                      ?.words;
            if (words != null) {
              final done = completedStageWords.putIfAbsent(
                stageId,
                () => <int>{},
              );
              done.add(wordIndex);
              if (vernacularLanguage != null && wordIndex < words.length) {
                completedLessonQuestions.add(
                  LessonCatalog.chaptersFor(
                    vernacularLanguage,
                  )[2].exercises[wordIndex].id,
                );
              }
              if (done.length >= words.length) {
                completedWordStages.add(stageId);
              }
            }
          }
        }
        if (event['hint_used'] == true) hintedLessonQuestions.add(id);
      }
      final masteryRounds = <String, BoolMap>{};
      for (final event in events) {
        final id = event['exercise_id'] as String?;
        final match = id == null
            ? null
            : RegExp(r'^word-chapter-lesson-(\d+)-([a-z]+)$').firstMatch(id);
        if (match == null) continue;
        final lessonNumber = int.parse(match.group(1)!);
        final word = match.group(2)!.toUpperCase();
        final correct = event['outcome'] == 'correct';
        if (lessonNumber == 5) {
          final group = event['group_id'] as String?;
          if (group != null) {
            masteryRounds.putIfAbsent(group, () => {})[word] = correct;
          }
        } else if (correct) {
          wordChapterCompletedWords
              .putIfAbsent(lessonNumber - 1, () => <String>{})
              .add(word);
        }
      }
      for (final round in masteryRounds.values) {
        if (round.length == LessonCatalog.wordLessons[4].words.length &&
            round.values.where((correct) => correct).length >= 4) {
          wordChapterCompletedWords[4] = LessonCatalog.wordLessons[4].words
              .toSet();
          break;
        }
      }
      _activeAdaptiveDecision = await store.pendingAdaptiveDecision(
        languageCode: selectedLanguage.code,
      );
      _latestAdaptiveDecision = await store.latestAdaptiveDecision(
        languageCode: selectedLanguage.code,
      );
      _selectWordChapterResumePoint();
      if (mounted) setState(() {});
      unawaited(_syncPendingProgress(knownStore: store));
    } catch (_) {}
  }

  Future<String?> persistLessonAttempt(
    LessonExercise exercise,
    bool correct, {
    String? eventExerciseId,
    String? exerciseType,
    String? assessmentKey,
    String? lessonId,
    String? questionText,
    List<String>? options,
    String? learningObjective,
    int difficulty = 1,
    Map<String, dynamic>? expectedResponse,
    Map<String, dynamic>? submittedResponse,
    int? attemptNumber,
    bool? hintUsed,
    String? questionId,
    String? questionInstanceId,
    String questionSource = 'validated_catalog',
    String questionVersion = 'flutter-catalog-v1',
    String? generationModel,
    String mappingVersion = 'unspecified',
    String curriculumVersion = 'flutter-catalog-v1',
    String? interventionType,
    String? feedbackType,
    String? skillIdOverride,
    bool syncAfter = true,
  }) async {
    final responseTimeMs = DateTime.now()
        .difference(exerciseStartedAt)
        .inMilliseconds
        .clamp(0, 3600000)
        .toInt();
    await progressReady;
    final store = progressStore;
    if (store == null) return null;
    String? submissionId;
    try {
      submissionId = await store.record(
        exerciseId: eventExerciseId ?? exercise.id,
        skillId: skillIdOverride ?? exercise.skillId,
        exerciseType: exerciseType ?? exercise.exerciseType,
        correct: correct,
        attemptNumber: attemptNumber ?? lessonAttempts[exercise.id] ?? 1,
        hintUsed: hintUsed ?? hintedLessonQuestions.contains(exercise.id),
        responseTimeMs: responseTimeMs,
        learnerId: activeAccount?.learnerId,
        language: selectedLanguage.storageName,
        assessmentKey: assessmentKey,
        lessonId: lessonId,
        questionText: questionText,
        options: options,
        learningObjective: learningObjective,
        difficulty: difficulty,
        expectedResponse: expectedResponse,
        submittedResponse: submittedResponse,
        questionId: questionId,
        questionInstanceId: questionInstanceId,
        questionSource: questionSource,
        questionVersion: questionVersion,
        generationModel: generationModel,
        mappingVersion: mappingVersion,
        curriculumVersion: curriculumVersion,
        interventionType: interventionType,
        feedbackType: feedbackType,
      );
      _emitDemoEvent(
        'practice_attempt_completed',
        payload: {
          'exercise_type': exerciseType ?? exercise.exerciseType,
          'correct': correct,
          'attempt_number': attemptNumber ?? lessonAttempts[exercise.id] ?? 1,
        },
      );
      if (assessmentKey != null) {
        _emitDemoEvent(
          'assessment_answer_checked',
          payload: {'correct': correct},
        );
        _emitDemoEvent(
          'assessment_feedback_generated',
          payload: {'correct': correct},
        );
      }
      if (correct) {
        _emitDemoEvent(
          'exercise_completed',
          payload: {'exercise_type': exerciseType ?? exercise.exerciseType},
        );
      }
      await _saveCurrentResume();
      await _refreshLearningHistory(store);
    } catch (_) {
      // Keep the learning flow responsive; local persistence is best effort.
    }
    if (syncAfter) unawaited(_syncPendingProgress(knownStore: store));
    return submissionId;
  }

  Future<void> _refreshLearningHistory(LessonProgressStore store) async {
    try {
      final history = await store.readEvents();
      _learningHistory = List<JsonMap>.from(history);
      if (mounted) setState(() {});
    } catch (_) {
      // Recommendation ordering remains on its previous safe snapshot.
    }
  }

  Future<void> _syncPendingProgress({LessonProgressStore? knownStore}) async {
    final store = knownStore ?? progressStore;
    if (store == null) return;
    await store.syncPending(accountStore: widget.accountStorage);
    await _refreshAdaptiveDecisionState(applyPending: true);
  }

  Future<void> _refreshAdaptiveDecisionState({
    bool applyPending = false,
  }) async {
    final store = progressStore;
    if (store == null) return;
    final pending = await store.pendingAdaptiveDecision(
      languageCode: selectedLanguage.code,
    );
    final latest = await store.latestAdaptiveDecision(
      languageCode: selectedLanguage.code,
    );
    if (!mounted) return;
    setState(() {
      _activeAdaptiveDecision = pending;
      _latestAdaptiveDecision = latest;
    });
    if (applyPending &&
        pending != null &&
        onboardingComplete &&
        !guidedPractice &&
        !lessonAssessment &&
        !wordAssessment &&
        !_applyingAdaptiveDecision) {
      await _applyAdaptiveDecision(pending, announce: true);
    }
  }

  Future<void> configureAudio() async {
    try {
      await tts.awaitSpeakCompletion(true);
      await tts.setLanguage(selectedLanguage.ttsLocale);
      await tts.setSpeechRate(0.45);
      await tts.setVolume(1.0);
    } catch (_) {}
  }

  void _clearCourseSwipe(PointerEvent event) {
    if (event.pointer == _courseSwipePointer) {
      _courseSwipePointer = null;
      _courseSwipeStart = null;
    }
  }

  void _handleCourseSwipeEnd(PointerEvent event) {
    if (event.pointer != _courseSwipePointer || _courseSwipeStart == null) {
      return;
    }
    final distance = event.position.dy - _courseSwipeStart!.dy;
    _clearCourseSwipe(event);
    if (page != 2 || chapter != 1 || guidedPractice || lessonAssessment) {
      return;
    }
    if (_adaptiveRequirementActive) {
      unawaited(speak(_adaptiveRequirementMessage));
      return;
    }
    if (distance < -48) {
      unawaited(_advanceCourseFromSwipe());
    } else if (distance > 48) {
      unawaited(speak(_lessonExplanation()));
    }
  }

  Future<void> openVoiceTutor({
    bool physicalActivation = false,
    bool startListening = true,
  }) async {
    _emitDemoEvent(
      'tutor_activated',
      payload: {
        'activation': physicalActivation ? 'volume_shortcut' : 'app_control',
      },
    );
    if (_activeTutorController != null) {
      if (physicalActivation) {
        await speak(
          'Resonant Tutor is ready. Press volume up to start speaking.',
        );
      } else if (startListening) {
        await _activeTutorController!.startListening();
      }
      return;
    }
    final currentWord =
        wordChapterScreenKey.currentState?.currentWordForTutor ??
        LessonCatalog.wordLessons[wordChapterLessonIndex].words.first;
    var lessonContext =
        selectedLanguage == AppLanguage.english && page == 2 && chapter == 2
        ? '${currentChapter.title}. ${LessonCatalog.wordLessons[wordChapterLessonIndex].title}. Current word: $currentWord. The learner is studying verified uncontracted English word cells.'
        : page == 2
        ? '${currentChapter.title}. Current exercise: ${currentExercise.prompt}. Skill: ${currentExercise.skillId}.'
        : 'Current section: ${pages[page]}. The learner is studying six-dot Braille.';
    final lessonExamples = <VerifiedBrailleExample>[];
    if (selectedLanguage == AppLanguage.english && page == 2 && chapter == 2) {
      final word = currentWord;
      lessonExamples.add(
        VerifiedBrailleExample(word, EnglishGrade1Engine.encode(word)),
      );
      lessonContext +=
          ' A deterministic engine has verified the whole word and its capital indicators.';
    } else if (page == 2) {
      final exampleText = _currentLessonExampleText();
      if (exampleText != null) {
        final cells = BrailleDispatcher.encodeToBitmasks(
          exampleText,
          selectedLanguage,
        );
        lessonExamples.add(VerifiedBrailleExample(exampleText, cells));
        lessonContext +=
            ' A deterministic engine has verified the current simple-letter example.';
      }
    }
    if (audioEnabled) await tts.stop();
    if (!mounted) return;
    var closeTutorAfterAction = false;
    final tutorLanguageAtOpen = selectedLanguage;
    late final VoiceTutorController controller;
    controller = createVoiceTutorController(
      tts: tts,
      speech: voiceSpeech,
      lessonContext: lessonContext,
      language: selectedLanguage.storageName,
      locale: voiceAssessmentSettings.recognitionLocaleFor(
        selectedLanguage.speechRecognitionLocale,
      ),
      listenTimeout: Duration(seconds: voiceAssessmentSettings.timeoutSeconds),
      lessonExamples: lessonExamples,
      screenContextProvider: () => tutorScreenContext,
      audioEnabled: audioEnabled,
      contextualCommandHandler: (question, recentTurns) async {
        final languageBeforeAction = selectedLanguage;
        final answer = await handleVoiceCommand(
          question,
          recentTurns: recentTurns,
        );
        closeTutorAfterAction = selectedLanguage != languageBeforeAction;
        if (answer != null) lastSpokenInstruction = answer;
        return answer;
      },
      onLocalCommandComplete: () async {
        if (closeTutorAfterAction &&
            selectedLanguage != tutorLanguageAtOpen &&
            mounted &&
            Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        if (!closeTutorAfterAction &&
            voiceAssessmentSettings.enabled &&
            voiceAssessmentSettings.autoRelisten &&
            (lessonAssessment || wordAssessment || cumulativeAssessment) &&
            identical(_activeTutorController, controller)) {
          unawaited(controller.startListening());
        }
      },
      onStatusAnnouncement: speak,
      onDemoEvent: (type, payload) => _emitDemoEvent(type, payload: payload),
    );
    _activeTutorController = controller;
    if (physicalActivation) {
      await _setPhysicalTutorActive(true);
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => VoiceTutorPanel(
          controller: controller,
          hapticsEnabled: hapticsEnabled,
          startListeningOnOpen: !physicalActivation && startListening,
        ),
      ).whenComplete(() async {
        if (identical(_activeTutorController, controller)) {
          _activeTutorController = null;
          _physicalTutorMode = false;
          await _setPhysicalTutorActive(false);
        }
      }),
    );
    if (physicalActivation) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted && identical(_activeTutorController, controller)) {
        await speak(
          'Resonant Tutor is ready. Press volume up to start speaking.',
        );
      }
    }
  }

  String? _currentLessonExampleText() {
    if (currentExercise.isComposedResponse) return currentExerciseAnswer;
    if (chapter == 1) {
      return selectedLanguage == AppLanguage.english
          ? currentExercise.answer.toLowerCase()
          : currentExercise.answer;
    }
    if (selectedLanguage == AppLanguage.english && chapter == 2) {
      return wordChapterScreenKey.currentState?.currentWordForTutor ??
          LessonCatalog.wordLessons[wordChapterLessonIndex].words.first;
    }
    return null;
  }

  Future<void> speak(String text) async {
    lastSpokenInstruction = text;
    final screenReaderActive =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    if (screenReaderActive) {
      SemanticsService.announce(text, Directionality.of(context));
      return;
    }
    if (audioEnabled) {
      try {
        await tts.stop();
        _emitDemoEvent(
          'tts_started',
          payload: {'response_kind': 'application_guidance'},
        );
        await tts.speak(text);
        _emitDemoEvent(
          'tts_completed',
          payload: {'response_kind': 'application_guidance'},
        );
      } catch (_) {}
    }
  }

  Future<String> _applyNavigationResolution(
    NavigationResolution resolution,
  ) async {
    if (!resolution.isResolved) return resolution.message;
    if (lessonAssessment || wordAssessment || cumulativeAssessment) {
      _emitDemoEvent(
        'assessment_abandoned',
        payload: {
          'recorded_as_complete': false,
          'reason': 'explicit_navigation',
        },
      );
    }
    _emitDemoEvent(
      'navigation_requested',
      payload: {
        'destination_chapter': resolution.chapterIndex,
        'destination_lesson': resolution.lessonIndex,
      },
    );
    final targetChapter = resolution.chapterIndex ?? chapter;
    final targetLesson = resolution.lessonIndex ?? 0;
    final targetWordChapter = resolution.wordChapterIndex;
    final existingWordScreen = wordChapterScreenKey.currentState;

    setState(() {
      page = 2;
      chapter = targetChapter;
      lessonItem = targetLesson;
      exerciseStartedAt = DateTime.now();
      selectedLessonAnswer = null;
      lessonFeedback = null;
      lessonAnswerCorrect = false;
      lessonTaught = false;
      guidedPractice = false;
      lessonAssessment = false;
      wordAssessment = false;
      assessmentCells.clear();
      if (targetWordChapter != null) {
        wordChapterLessonIndex = targetWordChapter;
      }
      if (selectedLanguage != AppLanguage.english && chapter == 0) {
        _vernacularIntroStep = 0;
      }
    });

    if (targetWordChapter != null && existingWordScreen != null) {
      existingWordScreen.goToLesson(targetWordChapter, announce: false);
    }
    await _saveCurrentResume();
    _emitDemoEvent(
      'navigation_completed',
      payload: {'chapter': chapter + 1, 'lesson_number': lessonItem + 1},
    );
    _emitDemoEvent(
      'lesson_opened',
      payload: {
        'lesson': currentExercise.answer.isEmpty
            ? currentChapter.title
            : currentExercise.answer,
      },
    );
    feedback();
    return resolution.message;
  }

  Future<String> _startCurrentSkillAssessment() async {
    if (wordAssessment) return _startWordAssessmentFromTutor();
    if (selectedLanguage == AppLanguage.english && chapter == 2) {
      return _startWordAssessmentFromTutor();
    }
    if (currentExercise.isComposedResponse) {
      _startComposedWritingPractice();
      return 'Starting the verified ${currentExercise.exerciseType.replaceAll('_', ' ')}. ${_compositionInstruction()}';
    }
    if (chapter != 1) {
      return 'Open a character lesson before starting a skill assessment.';
    }

    setState(() {
      lessonAssessmentAttempts[currentExercise.id] = 0;
      lessonTaught = true;
      guidedPractice = false;
      lessonAssessment = true;
      page = 2;
      lessonFeedback = null;
      lessonAnswerCorrect = false;
      selectedLessonAnswer = null;
      exerciseStartedAt = DateTime.now();
      assessmentCells.clear();
    });
    final target = currentExercise.answer.toUpperCase();
    return 'Starting the verified assessment for $target. ${currentExercise.prompt}';
  }

  Future<String> _startWordAssessmentFromTutor() async {
    if (wordAssessment) {
      setState(() {
        page = 1;
        lessonAssessment = false;
        assessmentCells.clear();
        lessonFeedback = null;
        exerciseStartedAt = DateTime.now();
      });
      return 'Starting the current word assessment. Write $assessmentWord, one Braille cell at a time.';
    }

    if (selectedLanguage == AppLanguage.english) {
      final stage = latestEligibleEnglishStage;
      if (stage != null && !completedWordStages.contains(stage.id)) {
        final nextWord = _nextRecommendedWordIndex(stage.id, stage.words);
        setState(() {
          chapter = 1;
          lessonItem = stage.last;
          cumulativeAssessment = false;
          lessonAssessment = false;
          wordAssessment = true;
          assessmentWordIndex = nextWord < stage.words.length ? nextWord : 0;
          assessmentWord = stage.words[assessmentWordIndex];
          assessmentCells.clear();
          _wordRemediationVisited.remove(stage.id);
          wordAssessmentAttempts = 0;
          lessonFeedback = null;
          page = 1;
          exerciseStartedAt = DateTime.now();
        });
        await _saveCurrentResume();
        return 'Starting the ${stage.title} word assessment. Write $assessmentWord, one Braille cell at a time.';
      }
      if (wordMasteryAssessmentAvailable) {
        return _applyNavigationResolution(
          const NavigationResolution(
            status: NavigationResolutionStatus.resolved,
            message: 'English Words, Chapter 5. Word mastery test.',
            chapterIndex: 2,
            wordChapterIndex: 4,
          ),
        );
      }
    } else if (vernacularWordAssessmentAvailable &&
        !completedWordStages.contains('${selectedLanguage.code}-word-test')) {
      final words = activeChapters[2].exercises
          .map((exercise) => exercise.answer)
          .toList();
      setState(() {
        chapter = 1;
        lessonItem = activeChapters[1].exercises.length - 1;
        wordAssessment = true;
        lessonAssessment = false;
        cumulativeAssessment = false;
        assessmentWordIndex = 0;
        assessmentWord = words.first;
        assessmentCells.clear();
        _wordRemediationVisited.remove('${selectedLanguage.code}-word-test');
        wordAssessmentAttempts = 0;
        lessonFeedback = null;
        page = 1;
        exerciseStartedAt = DateTime.now();
      });
      await _saveCurrentResume();
      return 'Starting the ${selectedLanguage.storageName} word assessment. Write $assessmentWord one cell at a time.';
    }

    return 'A validated word assessment is not eligible yet. Complete the prerequisite lessons first.';
  }

  Future<String> _openWordLearningFromTutor(String assessmentReason) async {
    if (activeChapters.length <= 2) {
      return 'The word assessment is not available in ${selectedLanguage.storageName} yet. $assessmentReason';
    }
    final resolution = NavigationResolution(
      status: NavigationResolutionStatus.resolved,
      message:
          '${activeChapters[2].title}. ${activeChapters[2].exercises.isEmpty ? '' : activeChapters[2].exercises.first.prompt}',
      chapterIndex: 2,
      lessonIndex: 0,
      wordChapterIndex: selectedLanguage == AppLanguage.english ? 0 : null,
    );
    await _applyNavigationResolution(resolution);
    _emitDemoEvent(
      'navigation_completed',
      payload: {
        'activity': 'word_learning',
        'reason': 'assessment_prerequisite',
      },
    );
    return 'The word assessment is not unlocked yet. $assessmentReason I opened ${activeChapters[2].title} so you can continue learning words.';
  }

  Future<String> _startComposedAssessmentFromTutor(String target) async {
    final wantsSentence = target.toLowerCase().contains('sentence');
    final targetChapter = wantsSentence ? 4 : 3;
    if (targetChapter >= activeChapters.length) {
      return 'This language does not have a validated $target assessment.';
    }
    if (!_chapterPrerequisitesComplete(targetChapter)) {
      return wantsSentence
          ? 'Complete word mastery and both verified phrase exercises before starting sentence writing.'
          : 'Complete the validated word assessment before starting phrase writing.';
    }
    final exercises = activeChapters[targetChapter].exercises;
    final next = exercises.indexWhere(
      (exercise) => !completedLessonQuestions.contains(exercise.id),
    );
    setState(() {
      chapter = targetChapter;
      lessonItem = next < 0 ? 0 : next;
      page = 2;
      lessonTaught = true;
      guidedPractice = false;
      lessonAssessment = false;
      wordAssessment = false;
      lessonFeedback = null;
      lessonAnswerCorrect = false;
      assessmentCells.clear();
      exerciseStartedAt = DateTime.now();
    });
    _startComposedWritingPractice();
    return 'Starting verified ${wantsSentence ? 'sentence' : 'phrase'} writing. ${_compositionInstruction()}';
  }

  ({int chapter, int lesson})? _findExerciseLocation(String exerciseId) {
    for (
      var chapterIndex = 0;
      chapterIndex < activeChapters.length;
      chapterIndex++
    ) {
      final exercises = activeChapters[chapterIndex].exercises;
      for (
        var exerciseIndex = 0;
        exerciseIndex < exercises.length;
        exerciseIndex++
      ) {
        if (exercises[exerciseIndex].id == exerciseId) {
          return (chapter: chapterIndex, lesson: exerciseIndex);
        }
      }
    }
    return null;
  }

  Future<String> _openExerciseActivity(
    ({int chapter, int lesson}) location, {
    required String prefix,
    bool beginPractice = false,
  }) async {
    final targetExercise =
        activeChapters[location.chapter].exercises[location.lesson];
    final startsBraillePractice =
        beginPractice &&
        (location.chapter == 1 || targetExercise.isComposedResponse);
    setState(() {
      chapter = location.chapter;
      lessonItem = location.lesson;
      page = startsBraillePractice ? 1 : 2;
      lessonTaught = startsBraillePractice;
      guidedPractice = startsBraillePractice;
      lessonAssessment = false;
      wordAssessment = false;
      lessonFeedback = null;
      selectedLessonAnswer = null;
      exerciseStartedAt = DateTime.now();
      assessmentCells.clear();
    });
    await _saveCurrentResume();

    if (targetExercise.isComposedResponse && startsBraillePractice) {
      return '$prefix ${targetExercise.prompt} ${_compositionInstruction()}';
    }
    if (startsBraillePractice) {
      return '$prefix ${currentExercise.answer.toUpperCase()}. Enter its verified Braille pattern.';
    }
    return '$prefix ${currentExercise.prompt}';
  }

  Future<String> _startTargetedPracticeFromTutor() async {
    final adaptive = _activeAdaptiveDecision;
    if (adaptive != null && adaptive.requiresLearningAction) {
      await _applyAdaptiveDecision(adaptive, announce: false);
      return 'Starting the assigned ${adaptive.action.name} for ${adaptive.recommendedLessonId}. ${adaptive.reason}';
    }
    final candidates =
        lessonAttempts.entries.where((entry) => entry.value > 1).toList()
          ..sort((left, right) => right.value.compareTo(left.value));
    for (final candidate in candidates) {
      final location = _findExerciseLocation(candidate.key);
      if (location != null) {
        return _openExerciseActivity(
          location,
          prefix: 'Starting targeted practice for',
          beginPractice: true,
        );
      }
    }
    return 'No repeated-error skill is available for targeted practice yet.';
  }

  Future<String> _startRevisionFromTutor(String? target) async {
    await progressReady;
    final events = await progressStore?.readEvents() ?? const <JsonMap>[];
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    for (final event in events.reversed) {
      if (event['outcome'] != 'correct') continue;
      if (target == 'yesterday') {
        final createdAt = DateTime.tryParse(
          '${event['created_at']}',
        )?.toLocal();
        if (createdAt == null ||
            createdAt.year != yesterday.year ||
            createdAt.month != yesterday.month ||
            createdAt.day != yesterday.day) {
          continue;
        }
      }
      final location = _findExerciseLocation('${event['exercise_id']}');
      if (location != null) {
        return _openExerciseActivity(location, prefix: 'Starting revision for');
      }
    }

    for (final exerciseId in completedLessonQuestions.toList().reversed) {
      final location = _findExerciseLocation(exerciseId);
      if (location != null && target != 'yesterday') {
        return _openExerciseActivity(location, prefix: 'Starting revision for');
      }
    }
    return target == 'yesterday'
        ? 'No completed lesson from yesterday is available on this device.'
        : 'Complete at least one lesson before starting revision.';
  }

  String _skillMasterySummary(String? target) {
    LessonExercise exercise = currentExercise;
    if (target != null && target.trim().isNotEmpty) {
      final query = target.toLowerCase().trim();
      final match = activeChapters
          .expand((chapter) => chapter.exercises)
          .where(
            (item) =>
                item.id.toLowerCase().contains(query) ||
                item.answer.toLowerCase() == query,
          )
          .firstOrNull;
      if (match != null) exercise = match;
    }
    final attempts = lessonAttempts[exercise.id] ?? 0;
    final complete = completedLessonQuestions.contains(exercise.id);
    return complete
        ? '${exercise.answer.toUpperCase()} is complete locally after $attempts ${attempts == 1 ? 'attempt' : 'attempts'}. Server mastery is available after progress sync.'
        : '${exercise.answer.toUpperCase()} is not complete yet. It has $attempts recorded ${attempts == 1 ? 'attempt' : 'attempts'} on this device.';
  }

  String _recommendationSummary() {
    final decision = _activeAdaptiveDecision ?? _latestAdaptiveDecision;
    if (decision != null) {
      return '${decision.learnerActivityMessage} ${decision.learnerModelStatusMessage}';
    }
    if (_wordProgressionComplete || validatedWordTestAvailable) {
      final candidates = selectedLanguage == AppLanguage.english
          ? LessonCatalog.wordLessons[wordChapterLessonIndex].words
          : activeChapters[2].exercises
                .map((exercise) => exercise.answer)
                .toList();
      final recommendation = _wordRecommendation(candidates);
      if (recommendation.rankedWords.isNotEmpty) {
        return '${recommendation.reason} Recommended verified word: ${recommendation.rankedWords.first}.';
      }
    }
    for (
      var chapterIndex = 0;
      chapterIndex < activeChapters.length;
      chapterIndex++
    ) {
      if (selectedLanguage == AppLanguage.english &&
          chapterIndex == 2 &&
          !courseComplete) {
        continue;
      }
      if (!_chapterPrerequisitesComplete(chapterIndex)) continue;
      for (final exercise in activeChapters[chapterIndex].exercises) {
        if (!completedLessonQuestions.contains(exercise.id)) {
          return 'Recommended next lesson: ${exercise.prompt} This is the first incomplete prerequisite-safe lesson in ${selectedLanguage.storageName}.';
        }
      }
    }
    return 'All current ${selectedLanguage.storageName} lesson exercises are complete. Review a difficult skill or start an eligible assessment.';
  }

  String _adaptiveDecisionExplanation() {
    final decision = _activeAdaptiveDecision ?? _latestAdaptiveDecision;
    if (decision == null) {
      return 'There is no recorded adaptive decision to explain yet.';
    }
    final accuracy = decision.evidence['accuracy'];
    final attempts =
        decision.evidence['attempt_number'] ??
        decision.evidence['repeated_attempts'];
    final repeated =
        decision.evidence['repeated_dot_confusion'] ??
        decision.evidence['repeated_error_count'];
    final evidence = <String>[
      if (accuracy != null) 'accuracy $accuracy',
      if (attempts != null) 'attempt evidence $attempts',
      if (repeated != null) 'repeated error evidence $repeated',
    ].join(', ');
    return 'The system selected ${decision.recommendedLessonId} to ${decision.action.name}. ${decision.reason}'
        '${evidence.isEmpty ? '' : ' Recorded evidence: $evidence.'} ${decision.learnerModelStatusMessage}';
  }

  String? _resolveSpokenLessonOption(String? spoken) {
    final activeOptions = tutorScreenContext.options;
    final index = TutorOptionResolver.resolveIndex(activeOptions, spoken);
    return index == null ? null : activeOptions[index];
  }

  String _explainSpokenOption(String? target) {
    final options = tutorScreenContext.options;
    if (target == null || target.isEmpty || options.isEmpty) {
      return 'There is no answer option to explain on this screen.';
    }
    final index = TutorOptionResolver.resolveIndex(options, target);
    if (index == null) {
      return 'I could not identify that option. Please say its letter.';
    }
    return 'Option ${String.fromCharCode(65 + index)} says: ${options[index]}.';
  }

  String _explainCurrentTutorContent() {
    if (page != 1 && page != 2) {
      final screen = tutorScreenContext;
      return 'You are on ${screen.screenName}. ${screen.readInstructions()}';
    }
    if (page == 2 && selectedLanguage == AppLanguage.english && chapter == 2) {
      return wordChapterScreenKey.currentState?.repeatQuestionFromTutor() ??
          'The current word activity is not ready yet.';
    }
    if (lessonAssessment && _lessonQuestionPrompt.isNotEmpty) {
      return 'This question asks: $_lessonQuestionPrompt. I can explain the task, but I will not reveal the assessment answer. Ask for a hint if you need help.';
    }
    return '${currentExercise.prompt} ${currentExercise.explanation}';
  }

  String _moveExerciseFromTutor(int direction) {
    if (page == 1) {
      if (wordAssessment) {
        return 'The word test advances after the current word is checked. Say exit assessment if you want to leave without completing it.';
      }
      final previousPage = page;
      final previousChapter = chapter;
      final previousLesson = lessonItem;
      moveLessonItem(direction, announce: false, allowIncomplete: true);
      if (page == previousPage &&
          chapter == previousChapter &&
          lessonItem == previousLesson) {
        return direction > 0
            ? 'You have reached the last exercise in this section.'
            : 'You are at the first exercise in this section.';
      }
      _emitDemoEvent(
        'navigation_completed',
        payload: {
          'direction': direction > 0 ? 'next' : 'previous',
          'lesson_number': lessonItem + 1,
        },
      );
      return direction > 0
          ? 'Next exercise. ${currentExercise.prompt}'
          : 'Previous exercise. ${currentExercise.prompt}';
    }
    if (page != 2) {
      return 'Exercise navigation is available while a lesson or word activity is open.';
    }
    if (page == 2 && selectedLanguage == AppLanguage.english && chapter == 2) {
      final screen = wordChapterScreenKey.currentState;
      final previousWord = screen?.currentWordForTutor;
      final result =
          screen?.moveWordFromTutor(direction) ??
          'The word activity is not ready yet.';
      if (screen?.currentWordForTutor != previousWord) {
        _emitDemoEvent(
          'navigation_completed',
          payload: {
            'direction': direction > 0 ? 'next' : 'previous',
            'activity': 'word_chapter',
          },
        );
      }
      return result;
    }
    if (wordAssessment) {
      return 'The word test advances only after a correct Braille answer. Say exit assessment to leave without completing it.';
    }
    final previousPage = page;
    final previousChapter = chapter;
    final previousLesson = lessonItem;
    final nextLesson = lessonItem + direction;
    if (nextLesson < 0 || nextLesson >= currentChapter.exercises.length) {
      return direction > 0
          ? 'You have reached the last exercise in this section.'
          : 'You are at the first exercise in this section.';
    }
    if (lessonAssessment || cumulativeAssessment) {
      _emitDemoEvent(
        'assessment_abandoned',
        payload: {
          'recorded_as_complete': false,
          'reason': 'next_exercise_navigation',
        },
      );
    }
    moveLessonItem(direction, announce: false, allowIncomplete: true);
    if (page == previousPage &&
        chapter == previousChapter &&
        lessonItem == previousLesson) {
      return 'I could not move to another exercise from this screen.';
    }
    _emitDemoEvent(
      'navigation_completed',
      payload: {
        'direction': direction > 0 ? 'next' : 'previous',
        'lesson_number': lessonItem + 1,
      },
    );
    _emitDemoEvent(
      'lesson_opened',
      payload: {
        'lesson': currentExercise.answer.isEmpty
            ? currentChapter.title
            : currentExercise.answer,
      },
    );
    return direction > 0
        ? 'Next exercise. ${currentExercise.prompt}'
        : 'Previous exercise. ${currentExercise.prompt}';
  }

  Future<String?> handleVoiceCommand(
    String input, {
    List<TutorMessage> recentTurns = const [],
  }) async {
    if (input.trim().isEmpty) return null;
    ParsedVoiceCommand? parsed;
    var interpretedByModel = false;
    var resolvedAsAssessmentControl = false;
    final screen = tutorScreenContext;
    final structuredContext = screen.toIntentContext();
    final allowedActions = screen.availableIntentActions;
    final assessmentCommand = AssessmentVoiceCommandResolver.resolve(
      utterance: input,
      assessmentActive:
          page == 2 &&
          lessonAssessment &&
          !wordAssessment &&
          !currentExercise.isComposedResponse,
      options: screen.options,
    );
    if (assessmentCommand != null) {
      parsed = assessmentCommand;
      resolvedAsAssessmentControl = true;
      _emitDemoEvent(
        'tutor_intent_interpretation_started',
        payload: {
          'method': 'deterministic_assessment_control',
          'input_text': input,
          'context': structuredContext,
        },
      );
      _emitDemoEvent(
        'tutor_intent_interpreted',
        payload: {
          'method': 'deterministic_assessment_control',
          'intent': assessmentCommand.command.name,
          if (assessmentCommand.target != null)
            'target': assessmentCommand.target,
          'outcome': 'candidate_action',
          'context': structuredContext,
        },
      );
    }
    if (assessmentCommand == null) {
      _emitDemoEvent(
        'tutor_intent_interpretation_started',
        payload: {
          'method': 'ollama_structured_tool_selection',
          'input_text': input,
          'context': structuredContext,
          'available_actions': allowedActions,
          'history_turn_count': recentTurns.length,
        },
      );
      try {
        final interpretation = await tutorIntentInterpreter.interpret(
          utterance: input,
          language: selectedLanguage.storageName,
          screenContext: structuredContext,
          recentTurns: recentTurns
              .where((turn) => turn.role == 'user' || turn.role == 'assistant')
              .toList(growable: false)
              .reversed
              .take(6)
              .toList(growable: false)
              .reversed
              .map(
                (turn) => {
                  'role': turn.role,
                  'content': turn.text.length > 500
                      ? turn.text.substring(0, 500)
                      : turn.text,
                },
              )
              .toList(growable: false),
          availableActions: allowedActions,
        );
        if (interpretation.clarification != null) {
          _emitDemoEvent(
            'tutor_intent_interpreted',
            payload: {
              'method': 'ollama_structured_tool_selection',
              'intent': 'clarify',
              'confidence': interpretation.confidence,
              'outcome': 'clarification_required',
              'context': structuredContext,
              'clarification': interpretation.clarification,
            },
          );
          return interpretation.clarification;
        }
        if (interpretation.isTutorQuestion) {
          _emitDemoEvent(
            'tutor_intent_interpreted',
            payload: {
              'method': 'ollama_structured_tool_selection',
              'intent': 'ask_tutor',
              'confidence': interpretation.confidence,
              'outcome': 'conversation',
              'context': structuredContext,
            },
          );
          return null;
        }
        parsed = interpretation.command;
        interpretedByModel = parsed != null;
        if (parsed != null) {
          _emitDemoEvent(
            'tutor_intent_interpreted',
            payload: {
              'method': 'ollama_structured_tool_selection',
              'proposed_action': {
                'name': parsed.command.name,
                if (parsed.target != null) 'target': parsed.target,
                if (parsed.letter != null) 'letter': parsed.letter,
                if (parsed.languageCode != null)
                  'language': parsed.languageCode,
                if (parsed.difficulty != null) 'difficulty': parsed.difficulty,
              },
              'confidence': interpretation.confidence,
              'evidence_summary': interpretation.reasoningSummary,
              'outcome': 'candidate_action',
              'context': structuredContext,
            },
          );
        }
      } catch (error) {
        debugPrint(
          'Tutor intent interpretation failed (${error.runtimeType}); using offline command fallback.',
        );
        _emitDemoEvent(
          'tutor_intent_interpretation_failed',
          payload: {
            'method': 'ollama_structured_tool_selection',
            'outcome': 'deterministic_fallback',
            'context': structuredContext,
          },
        );
      }
    }

    // The parser is a local availability fallback only. Normal online requests
    // are interpreted semantically against the current screen and tool catalog.
    parsed ??= VoiceCommandParser.parse(input);
    if (parsed == null &&
        page == 2 &&
        lessonAssessment &&
        !wordAssessment &&
        !currentExercise.isComposedResponse &&
        _lessonQuestionOptions.isNotEmpty) {
      final option = _resolveSpokenLessonOption(input);
      if (option != null) {
        parsed = ParsedVoiceCommand(VoiceCommand.selectAnswer, target: option);
      }
    }
    if (parsed == null &&
        page == 2 &&
        selectedLanguage == AppLanguage.english &&
        chapter == 2) {
      final option = wordChapterScreenKey.currentState?.spokenChoiceForTutor(
        input,
      );
      if (option != null) {
        parsed = ParsedVoiceCommand(VoiceCommand.selectAnswer, target: option);
      }
    }
    if (parsed == null) return null;
    if (!interpretedByModel && !resolvedAsAssessmentControl) {
      _emitDemoEvent(
        'tutor_command_parsed',
        payload: {
          'method': 'deterministic_offline_fallback',
          'command': parsed.command.name,
          if (parsed.letter != null) 'target_character': parsed.letter,
        },
      );
    }
    var actionContext = tutorActionContext;
    final navigationLanguage = switch (parsed.languageCode) {
      'english' => AppLanguage.english,
      'hindi' => AppLanguage.hindi,
      'kannada' => AppLanguage.kannada,
      _ => selectedLanguage,
    };
    if (navigationLanguage != selectedLanguage &&
        const {
          VoiceCommand.goToChapter,
          VoiceCommand.goToLesson,
        }.contains(parsed.command)) {
      actionContext = actionContext.withNavigation(
        LearningNavigationContext(
          language: navigationLanguage,
          chapterIndex: 0,
          lessonIndex: 0,
          wordChapterIndex: 0,
          englishLetterCourseComplete: false,
        ),
      );
    }
    final action = tutorActionController.resolve(parsed, actionContext);
    _emitDemoEvent(
      'tutor_action_validated',
      payload: {
        'command': parsed.command.name,
        'result': action.isReady ? 'allowed' : 'blocked',
      },
    );
    if (!action.isReady) {
      final requestedWordAssessment =
          parsed.command == VoiceCommand.startWordTest ||
          parsed.command == VoiceCommand.startModuleTest ||
          (parsed.command == VoiceCommand.startSkillTest &&
              (parsed.target?.toLowerCase().contains('word') ?? false));
      if (requestedWordAssessment && !actionContext.wordTestAvailable) {
        final result = await _openWordLearningFromTutor(action.message);
        _emitDemoEvent(
          'tutor_action_execution_completed',
          payload: {
            'command': parsed.command.name,
            'result': 'word_learning_opened_prerequisite_not_met',
          },
        );
        return result;
      }
      return action.message;
    }
    switch (parsed.command) {
      case VoiceCommand.startLearning:
        if (!onboardingComplete) {
          return 'Please complete Lesson 1 first. Your progress is saved so you can resume it.';
        }
        continueLearning(announce: false);
        return 'Opening your next lesson.';
      case VoiceCommand.resumeLearning:
        setState(() => learningPaused = false);
        if (!onboardingComplete) {
          return 'Please complete Lesson 1 first. Your progress is saved so you can resume it.';
        }
        continueLearning(announce: false);
        return 'Learning resumed. Opening your next lesson.';
      case VoiceCommand.pauseLearning:
        setState(() => learningPaused = true);
        await tts.stop();
        return 'Learning paused. Your current place is saved. Say resume learning when you are ready.';
      case VoiceCommand.teachLetter:
        if (!onboardingComplete) {
          return 'Please complete Lesson 1 first. Your progress is saved so you can resume it.';
        }
        final taughtLetter = parsed.letter;
        if (taughtLetter == null) {
          return 'Which letter would you like to learn?';
        }
        final hasIndicTarget = RegExp(
          r'[\u0900-\u097f\u0c80-\u0cff]',
        ).hasMatch(taughtLetter);
        final targetLanguage = parsed.languageCode == null
            ? hasIndicTarget
                  ? selectedLanguage
                  : AppLanguage.english
            : AppLanguage.fromCode(parsed.languageCode);
        if (targetLanguage != selectedLanguage) {
          await switchLanguage(targetLanguage, announce: false);
        }
        final targetChapter = activeChapters.indexWhere(
          (chapter) => chapter.exercises.any(
            (exercise) => exercise.answer.toUpperCase() == taughtLetter,
          ),
        );
        if (targetChapter < 0) {
          return 'The letter $taughtLetter is not available in the selected language lessons.';
        }
        final index = activeChapters[targetChapter].exercises.indexWhere(
          (exercise) => exercise.answer.toUpperCase() == taughtLetter,
        );
        setState(() {
          page = 2;
          chapter = targetChapter;
          lessonItem = index;
          lessonTaught = false;
          guidedPractice = false;
          lessonAssessment = false;
          wordAssessment = false;
          lessonFeedback = null;
        });
        unawaited(_saveCurrentResume());
        feedback();
        return 'Opening the lesson for letter $taughtLetter.';
      case VoiceCommand.repeat:
        return page == 2
            ? tutorScreenContext.question ?? currentExercise.prompt
            : tutorScreenContext.readInstructions();
      case VoiceCommand.readScreen:
        return tutorScreenContext.readScreen();
      case VoiceCommand.readQuestion:
        return tutorScreenContext.readQuestion();
      case VoiceCommand.readOptions:
        return tutorScreenContext.readOptions();
      case VoiceCommand.readInstructions:
        return tutorScreenContext.readInstructions();
      case VoiceCommand.readFeedback:
        return tutorScreenContext.readFeedback();
      case VoiceCommand.whatExercise:
        return tutorScreenContext.exerciseStatus();
      case VoiceCommand.explainCurrentContent:
        return _explainCurrentTutorContent();
      case VoiceCommand.explainOption:
        return _explainSpokenOption(parsed.target);
      case VoiceCommand.repeatQuestion:
        if (page == 2 &&
            selectedLanguage == AppLanguage.english &&
            chapter == 2) {
          return wordChapterScreenKey.currentState?.repeatQuestionFromTutor() ??
              'The word activity is not ready yet.';
        }
        if (wordAssessment) {
          return 'Current word assessment. Write $assessmentWord, one Braille cell at a time.';
        }
        if (page == 2 && lessonAssessment) {
          final choices = _lessonQuestionOptions
              .asMap()
              .entries
              .map(
                (entry) =>
                    'Option ${String.fromCharCode(65 + entry.key)}: ${entry.value}',
              )
              .join('. ');
          return choices.isEmpty
              ? _lessonQuestionPrompt
              : '$_lessonQuestionPrompt. $choices';
        }
        return currentExercise.prompt;
      case VoiceCommand.repeatLesson:
        if (selectedLanguage == AppLanguage.english && chapter == 2) {
          wordChapterScreenKey.currentState?.goToLesson(
            wordChapterLessonIndex,
            announce: false,
          );
          return 'Restarting ${LessonCatalog.wordLessons[wordChapterLessonIndex].title}. Your completed progress is preserved.';
        }
        setState(() {
          page = 2;
          lessonTaught = false;
          guidedPractice = false;
          wordAssessment = false;
          lessonFeedback = null;
          selectedLessonAnswer = null;
          assessmentCells.clear();
          exerciseStartedAt = DateTime.now();
        });
        return 'Restarting this lesson. Your completed progress is preserved.';
      case VoiceCommand.explainDots:
        return 'A Braille cell has two columns and three rows. Dot 1 is upper left, 2 middle left, 3 lower left; dot 4 is upper right, 5 middle right, and 6 lower right.';
      case VoiceCommand.startPractice:
        if (page == 2 && wordAssessment) {
          setState(() {
            assessmentCells.clear();
            page = 1;
          });
          return 'Starting the word test. Write $assessmentWord, one Braille cell at a time.';
        }
        if (page == 2 && currentExercise.isComposedResponse) {
          _startComposedWritingPractice();
          return _compositionInstruction();
        }
        if (page != 2 || chapter != 1 || !lessonTaught) {
          return 'On the letter lesson, swipe up to hear the verified explanation, then swipe up again to enter the Braille keyboard.';
        }
        final bitmask = BrailleDispatcher.encodeToBitmasks(
          selectedLanguage == AppLanguage.english
              ? currentExercise.answer.toLowerCase()
              : currentExercise.answer,
          selectedLanguage,
        ).first;
        final dots = _dotsFromCell(bitmask);
        setState(() {
          guidedPractice = true;
          page = 1;
          lessonFeedback = null;
          lessonAnswerCorrect = false;
        });
        feedback();
        return 'Starting practice for ${currentExercise.answer.toUpperCase()}. Enter dots $dots, then choose Check pattern.';
      case VoiceCommand.startTargetedPractice:
        return _startTargetedPracticeFromTutor();
      case VoiceCommand.startRemediation:
        return _startTargetedPracticeFromTutor();
      case VoiceCommand.explainAdaptiveSelection:
        return _adaptiveDecisionExplanation();
      case VoiceCommand.selectAnswer:
        if (page == 2 &&
            selectedLanguage == AppLanguage.english &&
            chapter == 2) {
          final result =
              await wordChapterScreenKey.currentState?.chooseSpokenAnswer(
                parsed.target,
              ) ??
              'The word activity is not ready for an answer yet.';
          _emitDemoEvent(
            'assessment_option_selected',
            payload: {'activity': 'word_choice'},
          );
          return result;
        }
        if (page != 2 ||
            !lessonAssessment ||
            wordAssessment ||
            currentExercise.isComposedResponse) {
          return 'There is no selectable answer on the current activity.';
        }
        final option = _resolveSpokenLessonOption(parsed.target);
        if (option == null) {
          return 'That answer is not one of the available choices. Say answer followed by the choice or its number.';
        }
        setState(() {
          selectedLessonAnswer = option;
          lessonFeedback = null;
          lessonAnswerCorrect = false;
        });
        feedback();
        final optionIndex = _lessonQuestionOptions.indexOf(option);
        _emitDemoEvent(
          'tutor_action_execution_completed',
          payload: {
            'command': parsed.command.name,
            'result': 'answer_selected',
            'option_index': optionIndex + 1,
          },
        );
        _emitDemoEvent(
          'assessment_option_selected',
          payload: {'option_index': optionIndex + 1},
        );
        final nextStep =
            voiceAssessmentSettings.enabled &&
                voiceAssessmentSettings.autoRelisten
            ? 'I will listen for your next command.'
            : 'Activate the tutor again and say check answer.';
        return voiceAssessmentSettings.confirmSelection
            ? 'Selected option ${String.fromCharCode(65 + optionIndex)}: $option. $nextStep If this answer is correct, I will continue to the next activity.'
            : 'Option selected. $nextStep If this answer is correct, I will continue to the next activity.';
      case VoiceCommand.checkAnswer:
        if (page == 2 &&
            selectedLanguage == AppLanguage.english &&
            chapter == 2) {
          final result =
              await wordChapterScreenKey.currentState?.checkAnswerFromTutor() ??
              'The word activity is not ready yet.';
          return result;
        }
        if (page == 2 &&
            lessonAssessment &&
            !wordAssessment &&
            !currentExercise.isComposedResponse) {
          if (selectedLessonAnswer == null) {
            return 'Choose an answer first. Say answer followed by the choice or its number.';
          }
          if (_lastTutorSubmittedExerciseId == currentExercise.id &&
              _lastTutorSubmittedAnswer == selectedLessonAnswer) {
            return lessonFeedback ?? 'That answer was already checked.';
          }
          final submit = submitLessonAnswer();
          final result = lessonFeedback ?? 'Answer submitted.';
          await submit;
          _lastTutorSubmittedExerciseId = currentExercise.id;
          _lastTutorSubmittedAnswer = selectedLessonAnswer;
          _emitDemoEvent(
            'assessment_answer_checked',
            payload: {
              'result': lessonAnswerCorrect ? 'correct' : 'incorrect',
              'recorded': true,
            },
          );
          return result;
        }
        if (page != 1) {
          return 'Start guided dot practice first. Then say check my answer.';
        }
        return submitVoicePattern();
      case VoiceCommand.repeatWord:
        if (page == 2 &&
            selectedLanguage == AppLanguage.english &&
            chapter == 2) {
          final currentWord =
              wordChapterScreenKey.currentState?.currentWordForTutor;
          return currentWord == null
              ? 'The word activity is not ready yet.'
              : 'The word is $currentWord.';
        }
        return wordAssessment
            ? assessmentWord
            : 'There is no active word test. Say continue learning to resume your course.';
      case VoiceCommand.clearPattern:
        brailleKeyboardKey.currentState?.clearPattern();
        return 'Current Braille cell cleared.';
      case VoiceCommand.giveHint:
        if (lessonAssessment || wordAssessment) {
          return 'You are still on the current assessment question. '
              'I will not reveal its answer or change your progress. '
              'Take a breath and use the Braille patterns you have practised.';
        }
        if (page == 2 &&
            selectedLanguage == AppLanguage.english &&
            chapter == 2) {
          _emitDemoEvent(
            'hint_requested',
            payload: {'activity': 'word_chapter'},
          );
          return wordChapterScreenKey.currentState?.requestHintFromTutor() ??
              'The word activity is not ready for a hint yet.';
        }
        if (page == 1 && !wordAssessment && !lessonAssessment) {
          hintedLessonQuestions.add(currentExercise.id);
          _emitDemoEvent(
            'hint_requested',
            payload: {'activity': 'braille_practice'},
          );
          final explanation = _lessonExplanation();
          return selectedLanguage == AppLanguage.english
              ? explanation
              : '$explanation ${currentExercise.hint}';
        }
        if (page == 2 && !wordAssessment) {
          hintedLessonQuestions.add(currentExercise.id);
          _emitDemoEvent('hint_requested', payload: {'activity': 'lesson'});
          return currentExercise.hint;
        }
        return 'Try recalling the Braille patterns from the letters you learned.';
      case VoiceCommand.showProgress:
        setState(() => page = 4);
        final mastered = completedLessonQuestions.length;
        return 'You have completed $mastered exercises and passed ${completedWordStages.length} word tests.';
      case VoiceCommand.getSkillMastery:
        return _skillMasterySummary(parsed.target);
      case VoiceCommand.getRecommendation:
        return _recommendationSummary();
      case VoiceCommand.reviewDifficult:
        return _startTargetedPracticeFromTutor();
      case VoiceCommand.openSettings:
        setState(() => page = 3);
        return 'Accessibility settings.';
      case VoiceCommand.startTest:
      case VoiceCommand.startAssessment:
        return _startCurrentSkillAssessment();
      case VoiceCommand.startWordTest:
        final result = await _startWordAssessmentFromTutor();
        _emitDemoEvent(
          'tutor_action_execution_completed',
          payload: {
            'command': parsed.command.name,
            'result': wordAssessment ? 'word_assessment_opened' : 'not_started',
          },
        );
        return result;
      case VoiceCommand.startSkillTest:
        if (parsed.target?.toLowerCase().contains('word') ?? false) {
          return _startWordAssessmentFromTutor();
        }
        if (parsed.target?.toLowerCase().contains('sentence') ?? false) {
          return _startComposedAssessmentFromTutor('sentence');
        }
        if (parsed.target?.toLowerCase().contains('phrase') ?? false) {
          return _startComposedAssessmentFromTutor('phrase');
        }
        return _startCurrentSkillAssessment();
      case VoiceCommand.startModuleTest:
        final result = await _startWordAssessmentFromTutor();
        _emitDemoEvent(
          'tutor_action_execution_completed',
          payload: {
            'command': parsed.command.name,
            'result': wordAssessment ? 'word_assessment_opened' : 'not_started',
          },
        );
        return result;
      case VoiceCommand.startRevision:
        return _startRevisionFromTutor(parsed.target);
      case VoiceCommand.changeDifficulty:
        return action.message;
      case VoiceCommand.nextLesson:
        return _moveExerciseFromTutor(1);
      case VoiceCommand.previousExercise:
        return _moveExerciseFromTutor(-1);
      case VoiceCommand.nextChapter:
      case VoiceCommand.previousChapter:
      case VoiceCommand.goToChapter:
      case VoiceCommand.goToLesson:
      case VoiceCommand.moduleBeginning:
        if (navigationLanguage != selectedLanguage &&
            (parsed.command == VoiceCommand.goToChapter ||
                parsed.command == VoiceCommand.goToLesson)) {
          await switchLanguage(navigationLanguage, announce: false);
        }
        return _applyNavigationResolution(action.navigation!);
      case VoiceCommand.goBack:
        setState(() {
          if (page == 1) {
            page = 2;
            if (!wordAssessment) {
              guidedPractice = false;
              lessonTaught = true;
            }
          } else if (page != 0) {
            page = 0;
          }
        });
        feedback();
        return page == 0 ? 'Home.' : 'Back to the lesson.';
      case VoiceCommand.exitAssessment:
        if (!(lessonAssessment || wordAssessment || cumulativeAssessment)) {
          return 'There is no assessment open to exit.';
        }
        setState(() {
          lessonAssessment = false;
          wordAssessment = false;
          cumulativeAssessment = false;
          page = 2;
          guidedPractice = false;
          lessonFeedback = null;
          selectedLessonAnswer = null;
        });
        await _saveCurrentResume();
        feedback();
        _emitDemoEvent(
          'assessment_abandoned',
          payload: {'recorded_as_complete': false},
        );
        return 'Assessment closed. It was not recorded as completed.';
      case VoiceCommand.openLessonMenu:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) openLessonNavigator(allowActiveActivity: true);
        });
        return 'Opening the lesson list.';
      case VoiceCommand.home:
        if (lessonAssessment || wordAssessment || cumulativeAssessment) {
          _emitDemoEvent(
            'assessment_abandoned',
            payload: {'recorded_as_complete': false, 'reason': 'go_home'},
          );
          setState(() {
            lessonAssessment = false;
            wordAssessment = false;
            cumulativeAssessment = false;
          });
        }
        setState(() => page = 0);
        _emitDemoEvent(
          'navigation_completed',
          payload: {'screen': 'Dashboard'},
        );
        feedback();
        return 'Your learning screen is ready.';
      case VoiceCommand.openTutor:
        return 'You are already talking to Resonant.';
      case VoiceCommand.stopSpeaking:
        return 'Swipe down in the tutor status area to interrupt my spoken reply.';
      case VoiceCommand.switchLanguage:
        final language = switch (action.languageCode) {
          'hindi' => AppLanguage.hindi,
          'kannada' => AppLanguage.kannada,
          _ => AppLanguage.english,
        };
        if (language == selectedLanguage) {
          return 'You are already learning in ${language.storageName}.';
        }
        await switchLanguage(language, announce: false);
        if (selectedLanguage != language) {
          return 'I could not change the learning language. Your current activity is still open.';
        }
        _emitDemoEvent(
          'tutor_action_execution_completed',
          payload: {
            'command': parsed.command.name,
            'result': 'language_changed',
          },
        );
        return switch (language) {
          AppLanguage.english =>
            'Language switched to English. ${currentChapter.title}. ${currentExercise.prompt}',
          AppLanguage.hindi =>
            'भाषा हिंदी में बदल गई है। ${currentChapter.title}। ${currentExercise.prompt}',
          AppLanguage.kannada =>
            'ಭಾಷೆಯನ್ನು ಕನ್ನಡಕ್ಕೆ ಬದಲಿಸಲಾಗಿದೆ. ${currentChapter.title}. ${currentExercise.prompt}',
        };
      case VoiceCommand.help:
        setState(() => page = 5);
        feedback();
        return 'Help is open.';
    }
  }

  void feedback() {
    if (hapticsEnabled) {
      HapticFeedback.vibrate();
    }
  }

  Future<void> _switchRole() async {
    await _saveCurrentResume();
    await _activeTutorController?.clearConversation();
    await voiceSpeech.stop();
    await tts.stop();
    if (!mounted) return;
    await _setPhysicalTutorActive(false);
    widget.onSwitchRole?.call();
  }

  void navigateTo(int newPage) {
    if (newPage < 0 || newPage >= pages.length) {
      return;
    }

    setState(() {
      final cameFromPractice = page == 1;
      page = newPage;
      if (newPage == 2 && chapter == 0) chapter = 1;
      if (newPage == 2 && cameFromPractice) {
        if (!wordAssessment) {
          guidedPractice = false;
          lessonTaught = true;
        }
      }
    });

    _emitDemoEvent('navigation_completed', payload: {'screen': pages[newPage]});
    feedback();
    speak(pages[newPage]);
  }

  void navigateByTwoFingerSwipe(int direction) {
    if (direction == 0 ||
        !mounted ||
        page == 1 ||
        guidedPractice ||
        lessonAssessment ||
        wordAssessment ||
        _adaptiveRequirementActive) {
      return;
    }
    if (page == 2) {
      if (selectedLanguage == AppLanguage.english && chapter == 2) {
        wordChapterScreenKey.currentState?.moveWord(direction);
        return;
      }
      moveLessonItem(direction);
      return;
    }
    const sections = [0, 2, 4, 5, 3];
    final current = sections.indexOf(page);
    final target = current + direction;
    if (target < 0 || target >= sections.length) {
      speak(
        direction > 0
            ? 'You are at the last section.'
            : 'You are at the first section.',
      );
      return;
    }
    navigateTo(sections[target]);
  }

  void _navigateLessonByTwoFingerSwipe(int direction) {
    if (page == 2 &&
        chapter == 0 &&
        selectedLanguage != AppLanguage.english &&
        !lessonTaught) {
      _navigateIntroduction(direction);
      return;
    }
    navigateByTwoFingerSwipe(direction);
  }

  Future<void> _navigateWordChapterByGesture(int direction) async {
    final resolution = direction > 0
        ? tutorActionController.navigationController.nextChapter(
            navigationContext,
          )
        : tutorActionController.navigationController.previousChapter(
            navigationContext,
          );
    final message = await _applyNavigationResolution(resolution);
    await speak(message);
  }

  void nextChapter(int direction) {
    if (_adaptiveRequirementActive) {
      speak(
        'Complete the assigned remediation and reassessment before changing chapters. ${_activeAdaptiveDecision!.reason}',
      );
      return;
    }
    if (lessonAssessment || wordAssessment) {
      speak(
        'Complete or leave the current assessment before changing chapters.',
      );
      return;
    }
    final next = chapter + direction;

    if (selectedLanguage == AppLanguage.english &&
        next == 2 &&
        !courseComplete) {
      speak(
        'Complete the English letter course before starting the word chapter.',
      );
      return;
    }
    if (next >= 3 && !_wordProgressionComplete) {
      speak(
        selectedLanguage == AppLanguage.english
            ? 'Complete English word mastery before opening phrase and sentence writing.'
            : 'Complete the ${selectedLanguage.storageName} word assessment before opening phrase and sentence writing.',
      );
      return;
    }
    if (next >= 4 && !_phraseProgressionComplete) {
      speak(
        'Complete the verified phrase exercises before opening sentence writing.',
      );
      return;
    }

    if (next < 0 || next >= activeChapters.length) {
      speak(
        direction > 0
            ? 'You have reached the last chapter.'
            : 'You are at the first chapter.',
      );
      return;
    }

    setState(() {
      chapter = next;
      lessonItem = 0;
      exerciseStartedAt = DateTime.now();
      selectedLessonAnswer = null;
      lessonFeedback = null;
      lessonAnswerCorrect = false;
      lessonTaught = false;
      guidedPractice = false;
      lessonAssessment = false;
      wordAssessment = false;
      assessmentCells.clear();
      if (selectedLanguage == AppLanguage.english && next == 2) {
        _selectWordChapterResumePoint();
      }
    });

    unawaited(_saveCurrentResume());
    _emitDemoEvent(
      'lesson_opened',
      payload: {
        'lesson_number': lessonItem + 1,
        'activity': currentExercise.exerciseType,
      },
    );
    feedback();
    speak(currentChapter.title);
  }

  void moveLessonItem(
    int direction, {
    bool announce = true,
    bool allowIncomplete = false,
  }) {
    if (!allowIncomplete && _adaptiveRequirementActive) {
      if (announce) {
        speak(
          'Complete the assigned remediation and reassessment before moving on. ${_activeAdaptiveDecision!.reason}',
        );
      }
      return;
    }
    if (!allowIncomplete && lessonAssessment) {
      if (announce) {
        speak('Complete the current lesson assessment before moving on.');
      }
      return;
    }
    if (!allowIncomplete &&
        direction > 0 &&
        (chapter == 1 || currentExercise.isComposedResponse) &&
        !completedLessonQuestions.contains(currentExercise.id)) {
      if (announce) {
        speak(
          'Complete the current lesson and verified assessment before moving to the next item.',
        );
      }
      return;
    }
    final next = lessonItem + direction;

    if (next < 0 || next >= currentChapter.exercises.length) {
      if (announce) {
        speak(
          direction > 0
              ? 'You have reached the last item in this chapter.'
              : 'You are at the first item in this chapter.',
        );
      }
      return;
    }

    setState(() {
      lessonItem = next;
      page = 2;
      exerciseStartedAt = DateTime.now();
      selectedLessonAnswer = null;
      lessonFeedback = null;
      lessonAnswerCorrect = false;
      lessonTaught = false;
      guidedPractice = false;
      lessonAssessment = false;
    });

    unawaited(_saveCurrentResume());
    feedback();
    if (announce) {
      speak(
        selectedLanguage != AppLanguage.english
            ? currentExercise.prompt
            : chapter == 1
            ? 'Next, learn letter ${currentExercise.answer.toUpperCase()}.'
            : currentExercise.prompt,
      );
    }
  }

  Future<void> submitLessonAnswer() async {
    final answer = selectedLessonAnswer;
    if (answer == null ||
        lessonAnswerCorrect ||
        (lessonAssessment &&
            _processingLessonAssessmentId == currentExercise.id)) {
      return;
    }

    final exercise = currentExercise;
    final adaptiveQuestion = _currentAdaptivePracticeQuestion;
    final correct = adaptiveQuestion == null
        ? exercise.isCorrect(answer)
        : answer == adaptiveQuestion.answer;
    final assessmentAttempt = lessonAssessment;
    setState(() {
      lessonAttempts.update(
        exercise.id,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (assessmentAttempt) {
        lessonAssessmentAttempts.update(
          exercise.id,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      lessonAnswerCorrect = correct;
      lessonFeedback = correct
          ? 'Correct. ${exercise.explanation}'
          : 'Not quite. Try again, or ask for a hint.';
      if (correct) completedLessonQuestions.add(exercise.id);
    });
    feedback();
    if (assessmentAttempt) {
      _processingLessonAssessmentId = exercise.id;
      try {
        await _handleLessonAssessmentResult(
          exercise,
          answer,
          correct,
          adaptiveQuestion: adaptiveQuestion,
        );
      } finally {
        if (_processingLessonAssessmentId == exercise.id) {
          _processingLessonAssessmentId = null;
        }
      }
      return;
    }
    speak(lessonFeedback!);
    await persistLessonAttempt(exercise, correct);
  }

  Future<void> _handleLessonAssessmentResult(
    LessonExercise exercise,
    String? submittedAnswer,
    bool correct, {
    AdaptivePracticeQuestion? adaptiveQuestion,
    String? expectedAnswerOverride,
    List<int>? expectedCellsOverride,
    List<int>? submittedCellsOverride,
    String? exerciseTypeOverride,
    bool cellOnlyResponse = false,
  }) async {
    final expectedAnswer =
        expectedAnswerOverride ?? adaptiveQuestion?.answer ?? exercise.answer;
    final expectedCells =
        expectedCellsOverride ??
        adaptiveQuestion?.expectedCells ??
        BrailleDispatcher.encodeToBitmasks(expectedAnswer, selectedLanguage);
    final submittedCells =
        submittedCellsOverride ??
        BrailleDispatcher.encodeToBitmasks(
          submittedAnswer ?? '',
          selectedLanguage,
        );
    final difficulty =
        adaptiveQuestion?.difficulty ??
        (chapter == 1 && selectedLanguage == AppLanguage.english
            ? LessonCatalog.curriculum.indexOf(currentCurriculumStage) + 1
            : exercise.difficulty);
    final assessmentAttemptNumber = lessonAssessmentAttempts[exercise.id] ?? 1;
    final previousDecision = _activeAdaptiveDecision;
    final isReassessment =
        previousDecision != null &&
        previousDecision.isActive &&
        (previousDecision.requiresLearningAction ||
            previousDecision.nextQuestion != null) &&
        (previousDecision.skillId == exercise.skillId ||
            previousDecision.recommendedLessonId == exercise.id);
    final submissionId = await persistLessonAttempt(
      exercise,
      correct,
      eventExerciseId: 'lesson-assessment-${exercise.id}',
      exerciseType: exerciseTypeOverride ?? 'quiz',
      assessmentKey: '${selectedLanguage.code}-${exercise.id}-v1',
      lessonId: exercise.id,
      questionText: adaptiveQuestion?.questionText ?? exercise.prompt,
      options: cellOnlyResponse
          ? const []
          : adaptiveQuestion?.options ?? exercise.options,
      learningObjective: exercise.explanation,
      difficulty: difficulty,
      expectedResponse: {
        cellOnlyResponse ? 'text' : 'choice': expectedAnswer,
        'cells': expectedCells,
      },
      submittedResponse: {
        if (!cellOnlyResponse && submittedAnswer != null)
          'choice': submittedAnswer,
        'cells': submittedCells,
      },
      attemptNumber: assessmentAttemptNumber,
      questionId: adaptiveQuestion?.questionId,
      questionInstanceId: adaptiveQuestion?.questionInstanceId,
      questionSource: adaptiveQuestion?.source ?? 'validated_catalog',
      questionVersion:
          adaptiveQuestion?.questionVersion ?? exercise.contentVersion,
      generationModel: adaptiveQuestion?.generationModel,
      mappingVersion:
          adaptiveQuestion?.mappingVersion ?? exercise.mappingVersion,
      curriculumVersion:
          adaptiveQuestion?.curriculumVersion ?? exercise.contentVersion,
      interventionType: isReassessment ? previousDecision.action.name : null,
      feedbackType: correct ? 'verified_correct' : 'corrective_feedback',
      syncAfter: false,
    );
    unawaited(speak(lessonFeedback!));
    final store = progressStore;
    if (isReassessment) {
      final completed = await store?.markAdaptiveDecisionCompleted(
        previousDecision.decisionId,
        succeeded: correct,
      );
      if (mounted) {
        setState(() {
          _latestAdaptiveDecision =
              completed ?? previousDecision.markCompleted(succeeded: correct);
          _activeAdaptiveDecision = null;
        });
      }
    }

    final history = await store?.readEvents() ?? const <JsonMap>[];
    final completedCycles =
        await store?.completedRemediationCycles(exercise.skillId) ?? 0;
    final cappedReassessmentFailed =
        await store?.hasFailedCappedReassessment(exercise.skillId) ?? false;
    final previousExercise = lessonItem > 0
        ? currentChapter.exercises[lessonItem - 1]
        : null;
    final prerequisiteSatisfied =
        previousExercise == null ||
        completedLessonQuestions.contains(previousExercise.id);
    final offlineDecision = adaptiveDecisionController.deriveOffline(
      AdaptiveAssessmentSnapshot(
        submissionId:
            submissionId ?? 'volatile-${DateTime.now().microsecondsSinceEpoch}',
        assessmentKey: '${selectedLanguage.code}-${exercise.id}-v1',
        languageCode: selectedLanguage.code,
        lessonId: exercise.id,
        skillId: exercise.skillId,
        correct: correct,
        attemptNumber: assessmentAttemptNumber,
        hintUsed: hintedLessonQuestions.contains(exercise.id),
        expectedCells: expectedCells,
        submittedCells: submittedCells,
        prerequisiteSatisfied: prerequisiteSatisfied,
        prerequisiteLessonId: previousExercise?.id,
        learningObjective: exercise.explanation,
        remediationCycles: isReassessment
            ? previousDecision.remediationCycle
            : completedCycles,
        isReassessment: isReassessment,
        history: history,
      ),
    );
    if (!correct &&
        offlineDecision.action == AdaptiveDecisionAction.reassess &&
        (cappedReassessmentFailed ||
            previousDecision?.action == AdaptiveDecisionAction.reassess)) {
      final terminalDecision = offlineDecision.markCompleted(succeeded: false);
      final saved =
          await store?.saveAdaptiveDecision(terminalDecision) ??
          terminalDecision;
      if (mounted) {
        setState(() {
          _activeAdaptiveDecision = null;
          _latestAdaptiveDecision = saved;
          lessonAssessment = true;
          lessonAnswerCorrect = false;
        });
        await speak(
          '${saved.reason} Automatic reassignment is paused to prevent a loop. You may retry this supported assessment or ask the tutor why this lesson was selected.',
        );
      }
      if (store != null) unawaited(_syncPendingProgress(knownStore: store));
      return;
    }
    final offlineSaved =
        await store?.saveAdaptiveDecision(offlineDecision) ?? offlineDecision;
    final backendDecision = submissionId == null || store == null
        ? null
        : await store.syncAssessmentDecision(
            submissionId: submissionId,
            accountStore: widget.accountStorage,
            timeout: const Duration(milliseconds: 1500),
          );
    final decision = backendDecision ?? offlineSaved;
    if (!mounted) return;
    await _applyAdaptiveDecision(decision, announce: true);
    if (store != null) {
      unawaited(_syncPendingProgress(knownStore: store));
    }
  }

  Future<void> _applyAdaptiveDecision(
    AdaptiveDecision decision, {
    required bool announce,
  }) {
    final task = _adaptiveDecisionApplications
        .catchError((_) {})
        .then((_) => _applyAdaptiveDecisionNow(decision, announce: announce));
    _adaptiveDecisionApplications = task;
    return task;
  }

  Future<void> _applyAdaptiveDecisionNow(
    AdaptiveDecision decision, {
    required bool announce,
  }) async {
    final resolution = adaptiveDecisionController.resolve(
      decision: decision,
      languageCode: selectedLanguage.code,
      chapters: activeChapters,
      currentChapterIndex: chapter,
      currentLessonIndex: lessonItem,
      completedExerciseIds: completedLessonQuestions,
    );
    if (!resolution.isReady) {
      if (announce) unawaited(speak(resolution.message));
      return;
    }

    _applyingAdaptiveDecision = true;
    try {
      final resolved =
          await progressStore?.saveAdaptiveDecision(resolution.decision) ??
          resolution.decision;
      if (!resolved.isActive) {
        if (announce) {
          unawaited(speak('This adaptive action was already handled.'));
        }
        return;
      }
      switch (resolved.action) {
        case AdaptiveDecisionAction.remediate:
        case AdaptiveDecisionAction.reinforce:
          final applied = await progressStore?.markAdaptiveDecisionApplied(
            resolved.decisionId,
          );
          final active = applied ?? resolved.markApplied();
          if (!mounted) return;
          setState(() {
            _activeAdaptiveDecision = active;
            _latestAdaptiveDecision = active;
          });
          final location = (
            chapter: resolution.chapterIndex ?? chapter,
            lesson: resolution.lessonIndex ?? lessonItem,
          );
          final opening = await _openExerciseActivity(
            location,
            prefix: resolved.action == AdaptiveDecisionAction.remediate
                ? 'Starting required remediation for'
                : 'Starting reinforcement for',
            beginPractice: true,
          );
          if (announce) {
            unawaited(
              speak(
                '${resolved.reason} ${currentExercise.explanation} $opening Practice is followed automatically by reassessment.',
              ),
            );
          }
          break;
        case AdaptiveDecisionAction.reassess:
          final applied = await progressStore?.markAdaptiveDecisionApplied(
            resolved.decisionId,
          );
          final active = applied ?? resolved.markApplied();
          if (!mounted) return;
          final targetChapter = resolution.chapterIndex ?? chapter;
          final targetLesson = resolution.lessonIndex ?? lessonItem;
          final composition = activeChapters[targetChapter]
              .exercises[targetLesson]
              .isComposedResponse;
          setState(() {
            _activeAdaptiveDecision = active;
            _latestAdaptiveDecision = active;
            chapter = targetChapter;
            lessonItem = targetLesson;
            lessonTaught = true;
            guidedPractice = composition;
            lessonAssessment = !composition;
            wordAssessment = false;
            page = composition ? 1 : 2;
            selectedLessonAnswer = null;
            lessonAnswerCorrect = false;
            lessonFeedback = null;
            assessmentCells.clear();
            exerciseStartedAt = DateTime.now();
            lessonAssessmentAttempts[currentExercise.id] = 0;
          });
          if (announce) {
            unawaited(
              speak(
                composition
                    ? '${resolved.reason} ${_compositionInstruction()}'
                    : '${resolved.reason} $_lessonQuestionPrompt',
              ),
            );
          }
          break;
        case AdaptiveDecisionAction.advance:
          final completed = await progressStore?.markAdaptiveDecisionCompleted(
            resolved.decisionId,
            succeeded: true,
          );
          if (!mounted) return;
          setState(() {
            _activeAdaptiveDecision = null;
            _latestAdaptiveDecision =
                completed ?? resolved.markCompleted(succeeded: true);
          });
          await _advanceAfterLessonAssessment(announce: announce);
          break;
        case AdaptiveDecisionAction.revise:
          if (resolved.nextQuestion != null) {
            final applied = await progressStore?.markAdaptiveDecisionApplied(
              resolved.decisionId,
            );
            final active = applied ?? resolved.markApplied();
            if (!mounted) return;
            setState(() {
              _activeAdaptiveDecision = active;
              _latestAdaptiveDecision = active;
              chapter = resolution.chapterIndex ?? chapter;
              lessonItem = resolution.lessonIndex ?? lessonItem;
              lessonTaught = true;
              guidedPractice = false;
              lessonAssessment = true;
              wordAssessment = false;
              page = 2;
              selectedLessonAnswer = null;
              lessonAnswerCorrect = false;
              lessonFeedback = null;
              assessmentCells.clear();
              exerciseStartedAt = DateTime.now();
              lessonAssessmentAttempts[currentExercise.id] = 0;
            });
            if (announce) {
              unawaited(
                speak(
                  '${resolved.learnerActivityMessage} $_lessonQuestionPrompt',
                ),
              );
            }
            break;
          }
          final location = (
            chapter: resolution.chapterIndex ?? chapter,
            lesson: resolution.lessonIndex ?? lessonItem,
          );
          final opening = await _openExerciseActivity(
            location,
            prefix: 'Starting spaced revision for',
          );
          final completed = await progressStore?.markAdaptiveDecisionCompleted(
            resolved.decisionId,
            succeeded: true,
          );
          if (!mounted) return;
          setState(() {
            _activeAdaptiveDecision = null;
            _latestAdaptiveDecision =
                completed ?? resolved.markCompleted(succeeded: true);
          });
          if (announce) unawaited(speak('${resolved.reason} $opening'));
          break;
      }
    } finally {
      _applyingAdaptiveDecision = false;
    }
  }

  Future<void> _advanceAfterLessonAssessment({required bool announce}) async {
    if (selectedLanguage == AppLanguage.english &&
        chapter == 1 &&
        lessonItem == currentCurriculumStage.last) {
      final stage = currentCurriculumStage;
      setState(() {
        lessonAssessment = false;
        wordAssessment = true;
        page = 2;
        guidedPractice = false;
        assessmentWordIndex = _nextRecommendedWordIndex(stage.id, stage.words);
        if (assessmentWordIndex >= stage.words.length) assessmentWordIndex = 0;
        assessmentWord = stage.words[assessmentWordIndex];
        cumulativeAssessment = false;
        assessmentCells.clear();
        selectedLessonAnswer = null;
        lessonAnswerCorrect = false;
        lessonFeedback = null;
      });
      if (announce) {
        unawaited(
          speak(
            'Lesson assessment complete. You finished ${stage.title}. The word assessment starts automatically with $assessmentWord.',
          ),
        );
      }
      return;
    }

    if (selectedLanguage != AppLanguage.english &&
        chapter == 1 &&
        lessonItem == currentChapter.exercises.length - 1) {
      setState(() {
        lessonAssessment = false;
        wordAssessment = true;
        assessmentWordIndex = 0;
        assessmentWord = currentAssessmentWords.first;
        assessmentCells.clear();
        page = 2;
        guidedPractice = false;
        selectedLessonAnswer = null;
        lessonAnswerCorrect = false;
        lessonFeedback = null;
      });
      if (announce) {
        unawaited(
          speak(
            'Lesson assessment complete. The ${selectedLanguage.storageName} word assessment starts automatically with $assessmentWord.',
          ),
        );
      }
      return;
    }

    if (currentExercise.isComposedResponse) {
      if (lessonItem + 1 < currentChapter.exercises.length) {
        setState(() => lessonAssessment = false);
        moveLessonItem(1, announce: false);
        if (announce) {
          unawaited(
            speak('Verified writing complete. Next: ${currentExercise.prompt}'),
          );
        }
        return;
      }
      final nextChapter = chapter + 1;
      if (nextChapter < activeChapters.length &&
          _chapterPrerequisitesComplete(nextChapter)) {
        setState(() {
          chapter = nextChapter;
          lessonItem = 0;
          page = 2;
          lessonTaught = false;
          guidedPractice = false;
          lessonAssessment = false;
          assessmentCells.clear();
          lessonFeedback = null;
          lessonAnswerCorrect = false;
          exerciseStartedAt = DateTime.now();
        });
        await _saveCurrentResume();
        if (announce) {
          unawaited(
            speak(
              'Chapter complete. Next: ${currentChapter.title}. ${currentExercise.prompt}',
            ),
          );
        }
        return;
      }
      if (announce) {
        unawaited(
          speak(
            'You completed the current verified ${selectedLanguage.storageName} writing chapter.',
          ),
        );
      }
      return;
    }

    setState(() => lessonAssessment = false);
    moveLessonItem(1, announce: false);
    if (announce) {
      unawaited(
        speak('Lesson assessment complete. Next: ${currentExercise.prompt}'),
      );
    }
  }

  void _startWordWritingPractice() {
    _startComposedWritingPractice();
  }

  void _startComposedWritingPractice() {
    setState(() {
      lessonTaught = true;
      guidedPractice = true;
      lessonAssessment = false;
      wordAssessment = false;
      assessmentCells.clear();
      lessonFeedback = null;
      lessonAnswerCorrect = false;
      page = 1;
      exerciseStartedAt = DateTime.now();
    });
    unawaited(speak(_compositionInstruction()));
  }

  String _compositionInstruction() {
    final target = currentExerciseAnswer;
    final count = currentExerciseCells.length;
    return switch (selectedLanguage) {
      AppLanguage.hindi =>
        '"$target" को $count ब्रेल सेल में लिखें। हर सेल के बाद जाँचें। खाली स्थान के लिए बिना बिंदु वाला सेल दर्ज करें।',
      AppLanguage.kannada =>
        '"$target" ಅನ್ನು $count ಬ್ರೈಲ್ ಕೋಶಗಳಲ್ಲಿ ಬರೆಯಿರಿ. ಪ್ರತಿ ಕೋಶದ ನಂತರ ಪರಿಶೀಲಿಸಿ. ಪದಗಳ ನಡುವಿನ ಜಾಗಕ್ಕೆ ಚುಕ್ಕೆಗಳಿಲ್ಲದ ಕೋಶವನ್ನು ನಮೂದಿಸಿ.',
      AppLanguage.english =>
        'Write "$target" in $count verified Braille cells. Check each cell in order. Submit a blank cell for each space.',
    };
  }

  String? get _brailleKeyboardStatus {
    if (guidedPractice && currentExercise.isComposedResponse) {
      return 'Response progress: ${assessmentCells.length} of ${currentExerciseCells.length} cells entered. ${lessonFeedback ?? ''}';
    }
    if (wordAssessment) {
      final expectedLength = WordAssessmentValidator.expectedCells(
        assessmentWord,
        selectedLanguage,
      ).length;
      return 'Word progress: ${assessmentCells.length} of $expectedLength cells entered. ${lessonFeedback ?? ''}';
    }
    return lessonFeedback;
  }

  String _wordCellErrorFeedback(
    WordAssessmentValidation validation, {
    List<Map<String, dynamic>> observations = const [],
  }) {
    final cell = (validation.firstDifferentCell ?? 0) + 1;
    final incorrect = observations
        .where((item) => item['correct'] != true)
        .firstOrNull;
    final targetLetter = incorrect?['character'];
    final letterPrefix = targetLetter is String
        ? 'The letter $targetLetter is incorrect. '
        : '';
    switch (validation.errorKind) {
      case BrailleCellErrorKind.missingDots:
        return '${letterPrefix}Cell $cell is missing dot${validation.missingDots.length == 1 ? '' : 's'} ${validation.missingDots.join(', ')}.';
      case BrailleCellErrorKind.extraDots:
        return '${letterPrefix}Cell $cell has extra dot${validation.extraDots.length == 1 ? '' : 's'} ${validation.extraDots.join(', ')}.';
      case BrailleCellErrorKind.mixedDots:
        return '${letterPrefix}Cell $cell has a different dot pattern.';
      case BrailleCellErrorKind.missingCell:
        return '${letterPrefix}The response is missing cell $cell.';
      case BrailleCellErrorKind.extraCell:
        return '${letterPrefix}The response has an extra cell at position $cell.';
      case null:
        return '${letterPrefix}The response did not match the verified word.';
    }
  }

  String? _alternativeWordForWeakEnglishLetter({
    required List<String> words,
    required String stageId,
    required int failedWordIndex,
    required int cellIndex,
  }) {
    if (cellIndex < 0 || cellIndex >= assessmentWord.length) return null;
    final completed = completedStageWords[stageId] ?? const <int>{};
    final visited = _wordRemediationVisited.putIfAbsent(stageId, () => <int>{});
    visited.add(failedWordIndex);
    final excludedWords = <String>{
      for (final index in completed) words[index].toLowerCase(),
      for (final index in visited) words[index].toLowerCase(),
    };
    final alternatives = WordAssessmentValidator.alternativeEnglishWords(
      failedWord: assessmentWord,
      cellIndex: cellIndex,
      candidates: words,
      excludedWords: excludedWords,
    );
    if (alternatives.isEmpty) return null;
    final recommended = _wordRecommendation(alternatives).rankedWords.first;
    return recommended == assessmentWord ? null : recommended;
  }

  void _backspaceAssessmentCell() {
    final keyboard = brailleKeyboardKey.currentState;
    if (keyboard != null && keyboard.selectedDots.isNotEmpty) {
      keyboard.clearPattern();
      return;
    }
    if (assessmentCells.isEmpty) {
      unawaited(speak('There is no earlier Braille cell to remove.'));
      return;
    }
    setState(() {
      assessmentCells.removeLast();
      lessonFeedback =
          'Previous cell removed. ${assessmentCells.length} cells remain in the response.';
      lessonAnswerCorrect = false;
    });
    feedback();
    unawaited(speak(lessonFeedback!));
  }

  void _resetAssessmentResponse() {
    setState(() {
      assessmentCells.clear();
      lessonFeedback = 'The complete Braille response was cleared.';
      lessonAnswerCorrect = false;
      exerciseStartedAt = DateTime.now();
    });
    brailleKeyboardKey.currentState?.clearPattern();
    feedback();
    unawaited(speak(lessonFeedback!));
  }

  void _submitComposedCell(int entered, {required bool announce}) {
    final exercise = currentExercise;
    if (_processingLessonAssessmentId == exercise.id) return;
    final target = currentExerciseAnswer;
    final expected = currentExerciseCells;
    assessmentCells.add(entered);
    brailleKeyboardKey.currentState?.clearPattern();
    if (assessmentCells.length < expected.length) {
      setState(() {
        lessonFeedback =
            'Cell ${assessmentCells.length} of ${expected.length} entered. Enter the next cell for $target.';
      });
      lastPatternFeedback = lessonFeedback!;
      if (announce) unawaited(speak(lastPatternFeedback));
      return;
    }

    final submitted = List<int>.from(assessmentCells);
    final correct = _sameCells(submitted, expected);
    lessonAttempts.update(exercise.id, (value) => value + 1, ifAbsent: () => 1);
    lessonAssessmentAttempts.update(
      exercise.id,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    if (correct) {
      completedLessonQuestions.add(exercise.id);
      feedback();
    } else if (hapticsEnabled) {
      HapticFeedback.vibrate();
    }
    setState(() {
      lessonAnswerCorrect = correct;
      lessonFeedback = correct
          ? 'Correct. You wrote the complete verified response: $target.'
          : 'That cell sequence does not match $target. The response was cleared so you can retry from the first cell.';
      guidedPractice = !correct;
      page = correct ? 2 : 1;
      if (!correct) {
        assessmentCells.clear();
        exerciseStartedAt = DateTime.now();
      }
    });
    lastPatternFeedback = lessonFeedback!;
    if (announce) unawaited(speak(lastPatternFeedback));
    _processingLessonAssessmentId = exercise.id;
    unawaited(
      _handleLessonAssessmentResult(
        exercise,
        null,
        correct,
        expectedAnswerOverride: target,
        expectedCellsOverride: expected,
        submittedCellsOverride: submitted,
        exerciseTypeOverride: exercise.exerciseType,
        cellOnlyResponse: true,
      ).whenComplete(() {
        if (_processingLessonAssessmentId == exercise.id) {
          _processingLessonAssessmentId = null;
        }
      }),
    );
  }

  Future<void> _submitWordRemediationCell(
    int entered, {
    required bool announce,
  }) async {
    final paused = _pausedWordAssessment;
    if (paused == null) return;
    final expected = currentExerciseCells;
    assessmentCells.add(entered);
    brailleKeyboardKey.currentState?.clearPattern();
    if (assessmentCells.length < expected.length) {
      setState(() {
        lessonFeedback =
            'Braille cell ${assessmentCells.length} of ${expected.length} entered for ${paused.letter}.';
      });
      if (announce) await speak(lessonFeedback!);
      return;
    }

    final submitted = List<int>.from(assessmentCells);
    final target = currentExerciseAnswer;
    final observations = WordAssessmentValidator.skillObservations(
      target: target,
      language: selectedLanguage,
      submittedCells: submitted,
    );
    final correct = _sameCells(submitted, expected);
    final updated = paused.copyWith(
      remediationAttempts: paused.remediationAttempts + 1,
    );
    _pausedWordAssessment = updated;
    setState(() {
      lessonAnswerCorrect = correct;
      lessonFeedback = correct
          ? 'Correct. You practised ${paused.letter} with the verified Braille pattern.'
          : 'That Braille pattern for ${paused.letter} is not correct yet. Hear the lesson hint and try again.';
      if (!correct) assessmentCells.clear();
    });
    feedback();
    final exercise = currentExercise;
    await persistLessonAttempt(
      exercise,
      correct,
      eventExerciseId:
          'word-remediation-${paused.assessmentSubmissionId}-${updated.remediationAttempts}',
      exerciseType: 'letter_writing',
      attemptNumber: updated.remediationAttempts,
      skillIdOverride: '${selectedLanguage.code}-word-remediation-attempt',
      expectedResponse: {'text': target, 'cells': expected},
      submittedResponse: {
        'cells': submitted,
        'skill_observations': observations,
        'remediation_for_submission_id': paused.assessmentSubmissionId,
        'remediation_status': correct ? 'completed' : 'in_progress',
      },
      interventionType: 'word_letter_remediation',
    );
    if (announce) await speak(lessonFeedback!);
    if (correct) {
      await _resumePausedWordAssessment();
    }
  }

  Future<void> checkGuidedPattern(
    String pattern, {
    bool announce = true,
  }) async {
    final entered = _cellFromPattern(pattern);
    if (guidedPractice && _pausedWordAssessment != null) {
      await _submitWordRemediationCell(entered, announce: announce);
      return;
    }
    if (guidedPractice && currentExercise.isComposedResponse) {
      _submitComposedCell(entered, announce: announce);
      return;
    }
    if (selectedLanguage != AppLanguage.english && wordAssessment) {
      final expected = WordAssessmentValidator.expectedCells(
        assessmentWord,
        selectedLanguage,
      );
      assessmentCells.add(entered);
      brailleKeyboardKey.currentState?.clearPattern();
      if (assessmentCells.length < expected.length) {
        setState(() {});
        lastPatternFeedback =
            'Cell ${assessmentCells.length} of ${expected.length}. Clear the keyboard and enter the next cell for $assessmentWord.';
        if (announce) speak(lastPatternFeedback);
        return;
      }
      final validation = WordAssessmentValidator.validate(
        target: assessmentWord,
        language: selectedLanguage,
        submittedCells: assessmentCells,
      );
      final correct = validation.isCorrect;
      final skillObservations = WordAssessmentValidator.skillObservations(
        target: assessmentWord,
        language: selectedLanguage,
        submittedCells: assessmentCells,
      );
      _emitDemoEvent(
        'braille_validation_completed',
        payload: {
          'language': selectedLanguage.storageName,
          'result': correct ? 'correct' : 'incorrect',
          'cell_count': expected.length,
          'dots': BrailleDispatcher.dotsForBitmask(entered).join(','),
        },
      );
      final submitted = List<int>.from(assessmentCells);
      wordAssessmentAttempts++;
      if (correct) {
        feedback();
      } else if (hapticsEnabled) {
        HapticFeedback.vibrate();
      }
      setState(() {
        lessonFeedback = correct
            ? 'Correct. You wrote $assessmentWord in Bharati Braille.'
            : '${_wordCellErrorFeedback(validation, observations: skillObservations)} Let us learn that letter, then continue the assessment.';
        lessonAnswerCorrect = correct;
        if (!correct) assessmentCells.clear();
      });
      lastPatternFeedback = lessonFeedback!;
      if (announce) speak(lastPatternFeedback);
      final failedSubmissionId = await persistWordAssessment(
        correct,
        assessmentStageId,
        assessmentWordIndex,
        submitted,
        targetWord: assessmentWord,
        language: selectedLanguage,
        validation: validation,
      );
      if (!correct &&
          await _beginWordLetterRemediation(
            submissionId: failedSubmissionId,
            stageId: assessmentStageId,
            wordIndex: assessmentWordIndex,
            word: assessmentWord,
            language: selectedLanguage,
            observations: skillObservations,
          )) {
        return;
      }
      if (correct) {
        final words = currentAssessmentWords;
        completedLessonQuestions.add(
          activeChapters[2].exercises[assessmentWordIndex].id,
        );
        completedStageWords
            .putIfAbsent(assessmentStageId, () => <int>{})
            .add(assessmentWordIndex);
        final next = _nextRecommendedWordIndex(assessmentStageId, words);
        if (next < words.length) {
          assessmentCells.clear();
          setState(() {
            assessmentWordIndex = next;
            assessmentWord = words[next];
            lessonAnswerCorrect = false;
            page = 2;
          });
          if (announce) speak('Correct. Next word: $assessmentWord.');
        } else {
          completedWordStages.add(assessmentStageId);
          setState(() {
            wordAssessment = false;
            courseComplete = true;
            chapter = 3;
            lessonItem = 0;
            lessonTaught = false;
            page = 2;
          });
          if (announce) {
            speak(
              'You completed the ${selectedLanguage.storageName} word test. Next: ${currentChapter.title}.',
            );
          }
        }
      }
      return;
    }
    if (selectedLanguage == AppLanguage.english && wordAssessment) {
      final stageWords = currentAssessmentWords;
      final isAllowed = cumulativeAssessment
          ? LessonCatalog.wordUsesOnly(
              assessmentWord,
              'abcdefghijklmnopqrstuvwxyz',
            )
          : currentCurriculumStage.allows(assessmentWord);
      if (!isAllowed) {
        lastPatternFeedback =
            'This test word contains a letter outside the taught set. I will not score it.';
        if (announce) speak(lastPatternFeedback);
        return;
      }
      assessmentCells.add(entered);
      brailleKeyboardKey.currentState?.clearPattern();
      if (assessmentCells.length < assessmentWord.length) {
        setState(() {});
        lastPatternFeedback =
            'Cell ${assessmentCells.length} entered. Clear the pattern, then enter the next letter of $assessmentWord.';
        if (announce) speak(lastPatternFeedback);
        return;
      }
      final validation = WordAssessmentValidator.validate(
        target: assessmentWord,
        language: selectedLanguage,
        submittedCells: assessmentCells,
      );
      final correct = validation.isCorrect;
      final skillObservations = WordAssessmentValidator.skillObservations(
        target: assessmentWord,
        language: selectedLanguage,
        submittedCells: assessmentCells,
      );
      _emitDemoEvent(
        'braille_validation_completed',
        payload: {
          'language': selectedLanguage.storageName,
          'result': correct ? 'correct' : 'incorrect',
          'cell_count': assessmentWord.length,
          'dots': BrailleDispatcher.dotsForBitmask(entered).join(','),
        },
      );
      final submitted = List<int>.from(assessmentCells);
      wordAssessmentAttempts++;
      if (!correct && hapticsEnabled) {
        HapticFeedback.vibrate();
      } else if (correct) {
        feedback();
      }
      setState(() {
        lessonFeedback = correct
            ? 'Correct. You wrote $assessmentWord using the patterns you learned.'
            : '${_wordCellErrorFeedback(validation, observations: skillObservations)} Let us learn that letter, then continue the assessment.';
        lessonAnswerCorrect = correct;
        if (!correct) {
          assessmentCells.clear();
        }
      });
      lastPatternFeedback = lessonFeedback!;
      if (announce) speak(lastPatternFeedback);
      final passedStageId = assessmentStageId;
      final passedWordIndex = assessmentWordIndex;
      final failedSubmissionId = await persistWordAssessment(
        correct,
        passedStageId,
        passedWordIndex,
        submitted,
        targetWord: assessmentWord,
        language: selectedLanguage,
        validation: validation,
      );
      if (!correct &&
          await _beginWordLetterRemediation(
            submissionId: failedSubmissionId,
            stageId: passedStageId,
            wordIndex: passedWordIndex,
            word: assessmentWord,
            language: selectedLanguage,
            observations: skillObservations,
          )) {
        return;
      }
      if (!correct) {
        final mismatchCell = validation.firstDifferentCell;
        final alternative = mismatchCell == null
            ? null
            : _alternativeWordForWeakEnglishLetter(
                words: stageWords,
                stageId: passedStageId,
                failedWordIndex: passedWordIndex,
                cellIndex: mismatchCell,
              );
        if (alternative != null) {
          final alternativeIndex = stageWords.indexOf(alternative);
          assessmentCells.clear();
          setState(() {
            assessmentWordIndex = alternativeIndex;
            assessmentWord = alternative;
            lessonFeedback =
                '${_wordCellErrorFeedback(validation)} Let us practise the same letter in a different word: $alternative.';
            lessonAnswerCorrect = false;
            page = 2;
            exerciseStartedAt = DateTime.now();
          });
          if (announce) speak(lessonFeedback!);
        }
        return;
      }
      if (correct) {
        final done = completedStageWords.putIfAbsent(
          passedStageId,
          () => <int>{},
        );
        done.add(passedWordIndex);
        final nextWordIndex = _nextRecommendedWordIndex(
          passedStageId,
          stageWords,
        );
        if (nextWordIndex < stageWords.length) {
          assessmentCells.clear();
          setState(() {
            assessmentWordIndex = nextWordIndex;
            assessmentWord = stageWords[nextWordIndex];
            lessonAnswerCorrect = false;
            page = 2;
          });
          if (announce) speak('Correct. Next word: $assessmentWord.');
          return;
        }
        completedWordStages.add(passedStageId);
        final nextIndex = cumulativeAssessment
            ? LessonCatalog.alphabet.length
            : currentCurriculumStage.last + 1;
        if (nextIndex < currentChapter.exercises.length) {
          assessmentCells.clear();
          setState(() {
            wordAssessment = false;
            lessonItem = nextIndex;
            page = 2;
            guidedPractice = false;
            lessonTaught = false;
          });
          if (announce) {
            speak(
              'You passed. Next, we will learn letter ${currentExercise.answer.toUpperCase()}.',
            );
          }
        } else if (!cumulativeAssessment) {
          assessmentCells.clear();
          cumulativeAssessment = true;
          assessmentWordIndex = _nextRecommendedWordIndex(
            'cumulative',
            LessonCatalog.cumulativeWords,
          );
          assessmentWord = LessonCatalog.cumulativeWords[assessmentWordIndex];
          page = 2;
          wordAssessment = true;
          if (announce) {
            speak(
              'You completed all 26 letters. Now write the cumulative word $assessmentWord.',
            );
          }
        } else {
          setState(() {
            wordAssessment = false;
            courseComplete = true;
            page = 2;
          });
          if (announce) {
            speak(
              'You completed the cumulative Braille word assessment. Say continue learning to review any letter.',
            );
          }
        }
      }
      return;
    }

    final expected = BrailleDispatcher.encodeToBitmasks(
      selectedLanguage == AppLanguage.english
          ? currentExercise.answer.toLowerCase()
          : currentExercise.answer,
      selectedLanguage,
    );
    final answerCellCount = expected.length;
    final correct = answerCellCount == 1 && entered == expected.first;
    if (!correct && hapticsEnabled) {
      HapticFeedback.vibrate();
    } else if (correct) {
      feedback();
    }
    setState(() {
      lessonAttempts.update(
        currentExercise.id,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      lessonFeedback = correct
          ? 'Correct. ${currentExercise.explanation}'
          : answerCellCount > 1
          ? 'This verified answer uses $answerCellCount Braille cells. The current practice screen validates one cell at a time; this multi-cell exercise is not scored yet.'
          : 'Not quite. You entered dots ${_dotsFromPattern(pattern)}. The pattern for ${currentExercise.answer.toUpperCase()} is dots ${_dotsFromCell(expected.first)}. Try again.';
      lessonAnswerCorrect = correct;
    });
    lastPatternFeedback = lessonFeedback!;
    if (announce) speak(lastPatternFeedback);
    unawaited(
      persistLessonAttempt(
        currentExercise,
        correct,
        eventExerciseId: chapter == 1
            ? 'guided-practice-${currentExercise.id}'
            : null,
      ),
    );
    if (correct && chapter == 1) {
      setState(() {
        lessonAssessmentAttempts[currentExercise.id] = 0;
        guidedPractice = false;
        lessonAssessment = true;
        page = 2;
        selectedLessonAnswer = null;
        lessonAnswerCorrect = false;
        lessonFeedback = null;
        assessmentCells.clear();
        exerciseStartedAt = DateTime.now();
      });
      lastPatternFeedback =
          'Guided practice complete. The lesson assessment starts automatically. $_lessonQuestionPrompt';
      if (announce) speak(lastPatternFeedback);
      return;
    }
    if (correct) {
      completedLessonQuestions.add(currentExercise.id);
      unawaited(_saveCurrentResume());
      if (selectedLanguage == AppLanguage.english &&
          lessonItem == currentCurriculumStage.last) {
        final stage = currentCurriculumStage;
        setState(() {
          wordAssessment = true;
          page = 2;
          guidedPractice = false;
          assessmentWord = stage.words.first;
          cumulativeAssessment = false;
          assessmentCells.clear();
        });
        if (announce) {
          speak(
            'You finished ${stage.title}. Now write $assessmentWord using ${assessmentWord.length} Braille cells.',
          );
        }
      } else if (selectedLanguage != AppLanguage.english &&
          chapter == 1 &&
          lessonItem == currentChapter.exercises.length - 1) {
        setState(() {
          wordAssessment = true;
          assessmentWordIndex = 0;
          assessmentWord = currentAssessmentWords.first;
          assessmentCells.clear();
          page = 2;
          guidedPractice = false;
        });
        if (announce) {
          speak(
            'You completed the ${selectedLanguage.storageName} letter lessons. Next, write $assessmentWord cell by cell in Bharati Braille.',
          );
        }
      } else {
        moveLessonItem(1, announce: announce);
      }
    }
  }

  bool _sameCells(List<int> actual, List<int> expected) =>
      actual.length == expected.length &&
      List<int>.generate(
        actual.length,
        (index) => index,
      ).every((index) => actual[index] == expected[index]);

  String submitVoicePattern() {
    final keyboard = brailleKeyboardKey.currentState;
    if (keyboard == null) {
      return 'Open guided dot practice first, then say check my answer.';
    }
    checkGuidedPattern(keyboard.pattern, announce: false);
    return lastPatternFeedback;
  }

  Future<String?> persistWordAssessment(
    bool correct,
    String stageId,
    int wordIndex,
    List<int> submittedCells, {
    required String targetWord,
    required AppLanguage language,
    WordAssessmentValidation? validation,
  }) async {
    final attemptNumber = wordAssessmentAttempts;
    final responseTimeMs = DateTime.now()
        .difference(exerciseStartedAt)
        .inMilliseconds
        .clamp(0, 3600000)
        .toInt();
    await progressReady;
    final store = progressStore;
    if (store == null) return null;
    final skillObservations = WordAssessmentValidator.skillObservations(
      target: targetWord,
      language: language,
      submittedCells: submittedCells,
    );
    String? submissionId;
    try {
      submissionId = await store.record(
        exerciseId: 'word-stage-$stageId-word-$wordIndex',
        skillId: '${selectedLanguage.code}-word-writing-$stageId',
        exerciseType: 'word_transcription',
        correct: correct,
        attemptNumber: attemptNumber,
        hintUsed: false,
        responseTimeMs: responseTimeMs,
        learnerId: activeAccount?.learnerId,
        language: language.storageName,
        expectedResponse: {
          'text': targetWord,
          'cells': WordAssessmentValidator.expectedCells(targetWord, language),
        },
        submittedResponse: {
          'cells': List<int>.from(submittedCells),
          'skill_observations': skillObservations,
          if (validation?.firstDifferentCell != null)
            'first_different_cell': validation!.firstDifferentCell,
          if (validation?.errorKind != null)
            'error_category': validation!.errorKind!.name,
          if (language == AppLanguage.english &&
              validation?.firstDifferentCell != null &&
              validation!.firstDifferentCell! < targetWord.length)
            'target_character': targetWord[validation.firstDifferentCell!]
                .toLowerCase(),
          'remediation_status': correct ? 'not_required' : 'pending',
        },
      );
      _emitDemoEvent(
        'practice_attempt_completed',
        payload: {
          'activity': 'word_writing_assessment',
          'correct': correct,
          'attempt_number': attemptNumber,
          'cell_count': submittedCells.length,
          'skill_observations': skillObservations,
        },
      );
      await _refreshLearningHistory(store);
    } catch (_) {
      // Do not block the assessment on a local storage failure.
    }
    unawaited(_syncPendingProgress(knownStore: store));
    return submissionId;
  }

  Future<void> persistWordChapterAttempt({
    required int lessonIndex,
    required String word,
    required bool correct,
    required int attemptNumber,
    required bool hintUsed,
    String? groupId,
    bool finalAttempt = true,
    int responseTimeMs = 0,
    List<Map<String, dynamic>> skillObservations = const [],
  }) async {
    await progressReady;
    final store = progressStore;
    if (store == null) return;
    final lessonNumber = lessonIndex + 1;
    final baseExerciseId =
        'word-chapter-lesson-$lessonNumber-${word.toLowerCase()}';
    final exerciseId = finalAttempt
        ? baseExerciseId
        : '$baseExerciseId-attempt-$attemptNumber';
    try {
      await store.record(
        exerciseId: exerciseId,
        skillId: 'english-word-${LessonCatalog.wordLessons[lessonIndex].id}',
        exerciseType: lessonIndex == 2 || lessonIndex == 4
            ? 'braille_writing'
            : 'listening',
        correct: correct,
        attemptNumber: attemptNumber,
        hintUsed: hintUsed,
        responseTimeMs: responseTimeMs.clamp(0, 3600000),
        groupId: groupId,
        learnerId: activeAccount?.learnerId,
        language: selectedLanguage.storageName,
        expectedResponse: {'text': word},
        submittedResponse: {'skill_observations': skillObservations},
      );
      _emitDemoEvent(
        'practice_attempt_completed',
        payload: {
          'activity': 'english_word_chapter',
          'correct': correct,
          'attempt_number': attemptNumber,
        },
      );
      if (lessonIndex == 1 || lessonIndex == 3) {
        _emitDemoEvent(
          'assessment_answer_checked',
          payload: {'activity': 'english_word_choice', 'correct': correct},
        );
        _emitDemoEvent(
          'assessment_feedback_generated',
          payload: {'activity': 'english_word_choice', 'correct': correct},
        );
      }
      if (correct) {
        _emitDemoEvent(
          'exercise_completed',
          payload: {'activity': 'english_word_chapter'},
        );
      }
      lessonAttempts.update(
        exerciseId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (correct && lessonIndex < 4) {
        wordChapterCompletedWords
            .putIfAbsent(lessonIndex, () => <String>{})
            .add(word);
      }
      await _saveCurrentResume();
      await _refreshLearningHistory(store);
    } catch (_) {
      // Keep offline lesson progress available if local persistence fails.
    }
    unawaited(_syncPendingProgress(knownStore: store));
  }

  void completeWordChapterMastery() {
    setState(() {
      wordChapterCompletedWords[4] = LessonCatalog.wordLessons[4].words.toSet();
      wordChapterComplete = true;
      wordChapterLessonIndex = 4;
      chapter = 3;
      lessonItem = 0;
      page = 2;
      lessonTaught = false;
      guidedPractice = false;
      lessonAssessment = false;
      wordAssessment = false;
      assessmentCells.clear();
      exerciseStartedAt = DateTime.now();
    });
    _emitDemoEvent(
      'mastery_state_updated',
      payload: {'skill': 'english_word_chapter_mastery', 'state': 'passed'},
    );
    unawaited(_saveCurrentResume());
  }

  String _dotsFromPattern(String pattern) => [
    for (var i = 0; i < pattern.length; i++)
      if (pattern[i] == '1') '${i + 1}',
  ].join(', ');

  int _cellFromPattern(String pattern) {
    var cell = 0;
    for (var index = 0; index < pattern.length; index++) {
      if (pattern[index] == '1') cell |= 1 << index;
    }
    return cell;
  }

  String _dotsFromCell(int cell) => [
    for (var i = 0; i < 6; i++)
      if ((cell & (1 << i)) != 0) '${i + 1}',
  ].join(', ');

  void announceLessonHint() {
    hintedLessonQuestions.add(currentExercise.id);
    speak('Hint. ${currentExercise.hint}');
  }

  String _lessonExplanation() {
    if (currentExercise.isComposedResponse) {
      return '${currentExercise.prompt} ${currentExercise.explanation} The verified response has ${currentExerciseCells.length} ordered Braille cells. ${currentExercise.hint}';
    }
    if (selectedLanguage != AppLanguage.english) {
      return '${currentExercise.prompt} ${currentExercise.explanation}';
    }
    final letter = currentExercise.answer.toUpperCase();
    final cell = EnglishGrade1Engine.encode(
      currentExercise.answer.toLowerCase(),
    ).single;
    final dots = EnglishGrade1Engine.dotsForCell(cell);
    const position = {
      1: 'top-left',
      2: 'middle-left',
      3: 'bottom-left',
      4: 'top-right',
      5: 'middle-right',
      6: 'bottom-right',
    };
    final places = dots.map((dot) => 'dot $dot at ${position[dot]}').join(', ');
    return 'In Braille, the letter $letter uses $places. ${currentExercise.hint}';
  }

  Future<void> _advanceCourseFromSwipe() async {
    if (selectedLanguage == AppLanguage.english &&
        courseComplete &&
        chapter == 1) {
      _selectWordChapterResumePoint();
      setState(() => chapter = 2);
      await speak(
        'Welcome to ${LessonCatalog.wordLessons[wordChapterLessonIndex].title}. '
        '${LessonCatalog.wordLessons[wordChapterLessonIndex].description}',
      );
      return;
    }
    if (wordAssessment) {
      setState(() {
        assessmentCells.clear();
        lessonFeedback = null;
        lessonAnswerCorrect = false;
        page = 1;
      });
      await speak(
        'The word is $assessmentWord. Enter each letter with the Braille keyboard, then say check my answer.',
      );
      return;
    }
    if (!lessonTaught) {
      setState(() => lessonTaught = true);
      await speak(_lessonExplanation());
      return;
    }
    setState(() {
      guidedPractice = true;
      page = 1;
      lessonFeedback = null;
      lessonAnswerCorrect = false;
      assessmentCells.clear();
      exerciseStartedAt = DateTime.now();
    });
    await speak(
      currentExercise.isComposedResponse
          ? _compositionInstruction()
          : 'Guided practice for ${currentExercise.answer.toUpperCase()}. Enter its Braille pattern on the keyboard.',
    );
  }

  void openLessonNavigator({bool allowActiveActivity = false}) {
    if (!allowActiveActivity &&
        (lessonAssessment || wordAssessment || guidedPractice)) {
      unawaited(
        speak(
          'Complete the current practice or assessment before opening another lesson.',
        ),
      );
      return;
    }
    if (!allowActiveActivity && _adaptiveRequirementActive) {
      unawaited(
        speak(
          'Complete the assigned remediation and reassessment before opening another lesson. ${_activeAdaptiveDecision!.reason}',
        ),
      );
      return;
    }
    speak(
      selectedLanguage == AppLanguage.hindi
          ? 'à¤ªà¤¾à¤  à¤¸à¥‚à¤šà¥€ à¤–à¥à¤²à¥€ à¤¹à¥ˆà¥¤ à¤•à¤¿à¤¸à¥€ à¤­à¥€ à¤…à¤§à¥à¤¯à¤¾à¤¯ à¤¯à¤¾ à¤…à¤•à¥à¤·à¤° à¤•à¥‹ à¤šà¥à¤¨à¥‡à¤‚à¥¤'
          : selectedLanguage == AppLanguage.kannada
          ? 'à²ªà²¾à² à²—à²³ à²ªà²Ÿà³à²Ÿà²¿ à²¤à³†à²°à³†à²¦à²¿à²¦à³†. à²¯à²¾à²µà³à²¦à³‡ à²…à²§à³à²¯à²¾à²¯ à²…à²¥à²µà²¾ à²…à²•à³à²·à²°à²µà²¨à³à²¨à³ à²†à²¯à³à²•à³†à²®à²¾à²¡à²¿.'
          : 'Lesson menu opened. Select any chapter, letter, or word lesson.',
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF202124),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        selectedLanguage == AppLanguage.hindi
                            ? 'à¤¸à¤­à¥€ à¤ªà¤¾à¤  à¤”à¤° à¤­à¤¾à¤·à¤¾ (Lessons & Language)'
                            : selectedLanguage == AppLanguage.kannada
                            ? 'à²Žà²²à³à²²à²¾ à²ªà²¾à² à²—à²³à³ à²®à²¤à³à²¤à³ à²­à²¾à²·à³† (Lessons & Language)'
                            : 'All Lessons & Language',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),
                  AccessibleActionSurface(
                    semanticsLabel: 'Close lesson menu',
                    actionLabel: 'Close lesson menu',
                    onActivate: () => Navigator.of(sheetContext).pop(),
                    showDivider: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 24),
                        SizedBox(width: 4),
                        Text('Close'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final lang in AppLanguage.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: AccessibleActionSurface(
                          semanticsLabel:
                              '${lang.nativeLabel} language. ${selectedLanguage == lang ? 'Selected.' : 'Not selected.'}',
                          semanticsHint:
                              'Double tap to use ${lang.storageName}.',
                          actionLabel: 'Use ${lang.storageName}',
                          selected: selectedLanguage == lang,
                          inMutuallyExclusiveGroup: true,
                          onActivate: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(switchLanguage(lang));
                          },
                          child: Center(
                            child: Text(
                              lang.nativeLabel,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: activeChapters.length,
                  itemBuilder: (context, chIdx) {
                    final ch = activeChapters[chIdx];
                    return ExpansionTile(
                      initiallyExpanded: chIdx == chapter,
                      title: Text(
                        ch.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      children: [
                        for (
                          var exIdx = 0;
                          exIdx < ch.exercises.length;
                          exIdx++
                        )
                          ListTile(
                            minVerticalPadding: 14,
                            leading: Icon(
                              completedLessonQuestions.contains(
                                    ch.exercises[exIdx].id,
                                  )
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color:
                                  completedLessonQuestions.contains(
                                    ch.exercises[exIdx].id,
                                  )
                                  ? const Color(0xFF9FE0B5)
                                  : Colors.white54,
                            ),
                            title: Text(
                              '${exIdx + 1}. ${ch.exercises[exIdx].answer.toUpperCase()} â€” ${ch.exercises[exIdx].prompt}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            selected: chIdx == chapter && exIdx == lessonItem,
                            onTap: () {
                              if (chIdx == 1 &&
                                  !ch.exercises
                                      .take(exIdx)
                                      .every(
                                        (exercise) => completedLessonQuestions
                                            .contains(exercise.id),
                                      )) {
                                unawaited(
                                  speak(
                                    'Complete the earlier character lessons before opening this lesson.',
                                  ),
                                );
                                return;
                              }
                              Navigator.of(sheetContext).pop();
                              setState(() {
                                page = 2;
                                chapter = chIdx;
                                lessonItem = exIdx;
                                lessonTaught = false;
                                guidedPractice = false;
                                wordAssessment = false;
                                courseComplete = false;
                                lessonFeedback = null;
                                selectedLessonAnswer = null;
                              });
                              unawaited(_saveCurrentResume());
                              feedback();
                              speak(
                                '${ch.title}. ${ch.exercises[exIdx].prompt}',
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseGestureFooter(BuildContext context) {
    var swipeDistance = 0.0;
    final composition = currentExercise.isComposedResponse;
    final prompt = composition
        ? (lessonTaught
              ? 'Swipe up to start six-dot writing · Swipe down to repeat'
              : 'Swipe up to hear the writing lesson · Swipe down to repeat')
        : courseComplete
        ? 'Swipe up to begin the word chapter Â· Swipe down to hear the next lesson'
        : wordAssessment
        ? 'Swipe up to start the word test Â· Swipe down to repeat'
        : lessonTaught
        ? 'Swipe up to practise with the Braille keyboard Â· Swipe down to repeat'
        : 'Swipe up to hear the explanation Â· Swipe down to repeat';
    return Padding(
      padding: const EdgeInsets.only(bottom: 48),
      child: Semantics(
        container: true,
        label: prompt,
        customSemanticsActions: {
          CustomSemanticsAction(
            label: composition
                ? lessonTaught
                      ? 'Start six-dot writing'
                      : 'Hear writing lesson'
                : courseComplete
                ? 'Begin word chapter'
                : wordAssessment
                ? 'Start word test'
                : lessonTaught
                ? 'Begin Braille practice'
                : 'Hear explanation',
          ): _advanceCourseFromSwipe,
          CustomSemanticsAction(label: 'Repeat current lesson'): () => speak(
            composition
                ? _lessonExplanation()
                : courseComplete
                ? 'Next is ${LessonCatalog.wordLessons[wordChapterLessonIndex].title}.'
                : wordAssessment
                ? 'The word is $assessmentWord.'
                : _lessonExplanation(),
          ),
        },
        child: GestureDetector(
          key: const ValueKey('course-swipe-navigation'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => swipeDistance = 0,
          onVerticalDragUpdate: (details) => swipeDistance += details.delta.dy,
          onVerticalDragEnd: (details) {
            if (swipeDistance < -40 || (details.primaryVelocity ?? 0) < -250) {
              _advanceCourseFromSwipe();
            } else if (swipeDistance > 40 ||
                (details.primaryVelocity ?? 0) > 250) {
              speak(
                composition
                    ? _lessonExplanation()
                    : courseComplete
                    ? 'Next is ${LessonCatalog.wordLessons[wordChapterLessonIndex].title}.'
                    : wordAssessment
                    ? 'The word is $assessmentWord.'
                    : _lessonExplanation(),
              );
            }
          },
          child: SizedBox(
            height: 64,
            width: double.infinity,
            child: Center(
              child: Text(
                prompt,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _physicalTutorSubscription?.cancel();
    _physicalTutorSubscription = null;
    _physicalTutorMode = false;
    unawaited(_setPhysicalTutorActive(false));
    _activeTutorController = null;
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAssessmentVoicePreparation();
    if (onboardingLoading) {
      return Scaffold(
        body: Center(
          child: Semantics(
            label: 'Loading Resonant',
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }
    if (!onboardingComplete || replayingOnboarding) {
      return WelcomeOnboarding(
        onComplete: finishOnboarding,
        onSpeak: speak,
        onStop: tts.stop,
        initialStep: replayingOnboarding ? 0 : onboardingStep,
        onStepChanged: (step) async {
          onboardingStep = step;
          await onboardingStore?.saveStep(step);
        },
      );
    }
    if (page == 1) {
      return Scaffold(
        body: SafeArea(
          child: BrailleKeyboard(
            key: brailleKeyboardKey,
            onFeedback: feedback,
            onSpeak: speak,
            onSubmitPattern: checkGuidedPattern,
            onBackspace:
                (wordAssessment ||
                    (guidedPractice && currentExercise.isComposedResponse))
                ? _backspaceAssessmentCell
                : null,
            onResetResponse:
                (wordAssessment ||
                    (guidedPractice && currentExercise.isComposedResponse))
                ? _resetAssessmentResponse
                : null,
            onRepeatInstruction: () => speak(
              guidedPractice && currentExercise.isComposedResponse
                  ? _compositionInstruction()
                  : wordAssessment
                  ? 'Write $assessmentWord, one Braille cell at a time.'
                  : _lessonExplanation(),
            ),
            statusMessage: _brailleKeyboardStatus,
            onAudioChanged: (value) => setState(() => audioEnabled = value),
            audioEnabled: audioEnabled,
            hapticsEnabled: hapticsEnabled,
            onTutor: openVoiceTutor,
          ),
        ),
      );
    }
    if (selectedLanguage == AppLanguage.english && page == 2 && chapter == 2) {
      final gestureEnabled =
          !MediaQuery.of(context).accessibleNavigation &&
          wordChapterLessonIndex != 2 &&
          wordChapterLessonIndex != 4;
      return Scaffold(
        body: SafeArea(
          child: Semantics(
            container: true,
            label:
                'English Words module, chapter ${wordChapterLessonIndex + 1} of ${LessonCatalog.wordLessons.length}.',
            customSemanticsActions: {
              CustomSemanticsAction(label: 'Next chapter'): () =>
                  unawaited(_navigateWordChapterByGesture(1)),
              CustomSemanticsAction(label: 'Previous chapter'): () =>
                  unawaited(_navigateWordChapterByGesture(-1)),
            },
            child: TwoFingerNavigationDetector(
              enabled: gestureEnabled,
              onSwipe: (direction) =>
                  unawaited(_navigateWordChapterByGesture(direction)),
              child: _buildWordChapterScreen(),
            ),
          ),
        ),
      );
    }
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.circle, color: Color(0xFF65A1FF), size: 13),
        const SizedBox(width: 8),
        const Text(
          'RESONANT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
    var tutorSwipeDistance = 0.0;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      container: true,
                      label:
                          'Tutor area. Swipe up to speak to Resonant. Swipe down to replay the welcome lesson. With TalkBack, use the Talk to Resonant or Replay welcome lesson custom action.',
                      customSemanticsActions: {
                        CustomSemanticsAction(label: 'Talk to Resonant'):
                            openVoiceTutor,
                        CustomSemanticsAction(label: 'Replay welcome lesson'):
                            replayWelcome,
                      },
                      child: Builder(
                        builder: (context) => GestureDetector(
                          key: const ValueKey('tutor-swipe-area'),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart:
                              MediaQuery.of(context).accessibleNavigation
                              ? null
                              : (_) => tutorSwipeDistance = 0,
                          onVerticalDragUpdate:
                              MediaQuery.of(context).accessibleNavigation
                              ? null
                              : (details) =>
                                    tutorSwipeDistance += details.delta.dy,
                          onVerticalDragEnd:
                              MediaQuery.of(context).accessibleNavigation
                              ? null
                              : (details) {
                                  if (tutorSwipeDistance < -48 ||
                                      (details.primaryVelocity ?? 0) < -250) {
                                    openVoiceTutor();
                                  } else if (tutorSwipeDistance > 48 ||
                                      (details.primaryVelocity ?? 0) > 250) {
                                    replayWelcome();
                                  }
                                },
                          child: SizedBox(
                            height: 72,
                            child: Row(
                              children: [
                                brand,
                                const Spacer(),
                                const Flexible(
                                  child: Text(
                                    'Swipe up here to talk',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(color: Color(0xFFB8D1FF)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onSwitchRole != null)
                    AccessibleActionSurface(
                      key: const ValueKey('learner-switch-role'),
                      semanticsLabel:
                          'Log out of learner mode and return to role selection. Saved learning progress is preserved.',
                      semanticsHint:
                          'Choose Teacher on the next screen to open the teacher dashboard.',
                      actionLabel: 'Log out / switch role',
                      onActivate: () => unawaited(_switchRole()),
                      showDivider: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.logout,
                            color: Color(0xFFB8D1FF),
                            size: 24,
                          ),
                          SizedBox(width: 6),
                          Text('Log out'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            AccessibleActionSurface(
              key: const ValueKey('open-lesson-navigator'),
              semanticsLabel:
                  'Lessons and language. Current language ${selectedLanguage.nativeLabel}.',
              semanticsHint:
                  'Double tap to browse lessons, or say lesson menu to Resonant.',
              actionLabel: 'Open lessons and language',
              onActivate: openLessonNavigator,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.list_alt, color: Color(0xFFB8D1FF)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Lessons and language · ${selectedLanguage.nativeLabel}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Listener(
                onPointerDown: (event) {
                  if (page == 2 &&
                      (chapter == 1 || currentExercise.isComposedResponse) &&
                      !guidedPractice) {
                    _courseSwipePointer = event.pointer;
                    _courseSwipeStart = event.position;
                  }
                },
                onPointerUp: _handleCourseSwipeEnd,
                onPointerCancel: _clearCourseSwipe,
                child: TwoFingerNavigationDetector(
                  enabled:
                      !MediaQuery.of(context).accessibleNavigation &&
                      (twoFingerNavigationEnabled || page == 2),
                  onSwipe: _navigateLessonByTwoFingerSwipe,
                  onLanguageSwipe: _cycleLanguageFromGesture,
                  onVerticalSwipe: _navigateSection,
                  child: _buildContentPage(),
                ),
              ),
            ),
            if (page == 2 &&
                (chapter == 1 || currentExercise.isComposedResponse) &&
                !guidedPractice &&
                !lessonAssessment)
              _buildCourseGestureFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildWordChapterScreen() => WordChapterScreen(
    key: wordChapterScreenKey,
    initialLesson: wordChapterLessonIndex,
    completedWords: wordChapterCompletedWords,
    wordOrders: _englishAdaptiveWordOrders,
    recommendationReasons: _englishAdaptiveWordReasons,
    onSpeak: speak,
    onFeedback: feedback,
    audioEnabled: audioEnabled,
    hapticsEnabled: hapticsEnabled,
    onAttempt: persistWordChapterAttempt,
    onLessonChanged: (index) => setState(() => wordChapterLessonIndex = index),
    onMasteryPassed: completeWordChapterMastery,
    onTutor: openVoiceTutor,
    onDemoEvent: (type, payload) => _emitDemoEvent(type, payload: payload),
  );

  Widget _buildLetterTeachingStep() {
    final letter = currentExercise.answer.toUpperCase();
    final explanation = _lessonExplanation();
    final pattern = BrailleDispatcher.encodeToBitmasks(
      selectedLanguage == AppLanguage.english
          ? currentExercise.answer.toLowerCase()
          : currentExercise.answer,
      selectedLanguage,
    ).first;
    final dots = _dotsFromCell(pattern);
    final stageText = selectedLanguage == AppLanguage.english
        ? '${LessonCatalog.stageForIndex(lessonItem).title}. Letter ${lessonItem + 1} of ${currentChapter.exercises.length}. ${lessonTaught ? 'Swipe up when you are ready to practise.' : 'Swipe up to hear the explanation.'}'
        : '${currentChapter.title}. Item ${lessonItem + 1} of ${currentChapter.exercises.length}. ${lessonTaught ? 'Swipe up when you are ready to practise.' : 'Swipe up to hear the explanation.'}';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            Semantics(
              header: true,
              child: Text(
                selectedLanguage == AppLanguage.english
                    ? 'Learn letter $letter'
                    : 'Learn $letter',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(stageText),
            const SizedBox(height: 12),
            Text(explanation, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              'Verified Braille dots: $dots. Dot numbering: 1, 2, 3 down the left; 4, 5, 6 down the right.',
            ),
            const SizedBox(height: 12),
            if (lessonFeedback != null)
              Semantics(liveRegion: true, child: Text(lessonFeedback!)),
          ],
        ),
      ),
    );
  }

  Widget _buildWordAssessment() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        padding: const EdgeInsets.all(24),
        shrinkWrap: true,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Write a word: $assessmentWord',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Word ${assessmentWordIndex + 1} of ${currentAssessmentWords.length}. Enter each letter of $assessmentWord in order with the six-dot keyboard. Every test word uses only letters already taught.',
          ),
          const SizedBox(height: 10),
          Text(
            'Cells entered: ${assessmentCells.length} of ${WordAssessmentValidator.expectedCells(assessmentWord, selectedLanguage).length}.',
          ),
          if (completedWordStages.contains(assessmentStageId))
            Semantics(
              liveRegion: true,
              child: Text(
                'Assessment complete. You decoded $assessmentWord correctly.',
              ),
            ),
          if (lessonFeedback != null)
            Semantics(liveRegion: true, child: Text(lessonFeedback!)),
          const SizedBox(height: 12),
          Text(
            completedWordStages.contains(assessmentStageId)
                ? 'This stage test is complete. Say review learned letters, or swipe up to continue your course.'
                : 'Swipe up when you are ready to enter the word.',
          ),
        ],
      ),
    ),
  );

  Widget _buildComposedResponseLesson() {
    final target = currentExerciseAnswer;
    final expectedCells = currentExerciseCells.length;
    final complete = completedLessonQuestions.contains(currentExercise.id);
    final startLabel = selectedLanguage == AppLanguage.hindi
        ? 'छह-बिंदु ब्रेल में लिखना शुरू करें'
        : selectedLanguage == AppLanguage.kannada
        ? 'ಆರು-ಚುಕ್ಕೆ ಬ್ರೈಲ್ ಬರವಣಿಗೆ ಪ್ರಾರಂಭಿಸಿ'
        : 'Start six-dot Braille writing';
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '${currentChapter.title}. ${currentExercise.prompt} Target: $target. $expectedCells ordered Braille cells. ${currentExercise.explanation}',
      customSemanticsActions: {
        CustomSemanticsAction(label: startLabel): _startComposedWritingPractice,
        CustomSemanticsAction(label: 'Repeat writing target'): () =>
            unawaited(speak(_compositionInstruction())),
        CustomSemanticsAction(label: 'Hear writing hint'): () =>
            unawaited(speak(currentExercise.hint)),
      },
      child: ExcludeSemantics(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text(
                  currentChapter.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  currentExercise.prompt,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  target,
                  key: const ValueKey('composed-response-target'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$expectedCells verified cells. Blank cells represent spaces. ${currentExercise.explanation}',
                  textAlign: TextAlign.center,
                ),
                if (complete)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'This writing assessment is complete. You may repeat it for revision.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (lessonFeedback != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(lessonFeedback!, textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 16),
                GestureDetector(
                  key: const ValueKey('start-composed-braille-writing'),
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: _startComposedWritingPractice,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Tap or swipe up to begin six-dot writing; swipe down to repeat. '
                      'Say “hint” or use the TalkBack actions for more help.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFB8D1FF)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentPage() {
    if (page == 0) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Your Braille learning (${selectedLanguage.nativeLabel})',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your lesson is ready. Open Lessons and language to choose a destination, or continue where you left off.',
          ),
          const SizedBox(height: 16),
          AccessibleActionSurface(
            semanticsLabel: 'Continue learning',
            semanticsHint: 'Double tap to resume your saved lesson.',
            actionLabel: 'Continue learning',
            onActivate: continueLearning,
            child: const Row(
              children: [
                Icon(Icons.play_arrow, color: Color(0xFFB8D1FF)),
                SizedBox(width: 12),
                Expanded(child: Text('Continue learning')),
              ],
            ),
          ),
        ],
      );
    }

    if (page == 2) {
      if (chapter == 0 &&
          selectedLanguage != AppLanguage.english &&
          !lessonTaught) {
        final steps = _introStepsFor(selectedLanguage);
        final introduction =
            steps[_vernacularIntroStep.clamp(0, steps.length - 1)];
        final nextAction = selectedLanguage == AppLanguage.hindi
            ? 'अगला परिचय भाग'
            : 'ಮುಂದಿನ ಪರಿಚಯದ ಭಾಗ';
        final previousAction = selectedLanguage == AppLanguage.hindi
            ? 'पिछला परिचय भाग'
            : 'ಹಿಂದಿನ ಪರಿಚಯದ ಭಾಗ';
        final repeatAction = selectedLanguage == AppLanguage.hindi
            ? 'यह परिचय भाग फिर सुनें'
            : 'ಈ ಪರಿಚಯದ ಭಾಗವನ್ನು ಮತ್ತೆ ಕೇಳಿ';
        final gestureHint = selectedLanguage == AppLanguage.hindi
            ? 'अगले भाग के लिए दो उंगलियों से बाईं ओर स्वाइप करें। पिछले भाग के लिए दाईं ओर स्वाइप करें।'
            : 'ಮುಂದಿನ ಭಾಗಕ್ಕೆ ಎರಡು ಬೆರಳುಗಳಿಂದ ಎಡಕ್ಕೆ ಸ್ವೈಪ್ ಮಾಡಿ. ಹಿಂದಿನ ಭಾಗಕ್ಕೆ ಬಲಕ್ಕೆ ಸ್ವೈಪ್ ಮಾಡಿ.';
        final stepCounter = selectedLanguage == AppLanguage.hindi
            ? 'परिचय भाग ${_vernacularIntroStep + 1} में से ${steps.length}'
            : 'ಪರಿಚಯದ ಭಾಗ ${_vernacularIntroStep + 1}ರಲ್ಲಿ ${steps.length}';
        return Semantics(
          key: const ValueKey('vernacular-introduction-surface'),
          container: true,
          liveRegion: true,
          label:
              '${currentChapter.title}. $introduction. $stepCounter. $gestureHint',
          customSemanticsActions: {
            CustomSemanticsAction(label: nextAction): () =>
                _navigateIntroduction(1),
            if (_vernacularIntroStep > 0)
              CustomSemanticsAction(label: previousAction): () =>
                  _navigateIntroduction(-1),
            CustomSemanticsAction(label: repeatAction): () =>
                unawaited(speak(introduction)),
          },
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currentChapter.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              introduction,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(height: 12),
                            Text(stepCounter),
                            const SizedBox(height: 20),
                            Text(gestureHint, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (selectedLanguage == AppLanguage.english && chapter == 2) {
        return WordChapterScreen(
          key: wordChapterScreenKey,
          initialLesson: wordChapterLessonIndex,
          completedWords: wordChapterCompletedWords,
          wordOrders: _englishAdaptiveWordOrders,
          recommendationReasons: _englishAdaptiveWordReasons,
          onSpeak: speak,
          onFeedback: feedback,
          audioEnabled: audioEnabled,
          hapticsEnabled: hapticsEnabled,
          onAttempt: persistWordChapterAttempt,
          onLessonChanged: (index) =>
              setState(() => wordChapterLessonIndex = index),
          onMasteryPassed: completeWordChapterMastery,
          onDemoEvent: (type, payload) =>
              _emitDemoEvent(type, payload: payload),
        );
      }
      if (currentExercise.isComposedResponse) {
        return _buildComposedResponseLesson();
      }
      if (selectedLanguage == AppLanguage.english &&
          courseComplete &&
          chapter == 1) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You completed the English Braille letter course.',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Open All Lessons to review letters or switch to Hindi or Kannada.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }
      if (chapter == 1 &&
          !guidedPractice &&
          !lessonAssessment &&
          !wordAssessment) {
        return _buildLetterTeachingStep();
      }
      if (wordAssessment) return _buildWordAssessment();
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.menu_book,
                    color: Color(0xFF65A1FF),
                    size: 36,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lessonAssessment
                        ? '${selectedLanguage.storageName.toUpperCase()} LESSON ASSESSMENT'
                        : '${selectedLanguage.storageName.toUpperCase()} BRAILLE PRACTICE',
                    style: const TextStyle(
                      color: Colors.white70,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentChapter.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lessonAssessment
                        ? 'Assessment for lesson ${lessonItem + 1} of ${currentChapter.exercises.length}. Your progress is recorded after each answer.'
                        : 'Exercise ${lessonItem + 1} of ${currentChapter.exercises.length}. ${completedLessonQuestions.length} completed this session.',
                    style: const TextStyle(color: Color(0xFFB8D1FF)),
                  ),
                  if (_activeAdaptiveDecision != null &&
                      (_activeAdaptiveDecision!.recommendedLessonId ==
                              currentExercise.id ||
                          _activeAdaptiveDecision!.lessonId ==
                              currentExercise.id)) ...[
                    const SizedBox(height: 12),
                    AdaptiveRecommendationStatus(
                      key: const ValueKey('adaptive-recommendation-status'),
                      decision: _activeAdaptiveDecision!,
                    ),
                  ],
                  const SizedBox(height: 12),
                  AccessibleLessonQuestion(
                    prompt: _lessonQuestionPrompt,
                    options: _lessonQuestionOptions,
                    selectedOption: selectedLessonAnswer,
                    enabled: !lessonAnswerCorrect,
                    onSelected: (option) => setState(() {
                      selectedLessonAnswer = option;
                      lessonFeedback = null;
                    }),
                  ),
                  if (lessonFeedback != null) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        lessonFeedback!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: lessonAnswerCorrect
                              ? const Color(0xFF9FE0B5)
                              : const Color(0xFFFFD18A),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: [
                        AccessibleActionSurface(
                          semanticsLabel: 'Hear a hint',
                          semanticsHint:
                              'Double tap, say hint, or use the TalkBack action.',
                          actionLabel: 'Hear a hint',
                          onActivate: announceLessonHint,
                          child: const Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: Color(0xFFB8D1FF),
                              ),
                              SizedBox(width: 12),
                              Expanded(child: Text('Hear a hint')),
                              Text(
                                'Say “hint”',
                                style: TextStyle(
                                  color: Color(0xFFB8D1FF),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AccessibleActionSurface(
                          key: const ValueKey('check-lesson-answer'),
                          semanticsLabel: 'Check selected answer',
                          semanticsHint: selectedLessonAnswer == null
                              ? 'Select an answer first.'
                              : lessonAnswerCorrect
                              ? 'This answer is already correct.'
                              : 'Double tap or say check answer.',
                          actionLabel: 'Check selected answer',
                          onActivate:
                              selectedLessonAnswer == null ||
                                  lessonAnswerCorrect
                              ? null
                              : () => unawaited(submitLessonAnswer()),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color:
                                    selectedLessonAnswer == null ||
                                        lessonAnswerCorrect
                                    ? Colors.white38
                                    : const Color(0xFFB8D1FF),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(child: Text('Check answer')),
                              const Text(
                                'Say “check answer”',
                                style: TextStyle(
                                  color: Color(0xFFB8D1FF),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (chapter == 2 &&
                            currentExercise.exerciseType ==
                                'word_transcription')
                          AccessibleActionSurface(
                            key: const ValueKey('start-word-braille-writing'),
                            semanticsLabel:
                                selectedLanguage == AppLanguage.hindi
                                ? 'ब्रेल में लिखें'
                                : selectedLanguage == AppLanguage.kannada
                                ? 'ಬ್ರೈಲ್‌ನಲ್ಲಿ ಬರೆಯಿರಿ'
                                : 'Write using the six-dot Braille surface',
                            actionLabel: 'Start six-dot Braille writing',
                            onActivate: _startWordWritingPractice,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.dialpad,
                                  color: Color(0xFFB8D1FF),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    selectedLanguage == AppLanguage.hindi
                                        ? 'ब्रेल में लिखें'
                                        : selectedLanguage ==
                                              AppLanguage.kannada
                                        ? 'ಬ್ರೈಲ್‌ನಲ್ಲಿ ಬರೆಯಿರಿ'
                                        : 'Write using six-dot Braille',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        AccessibleActionSurface(
                          semanticsLabel: 'Next exercise',
                          semanticsHint:
                              'Complete this exercise before moving forward.',
                          actionLabel: 'Next exercise',
                          onActivate:
                              lessonItem + 1 < currentChapter.exercises.length
                              ? () => moveLessonItem(1)
                              : null,
                          child: const Row(
                            children: [
                              Icon(
                                Icons.arrow_forward,
                                color: Color(0xFFB8D1FF),
                              ),
                              SizedBox(width: 12),
                              Expanded(child: Text('Next exercise')),
                              Text(
                                'Say “next lesson”',
                                style: TextStyle(
                                  color: Color(0xFFB8D1FF),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    container: true,
                    label:
                        'Chapter navigation. Use a two-finger horizontal swipe, say next chapter or previous chapter, or choose a TalkBack action.',
                    customSemanticsActions: {
                      CustomSemanticsAction(label: 'Previous chapter'): () =>
                          nextChapter(-1),
                      CustomSemanticsAction(label: 'Next chapter'): () =>
                          nextChapter(1),
                    },
                    child: const ExcludeSemantics(
                      child: Text(
                        'Two-finger swipe for chapters · say “lesson menu” to jump anywhere',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (page == 3) {
      return Center(
        child: SizedBox(
          width: 380,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              const Text(
                'ACCESSIBILITY SETTINGS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SwitchListTile(
                title: const Text(
                  'Audio feedback',
                  style: TextStyle(color: Colors.white),
                ),
                value: audioEnabled,
                onChanged: (value) {
                  setState(() => audioEnabled = value);
                  speak(
                    value
                        ? 'Audio feedback enabled.'
                        : 'Audio feedback disabled.',
                  );
                },
              ),
              SwitchListTile(
                title: const Text(
                  'Haptic feedback',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Vibration confirms navigation, dot selection, and answer feedback.',
                ),
                value: hapticsEnabled,
                onChanged: (value) {
                  setState(() => hapticsEnabled = value);
                  if (value) HapticFeedback.vibrate();
                  speak(
                    value
                        ? 'Haptic feedback enabled.'
                        : 'Haptic feedback disabled.',
                  );
                },
              ),
              SwitchListTile(
                title: const Text('Two-finger navigation gestures'),
                subtitle: const Text(
                  'Optional horizontal two-finger swipes change sections or lesson items. The Braille keyboard is excluded.',
                ),
                value: twoFingerNavigationEnabled,
                onChanged: (value) {
                  setState(() => twoFingerNavigationEnabled = value);
                  speak(
                    value
                        ? 'Two-finger navigation enabled on content screens.'
                        : 'Two-finger navigation disabled.',
                  );
                },
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'VOICE ASSESSMENT',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              SwitchListTile(
                title: const Text('Enable voice assessment'),
                subtitle: const Text(
                  'Voice features remain off until enabled here.',
                ),
                value: voiceAssessmentSettings.enabled,
                onChanged: (value) => _saveVoiceAssessmentSettings(
                  voiceAssessmentSettings.copyWith(enabled: value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: DropdownButtonFormField<String>(
                  value: voiceAssessmentSettings.recognitionLocale,
                  decoration: const InputDecoration(
                    labelText: 'Speech recognition language',
                    helperText:
                        'Follow learning language selects English (India), Hindi (India), or Kannada (India). Availability depends on the speech service installed on this device.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'system',
                      child: Text('Follow learning language'),
                    ),
                    DropdownMenuItem(
                      value: 'en-IN',
                      child: Text('English (India)'),
                    ),
                    DropdownMenuItem(value: 'hi-IN', child: Text('Hindi')),
                    DropdownMenuItem(value: 'kn-IN', child: Text('Kannada')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _saveVoiceAssessmentSettings(
                        voiceAssessmentSettings.copyWith(
                          recognitionLocale: value,
                        ),
                      );
                    }
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('Prepare tutor on assessment screens'),
                value: voiceAssessmentSettings.activateTutorOnAssessment,
                onChanged: voiceAssessmentSettings.enabled
                    ? (value) => _saveVoiceAssessmentSettings(
                        voiceAssessmentSettings.copyWith(
                          activateTutorOnAssessment: value,
                        ),
                      )
                    : null,
              ),
              SwitchListTile(
                title: const Text('Read assessment questions automatically'),
                value: voiceAssessmentSettings.readQuestions,
                onChanged: (value) => _saveVoiceAssessmentSettings(
                  voiceAssessmentSettings.copyWith(readQuestions: value),
                ),
              ),
              SwitchListTile(
                title: const Text('Read answer options automatically'),
                value: voiceAssessmentSettings.readOptions,
                onChanged: (value) => _saveVoiceAssessmentSettings(
                  voiceAssessmentSettings.copyWith(readOptions: value),
                ),
              ),
              SwitchListTile(
                title: const Text('Listen after reading'),
                subtitle: const Text(
                  'Starts the microphone only after you enable voice assessment and grant microphone permission.',
                ),
                value: voiceAssessmentSettings.listenAfterReading,
                onChanged: voiceAssessmentSettings.enabled
                    ? (value) => _saveVoiceAssessmentSettings(
                        voiceAssessmentSettings.copyWith(
                          listenAfterReading: value,
                        ),
                      )
                    : null,
              ),
              SwitchListTile(
                title: const Text('Confirm a spoken answer before checking'),
                value: voiceAssessmentSettings.confirmSelection,
                onChanged: (value) => _saveVoiceAssessmentSettings(
                  voiceAssessmentSettings.copyWith(confirmSelection: value),
                ),
              ),
              SwitchListTile(
                title: const Text('Stop listening whenever Resonant speaks'),
                value: voiceAssessmentSettings.stopListeningForSpeech,
                onChanged: (value) => _saveVoiceAssessmentSettings(
                  voiceAssessmentSettings.copyWith(
                    stopListeningForSpeech: value,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('Listen again after tutor response'),
                value: voiceAssessmentSettings.autoRelisten,
                onChanged: voiceAssessmentSettings.enabled
                    ? (value) => _saveVoiceAssessmentSettings(
                        voiceAssessmentSettings.copyWith(autoRelisten: value),
                      )
                    : null,
              ),
              ListTile(
                title: const Text('Listening timeout'),
                subtitle: Text(
                  '${voiceAssessmentSettings.timeoutSeconds} seconds',
                ),
                enabled: voiceAssessmentSettings.enabled,
                trailing: SizedBox(
                  width: 200,
                  child: Slider(
                    min: 10,
                    max: 120,
                    divisions: 11,
                    value: voiceAssessmentSettings.timeoutSeconds.toDouble(),
                    label: '${voiceAssessmentSettings.timeoutSeconds}s',
                    onChanged: voiceAssessmentSettings.enabled
                        ? (value) => _saveVoiceAssessmentSettings(
                            voiceAssessmentSettings.copyWith(
                              timeoutSeconds: value.round(),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.lan),
                title: const Text('Connect to laptop AIML dashboard'),
                subtitle: const Text(
                  'Join an explicitly paired, temporary live session.',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LiveDemoConnectPage(client: liveDemoClient),
                  ),
                ),
              ),
              AccessibleActionSurface(
                semanticsLabel: 'Replay Welcome to Resonant',
                actionLabel: 'Replay welcome lesson',
                onActivate: () => setState(() => replayingOnboarding = true),
                child: const Row(
                  children: [
                    Icon(Icons.replay, color: Color(0xFFB8D1FF)),
                    SizedBox(width: 12),
                    Expanded(child: Text('Replay Welcome to Resonant')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (page == 4) {
      final difficult = lessonAttempts.entries
          .where((entry) => entry.value > 1)
          .toList();
      return FutureBuilder<void>(
        future: progressReady,
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Semantics(
              header: true,
              child: Text(
                'My Progress',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Text(
              'Saved practice exercises: ${lessonAttempts.length}. Correct exercises: ${completedLessonQuestions.length}.',
            ),
            const SizedBox(height: 12),
            const Text('Review Difficult Letters'),
            if (difficult.isEmpty)
              const Text('No repeated practice items are recorded yet.'),
            for (final entry in difficult)
              AccessibleActionSurface(
                semanticsLabel:
                    '${entry.key.replaceAll('-', ' ')}, ${entry.value} attempts',
                semanticsHint: 'Double tap to review this difficult skill.',
                actionLabel: 'Review ${entry.key.replaceAll('-', ' ')}',
                onActivate: () {
                  final index = currentChapter.exercises.indexWhere(
                    (exercise) => exercise.id == entry.key,
                  );
                  if (index >= 0) {
                    setState(() {
                      page = 2;
                      chapter = 1;
                      lessonItem = index.clamp(
                        0,
                        currentChapter.exercises.length - 1,
                      );
                      lessonTaught = false;
                    });
                  }
                },
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Color(0xFFB8D1FF)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${entry.key.replaceAll('-', ' ')}: ${entry.value} attempts',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (page == 5) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Help',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const Text(
            'Use Lessons and language at the top, or say “lesson menu”, to jump directly to a chapter, letter, or language.',
          ),
          const SizedBox(height: 12),
          AccessibleActionSurface(
            semanticsLabel: 'Replay Welcome to Resonant',
            actionLabel: 'Replay welcome lesson',
            onActivate: () => setState(() => replayingOnboarding = true),
            child: const Row(
              children: [
                Icon(Icons.replay, color: Color(0xFFB8D1FF)),
                SizedBox(width: 12),
                Expanded(child: Text('Replay Welcome to Resonant')),
              ],
            ),
          ),
          AccessibleActionSurface(
            semanticsLabel: 'Stop speaking',
            actionLabel: 'Stop speaking',
            onActivate: tts.stop,
            child: const Row(
              children: [
                Icon(Icons.stop, color: Color(0xFFB8D1FF)),
                SizedBox(width: 12),
                Expanded(child: Text('Stop speaking')),
              ],
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class BrailleKeyboard extends StatefulWidget {
  final VoidCallback onFeedback;
  final Future<void> Function(String) onSpeak;
  final ValueChanged<bool> onAudioChanged;
  final bool audioEnabled;
  final bool hapticsEnabled;
  final ValueChanged<String>? onSubmitPattern;
  final VoidCallback? onBackspace;
  final VoidCallback? onResetResponse;
  final VoidCallback? onRepeatInstruction;
  final VoidCallback? onTutor;
  final String? statusMessage;

  const BrailleKeyboard({
    super.key,
    required this.onFeedback,
    required this.onSpeak,
    required this.onAudioChanged,
    required this.audioEnabled,
    required this.hapticsEnabled,
    this.onSubmitPattern,
    this.onBackspace,
    this.onResetResponse,
    this.onRepeatInstruction,
    this.onTutor,
    this.statusMessage,
  });

  @override
  State<BrailleKeyboard> createState() => _BrailleKeyboardState();
}

class _BrailleKeyboardState extends State<BrailleKeyboard> {
  final Map<int, int> activePointers = {};
  final Set<int> chordDots = {};

  Set<int> selectedDots = {};
  bool accessibleDotControls = false;
  String message = 'Touch one or more dots together.';
  Offset checkSwipeDistance = Offset.zero;

  void beginCheckSwipe(DragStartDetails _) => checkSwipeDistance = Offset.zero;

  void updateCheckSwipe(DragUpdateDetails details) {
    checkSwipeDistance += details.delta;
  }

  void finishCheckSwipe(DragEndDetails _) {
    if (checkSwipeDistance.distance >= 48 && widget.onSubmitPattern != null) {
      widget.onSubmitPattern!(pattern);
    }
    checkSwipeDistance = Offset.zero;
  }

  String get pattern => List.generate(
    6,
    (index) => selectedDots.contains(index + 1) ? '1' : '0',
  ).join();

  String get dotLabel {
    if (selectedDots.isEmpty) return 'None';
    final sorted = selectedDots.toList()..sort();
    return sorted.join(', ');
  }

  String get spokenDotLabel {
    final dots = selectedDots.toList()..sort();
    if (dots.isEmpty) return 'no dots';
    if (dots.length == 1) return 'dot ${dots.single}';
    if (dots.length == 2) return 'dots ${dots[0]} and ${dots[1]}';
    return 'dots ${dots.take(dots.length - 1).join(', ')}, and ${dots.last}';
  }

  int get cellValue =>
      selectedDots.fold(0, (value, dot) => value | (1 << (dot - 1)));

  String get spokenCharacter {
    try {
      final value = EnglishGrade1Engine.decode([cellValue]);
      return value.isEmpty
          ? 'an indicator pattern with no standalone character'
          : 'the character $value';
    } on Object {
      return 'an unsupported single-cell pattern';
    }
  }

  Future<void> speakCurrentCell() => widget.onSpeak(
    'Selected $spokenDotLabel. This Braille cell represents $spokenCharacter.',
  );

  int? dotAtPosition(Offset position, Size size) {
    if (position.dx < 0 ||
        position.dx >= size.width ||
        position.dy < 0 ||
        position.dy >= size.height) {
      return null;
    }

    final column = position.dx < size.width / 2 ? 0 : 1;
    final row = (position.dy / (size.height / 3)).floor().clamp(0, 2);

    const leftDots = [1, 2, 3];
    const rightDots = [4, 5, 6];

    return column == 0 ? leftDots[row] : rightDots[row];
  }

  void pointerDown(PointerDownEvent event, Size size) {
    final dot = dotAtPosition(event.localPosition, size);
    if (dot == null) return;

    setState(() {
      activePointers[event.pointer] = dot;
      chordDots.add(dot);
      message = 'Dot $dot touched.';
    });

    if (widget.hapticsEnabled) {
      widget.onFeedback();
    }
  }

  void pointerMove(PointerMoveEvent event, Size size) {
    if (!activePointers.containsKey(event.pointer)) return;

    final dot = dotAtPosition(event.localPosition, size);
    if (dot == activePointers[event.pointer]) return;
    cancelChord('Touch moved. Chord cancelled. Try again.');
  }

  void pointerCancel(PointerCancelEvent event) {
    if (!activePointers.containsKey(event.pointer)) return;
    cancelChord('Touch interrupted. Chord cancelled. Try again.');
  }

  void cancelChord(String reason) {
    setState(() {
      activePointers.clear();
      chordDots.clear();
      message = reason;
    });
    widget.onSpeak(reason);
  }

  void pointerEnd(int pointer) {
    if (!activePointers.containsKey(pointer)) return;

    late bool chordFinished;

    setState(() {
      activePointers.remove(pointer);
      chordFinished = activePointers.isEmpty;

      if (chordFinished) {
        selectedDots = Set<int>.from(chordDots);
        chordDots.clear();

        message = selectedDots.isEmpty
            ? 'No dots selected.'
            : 'Braille pattern entered.';
      }
    });

    if (chordFinished) {
      if (widget.hapticsEnabled) {
        HapticFeedback.vibrate();
      }

      speakCurrentCell();
    }
  }

  void clearPattern() {
    setState(() {
      activePointers.clear();
      chordDots.clear();
      selectedDots.clear();
      message = 'Pattern cleared.';
    });

    if (widget.hapticsEnabled) {
      HapticFeedback.vibrate();
    }
    widget.onSpeak('Pattern cleared.');
  }

  void toggleAccessibleDot(int dot) {
    setState(() {
      if (selectedDots.contains(dot)) {
        selectedDots.remove(dot);
        message = 'Dot $dot cleared.';
      } else {
        selectedDots.add(dot);
        message = 'Dot $dot selected.';
      }
    });
    if (widget.hapticsEnabled) widget.onFeedback();
    widget.onSpeak('$message Current selection: $spokenDotLabel.');
  }

  Widget buildAccessibleGrid(double diameter) {
    return Column(
      children: [
        for (final rowDots in const [
          [1, 4],
          [2, 5],
          [3, 6],
        ])
          Expanded(
            child: Row(
              children: [
                for (final dot in rowDots)
                  Expanded(
                    child: Semantics(
                      focusable: true,
                      label: 'Braille dot $dot',
                      value: selectedDots.contains(dot)
                          ? 'selected'
                          : 'not selected',
                      toggled: selectedDots.contains(dot),
                      onTap: () => toggleAccessibleDot(dot),
                      customSemanticsActions: {
                        CustomSemanticsAction(
                          label: selectedDots.contains(dot)
                              ? 'Clear Braille dot $dot'
                              : 'Select Braille dot $dot',
                        ): () =>
                            toggleAccessibleDot(dot),
                      },
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: () => toggleAccessibleDot(dot),
                          child: Center(child: buildDot(dot, diameter)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget buildDot(int dot, double diameter) {
    final active = chordDots.contains(dot);
    final selected = selectedDots.contains(dot);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active || selected ? const Color(0xFF2468D9) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF8CB5FF), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        '$dot',
        style: TextStyle(
          fontSize: diameter * 0.43,
          fontWeight: FontWeight.bold,
          color: active || selected ? Colors.white : const Color(0xFF2468D9),
        ),
      ),
    );
  }

  Widget buildKeyboardAction({
    required String label,
    required IconData icon,
    required VoidCallback? onActivate,
    Key? key,
  }) {
    return Tooltip(
      message: label,
      child: AccessibleActionSurface(
        key: key,
        semanticsLabel: label,
        actionLabel: label,
        onActivate: onActivate,
        showDivider: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(
          icon,
          color: onActivate == null ? Colors.white38 : Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final controlsHeight = (height * 0.27).clamp(94.0, 110.0).toDouble();
        final keyboardHeight = (height - controlsHeight)
            .clamp(0.0, height)
            .toDouble();
        final keyboardSize = Size(width, keyboardHeight);
        final diameter = (keyboardHeight * 0.28).clamp(48.0, 104.0).toDouble();

        return Container(
          color: const Color(0xFF080A1B),
          child: Column(
            children: [
              Expanded(
                child: SizedBox(
                  width: width,
                  child: accessibleDotControls
                      ? buildAccessibleGrid(diameter)
                      : Listener(
                          key: const ValueKey('braille-touch-surface'),
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) =>
                              pointerDown(event, keyboardSize),
                          onPointerMove: (event) =>
                              pointerMove(event, keyboardSize),
                          onPointerUp: (event) => pointerEnd(event.pointer),
                          onPointerCancel: pointerCancel,
                          child: Column(
                            children: [
                              for (int row = 0; row < 3; row++)
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Center(
                                          child: buildDot(
                                            [1, 2, 3][row],
                                            diameter,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: buildDot(
                                            [4, 5, 6][row],
                                            diameter,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
              SizedBox(
                height: controlsHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                container: true,
                                liveRegion: true,
                                focusable: true,
                                label:
                                    '$message Current selection: $spokenDotLabel. Pattern $pattern. Tap or swipe in any direction here to check this cell. ${widget.statusMessage ?? ''}',
                                onTap: widget.onSubmitPattern == null
                                    ? null
                                    : () => widget.onSubmitPattern!(pattern),
                                customSemanticsActions:
                                    widget.onSubmitPattern == null
                                    ? const {}
                                    : {
                                        CustomSemanticsAction(
                                          label: 'Check current Braille cell',
                                        ): () =>
                                            widget.onSubmitPattern!(pattern),
                                      },
                                child: ExcludeSemantics(
                                  child: GestureDetector(
                                    key: const ValueKey(
                                      'braille-check-swipe-area',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    excludeFromSemantics: true,
                                    onPanStart: beginCheckSwipe,
                                    onPanUpdate: updateCheckSwipe,
                                    onPanEnd: finishCheckSwipe,
                                    onPanCancel: () =>
                                        checkSwipeDistance = Offset.zero,
                                    child: Text(
                                      '$message  â€¢  Dots: $dotLabel  â€¢  $pattern\nTap or swipe here to check',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFB8D1FF),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (widget.onTutor != null)
                              Semantics(
                                container: true,
                                label:
                                    'Swipe up here to talk to Resonant. Tap or use the Talk to Resonant accessibility action.',
                                customSemanticsActions: {
                                  CustomSemanticsAction(
                                    label: 'Talk to Resonant',
                                  ): widget.onTutor!,
                                },
                                child: Builder(
                                  builder: (context) => GestureDetector(
                                    key: const ValueKey(
                                      'keyboard-tutor-prompt',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: widget.onTutor,
                                    onVerticalDragEnd:
                                        MediaQuery.of(
                                          context,
                                        ).accessibleNavigation
                                        ? null
                                        : (details) {
                                            if ((details.primaryVelocity ?? 0) <
                                                -250) {
                                              widget.onTutor!();
                                            }
                                          },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Swipe up here to talk',
                                        style: TextStyle(
                                          color: Color(0xFFB8D1FF),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            buildKeyboardAction(
                              label: accessibleDotControls
                                  ? 'Switch to touch keyboard'
                                  : 'Switch to accessible dot controls',
                              onActivate: () {
                                setState(() {
                                  accessibleDotControls =
                                      !accessibleDotControls;
                                  activePointers.clear();
                                  chordDots.clear();
                                });
                                if (widget.hapticsEnabled) widget.onFeedback();
                                widget.onSpeak(
                                  accessibleDotControls
                                      ? 'Accessible dot controls.'
                                      : 'Touch keyboard.',
                                );
                              },
                              icon: Icons.accessibility,
                            ),
                            if (widget.onSubmitPattern != null)
                              buildKeyboardAction(
                                key: const ValueKey('keyboard-check-pattern'),
                                label: 'Check pattern',
                                icon: Icons.check_circle_outline,
                                onActivate: () =>
                                    widget.onSubmitPattern!(pattern),
                              ),
                            if (widget.onBackspace != null)
                              buildKeyboardAction(
                                label: 'Backspace previous Braille cell',
                                icon: Icons.backspace_outlined,
                                onActivate: widget.onBackspace,
                              ),
                            if (widget.onResetResponse != null)
                              buildKeyboardAction(
                                label: 'Clear complete Braille response',
                                icon: Icons.delete_sweep_outlined,
                                onActivate: widget.onResetResponse,
                              ),
                            if (widget.onRepeatInstruction != null)
                              buildKeyboardAction(
                                label: 'Repeat current writing instruction',
                                icon: Icons.replay,
                                onActivate: widget.onRepeatInstruction,
                              ),
                            buildKeyboardAction(
                              label: 'Hear Braille character',
                              icon: Icons.volume_up,
                              onActivate: speakCurrentCell,
                            ),
                            buildKeyboardAction(
                              label: 'Clear pattern',
                              icon: Icons.refresh,
                              onActivate: clearPattern,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

typedef WordChapterAttemptHandler =
    Future<void> Function({
      required int lessonIndex,
      required String word,
      required bool correct,
      required int attemptNumber,
      required bool hintUsed,
      String? groupId,
      bool finalAttempt,
      int responseTimeMs,
      required List<Map<String, dynamic>> skillObservations,
    });

class WordChapterScreen extends StatefulWidget {
  final int initialLesson;
  final Map<int, StringSet> completedWords;
  final Map<int, List<String>> wordOrders;
  final Map<int, String> recommendationReasons;
  final Future<void> Function(String) onSpeak;
  final VoidCallback onFeedback;
  final bool audioEnabled;
  final bool hapticsEnabled;
  final WordChapterAttemptHandler onAttempt;
  final ValueChanged<int> onLessonChanged;
  final VoidCallback onMasteryPassed;
  final VoidCallback? onTutor;
  final void Function(String, Map<String, Object?>)? onDemoEvent;

  const WordChapterScreen({
    super.key,
    required this.initialLesson,
    required this.completedWords,
    this.wordOrders = const {},
    this.recommendationReasons = const {},
    required this.onSpeak,
    required this.onFeedback,
    required this.audioEnabled,
    required this.hapticsEnabled,
    required this.onAttempt,
    required this.onLessonChanged,
    required this.onMasteryPassed,
    this.onTutor,
    this.onDemoEvent,
  });

  @override
  State<WordChapterScreen> createState() => _WordChapterScreenState();
}

class _WordChapterScreenState extends State<WordChapterScreen> {
  final GlobalKey<_BrailleKeyboardState> _keyboardKey =
      GlobalKey<_BrailleKeyboardState>();
  late int lessonIndex;
  late Map<int, StringSet> completedWords;
  late Map<int, List<String>> activeWordOrders;
  int wordIndex = 0;
  int cellIndex = 0;
  int attemptNumber = 0;
  int firstTryMasteryScore = 0;
  bool firstTry = true;
  bool hintUsed = false;
  bool busy = false;
  bool masteryFailed = false;
  String? feedbackText;
  bool? feedbackCorrect;
  String? _pendingTutorWord;
  late String groupId;
  late DateTime activityStarted;

  WordLearningLesson get lesson => LessonCatalog.wordLessons[lessonIndex];
  List<String> get words => wordsAt(lessonIndex);
  String get word => words[wordIndex];
  String get currentWordForTutor => word;
  List<int> get targetCells => EnglishGrade1Engine.encode(word);
  bool get writingLesson =>
      lessonIndex == 0 || lessonIndex == 2 || lessonIndex == 4;

  String? spokenChoiceForTutor(String? spoken) {
    if (lessonIndex != 1 && lessonIndex != 3) return null;
    final normalized = spoken?.toLowerCase().trim();
    if (normalized == null || normalized.isEmpty) return null;
    const numberWords = <String, int>{
      'a': 0,
      'b': 1,
      'c': 2,
      'd': 3,
      'e': 4,
      'one': 0,
      'first': 0,
      'two': 1,
      'second': 1,
      'three': 2,
      'third': 2,
      'four': 3,
      'fourth': 3,
      'five': 4,
      'fifth': 4,
    };
    final option = RegExp(
      r'^(?:the )?(?:option|choice) ([a-e]|[1-5])$',
    ).firstMatch(normalized)?.group(1);
    final target = option ?? normalized;
    final numericIndex = int.tryParse(target);
    final index = numericIndex == null ? numberWords[target] : numericIndex - 1;
    final selected = index != null && index >= 0 && index < words.length
        ? words[index]
        : words.cast<String?>().firstWhere(
            (candidate) => candidate?.toLowerCase() == target,
            orElse: () => null,
          );
    return selected;
  }

  Future<String> chooseSpokenAnswer(String? spoken) async {
    if (lessonIndex != 1 && lessonIndex != 3) {
      return 'This word activity does not have spoken answer choices. Use the current lesson action instead.';
    }
    if (busy) return 'The previous answer is still being processed.';
    final selected = spokenChoiceForTutor(spoken);
    if (selected == null) {
      return 'That answer is not one of the available choices. Say the option, its number, or its word.';
    }
    setState(() {
      _pendingTutorWord = selected;
      feedbackText =
          'Selected $selected. Say check answer or submit when ready.';
      feedbackCorrect = null;
    });
    return 'Selected $selected. Say check answer or submit when ready.';
  }

  String repeatQuestionFromTutor() => _repeatPrompt();

  Future<String> checkAnswerFromTutor() async {
    final selected = _pendingTutorWord;
    if (selected == null) {
      return 'Choose an answer first, then say check answer or submit.';
    }
    _pendingTutorWord = null;
    await _chooseWord(selected, announce: false);
    return feedbackText ?? 'The selected answer was checked.';
  }

  String moveWordFromTutor(int direction) {
    if (busy) return 'The current word action is still being processed.';
    final previousIndex = wordIndex;
    final current = word;
    moveWord(direction, announce: false);
    if (previousIndex == wordIndex) {
      if (direction > 0 &&
          !(completedWords[lessonIndex] ?? const <String>{}).contains(
            current,
          )) {
        return 'Complete this word before moving to the next one.';
      }
      return direction > 0
          ? 'This is the last word in this lesson.'
          : 'This is the first word in this lesson.';
    }
    return 'Word ${wordIndex + 1} of ${words.length}: $word.';
  }

  String requestHintFromTutor() {
    unawaited(_hint());
    return 'Playing a hint for $word.';
  }

  String activatePrimaryFromTutor() {
    if (busy) return 'The current word action is still being processed.';
    if (lessonIndex == 4 && masteryFailed) {
      _retryMastery();
      return 'Starting a new mastery attempt.';
    }
    if (lessonIndex == 1 || lessonIndex == 3) {
      return 'Say answer followed by the word or its choice number.';
    }
    return 'Use the six-dot Braille surface for the current word.';
  }

  @override
  void initState() {
    super.initState();
    lessonIndex = widget.initialLesson.clamp(
      0,
      LessonCatalog.wordLessons.length - 1,
    );
    completedWords = {
      for (final entry in widget.completedWords.entries)
        entry.key: Set<String>.from(entry.value),
    };
    activeWordOrders = {
      for (var index = 0; index < LessonCatalog.wordLessons.length; index++)
        index: List<String>.from(_validatedWordOrder(index)),
    };
    wordIndex = _firstIncompleteWord(lessonIndex);
    groupId = _newRoundId();
    activityStarted = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onSpeak(
          lessonIndex == 3
              ? '${lesson.title}. ${lesson.description} ${widget.recommendationReasons[lessonIndex] ?? ''} Explore the Braille cells and identify the word.'
              : lessonIndex == 2
              ? '${lesson.title}. ${lesson.description} ${widget.recommendationReasons[lessonIndex] ?? ''} Current word: $word. ${_cellDescription(0)}'
              : '${lesson.title}. ${lesson.description} ${widget.recommendationReasons[lessonIndex] ?? ''} Current word: $word.',
        );
      }
    });
  }

  String _newRoundId() =>
      'word-mastery-${DateTime.now().toUtc().microsecondsSinceEpoch}';

  int _firstIncompleteWord(int index) {
    final done = completedWords[index] ?? const <String>{};
    final ordered = wordsAt(index);
    return ordered
        .indexWhere((entry) => !done.contains(entry))
        .clamp(0, ordered.length - 1);
  }

  WordLearningLesson lessonAt(int index) => LessonCatalog.wordLessons[index];

  List<String> wordsAt(int index) {
    final active = activeWordOrders[index];
    if (active != null) return active;
    return _validatedWordOrder(index);
  }

  List<String> _validatedWordOrder(int index) {
    final verified = lessonAt(index).words;
    final recommended = widget.wordOrders[index];
    if (recommended == null ||
        recommended.length != verified.length ||
        recommended.toSet().length != verified.length ||
        !recommended.toSet().containsAll(verified)) {
      return verified;
    }
    return recommended;
  }

  bool goToLesson(int target, {bool announce = true}) {
    if (busy || target < 0 || target >= LessonCatalog.wordLessons.length) {
      return false;
    }
    if (target > lessonIndex) {
      for (var prerequisite = 0; prerequisite < target; prerequisite++) {
        final completed = completedWords[prerequisite] ?? const <String>{};
        if (!wordsAt(prerequisite).every(completed.contains)) {
          if (announce) {
            widget.onSpeak(
              'Complete the earlier Words chapters before opening ${lessonAt(target).title}.',
            );
          }
          return false;
        }
      }
    }

    setState(() {
      activeWordOrders[target] = List<String>.from(_validatedWordOrder(target));
      lessonIndex = target;
      wordIndex = _firstIncompleteWord(target);
      firstTryMasteryScore = 0;
      masteryFailed = false;
      if (target == 4) groupId = _newRoundId();
      _resetWord();
    });
    widget.onLessonChanged(target);
    if (announce) {
      widget.onFeedback();
      widget.onSpeak(
        'English Words, Chapter ${target + 1}. ${lesson.title}. ${lesson.description} ${widget.recommendationReasons[target] ?? ''}',
      );
    }
    return true;
  }

  void moveWord(int direction, {bool announce = true}) {
    if (busy) return;
    final next = wordIndex + direction;
    if (next < 0 || next >= words.length) {
      if (announce) {
        widget.onSpeak(
          direction < 0
              ? 'This is the first word.'
              : 'This is the last word in this lesson.',
        );
      }
      return;
    }
    if (direction > 0 &&
        !((completedWords[lessonIndex] ?? const <String>{}).contains(word))) {
      if (announce) widget.onSpeak('Complete this word before moving on.');
      return;
    }
    setState(() {
      wordIndex = next;
      _resetWord();
    });
    widget.onFeedback();
    if (announce) {
      widget.onSpeak('Word ${wordIndex + 1} of ${words.length}: $word.');
    }
  }

  void _resetWord() {
    cellIndex = 0;
    attemptNumber = 0;
    firstTry = true;
    hintUsed = false;
    feedbackText = null;
    feedbackCorrect = null;
    activityStarted = DateTime.now();
    _keyboardKey.currentState?.clearPattern();
  }

  Future<void> _persist({
    required bool correct,
    required bool finalAttempt,
    List<Map<String, dynamic>> skillObservations = const [],
  }) async {
    await widget.onAttempt(
      lessonIndex: lessonIndex,
      word: word,
      correct: correct,
      attemptNumber: attemptNumber.clamp(1, 100000),
      hintUsed: hintUsed,
      groupId: lessonIndex == 4 ? groupId : null,
      finalAttempt: finalAttempt,
      responseTimeMs: DateTime.now()
          .difference(activityStarted)
          .inMilliseconds
          .clamp(0, 3600000),
      skillObservations: skillObservations,
    );
  }

  Future<void> _completeCurrentWord({
    required bool firstTryCorrect,
    bool announce = true,
  }) async {
    final completedThisAssessment = firstTryCorrect;
    await _persist(
      correct: lessonIndex == 4 ? completedThisAssessment : true,
      finalAttempt: true,
      skillObservations: writingLesson
          ? WordAssessmentValidator.skillObservations(
              target: word,
              language: AppLanguage.english,
              submittedCells: WordAssessmentValidator.expectedCells(
                word.toLowerCase(),
                AppLanguage.english,
              ),
            )
          : const [],
    );
    if (!mounted) return;

    if (lessonIndex == 4 && completedThisAssessment) {
      firstTryMasteryScore++;
    }
    final done = completedWords.putIfAbsent(lessonIndex, () => <String>{});
    if (lessonIndex < 4) done.add(word);

    final hasNextWord = lessonIndex == 4
        ? wordIndex + 1 < words.length
        : done.length < words.length;
    if (hasNextWord) {
      if (lessonIndex < 4) {
        activeWordOrders[lessonIndex] = List<String>.from(
          _validatedWordOrder(lessonIndex),
        );
      }
      setState(() {
        wordIndex = lessonIndex == 4
            ? wordIndex + 1
            : _firstIncompleteWord(lessonIndex);
        _resetWord();
        feedbackText = lessonIndex == 4
            ? 'Word complete. ${words.length - wordIndex - 1} words remain in this test.'
            : 'Word complete. Next: ${words[wordIndex]}.';
        feedbackCorrect = true;
      });
      widget.onFeedback();
      if (announce) {
        await widget.onSpeak(
          lessonIndex == 4
              ? 'Word complete. Next word: $word.'
              : 'Good work. Next word: $word.',
        );
      }
      return;
    }

    if (lessonIndex == 4) {
      if (firstTryMasteryScore >= 4) {
        setState(() {
          done.addAll(words);
          feedbackText =
              'Mastery passed: $firstTryMasteryScore of 5 correct on the first try. The word chapter is complete.';
          feedbackCorrect = true;
        });
        widget.onMasteryPassed();
        widget.onFeedback();
        if (announce) await widget.onSpeak(feedbackText!);
      } else {
        setState(() {
          masteryFailed = true;
          feedbackText =
              'You got $firstTryMasteryScore of 5 on the first try. Four correct are needed. Review the words and try the test again.';
          feedbackCorrect = false;
        });
        if (announce) await widget.onSpeak(feedbackText!);
      }
      return;
    }

    final allComplete = words.every(done.contains);
    if (allComplete && lessonIndex < 4) {
      final nextLesson = lessonIndex + 1;
      setState(() {
        lessonIndex = nextLesson;
        activeWordOrders[nextLesson] = List<String>.from(
          _validatedWordOrder(nextLesson),
        );
        wordIndex = _firstIncompleteWord(nextLesson);
        if (nextLesson == 4) groupId = _newRoundId();
        firstTryMasteryScore = 0;
        _resetWord();
      });
      widget.onLessonChanged(nextLesson);
      if (announce) {
        await widget.onSpeak(
          'Lesson complete. ${lesson.title}. Next: ${lessonAt(nextLesson).title}. ${lessonAt(nextLesson).description}',
        );
      }
    }
  }

  Future<void> _chooseWord(String selected, {bool announce = true}) async {
    if (busy) return;
    setState(() => busy = true);
    attemptNumber++;
    final correct = selected == word;
    if (!correct) {
      firstTry = false;
      await _persist(correct: false, finalAttempt: false);
      if (mounted) {
        setState(() {
          feedbackText =
              'Not quite. You chose $selected. Listen again or ask for a hint, then try once more.';
          feedbackCorrect = false;
          busy = false;
        });
      }
      widget.onFeedback();
      if (announce) {
        await widget.onSpeak('Not quite. Listen again, or ask for a hint.');
      }
      return;
    }
    setState(() {
      feedbackText = 'Correct. $word is spelled one cell per letter.';
      feedbackCorrect = true;
    });
    await _completeCurrentWord(firstTryCorrect: firstTry, announce: announce);
    if (mounted) setState(() => busy = false);
  }

  void _submitCell(String pattern) {
    unawaited(_checkCell(pattern));
  }

  Future<void> _checkCell(String pattern) async {
    if (busy || cellIndex >= targetCells.length) return;
    setState(() => busy = true);
    attemptNumber++;
    var value = 0;
    for (var index = 0; index < pattern.length && index < 6; index++) {
      if (pattern[index] == '1') value |= 1 << index;
    }
    final correct = value == targetCells[cellIndex];
    if (!correct) {
      firstTry = false;
      final observation = _currentCellObservation(correct: false);
      await _persist(
        correct: false,
        finalAttempt: false,
        skillObservations: observation == null ? const [] : [observation],
      );
      _keyboardKey.currentState?.clearPattern();
      final expectedDots = EnglishGrade1Engine.dotsForCell(
        targetCells[cellIndex],
      );
      final hint = expectedDots.isEmpty
          ? 'a blank cell'
          : _dotsText([targetCells[cellIndex]]);
      if (mounted) {
        setState(() {
          feedbackText =
              'That cell was not quite right. ${_cellDescription(cellIndex)} uses $hint. Try again.';
          feedbackCorrect = false;
          busy = false;
        });
      }
      widget.onFeedback();
      await widget.onSpeak(feedbackText!);
      return;
    }

    final nextCell = cellIndex + 1;
    _keyboardKey.currentState?.clearPattern();
    if (nextCell < targetCells.length) {
      setState(() {
        cellIndex = nextCell;
        feedbackText = 'Correct. ${_cellDescription(nextCell)}';
        feedbackCorrect = true;
        busy = false;
      });
      widget.onFeedback();
      await widget.onSpeak('Correct. ${_cellDescription(nextCell)}');
      return;
    }
    setState(() {
      cellIndex = nextCell;
      feedbackText = 'You wrote $word correctly.';
      feedbackCorrect = true;
    });
    await _completeCurrentWord(firstTryCorrect: firstTry);
    if (mounted) setState(() => busy = false);
  }

  String _cellDescription(int index) {
    if (word == word.toUpperCase() && index < 2) {
      return 'Capital-word sign cell ${index + 1} of 2 for $word. Select dot 6.';
    }
    final letterIndex = word == word.toUpperCase() ? index - 2 : index;
    final letter = word[letterIndex.clamp(0, word.length - 1)];
    return 'Cell ${index + 1} of ${targetCells.length}: letter $letter uses ${_dotsText([targetCells[index]])}.';
  }

  Map<String, dynamic>? _currentCellObservation({required bool correct}) {
    final letterIndex = word == word.toUpperCase() ? cellIndex - 2 : cellIndex;
    if (letterIndex < 0 || letterIndex >= word.length) return null;
    final character = word[letterIndex].toLowerCase();
    return {
      'character': character,
      'skill_id': 'english-letter-$character',
      'correct': correct,
      'cell_start': letterIndex,
      'cell_count': 1,
    };
  }

  Future<void> _hint() async {
    hintUsed = true;
    widget.onDemoEvent?.call('hint_requested', {
      'activity': 'english_word_chapter',
      'lesson_index': lessonIndex,
    });
    if (lessonIndex == 4) firstTry = false;
    if (writingLesson) {
      await widget.onSpeak('Hint. ${_cellDescription(cellIndex)}');
    } else {
      await widget.onSpeak(
        'Hint. The word is ${word.toLowerCase()}, spelled ${word.split('').join(', ')}.',
      );
    }
    if (mounted) setState(() {});
  }

  void _backspace() {
    final keyboard = _keyboardKey.currentState;
    if (keyboard != null && keyboard.selectedDots.isNotEmpty) {
      keyboard.clearPattern();
      return;
    }
    if (cellIndex > 0) {
      setState(() {
        cellIndex--;
        firstTry = false;
        feedbackText = 'Previous cell removed. ${_cellDescription(cellIndex)}';
        feedbackCorrect = null;
      });
      widget.onFeedback();
      widget.onSpeak(feedbackText!);
    } else {
      widget.onSpeak('There is no earlier cell to remove.');
    }
  }

  void _retryMastery() {
    setState(() {
      wordIndex = 0;
      firstTryMasteryScore = 0;
      masteryFailed = false;
      groupId = _newRoundId();
      _resetWord();
    });
    widget.onSpeak(
      'New mastery attempt. Write ${words.first}. Four of five words must be correct on the first try.',
    );
  }

  String _dotsText(List<int> cells) {
    const position = {
      1: 'top-left',
      2: 'middle-left',
      3: 'bottom-left',
      4: 'top-right',
      5: 'middle-right',
      6: 'bottom-right',
    };
    return cells
        .asMap()
        .entries
        .map((entry) {
          final dots = EnglishGrade1Engine.dotsForCell(entry.value);
          return dots.isEmpty
              ? 'blank cell'
              : dots.map((dot) => 'dot $dot at ${position[dot]}').join(' and ');
        })
        .join(', then ');
  }

  String _repeatPrompt() {
    if (lessonIndex == 3) {
      return 'Braille cells for identification: ${_dotsText(targetCells)}. Which word do they spell?';
    }
    if (writingLesson) {
      return 'Let us write $word. ${_cellDescription(cellIndex)}';
    }
    return '${lesson.title}. Current word: $word. ${lesson.description}';
  }

  @override
  Widget build(BuildContext context) {
    final completed = completedWords[lessonIndex]?.length ?? 0;
    final isMasteryPassed =
        lessonIndex == 4 && completedWords[4]?.length == words.length;
    if (writingLesson && !isMasteryPassed && !masteryFailed) {
      return BrailleKeyboard(
        key: _keyboardKey,
        onFeedback: widget.onFeedback,
        onSpeak: widget.onSpeak,
        onAudioChanged: (_) {},
        audioEnabled: widget.audioEnabled,
        hapticsEnabled: widget.hapticsEnabled,
        onSubmitPattern: _submitCell,
        onBackspace: _backspace,
        onTutor: widget.onTutor,
        statusMessage: feedbackText,
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  liveRegion: true,
                  label:
                      '${lesson.title}. Word ${wordIndex + 1} of ${words.length}. $completed completed. ${widget.recommendationReasons[lessonIndex] ?? ''}',
                  child: Text(
                    '${lesson.title}  Â·  Word ${wordIndex + 1} of ${words.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Text(
                '$completed/${words.length} complete',
                style: const TextStyle(color: Color(0xFFB8D1FF)),
              ),
              Tooltip(
                message: 'Repeat current lesson prompt',
                child: AccessibleActionSurface(
                  semanticsLabel: 'Repeat current lesson prompt',
                  actionLabel: 'Repeat current lesson prompt',
                  onActivate: () => widget.onSpeak(_repeatPrompt()),
                  showDivider: false,
                  padding: const EdgeInsets.all(10),
                  child: const Icon(Icons.replay, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            lesson.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB8D1FF)),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (lessonIndex != 3)
                  Text(word, style: Theme.of(context).textTheme.headlineMedium)
                else
                  Text(
                    'Braille word to identify',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                const SizedBox(height: 8),
                _BrailleWordDisplay(word: word, cells: targetCells),
                const SizedBox(height: 8),
                Text(
                  'Verified cells in order: ${_dotsText(targetCells)}',
                  textAlign: TextAlign.center,
                ),
                if (feedbackText != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(feedbackText!, textAlign: TextAlign.center),
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      if (lessonIndex != 3)
                        AccessibleActionSurface(
                          semanticsLabel: 'Hear the current word',
                          actionLabel: 'Hear the current word',
                          onActivate: () => widget.onSpeak(
                            'The word is ${word.toLowerCase()}.',
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.volume_up, color: Color(0xFFB8D1FF)),
                              SizedBox(width: 12),
                              Expanded(child: Text('Hear the word')),
                              Text(
                                'Say “repeat word”',
                                style: TextStyle(
                                  color: Color(0xFFB8D1FF),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      AccessibleActionSurface(
                        semanticsLabel: lessonIndex == 3
                            ? 'Hear Braille cells'
                            : 'Hear each Braille cell',
                        actionLabel: lessonIndex == 3
                            ? 'Hear Braille cells'
                            : 'Hear each Braille cell',
                        onActivate: () => widget.onSpeak(
                          lessonIndex == 3
                              ? 'Braille cell sequence: ${_dotsText(targetCells)}.'
                              : '$word, letter by letter. ${_dotsText(targetCells)}.',
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hearing, color: Color(0xFFB8D1FF)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                lessonIndex == 3
                                    ? 'Hear Braille cells'
                                    : 'Hear each cell',
                              ),
                            ),
                          ],
                        ),
                      ),
                      AccessibleActionSurface(
                        semanticsLabel: 'Hear a hint',
                        actionLabel: 'Hear a hint',
                        onActivate: _hint,
                        child: const Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: Color(0xFFB8D1FF),
                            ),
                            SizedBox(width: 12),
                            Expanded(child: Text('Hear a hint')),
                            Text(
                              'Say “hint”',
                              style: TextStyle(
                                color: Color(0xFFB8D1FF),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (lessonIndex == 1 || lessonIndex == 3) ...[
                  const SizedBox(height: 8),
                  Text(
                    lessonIndex == 1
                        ? 'Which word did you hear?'
                        : 'Which word do these Braille cells spell?',
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: [
                        for (var index = 0; index < words.length; index++)
                          AccessibleActionSurface(
                            key: ValueKey('word-answer-option-$index'),
                            semanticsLabel:
                                'Answer ${index + 1}: ${words[index]}',
                            semanticsHint:
                                'Double tap, or say answer ${words[index]}.',
                            actionLabel: 'Choose ${words[index]}',
                            onActivate: busy
                                ? null
                                : () => _chooseWord(words[index]),
                            inMutuallyExclusiveGroup: true,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    '${index + 1}.',
                                    style: const TextStyle(
                                      color: Color(0xFFB8D1FF),
                                    ),
                                  ),
                                ),
                                Expanded(child: Text(words[index])),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (lessonIndex == 4 && isMasteryPassed)
                  const Text('Word chapter complete. You may review any word.'),
                if (lessonIndex == 4 && masteryFailed)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: AccessibleActionSurface(
                      semanticsLabel: 'Retry mastery test',
                      actionLabel: 'Retry mastery test',
                      onActivate: _retryMastery,
                      child: const Row(
                        children: [
                          Icon(Icons.replay, color: Color(0xFFB8D1FF)),
                          SizedBox(width: 12),
                          Expanded(child: Text('Retry mastery test')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BrailleWordDisplay extends StatelessWidget {
  final String word;
  final List<int> cells;
  const _BrailleWordDisplay({required this.word, required this.cells});

  @override
  Widget build(BuildContext context) {
    final descriptions = cells
        .asMap()
        .entries
        .map((entry) {
          final dots = EnglishGrade1Engine.dotsForCell(entry.value);
          return 'cell ${entry.key + 1}, dots ${dots.join(', ')}';
        })
        .join('; ');
    return Semantics(
      container: true,
      label: 'Braille pattern. ${cells.length} cells. $descriptions.',
      child: ExcludeSemantics(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var cellIndex = 0; cellIndex < cells.length; cellIndex++)
              _BrailleCellSymbol(
                cell: cells[cellIndex],
                label: 'Cell ${cellIndex + 1}',
              ),
          ],
        ),
      ),
    );
  }
}

class _BrailleCellSymbol extends StatelessWidget {
  final int cell;
  final String label;
  const _BrailleCellSymbol({required this.cell, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white60),
          ),
          for (final row in const [
            [1, 4],
            [2, 5],
            [3, 6],
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final dot in row)
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cell & (1 << (dot - 1)) != 0
                            ? const Color(0xFF65A1FF)
                            : Colors.white24,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
