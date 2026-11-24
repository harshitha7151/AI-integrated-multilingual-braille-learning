import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/learning/chapter_navigation_controller.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';

void main() {
  const controller = ChapterNavigationController();

  LearningNavigationContext context({
    AppLanguage language = AppLanguage.english,
    int chapter = 1,
    int lesson = 0,
    int wordChapter = 0,
    bool letterCourseComplete = false,
    bool wordCourseComplete = false,
    Map<int, Set<String>> completedWords = const {},
    Set<String> completedWordStages = const {},
    Set<String> completedLessons = const {},
  }) => LearningNavigationContext(
    language: language,
    chapterIndex: chapter,
    lessonIndex: lesson,
    wordChapterIndex: wordChapter,
    englishLetterCourseComplete: letterCourseComplete,
    englishWordCourseComplete: wordCourseComplete,
    completedWordChapterWords: completedWords,
    completedWordAssessmentStageIds: completedWordStages,
    completedLessonExerciseIds: completedLessons,
  );

  test('explicit chapter navigation is separate from completion state', () {
    final result = controller.nextChapter(context());
    expect(result.isResolved, isTrue);
    expect(result.chapterIndex, 2);
    expect(result.wordChapterIndex, 0);
    expect(context().englishLetterCourseComplete, isFalse);
  });

  test('keeps chapter navigation inside the English Words module', () {
    final completed = {0: LessonCatalog.wordLessons[0].words.toSet()};
    final result = controller.nextChapter(
      context(
        chapter: 2,
        letterCourseComplete: true,
        completedWords: completed,
      ),
    );
    expect(result.isResolved, isTrue);
    expect(result.chapterIndex, 2);
    expect(result.wordChapterIndex, 1);
    expect(result.message, contains('English Words, Chapter 2'));
  });

  test(
    'explicit navigation can open a later word lesson without completion',
    () {
      final result = controller.goToChapter(
        context(chapter: 2, letterCourseComplete: true),
        '3',
      );
      expect(result.isResolved, isTrue);
      expect(result.wordChapterIndex, 2);
    },
  );

  test('resolves a named letter lesson and reports safe boundaries', () {
    final letter = controller.goToLesson(
      context(completedLessons: const {'letter-a'}),
      'b',
    );
    expect(letter.isResolved, isTrue);
    expect(letter.chapterIndex, 1);
    expect(letter.lessonIndex, 1);

    final boundary = controller.previousChapter(context(chapter: 0));
    expect(boundary.status, NavigationResolutionStatus.blocked);
    expect(boundary.message, contains('first chapter'));
  });

  test('named lesson navigation does not falsely complete prerequisites', () {
    final before = context();
    final result = controller.goToLesson(before, 'c');
    expect(result.isResolved, isTrue);
    expect(result.lessonIndex, 2);
    expect(before.completedLessonExerciseIds, isEmpty);
  });

  test(
    'category navigation resolves word and alphabet modules per language',
    () {
      for (final language in AppLanguage.values) {
        final alphabet = controller.goToChapter(
          context(language: language),
          'alphabet',
        );
        final words = controller.goToChapter(
          context(language: language),
          'words',
        );
        expect(alphabet.isResolved, isTrue, reason: language.name);
        expect(alphabet.chapterIndex, 1, reason: language.name);
        expect(words.isResolved, isTrue, reason: language.name);
        expect(words.chapterIndex, 2, reason: language.name);
      }
    },
  );

  test('explicit navigation to phrase and sentence chapters is available', () {
    final phraseBlocked = controller.goToChapter(
      context(chapter: 2, wordChapter: 4, letterCourseComplete: true),
      'English Phrases',
    );
    expect(phraseBlocked.isResolved, isTrue);

    final phraseReady = controller.goToChapter(
      context(
        chapter: 2,
        wordChapter: 4,
        letterCourseComplete: true,
        wordCourseComplete: true,
      ),
      'English Phrases',
    );
    expect(phraseReady.isResolved, isTrue);
    expect(phraseReady.chapterIndex, 3);

    final sentenceBlocked = controller.goToChapter(
      context(chapter: 3, letterCourseComplete: true, wordCourseComplete: true),
      'English Sentences',
    );
    expect(sentenceBlocked.isResolved, isTrue);

    final sentenceReady = controller.goToChapter(
      context(
        chapter: 3,
        letterCourseComplete: true,
        wordCourseComplete: true,
        completedLessons: LessonCatalog.english[3].exercises
            .map((exercise) => exercise.id)
            .toSet(),
      ),
      'English Sentences',
    );
    expect(sentenceReady.isResolved, isTrue);
    expect(sentenceReady.chapterIndex, 4);
  });

  test(
    'named writing lesson can be opened without recording earlier completion',
    () {
      final phrases = LessonCatalog.english[3].exercises;
      final sentences = LessonCatalog.english[4].exercises;
      final phraseIds = phrases.map((exercise) => exercise.id).toSet();

      final secondPhraseBlocked = controller.goToLesson(
        context(
          chapter: 3,
          letterCourseComplete: true,
          wordCourseComplete: true,
        ),
        phrases[1].id,
      );
      expect(secondPhraseBlocked.isResolved, isTrue);

      final secondSentenceBlocked = controller.goToLesson(
        context(
          chapter: 4,
          letterCourseComplete: true,
          wordCourseComplete: true,
          completedLessons: phraseIds,
        ),
        sentences[1].id,
      );
      expect(secondSentenceBlocked.isResolved, isTrue);

      final secondSentenceReady = controller.goToLesson(
        context(
          chapter: 4,
          letterCourseComplete: true,
          wordCourseComplete: true,
          completedLessons: {...phraseIds, sentences.first.id},
        ),
        sentences[1].id,
      );
      expect(secondSentenceReady.isResolved, isTrue);
      expect(secondSentenceReady.lessonIndex, 1);
    },
  );
}
