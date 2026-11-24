import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';
import 'package:resonant_braille/core/braille/english_grade1_engine.dart';

void main() {
  test('lesson questions have a valid answer and unique skill identifiers', () {
    final exercises = LessonCatalog.english
        .expand((chapter) => chapter.exercises)
        .toList();
    final skillIds = exercises.map((exercise) => exercise.skillId).toSet();

    expect(exercises, isNotEmpty);
    expect(skillIds.length, exercises.length);
    for (final exercise in exercises) {
      expect(exercise.options, contains(exercise.answer));
      expect(exercise.isCorrect(exercise.answer), isTrue);
      expect(
        exercise.options
            .where((option) => option != exercise.answer)
            .every((option) => !exercise.isCorrect(option)),
        isTrue,
      );
    }
  });

  test(
    'curriculum defines the required letter groups and valid stage words',
    () {
      expect(LessonCatalog.curriculum.map((stage) => stage.title), [
        'Letters A through E',
        'Letters F through J',
        'Letters K through O',
        'Letters P through T',
        'Letters U through Z',
      ]);
      expect(LessonCatalog.alphabet.join(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
      expect(
        LessonCatalog.curriculum.map((stage) => [stage.first, stage.last]),
        [
          [0, 4],
          [5, 9],
          [10, 14],
          [15, 19],
          [20, 25],
        ],
      );
      for (final stage in LessonCatalog.curriculum) {
        for (final word in stage.words) {
          expect(
            stage.allows(word),
            isTrue,
            reason: '$word must use ${stage.allowedLetters}',
          );
          expect(
            EnglishGrade1Engine.decode(EnglishGrade1Engine.encode(word)),
            word,
          );
        }
      }
      expect(
        LessonCatalog.curriculum.first.words,
        containsAll(['BAD', 'CAB', 'BED', 'ACE', 'DECADE']),
      );
      expect(LessonCatalog.cumulativeWords.map((word) => word.length), [
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(
        LessonCatalog.cumulativeWords.every(
          (word) =>
              LessonCatalog.wordUsesOnly(word, 'abcdefghijklmnopqrstuvwxyz'),
        ),
        isTrue,
      );
    },
  );

  test(
    'English word chapter has five ordered lessons and stable unique exercises',
    () {
      expect(LessonCatalog.english, hasLength(5));
      expect(LessonCatalog.english[2].title, 'Chapter 3: English Words');
      expect(LessonCatalog.wordLessons.map((lesson) => lesson.title), [
        'Lesson 1: Build your first words',
        'Lesson 2: Read familiar words',
        'Lesson 3: Write the word',
        'Lesson 4: Read and identify',
        'Lesson 5: Word mastery test',
      ]);
      expect(LessonCatalog.wordLessons.first.words, ['CAT', 'BAT', 'MAT']);
      expect(LessonCatalog.wordLessons[1].words, ['SUN', 'DOG', 'HAT', 'PEN']);
      final chapterExercises = LessonCatalog.english[2].exercises;
      expect(
        chapterExercises.map((exercise) => exercise.id).toSet().length,
        chapterExercises.length,
      );
      for (final lesson in LessonCatalog.wordLessons) {
        for (final word in lesson.words) {
          expect(
            EnglishGrade1Engine.decode(EnglishGrade1Engine.encode(word)),
            word,
          );
        }
      }
    },
  );

  test('phrase and sentence content is engine-valid in every language', () {
    for (final language in AppLanguage.values) {
      final chapters = LessonCatalog.chaptersFor(language);
      expect(chapters, hasLength(5));
      for (final exercise
          in chapters.skip(3).expand((chapter) => chapter.exercises)) {
        expect(exercise.isComposedResponse, isTrue);
        expect(exercise.validationStatus, 'mapping_verified_authored_content');
        expect(
          () => BrailleDispatcher.encodeToBitmasks(exercise.answer, language),
          returnsNormally,
          reason: '${language.storageName}: ${exercise.answer}',
        );
        expect(
          BrailleDispatcher.encodeToBitmasks(exercise.answer, language),
          isNotEmpty,
        );
      }
    }
  });

  test('Hindi and Kannada character lessons describe every ordered Braille cell', () {
    final cases = [
      (AppLanguage.hindi, 'अ', 1),
      (AppLanguage.hindi, 'ऋ', 2),
      (AppLanguage.hindi, 'त्र', 3),
      (AppLanguage.kannada, 'ಅ', 1),
      (AppLanguage.kannada, 'ಋ', 2),
    ];

    for (final (language, character, expectedCellCount) in cases) {
      final exercise = LessonCatalog.chaptersFor(language)[1].exercises
          .singleWhere((item) => item.answer == character);
      final cells = BrailleDispatcher.encodeToBitmasks(character, language);
      expect(cells, hasLength(expectedCellCount), reason: '$character mapping');

      final cellDescriptions = [
        for (var index = 0; index < cells.length; index++)
          language == AppLanguage.hindi
              ? 'सेल ${index + 1}: बिंदु ${BrailleDispatcher.dotsForBitmask(cells[index]).join(', ')}'
              : 'ಕೋಶ ${index + 1}: ಚುಕ್ಕೆ ${BrailleDispatcher.dotsForBitmask(cells[index]).join(', ')}',
      ];
      for (final text in [exercise.prompt, exercise.hint, exercise.explanation]) {
        for (final cell in cellDescriptions) {
          expect(text, contains(cell), reason: '$character: $text');
        }
      }

      if (expectedCellCount == 1) {
        expect(exercise.prompt, isNot(contains('सेल 2:')));
        expect(exercise.prompt, isNot(contains('ಕೋಶ 2:')));
      }
    }
  });

  test('personalized name sentences fail closed to an encodable fallback', () {
    final english = LessonCatalog.english[4].exercises.first;
    expect(
      english.resolvedAnswer(AppLanguage.english, learnerName: 'Namit'),
      'My name is Namit.',
    );
    final hindi = LessonCatalog.hindi[4].exercises.first;
    expect(
      hindi.resolvedAnswer(AppLanguage.hindi, learnerName: 'Unsupported Latin'),
      hindi.answer,
    );
  });
}
