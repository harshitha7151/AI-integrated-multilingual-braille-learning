import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/learning/paused_word_assessment.dart';

void main() {
  test(
    'pause metadata survives serialization without losing assessment state',
    () {
      const paused = PausedWordAssessment(
        assessmentSubmissionId: 'attempt-1',
        stageId: 'a-e',
        language: 'en',
        wordIndex: 0,
        word: 'BAD',
        cumulative: false,
        lessonItem: 4,
        letter: 'd',
        letterLessonIndex: 3,
        nextWordIndex: 2,
        remediationAttempts: 1,
      );

      final restored = PausedWordAssessment.fromJson(paused.toJson());
      expect(restored?.assessmentSubmissionId, 'attempt-1');
      expect(restored?.stageId, 'a-e');
      expect(restored?.word, 'BAD');
      expect(restored?.lessonItem, 4);
      expect(restored?.letter, 'd');
      expect(restored?.nextWordIndex, 2);
      expect(restored?.remediationAttempts, 1);
    },
  );

  test('resumes on another incomplete word and retries failed word last', () {
    expect(
      PausedWordAssessment.nextUncompletedWord(
        failedIndex: 1,
        wordCount: 4,
        completedIndices: const {0},
      ),
      2,
    );
    expect(
      PausedWordAssessment.nextUncompletedWord(
        failedIndex: 1,
        wordCount: 3,
        completedIndices: const {0, 2},
      ),
      1,
    );
  });

  test('rejects malformed saved remediation rather than guessing', () {
    expect(PausedWordAssessment.fromJson({'word': 'CAT'}), isNull);
  });
}
