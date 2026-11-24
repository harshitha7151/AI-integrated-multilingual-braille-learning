/// Minimal, non-sensitive snapshot of the learner-facing screen state.
///
/// It is assembled from Flutter state, never inferred from a screenshot or an
/// LLM. Keep answer keys, account data, credentials, and unrelated app data out.
class TutorScreenContext {
  const TutorScreenContext({
    required this.screenName,
    required this.language,
    this.module,
    this.lesson,
    this.exerciseNumber,
    this.exerciseCount,
    this.instruction,
    this.question,
    this.options = const [],
    this.selectedAnswer,
    this.answerSubmitted = false,
    this.feedback,
    this.availableActions = const [],
    this.availableIntentActions = const [],
    this.contextMetadata = const {},
    this.visibleBrailleDescription,
    this.accessibilityInstruction,
    this.completedItems,
  });

  final String screenName;
  final String language;
  final String? module;
  final String? lesson;
  final int? exerciseNumber;
  final int? exerciseCount;
  final String? instruction;
  final String? question;
  final List<String> options;
  final String? selectedAnswer;
  final bool answerSubmitted;
  final String? feedback;
  final List<String> availableActions;

  /// Validated action identifiers the active screen can currently support.
  final List<String> availableIntentActions;

  /// Small, non-sensitive state such as navigation indexes and prerequisites.
  final Map<String, Object?> contextMetadata;
  final String? visibleBrailleDescription;
  final String? accessibilityInstruction;
  final int? completedItems;

  String get position => exerciseNumber == null || exerciseCount == null
      ? ''
      : 'Exercise $exerciseNumber of $exerciseCount.';

  String readScreen() => [
    screenName,
    if (module != null) module!,
    if (lesson != null) lesson!,
    position,
    if (instruction != null) instruction!,
    if (question != null) 'Question: $question',
    if (options.isNotEmpty) readOptions(),
    if (selectedAnswer != null) 'Selected answer: $selectedAnswer.',
    if (answerSubmitted) 'The answer has been checked.',
    if (feedback != null) 'Feedback: $feedback',
    if (visibleBrailleDescription != null) visibleBrailleDescription!,
    if (accessibilityInstruction != null) accessibilityInstruction!,
  ].where((part) => part.trim().isNotEmpty).join(' ');

  String readQuestion() => question == null || question!.trim().isEmpty
      ? 'There is no question on this screen.'
      : question!;

  String readOptions() => options.isEmpty
      ? 'There are no answer choices on this screen.'
      : 'The choices are ${options.asMap().entries.map((entry) => 'Option ${String.fromCharCode(65 + entry.key)}: ${entry.value}').join('. ')}.';

  String readInstructions() =>
      instruction ??
      question ??
      accessibilityInstruction ??
      'There are no additional instructions on this screen.';

  String readFeedback() =>
      feedback ?? 'There is no feedback on this screen yet.';

  String exerciseStatus() => exerciseNumber == null || exerciseCount == null
      ? 'You are on $screenName.'
      : 'You are on $lesson, $position';

  /// Compact context for the existing Tutor API field. Only the active screen
  /// is included; deterministic commands still execute locally in Flutter.
  String toTutorContext() {
    final relevant = [
      'Active screen: $screenName.',
      'Selected language: $language.',
      if (module != null) 'Module: $module.',
      if (lesson != null) 'Lesson: $lesson.',
      if (position.isNotEmpty) position,
      if (instruction != null) 'Instruction: $instruction',
      if (question != null) 'Current question: $question',
      if (options.isNotEmpty) readOptions(),
      if (selectedAnswer != null) 'Selected answer: $selectedAnswer.',
      if (answerSubmitted) 'Answer submitted: yes.',
      if (feedback != null) 'Current feedback: $feedback',
      if (visibleBrailleDescription != null) visibleBrailleDescription!,
      if (accessibilityInstruction != null) accessibilityInstruction!,
    ].join(' ');
    final supplemental = [
      if (availableActions.isNotEmpty)
        'Available actions: ${availableActions.join(', ')}.',
      if (completedItems != null) 'Completed learning items: $completedItems.',
    ].join(' ');
    final combined = supplemental.isEmpty
        ? relevant
        : '$relevant $supplemental';
    if (combined.length <= 600) return combined;
    if (relevant.length >= 600) {
      return '${relevant.runes.take(597).map(String.fromCharCode).join()}...';
    }
    final room = 600 - relevant.length - 1;
    return room <= 3
        ? relevant
        : '$relevant ${supplemental.runes.take(room - 3).map(String.fromCharCode).join()}...';
  }

  Map<String, Object?> toIntentContext() => {
    'screen': screenName,
    'language': language,
    if (module != null) 'module': module,
    if (lesson != null) 'lesson': lesson,
    if (exerciseNumber != null) 'exercise_number': exerciseNumber,
    if (exerciseCount != null) 'exercise_count': exerciseCount,
    if (instruction != null) 'instruction': instruction,
    if (question != null) 'question': question,
    if (options.isNotEmpty) 'options': options,
    if (selectedAnswer != null) 'selected_answer': selectedAnswer,
    'answer_submitted': answerSubmitted,
    if (feedback != null) 'feedback': feedback,
    'available_actions': availableIntentActions,
    if (completedItems != null) 'completed_items': completedItems,
    if (visibleBrailleDescription != null)
      'braille_state': visibleBrailleDescription,
    if (accessibilityInstruction != null)
      'accessibility_instruction': accessibilityInstruction,
    if (contextMetadata.isNotEmpty) 'state': contextMetadata,
  };
}

typedef TutorScreenContextProvider = TutorScreenContext Function();
