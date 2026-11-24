import '../core/braille/braille_dispatcher.dart';
import 'lesson_catalog.dart';

enum NavigationResolutionStatus {
  resolved,
  blocked,
  notFound,
  needsClarification,
}

class LearningNavigationContext {
  final AppLanguage language;
  final int chapterIndex;
  final int lessonIndex;
  final int wordChapterIndex;
  final bool englishLetterCourseComplete;
  final bool englishWordCourseComplete;
  final Map<int, Set<String>> completedWordChapterWords;
  final Set<String> completedWordAssessmentStageIds;
  final Set<String> completedLessonExerciseIds;

  const LearningNavigationContext({
    required this.language,
    required this.chapterIndex,
    required this.lessonIndex,
    required this.wordChapterIndex,
    required this.englishLetterCourseComplete,
    this.englishWordCourseComplete = false,
    this.completedWordChapterWords = const {},
    this.completedWordAssessmentStageIds = const {},
    this.completedLessonExerciseIds = const {},
  });
}

class NavigationResolution {
  final NavigationResolutionStatus status;
  final String message;
  final int? chapterIndex;
  final int? lessonIndex;
  final int? wordChapterIndex;

  const NavigationResolution({
    required this.status,
    required this.message,
    this.chapterIndex,
    this.lessonIndex,
    this.wordChapterIndex,
  });

  bool get isResolved => status == NavigationResolutionStatus.resolved;
}

/// Resolves curriculum navigation without mutating Flutter state.
///
/// The caller remains responsible for applying a resolved destination and for
/// persisting resume state. This prevents an unvalidated tutor response from
/// manipulating navigation directly.
class ChapterNavigationController {
  const ChapterNavigationController();

  NavigationResolution nextChapter(LearningNavigationContext context) {
    if (_insideEnglishWords(context)) {
      if (context.wordChapterIndex == LessonCatalog.wordLessons.length - 1) {
        return _topLevelChapter(context, context.chapterIndex + 1);
      }
      return _wordChapter(context, context.wordChapterIndex + 1);
    }
    return _topLevelChapter(context, context.chapterIndex + 1);
  }

  NavigationResolution previousChapter(LearningNavigationContext context) {
    if (_insideEnglishWords(context)) {
      if (context.wordChapterIndex == 0) {
        return _topLevelChapter(context, context.chapterIndex - 1);
      }
      return _wordChapter(context, context.wordChapterIndex - 1);
    }
    return _topLevelChapter(context, context.chapterIndex - 1);
  }

  NavigationResolution beginningOfModule(LearningNavigationContext context) {
    if (_insideEnglishWords(context)) {
      return NavigationResolution(
        status: NavigationResolutionStatus.resolved,
        message: _wordAnnouncement(0),
        chapterIndex: context.chapterIndex,
        wordChapterIndex: 0,
      );
    }
    final chapters = LessonCatalog.chaptersFor(context.language);
    return NavigationResolution(
      status: NavigationResolutionStatus.resolved,
      message: '${chapters[context.chapterIndex].title}. First lesson.',
      chapterIndex: context.chapterIndex,
      lessonIndex: 0,
    );
  }

  NavigationResolution goToChapter(
    LearningNavigationContext context,
    String? target,
  ) {
    final query = _normalize(target ?? '');
    if (query.isEmpty) {
      return const NavigationResolution(
        status: NavigationResolutionStatus.needsClarification,
        message: 'Which chapter should I open?',
      );
    }

    if (_insideEnglishWords(context)) {
      final wordMatch = _matchWordChapter(query);
      if (wordMatch != null) return _wordChapter(context, wordMatch);
    }

    final chapters = LessonCatalog.chaptersFor(context.language);
    if (_isAlphabetModuleQuery(query) && chapters.length > 1) {
      return _topLevelChapter(context, 1);
    }
    if (_isWordModuleQuery(query) && chapters.length > 2) {
      return _topLevelChapter(context, 2);
    }
    final number = _oneBasedNumber(query);
    if (number != null && number <= chapters.length) {
      return _topLevelChapter(context, number - 1);
    }
    final matches = <int>[
      for (var index = 0; index < chapters.length; index++)
        if (_matches(query, chapters[index].title)) index,
    ];
    if (matches.length == 1) return _topLevelChapter(context, matches.single);
    if (matches.length > 1) {
      return const NavigationResolution(
        status: NavigationResolutionStatus.needsClarification,
        message:
            'More than one chapter matches. Please say its chapter number.',
      );
    }
    return NavigationResolution(
      status: NavigationResolutionStatus.notFound,
      message:
          'I could not find a chapter named $target in the current language.',
    );
  }

  NavigationResolution goToLesson(
    LearningNavigationContext context,
    String? target,
  ) {
    final query = _normalize(target ?? '');
    if (query.isEmpty) {
      return const NavigationResolution(
        status: NavigationResolutionStatus.needsClarification,
        message: 'Which lesson should I open?',
      );
    }

    if (_insideEnglishWords(context)) {
      final wordMatch = _matchWordChapter(query);
      if (wordMatch != null) return _wordChapter(context, wordMatch);
    }

    final chapters = LessonCatalog.chaptersFor(context.language);
    final exactMatches = <({int chapter, int lesson})>[];
    final fuzzyMatches = <({int chapter, int lesson})>[];
    for (var chapter = 0; chapter < chapters.length; chapter++) {
      for (
        var lesson = 0;
        lesson < chapters[chapter].exercises.length;
        lesson++
      ) {
        final exercise = chapters[chapter].exercises[lesson];
        final normalizedId = _normalize(exercise.id);
        final normalizedAnswer = _normalize(exercise.answer);
        if (normalizedAnswer == query ||
            normalizedId == query ||
            normalizedId.split(' ').last == query) {
          exactMatches.add((chapter: chapter, lesson: lesson));
        } else if (query.length >= 3 &&
            (_matches(query, exercise.id) ||
                _matches(query, exercise.answer) ||
                _matches(query, exercise.prompt))) {
          fuzzyMatches.add((chapter: chapter, lesson: lesson));
        }
      }
    }
    final matches = exactMatches.isNotEmpty ? exactMatches : fuzzyMatches;
    if (matches.length == 1) {
      final match = matches.single;
      final chapterResolution = _topLevelChapter(context, match.chapter);
      if (!chapterResolution.isResolved) return chapterResolution;
      return NavigationResolution(
        status: NavigationResolutionStatus.resolved,
        message:
            '${chapters[match.chapter].title}. ${chapters[match.chapter].exercises[match.lesson].prompt}',
        chapterIndex: match.chapter,
        lessonIndex: match.lesson,
      );
    }
    if (matches.length > 1) {
      return const NavigationResolution(
        status: NavigationResolutionStatus.needsClarification,
        message:
            'More than one lesson matches. Please name the letter, word, or lesson more precisely.',
      );
    }
    return NavigationResolution(
      status: NavigationResolutionStatus.notFound,
      message:
          'I could not find a lesson named $target in the current language.',
    );
  }

  NavigationResolution _topLevelChapter(
    LearningNavigationContext context,
    int target,
  ) {
    final chapters = LessonCatalog.chaptersFor(context.language);
    if (target < 0 || target >= chapters.length) {
      return NavigationResolution(
        status: NavigationResolutionStatus.blocked,
        message: target < 0
            ? 'You are at the first chapter in this language.'
            : 'You are at the last chapter in this language.',
      );
    }
    return NavigationResolution(
      status: NavigationResolutionStatus.resolved,
      message: chapters[target].title,
      chapterIndex: target,
      lessonIndex: 0,
      wordChapterIndex: context.language == AppLanguage.english && target == 2
          ? 0
          : null,
    );
  }

  NavigationResolution _wordChapter(
    LearningNavigationContext context,
    int target,
  ) {
    if (target < 0 || target >= LessonCatalog.wordLessons.length) {
      return NavigationResolution(
        status: NavigationResolutionStatus.blocked,
        message: target < 0
            ? 'You are at the first chapter in the Words module.'
            : 'You are at the last chapter in the Words module.',
      );
    }
    return NavigationResolution(
      status: NavigationResolutionStatus.resolved,
      message: _wordAnnouncement(target),
      chapterIndex: 2,
      wordChapterIndex: target,
    );
  }

  int? _matchWordChapter(String query) {
    final number = _oneBasedNumber(query);
    if (number != null && number <= LessonCatalog.wordLessons.length) {
      return number - 1;
    }
    final matches = <int>[
      for (var index = 0; index < LessonCatalog.wordLessons.length; index++)
        if (_matches(query, LessonCatalog.wordLessons[index].title) ||
            _matches(query, LessonCatalog.wordLessons[index].id))
          index,
    ];
    return matches.length == 1 ? matches.single : null;
  }

  bool _insideEnglishWords(LearningNavigationContext context) =>
      context.language == AppLanguage.english && context.chapterIndex == 2;

  String _wordAnnouncement(int index) {
    final lesson = LessonCatalog.wordLessons[index];
    return 'English Words, Chapter ${index + 1}. ${lesson.title}.';
  }

  int? _oneBasedNumber(String value) {
    final match = RegExp(r'\b(\d+)\b').firstMatch(value);
    final number = match == null ? null : int.tryParse(match.group(1)!);
    return number != null && number > 0 ? number : null;
  }

  bool _matches(String query, String candidate) {
    final normalizedCandidate = _normalize(candidate);
    return normalizedCandidate == query || normalizedCandidate.contains(query);
  }

  bool _isAlphabetModuleQuery(String query) =>
      RegExp(r'\b(?:letters?|alphabet|characters?)\b').hasMatch(query) ||
      query.contains('वर्णमाला') ||
      query.contains('ಅಕ್ಷರಮಾಲೆ') ||
      query.contains('ವರ್ಣಮಾಲೆ');

  bool _isWordModuleQuery(String query) =>
      RegExp(r'\b(?:words?|vocabulary)\b').hasMatch(query) ||
      query.contains('शब्द') ||
      query.contains('ಪದ');

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097f\u0c80-\u0cff]+'), ' ')
      .replaceAll(RegExp(r'\b(?:go|to|the|named|chapter|lesson)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
