import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/learning/adaptive_decision_controller.dart';
import 'package:resonant_braille/learning/adaptive_recommendation_status.dart';

void main() {
  final decision = AdaptiveDecision(
    decisionId: '77777777-7777-4777-8777-777777777777',
    assessmentSubmissionId: '88888888-8888-4888-8888-888888888888',
    assessmentKey: 'en-letter-a-v1',
    languageCode: 'en',
    lessonId: 'letter-a',
    skillId: 'english-letter-a',
    action: AdaptiveDecisionAction.reassess,
    recommendedLessonId: 'letter-a',
    reason: 'Recent verified work calls for one supported reassessment.',
    evidence: {
      'model_status': 'qualified_prediction_used',
      'probability_incorrect': 0.73,
    },
    confidence: 0.7,
    expectedLearningObjective: 'Recognize letter a.',
    source: AdaptiveDecisionSource.mlAssistedBackend,
    status: AdaptiveDecisionStatus.pending,
    remediationCycle: 1,
    createdAt: DateTime.utc(2026, 11, 22),
  );

  testWidgets(
    'adaptive recommendation and validated choices are screen-reader accessible',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdaptiveRecommendationStatus(
                  key: const ValueKey('adaptive-recommendation-status'),
                  decision: decision,
                ),
                AccessibleLessonQuestion(
                  prompt: 'Choose the English letter represented by dot 1.',
                  options: const ['b', 'a', 'c'],
                  selectedOption: selected,
                  enabled: true,
                  onSelected: (value) => selected = value,
                ),
              ],
            ),
          ),
        ),
      );

      final status = tester.getSemantics(
        find.byKey(const ValueKey('adaptive-recommendation-status')),
      );
      expect(status.label, contains('Recommended activity'));
      expect(
        status.label,
        contains('qualified Resonant learner-history model'),
      );
      expect(status.label, isNot(contains('0.73')));
      final prompt = tester.getSemantics(
        find.byKey(const ValueKey('lesson-question-prompt')),
      );
      expect(prompt.label, 'Choose the English letter represented by dot 1.');
      expect(find.byType(OutlinedButton), findsNothing);
      final answer = find.byKey(const ValueKey('lesson-answer-a'));
      expect(answer, findsOneWidget);
      expect(
        tester
            .getSemantics(answer)
            .getSemanticsData()
            .hasFlag(SemanticsFlag.isButton),
        isFalse,
      );
      await tester.tap(answer);
      expect(selected, 'a');
      semanticsHandle.dispose();
    },
  );
}
