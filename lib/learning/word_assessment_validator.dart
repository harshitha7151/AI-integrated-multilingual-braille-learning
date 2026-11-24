import '../core/braille/braille_dispatcher.dart';
import '../core/braille/english_grade1_engine.dart';

enum BrailleCellErrorKind {
  missingCell,
  extraCell,
  missingDots,
  extraDots,
  mixedDots,
}

class WordAssessmentValidation {
  final String target;
  final List<int> expectedCells;
  final List<int> submittedCells;
  final int? firstDifferentCell;
  final List<int> missingDots;
  final List<int> extraDots;
  final BrailleCellErrorKind? errorKind;
  final String? decodedEnglish;

  const WordAssessmentValidation({
    required this.target,
    required this.expectedCells,
    required this.submittedCells,
    required this.firstDifferentCell,
    required this.missingDots,
    required this.extraDots,
    required this.errorKind,
    required this.decodedEnglish,
  });

  bool get isCorrect =>
      errorKind == null && expectedCells.length == submittedCells.length;
}

/// Validates ordered multi-cell responses against deterministic language
/// encoders. English course assessments ask for letter cells without requiring
/// a capitalization indicator; Bharati content uses the engine's exact cells.
class WordAssessmentValidator {
  const WordAssessmentValidator._();

  static List<int> expectedCells(String word, AppLanguage language) {
    if (language == AppLanguage.english) {
      return [
        for (final character in word.runes)
          ...EnglishGrade1Engine.encode(
            String.fromCharCode(character).toLowerCase(),
          ),
      ];
    }
    return BrailleDispatcher.encodeToBitmasks(word, language);
  }

  /// Compares each engine-segmented character/conjunct with the entered cell
  /// stream. Matching cells are aligned by sequence so a missing cell does
  /// not incorrectly mark every following character as wrong.
  static List<Map<String, dynamic>> skillObservations({
    required String target,
    required AppLanguage language,
    required Iterable<int> submittedCells,
  }) {
    final units = BrailleDispatcher.encodeUnits(target, language);
    final submitted = submittedCells.toList(growable: false);
    final expected = [for (final unit in units) ...unit.cells];
    final rows = List<List<int>>.generate(
      expected.length + 1,
      (_) => List<int>.filled(submitted.length + 1, 0),
    );
    for (var i = expected.length - 1; i >= 0; i--) {
      for (var j = submitted.length - 1; j >= 0; j--) {
        rows[i][j] = expected[i] == submitted[j]
            ? rows[i + 1][j + 1] + 1
            : (rows[i + 1][j] > rows[i][j + 1]
                  ? rows[i + 1][j]
                  : rows[i][j + 1]);
      }
    }
    final matchedExpected = <int>{};
    var expectedIndex = 0;
    var submittedIndex = 0;
    while (expectedIndex < expected.length &&
        submittedIndex < submitted.length) {
      if (expected[expectedIndex] == submitted[submittedIndex]) {
        matchedExpected.add(expectedIndex++);
        submittedIndex++;
      } else if (rows[expectedIndex + 1][submittedIndex] >=
          rows[expectedIndex][submittedIndex + 1]) {
        expectedIndex++;
      } else {
        submittedIndex++;
      }
    }

    var offset = 0;
    return [
      for (final unit in units)
        () {
          final start = offset;
          offset += unit.cells.length;
          final correct = List<int>.generate(
            unit.cells.length,
            (index) => start + index,
          ).every(matchedExpected.contains);
          return {
            'character': unit.text,
            'skill_id': _skillId(unit.text, language),
            'correct': correct,
            'cell_start': start,
            'cell_count': unit.cells.length,
            'expected_cells': List<int>.unmodifiable(unit.cells),
            'submitted_cells': List<int>.unmodifiable([
              for (
                var index = start;
                index < start + unit.cells.length && index < submitted.length;
                index++
              )
                submitted[index],
            ]),
            'expected_dots': [
              for (final cell in unit.cells)
                BrailleDispatcher.dotsForBitmask(cell),
            ],
            'submitted_dots': [
              for (
                var index = start;
                index < start + unit.cells.length && index < submitted.length;
                index++
              )
                BrailleDispatcher.dotsForBitmask(submitted[index]),
            ],
            'error_category': correct
                ? 'correct'
                : _unitErrorCategory(
                    unit.cells,
                    submitted.skip(start).take(unit.cells.length).toList(),
                  ),
          };
        }(),
    ];
  }

  static String _unitErrorCategory(List<int> expected, List<int> submitted) {
    if (submitted.length < expected.length) return 'missing_cell';
    if (submitted.length > expected.length) return 'extra_cell';
    var missing = 0;
    var extra = 0;
    for (var index = 0; index < expected.length; index++) {
      final expectedDots = BrailleDispatcher.dotsForBitmask(expected[index]);
      final submittedDots = BrailleDispatcher.dotsForBitmask(submitted[index]);
      missing += expectedDots
          .where((dot) => !submittedDots.contains(dot))
          .length;
      extra += submittedDots.where((dot) => !expectedDots.contains(dot)).length;
    }
    if (missing == 1 && extra == 0) return 'missing_dot';
    if (extra == 1 && missing == 0) return 'extra_dot';
    if (missing == 1 && extra == 1) return 'dot_substitution';
    if (missing + extra > 0) return 'multiple_dot_error';
    return 'cell_order';
  }

  static String _skillId(String text, AppLanguage language) {
    final normalized = language == AppLanguage.english
        ? text.toLowerCase()
        : text;
    final prefix = switch (language) {
      AppLanguage.english => 'english-letter-',
      AppLanguage.hindi => 'hi-bharati-',
      AppLanguage.kannada => 'kn-bharati-',
    };
    return '$prefix$normalized';
  }

  /// Returns different unfinished words that repeat the English letter at the
  /// failed cell. English assessment cells are one per ASCII letter.
  static List<String> alternativeEnglishWords({
    required String failedWord,
    required int cellIndex,
    required Iterable<String> candidates,
    required Set<String> excludedWords,
  }) {
    if (cellIndex < 0 || cellIndex >= failedWord.length) return const [];
    final target = failedWord[cellIndex].toLowerCase();
    return List.unmodifiable(
      candidates.where(
        (word) =>
            word.toLowerCase() != failedWord.toLowerCase() &&
            !excludedWords.contains(word.toLowerCase()) &&
            word.toLowerCase().contains(target),
      ),
    );
  }

  static WordAssessmentValidation validate({
    required String target,
    required AppLanguage language,
    required Iterable<int> submittedCells,
  }) {
    final expected = expectedCells(target, language);
    final submitted = List<int>.unmodifiable(submittedCells);
    int? firstDifferent;
    var missing = <int>[];
    var extra = <int>[];
    BrailleCellErrorKind? kind;

    final sharedLength = expected.length < submitted.length
        ? expected.length
        : submitted.length;
    for (var index = 0; index < sharedLength; index++) {
      if (expected[index] == submitted[index]) continue;
      firstDifferent = index;
      final expectedDots = BrailleDispatcher.dotsForBitmask(expected[index]);
      final submittedDots = BrailleDispatcher.dotsForBitmask(submitted[index]);
      missing = expectedDots
          .where((dot) => !submittedDots.contains(dot))
          .toList();
      extra = submittedDots
          .where((dot) => !expectedDots.contains(dot))
          .toList();
      kind = missing.isNotEmpty && extra.isEmpty
          ? BrailleCellErrorKind.missingDots
          : extra.isNotEmpty && missing.isEmpty
          ? BrailleCellErrorKind.extraDots
          : BrailleCellErrorKind.mixedDots;
      break;
    }
    if (kind == null && expected.length != submitted.length) {
      firstDifferent = sharedLength;
      kind = submitted.length < expected.length
          ? BrailleCellErrorKind.missingCell
          : BrailleCellErrorKind.extraCell;
    }

    String? decoded;
    if (language == AppLanguage.english) {
      try {
        decoded = EnglishGrade1Engine.decode(submitted);
      } on Object {
        decoded = null;
      }
    }
    return WordAssessmentValidation(
      target: target,
      expectedCells: List.unmodifiable(expected),
      submittedCells: submitted,
      firstDifferentCell: firstDifferent,
      missingDots: List.unmodifiable(missing),
      extraDots: List.unmodifiable(extra),
      errorKind: kind,
      decodedEnglish: decoded,
    );
  }
}
