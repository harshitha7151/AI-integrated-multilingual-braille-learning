import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/core/braille/english_grade1_engine.dart';
import 'package:resonant_braille/learning/word_assessment_validator.dart';

void main() {
  test('validates multi-cell English word in input order', () {
    final cells = 'CAT'
        .split('')
        .map(
          (character) =>
              EnglishGrade1Engine.encode(character.toLowerCase()).single,
        )
        .toList();

    final correct = WordAssessmentValidator.validate(
      target: 'CAT',
      language: AppLanguage.english,
      submittedCells: cells,
    );
    final reversed = WordAssessmentValidator.validate(
      target: 'CAT',
      language: AppLanguage.english,
      submittedCells: cells.reversed,
    );

    expect(correct.isCorrect, isTrue);
    expect(correct.expectedCells, cells);
    expect(correct.decodedEnglish?.toLowerCase(), 'cat');
    expect(reversed.isCorrect, isFalse);
    expect(reversed.firstDifferentCell, 0);
  });

  test('identifies missing and extra dots without revealing the answer', () {
    final expected = EnglishGrade1Engine.encode('c');
    final missingDotCell = expected.single & ~(1 << 0);
    final missing = WordAssessmentValidator.validate(
      target: 'C',
      language: AppLanguage.english,
      submittedCells: [missingDotCell],
    );
    final extra = WordAssessmentValidator.validate(
      target: 'C',
      language: AppLanguage.english,
      submittedCells: [expected.single | (1 << 5)],
    );

    expect(missing.errorKind, BrailleCellErrorKind.missingDots);
    expect(missing.missingDots, contains(1));
    expect(extra.errorKind, BrailleCellErrorKind.extraDots);
    expect(extra.extraDots, contains(6));
  });

  test('identifies missing and extra cells in a word', () {
    final cells = WordAssessmentValidator.expectedCells(
      'CAT',
      AppLanguage.english,
    );
    final missing = WordAssessmentValidator.validate(
      target: 'CAT',
      language: AppLanguage.english,
      submittedCells: cells.take(2),
    );
    final extra = WordAssessmentValidator.validate(
      target: 'CAT',
      language: AppLanguage.english,
      submittedCells: [...cells, cells.first],
    );
    expect(missing.errorKind, BrailleCellErrorKind.missingCell);
    expect(extra.errorKind, BrailleCellErrorKind.extraCell);
  });

  test(
    'selects different eligible English words containing the weak letter',
    () {
      final alternatives = WordAssessmentValidator.alternativeEnglishWords(
        failedWord: 'BAD',
        cellIndex: 1,
        candidates: ['BAD', 'CAB', 'BED', 'ACE'],
        excludedWords: {'bed'},
      );
      expect(alternatives, contains('CAB'));
      expect(alternatives, contains('ACE'));
      expect(alternatives, isNot(contains('BAD')));
      expect(alternatives, isNot(contains('BED')));
    },
  );

  test('uses the selected Bharati encoder for forward word validation', () {
    const word = 'ಅಮ್ಮ';
    final cells = BrailleDispatcher.encodeToBitmasks(word, AppLanguage.kannada);
    final result = WordAssessmentValidator.validate(
      target: word,
      language: AppLanguage.kannada,
      submittedCells: cells,
    );
    expect(result.isCorrect, isTrue);
    expect(result.expectedCells, cells);
    expect(result.decodedEnglish, isNull);
  });

  test('identifies only the incorrect English letter in a word', () {
    final expected = WordAssessmentValidator.expectedCells(
      'cat',
      AppLanguage.english,
    );
    final observations = WordAssessmentValidator.skillObservations(
      target: 'cat',
      language: AppLanguage.english,
      submittedCells: [expected[0], expected[1], expected[2] ^ 1],
    );

    expect(observations.map((item) => item['correct']), [true, true, false]);
    expect(observations.map((item) => item['skill_id']), [
      'english-letter-c',
      'english-letter-a',
      'english-letter-t',
    ]);
    expect(observations.last['expected_dots'], [
      BrailleDispatcher.dotsForBitmask(expected.last),
    ]);
    expect(observations.last['submitted_dots'], [
      BrailleDispatcher.dotsForBitmask(expected.last ^ 1),
    ]);
    expect(observations.last['error_category'], 'extra_dot');
  });

  test('identifies each incorrect character in a multi-error word', () {
    final expected = WordAssessmentValidator.expectedCells(
      'CAT',
      AppLanguage.english,
    );
    final observations = WordAssessmentValidator.skillObservations(
      target: 'CAT',
      language: AppLanguage.english,
      submittedCells: [expected[0] ^ 1, expected[1], expected[2] ^ (1 << 3)],
    );

    expect(observations.map((item) => item['correct']), [false, true, false]);
    expect(
      observations
          .where((item) => item['correct'] == false)
          .map((item) => item['character']),
      ['C', 'T'],
    );
    expect(observations.first['submitted_cells'], [expected[0] ^ 1]);
    expect(observations.last['submitted_cells'], [expected[2] ^ (1 << 3)]);
  });

  test('preserves engine conjunct units and all their cells', () {
    for (final entry in <(String, AppLanguage)>[
      ('त्र', AppLanguage.hindi),
      ('ಜ್ಞ', AppLanguage.kannada),
    ]) {
      final expected = WordAssessmentValidator.expectedCells(
        entry.$1,
        entry.$2,
      );
      final observations = WordAssessmentValidator.skillObservations(
        target: entry.$1,
        language: entry.$2,
        submittedCells: expected,
      );
      expect(observations, hasLength(1));
      expect(observations.single['character'], entry.$1);
      expect(observations.single['correct'], isTrue);
      expect(observations.single['cell_count'], expected.length);
    }
  });

  test('missing cell does not mark aligned following letters incorrect', () {
    final expected = WordAssessmentValidator.expectedCells(
      'cat',
      AppLanguage.english,
    );
    final observations = WordAssessmentValidator.skillObservations(
      target: 'cat',
      language: AppLanguage.english,
      submittedCells: [expected[0], expected[2]],
    );
    expect(observations.map((item) => item['correct']), [true, false, true]);
  });
}
