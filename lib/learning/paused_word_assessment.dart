/// Local resume metadata for a word assessment paused for letter remediation.
/// Attempt content remains in the normal progress-attempt log.
class PausedWordAssessment {
  const PausedWordAssessment({
    required this.assessmentSubmissionId,
    required this.stageId,
    required this.language,
    required this.wordIndex,
    required this.word,
    required this.cumulative,
    required this.lessonItem,
    required this.letter,
    required this.letterLessonIndex,
    required this.nextWordIndex,
    this.remediationAttempts = 0,
  });

  final String assessmentSubmissionId;
  final String stageId;
  final String language;
  final int wordIndex;
  final String word;
  final bool cumulative;
  final int lessonItem;
  final String letter;
  final int letterLessonIndex;
  final int nextWordIndex;
  final int remediationAttempts;

  static int nextUncompletedWord({
    required int failedIndex,
    required int wordCount,
    required Set<int> completedIndices,
  }) {
    if (wordCount <= 0 || failedIndex < 0 || failedIndex >= wordCount) {
      return -1;
    }
    for (var step = 1; step < wordCount; step++) {
      final candidate = (failedIndex + step) % wordCount;
      if (candidate != failedIndex && !completedIndices.contains(candidate)) {
        return candidate;
      }
    }
    return failedIndex;
  }

  PausedWordAssessment copyWith({int? remediationAttempts}) =>
      PausedWordAssessment(
        assessmentSubmissionId: assessmentSubmissionId,
        stageId: stageId,
        language: language,
        wordIndex: wordIndex,
        word: word,
        cumulative: cumulative,
        lessonItem: lessonItem,
        letter: letter,
        letterLessonIndex: letterLessonIndex,
        nextWordIndex: nextWordIndex,
        remediationAttempts: remediationAttempts ?? this.remediationAttempts,
      );

  Map<String, dynamic> toJson() => {
    'assessment_submission_id': assessmentSubmissionId,
    'stage_id': stageId,
    'language': language,
    'word_index': wordIndex,
    'word': word,
    'cumulative': cumulative,
    'lesson_item': lessonItem,
    'letter': letter,
    'letter_lesson_index': letterLessonIndex,
    'next_word_index': nextWordIndex,
    'remediation_attempts': remediationAttempts,
  };

  static PausedWordAssessment? fromJson(Object? value) {
    if (value is! Map) return null;
    final data = Map<String, dynamic>.from(value);
    final id = data['assessment_submission_id'];
    final stage = data['stage_id'];
    final language = data['language'];
    final word = data['word'];
    final letter = data['letter'];
    final wordIndex = data['word_index'];
    final lessonItem = data['lesson_item'];
    final letterIndex = data['letter_lesson_index'];
    final nextIndex = data['next_word_index'];
    if (id is! String ||
        id.isEmpty ||
        stage is! String ||
        stage.isEmpty ||
        language is! String ||
        word is! String ||
        word.isEmpty ||
        letter is! String ||
        letter.isEmpty ||
        wordIndex is! int ||
        lessonItem is! int ||
        letterIndex is! int ||
        nextIndex is! int) {
      return null;
    }
    return PausedWordAssessment(
      assessmentSubmissionId: id,
      stageId: stage,
      language: language,
      wordIndex: wordIndex,
      word: word,
      cumulative: data['cumulative'] == true,
      lessonItem: lessonItem,
      letter: letter,
      letterLessonIndex: letterIndex,
      nextWordIndex: nextIndex,
      remediationAttempts: data['remediation_attempts'] is int
          ? (data['remediation_attempts'] as int).clamp(0, 100000)
          : 0,
    );
  }
}
