import 'theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';
import 'package:resonant_braille/learning/lesson_progress_store.dart';
import 'package:resonant_braille/learning/onboarding_store.dart';
import 'package:resonant_braille/learning/welcome_onboarding.dart';
import 'package:resonant_braille/core/braille/english_grade1_engine.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/tutor/speech_to_text_recognizer.dart';
import 'package:resonant_braille/tutor/voice_tutor_panel.dart';
import 'package:resonant_braille/tutor/voice_tutor_controller.dart';
import 'package:resonant_braille/tutor/voice_command_parser.dart';
import 'package:resonant_braille/accessibility/two_finger_navigation_detector.dart';
import 'package:resonant_braille/learning/role_selection_page.dart';
import 'package:resonant_braille/learning/role_store.dart';
import 'package:resonant_braille/teacher/teacher_dashboard_placeholder.dart';

typedef IntSet = Set<int>;
typedef StringSet = Set<String>;
typedef BoolMap = Map<String, bool>;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ResonantApp());
}

class ResonantApp extends StatelessWidget {
  const ResonantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resonant',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
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
      learnerHome: const ResonantHome(),
      teacherHome: (onSwitchRole) => TeacherDashboardPlaceholder(
        onSwitchRole: onSwitchRole,
      ),
    );
  }
}

class ResonantHome extends StatefulWidget {
  final OnboardingProgress? onboardingProgress;
  final LessonProgressStore? lessonProgressStore;

  const ResonantHome({
    super.key,
    this.onboardingProgress,
    this.lessonProgressStore,
  });

  @override
  State<ResonantHome> createState() => _ResonantHomeState();
}

class _ResonantHomeState extends State<ResonantHome> {
  final FlutterTts tts = FlutterTts();
  final SpeechToTextRecognizer voiceSpeech = SpeechToTextRecognizer();

  int page = 0;
  int chapter = 0;
  int lessonItem = 0;
  String? selectedLessonAnswer;
  String? lessonFeedback;
  bool lessonAnswerCorrect = false;
  final Set<String> completedLessonQuestions = {};
  final Set<String> hintedLessonQuestions = {};
  final Map<String, int> lessonAttempts = {};
  LessonProgressStore? progressStore;
  late final Future<void> progressReady;
  DateTime exerciseStartedAt = DateTime.now();
  OnboardingProgress? onboardingStore;
  bool onboardingLoading = true;
  bool onboardingComplete = false;
  int onboardingStep = 0;
  bool replayingOnboarding = false;
  bool lessonTaught = false;
  bool guidedPractice = false;
  bool wordAssessment = false;
  bool cumulativeAssessment = false;
  bool courseComplete = false;
  String assessmentWord = 'BAD';
  final Set<String> completedWordStages = {};
  final Map<String, IntSet> completedStageWords = {};
  int assessmentWordIndex = 0;
  final List<int> assessmentCells = [];
  int wordAssessmentAttempts = 0;
  int wordChapterLessonIndex = 0;
  bool wordChapterComplete = false;
  final Map<int, StringSet> wordChapterCompletedWords = {};
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
  AppLanguage selectedLanguage = AppLanguage.english;

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

  CurriculumStage get currentCurriculumStage =>
      LessonCatalog.stageForIndex(lessonItem);

  String get assessmentStageId =>
      cumulativeAssessment ? 'cumulative' : currentCurriculumStage.id;

  List<String> get currentAssessmentWords => cumulativeAssessment
      ? LessonCatalog.cumulativeWords
      : currentCurriculumStage.words;

  int _nextIncompleteWordIndex(String stageId, List<String> words) {
    final done = completedStageWords[stageId] ?? const <int>{};
    return List<int>.generate(
          words.length,
          (index) => index,
        ).where((index) => !done.contains(index)).firstOrNull ??
        words.length;
  }

  @override
  void initState() {
    super.initState();
    progressReady = restoreLessonProgress();
    restoreOnboarding();
    configureAudio();
  }

  Future<void> _saveCurrentResume() async {
    await progressReady;
    await progressStore?.saveResumeState(
      languageCode: selectedLanguage.code,
      chapter: chapter,
      lessonItem: lessonItem,
      wordLessonIndex: wordChapterLessonIndex,
    );
  }

  Future<void> switchLanguage(AppLanguage lang, {bool announce = true}) async {
    setState(() {
      selectedLanguage = lang;
      chapter = 1;
      lessonItem = 0;
      lessonTaught = false;
      guidedPractice = false;
      wordAssessment = false;
      courseComplete = false;
      lessonFeedback = null;
      selectedLessonAnswer = null;
      assessmentCells.clear();
    });
    try {
      await tts.setLanguage(lang.ttsLocale);
      await tts.setSpeechRate(0.45);
    } catch (_) {}
    await _saveCurrentResume();
    if (announce) {
      final msg = switch (lang) {
        AppLanguage.english =>
          'Language switched to English. ${currentChapter.title}.',
        AppLanguage.hindi => 'à¤­à¤¾à¤·à¤¾ à¤¹à¤¿à¤‚à¤¦à¥€ à¤šà¥à¤¨à¥€ à¤—à¤ˆ à¤¹à¥ˆà¥¤ ${currentChapter.title}à¥¤',
        AppLanguage.kannada =>
          'à²•à²¨à³à²¨à²¡ à²­à²¾à²·à³†à²¯à²¨à³à²¨à³ à²†à²¯à³à²•à³†à²®à²¾à²¡à²²à²¾à²—à²¿à²¦à³†. ${currentChapter.title}.',
      };
      await speak(msg);
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
      chapter = courseComplete ? 2 : 1;
      page = 2;
      lessonTaught = !wordAssessment;

      final savedResume = await progressStore?.readResumeState() ?? {};
      if (savedResume.isNotEmpty && savedResume['language'] != 'en') {
        selectedLanguage = AppLanguage.fromCode(
          savedResume['language'] as String?,
        );
        final savedChapter = savedResume['chapter'];
        final savedItem = savedResume['lesson_item'];
        final savedWordIdx = savedResume['word_lesson_index'];
        if (savedChapter is int &&
            savedChapter >= 0 &&
            savedChapter < activeChapters.length) {
          chapter = savedChapter;
        }
        if (savedItem is int &&
            savedItem >= 0 &&
            savedItem < currentChapter.exercises.length) {
          lessonItem = savedItem;
        }
        if (savedWordIdx is int &&
            savedWordIdx >= 0 &&
            savedWordIdx < LessonCatalog.wordLessons.length) {
          wordChapterLessonIndex = savedWordIdx;
        }
        try {
          await tts.setLanguage(selectedLanguage.ttsLocale);
        } catch (_) {}
      }
    }
    if (mounted) setState(() => onboardingLoading = false);
    if (onboardingComplete && mounted) {
      unawaited(
        speak(
          selectedLanguage != AppLanguage.english
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
      chapter = courseComplete ? 2 : 1;
    });
    if (announce) {
      await speak(
        chapter == 2
            ? '${LessonCatalog.wordLessons[wordChapterLessonIndex].title}. ${LessonCatalog.wordLessons[wordChapterLessonIndex].description}'
            : 'Let us begin with letter ${currentExercise.answer.toUpperCase()}. ${_lessonExplanation()}',
      );
    }
  }

  void continueLearning({bool announce = true}) {
    if (selectedLanguage != AppLanguage.english) {
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
    setState(() {
      page = 2;
      chapter = courseComplete ? 2 : 1;
      lessonTaught = !wordAssessment;
      guidedPractice = false;
    });
    if (announce && courseComplete) {
      speak(
        wordChapterComplete
            ? 'You completed the English word chapter. You can review any word.'
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
        assessmentWordIndex = _nextIncompleteWordIndex(stage.id, stage.words);
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
    assessmentWordIndex = _nextIncompleteWordIndex(
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
      for (final event in events) {
        final id = event['exercise_id'] as String?;
        if (id == null) continue;
        lessonAttempts.update(id, (value) => value + 1, ifAbsent: () => 1);
        if (event['outcome'] == 'correct') completedLessonQuestions.add(id);
        if (id.startsWith('word-stage-') && event['outcome'] == 'correct') {
          final wordSeparator = id.lastIndexOf('-word-');
          final wordIndex = wordSeparator < 0
              ? null
              : int.tryParse(id.substring(wordSeparator + 6));
          if (wordIndex != null) {
            final stageId = id.substring('word-stage-'.length, wordSeparator);
            final words = stageId == 'cumulative'
                ? LessonCatalog.cumulativeWords
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
              if (done.length >= words.length) completedWordStages.add(stageId);
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
      _selectWordChapterResumePoint();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> persistLessonAttempt(
    LessonExercise exercise,
    bool correct,
  ) async {
    await progressReady;
    final store = progressStore;
    if (store == null) return;
    try {
      await store.record(
        exerciseId: exercise.id,
        skillId: exercise.skillId,
        exerciseType: exercise.exerciseType,
        correct: correct,
        attemptNumber: lessonAttempts[exercise.id] ?? 1,
        hintUsed: hintedLessonQuestions.contains(exercise.id),
        responseTimeMs: DateTime.now()
            .difference(exerciseStartedAt)
            .inMilliseconds
            .clamp(0, 3600000)
            .toInt(),
      );
      await _saveCurrentResume();
    } catch (_) {}
  }

  Future<void> configureAudio() async {
    try {
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
    if (page != 2 || chapter != 1 || guidedPractice) return;
    if (distance < -48) {
      unawaited(_advanceCourseFromSwipe());
    } else if (distance > 48) {
      unawaited(speak(_lessonExplanation()));
    }
  }

  Future<void> openVoiceTutor() async {
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
    final controller = createVoiceTutorController(
      tts: tts,
      speech: voiceSpeech,
      lessonContext: lessonContext,
      lessonExamples: lessonExamples,
      audioEnabled: audioEnabled,
      localCommandHandler: (question) async {
        final answer = await handleVoiceCommand(question);
        if (answer != null) lastSpokenInstruction = answer;
        return answer;
      },
      onLocalCommandComplete: () async {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      onStatusAnnouncement: speak,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => VoiceTutorPanel(
        controller: controller,
        hapticsEnabled: hapticsEnabled,
        startListeningOnOpen: true,
      ),
    );
  }

  String? _currentLessonExampleText() {
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
        await tts.speak(text);
      } catch (_) {}
    }
  }

  Future<String?> handleVoiceCommand(String input) async {
    final lower = input.toLowerCase().trim();
    if (lower.contains('hindi') || lower.contains('à¤¹à¤¿à¤‚à¤¦à¥€')) {
      await switchLanguage(AppLanguage.hindi, announce: false);
      return 'à¤­à¤¾à¤·à¤¾ à¤¹à¤¿à¤‚à¤¦à¥€ à¤šà¥à¤¨à¥€ à¤—à¤ˆ à¤¹à¥ˆà¥¤';
    }
    if (lower.contains('kannada') || lower.contains('à²•à²¨à³à²¨à²¡')) {
      await switchLanguage(AppLanguage.kannada, announce: false);
      return 'à²•à²¨à³à²¨à²¡ à²­à²¾à²·à³†à²¯à²¨à³à²¨à³ à²†à²¯à³à²•à³†à²®à²¾à²¡à²²à²¾à²—à²¿à²¦à³†.';
    }
    if (lower.contains('english')) {
      await switchLanguage(AppLanguage.english, announce: false);
      return 'Language switched to English.';
    }
    if (lower.contains('all lessons') || lower.contains('lesson menu')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openLessonNavigator();
      });
      return 'Opening the lesson list.';
    }

    final parsed = VoiceCommandParser.parse(input);
    if (parsed == null) return null;
    switch (parsed.command) {
      case VoiceCommand.startLearning:
        if (!onboardingComplete) {
          return 'Please complete Lesson 1 first. Your progress is saved so you can resume it.';
        }
        continueLearning(announce: false);
        return 'Opening your next lesson.';
      case VoiceCommand.teachLetter:
        if (!onboardingComplete) {
          return 'Please complete Lesson 1 first. Your progress is saved so you can resume it.';
        }
        final index = activeChapters[1].exercises.indexWhere(
          (exercise) => exercise.answer.toUpperCase() == parsed.letter,
        );
        if (index < 0) {
          return 'That letter is not in the current alphabet lesson.';
        }
        setState(() {
          page = 2;
          chapter = 1;
          lessonItem = index;
          lessonTaught = false;
          guidedPractice = false;
          wordAssessment = false;
          lessonFeedback = null;
        });
        unawaited(_saveCurrentResume());
        feedback();
        return 'Opening the lesson for letter ${parsed.letter}.';
      case VoiceCommand.repeat:
        return lastSpokenInstruction.isEmpty
            ? 'There is no previous lesson instruction to repeat yet.'
            : lastSpokenInstruction;
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
      case VoiceCommand.checkAnswer:
        if (page != 1) {
          return 'Start guided dot practice first. Then say check my answer.';
        }
        return submitVoicePattern();
      case VoiceCommand.repeatWord:
        return wordAssessment
            ? assessmentWord
            : 'There is no active word test. Say continue learning to resume your course.';
      case VoiceCommand.clearPattern:
        brailleKeyboardKey.currentState?.clearPattern();
        return 'Current Braille cell cleared.';
      case VoiceCommand.giveHint:
        if (page == 2 && !wordAssessment && !courseComplete) {
          return currentExercise.hint;
        }
        return 'Try recalling the Braille patterns from the letters you learned.';
      case VoiceCommand.showProgress:
        setState(() => page = 4);
        final mastered = completedLessonQuestions.length;
        return 'You have completed $mastered exercises and passed ${completedWordStages.length} word tests.';
      case VoiceCommand.reviewDifficult:
        final difficult = lessonAttempts.entries
            .where((entry) => entry.value > 1)
            .firstOrNull;
        if (difficult == null) {
          setState(() => page = 4);
          return 'No letters have needed repeated attempts yet.';
        }
        final index = currentChapter.exercises.indexWhere(
          (exercise) => exercise.id == difficult.key,
        );
        if (index >= 0) {
          setState(() {
            chapter = 1;
            lessonItem = index;
            page = 2;
            lessonTaught = false;
            guidedPractice = false;
            wordAssessment = false;
            courseComplete = false;
          });
          return 'Reviewing ${currentChapter.exercises[index].answer.toUpperCase()}.';
        }
        setState(() => page = 4);
        return 'Open progress to review your repeated practice items.';
      case VoiceCommand.openSettings:
        setState(() => page = 3);
        return 'Accessibility settings.';
      case VoiceCommand.startTest:
        if (!wordAssessment) {
          return 'Finish the current letter group first. Then I will open its word test.';
        }
        setState(() {
          page = 1;
          assessmentCells.clear();
          lessonFeedback = null;
        });
        return 'The word is $assessmentWord. Enter each letter with the Braille keyboard, then say check my answer.';
      case VoiceCommand.nextLesson:
        moveLessonItem(1);
        return 'Moving to the next lesson.';
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
      case VoiceCommand.home:
        setState(() => page = 0);
        feedback();
        return 'Your learning screen is ready.';
      case VoiceCommand.openTutor:
        return 'You are already talking to Resonant.';
      case VoiceCommand.stopSpeaking:
        return 'Swipe down in the tutor status area to interrupt my spoken reply.';
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

    feedback();
    speak(pages[newPage]);
  }

  void navigateByTwoFingerSwipe(int direction) {
    if (direction == 0 || !twoFingerNavigationEnabled || !mounted) return;
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

  void nextChapter(int direction) {
    final next = chapter + direction;

    if (selectedLanguage == AppLanguage.english &&
        next == 2 &&
        !courseComplete) {
      speak(
        'Complete the English letter course before starting the word chapter.',
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
      wordAssessment = false;
      assessmentCells.clear();
      if (selectedLanguage == AppLanguage.english && next == 2) {
        _selectWordChapterResumePoint();
      }
    });

    unawaited(_saveCurrentResume());
    feedback();
    speak(currentChapter.title);
  }

  void moveLessonItem(int direction, {bool announce = true}) {
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

  void submitLessonAnswer() {
    final answer = selectedLessonAnswer;
    if (answer == null || lessonAnswerCorrect) return;

    final exercise = currentExercise;
    final correct = exercise.isCorrect(answer);
    setState(() {
      lessonAttempts.update(
        exercise.id,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      lessonAnswerCorrect = correct;
      lessonFeedback = correct
          ? 'Correct. ${exercise.explanation}'
          : 'Not quite. Try again, or ask for a hint.';
      if (correct) completedLessonQuestions.add(exercise.id);
    });
    feedback();
    speak(lessonFeedback!);
    unawaited(persistLessonAttempt(exercise, correct));
  }

  void checkGuidedPattern(String pattern, {bool announce = true}) {
    final entered = _cellFromPattern(pattern);
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
      if (assessmentCells.length < assessmentWord.length) {
        setState(() {});
        lastPatternFeedback =
            'Cell ${assessmentCells.length} entered. Clear the pattern, then enter the next letter of $assessmentWord.';
        if (announce) speak(lastPatternFeedback);
        return;
      }
      String decoded;
      try {
        decoded = EnglishGrade1Engine.decode(assessmentCells);
      } catch (_) {
        decoded = '';
      }
      final correct = decoded.toLowerCase() == assessmentWord.toLowerCase();
      wordAssessmentAttempts++;
      if (!correct && hapticsEnabled) {
        HapticFeedback.vibrate();
      } else if (correct) {
        feedback();
      }
      setState(() {
        lessonFeedback = correct
            ? 'Correct. You wrote $assessmentWord using the patterns you learned.'
            : 'That did not decode to $assessmentWord. Clear the cells and try the word again.';
        lessonAnswerCorrect = correct;
        if (!correct) {
          assessmentCells.clear();
        }
      });
      lastPatternFeedback = lessonFeedback!;
      if (announce) speak(lastPatternFeedback);
      final passedStageId = assessmentStageId;
      final passedWordIndex = assessmentWordIndex;
      unawaited(persistWordAssessment(correct, passedStageId, passedWordIndex));
      if (correct) {
        final done = completedStageWords.putIfAbsent(
          passedStageId,
          () => <int>{},
        );
        done.add(passedWordIndex);
        final nextWordIndex = _nextIncompleteWordIndex(
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
          assessmentWordIndex = _nextIncompleteWordIndex(
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
    ).first;
    final correct = entered == expected;
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
          : 'Not quite. You entered dots ${_dotsFromPattern(pattern)}. The pattern for ${currentExercise.answer.toUpperCase()} is dots ${_dotsFromCell(expected)}. Try again.';
      lessonAnswerCorrect = correct;
    });
    lastPatternFeedback = lessonFeedback!;
    if (announce) speak(lastPatternFeedback);
    unawaited(persistLessonAttempt(currentExercise, correct));
    if (correct) {
      completedLessonQuestions.add(currentExercise.id);
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
      } else {
        moveLessonItem(1, announce: announce);
      }
    }
  }

  String submitVoicePattern() {
    final keyboard = brailleKeyboardKey.currentState;
    if (keyboard == null) {
      return 'Open guided dot practice first, then say check my answer.';
    }
    checkGuidedPattern(keyboard.pattern, announce: false);
    return lastPatternFeedback;
  }

  Future<void> persistWordAssessment(
    bool correct,
    String stageId,
    int wordIndex,
  ) async {
    await progressReady;
    final store = progressStore;
    if (store == null) return;
    try {
      await store.record(
        exerciseId: 'word-stage-$stageId-word-$wordIndex',
        skillId: 'english-word-writing-$stageId',
        exerciseType: 'word_transcription',
        correct: correct,
        attemptNumber: wordAssessmentAttempts,
        hintUsed: false,
        responseTimeMs: DateTime.now()
            .difference(exerciseStartedAt)
            .inMilliseconds
            .clamp(0, 3600000)
            .toInt(),
      );
    } catch (_) {}
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
      );
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
    } catch (_) {}
  }

  void completeWordChapterMastery() {
    setState(() {
      wordChapterCompletedWords[4] = LessonCatalog.wordLessons[4].words.toSet();
      wordChapterComplete = true;
      wordChapterLessonIndex = 4;
    });
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
    });
    await speak(
      'Guided practice for ${currentExercise.answer.toUpperCase()}. Enter its Braille pattern on the keyboard.',
    );
  }

  void openLessonNavigator() {
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
      backgroundColor: AppColors.background,
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
                  IconButton(
                    tooltip: 'Close lesson menu',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close, size: 28),
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
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: selectedLanguage == lang
                                ? AppColors.primary
                                : AppColors.surface,
                            minimumSize: const Size(0, 52),
                          ),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(switchLanguage(lang));
                          },
                          child: Text(
                            lang.nativeLabel,
                            style: const TextStyle(fontSize: 16),
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
                              color: completedLessonQuestions.contains(
                                    ch.exercises[exIdx].id,
                                  )
                                  ? AppColors.success
                                  : Colors.white54,
                            ),
                            title: Text(
                              '${exIdx + 1}. ${ch.exercises[exIdx].answer.toUpperCase()} — ${ch.exercises[exIdx].prompt}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            selected: chIdx == chapter && exIdx == lessonItem,
                            onTap: () {
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
    final prompt = courseComplete
        ? 'Swipe up to begin the word chapter · Swipe down to hear the next lesson'
        : wordAssessment
        ? 'Swipe up to start the word test · Swipe down to repeat'
        : lessonTaught
        ? 'Swipe up to practise with the Braille keyboard · Swipe down to repeat'
        : 'Swipe up to hear the explanation · Swipe down to repeat';
    return Padding(
      padding: const EdgeInsets.only(bottom: 48),
      child: Semantics(
        container: true,
        label: prompt,
        customSemanticsActions: {
          CustomSemanticsAction(
            label: courseComplete
                ? 'Begin word chapter'
                : wordAssessment
                ? 'Start word test'
                : lessonTaught
                ? 'Begin Braille practice'
                : 'Hear explanation',
          ): _advanceCourseFromSwipe,
          CustomSemanticsAction(label: 'Repeat current lesson'): () => speak(
            courseComplete
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
                courseComplete
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
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            statusMessage: lessonFeedback,
            onAudioChanged: (value) => setState(() => audioEnabled = value),
            audioEnabled: audioEnabled,
            hapticsEnabled: hapticsEnabled,
            onTutor: openVoiceTutor,
          ),
        ),
      );
    }
    if (selectedLanguage == AppLanguage.english && page == 2 && chapter == 2) {
      return Scaffold(body: SafeArea(child: _buildWordChapterScreen()));
    }
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.circle, color: AppColors.accent, size: 13),
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
                        : (details) => tutorSwipeDistance += details.delta.dy,
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
                              style: TextStyle(color: AppColors.primaryTint),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('open-lesson-navigator'),
                      onPressed: openLessonNavigator,
                      icon: const Icon(Icons.list_alt),
                      label: Text(
                        'Lessons (${selectedLanguage.nativeLabel})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('open-keyboard-shortcut'),
                      onPressed: () => navigateTo(1),
                      icon: const Icon(Icons.dialpad),
                      label: const Text(
                        'Braille Pad',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Listener(
                onPointerDown: (event) {
                  if (page == 2 && chapter == 1 && !guidedPractice) {
                    _courseSwipePointer = event.pointer;
                    _courseSwipeStart = event.position;
                  }
                },
                onPointerUp: _handleCourseSwipeEnd,
                onPointerCancel: _clearCourseSwipe,
                child: TwoFingerNavigationDetector(
                  enabled: twoFingerNavigationEnabled,
                  onSwipe: navigateByTwoFingerSwipe,
                  child: _buildContentPage(),
                ),
              ),
            ),
            if (page == 2 && chapter == 1 && !guidedPractice)
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
    onSpeak: speak,
    onFeedback: feedback,
    audioEnabled: audioEnabled,
    hapticsEnabled: hapticsEnabled,
    onAttempt: persistWordChapterAttempt,
    onLessonChanged: (index) => setState(() => wordChapterLessonIndex = index),
    onMasteryPassed: completeWordChapterMastery,
    onTutor: openVoiceTutor,
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
                selectedLanguage == AppLanguage.english ? 'Learn letter $letter' : 'Learn $letter',
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
            'Cells entered: ${assessmentCells.length} of ${assessmentWord.length}.',
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
            'Your lesson is ready. Open All Lessons to pick any lesson or language, or continue where you left off.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: continueLearning,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Continue learning'),
          ),
        ],
      );
    }

    if (page == 2) {
      if (selectedLanguage == AppLanguage.english && chapter == 2) {
        return WordChapterScreen(
          key: wordChapterScreenKey,
          initialLesson: wordChapterLessonIndex,
          completedWords: wordChapterCompletedWords,
          onSpeak: speak,
          onFeedback: feedback,
          audioEnabled: audioEnabled,
          hapticsEnabled: hapticsEnabled,
          onAttempt: persistWordChapterAttempt,
          onLessonChanged: (index) =>
              setState(() => wordChapterLessonIndex = index),
          onMasteryPassed: completeWordChapterMastery,
        );
      }
      if (selectedLanguage == AppLanguage.english && courseComplete) {
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
      if (chapter == 1 && !guidedPractice && !wordAssessment) {
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
                    color: AppColors.accent,
                    size: 36,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${selectedLanguage.storageName.toUpperCase()} BRAILLE PRACTICE',
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
                    'Exercise ${lessonItem + 1} of ${currentChapter.exercises.length}. '
                    '${completedLessonQuestions.length} completed this session.',
                    style: const TextStyle(color: AppColors.primaryTint),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    currentExercise.prompt,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 19),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final option in currentExercise.options)
                        OutlinedButton(
                          onPressed: lessonAnswerCorrect
                              ? null
                              : () => setState(() {
                                  selectedLessonAnswer = option;
                                  lessonFeedback = null;
                                }),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: selectedLessonAnswer == option
                                ? Colors.white
                                : AppColors.primaryTint,
                            backgroundColor: selectedLessonAnswer == option
                                ? AppColors.primary
                                : Colors.transparent,
                            minimumSize: const Size(104, 48),
                          ),
                          child: Text(option),
                        ),
                    ],
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
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: announceLessonHint,
                        icon: const Icon(Icons.lightbulb_outline),
                        label: const Text('Hear a hint'),
                      ),
                      FilledButton(
                        onPressed:
                            selectedLessonAnswer == null || lessonAnswerCorrect
                            ? null
                            : submitLessonAnswer,
                        child: const Text('Check answer'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            lessonItem + 1 < currentChapter.exercises.length
                            ? () => moveLessonItem(1)
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next exercise'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous chapter',
                        onPressed: () => nextChapter(-1),
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                        ),
                      ),
                      const Flexible(
                        child: Text(
                          'Use the Lessons button above to jump to any chapter or character.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next chapter',
                        onPressed: () => nextChapter(1),
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                      ),
                    ],
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
              TextButton.icon(
                onPressed: () => setState(() => replayingOnboarding = true),
                icon: const Icon(Icons.replay),
                label: const Text('Replay Welcome to Resonant'),
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
              OutlinedButton(
                onPressed: () {
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
                child: Text(
                  '${entry.key.replaceAll('-', ' ')}: ${entry.value} attempts',
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
            'Use the Lessons button at the top to jump directly to any chapter, letter, or language (English, Hindi, Kannada).',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => setState(() => replayingOnboarding = true),
            icon: const Icon(Icons.replay),
            label: const Text('Replay Welcome to Resonant'),
          ),
          OutlinedButton.icon(
            onPressed: tts.stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop speaking'),
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
                      label: 'Braille dot $dot',
                      value: selectedDots.contains(dot)
                          ? 'selected'
                          : 'not selected',
                      button: true,
                      toggled: selectedDots.contains(dot),
                      onTap: () => toggleAccessibleDot(dot),
                      child: ExcludeSemantics(
                        child: Center(
                          child: SizedBox(
                            width: diameter,
                            height: diameter,
                            child: OutlinedButton(
                              onPressed: () => toggleAccessibleDot(dot),
                              style: OutlinedButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: EdgeInsets.zero,
                                backgroundColor: selectedDots.contains(dot)
                                    ? AppColors.primary
                                    : Colors.white,
                                foregroundColor: selectedDots.contains(dot)
                                    ? Colors.white
                                    : AppColors.primary,
                                side: const BorderSide(
                                  color: AppColors.accent,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '$dot',
                                style: TextStyle(
                                  fontSize: diameter * 0.43,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
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
        color: active || selected ? AppColors.primary : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        '$dot',
        style: TextStyle(
          fontSize: diameter * 0.43,
          fontWeight: FontWeight.bold,
          color: active || selected ? Colors.white : AppColors.primary,
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
          color: AppColors.keyboardBackdrop,
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
                              child: GestureDetector(
                                key: const ValueKey('braille-check-swipe-area'),
                                behavior: HitTestBehavior.opaque,
                                onPanStart: beginCheckSwipe,
                                onPanUpdate: updateCheckSwipe,
                                onPanEnd: finishCheckSwipe,
                                onPanCancel: () =>
                                    checkSwipeDistance = Offset.zero,
                                child: Semantics(
                                  liveRegion: true,
                                  label:
                                      '$message Current selection: $spokenDotLabel. Pattern $pattern. Swipe left, right, up, or down here to check this cell. ${widget.statusMessage ?? ''}',
                                  child: ExcludeSemantics(
                                    child: Text(
                                      '$message  •  Dots: $dotLabel  •  $pattern\nSwipe left, right, up, or down here to check',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.primaryTint,
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
                                          color: AppColors.primaryTint,
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
                            IconButton(
                              tooltip: accessibleDotControls
                                  ? 'Switch to touch keyboard'
                                  : 'Switch to accessible dot controls',
                              onPressed: () {
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
                              icon: const Icon(
                                Icons.accessibility,
                                color: Colors.white,
                              ),
                            ),
                            if (widget.onSubmitPattern != null)
                              if (width < 480 ||
                                  MediaQuery.textScalerOf(context).scale(14) >
                                      19)
                                IconButton(
                                  tooltip: 'Check pattern',
                                  onPressed: () =>
                                      widget.onSubmitPattern!(pattern),
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                FilledButton(
                                  onPressed: () =>
                                      widget.onSubmitPattern!(pattern),
                                  child: const Text('Check pattern'),
                                ),
                            if (widget.onBackspace != null)
                              IconButton(
                                tooltip: 'Backspace previous Braille cell',
                                onPressed: widget.onBackspace,
                                icon: const Icon(
                                  Icons.backspace_outlined,
                                  color: Colors.white,
                                ),
                              ),
                            IconButton(
                              tooltip: 'Hear Braille character',
                              onPressed: speakCurrentCell,
                              icon: const Icon(
                                Icons.volume_up,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Clear pattern',
                              onPressed: clearPattern,
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.white,
                              ),
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
    });

class WordChapterScreen extends StatefulWidget {
  final int initialLesson;
  final Map<int, StringSet> completedWords;
  final Future<void> Function(String) onSpeak;
  final VoidCallback onFeedback;
  final bool audioEnabled;
  final bool hapticsEnabled;
  final WordChapterAttemptHandler onAttempt;
  final ValueChanged<int> onLessonChanged;
  final VoidCallback onMasteryPassed;
  final VoidCallback? onTutor;

  const WordChapterScreen({
    super.key,
    required this.initialLesson,
    required this.completedWords,
    required this.onSpeak,
    required this.onFeedback,
    required this.audioEnabled,
    required this.hapticsEnabled,
    required this.onAttempt,
    required this.onLessonChanged,
    required this.onMasteryPassed,
    this.onTutor,
  });

  @override
  State<WordChapterScreen> createState() => _WordChapterScreenState();
}

class _WordChapterScreenState extends State<WordChapterScreen> {
  final GlobalKey<_BrailleKeyboardState> _keyboardKey =
      GlobalKey<_BrailleKeyboardState>();
  late int lessonIndex;
  late Map<int, StringSet> completedWords;
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
  late String groupId;
  late DateTime activityStarted;

  WordLearningLesson get lesson => LessonCatalog.wordLessons[lessonIndex];
  String get word => lesson.words[wordIndex];
  String get currentWordForTutor => word;
  List<int> get targetCells => EnglishGrade1Engine.encode(word);
  bool get writingLesson => lessonIndex == 2 || lessonIndex == 4;

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
    wordIndex = _firstIncompleteWord(lessonIndex);
    groupId = _newRoundId();
    activityStarted = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onSpeak(
          lessonIndex == 3
              ? '${lesson.title}. ${lesson.description} Explore the Braille cells and identify the word.'
              : lessonIndex == 2
              ? '${lesson.title}. ${lesson.description} Current word: $word. ${_cellDescription(0)}'
              : '${lesson.title}. ${lesson.description} Current word: $word.',
        );
      }
    });
  }

  String _newRoundId() =>
      'word-mastery-${DateTime.now().toUtc().microsecondsSinceEpoch}';

  int _firstIncompleteWord(int index) {
    final done = completedWords[index] ?? const <String>{};
    return lessonAt(index).words
        .indexWhere((entry) => !done.contains(entry))
        .clamp(0, lessonAt(index).words.length - 1);
  }

  WordLearningLesson lessonAt(int index) => LessonCatalog.wordLessons[index];

  void moveWord(int direction) {
    if (busy) return;
    final next = wordIndex + direction;
    if (next < 0 || next >= lesson.words.length) {
      widget.onSpeak(
        direction < 0
            ? 'This is the first word.'
            : 'This is the last word in this lesson.',
      );
      return;
    }
    if (direction > 0 &&
        !((completedWords[lessonIndex] ?? const <String>{}).contains(word))) {
      widget.onSpeak('Complete this word before moving on.');
      return;
    }
    setState(() {
      wordIndex = next;
      _resetWord();
    });
    widget.onFeedback();
    widget.onSpeak('Word ${wordIndex + 1} of ${lesson.words.length}: $word.');
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
    );
  }

  Future<void> _completeCurrentWord({required bool firstTryCorrect}) async {
    final completedThisAssessment = firstTryCorrect;
    await _persist(
      correct: lessonIndex == 4 ? completedThisAssessment : true,
      finalAttempt: true,
    );
    if (!mounted) return;

    if (lessonIndex == 4 && completedThisAssessment) {
      firstTryMasteryScore++;
    }
    final done = completedWords.putIfAbsent(lessonIndex, () => <String>{});
    if (lessonIndex < 4) done.add(word);

    if (wordIndex + 1 < lesson.words.length) {
      setState(() {
        wordIndex++;
        _resetWord();
        feedbackText = lessonIndex == 4
            ? 'Word complete. ${lesson.words.length - wordIndex - 1} words remain in this test.'
            : 'Word complete. Next: ${lesson.words[wordIndex]}.';
        feedbackCorrect = true;
      });
      widget.onFeedback();
      await widget.onSpeak(
        lessonIndex == 4
            ? 'Word complete. Next word: $word.'
            : 'Good work. Next word: $word.',
      );
      return;
    }

    if (lessonIndex == 4) {
      if (firstTryMasteryScore >= 4) {
        setState(() {
          done.addAll(lesson.words);
          feedbackText =
              'Mastery passed: $firstTryMasteryScore of 5 correct on the first try. The word chapter is complete.';
          feedbackCorrect = true;
        });
        widget.onMasteryPassed();
        widget.onFeedback();
        await widget.onSpeak(feedbackText!);
      } else {
        setState(() {
          masteryFailed = true;
          feedbackText =
              'You got $firstTryMasteryScore of 5 on the first try. Four correct are needed. Review the words and try the test again.';
          feedbackCorrect = false;
        });
        await widget.onSpeak(feedbackText!);
      }
      return;
    }

    final allComplete = lesson.words.every(done.contains);
    if (allComplete && lessonIndex < 4) {
      final nextLesson = lessonIndex + 1;
      setState(() {
        lessonIndex = nextLesson;
        wordIndex = _firstIncompleteWord(nextLesson);
        if (nextLesson == 4) groupId = _newRoundId();
        firstTryMasteryScore = 0;
        _resetWord();
      });
      widget.onLessonChanged(nextLesson);
      await widget.onSpeak(
        'Lesson complete. ${lesson.title}. Next: ${lessonAt(nextLesson).title}. ${lessonAt(nextLesson).description}',
      );
    }
  }

  Future<void> _markExplored() async {
    if (busy) return;
    setState(() => busy = true);
    attemptNumber++;
    await _completeCurrentWord(firstTryCorrect: true);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _chooseWord(String selected) async {
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
      await widget.onSpeak('Not quite. Listen again, or ask for a hint.');
      return;
    }
    setState(() {
      feedbackText = 'Correct. $word is spelled one cell per letter.';
      feedbackCorrect = true;
    });
    await _completeCurrentWord(firstTryCorrect: firstTry);
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
      await _persist(correct: false, finalAttempt: false);
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

  Future<void> _hint() async {
    hintUsed = true;
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
      'New mastery attempt. Write ${lesson.words.first}. Four of five words must be correct on the first try.',
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
        lessonIndex == 4 && completedWords[4]?.length == lesson.words.length;
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
                      '${lesson.title}. Word ${wordIndex + 1} of ${lesson.words.length}. $completed completed.',
                  child: Text(
                    '${lesson.title}  ·  Word ${wordIndex + 1} of ${lesson.words.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Text(
                '$completed/${lesson.words.length} complete',
                style: const TextStyle(color: AppColors.primaryTint),
              ),
              IconButton(
                tooltip: 'Repeat current lesson prompt',
                onPressed: () => widget.onSpeak(_repeatPrompt()),
                icon: const Icon(Icons.replay, color: Colors.white),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            lesson.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.primaryTint),
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
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (lessonIndex != 3)
                      OutlinedButton.icon(
                        onPressed: () => widget.onSpeak(
                          'The word is ${word.toLowerCase()}.',
                        ),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Hear the word'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onSpeak(
                        lessonIndex == 3
                            ? 'Braille cell sequence: ${_dotsText(targetCells)}.'
                            : '$word, letter by letter. ${_dotsText(targetCells)}.',
                      ),
                      icon: const Icon(Icons.hearing),
                      label: Text(
                        lessonIndex == 3
                            ? 'Hear Braille cells'
                            : 'Hear each cell',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _hint,
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Hear a hint'),
                    ),
                  ],
                ),
                if (lessonIndex == 0)
                  FilledButton(
                    onPressed: busy ? null : _markExplored,
                    child: const Text('I explored this word'),
                  ),
                if (lessonIndex == 1 || lessonIndex == 3) ...[
                  const SizedBox(height: 8),
                  Text(
                    lessonIndex == 1
                        ? 'Which word did you hear?'
                        : 'Which word do these Braille cells spell?',
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      for (final option in lesson.words)
                        OutlinedButton(
                          onPressed: busy ? null : () => _chooseWord(option),
                          child: Text(option),
                        ),
                    ],
                  ),
                ],
                if (lessonIndex == 4 && isMasteryPassed)
                  const Text('Word chapter complete. You may review any word.'),
                if (lessonIndex == 4 && masteryFailed)
                  FilledButton.icon(
                    onPressed: _retryMastery,
                    icon: const Icon(Icons.replay),
                    label: const Text('Retry mastery test'),
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
                            ? AppColors.accent
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

