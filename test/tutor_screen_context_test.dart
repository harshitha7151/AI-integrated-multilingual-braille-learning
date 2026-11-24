import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/tutor/tutor_screen_context.dart';

void main() {
  test(
    'screen reader text uses only the active structured screen snapshot',
    () {
      const context = TutorScreenContext(
        screenName: 'Lessons',
        language: 'Kannada',
        module: 'Kannada vowels',
        lesson: 'ಕ',
        exerciseNumber: 2,
        exerciseCount: 14,
        instruction: 'Choose the matching Braille pattern.',
        question: 'Which cell represents ಕ?',
        options: ['dots 1 and 2', 'dots 1, 3 and 5'],
        selectedAnswer: 'dots 1 and 2',
        answerSubmitted: true,
        feedback: 'Try again.',
        availableActions: ['read options', 'select an option'],
        visibleBrailleDescription: 'The selected cell has dots 1 and 2.',
        accessibilityInstruction: 'Swipe to check your answer.',
        completedItems: 1,
      );

      final spoken = context.readScreen();
      expect(spoken, contains('Kannada'));
      expect(spoken, contains('Exercise 2 of 14'));
      expect(spoken, contains('Which cell represents ಕ?'));
      expect(spoken, contains('Option B: dots 1, 3 and 5'));
      expect(spoken, contains('Feedback: Try again.'));
      expect(spoken, isNot(contains('password')));
    },
  );

  test('screen-reading requests safely describe unavailable content', () {
    const context = TutorScreenContext(
      screenName: 'Dashboard',
      language: 'English',
    );

    expect(context.readQuestion(), 'There is no question on this screen.');
    expect(
      context.readOptions(),
      'There are no answer choices on this screen.',
    );
    expect(context.readFeedback(), 'There is no feedback on this screen yet.');
  });

  test('backend tutor context stays within the current API field limit', () {
    final context = TutorScreenContext(
      screenName: 'Lessons',
      language: 'Hindi',
      question: 'à¤•' * 500,
      options: ['option' * 100, 'choice' * 100],
      availableActions: const ['read options', 'select option'],
    );

    expect(context.toTutorContext().length, lessThanOrEqualTo(600));
  });

  test('provider returns fresh screen context after navigation', () {
    var screen = 'Lesson 1';
    TutorScreenContext provider() =>
        TutorScreenContext(screenName: screen, language: 'English');

    expect(provider().readScreen(), contains('Lesson 1'));
    screen = 'Lesson 2';
    expect(provider().readScreen(), contains('Lesson 2'));
  });

  test(
    'intent snapshot supplies structured context and screen capabilities only',
    () {
      const context = TutorScreenContext(
        screenName: 'Assessment',
        language: 'Kannada',
        module: 'Kannada letters',
        question: 'Choose the matching cell.',
        options: ['Option one', 'Option two'],
        selectedAnswer: 'Option one',
        answerSubmitted: false,
        availableIntentActions: [
          'ask_tutor',
          'select_answer',
          'exit_assessment',
        ],
        completedItems: 4,
        contextMetadata: {
          'assessment_active': true,
          'destinations': ['letters', 'words'],
        },
      );

      final snapshot = context.toIntentContext();
      expect(snapshot['screen'], 'Assessment');
      expect(snapshot['language'], 'Kannada');
      expect(snapshot['options'], ['Option one', 'Option two']);
      expect(snapshot['available_actions'], contains('select_answer'));
      expect((snapshot['state'] as Map)['assessment_active'], isTrue);
      expect(snapshot.keys, isNot(contains('learner_id')));
    },
  );
}
